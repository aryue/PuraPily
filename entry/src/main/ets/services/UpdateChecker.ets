/**
 * UpdateChecker.ets — GitHub Release 更新检测
 *
 * 数据源: GET https://api.github.com/repos/<owner>/<repo>/releases/latest
 * （免鉴权，匿名限额 60 次/小时/IP，单用户足够；仍做 12h 静默节流）
 *
 * 约定：
 * - 手动检查 force=true 永远实发请求；启动静默检查 force=false 在 12h 窗口内直接读缓存
 * - 版本比较用数值化语义比较（2.0.10 > 2.0.9），不比 versionCode（tag 里无约定）
 * - 结果缓存到 preferences（my_app_settings）；发现新版本时置 AppStorage('hasNewVersion')
 *   供「我的」页关于入口红点，进入 AboutPage 后由页面清除
 * - 前往下载只跳浏览器打开 Release 页，不做应用内下载安装
 * - 低频普通请求，不走 NetworkGate / 预热预算体系
 */
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'UpdateChecker';

/** 仓库配置收口：换仓库只改这里。 */
export const GITHUB_OWNER: string = 'aryue';
export const GITHUB_REPO: string = 'PuraPily';
export const GITHUB_PROJECT_URL: string = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}`;
export const GITHUB_RELEASE_PAGE_URL: string = `${GITHUB_PROJECT_URL}/releases/latest`;

const API_URL: string = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;

const PREF_NAME: string = 'my_app_settings';
const KEY_LAST_CHECK: string = 'updateLastCheckTime';
const KEY_LATEST_VERSION: string = 'updateLatestVersion';
const KEY_RELEASE_NOTES: string = 'updateReleaseNotes';
const KEY_RELEASE_URL: string = 'updateReleaseUrl';

/** 静默检查节流窗口：12 小时。 */
const SILENT_CHECK_INTERVAL_MS: number = 12 * 60 * 60 * 1000;
/** Release Notes 缓存上限，避免极端长文撑爆偏好文件。 */
const MAX_NOTES_LEN: number = 1500;
const HTTP_TIMEOUT_MS: number = 10000;

export enum UpdateCheckStatus {
  UP_TO_DATE = 0,
  UPDATE_AVAILABLE = 1,
  ERROR = 2
}

export interface UpdateCheckResult {
  status: UpdateCheckStatus;
  currentVersion: string;
  latestVersion: string;
  releaseNotes: string;
  releaseUrl: string;
  errorMessage: string;
}

interface GitHubRelease {
  tag_name?: string;
  name?: string;
  body?: string;
  html_url?: string;
}

let cachedCurrentVersion: string = '';

/** 当前版本名（读打包后的 app.json5 versionName，进程内缓存）。 */
export async function getCurrentVersionName(): Promise<string> {
  if (cachedCurrentVersion.length > 0) {
    return cachedCurrentVersion;
  }
  const bundleInfo = await bundleManager.getBundleInfoForSelf(
    bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
  cachedCurrentVersion = bundleInfo.versionName ?? '';
  return cachedCurrentVersion;
}

/** 剥掉 tag 常见的 v/V 前缀。 */
function normalizeVersion(v: string): string {
  return v.trim().replace(/^v/i, '');
}

/** 数值化语义比较：返回 >0 表示 a 更新，<0 表示 b 更新，0 相等。 */
export function compareVersions(a: string, b: string): number {
  const pa: string[] = normalizeVersion(a).split('.');
  const pb: string[] = normalizeVersion(b).split('.');
  const len: number = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const na: number = i < pa.length ? (parseInt(pa[i], 10) || 0) : 0;
    const nb: number = i < pb.length ? (parseInt(pb[i], 10) || 0) : 0;
    if (na !== nb) {
      return na > nb ? 1 : -1;
    }
  }
  return 0;
}

function buildResult(currentVersion: string, latestVersion: string, notes: string,
  url: string): UpdateCheckResult {
  const hasNewer: boolean = latestVersion.length > 0 && compareVersions(latestVersion, currentVersion) > 0;
  const result: UpdateCheckResult = {
    status: hasNewer ? UpdateCheckStatus.UPDATE_AVAILABLE : UpdateCheckStatus.UP_TO_DATE,
    currentVersion: currentVersion,
    latestVersion: latestVersion,
    releaseNotes: notes,
    releaseUrl: url,
    errorMessage: ''
  };
  return result;
}

function applyAppStorage(result: UpdateCheckResult): void {
  AppStorage.setOrCreate('hasNewVersion', result.status === UpdateCheckStatus.UPDATE_AVAILABLE);
}

async function fetchLatestRelease(): Promise<GitHubRelease> {
  const httpRequest = http.createHttp();
  try {
    const response = await httpRequest.request(API_URL, {
      method: http.RequestMethod.GET,
      header: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'PuraPily-UpdateChecker'
      },
      connectTimeout: HTTP_TIMEOUT_MS,
      readTimeout: HTTP_TIMEOUT_MS
    });
    if (response.responseCode !== 200) {
      throw new Error(`GitHub API HTTP ${response.responseCode}`);
    }
    return JSON.parse(response.result as string) as GitHubRelease;
  } finally {
    httpRequest.destroy();
  }
}

/**
 * 更新检查入口。
 * @param force true=手动检查（永远实发请求）；false=启动静默检查（12h 节流，窗口内读缓存）
 */
export async function checkForUpdate(context: common.Context, force: boolean): Promise<UpdateCheckResult> {
  const currentVersion = await getCurrentVersionName();
  try {
    const pref = await preferences.getPreferences(context, PREF_NAME);
    if (!force) {
      const lastCheck = await pref.get(KEY_LAST_CHECK, 0) as number;
      const cachedVersion = await pref.get(KEY_LATEST_VERSION, '') as string;
      if (cachedVersion.length > 0 && lastCheck > 0 && Date.now() - lastCheck < SILENT_CHECK_INTERVAL_MS) {
        const notes = await pref.get(KEY_RELEASE_NOTES, '') as string;
        const url = await pref.get(KEY_RELEASE_URL, GITHUB_RELEASE_PAGE_URL) as string;
        const result = buildResult(currentVersion, cachedVersion, notes, url);
        applyAppStorage(result);
        hilog.info(DOMAIN, TAG, 'silent check served from cache: latest=%{public}s', cachedVersion);
        return result;
      }
      // 无缓存（首次安装后首次启动）时静默检查也照常发一次请求。
    }

    const release = await fetchLatestRelease();
    const latestVersion = normalizeVersion(release.tag_name ?? '');
    if (latestVersion.length === 0) {
      throw new Error('release tag_name 缺失');
    }
    const notes: string = (release.body ?? '').slice(0, MAX_NOTES_LEN);
    const url: string = (release.html_url !== undefined && release.html_url.length > 0)
      ? release.html_url : GITHUB_RELEASE_PAGE_URL;

    await pref.put(KEY_LAST_CHECK, Date.now());
    await pref.put(KEY_LATEST_VERSION, latestVersion);
    await pref.put(KEY_RELEASE_NOTES, notes);
    await pref.put(KEY_RELEASE_URL, url);
    await pref.flush();

    const result = buildResult(currentVersion, latestVersion, notes, url);
    applyAppStorage(result);
    hilog.info(DOMAIN, TAG, 'check done: current=%{public}s latest=%{public}s hasNewer=%{public}s',
      currentVersion, latestVersion, String(result.status === UpdateCheckStatus.UPDATE_AVAILABLE));
    return result;
  } catch (err) {
    const message: string = (err as BusinessError).message ?? 'unknown error';
    hilog.warn(DOMAIN, TAG, 'update check failed: %{public}s', message);
    const failed: UpdateCheckResult = {
      status: UpdateCheckStatus.ERROR,
      currentVersion: currentVersion,
      latestVersion: '',
      releaseNotes: '',
      releaseUrl: GITHUB_RELEASE_PAGE_URL,
      errorMessage: message
    };
    // 失败不动缓存与红点：下次启动/手动检查再试。
    return failed;
  }
}
