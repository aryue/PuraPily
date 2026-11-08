import { NetworkGate } from '../utils/NetworkGate';
import native from 'libpurapily_ijk.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { PlayUrlResult } from '../api/BilibiliApi';
import { selectDashVideo } from '../utils/DashQuality';

/** Finite prefixes shared with playback; no rolling 30-second aggregate quota. */
export class IjkPrewarm {
  /**
   * @param resumeSec 续播起点（秒）。>0 时原生侧会解析 m4s 的 sidx，把前缀从
   *   「固定 0~512KiB」改成「0 处索引 + 该时间点所在分片」，跳过中间几十 MB。
   */
  static warm(result: PlayUrlResult | null | undefined, resumeSec: number = 0): boolean {
    if (!NetworkGate.allowsBoundedPrefix() || AppStorage.get<boolean>('playbackPrewarmOff') === true) return false;
    if (AppStorage.get<string>('playbackKernel') !== 'ijk' || !result?.dash) return false;
    if (result.actualQn === 125 || result.actualQn === 126) return false;
    const dash = result.dash;
    const video = selectDashVideo(dash.videoStreams, dash.quality);
    const audio = dash.audioStreams[0];
    if (!video?.baseUrl || !audio?.baseUrl || (video.codecid !== 7 && video.codecid !== 12)) return false;
    const agent = result.mediaUserAgent || 'Mozilla/5.0';
    const referer = result.mediaReferer ?? 'https://www.bilibili.com/';
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const forced = AppStorage.get<number>('prewarmSeekMs') ?? 0;
    const seekMs = forced > 0 ? forced : (resumeSec > 0 ? Math.round(resumeSec * 1000) : 0);
    try {
      const v = native.prewarmUrl(video.baseUrl, agent, referer, cookie, 512 * 1024, seekMs);
      const a = native.prewarmUrl(audio.baseUrl, agent, referer, cookie, 64 * 1024, seekMs);
      return v > 0 || a > 0;
    } catch (e) {
      hilog.warn(0, 'Prefix', 'prepare failed %{public}s', (e as Error).message);
      return false;
    }
  }

  /** Compatibility call: the same bounded job is deduplicated natively. */
  static prefetchFirstRender(result: PlayUrlResult | null | undefined, resumeSec: number = 0): void {
    IjkPrewarm.warm(result, resumeSec);
  }
}
