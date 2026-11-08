/**
 * EntryAbility.ets
 * 主 Ability — 按官方 MusicCard 模式重写
 *
 * 新增功能：
 * 1. callee.on('playByAction') — 接收卡片播放/暂停控制命令
 * 2. callee.on('requestUpdatePlayCard') — 接收卡片数据拉取请求
 * 3. 播放状态变化时 → FormUtils.updatePlayControlCards() 批量推送
 * 4. AppStorage 共享播放状态（供卡片 call 响应时读取）
 */
import { AbilityConstant, UIAbility, Want, wantConstant, Configuration } from '@kit.AbilityKit';
import { AppContinuation, ContinuationSnapshot, CONTINUATION_KEY, CONTINUATION_MIN_VERSION } from '../services/AppContinuation';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, router, uiObserver } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { rpc } from '@kit.IPCKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import FormUtils from '../utils/FormUtils';
import { PlayerService } from '../services/PlayerService';
import { FloatingPiP } from '../services/FloatingPiP';
import { AppScaleService } from '../services/AppScaleService';
import { HighRefreshService } from '../services/HighRefreshService';
import { errMsg, setVerboseLog } from '../utils/Logger';
import { redactPrivateLog } from '../utils/PrivacyLog';
import { syncThemeConfiguration } from '../utils/ReferenceAppearance';
import { initializeLoginCredentials } from '../utils/CredentialStore';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { BiliLinkParser, BiliLinkResult } from '../utils/BiliLinkParser';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private pendingUri: string | null = null;
  private pendingIjkLab: boolean = false;
  private pendingSurfaceLab: string = '';
  private pendingContinuation: ContinuationSnapshot | null = null;
  /** --ps cellularPrefetch 只覆盖本次启动，不写偏好文件；设置页里的开关才是持久值。 */
  private cellularPrefetchLaunchOverride: boolean | null = null;
  private continuationPage: string = '';
  private continuationObserverRegistered: boolean = false;
  private continuationPageChanged: (info: uiObserver.RouterPageInfo) => void = (info: uiObserver.RouterPageInfo): void => {
    const path = AppContinuation.normalizePage(info.path.endsWith('/') ? info.path + info.name : info.path);
    if (info.state === uiObserver.RouterPageState.ON_PAGE_SHOW) {
      this.continuationPage = path;
      this.setContinuationAvailable(AppContinuation.isPlaybackPage(path) && !AppStorage.get<boolean>('floatingPiPActive'));
    } else if (info.state === uiObserver.RouterPageState.ON_PAGE_HIDE && this.continuationPage === path) {
      this.continuationPage = '';
      this.setContinuationAvailable(false);
    }
  };

  private setContinuationAvailable(available: boolean): void {
    hilog.info(DOMAIN, TAG, 'Continuation available=%{public}s page=%{public}s', String(available), this.continuationPage);
    try {
      this.context.setMissionContinueState(available ? AbilityConstant.ContinueState.ACTIVE : AbilityConstant.ContinueState.INACTIVE)
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'setMissionContinueState failed: %{public}s', errMsg(error));
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'setMissionContinueState failed: %{public}s', errMsg(error));
    }
  }

  // ==================== Callee 处理器 ====================

  /** 播放控制（卡片发来的播放/暂停命令） */
  private playByActionCall(data: rpc.MessageSequence): MyParcelable {
    try {
      const params: Record<string, string> = JSON.parse(data.readString());
      const playActionType = params['playActionType'] as string;
      const formId = params['formId'] as string;
      const ps = PlayerService.getInstance();

      if (playActionType === '0') {
        // 暂停
        if (ps.hasActivePlayer) {
          ps.pause();
        }
      } else if (playActionType === '1') {
        // 播放
        if (ps.hasActivePlayer) {
          ps.play();
        }
      }
      // 更新后推送状态到该卡片
      if (formId) {
        FormUtils.updateSingleCard(this.context, formId);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'playByActionCall error: %{public}s', JSON.stringify(e));
    }
    return new MyParcelable(0);
  }

  /** 卡片请求数据更新（卡片首次加载或刷新时触发） */
  private requestUpdatePlayCard(data: rpc.MessageSequence): MyParcelable {
    try {
      const params: Record<string, string> = JSON.parse(data.readString());
      const formId = params['formId'] as string;
      if (formId) {
        FormUtils.updateSingleCard(this.context, formId);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'requestUpdatePlayCard error: %{public}s', JSON.stringify(e));
    }
    return new MyParcelable(0);
  }

  // ==================== 生命周期 ====================

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    // 联调日志开关：只有显式 `--ps verboseLog on` 才把 logInfo 放出来。
    if (want.parameters?.['verboseLog'] !== undefined) {
      setVerboseLog(String(want.parameters['verboseLog']) === 'on');
    }
    AppStorage.setOrCreate('appContext', this.context);
    initializeLoginCredentials(this.context).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Startup credential restore failed: %{public}s', errMsg(error));
    });
    PlayerService.setAppContext(this.context);
    HighRefreshService.getInstance().initialize(this.context);
    // 必须在 loadCardSettings() 之前解析：恢复持久化开关是异步的，否则会反过来覆盖本次启动的命令行值。
    if (want.parameters?.['cellularPrefetch'] !== undefined) {
      this.cellularPrefetchLaunchOverride = String(want.parameters['cellularPrefetch']) !== 'off';
    }
    this.loadCardSettings();
    this.registerCalleeHandlers();
    PersistentStorage.persistProp('statusBarHeight', 40);
    this.setContinuationAvailable(false);
    uiObserver.on('routerPageUpdate', this.context, this.continuationPageChanged);
    this.continuationObserverRegistered = true;

    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.receiveContinuation(want);
      return;
    }

    if (want.uri && want.uri.length > 0) {
      this.pendingUri = want.uri;
      hilog.info(DOMAIN, TAG, 'onCreate received deep link: %{public}s', redactPrivateLog(want.uri));
    }
    if (want.parameters?.['surfaceLab'] !== undefined) {
      this.pendingSurfaceLab = String(want.parameters['surfaceLab']);
    }
    if (want.parameters?.['ijkLab'] !== undefined) {
      this.pendingIjkLab = true;
    }
    // 联调开关：aa start --ps prewarmSeek 30000 强制按该时间点预热，用于验证 sidx 段选择。
    if (want.parameters?.['prewarmSeek'] !== undefined) {
      const ms = Math.max(0, Math.round(Number(String(want.parameters['prewarmSeek'])) || 0));
      AppStorage.setOrCreate('prewarmSeekMs', ms);
    }
    // 联调开关：--ps feedStillHold 5000 让静帧→surface 的硬切前后各停 5s，
    // 便于逐帧截图对比两边的几何（默认 0，正常流程不受影响）。
    if (want.parameters?.['feedStillHold'] !== undefined) {
      const ms = Math.max(0, Math.round(Number(String(want.parameters['feedStillHold'])) || 0));
      AppStorage.setOrCreate('feedStillHoldMs', ms);
    }
    // 联调开关：aa start --ps noPrewarm true 可在不重新打包的情况下关掉连接预热。
    if (want.parameters?.['noPrewarm'] !== undefined) {
      AppStorage.setOrCreate('playbackPrewarmOff', String(want.parameters['noPrewarm']) === 'true');
    }
    // IJK 实例池开关：--ps ijkWarm off 关闭做 A/B。
    if (want.parameters?.['ijkWarm'] !== undefined) {
      // on = 强制开启，off = 强制关闭，不带参数时走默认（IJK 内核 + 非计费网络）。
      AppStorage.setOrCreate('ijkWarmPool', String(want.parameters['ijkWarm']) === 'on');
    }
    // 实例池槽数：--ps ijkWarmSlots 2 一次预热两张卡，用于对比命中率与内存代价。
    if (want.parameters?.['ijkWarmSlots'] !== undefined) {
      const slots = Number(String(want.parameters['ijkWarmSlots'])) || 1;
      AppStorage.setOrCreate('ijkWarmSlots', Math.max(1, Math.min(3, Math.round(slots))));
    }
    // 稀疏分段缓存默认开启；--ps diskCache off 可一键关闭做 A/B。
    if (want.parameters?.['diskCache'] !== undefined) {
      AppStorage.setOrCreate('playbackDiskCache', String(want.parameters['diskCache']) !== 'off');
    }
    // 点击瞬间首帧区间任务（官方 addTask 形态）默认关闭：实测赶不上首帧；
    // --ps headPrefetch on 开启做对照，待连接池补齐后再转正。
    if (want.parameters?.['headPrefetch'] !== undefined) {
      AppStorage.setOrCreate('headPrefetch', String(want.parameters['headPrefetch']) === 'on');
    }
    // 邻片预热对照开关：--ps neighborWarm on|off
    // 联调开关：--ps neighborWarm on 开启邻片预热原为省流量默认关闭；
    // 现在 Wi-Fi 默认恢复，on/off 只用于强制。
    if (want.parameters?.['neighborWarm'] !== undefined) {
      AppStorage.setOrCreate('playbackNeighborWarm', String(want.parameters['neighborWarm']) === 'on');
    }
    // 联调开关：--ps feedMode true 直接以连刷布局打开播放页（横屏视频也可复现切换流程）。
    if (want.parameters?.['feedMode'] !== undefined) {
      AppStorage.setOrCreate('forceFeedMode', String(want.parameters['feedMode']) === 'true');
    }
    // 蜂窝预热门控：设置页开关为持久值，--ps cellularPrefetch on|off 仅本次启动覆盖，
    // 二者在 loadCardSettings() 中合并后写入 AppStorage；只影响 NetworkGate 判定，不改字节预算。
  }

  /** 仅用于实验页：surface 改绑测量（不影响正式播放链路）。 */
  private openSurfaceLab(bvid: string): void {
    try {
      this.context.windowStage.getMainWindowSync().getUIContext().getRouter()
        .pushUrl({ url: 'pages/SurfaceRebindLab', params: { bvid: bvid } })
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'surface lab navigation failed: %{public}s', errMsg(error));
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'surface lab navigation threw: %{public}s', errMsg(error));
    }
  }


  /** 注册 callee 处理器（匹配 ActionUtils 中的 CallMethod） */
  private registerCalleeHandlers(): void {
    try {
      this.callee.on('playByAction', (data: rpc.MessageSequence): MyParcelable => {
        return this.playByActionCall(data);
      });
      this.callee.on('requestUpdatePlayCard', (data: rpc.MessageSequence): MyParcelable => {
        return this.requestUpdatePlayCard(data);
      });
      hilog.info(DOMAIN, TAG, 'callee handlers registered');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'register callee failed: %{public}s', JSON.stringify(e));
    }
  }

  onDestroy(): void {
    if (this.continuationObserverRegistered) {
      uiObserver.off('routerPageUpdate', this.context, this.continuationPageChanged);
      this.continuationObserverRegistered = false;
    }
    HighRefreshService.getInstance().destroy();
    // 应用退出前更新卡片为"无播放"状态
    this.updateCardsOnExit();
    try {
      this.callee.off('playByAction');
      this.callee.off('requestUpdatePlayCard');
    } catch (_e) {
      // ignore
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  /** 应用退出时通知所有卡片 */
  private updateCardsOnExit(): void {
    const isPlay = AppStorage.get<boolean>('cardIsPlay') ?? false;
    if (isPlay) {
      FormUtils.updateCardPlayStatus(this.context, false);
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters?.['verboseLog'] !== undefined) {
      setVerboseLog(String(want.parameters['verboseLog']) === 'on');
    }
    // 运行中临时切换蜂窝预热门控（不写偏好文件，设置页的持久值保持不变），方便同一台设备直接 A/B。
    if (want.parameters?.['cellularPrefetch'] !== undefined) {
      AppStorage.setOrCreate('cellularPrefetch', String(want.parameters['cellularPrefetch']) !== 'off');
    }
    if (want.parameters?.['levelBarLab'] === true) {
      this.context.windowStage.getMainWindowSync().getUIContext().getRouter().pushUrl({ url: 'pages/LevelBarLab' });
      return;
    }
    if (want.parameters?.['surfaceLab'] !== undefined) {
      this.openSurfaceLab(String(want.parameters['surfaceLab']));
      return;
    }
    if (want.parameters?.['ijkLab'] !== undefined) {
      this.context.windowStage.getMainWindowSync().getUIContext().getRouter()
        .pushUrl({ url: 'pages/IjkLab' })
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'ijk lab navigation failed: %{public}s', errMsg(error));
        });
      return;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION) {
      this.receiveContinuation(want);
      return;
    }
    if (want.uri && want.uri.length > 0) {
      hilog.info(DOMAIN, TAG, 'onNewWant received deep link: %{public}s', redactPrivateLog(want.uri));
      this.handleDeepLink(want.uri);
    }
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (typeof wantParam['version'] === 'number' && wantParam['version'] < CONTINUATION_MIN_VERSION) {
      this.continuationToast('请先更新目标设备上的应用，再使用接续');
      return AbilityConstant.OnContinueResult.MISMATCH;
    }
    try {
      const uiRouter = this.context.windowStage.getMainWindowSync().getUIContext().getRouter();
      const state = uiRouter.getState();
      const path = state.path.endsWith('/') ? state.path + state.name : state.path;
      if (!AppContinuation.isPlaybackPage(path) || AppStorage.get<boolean>('floatingPiPActive')) {
        this.continuationToast('仅支持在在线播放页使用接续');
        return AbilityConstant.OnContinueResult.REJECT;
      }
      const snapshot = AppContinuation.snapshot(path, uiRouter.getParams() as Record<string, Object> ?? {});
      if (!snapshot) {
        this.continuationToast('当前内容暂不支持接续，请在在线播放页重试');
        return AbilityConstant.OnContinueResult.REJECT;
      }
      wantParam[CONTINUATION_KEY] = JSON.stringify(snapshot);
      wantParam[wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY] = false;
      wantParam[wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY] = true;
      hilog.info(DOMAIN, TAG, 'Continuation prepared: %{public}s', snapshot.destination.page);
      return AbilityConstant.OnContinueResult.AGREE;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Continuation preparation failed: %{public}s', errMsg(error));
      return AbilityConstant.OnContinueResult.REJECT;
    }
  }

  private continuationToast(message: string): void {
    try { this.context.windowStage.getMainWindowSync().getUIContext().getPromptAction().showToast({ message: message }); }
    catch (_error) {}
  }

  private receiveContinuation(want: Want): void {
    this.pendingUri = null;
    this.pendingContinuation = AppContinuation.decode(want.parameters?.[CONTINUATION_KEY]);
    // Invalid/newer payloads land safely at the root, without loading arbitrary routes.
    const snapshot = this.pendingContinuation;
    AppStorage.setOrCreate('continuationMainTab', snapshot?.tab ?? 0);
    AppStorage.setOrCreate('homeChannelIndex', snapshot?.channel ?? 2);
    try {
      this.setContinuationAvailable(false);
      this.context.restoreWindowStage(new LocalStorage());
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'restoreWindowStage failed: %{public}s', errMsg(error));
    }
  }

  onWindowStageRestore(windowStage: window.WindowStage): void {
    // Manual route reconstruction also handles hot continuation; always keep Index underneath.
    this.restoreContinuationWindow(windowStage);
  }

  private async restoreContinuationWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      await FloatingPiP.getInstance().detach();
      PlayerService.getInstance().release();
      this.onWindowStageCreate(windowStage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Continuation window restore failed: %{public}s', errMsg(error));
      this.onWindowStageCreate(windowStage);
    }
  }

  private handleDeepLink(uri: string): void {
    const result = BiliLinkParser.parse(uri);
    if (!result) {
      hilog.info(DOMAIN, TAG, 'deep link not recognized: %{public}s', redactPrivateLog(uri));
      return;
    }

    if (result.page === '__shortlink__') {
      this.resolveShortLink(uri);
      return;
    }

    hilog.info(DOMAIN, TAG, 'deep link navigating to: %{public}s', result.page);
    try {
      router.pushUrl({ url: result.page, params: result.params });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'deep link navigation failed: %{public}s', JSON.stringify(e));
    }
  }

  private async resolveShortLink(url: string): Promise<void> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'Mozilla/5.0' },
        connectTimeout: 5000,
        readTimeout: 5000
      });
      httpRequest.destroy();

      const location = response.header?.['location'] as string ?? '';
      if (location && location.length > 0) {
        hilog.info(DOMAIN, TAG, 'short link resolved');
        this.handleDeepLink(location);
      } else {
        hilog.info(DOMAIN, TAG, 'short link no redirect, responseCode=%{public}d', response.responseCode);
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'short link resolve failed: %{public}s', JSON.stringify(e));
    }
  }


  // ==================== 窗口/UI 配置 ====================

  private async loadCardSettings(): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, 'my_app_settings');
      // 画质必须以偏好文件为准：VideoPlayerPage 是懒加载模块，只在它模块顶层 persistProp 的话，
      // 冷启首页第一次列表预取时 AppStorage 还没有这个键，会回落到 116；
      // 播放页模块加载后才恢复成 120 —— 两边缓存键不同（bvid_cid_qn_kernel），预取全部作废。
      const savedQn = await pref.get('defaultVideoQn', 116) as number;
      const resolvedQn: number = savedQn > 0 ? Math.round(savedQn) : 116;
      PersistentStorage.persistProp('defaultVideoQn', resolvedQn);
      AppStorage.setOrCreate('defaultVideoQn', resolvedQn);
      const kernel = await pref.get('playbackKernel', 'system');
      AppStorage.setOrCreate('playbackKernel', kernel === 'ijk' ? 'ijk' : 'system');
      const landscapeSide = await pref.get('landscapePlaybackSide', 'left');
      AppStorage.setOrCreate('landscapePlaybackSide', landscapeSide === 'right' ? 'right' : 'left');
      const cardMargin = await pref.get('cardMargin', 12) as number;
      AppStorage.setOrCreate('cardMargin', cardMargin);
      const cardBorderRadius = await pref.get('cardBorderRadius', 20) as number;
      AppStorage.setOrCreate('cardBorderRadius', cardBorderRadius);
      const cardListBorderRadius = await pref.get('cardListBorderRadius', 12) as number;
      AppStorage.setOrCreate('cardListBorderRadius', cardListBorderRadius);
      const cardListMargin = await pref.get('cardListMargin', 12) as number;
      AppStorage.setOrCreate('cardListMargin', cardListMargin);
      // ⭐ 加载全局关闭动画开关（避免重启后失效）
      const disableAnimations = await pref.get('da', false) as boolean;
      AppStorage.setOrCreate('da', disableAnimations);
      // ⭐ 加载屏幕旋转锁定（避免重启后视频页回退为自动旋转）
      const orientationLock = await pref.get('screenOrientationLock', '跟随系统') as string;
      AppStorage.setOrCreate('screenOrientationLock', orientationLock);
      // ⭐ 加载震动反馈开关（避免重启后震动失效或无法关闭）
      const vibrateEnabled = await pref.get('vibrateEnabled', true) as boolean;
      AppStorage.setOrCreate('vibrateEnabled', vibrateEnabled);
      // 蜂窝预热取流：设置页开关落盘，重启后必须恢复；--ps 只覆盖本次启动且不写偏好文件。
      const savedCellularPrefetch = await pref.get('cellularPrefetch', false) as boolean;
      const launchOverride = this.cellularPrefetchLaunchOverride;
      const cellularPrefetch = launchOverride === null ? savedCellularPrefetch : launchOverride;
      AppStorage.setOrCreate('cellularPrefetch', cellularPrefetch);
      hilog.info(DOMAIN, TAG, 'cellularPrefetch saved=%{public}s override=%{public}s active=%{public}s',
        String(savedCellularPrefetch), String(launchOverride), String(cellularPrefetch));
      // ⭐ 注册 bgp（后台播放开关）为持久化 AppStorage 属性：重启后仍保留（直播/点播共用）。
      //    必须入口注册，否则直接重启进直播页时 persistProp 未执行，@StorageLink('bgp') 只能拿默认 false
      PersistentStorage.persistProp('bgp', false);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to load card settings: %{public}s', JSON.stringify(e));
    }
  }

  private async setupImmersiveWindow(): Promise<void> {
    try {
      const windowClass = await window.getLastWindow(this.context);
      // ★ 在 loadContent 之前设置全屏布局，避免首帧渲染有 117px 避让区
      await windowClass.setWindowLayoutFullScreen(true);
      const historyStatusBarVisible: boolean = AppStorage.get<boolean>('historyStatusBarVisible') ?? false;
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: historyStatusBarVisible && !(AppStorage.get<boolean>('isDarkMode') ?? false) ? '#000000' : '#FFFFFF',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#FFFFFF',
      };
      await windowClass.setWindowSystemBarProperties(sysBarProps);
      const pref = await preferences.getPreferences(this.context, 'my_app_settings');
      const navInset = windowClass.getUIContext().px2vp(
        windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height);
      if (navInset > 0 && !(AppStorage.get<boolean>('hideNavigationIndicator') ?? false)) {
        AppStorage.setOrCreate('realNavIndicatorHeight', navInset);
      }
      AppStorage.setOrCreate('hideNavigationIndicator', await pref.get('hideNavigationIndicator', false) as boolean);
      StatusBarUtils.updateNavigationInset();
      // ★ 按用户偏好和全屏状态设置状态栏显隐
      const isFullscreen: boolean = AppStorage.get<boolean>('isFullscreen') ?? false;
      const hideStatusBar: boolean = AppStorage.get<boolean>('hideStatusBar') ?? false;
      if (!historyStatusBarVisible && (isFullscreen || hideStatusBar)) {
        await StatusBarUtils.setSystemBars(windowClass, false, true);
        // 隐藏系统栏时保留设备安全高度，避免其他页面恢复时使用 0。
      } else {
        await StatusBarUtils.setSystemBars(windowClass, true, true);
        // 竖屏显示状态栏时恢复高度
        AppStorage.set('statusBarHeight', StatusBarUtils.statusBarInset(windowClass));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to setup immersive: %{public}s', errMsg(err));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    HighRefreshService.getInstance().setMainWindow(windowStage.getMainWindowSync());
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    // ★ 在 loadContent 之前设置全屏模式，避免首帧渲染时状态栏/胶囊闪烁
    // （首帧 statusBarHeight 由 onCreate 中持久化的默认值 40 兜底，不再依赖异步 getWindowAvoidArea）
    this.setupImmersiveWindow();
    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', redactPrivateLog(errMsg(err) ?? ''));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content. Data: %{public}s', JSON.stringify(data) ?? '');
      this.applyOrientationLockFromPrefs();
      AppStorage.setOrCreate('appWindowStage', windowStage);
      this.applyAppScale(windowStage);

      const snapshot = this.pendingContinuation;
      this.pendingContinuation = null;
      if (snapshot && snapshot.destination.page !== 'pages/Index') {
        const uiRouter = windowStage.getMainWindowSync().getUIContext().getRouter();
        uiRouter.pushUrl({ url: snapshot.destination.page, params: snapshot.destination.params }).catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, 'Continuation navigation failed: %{public}s', errMsg(error));
        });
      }

      if (this.pendingUri) {
        const uri = this.pendingUri;
        this.pendingUri = null;
        setTimeout(() => { this.handleDeepLink(uri); }, 500);
      }

      if (this.pendingIjkLab) {
        this.pendingIjkLab = false;
        setTimeout(() => {
          windowStage.getMainWindowSync().getUIContext().getRouter()
            .pushUrl({ url: 'pages/IjkLab' })
            .catch((error: BusinessError) => {
              hilog.error(DOMAIN, TAG, 'ijk lab navigation failed: %{public}s', errMsg(error));
            });
        }, 700);
      }

      if (this.pendingSurfaceLab.length > 0) {
        const labBvid: string = this.pendingSurfaceLab;
        this.pendingSurfaceLab = '';
        setTimeout(() => { this.openSurfaceLab(labBvid); }, 700);
      }
    });
  }

  /** 启动时应用「应用比例调节」的自定义比例（system 模式由 engine 默认跟随，无需调用） */
  private async applyAppScale(windowStage: window.WindowStage): Promise<void> {
    await AppScaleService.applyFromPrefsAtStartup(this.context, windowStage);
  }

  /** 从 Preferences 读取并应用屏幕旋转锁定（冷启动时调用，保证重启后立即生效） */
  private async applyOrientationLockFromPrefs(): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.context, 'my_app_settings');
      const lock = await pref.get('screenOrientationLock', '跟随系统') as string;
      AppStorage.setOrCreate('screenOrientationLock', lock);
      const windowClass = await window.getLastWindow(this.context);
      let orientation: window.Orientation;
      switch (lock) {
        case '跟随系统':
          orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
          break;
        case '锁定竖屏':
          orientation = window.Orientation.PORTRAIT;
          break;
        case '锁定横屏':
          orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
          break;
        default:
          orientation = window.Orientation.AUTO_ROTATION;
          break;
      }
      await windowClass.setPreferredOrientation(orientation);
      hilog.info(DOMAIN, TAG, 'Applied orientation lock: %{public}s', lock);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to apply orientation lock: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageDestroy(): void {
    this.continuationPage = '';
    this.setContinuationAvailable(false);
    HighRefreshService.getInstance().setForeground(false);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    syncThemeConfiguration(newConfig.colorMode);
    StatusBarUtils.updateStatusBarColor(this.context, AppStorage.get<boolean>('isDarkMode') ?? true);
  }

  onForeground(): void {
    HighRefreshService.getInstance().setForeground(true);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    AppStorage.set('appInBackground', false);
    FloatingPiP.getInstance().foreground();
    this.setupImmersiveWindow();
  }

  onBackground(): void {
    HighRefreshService.getInstance().setForeground(false);
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
    AppStorage.set('appInBackground', true);
    // ⭐ 记录切后台那一刻的路由栈顶：播放页据此区分「播放页自己切后台」与
    //    「已跳到 UP 空间等页面后再切后台」，后者不允许恢复后台播放。
    let topPage = '';
    try {
      const uiRouter = this.context.windowStage.getMainWindowSync().getUIContext().getRouter();
      const state = uiRouter.getState();
      topPage = state.path.endsWith('/') ? `${state.path}${state.name}` : state.path;
    } catch (_e) {
      topPage = '';
    }
    AppStorage.set('appBackgroundTopPage', topPage);
    // 小窗在前台点击时已启动；退后台继续沿用同一系统窗口。
    // timestamp 必须最后写：播放页的 @Watch 依赖其余状态已就绪。
    AppStorage.set('appBackgroundTimestamp', Date.now());
  }
}

/** callee 返回类型 */
class MyParcelable implements rpc.Parcelable {
  num: number;

  constructor(num: number) {
    this.num = num;
  }

  marshalling(dataOut: rpc.MessageSequence): boolean {
    dataOut.writeInt(this.num);
    return true;
  }

  unmarshalling(dataIn: rpc.MessageSequence): boolean {
    this.num = dataIn.readInt();
    return true;
  }
}
