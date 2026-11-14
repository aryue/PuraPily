import { SplitPaneLayout } from '../components/SplitPaneLayout';
import { SPLIT_DEFAULT_RATIO, SPLIT_EXPAND_THRESHOLD, clampSplitWidth, splitPrimaryWidth, splitResize,
  splitSecondaryWidth, splitSecondaryX } from '../utils/SplitPaneGeometry';
import { AdjustmentMotion } from '../controlcenter/model/AdjustmentMotion';
import { PlaybackAudioOutputMonitor } from '../utils/PlaybackAudioOutput';
import { PlaybackAudioSession } from '../utils/PlaybackAudioSession';
import { PlayerLevelBar } from '../components/PlayerLevelBar';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { PlaybackMenuIcon } from '../components/PlaybackMenuIcon';
import { PlaybackMenuRow } from '../components/PlaybackMenuRow';
import { NativeGlassCapsule } from '../components/NativeGlassCapsule';
import { CommentMenuSurface } from '../components/CommentMenuSurface';
import { playbackMenuOptions } from '../utils/PlaybackMenuStyle';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PlayerStatusStrip } from '../components/PlayerStatusStrip';
import { VideoListItem } from '../components/VideoListItem';
import { AppContinuation, ContinuationPage } from '../services/AppContinuation';
import { HOME_CHANNEL_CURVE, HOME_CHANNEL_DURATION } from '../utils/HomeChannelMotion';
import { window, display, LengthMetrics } from '@kit.ArkUI';
import { FullscreenDeviceOrientation } from '../utils/FullscreenDeviceOrientation';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { media } from '@kit.MediaKit';
import { getLiveRoomInfo, getLiveStreamUrl, getLiveQualityLabel, invalidateCachedStreamUrl, getRoomPlayInfo, QualityDescription, LiveStreamUrlResult, LiveRoomInfo } from '../api/LiveApi';
import { LiveFeedRoom, fetchLiveRoomsByArea, fetchRecommendedLiveRooms, formatOnlineCount } from '../api/LiveFeedApi';
import { getVideoIntroCard } from '../api/BilibiliApi';
import { LiveViewHelper } from '../services/LiveViewHelper';
import { systemShare } from '@kit.ShareKit';
import { getLiveChatHistory, LiveChatMessage } from '../api/LiveApi';
import { LiveChatReceiver } from '../services/LiveChatReceiver';
import { BusinessError } from '@kit.BasicServicesKit';
import { VibrateUtils } from '../utils/VibrateUtils';

interface QualityOption {
  qn: number;
  label: string;
}

@Entry
@Component
struct LivePlayerPage {
  // ========== 直播状态 ==========
  @State roomId: number = 0;
  @State title: string = '';
  @State online: number = 0;
  @State uname: string = '';
  @State roomCover: string = ''; // 直播间封面（实况窗/通知中心媒体封面）
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State retryCount: number = 0;
  @State currentQn: number = 0;  // 0=未设置，从API获取后选择最高画质
  @State showQualityPicker: boolean = false;

  // ========== Video 组件状态 ==========
  @State videoSrc: string = '';
  @State videoSrcVersion: number = 0;  // 强制重建 Video 用
  private av: media.AVPlayer | null = null; // AVPlayer 播放器（支持后台续播）
  private xc: XComponentController = new XComponentController(); // 视频渲染表面
  private surfaceId_: string = '';
  private spareXc: XComponentController = new XComponentController();
  @State activeSlot: number = 0;
  @State activeFrameReady: boolean = false;
  private previewAV: media.AVPlayer | null = null;
  @State previewRoomId: number = 0;
  @State previewReady: boolean = false;
  @State previewWidth: number = 16;
  @State previewHeight: number = 9;
  private previewInfo: LiveRoomInfo | null = null;
  private previewStream: LiveStreamUrlResult | null = null;
  private previewQualities: QualityOption[] = [];
  private previewGeneration: number = 0;
  private previewRelease: Promise<void> = Promise.resolve();
  private previewTask: Promise<void> = Promise.resolve();
  private userPaused: boolean = false;
  private pageHidden: boolean = false;
  private touchActive: boolean = false;
  @State sourceWidth: number = 16;
  @State sourceHeight: number = 9;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State informationVisible: boolean = true;
  @State informationProgress: number = 0;
  @State liveMenuPanel: string = 'share';
  @State private liveMenuHeight: number = 0;
  @State private liveChoice: string = '';
  @State private liveDropdown: boolean = false;
  private liveShareController: systemShare.ShareController | null = null;
  @State showPlaybackSettings: boolean = false;
  @State portraitScale: string = 'fill';
  @State portraitScaleScope: string = 'standard';
  @State anchorFace: string = '';
  /** 主播粉丝数：用房间 uid 取用户卡片，简介页与普通简介页 ReferenceUpRow 同款 */
  @State anchorFans: number = 0;
  @State roomOffset: number = 0;
  @State roomSlideDirection: number = 1;
  @State roomAnimating: boolean = false;
  private roomIds: number[] = [];
  /** 上下滑切房 / 旧推荐数据源（分页追加时整体重新赋值，保证 @State 触发重绘） */
  @State rooms: LiveFeedRoom[] = [];
  /** 简介 tab 的直播推荐：与竖屏直播页同一套拉数算法（areaId=0 走 fetchRecommendedLiveRooms），
   *  按 roomId 去重、排除当前房间、触底分页追加 */
  @State liveIntroRooms: LiveFeedRoom[] = [];
  private liveIntroPage: number = 1;
  private liveIntroLoading: boolean = false;
  private liveIntroHasMore: boolean = true;
  private liveIntroRoomIds: Set<number> = new Set<number>();
  /** 评论 tab：弹幕列表滚动器与「是否贴底」跟随标记（贴底才自动滚到最新，不打断上滑看历史） */
  private landscapeChatScroller: Scroller = new Scroller();
  @State private chatFollowLatest: boolean = true;
  /** 横屏信息面板：0=简介（主播信息+直播推荐），1=评论（弹幕列表） */
  @State livePanelTab: number = 0;
  /** Swiper 跟手进度（0=简介 1=评论），tab 文字与指示器连续插值，口径同普通页 referenceTabProgress */
  @State livePanelTabProgress: number = 0;
  private livePanelSwiper: SwiperController = new SwiperController();
  private livePanelTabWidths: number[] = [0, 0];
  /** 切 tab 瞬间新挂载的卡片会消费同一次 pointer-up，300ms 内的卡片点击一律忽略 */
  private lastPanelTabChangeAt: number = 0;
  /** 拖动分界柄期间冻结面板内容宽度，避免每帧重排（普通页 referenceLandscapeTabWidth 同款） */
  // 拖动期间不冻结任何 tab：直播页两个 tab 都比普通页评论列表轻，统一用 '100%'
  // 跟随 Swiper 容器重排，切 tab 前后内容宽度完全一致，不会出现比例突变。
  /** 竖屏全屏按钮：请求横屏后，旋转完成再落到横屏全屏态。 */
  private pendingLandscapeFullscreen: boolean = false;
  private fullscreenExitTimer: number = -1;
  private fullscreenDeviceOrientation: FullscreenDeviceOrientation = new FullscreenDeviceOrientation();
  /** 全屏横向锁定：进横屏全屏即锁 AUTO_ROTATION_LANDSCAPE，退出时交还全局旋转设置。
   *  普通页 prepareFullscreenEnvironment / restoreOrientationOnly 同款口径，手机转竖屏不会掉出全屏。 */
  private liveFullscreenLocked: boolean = false;
  private areaId: number = 0;
  private roomPage: number = 0;
  private switchingRoom: boolean = false;
  private disposed: boolean = false;
  private playGeneration: number = 0;
  private lastDx: number = 0;
  private lastDy: number = 0;

  // ========== 动态画质列表（从API获取，只显示此直播间有的画质） ==========
  @State availableQualities: QualityOption[] = [];

  // ========== VideoControls 绑定状态 ==========
  @State isPlaying: boolean = false;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isControlsVisible: boolean = true;
  @State isFullscreen: boolean = true;
  @State isMuted: boolean = false;
  @State playbackRate: number = 1.0;
  @State showGestureHint: boolean = false;
  @State private gestureHintActive: boolean = false;
  @State private outputUsesHeadphones: boolean = false;
  @State private outputHeadphoneIcon: string = 'headphones_fill';
  private audioOutputMonitor: PlaybackAudioOutputMonitor = new PlaybackAudioOutputMonitor((headphones: boolean, icon: string) => {
    this.outputUsesHeadphones = headphones;
    this.outputHeadphoneIcon = icon;
  }, () => this.getUIContext().getHostContext() as common.UIAbilityContext);
  @State gestureHintMainText: string = '';
  @State gestureHintProgress: number = 0;
  @State gestureHintType: string = '';
  @State showBottomHint: boolean = false;
  @State bottomHintImage: ResourceStr | undefined = undefined;
  @State bottomHintText: string = '';
  /** 弹幕历史上限：评论 tab 持续刷新且旧消息不消失，同时避免无界增长 */
  private readonly LIVE_CHAT_LIMIT: number = 200;
  @State @Watch('onLiveChatMessagesChanged') liveChatMessages: LiveChatMessage[] = [];
  @State liveChatStatus: string = '正在加载弹幕…';
  private liveChatTimer: number = -1;
  private liveChatGeneration: number = 0;
  private liveChatConnected: boolean = false;
  private liveChatReceiver: LiveChatReceiver = new LiveChatReceiver((message: LiveChatMessage) => {
    if (this.disposed || this.pageHidden) return;
    this.liveChatMessages = this.liveChatMessages.concat([message]).slice(-this.LIVE_CHAT_LIMIT);
  }, (status: string) => {
    if (this.disposed || this.pageHidden) return;
    this.liveChatConnected = status === '';
    this.liveChatStatus = status;
  });
  @State isBackgroundPlayback: boolean = false;
  // 亮度/音量起始值
  @State sv: number = 1; // start volume (0-1)
  @State sb: number = 1; // start brightness (0-1)
  @State vol: number = 1;
  @State bri: number = 1;
  // 安全区域
  @State safeTop: number = 28;
  @State safeBottom: number = 24;
  // 系统状态栏当前高度（StatusBarUtils 在每次显隐/旋转后回写 AppStorage；分栏内容要让它位）
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('realStatusBarHeight') realStatusBarHeight: number = 0;

  private maxRetries: number = 8;
  private controlsTimer: number = -1;
  private retryTimer: number = -1;
  private screenW: number = 720;
  private screenH_: number = 0;  // 屏幕高度(vp)，用于手势灵敏度
  /** ⭐ 设备媒体音量最大档位（readSystemVolume 时刷新） */
  private maxVol_: number = 15
  /** ⭐ AudioVolumeManager 实例（供 streamVolumeChange 监听/注销） */
  private volMgr_: audio.AudioVolumeManager | null = null
  /** ⭐ 是否已注册系统音量变化监听 */
  private volListening_: boolean = false
  private mw: window.Window | undefined = undefined;  // 主窗口，用于控制系统栏

  // 记录播放开始时间，用于过滤启动时的非致命错误（如 live-stream loop 801）
  private playbackStartMs: number = 0;

  // ========== 屏幕旋转 ==========
  @State rotationMode: string = 'system';  // 'system' | 'auto' | 'portrait' | 'landscape'
  private rotationFreeMode: string = 'system';

  // ========== 卡片样式 ==========
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardStyleLiveQuality') cardStyleLiveQuality: boolean = true;
  @StorageLink('bgp') bgp: boolean = false; // 后台播放开关（与普通播放器共用持久化 key）

  // ========== 横屏播放页（信息层居一侧；播放区方位与普通播放页共用同一设置项） ==========
  @StorageLink('cardBorderRadius') cardBorderRadius: number = 20;
  /** 横屏分栏边距与普通播放页共用同一设置项（普通页 safeCM 读的就是它） */
  @StorageLink('cardMargin') cardMargin: number = 0;
  @StorageProp('landscapePlaybackSide') landscapePlaybackSide: string = 'left';
  /** 横屏分栏比例：播放区占窗口宽度的比例（默认 2/3，与普通播放页一致）。
   *  只属于当前页面实例、不落盘：重新进入分栏界面必然回默认值；单纯横竖屏切换不经过
   *  aboutToAppear，比例自然保留；不同分栏页跳转通过 landscapePlayerRatio 路由参数继承。 */
  @State landscapeRatio: number = SPLIT_DEFAULT_RATIO;
  /** 拖动分界柄时的临时展开量（0..1，1 = 播放区占满窗口） */
  @State landscapeExpand: number = 0;
  /** 横屏全屏：信息面板推出屏幕，播放区占满窗口 */
  @State liveFullscreen: boolean = false;
  private landscapeResizeStart: number = SPLIT_DEFAULT_RATIO;
  /** 横屏信息面板里弹幕区实际可用高度（由布局回填，用于决定显示条数） */
  @State chatSlotHeight: number = 0;

  /** 当前窗口是否为横屏（基于窗口尺寸，非物理屏幕） */
  private isWindowLandscape(): boolean {
    if (this.mw) {
      try {
        const wp = this.mw.getWindowProperties();
        return wp.windowRect.width > wp.windowRect.height;
      } catch (_e) {}
    }
    try {
      const d = display.getDefaultDisplaySync();
      return d.width > d.height;
    } catch (_e) {
      return false;
    }
  }

  // ==================== 横屏分栏几何（对齐普通播放页） ====================

  /** 以实际视口判断横屏布局；首帧视口未量到时退回物理屏幕，避免闪一帧竖屏结构 */
  private landscapeLayout(): boolean {
    return (this.viewportWidth || this.screenWv()) > (this.viewportHeight || this.screenHv());
  }

  /** 横屏（分栏/全屏）进入即纯净观看：控件默认隐藏，单击播放区再唤出；竖屏信息层默认显示。
   *  进页、旋转换向、退出全屏回到分栏都走这一个口径，避免某条路径把控件又冒出来。 */
  private defaultInformationVisible(): boolean {
    return !this.landscapeLayout();
  }

  private landscapeSwapped(): boolean {
    return this.landscapePlaybackSide === 'right';
  }

  /** 分栏边距取普通页 safeCM 的同源设置 cardMargin。参考外观下它为 0，
   *  播放区贴屏幕左/右边缘、详情面板贴右边缘与窗口底边，三者之间零缝隙。 */
  private landscapeInset(): number {
    const v = Number(this.cardMargin);
    return Number.isFinite(v) ? Math.max(0, v) : 0;
  }

  /** 渲染用的连续展开量：拖动跟手、进/退全屏用 animateTo 连续插值（普通页 expandProgress 口径）。
   *  liveFullscreen 只是逻辑标志，不再直接参与几何，否则切全屏会瞬间跳变。 */
  private landscapeExpandAmount(): number {
    return this.landscapeExpand;
  }

  private landscapeLayoutPixel(value: number): number {
    const context = this.getUIContext();
    return context.px2vp(Math.round(context.vp2px(value)));
  }

  private landscapePlayerWidth(): number {
    const cw = this.viewportWidth || this.screenWv();
    return splitPrimaryWidth(cw, this.landscapeRatio || SPLIT_DEFAULT_RATIO, this.landscapeExpandAmount());
  }

  private landscapePlayerX(): number {
    const cw = this.viewportWidth || this.screenWv();
    const inset = this.landscapeInset() * (1 - this.landscapeExpandAmount());
    // 与普通页 referenceLandscapePlayerX 同口径：外侧边距随展开量收起；
    // 播放区在右时向内收（不越出窗口右边界），cardMargin=0 时两侧都是零边距
    return this.landscapeSwapped() ? cw - this.landscapePlayerWidth() - inset : inset;
  }

  /** 顶部让位系统状态栏，逐值照抄普通页 referenceSafeTop()：只取状态栏高度，不掺分栏边距 */
  private landscapeTopInset(): number {
    const real: number = this.realStatusBarHeight || this.statusBarHeight || 40;
    return real;
  }

  private landscapeAreaTop(): number {
    return this.landscapeTopInset() * (1 - this.landscapeExpandAmount());
  }

  /** 面板底部只留与播放区一致的 cardMargin（普通页 safeCM 口径）；为 0 时面板贴窗口底边 */
  private landscapeBottomInset(): number {
    return this.landscapeInset();
  }

  /** 视频区：顶部让状态栏、底部贴窗口底边，不跟着面板留白 */
  private landscapeAreaHeight(): number {
    const ch = this.viewportHeight || this.screenHv();
    return Math.max(1, ch - this.landscapeAreaTop());
  }

  /** 面板 y 固定状态栏下缘、高度固定，展开时只靠 x 整块平移推出（普通页 ReferencePortrait 口径）。
   *  高度只扣顶部状态栏与底部 cardMargin：cardMargin=0 时详情区整块贴到屏幕底边 */
  private landscapePanelTop(): number {
    return this.landscapeTopInset();
  }

  private landscapeViewportWidth(): number {
    return Math.max(1, this.landscapePlayerWidth() -
      2 * this.landscapeInset() * (1 - this.landscapeExpandAmount()));
  }

  /** 画面完整显示在播放区内（横屏不再套用竖屏直播的裁切铺满） */
  private landscapeMediaWidth(srcW: number, srcH: number): number {
    const ar = srcW / Math.max(1, srcH);
    return Math.max(1, Math.min(this.landscapeViewportWidth(), this.landscapeAreaHeight() * ar));
  }

  private landscapeMediaX(srcW: number, srcH: number): number {
    return this.landscapePlayerX() + (this.landscapePlayerWidth() - this.landscapeMediaWidth(srcW, srcH)) / 2;
  }

  private landscapeMediaY(srcW: number, srcH: number): number {
    const height = this.landscapeMediaWidth(srcW, srcH) * srcH / Math.max(1, srcW);
    return this.landscapeAreaTop() + (this.landscapeAreaHeight() - height) / 2;
  }

  /** 容器宽度必须实时跟随分栏比例：拖动时播放区与详情区此消彼长，面板右缘始终贴屏幕边。
   *  冻结容器宽度会让 panelX 跟着播放区走、宽度却不变 ⇒ 右侧露出一条大黑边（普通页不冻结容器）。
   *  进全屏（expand>0）时 ratio 不变，宽度保持 resting，面板靠 x 整块平移推出，与普通页一致。 */
  private landscapePanelWidth(): number {
    const cw = this.viewportWidth || this.screenWv();
    return Math.max(1, this.landscapeLayoutPixel(splitSecondaryWidth(
      cw, this.landscapeRatio || SPLIT_DEFAULT_RATIO, this.landscapeInset())));
  }

  /** 简介卡片可用宽度（面板宽减去 List 左右各 12vp padding），实时跟随分栏比例。
   *  两个 tab 外层都用 '100%' 跟随 Swiper 容器，拖动时不冻结任何一页：普通页因评论
   *  列表很重才冻结非活动 tab，直播页内容轻，同步重排可避免切 tab 时内容宽度突变。 */
  private landscapePanelContentWidth(): number {
    return Math.max(1, this.landscapePanelWidth() - 24);
  }

  private landscapePanelHeight(): number {
    const ch = this.viewportHeight || this.screenHv();
    return Math.max(1, ch - this.landscapePanelTop() - this.landscapeBottomInset());
  }

  /** 展开时整块面板随播放区推出屏幕，而不是靠条件渲染瞬间消失 */
  private landscapePanelX(): number {
    return splitSecondaryX(this.landscapePlayerWidth(), this.landscapePanelWidth(),
      this.landscapeInset(), this.landscapeExpandAmount(), this.landscapeSwapped());
  }

  /**
   * 全屏时信息面板已整块推出屏幕，
   * 浮层菜单不能跟着面板走，仍按「收起态」面板的位置与宽度摆放。
   */
  private landscapeDockPanelX(): number {
    if (!this.liveFullscreen) return this.landscapePanelX();
    const cw = this.viewportWidth || this.screenWv();
    const resting = clampSplitWidth(cw, cw * (this.landscapeRatio || SPLIT_DEFAULT_RATIO));
    return this.landscapeSwapped() ? this.landscapeInset() : resting + this.landscapeInset();
  }

  /** 信息面板配色：与普通页 ReferencePanel / ReferenceIntro 同一套深浅口径 */
  private panelBgColor(): string { return this.isDarkMode ? '#17181A' : '#FFFFFF'; }
  private panelPrimaryColor(): string { return this.isDarkMode ? '#E7E9EB' : '#18191C'; }
  private panelMutedColor(): string { return this.isDarkMode ? '#9A9BA1' : '#757A81'; }
  private panelDividerColor(): string { return this.isDarkMode ? '#24FFFFFF' : '#18000000'; }
  private panelCardColor(): string { return this.isDarkMode ? '#242629' : '#F1F2F3'; }
  private panelChatBubbleColor(): string { return this.isDarkMode ? '#6630323A' : '#12000000'; }
  /** 指示器从「详情」中心滑到「推荐」中心的距离（普通页 referenceTabProgress 同款公式） */
  private panelTabIndicatorTravel(): number {
    const a = this.livePanelTabWidths[0] || 28;
    const b = this.livePanelTabWidths[1] || 28;
    return a / 2 + 20 + b / 2;
  }

  /** 分栏时三点菜单跟随播放区右下（与顶栏「更多」同侧）；全屏沿用收起态面板 dock */
  private landscapeMenuDockWidth(): number {
    if (this.liveFullscreen) return this.landscapePanelWidth();
    return Math.max(1, Math.min(360, this.landscapePlayerWidth() - 2 * this.landscapeInset()));
  }

  private landscapeMenuDockX(): number {
    if (this.liveFullscreen) return this.landscapeDockPanelX();
    return this.landscapePlayerX() + this.landscapePlayerWidth() -
      this.landscapeInset() - this.landscapeMenuDockWidth();
  }

  private landscapeResize(offset: number): void {
    if (!this.landscapeLayout() || this.liveFullscreen) return;
    const cw = this.viewportWidth || this.screenWv();
    if (cw <= 0) return;
    const delta = this.landscapeSwapped() ? -offset : offset;
    const proposed = this.landscapeLayoutPixel(cw * this.landscapeResizeStart + delta);
    const resize = splitResize(cw, proposed);
    this.landscapeRatio = resize.ratio;
    this.landscapeExpand = resize.expand;
  }

  private beginLandscapeResize(): void {
    if (this.liveFullscreen) return;
    const cw = this.viewportWidth || this.screenWv();
    this.landscapeResizeStart = cw > 0 ? this.landscapePlayerWidth() / cw : SPLIT_DEFAULT_RATIO;
    // 不冻结 tab 内容：两页都用 '100%' 跟随容器，随分栏比例同步重排
  }

  private finishLandscapeResize(offset: number, cancel: boolean = false): void {
    const settle = (): void => {
      this.applySystemBars(false);
    };
    if (cancel) {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 200, curve: Curve.EaseOut, onFinish: settle }, () => {
        this.landscapeRatio = this.landscapeResizeStart;
        this.landscapeExpand = 0;
      });
      return;
    }
    this.landscapeResize(offset);
    if (this.landscapeExpand >= SPLIT_EXPAND_THRESHOLD) {
      // 从松手时的真实矩形连续放大到全屏，动画落定后才置逻辑标志（几何等价，无跳变）。
      this.settleInformation(false);
      this.applySystemBars(true);
      this.lockFullscreenLandscape();
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 260, curve: Curve.EaseOut,
        onFinish: () => {
          this.liveFullscreen = true;
          this.landscapeExpand = 1;
          this.landscapeRatio = this.landscapeResizeStart;
        } }, () => {
        this.landscapeExpand = 1;
      });
    } else {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 200, curve: Curve.EaseOut, onFinish: settle }, () => {
        this.landscapeExpand = 0;
      });
    }
  }

  /** 全屏横向锁定（普通页 prepareFullscreenEnvironment 口径）：全屏期间只允许两个横屏方向互换，
   *  手机转到竖屏方向不会退回竖屏页面。三条进全屏的路径都走这里：顶部按钮、拖柄甩入、竖屏请求旋转。 */
  private lockFullscreenLandscape(): void {
    if (this.liveFullscreenLocked || !this.mw) return;
    this.liveFullscreenLocked = true;
    this.fullscreenDeviceOrientation.start();
    try {
      this.mw.enableLandscapeMultiWindow().catch(() => {});
      this.mw.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE).catch(() => {});
    } catch (_e) { logWarn('[LivePlayer] 全屏横向锁定失败'); }
  }

  private async unlockFullscreenLandscape(): Promise<void> {
    if (!this.liveFullscreenLocked) return;
    this.liveFullscreenLocked = false;
    this.fullscreenDeviceOrientation.stop();
    if (!this.mw) return;
    await this.mw.disableLandscapeMultiWindow().catch(() => {});
    if (!this.disposed && !this.liveFullscreenLocked) await this.applyRotationMode();
  }

  private finishFullscreenExit(): void {
    clearTimeout(this.fullscreenExitTimer);
    this.fullscreenExitTimer = -1;
    this.liveFullscreen = false;
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      duration: 260, curve: Curve.EaseOut }, () => {
      this.landscapeExpand = 0;
    });
    this.applySystemBars(false);
  }

  private toggleLandscapeFullscreen(): void {
    if (this.fullscreenExitTimer !== -1) return;
    const enabled = !this.liveFullscreen;
    // 进/退全屏都是同一条连续缩放曲线；liveFullscreen 只作逻辑标志，在动画落定后切换。
    if (enabled) {
      this.lockFullscreenLandscape();
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 260, curve: Curve.EaseOut,
        onFinish: () => { this.liveFullscreen = true; this.landscapeExpand = 1; } }, () => {
        this.landscapeExpand = 1;
      });
    } else {
      const target = this.fullscreenDeviceOrientation.returnLandscape(this.rotationOrientation(), this.landscapeLayout(),
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      if (target) {
        this.finishFullscreenExit();
      } else {
        // 保持全屏画面，等竖屏视口到达。系统未旋转时再收回横屏分栏。
        this.fullscreenExitTimer = setTimeout(() => this.finishFullscreenExit(), 900);
      }
      void this.unlockFullscreenLandscape();
    }
    // 全屏与分栏都默认纯净观看：进/退全屏一律收起控件，单击播放区再唤出
    this.settleInformation(false);
    // 全屏隐藏系统状态栏、退回分栏恢复显示（对齐普通横屏播放页）
    if (enabled) this.applySystemBars(true);
  }

  /** 竖屏全屏入口：请求横屏并锁横屏，旋转完成后由 onAreaChange 落到横屏全屏态
   *  （普通页 prepareFullscreenEnvironment 口径） */
  private enterPortraitFullscreen(): void {
    if (this.landscapeLayout() || this.pendingLandscapeFullscreen || !this.mw) return;
    this.pendingLandscapeFullscreen = true;
    // 锁横屏必须在请求旋转时就下发，否则旋转落定后手机一转又会掉回竖屏页面
    this.lockFullscreenLandscape();
  }

  /** 分栏比例的入口口径（普通页 referenceLandscapeRestoreRatio / @State 默认 2/3 同款）：
   *  比例只属于当前页面实例、不落盘 —— 重新进入分栏界面必然回到默认 2/3；
   *  只有「不同分栏页跳转」带 landscapePlayerRatio 才继承；单纯横竖屏切换不经过
   *  aboutToAppear，且 onAreaChange 不动 landscapeRatio，比例自然保留。 */
  private initialLandscapeRatio(params: Record<string, Object> | undefined): number {
    const passed = params ? Number(params['landscapePlayerRatio']) : NaN;
    return Number.isFinite(passed) && passed > 0 && passed < 1 ? passed : SPLIT_DEFAULT_RATIO;
  }

  // ========== 手势状态（onVT 风格） ==========
  private sx_: number = 0; private sy_: number = 0;
  private gm_: string = '';         // 手势模式: '' | 'volume' | 'brightness'
  private ml_: boolean = false;     // 是否已移动（区分点击）
  private la_: boolean = false;     // 长按激活（直播无长按，保留占位）
  private dt_: number = -1;        // 双击定时器
  private dtp_: boolean = false;    // 是否双击
  private lt_: number = -1;        // 长按定时器
  private gt_: number = -1;        // 手势提示隐藏定时器
  private lastHapticPct_: number = -1;

  // ==================== 画面比例 + 重置直播 ====================

  private screenWv(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.width / d.densityPixels;
    } catch (_e) { return 720; }
  }

  private screenHv(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.height / d.densityPixels;
    } catch (_e) { return 405; }
  }

  private portraitRoom(): boolean {
    return this.sourceHeight > this.sourceWidth;
  }

  private portraitWindow(): boolean {
    return (this.viewportHeight || this.screenHv()) > (this.viewportWidth || this.screenWv());
  }

  private videoW(): number {
    if (this.landscapeLayout()) return this.landscapeMediaWidth(this.sourceWidth, this.sourceHeight);
    const sw = this.viewportWidth || this.screenWv();
    const sh = this.viewportHeight || this.screenHv();
    const r = this.sourceWidth / this.sourceHeight;
    const fill = this.portraitRoom() && this.portraitWindow() && this.portraitScale === 'fill'
      && (this.portraitScaleScope === 'all' || Math.abs(r / (9 / 16) - 1) <= 0.001);
    return fill ? Math.max(sw, sh * r) : Math.min(sw, sh * r);
  }

  private videoH(): number {
    return this.videoW() * this.sourceHeight / Math.max(1, this.sourceWidth);
  }

  private videoLeft(): number {
    if (this.landscapeLayout()) return this.landscapeMediaX(this.sourceWidth, this.sourceHeight);
    const sw = this.viewportWidth || this.screenWv();
    return (sw - this.videoW()) / 2;
  }

  private videoTop(): number {
    if (this.landscapeLayout()) return this.landscapeMediaY(this.sourceWidth, this.sourceHeight);
    const sh = this.viewportHeight || this.screenHv();
    // 横向直播在竖屏中上部播放，为下方信息留出空间；清屏时位置不变。
    return this.portraitWindow() && !this.portraitRoom()
      ? Math.max(this.safeTop + 86, sh * 0.237) : (sh - this.videoH()) / 2;
  }

  private settleInformation(visible: boolean): void {
    this.informationVisible = visible;
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 160, curve: Curve.EaseOut }, () => {
      this.informationProgress = visible ? 0 : 1;
    });
  }

  /**
   * 系统栏对齐普通播放页：横屏分栏显示系统状态栏（小白条仍隐藏），全屏与竖屏保持隐藏。
   * 同时同步 AppStorage `isFullscreen` —— EntryAbility 回前台恢复（后台播放）读它决定显隐；
   * 离开直播间（aboutToDisappear）必须复位为 false。
   */
  private applySystemBars(fullscreenOverride?: boolean): void {
    // ⚠️ 进/退全屏时状态在 animateTo 闭包里才写入，这里必须允许直接传目标态，
    //    否则读到的是旧值（分栏→全屏仍下发"显示"，系统状态栏就藏不掉）。
    const fullscreen = fullscreenOverride === undefined ? this.liveFullscreen : fullscreenOverride;
    const hide = !this.landscapeLayout() || fullscreen;
    AppStorage.setOrCreate('isFullscreen', hide);
    // ⭐ 状态栏内容色不在这里下发：首次进入时 applySystemBars 经 aboutToAppear 调用，
    //    跑在 push 转场首帧之前，会让上一个页面满屏时状态栏就变白。统一由 onPageShow
    //    与 applySystemBars 同拍下发（见 onPageShow）。
    if (!this.mw) return;
    StatusBarUtils.setSystemBars(this.mw, !hide, false);
  }

  private openLiveMenu(): void {
    this.liveMenuPanel = 'share';
    this.showPlaybackSettings = true;
  }

  private async shareLiveRoom(): Promise<void> {
    const url = `https://live.bilibili.com/${this.roomId}`;
    try {
      const data = new systemShare.SharedData({ utd: 'general.hyperlink', content: url, title: this.title });
      this.liveShareController = new systemShare.ShareController(data);
      await this.liveShareController.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {});
    } catch (_e) { this.showBottomHintTemporarily('未能打开系统分享'); }
  }

  /** 评论 tab：新弹幕到达时只在用户仍贴底的情况下自动滚到最新，上滑翻历史不被打断 */
  private onLiveChatMessagesChanged(): void {
    if (!this.chatFollowLatest || !this.landscapeLayout() || this.disposed) return;
    setTimeout(() => {
      if (this.disposed || !this.chatFollowLatest) return;
      try { this.landscapeChatScroller.scrollEdge(Edge.Bottom); } catch (_e) { /* 列表尚未挂载 */ }
    }, 30);
  }

  /** 简介 tab 的直播推荐：照抄竖屏 LivePage.loadLiveRooms 的取数口径——
   *  areaId=0 走 fetchRecommendedLiveRooms（B 站默认推荐流），否则按分区取；
   *  客户端按 roomId 去重、分页追加，额外排除当前房间。 */
  private async loadLiveIntroRooms(reset: boolean): Promise<void> {
    if (this.liveIntroLoading || this.disposed) return;
    if (!reset && !this.liveIntroHasMore) return;
    if (reset) {
      this.liveIntroPage = 1;
      this.liveIntroRoomIds.clear();
      this.liveIntroHasMore = true;
    }
    this.liveIntroLoading = true;
    const page = this.liveIntroPage;
    const roomId = this.roomId;
    try {
      const rooms = this.areaId > 0
        ? await fetchLiveRoomsByArea(this.areaId, page, 30)
        : await fetchRecommendedLiveRooms(page, 30);
      if (this.disposed || this.roomId !== roomId) return;
      const fresh: LiveFeedRoom[] = [];
      rooms.forEach((room: LiveFeedRoom) => {
        if (room.roomId > 0 && room.roomId !== roomId && !this.liveIntroRoomIds.has(room.roomId)) {
          this.liveIntroRoomIds.add(room.roomId);
          fresh.push(room);
        }
      });
      this.liveIntroRooms = reset ? fresh : this.liveIntroRooms.concat(fresh);
      this.liveIntroHasMore = rooms.length >= 30;
      this.liveIntroPage = page + 1;
    } catch (_e) {
      if (reset) this.liveIntroRooms = [];
    } finally {
      this.liveIntroLoading = false;
    }
  }

  private stopLiveChat(): void {
    this.liveChatGeneration++;
    clearTimeout(this.liveChatTimer);
    this.liveChatTimer = -1;
    this.liveChatReceiver.stop();
    this.liveChatConnected = false;
  }

  private startLiveChat(clear: boolean = false): void {
    this.stopLiveChat();
    if (clear) {
      this.liveChatMessages = [];
      this.liveChatStatus = '正在加载弹幕…';
    }
    if (this.disposed || this.pageHidden || this.roomId <= 0) return;
    this.liveChatReceiver.start(this.roomId);
    void this.refreshLiveChat(this.roomId, this.liveChatGeneration);
  }

  private async refreshLiveChat(roomId: number, generation: number): Promise<void> {
    let delay = 3000;
    try {
      const messages = await getLiveChatHistory(roomId);
      if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.roomId !== roomId) return;
      if (this.liveChatConnected) return;
      const merged = new Map<string, LiveChatMessage>();
      this.liveChatMessages.forEach(message => merged.set(message.id, message));
      messages.forEach(message => merged.set(message.id, message));
      this.liveChatMessages = Array.from(merged.values())
        .sort((a, b) => a.timeline.localeCompare(b.timeline)).slice(-this.LIVE_CHAT_LIMIT);
      if (!this.liveChatConnected && this.liveChatMessages.length) this.liveChatStatus = '';
    } catch (_) {
      if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.roomId !== roomId) return;
      if (!this.liveChatConnected) this.liveChatStatus = '弹幕暂不可用，正在重试…';
      delay = 10000;
    }
    if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.liveChatConnected) return;
    this.liveChatTimer = setTimeout(() => { void this.refreshLiveChat(roomId, generation); }, delay);
  }

  private unavailableLiveAction(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private async setPortraitScale(mode: string): Promise<void> {
    this.portraitScale = mode;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const pref = await preferences.getPreferences(ctx, 'my_app_settings');
      await pref.put('livePortraitScale', mode);
      await pref.flush();
    } catch (_e) { logWarn('[LivePlayer] 直播比例保存失败'); }
  }

  private async setPortraitScaleScope(scope: string): Promise<void> {
    this.portraitScaleScope = scope;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(ctx, 'my_app_settings');
      await pref.put('livePortraitScaleScope', scope);
      await pref.flush();
    } catch (_e) { logWarn('[LivePlayer] 直播比例生效范围保存失败'); }
  }

  /** 简介 tab 的直播推荐列表（换房后再过滤一次当前房间） */
  private introRooms(): LiveFeedRoom[] {
    return this.liveIntroRooms.filter((room: LiveFeedRoom) => room.roomId > 0 && room.roomId !== this.roomId);
  }

  /** 旧推荐/上下滑列表：排除当前房间的其它直播间 */
  private recommendedRooms(): LiveFeedRoom[] {
    return this.rooms.filter((room: LiveFeedRoom) => room.roomId > 0 && room.roomId !== this.roomId).slice(0, 30);
  }

  /** 推荐卡片点击：push 出新的直播播放页（普通页相关视频同款跳转），并带上当前分栏比例 */
  private selectRecommendedRoom(target: LiveFeedRoom): void {
    if (!target || target.roomId <= 0 || target.roomId === this.roomId || this.disposed) return;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LivePlayerPage',
      params: {
        roomId: target.roomId,
        roomIds: this.roomIds.slice(),
        rooms: this.rooms.slice(),
        areaId: this.areaId,
        roomPage: this.roomPage,
        landscapePlayerRatio: this.landscapeRatio
      }
    }).catch((err: Error) => { logError(`[LivePlayer] 跳转推荐直播间失败: ${err.message}`); });
  }

  private async switchRoom(direction: number): Promise<void> {
    if (this.switchingRoom || this.disposed) return;
    this.switchingRoom = true;
    try {
      let index = this.roomIds.indexOf(this.roomId);
      if (direction < 0 && index <= 0) {
        this.showBottomHintTemporarily('已经是第一个直播间');
        return;
      }
      if (index + direction >= this.roomIds.length) {
        const rooms = await fetchLiveRoomsByArea(this.areaId, this.roomPage + 1, 30);
        if (this.disposed) return;
        if (rooms.length > 0) this.roomPage++;
        rooms.forEach(room => {
          if (room.roomId > 0 && !this.roomIds.includes(room.roomId)) {
            this.roomIds.push(room.roomId);
            this.rooms = this.rooms.concat(room);
          }
        });
        index = this.roomIds.indexOf(this.roomId);
      }
      const next = this.roomIds[index + direction];
      if (!next) { this.showBottomHintTemporarily('暂无更多直播间，请稍后重试'); return; }
      this.roomSlideDirection = direction;
      this.prepareAdjacentRoom(direction, true);
      await this.animateRoomOffset(-direction * (this.viewportHeight || this.screenHv()));
      if (this.disposed) return;
      this.playGeneration++;
      clearTimeout(this.retryTimer);
      const incoming = this.previewRoomId === next ? this.previewAV : null;
      const stream = incoming ? this.previewStream : null;
      const info = incoming ? this.previewInfo : null;
      const qualities = incoming ? this.previewQualities : [];
      const ready = incoming !== null && this.previewReady;
      const width = this.previewWidth;
      const height = this.previewHeight;
      const outgoing = this.av;
      // 先关闭旧声音，再启用新声音；固定 Surface 只交换角色，不重建。
      try { outgoing?.setVolume(0); } catch (_) {}
      this.av = incoming;
      if (incoming) this.audioOutputMonitor.bind(incoming, audio.StreamUsage.STREAM_USAGE_MOVIE);
      this.previewAV = null;
      this.clearPreview();
      this.activeSlot = 1 - this.activeSlot;
      this.activeFrameReady = ready;
      this.userPaused = false;
      this.videoSrc = '';
      this.roomId = next;
      this.startLiveChat(true);
      this.title = '';
      this.uname = '';
      this.anchorFace = '';
      this.roomCover = '';
      this.online = 0;
      this.sourceWidth = 16;
      this.sourceHeight = 9;
      this.availableQualities = [];
      this.currentQn = 0;
      this.retryCount = 0;
      this.errorMsg = '';
      this.loading = true;
      this.roomOffset = 0;
      if (incoming && stream) {
        this.videoSrc = stream.url;
        this.sourceWidth = width;
        this.sourceHeight = height;
        this.availableQualities = qualities;
        this.applyStreamQuality(stream);
        const card = this.rooms.find(room => room.roomId === next);
        this.title = info?.title || card?.title || '';
        this.uname = info?.uname || card?.uname || '';
        this.anchorFace = card?.face || info?.face || '';
        this.roomCover = info?.keyframe || info?.face || '';
        this.online = info?.online || 0;
        if (incoming.state === 'playing' || incoming.state === 'paused' || incoming.state === 'prepared') {
          incoming.setVolume(this.isMuted ? 0 : 1);
          if (incoming.state === 'playing') this.onVideoStart();
          else if (!this.pageHidden || this.bgp) void incoming.play();
        }
        this.loading = !ready;
        this.setupLiveView_();
      }
      // 等旧解码器释放完再预热，始终最多两个播放器。
      await this.disposePlayer(outgoing);
      if (!incoming) await this.initPlayback();
    } finally {
      this.switchingRoom = false;
      if (!this.disposed && this.roomOffset !== 0) void this.animateRoomOffset(0);
      if (!this.disposed && !this.pageHidden && this.av) this.prepareAdjacentRoom(1);
    }
  }

  private clearPreview(): void {
    this.previewGeneration++;
    const player = this.previewAV;
    this.previewAV = null;
    this.previewRoomId = 0;
    this.previewReady = false;
    this.previewInfo = null;
    this.previewStream = null;
    this.previewQualities = [];
    this.previewRelease = this.previewRelease.then(() => this.disposePlayer(player));
  }

  private async disposePlayer(player: media.AVPlayer | null): Promise<void> {
    if (!player) return;
    try {
      player.off('stateChange');
      player.off('error');
      player.off('videoSizeChange');
      player.off('startRenderFrame');
      if (player.state !== 'released') await player.release();
    } catch (_) {}
  }

  private prepareAdjacentRoom(direction: number, committing: boolean = false): void {
    const next = this.roomIds[this.roomIds.indexOf(this.roomId) + direction];
    if (!next || this.disposed || this.pageHidden || this.switchingRoom && !committing) return;
    if (next === this.previewRoomId) return;
    this.clearPreview();
    this.previewRoomId = next;
    const generation = this.previewGeneration;
    this.previewTask = this.previewTask.then(() => this.preparePreview(next, generation));
  }

  private async preparePreview(roomId: number, generation: number): Promise<void> {
    let player: media.AVPlayer | null = null;
    try {
      await this.previewRelease;
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) return;
      const info = await getLiveRoomInfo(roomId);
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) return;
      if (info?.liveStatus !== 1) return;
      const quality = await getRoomPlayInfo(roomId);
      const stream = await getLiveStreamUrl(roomId, quality?.qualities[0]?.qn || 250);
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden || !stream?.url) return;
      player = await media.createAVPlayer();
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) {
        await this.disposePlayer(player);
        return;
      }
      this.previewAV = player;
      this.previewInfo = info;
      this.previewStream = stream;
      this.previewQualities = quality?.qualities.map(option => ({ qn: option.qn, label: option.desc }) as QualityOption) || [];
      this.previewWidth = stream.videoWidth || 16;
      this.previewHeight = stream.videoHeight || 9;
      this.bindPlayer(player, 1 - this.activeSlot);
      await player.setMediaSource(this.liveMediaSource(stream.url));
    } catch (_) {
      if (player && this.av === player) this.handlePlayError();
      else if (generation === this.previewGeneration) this.clearPreview();
    }
  }

  private animateRoomOffset(offset: number): Promise<void> {
    this.roomAnimating = true;
    return new Promise<void>(resolve => {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 340, curve: Curve.EaseOut, onFinish: () => {
        this.roomAnimating = false;
        resolve();
      } }, () => { this.roomOffset = offset; });
    });
  }

  /** ⭐ 重置直播：释放播放器并强制重新拉流 */
  private resetLive(): void {
    this.showBottomHintTemporarily('已重置直播');
    this.releasePlayer();
    this.showControlsTemporarily();
    this.startPlay(true);
  }

  /** ⭐ 播放/暂停切换 */
  private async togglePlayPause(): Promise<void> {
    const player = this.av;
    if (!player || this.switchingRoom || this.roomAnimating) return;
    try {
      if (player.state === 'playing') {
        this.userPaused = true;
        await player.pause();
      } else if (player.state === 'paused' || player.state === 'prepared') {
        this.userPaused = false;
        await this.resumeLivePlayer(player);
      }
    } catch (_e) {}
  }

  private async resumeLivePlayer(player: media.AVPlayer): Promise<void> {
    await PlaybackAudioSession.activate();
    if (this.disposed || this.av !== player || this.userPaused || (this.pageHidden && !this.bgp)) return;
    await player.play();
  }

  private registerContinuation(): void {
    AppContinuation.register(this, 'pages/LivePlayerPage', (): ContinuationPage | null => {
      if (this.roomId <= 0) return null;
      const params: Record<string, string | number | boolean> = { 'roomId': this.roomId, 'areaId': this.areaId };
      const destination: ContinuationPage = { page: 'pages/LivePlayerPage', params: params };
      return destination;
    });
  }

  aboutToAppear() {
    // ⭐ 存活播放页计数（与 VideoPlayerPage 共用）：退出时若还有别的播放页活着，
    //    内容色必须回到白字而不是主题口径，否则浅色模式下层播放页被恢复成黑字。
    AppStorage.setOrCreate('immersivePlayerAliveCount',
      Math.max(0, (AppStorage.get<number>('immersivePlayerAliveCount') ?? 0)) + 1);
    // 横屏进页（含推荐卡片 push 的新直播页）默认纯净观看，控件隐藏；竖屏信息层仍默认显示
    this.informationVisible = this.defaultInformationVisible();
    this.informationProgress = this.informationVisible ? 0 : 1;
    this.registerContinuation();
    // ⭐ 注册系统音量变化监听（音量键调节时同步 app 内滑块/手势起点）
    this.registerVolumeListener();
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    // 比例只在实例内：重新进入分栏界面重置 2/3，只有不同分栏页跳转继承（普通页口径）
    this.landscapeRatio = this.initialLandscapeRatio(params);
    if (params && params['roomId']) {
      this.roomId = params['roomId'] as number;
      this.roomIds = (params['roomIds'] as number[] || []).filter(id => id > 0);
      this.rooms = params['rooms'] as LiveFeedRoom[] || [];
      if (!this.roomIds.includes(this.roomId)) this.roomIds.unshift(this.roomId);
      this.areaId = params['areaId'] as number || 0;
      this.roomPage = params['roomPage'] as number || 0;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      preferences.getPreferences(ctx, 'my_app_settings').then(pref => {
        if (!this.disposed) {
          // 只读取竖屏画面比例设置；横屏分栏比例不持久化，避免重新进入分栏时恢复旧值
          this.portraitScale = pref.getSync('livePortraitScale', 'fill') === 'auto' ? 'auto' : 'fill';
          this.portraitScaleScope = pref.getSync('livePortraitScaleScope', 'standard') === 'all' ? 'all' : 'standard';
        }
      });
      this.initSwipeControl();
      this.getSafeArea();
      this.initPlayback();
      this.startLiveChat(true);
    } else {
      this.errorMsg = '缺少房间号';
      this.loading = false;
    }
  }

  /**
   * 初始化播放：先获取画质信息选最高画质，再开始播放
   */
  private async initPlayback(): Promise<void> {
    await this.fetchQualityInfo();
    if (!this.disposed) await this.startPlay();
  }

  private getSafeArea(): void {
    try {
      window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((w: window.Window) => {
        this.mw = w;
        // ⭐ 窗口就绪后按当前播放状态补设屏幕常亮：
        //    startPlay 是异步的（先取画质再拉流），可能早于这里拿到窗口，
        //    而 onVideoStart 里那次调用会因 mw 还是 undefined 而被静默丢弃。
        this.updateKeepScreen();
        // 初始化时尊重全局旋转设置；窗口回调是异步的，不能把已生效的全屏横向锁覆盖掉。
        const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
        this.rotationFreeMode = lock === '自动旋转' ? 'auto' : 'system';
        this.rotationMode = lock === '锁定竖屏' ? 'portrait' : lock === '锁定横屏' ? 'landscape' : this.rotationFreeMode;
        if (!this.liveFullscreenLocked) this.applyRotationMode();
        const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        if (top.topRect.height > 0) {
          this.safeTop = this.getUIContext().px2vp(top.topRect.height);
        }
        const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        if (bottom.bottomRect.height > 0) {
          this.safeBottom = this.getUIContext().px2vp(bottom.bottomRect.height);
        }
        // 进入直播间立即隐藏系统栏（状态栏+小白条），与普通播放页同一口径
        this.applySystemBars();
      });
    } catch (_e) {
      // 使用默认值
    }
  }

  /**
   * 从API获取直播间可用画质列表，替换默认列表（只显示此直播间有的画质）
   */
  private async fetchQualityInfo(): Promise<void> {
    const roomId = this.roomId;
    try {
      const info = await getRoomPlayInfo(roomId);
      if (this.disposed || this.roomId !== roomId) return;
      if (info && info.qualities.length > 0) {
        // B站返回的画质排序：从高到低
        const sorted: QualityOption[] = info.qualities.map((q: QualityDescription) => ({
          qn: q.qn,
          label: q.desc
        }) as QualityOption);
        // 替换为API返回的列表（只显示此直播间有的画质）
        this.availableQualities = sorted;
        // 自动选择最高画质（列表第一项）
        if (sorted[0].qn !== this.currentQn) {
          this.currentQn = sorted[0].qn;
          logInfo(`[LivePlayer] 动态获取画质列表: ${JSON.stringify(sorted)}, 自动选择最高画质: ${sorted[0].label}(${sorted[0].qn})`);
        }
      } else {
        logWarn('[LivePlayer] API返回的画质列表为空，使用用户手动选择');
      }
    } catch (_e) {
      logWarn(`[LivePlayer] 获取画质列表失败，将由startPlay使用默认兜底画质: ${_e}`);
    }
  }

  aboutToDisappear() {
    this.fullscreenDeviceOrientation.stop();
    clearTimeout(this.fullscreenExitTimer);
    AppContinuation.unregister(this);
    this.disposed = true;
    // ⭐ 存活计数先减自己：还有别的播放页活着（如直播页下面压着的视频播放页）就不能恢复
    //    主题口径——下层实例的 onPageShow 已设白字，这次恢复若后到会让浅色模式下层播放页
    //    闪黑；改为主动回写白字，保证最后一个写窗口的是白。直用 this.mw，不等 getLastWindow。
    const remaining = Math.max(0, (AppStorage.get<number>('immersivePlayerAliveCount') ?? 1) - 1);
    AppStorage.setOrCreate('immersivePlayerAliveCount', remaining);
    if (remaining > 0) {
      StatusBarUtils.setPlayerStatusBarContent(
        this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
    } else {
      StatusBarUtils.restoreThemeStatusBarContent(
        this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
    }
    this.stopLiveChat();
    this.playGeneration++;
    // ⭐ 注销系统音量变化监听
    this.unregisterVolumeListener();
    this.audioOutputMonitor.dispose();
    // ⭐ 结束后台媒体会话（返回即停；切后台续播由 onPageHide 处理）
    LiveViewHelper.end();
    this.releasePlayer();
    clearTimeout(this.controlsTimer);
    clearTimeout(this.retryTimer);
    clearTimeout(this.gt_);
    clearTimeout(this.dt_);
    clearTimeout(this.lt_);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowBrightness(-1);
        // ⭐ 离开直播间：释放屏幕常亮（防止"页面已销毁但常亮没关"导致一直不熄屏）
        w.setWindowKeepScreenOn(false).catch(() => {});
        // 离开时恢复导航小白条（横屏时保持状态栏隐藏）
        const isLandscape: boolean = AppStorage.get<boolean>('isLandscape') ?? false;
        const hideSb: boolean = AppStorage.get<boolean>('hideStatusBar') ?? false;
        StatusBarUtils.setSystemBars(w, !isLandscape && !hideSb, true);
        // 直播间的系统栏常隐态结束，别让 EntryAbility 在其它页面上继续隐藏状态栏。
        AppStorage.setOrCreate('isFullscreen', false);
        // 离开直播恢复全局设置，避免临时锁定覆盖系统旋转策略。
        const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
        const orientation = lock === '锁定竖屏' ? window.Orientation.PORTRAIT
          : lock === '锁定横屏' ? window.Orientation.AUTO_ROTATION_LANDSCAPE
          : lock === '自动旋转' ? window.Orientation.AUTO_ROTATION : window.Orientation.AUTO_ROTATION_RESTRICTED;
        w.setPreferredOrientation(orientation).catch(() => {});
      });
    } catch (_e) {}
  }

  /** ⭐ 页面隐藏（切后台/跳转）：后台播放开启则保持播放，否则暂停 */
  onPageHide(): void {
    this.pageHidden = true;
    this.fullscreenDeviceOrientation.stop();
    // ⭐ 提前一步恢复状态栏内容色：pop 出栈或被普通页面覆盖时，此刻路由栈已指向目标页，
    //    立即恢复主题口径（目标页还是播放页则交给对方 onPageShow 强制白字）。
    //    切后台时栈顶仍是本页，不会误发。
    try {
      const state = this.getUIContext().getRouter().getState();
      const raw = state.path.endsWith('/') ? `${state.path}${state.name}` : state.path;
      const top = raw.startsWith('/') ? raw.substring(1) : raw;
      if (top !== 'pages/LivePlayerPage' && top !== 'pages/VideoPlayerPage') {
        StatusBarUtils.restoreThemeStatusBarContent(
          this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
      }
    } catch (_e) {}
    this.stopLiveChat();
    this.finishLevelGesture();
    this.clearPreview();
    this.cancelPendingTap();
    // ⭐ 页面隐藏即释放屏幕常亮（切后台/跳页时屏幕应能正常锁屏）
    //    ⚠️ 必须放在下面的 return 之前，否则"播放器还没建好"时提前返回会漏掉释放
    this.mw?.setWindowKeepScreenOn(false).catch(() => {});
    if (!this.av) { return; }
    if (this.bgp) {
      logInfo('[LivePlayer] onPageHide → 后台播放模式，保持播放');
      if (!LiveViewHelper.active) { this.setupLiveView_(); }
      return;
    }
    try { this.av.pause(); } catch (_) {}
    LiveViewHelper.updatePlayState(false);
  }

  /** 回前台仅恢复系统暂停，保留用户主动暂停。 */
  onPageShow(): void {
    this.pageHidden = false;
    if (this.liveFullscreenLocked) this.fullscreenDeviceOrientation.start();
    this.startLiveChat();
    this.registerContinuation();
    if (!this.userPaused && this.av?.state === 'paused') this.resumeLivePlayer(this.av).catch(() => {});
    // ⭐ 回到直播间：恢复屏幕常亮 + 重新隐藏系统栏（EntryAbility 回前台可能按
    //    全局状态把状态栏恢复了，这里与普通播放页 onPageShow → manageSB(true) 同口径补设）。
    //    "后台播放"模式下播放从未中断，不会有 stateChange('playing') 去触发 onVideoStart。
    this.updateKeepScreen();
    this.applySystemBars();
    // ⭐ 状态栏内容色强制白字：横屏分栏时状态栏压在视频/封面上，浅色模式的全局黑字（首页口径）
    //    会看不见。与 applySystemBars 同拍同步下发：转场启动帧内发出窗口属性，IPC 落地在
    //    首帧后 1~3 帧（对齐原版节奏）；更早（aboutToAppear 链）会在上一个页面满屏时变色，
    //    延迟中段下发则会触发 avoidArea 重算顿掉转场一拍。已持有 mw 就直传，省一跳中转。
    StatusBarUtils.setPlayerStatusBarContent(
      this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
    // 从其它页面回到仍处于横屏全屏的直播间：补发方向锁，避免新页面的全局方向设置把它带成竖屏
    if (this.liveFullscreen && this.liveFullscreenLocked && this.mw) {
      try { this.mw.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE).catch(() => {}); } catch (_e) {}
    }
  }

  // ==================== 播放器逻辑（基于 media.AVPlayer） ====================

  private applyStreamQuality(result: LiveStreamUrlResult): void {
    const supported = result.acceptQuality.filter((qn, index, all) => qn > 0 && all.indexOf(qn) === index);
    if (result.currentQn > 0 && !supported.includes(result.currentQn)) supported.push(result.currentQn);
    this.availableQualities = supported.sort((a, b) => b - a).map(qn => ({
      qn, label: this.availableQualities.find(option => option.qn === qn)?.label || getLiveQualityLabel(qn)
    }) as QualityOption);
    this.currentQn = result.currentQn;
    logInfo(`[LivePlayer] 实际画质=${this.currentQn}, 当前流支持=${supported.join(',')}`);
  }

  private async startPlay(forceRefresh: boolean = false): Promise<void> {
    const generation = ++this.playGeneration;
    try {
      // 读取当前系统音量，确保手势滑块从真实音量开始
      this.readSystemVolume();
      this.isMuted = AppStorage.get<boolean>('globalMuted') ?? false;
      // 如果currentQn未设置（API获取失败等情况），使用超清兜底
      if (this.currentQn <= 0) {
        this.currentQn = 250;
      }

      const info = await getLiveRoomInfo(this.roomId);
      if (this.disposed || generation !== this.playGeneration) return;
      if (info) {
        const card = this.rooms.find(room => room.roomId === this.roomId);
        this.anchorFace = card?.face || info.face;
        this.title = info.title;
        this.online = info.online;
        this.uname = info.uname || card?.uname || '';
        this.roomCover = info.face || info.keyframe || ''; // 封面优先 user_cover，其次 keyframe
        // 简介页的「N粉丝」用主播 uid 取用户卡片（与普通简介页 ReferenceUpRow 同源）
        this.anchorFans = 0;
        const anchorUid = info.uid || card?.uid || 0;
        if (anchorUid > 0) {
          void getVideoIntroCard(anchorUid).then(introCard => {
            if (!this.disposed && introCard?.card?.fans !== undefined) {
              this.anchorFans = Number(introCard.card.fans) || 0;
            }
          }).catch(() => {});
        }
        if (info.liveStatus !== 1) {
          this.errorMsg = '主播未开播';
          this.loading = false;
          return;
        }
      }

      const streamResult = await getLiveStreamUrl(this.roomId, this.currentQn, forceRefresh);
      if (this.disposed || generation !== this.playGeneration) return;
      if (!streamResult || !streamResult.url) {
        this.errorMsg = '获取直播流地址失败';
        this.loading = false;
        return;
      }

      this.loading = true;
      this.errorMsg = '';
      this.playbackStartMs = Date.now();
      this.applyStreamQuality(streamResult);
      this.sourceWidth = streamResult.videoWidth || 16;
      this.sourceHeight = streamResult.videoHeight || 9;
      this.videoSrc = streamResult.url;
      this.videoSrcVersion++;
      await this.setupAVPlayer(streamResult.url, generation);
    } catch (e) {
      logError(`[LivePlayer] startPlay异常: ${e}`);
      if (!this.disposed && generation === this.playGeneration) this.handlePlayError();
    }
  }

  private onVideoPrepared(): void {
    this.errorMsg = '';
    this.retryCount = 0;
    // AVPlayer 音量随系统媒体音量
  }

  /**
   * ⭐ 屏幕常亮：播放中保持屏幕不自动休眠（AVPlayer 不会自动阻止系统休眠，必须显式调用）
   *    之前直播间漏了这一步 → 播放中会跟随系统"休眠时间"自动熄屏锁屏。
   *    play=true 时开启；暂停 / 页面隐藏 / 离开页面时释放。
   *    ⚠️ this.mw 是**异步**拿到的（getSafeArea），播放状态可能先于窗口就绪 →
   *       窗口就绪后必须补调一次（见 getSafeArea），否则首次进入直播间不生效。
   */
  private updateKeepScreen(): void {
    this.mw?.setWindowKeepScreenOn(this.isPlaying && !this.pageHidden).catch(() => {});
  }

  private onVideoStart(): void {
    this.retryCount = 0;
    this.isPlaying = true;
    // ⭐ 开播 → 屏幕常亮
    this.updateKeepScreen();
    this.playbackStartMs = Date.now();
    // 初始保持控制栏可见，等用户第一次点击后再进入自动隐藏模式
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
    // ⭐ 同步媒体会话播放状态（通知/实况窗）：否则状态停在初始"播放中"，
    //    用户点暂停实际是让已暂停的播放器再 pause（invalid operation），控制无效
    LiveViewHelper.updatePlayState(true);
    this.prepareAdjacentRoom(1);
  }

  private onVideoPause(): void {
    this.isPlaying = false;
    // ⭐ 暂停 → 释放屏幕常亮（用户主动暂停后允许系统正常熄屏）
    this.updateKeepScreen();
    // ⭐ 同步媒体会话播放状态为暂停
    LiveViewHelper.updatePlayState(false);
  }

  private onVideoError(): void {
    const elapsed: number = Date.now() - this.playbackStartMs;
    // 播放启动后 3s 内的 onError 通常是直播流不支持循环设置(errorCode=801)，
    // 这是非致命警告，播放器实际仍在正常渲染画面。忽略它避免 stop→retry 死循环。
    if (elapsed < 3000) {
      logWarn(`[LivePlayer] 忽略启动后${elapsed}ms内的非致命错误（直播流 loop 设置不支持）`);
      return;
    }
    logError(`[LivePlayer] AVPlayer 错误（播放${elapsed}ms后）`);
    this.releasePlayer();
    this.handlePlayError();
  }

  private handlePlayError(): void {
    if (this.retryCount < this.maxRetries) {
      this.retryCount++;
      this.loading = true;
      this.errorMsg = '';
      const shouldRefresh: boolean = this.retryCount > 2;
      if (shouldRefresh) {
        invalidateCachedStreamUrl(this.roomId);
      }
      // 重试超过 3 次后尝试降画质
      if (this.retryCount >= 3 && this.availableQualities.length > 0) {
        this.downgradeQuality();
      }
      if (this.retryTimer !== -1) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => {
        this.retryTimer = -1;
        this.startPlay(shouldRefresh);
      }, 1000);
    } else {
      this.retryCount = 0;
      this.loading = true;
      this.errorMsg = '';
      invalidateCachedStreamUrl(this.roomId);
      // 最大重试后降画质，防止死循环
      this.downgradeQuality();
      if (this.retryTimer !== -1) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => {
        this.retryTimer = -1;
        this.startPlay(true);
      }, 2000);
    }
  }

  /** 降画质：从当前画质降到下一个更低画质 */
  private downgradeQuality(): void {
    if (this.availableQualities.length === 0) {
      return;
    }
    const currentIdx: number = this.availableQualities.findIndex((q: QualityOption) => q.qn === this.currentQn);
    if (currentIdx < this.availableQualities.length - 1) {
      const nextQn: number = this.availableQualities[currentIdx + 1].qn;
      logInfo(`[LivePlayer] 降画质: ${getLiveQualityLabel(this.currentQn)}(${this.currentQn}) → ${getLiveQualityLabel(nextQn)}(${nextQn})`);
      this.currentQn = nextQn;
      invalidateCachedStreamUrl(this.roomId);
    } else {
      logInfo(`[LivePlayer] 已是最低画质，不再降级`);
    }
  }

  /** 释放播放器资源 */
  private releasePlayer(): void {
    this.clearPreview();
    this.releaseAVPlayer();
    this.videoSrc = '';
  }

  private async releaseAVPlayer(): Promise<void> {
    const av = this.av;
    this.av = null;
    this.activeFrameReady = false;
    if (!av) { return; }
    try {
      av.off('stateChange');
      av.off('error');
      av.off('videoSizeChange');
      av.off('startRenderFrame');
      if (av.state !== 'released') { await av.release(); }
    } catch (_e) {}
  }

  /** ⭐ 创建 AVPlayer（HLS 主流；极端 FLV 可能不支持，交由错误重试链处理） */
  private async setupAVPlayer(url: string, generation: number): Promise<void> {
    if (this.av) { await this.releaseAVPlayer(); }
    if (url.toLowerCase().includes('.flv')) {
      logWarn('[LivePlayer] 该直播流为 FLV，AVPlayer 可能不支持，仅尝试播放');
    }
    const av: media.AVPlayer = await media.createAVPlayer();
    if (this.disposed || generation !== this.playGeneration) { await av.release(); return; }
    this.av = av;
    this.audioOutputMonitor.bind(av, audio.StreamUsage.STREAM_USAGE_MOVIE);
    this.bindPlayer(av, this.activeSlot);
    await av.setMediaSource(this.liveMediaSource(url));
  }

  private liveMediaSource(url: string): media.MediaSource {
    return media.createMediaSourceWithUrl(url, {
      'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'
    });
  }

  private ownsPlayer(player: media.AVPlayer): boolean {
    return !this.disposed && (this.av === player || this.previewAV === player);
  }

  private bindPlayer(player: media.AVPlayer, slot: number): void {
    player.on('startRenderFrame', () => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player) {
        this.activeFrameReady = true;
        this.loading = false;
      }
      else this.previewReady = true;
    });
    player.on('videoSizeChange', (width: number, height: number) => {
      if (!this.ownsPlayer(player) || width <= 0 || height <= 0) return;
      if (this.av === player) { this.sourceWidth = width; this.sourceHeight = height; }
      else { this.previewWidth = width; this.previewHeight = height; }
    });
    player.on('error', (err: BusinessError) => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player) {
        logError(`[LivePlayer] AVPlayer error: ${err.message}`);
        this.onVideoError();
      } else this.clearPreview();
    });
    player.on('stateChange', async (state: string) => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player && (state === 'prepared' || state === 'playing')) {
        this.audioOutputMonitor.bind(player, audio.StreamUsage.STREAM_USAGE_MOVIE);
      }
      try {
        if (state === 'initialized') {
          const surface = await this.ensureSurfaceId_(slot);
          if (!this.ownsPlayer(player)) return;
          if (!surface) throw new Error('直播 Surface 尚未就绪');
          player.surfaceId = surface;
          await player.prepare();
        } else if (state === 'prepared') {
          await PlaybackAudioSession.activate();
          if (!this.ownsPlayer(player)) return;
          // SHARE_MODE 允许同应用两个直播并播，待切房仅音量为零。
          player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
          player.setVolume(this.av === player && !this.isMuted ? 1 : 0);
          if (this.av === player) this.onVideoPrepared();
          if (this.av === player && (this.userPaused || this.pageHidden && !this.bgp)) return;
          await player.play();
          if (this.av === player && this.ownsPlayer(player)) this.setupLiveView_();
        } else if (state === 'playing') {
          if (this.av === player) this.onVideoStart();
        } else if ((state === 'paused' || state === 'stopped' || state === 'completed' || state === 'error') && this.av === player) this.onVideoPause();
      } catch (error) {
        if (!this.ownsPlayer(player)) return;
        logWarn(`[LivePlayer] state=${state}: ${error}`);
        if (this.av === player) this.handlePlayError();
        else this.clearPreview();
      }
    });
  }

  private async ensureSurfaceId_(slot: number = this.activeSlot): Promise<string> {
    const controller = slot === 0 ? this.xc : this.spareXc;
    for (let i = 0; i < 10; i++) {
      const sid = controller.getXComponentSurfaceId();
      if (sid) return sid;
      await new Promise<void>(resolve => setTimeout(resolve, 30));
    }
    return '';
  }

  /** ⭐ 建立媒体会话 + 后台长时任务（通知栏/锁屏控制卡） */
  private setupLiveView_(): void {
    LiveViewHelper.setControlHandlers({
      play: () => {
        this.userPaused = false;
        const av = this.av;
        if (av && av.state !== 'playing') this.resumeLivePlayer(av).catch(() => {});
      },
      pause: () => {
        this.userPaused = true;
        try {
          const av = this.av;
          if (av && av.state !== 'paused') { av.pause(); }
        } catch (_) {}
      },
      seek: (_t: number) => { /* 直播无进度，忽略 */ }
    });
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      void LiveViewHelper.create(ctx, this.title, this.roomCover, String(this.roomId), 0, this.uname);
    } catch (_) {}
  }

  /** 切换画质 */
  private switchQuality(qn: number): void {
    if (!this.availableQualities.some(option => option.qn === qn)) return;
    this.currentQn = qn;
    this.loading = true;
    this.errorMsg = '';
    this.showQualityPicker = false;
    this.retryCount = 0;
    this.releasePlayer();
    invalidateCachedStreamUrl(this.roomId);
    this.startPlay(true);
  }

  private goBack(): void {
    this.disposed = true;
    this.playGeneration++;
    this.releasePlayer();
    this.getUIContext().getRouter().back();
  }

  /** 顶栏返回：横屏全屏先退回分栏播放态（对齐普通横屏播放页），其余直接退出直播间 */
  private handleHeaderBack(): void {
    if (this.liveFullscreen) {
      this.toggleLandscapeFullscreen();
      return;
    }
    this.goBack();
  }

  /** 返回键/侧滑返回：先收菜单，再退全屏，最后才离开直播间 */
  onBackPress(): boolean {
    if (this.showPlaybackSettings) {
      this.showPlaybackSettings = false;
      return true;
    }
    if (this.liveFullscreen) {
      this.toggleLandscapeFullscreen();
      return true;
    }
    return false;
  }

  /** 后台播放开关：持久化设置并同步媒体会话。 */
  private toggleBackgroundPlayback(): void {
    this.bgp = !this.bgp;
    AppStorage.set<boolean>('bgp', this.bgp);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      preferences.getPreferences(ctx, 'my_app_settings').then((pref) => {
        pref.put('bgp', this.bgp);
        pref.flush();
      });
    } catch (e) {
      logError('[LivePlayer] bgp 持久化保存失败', e);
    }
    // ⭐ 接入媒体会话：开启→建会话（在播时）；关闭→结束会话并暂停（若在后台）
    if (this.bgp) {
      if (this.av && (this.av.state === 'playing' || this.av.state === 'prepared')) {
        this.setupLiveView_();
      }
    } else {
      LiveViewHelper.end();
      const appBg: boolean = AppStorage.get<boolean>('appInBackground') ?? false;
      if (appBg && this.av && this.av.state === 'playing') {
        try { this.av.pause(); } catch (_) {}
      }
    }
  }

  private showControlsTemporarily(): void {
    this.isControlsVisible = true;
    if (this.controlsTimer !== -1) clearTimeout(this.controlsTimer);
    this.controlsTimer = setTimeout(() => {
      if (!this.showQualityPicker) {
        this.isControlsVisible = false;
      }
    }, 4000);
  }

  private showBottomHintTemporarily(txt: string, img?: ResourceStr): void {
    this.bottomHintText = txt;
    this.bottomHintImage = img;
    this.showBottomHint = true;
    setTimeout(() => { this.showBottomHint = false; }, 2000);
  }

  private setSystemVolume(vol: number): void {
    // 设置系统媒体音量：档位范围动态获取，不硬编码 15（设备档位不同会导致实际音量偏小）
    try {
      const v: number = Math.round(vol * this.maxVol_);
      audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, v);
    } catch (_e) {}
  }

  private async readSystemVolume(): Promise<void> {
    try {
      const mgr = audio.getAudioManager().getVolumeManager();
      const maxVol: number = mgr.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.maxVol_ = maxVol > 0 ? maxVol : 15;
      const sysVol: number = mgr.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.vol = maxVol > 0 ? Math.min(1, Math.max(0, sysVol / maxVol)) : 0.7;
      this.sv = this.vol;
      AppStorage.setOrCreate('globalVolume', this.vol);
    } catch (_e) {
      this.vol = AppStorage.get<number>('globalVolume') ?? 0.7;
    }
  }

  /** ⭐ 注册系统音量变化监听（音量键调节时同步 app 内滑块/手势起点） */
  private registerVolumeListener(): void {
    try {
      const mgr = audio.getAudioManager().getVolumeManager();
      this.volMgr_ = mgr;
      if (this.volListening_) return;
      // 注：本机 SDK 中 streamVolumeChange 的签名与官方文档示例不一致，改用编译确认存在的 volumeChange
      mgr.on('volumeChange', (ev: audio.VolumeEvent) => {
        // 不依赖事件字段（避免版本差异），直接重读系统音量同步 UI
        try {
          if (this.maxVol_ > 0 && this.gm_ !== 'volume') {
            // ⭐ 音量滑动手势进行中不重读/重置基准 sv：否则每次 move 都用总位移 dy 从已调整的基准叠加，
            //    越滑越快（轻滑即满/0）。手势由 onTM 的 sv+dy 全权控制；手势外（音量键/结束）才同步
            const sysVol: number = this.volMgr_?.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC) ?? 0;
            this.vol = Math.min(1, Math.max(0, sysVol / this.maxVol_));
            this.sv = this.vol;
            AppStorage.setOrCreate('globalVolume', this.vol);
          }
        } catch (_e2) {}
      });
      this.volListening_ = true;
    } catch (_e) {}
  }

  /** ⭐ 注销系统音量变化监听 */
  private unregisterVolumeListener(): void {
    try {
      if (this.volMgr_ && this.volListening_) {
        this.volMgr_.off('volumeChange');
        this.volListening_ = false;
      }
    } catch (_e) {}
  }

  private initSwipeControl(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.screenW = this.getUIContext().px2vp(d.width);
      this.screenH_ = this.getUIContext().px2vp(d.height);
    } catch (_e) {
      this.screenW = 360;
      this.screenH_ = 720;
    }
  }

  // ==================== 手势系统（onVT 风格） ====================

  // ── 卡片样式辅助 ──
  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  @State private gestureHintMotion: AdjustmentMotion = { sequence: 0, delta: 0, velocity: 0 };
  private levelInputTotal: number = 0;
  private levelInputAt: number = 0;

  private sampleLevelInput(total: number): void {
    const now: number = Date.now();
    const delta: number = this.gestureHintActive ? total - this.levelInputTotal : total;
    const elapsed: number = this.gestureHintActive ? Math.max(16, now - this.levelInputAt) : 16;
    this.levelInputTotal = total;
    this.levelInputAt = now;
    this.gestureHintMotion = { sequence: this.gestureHintMotion.sequence + 1,
      delta: delta, velocity: delta * 1000 / elapsed };
  }

  private sGH(txt: string, progress: number = -1, type: string = ''): void {
    this.gestureHintMainText = txt;
    this.showGestureHint = true;
    this.gestureHintProgress = progress;
    this.gestureHintType = type;
    this.gestureHintActive = true;
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = -1;
  }

  private finishLevelGesture(): void {
    this.gestureHintActive = false;
    if (!this.showGestureHint) return;
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = setTimeout(() => {
      this.showGestureHint = false;
      this.gt_ = -1;
    }, 900);
  }

  private triggerHaptic(): void {
    VibrateUtils.vibratePreset('haptic.notification.trigger');
  }

  /** 音量条贴播放区左边、亮度条贴播放区右边；横屏时不能按整窗宽度算 */
  private gestureHintX(): number {
    if (!this.landscapeLayout()) {
      return this.gestureHintType === 'volume' ? 28 : Math.max(28, this.viewportWidth - 92);
    }
    const left = this.landscapePlayerX();
    return this.gestureHintType === 'volume' ? left + 28
      : Math.max(left + 28, left + this.landscapePlayerWidth() - 92);
  }

  private fireHaptic(duration: number): void {
    VibrateUtils.vibrateTime(duration);
  }

  private onVT = (e: TouchEvent) => {
    switch (e.type) {
      case TouchType.Down:
        this.onTD(e);
        break;
      case TouchType.Move:
        this.onTM(e);
        break;
      case TouchType.Up:
        this.onTU(e);
        break;
      case TouchType.Cancel:
        this.onTC();
        break;
    }
  }

  private onTD(e: TouchEvent): void {
    if (e.touches.length === 0 || this.showPlaybackSettings || this.showQualityPicker || this.switchingRoom || this.roomAnimating) return;
    this.touchActive = true;
    this.lastDx = 0;
    this.lastDy = 0;
    this.gm_ = '';
    logInfo(`[LivePlayer] onTD: type=${e.type} pos=(${e.touches[0].windowX.toFixed(0)},${e.touches[0].windowY.toFixed(0)})`);
    const t = e.touches[0];
    this.sx_ = t.windowX;
    this.sy_ = t.windowY;
    this.sv = this.vol;
    this.sb = this.bri;
    this.ml_ = false;
    this.la_ = false;
    this.dtp_ = false;

    if (this.dt_ !== -1) {
      this.cancelPendingTap();
      this.dtp_ = true;
    }

    // 长按定时器
    this.lt_ = setTimeout(() => {
      if (!this.ml_) {
        this.la_ = true;
      }
    }, 500);
  }

  private onTM(e: TouchEvent): void {
    if (e.touches.length === 0 || this.showPlaybackSettings || this.showQualityPicker || this.switchingRoom || this.roomAnimating) return;
    const t = e.touches[0];
    const dx = t.windowX - this.sx_;
    const dy = this.sy_ - t.windowY;
    this.lastDx = dx;
    this.lastDy = dy;
    const adx = Math.abs(dx);
    const ady = Math.abs(dy);
    if (adx > 10 || ady > 10) {
      this.ml_ = true;
      this.cancelPendingTap();
      this.dtp_ = false;
      if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    }
    if (this.la_) return;
    if (this.gm_ === '') {
      if (adx > 25 || ady > 25) {
        if (adx > ady * 1.2) {
          this.gm_ = 'horizontal';
        } else if (ady > adx * 1.2 && this.portraitWindow()) {
          this.gm_ = 'room';
        } else if (ady > adx * 1.2) {
          // 垂直滑动：左半 = 亮度，右半 = 音量。
          // ⚠️ 横屏分栏的播放区只占窗口一部分（比例可拖、还能换到右侧），分界取播放视口中线；
          //    全屏时播放区已展开到整窗，playerX+width/2 退化为屏幕中线，与原来一致。
          const centerX = this.landscapeLayout()
            ? this.landscapePlayerX() + this.landscapeViewportWidth() / 2
            : this.screenW / 2;
          if (t.windowX < centerX) {
            this.gm_ = 'brightness';
          } else {
            this.gm_ = 'volume';
          }
        }
      }
    }
    if (this.gm_ === 'room') {
      this.roomSlideDirection = dy >= 0 ? 1 : -1;
      this.prepareAdjacentRoom(this.roomSlideDirection);
      const height = this.viewportHeight || this.screenHv();
      const atStart = this.roomIds.indexOf(this.roomId) <= 0 && dy < 0;
      this.roomOffset = Math.max(-height, Math.min(height, -dy / (atStart ? 4 : 1)));
    } else if (this.gm_ === 'volume') {
      const volSensitivity: number = 400;
      let v = this.sv + dy / volSensitivity;
      v = Math.min(1, Math.max(0, v));
      this.vol = v;
      AppStorage.setOrCreate('globalVolume', v);
      this.setSystemVolume(v);
      this.sampleLevelInput(dy / volSensitivity);
      this.sGH(`${Math.round(v * 100)}%`, v, 'volume');
      const volPct = Math.round(v * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(volPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = volPct;
      }
    } else if (this.gm_ === 'brightness') {
      const briSensitivity: number = 400;
      let b = this.sb + dy / briSensitivity;
      b = Math.min(1, Math.max(0, b));
      this.bri = b;
      window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((w: window.Window) => {
        w.setWindowBrightness(b);
      });
      this.sampleLevelInput(dy / briSensitivity);
      this.sGH(`${Math.round(b * 100)}%`, b, 'brightness');
      const briPct = Math.round(b * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(briPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = briPct;
      }
    }
  }

  private onTU(e: TouchEvent): void {
    if (!this.touchActive) return;
    this.touchActive = false;
    this.finishLevelGesture();
    const wasLongPress = this.la_;
    const wasMoved = this.ml_;

    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    this.la_ = false;

    if (this.showPlaybackSettings || this.showQualityPicker) { this.onTC(); return; }
    if (this.gm_ === 'room' && Math.abs(this.lastDy) >= 80) {
      void this.switchRoom(this.lastDy > 0 ? 1 : -1);
    } else if (this.gm_ === 'room') {
      void this.animateRoomOffset(0);
    }
    if (!wasMoved && !wasLongPress && !this.switchingRoom && !this.roomAnimating) {
      if (this.dtp_) {
        this.togglePlayPause();
      } else {
        this.dt_ = setTimeout(() => {
          this.dt_ = -1;
          if (!this.disposed && !this.pageHidden && !this.showPlaybackSettings && !this.showQualityPicker) {
            // 横屏分栏/全屏的控件层与竖屏浮层一样，单击整体显隐
            this.settleInformation(!this.informationVisible);
          }
        }, 250);
      }
    }
    this.gm_ = '';
    this.ml_ = false;
  }

  private cancelPendingTap(): void {
    clearTimeout(this.dt_);
    this.dt_ = -1;
  }

  private onTC(): void {
    this.touchActive = false;
    this.finishLevelGesture();
    this.cancelPendingTap();
    this.dtp_ = false;
    if (this.gm_ === 'room' && !this.switchingRoom) void this.animateRoomOffset(0);
    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    this.la_ = false;
    this.gm_ = '';
    this.ml_ = false;
  }

  // ==================== 屏幕旋转控制 ====================

  private rotationOrientation(): window.Orientation {
    switch (this.rotationMode) {
      case 'system': return window.Orientation.AUTO_ROTATION_RESTRICTED;
      case 'auto': return window.Orientation.AUTO_ROTATION;
      case 'portrait': return window.Orientation.PORTRAIT;
      default: return window.Orientation.AUTO_ROTATION_LANDSCAPE;
    }
  }

  /** 应用当前旋转模式到窗口 */
  private async applyRotationMode(): Promise<void> {
    if (!this.mw) return;
    try {
      await this.mw.setPreferredOrientation(this.rotationOrientation());
    } catch (_e) {
      logError(`[LivePlayer] 旋转模式应用失败: ${_e}`);
    }
  }

  @Builder
  /** 直播操作按钮：与顶部按钮同一套玻璃材质（HeaderGlassControl 40×40 图标钮） */
  private LiveAction(icon: Resource, label: string, action: () => void) {
    Column() {
      HeaderGlassControl({ label: label, controlId: 'live-action-' + label, onActivate: action }) {
        Image(icon).width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
      }
    }.width(40).height(40)
  }

  @Builder
  private AnchorIdentity(details: boolean, maxWidth: number) {
    Row({ space: 8 }) {
      if (this.anchorFace) { Image(this.anchorFace).width(36).height(36).borderRadius(18) }
      Column({ space: 3 }) {
        Text(this.uname || '直播间').fontSize(14).fontColor('#FFFFFF').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (details) { Text(`${formatOnlineCount(this.online)} 人气`).fontSize(10).fontColor('#CCCCCC') }
      }.alignItems(HorizontalAlign.Start).constraintSize({ maxWidth: maxWidth })
    }.padding({ left: 5, right: 14, top: 5, bottom: 5 })
    .backgroundColor('#66282A33').borderRadius(24)
  }

  /** 横屏面板只有一列宽，主播胶囊不能按整窗 260 取值 */
  private overlayIdentityMaxWidth(): number {
    return this.portraitWindow() ? 150 : 260;
  }

  /** 弹幕只在竖屏画面浮层；横屏统一放详情 tab（受面板实测高度约束） */
  private chatOverlayMode(): boolean {
    return !this.landscapeLayout();
  }

  private chatMaxHeight(): number {
    if (!this.chatOverlayMode()) {
      return Math.max(60, this.chatSlotHeight || this.landscapePanelHeight() * 0.5);
    }
    return Math.max(40, (this.viewportHeight || this.screenHv()) * 0.32);
  }

  private chatMessageLimit(): number {
    const height = this.chatMaxHeight();
    return Math.max(1, Math.min(12, Math.floor((height - (this.liveChatStatus ? 32 : 0)) / 48)));
  }

  private visibleLiveChatMessages(): LiveChatMessage[] {
    return this.liveChatMessages.slice(-this.chatMessageLimit());
  }

  @Builder
  private LiveChatInformation(themed: boolean) {
    Column({ space: 5 }) {
      ForEach(this.visibleLiveChatMessages(), (message: LiveChatMessage) => {
        Text() {
          Span(`${message.nickname}：`).fontColor(message.nameColor)
          Span(message.text).fontColor(themed ? this.panelPrimaryColor() : '#FFFFFF')
        }.fontSize(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(themed ? this.panelChatBubbleColor() : '#6630323A').borderRadius(15)
        .constraintSize({ maxWidth: '100%' })
      }, (message: LiveChatMessage) => message.id)
      if (this.liveChatStatus) {
        Text(this.liveChatStatus).fontSize(12).fontColor(themed ? this.panelMutedColor() : '#D2D3D8')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(themed ? this.panelChatBubbleColor() : '#6630323A').borderRadius(15)
      }
    }.alignItems(HorizontalAlign.Start)
    .width(this.chatOverlayMode() ? (this.portraitWindow() ? '86%' : '55%') : '100%')
    .constraintSize({ maxHeight: this.chatMaxHeight() })
    .clip(true).align(Alignment.BottomStart)
    .margin({ left: this.chatOverlayMode() ? 16 : 0, bottom: this.chatOverlayMode() ? 12 : 0 })
    .alignSelf(ItemAlign.Start)
    .id('live-chat-information').hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private MoreGlassButton() {
    Column() {
      HeaderGlassControl({ label: '更多', controlId: 'live-header-more', onActivate: () => this.openLiveMenu() }) {
        Image($r('app.media.ref_more')).width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
      }
    }.width(40).height(40)
  }

  /** 播放器顶栏（返回 + 更多）：竖屏浮层保留主播胶囊；横屏分栏的主播信息已在详情面板里，
   *  播放区不再重复放胶囊（普通页分栏顶栏同款）；全屏保留胶囊对应普通页全屏的标题位。 */
  @Builder
  private LiveInfoHeader(showAnchor: boolean) {
    Row({ space: 10 }) {
      HeaderBackButton({ iconColor: '#FFFFFF', onBack: () => this.handleHeaderBack() })
      if (showAnchor) {
        this.AnchorIdentity(true, this.overlayIdentityMaxWidth())
      }
      Blank()
      this.MoreGlassButton()
    }.width('100%')
    .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
  }

  /** 竖屏浮层底部：标题/房间号 + 操作行 */
  @Builder
  private LiveInfoFooter() {
    Column({ space: 10 }) {
      Text(this.title).fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Medium)
        .maxLines(2).width('100%')
      Text(`房间号 ${this.roomId}`).fontSize(12).fontColor('#BFC0C9').width('100%')
      this.LiveControlRow(false)
    }.width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: this.safeBottom + 12 })
    .backgroundColor('#40202430')
  }

  /** 播放/重置/画质操作行；横屏控件层额外带进/退全屏按钮（对齐普通横屏页底部控件行） */
  @Builder
  private LiveControlRow(landscape: boolean) {
    Row({ space: landscape ? 12 : 14 }) {
      Column() {
        HeaderGlassControl({ label: this.isPlaying ? '暂停' : '播放', controlId: 'live-play-pause',
          onActivate: () => this.togglePlayPause() }) {
          Image(this.isPlaying ? $r('app.media.ic_public_pause') : $r('app.media.ic_public_play'))
            .width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
        }
      }.width(40).height(40)
      this.LiveAction($r('app.media.reset_70'), '重置直播', () => this.resetLive())
      Blank()
      this.QualityLabel()
      this.FullscreenGlassButton(!landscape)
    }.width('100%').height(42)
    .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
  }

  /** 全屏入口：横屏切分栏/全屏；竖屏请求横屏并落到横屏全屏态（普通页 toggleFS 口径） */
  @Builder
  private FullscreenGlassButton(portrait: boolean) {
    Column() {
      HeaderGlassControl({ label: this.liveFullscreen ? '退出全屏' : '进入全屏',
        controlId: 'live-landscape-fullscreen',
        onActivate: () => { if (portrait) this.enterPortraitFullscreen(); else this.toggleLandscapeFullscreen(); } }) {
        Image(this.liveFullscreen ? $r('app.media.ref_apk_minimize') : $r('app.media.ref_fullscreen'))
          .width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
      }
    }.width(40).height(40)
  }

  @Builder
  private QualityLabel() {
    Text(this.availableQualities.find(q => q.qn === this.currentQn)?.label || getLiveQualityLabel(this.currentQn))
      .fontSize(13).fontColor('#FFFFFF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick(() => { this.showQualityPicker = true; })
      .id('live-quality-anchor')
      .bindMenu(this.showQualityPicker, this.LiveOptions('quality'),
        playbackMenuOptions(this.isDarkMode, () => { this.showQualityPicker = false; }))
  }

  /** 竖屏浮层：顶栏、弹幕、标题与操作行，单击整体显隐 */
  @Builder
  private RoomInformation() {
    Stack() {
      Column() {
        Column() {
          this.LiveInfoHeader(true)
        }.width('100%').padding({ left: 16, right: 12, top: this.safeTop + 8 })
        Blank()
        Column() {
          this.LiveChatInformation(false)
        }.width('100%')
        this.LiveInfoFooter()
      }.width('100%').height('100%')
      .id('live-information-layer')
      .opacity(1 - this.informationProgress)
      .hitTestBehavior(this.informationVisible ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
    }.width('100%').height('100%')
  }

  /** 横屏信息面板：详情 / 推荐 tab 走与普通页 ReferencePanel 同款 Swiper（380ms 自定义曲线 + 跟手指示器） */
  @Builder
  private LandscapeInformationPanel() {
    Column() {
      Row() {
        this.PanelTab('简介', 0)
        this.PanelTab('评论', 1)
      }.width('100%').height(46).padding({ left: 16, right: 16 })
      Row().width('100%').height(0.5).backgroundColor(this.panelDividerColor())
      Swiper(this.livePanelSwiper) {
        ForEach([0, 1], (page: number) => {
          Column() {
            if (page === 0) {
              this.LandscapeIntroTab()
            } else {
              this.LandscapeCommentTab()
            }
          }.width('100%').height('100%')
        }, (page: number) => page.toString())
      }
      .index(this.livePanelTab)
      .loop(false)
      .indicator(false)
      .cachedCount(1)
      .duration(HOME_CHANNEL_DURATION)
      .curve(HOME_CHANNEL_CURVE)
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .onContentDidScroll((_selected: number, index: number, position: number, _length: number) => {
        this.livePanelTabProgress = Math.max(0, Math.min(1, index - position));
      })
      .onChange((index: number) => {
        this.livePanelTab = index;
        this.livePanelTabProgress = index;
        this.lastPanelTabChangeAt = Date.now();
      })
    }
    .width('100%').height('100%')
    .backgroundColor(this.panelBgColor())
    .borderRadius({ topLeft: this.cardBorderRadius, topRight: this.cardBorderRadius,
      bottomLeft: this.cardBorderRadius, bottomRight: this.cardBorderRadius })
    .clip(true)
    .id('live-landscape-information-panel')
    .hitTestBehavior(this.landscapeExpandAmount() > 0.01 ? HitTestMode.None : HitTestMode.Default)
    .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
  }

  /** tab 文字/指示器随 Swiper 进度连续插值；点击走 changeIndex(index, true) 带动画 */
  @Builder
  private PanelTab(label: string, index: number) {
    Column({ space: 6 }) {
      Text(label).fontSize(14)
        .fontWeight(Math.abs(this.livePanelTabProgress - index) < 0.5 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(Math.abs(this.livePanelTabProgress - index) < 0.5 ? this.panelPrimaryColor() : this.panelMutedColor())
        .onAreaChange((_old: Area, area: Area) => { this.livePanelTabWidths[index] = Number(area.width); })
      Row().width(16).height(3).borderRadius(2)
        .backgroundColor(index === 0 ? '#D34E7E' : Color.Transparent)
        .translate({ x: index === 0 ? this.livePanelTabProgress * this.panelTabIndicatorTravel() : 0 })
    }.height(32).justifyContent(FlexAlign.End).margin({ right: 20 })
    .onClick(() => {
      if (this.livePanelTab === index) return;
      this.lastPanelTabChangeAt = Date.now();
      this.livePanelSwiper.changeIndex(index, true);
    })
    .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
  }

  /** 简介 tab：结构与普通播放页 ReferenceIntro 一致——头部主播信息（头像/名字/
   *  「N粉丝  N人气」，视频数换人气、bv 号位置换房间号），下面直接列直播推荐。 */
  @Builder
  private LandscapeIntroTab() {
    List() {
      ListItem() {
        Column() {
          // 主播信息行：照抄 ReferenceUpRow(false) 的尺寸与配色
          Row({ space: 10 }) {
            if (this.anchorFace) {
              Image(this.anchorFace).width(28).height(28).borderRadius(20)
                .objectFit(ImageFit.Cover).backgroundColor(this.panelCardColor()).draggable(false)
            }
            Column({ space: 3 }) {
              Text(this.uname || '直播间').fontSize(13).fontColor('#D34E7E').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${this.anchorFans > 0 ? formatOnlineCount(this.anchorFans) : '—'}粉丝  ${formatOnlineCount(this.online)}人气`)
                .fontSize(10).fontColor('#757A81').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').height(62).alignItems(VerticalAlign.Center)
          // 标题 + 房间号：普通简介页这里是可展开标题 + 统计行 + bv 号
          Column({ space: 7 }) {
            Text(this.title).fontSize(16).lineHeight(22).fontColor(this.panelPrimaryColor())
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            Text(`房间号 ${this.roomId}`).fontSize(10).fontColor('#757A81').maxLines(1).width('100%')
          }.width('100%').padding({ top: 10, bottom: 12 })
        }.width('100%').padding({ top: 8 })
      }.width('100%')
      // 与普通简介页一样，正文和推荐列表之间留一条短占位
      ListItem() { Column().width('100%').height(10) }
      // 直播推荐：与普通简介页相关视频列表同款 VideoListItem，宽度随面板实时变化
      ForEach(this.introRooms(), (room: LiveFeedRoom) => {
        ListItem() {
          Column() {
            VideoListItem({
              availableWidth: this.landscapePanelContentWidth(),
              title: room.title, cover: room.cover || '', duration: 0,
              owner: room.uname, playCount: -1,
              detailText: `${formatOnlineCount(room.online)}人气`,
              videoId: '', ownerMid: '',
              onActivate: () => {
                if (Date.now() - this.lastPanelTabChangeAt < 300) return;
                this.selectRecommendedRoom(room);
              }
            })
          }.width('100%').id('live-intro-room-' + room.roomId)
        }.width('100%')
      }, (room: LiveFeedRoom) => `${room.roomId}`)
      if (this.introRooms().length === 0) {
        ListItem() {
          Text('正在获取直播推荐…').fontSize(12).fontColor(this.panelMutedColor())
            .width('100%').padding({ top: 16, bottom: 16 })
        }
      }
      ListItem() { Column().width('100%').height(20) }
    }
    .id('live-landscape-intro')
    .width('100%').height('100%')
    .padding({ left: 12, right: 12 }).cachedCount(2).scrollBar(BarState.Off)
    .align(Alignment.TopStart).edgeEffect(EdgeEffect.None)
    .onReachEnd(() => { void this.loadLiveIntroRooms(false); })
    .onAppear(() => { if (this.liveIntroRooms.length === 0) void this.loadLiveIntroRooms(true); })
  }

  // 推荐卡片复用 components/VideoListItem：封面按可用宽度 40% 自适应、行高至少 98vp，
  // 标题/主播/人气各有独立行，窄面板下不会再互相挤压串行；空 videoId 会隐藏视频反馈三点菜单。

  /** 评论 tab：渲染全部弹幕历史（上限 LIVE_CHAT_LIMIT），持续刷新且旧消息不消失；
   *  列表可上下滑动，贴底时自动跟随最新，上滑翻历史不会被拉回。 */
  @Builder
  private LandscapeCommentTab() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ scroller: this.landscapeChatScroller }) {
        ForEach(this.liveChatMessages, (message: LiveChatMessage) => {
          ListItem() {
            // ListItem 默认把子组件水平居中；包一层满宽 Column 让气泡靠左（普通评论列表口径）
            Column() {
              Text() {
                Span(`${message.nickname}：`).fontColor(message.nameColor)
                Span(message.text).fontColor(this.panelPrimaryColor())
              }.fontSize(13).maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(this.panelChatBubbleColor()).borderRadius(12)
                .constraintSize({ maxWidth: '100%' })
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ bottom: 6 })
        }, (message: LiveChatMessage) => message.id)
        if (this.liveChatStatus) {
          ListItem() {
            Column() {
              Text(this.liveChatStatus).fontSize(12).fontColor(this.panelMutedColor())
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.panelChatBubbleColor()).borderRadius(12)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ bottom: 6 })
        }
        ListItem() { Column().width('100%').height(12) }
      }
      .id('live-landscape-comment-list')
      .width('100%').height('100%')
      .padding({ left: 12, right: 12, top: 8 })
      .cachedCount(2).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      .onScrollIndex((_start: number, end: number) => {
        this.chatFollowLatest = end >= this.liveChatMessages.length - 2;
      })
      if (!this.chatFollowLatest) {
        Text('回到最新').fontSize(12).fontColor('#FFFFFF')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#CC242629').borderRadius(16)
          .margin({ right: 16, bottom: 16 })
          .onClick(() => {
            this.chatFollowLatest = true;
            try { this.landscapeChatScroller.scrollEdge(Edge.Bottom); } catch (_e) {}
          })
      }
    }.width('100%').height('100%')
  }

  /**
   * 横屏控件层：全部叠在播放区（分栏与全屏同一套），单击整体显隐。
   * 全屏时系统状态栏隐藏 ⇒ 顶部补自绘「网速·时间·电量」条（普通页全屏同款）。
   */
  @Builder
  private LandscapePlayerControls() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.liveFullscreen) {
          PlayerStatusStrip()
        }
        Column() {
          this.LiveInfoHeader(this.liveFullscreen)
        }.width('100%')
        .padding({ left: this.liveFullscreen ? 18 : 12, right: this.liveFullscreen ? 18 : 12,
          top: this.liveFullscreen ? 20 : 12, bottom: 12 })
        // 普通页分栏顶栏（ReferenceTopBar）没有渐变底板；只有全屏档才压一层顶部渐变
        .linearGradient({ direction: GradientDirection.Bottom,
          colors: [[this.liveFullscreen ? '#66000000' : '#00000000', 0], ['#00000000', 1]] })
      }.width('100%')
      Blank().layoutWeight(1)
      Column() {
        this.LiveControlRow(true)
      }.width('100%')
      .padding({ left: this.liveFullscreen ? 18 : 12, right: this.liveFullscreen ? 18 : 12,
        top: 14, bottom: this.liveFullscreen ? 20 : 12 })
      // 底部控件不加实色/渐变底板：普通页 ReferenceLandscapeBottomControls 只留 padding，
      // 按钮靠自身玻璃材质浮在画面上，播放区与屏幕底边之间不留遮罩带
    }
    .width('100%').height('100%')
    .clip(true)
    .id('live-landscape-player-controls')
    .opacity(1 - this.informationProgress)
    .hitTestBehavior(this.informationVisible ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
  }

  private menuTextColor(): string { return this.isDarkMode ? '#EEEFF1' : '#18191C'; }

  private liveRowWidth(): number {
    const width = this.landscapeLayout() ? this.landscapeMenuDockWidth() : (this.viewportWidth || this.screenWv());
    return Math.max(0, width - 28);
  }

  private liveOptionLabels(kind: string): string[] {
    if (kind === 'quality') return this.availableQualities.map((item: QualityOption) => item.label);
    if (kind === 'scale') return ['完整显示', '裁切铺满'];
    return ['仅 9:16 竖屏直播', '所有竖屏直播'];
  }

  private liveSelectedLabel(kind: string): string {
    if (kind === 'quality') return this.availableQualities.find((item: QualityOption) => item.qn === this.currentQn)?.label || getLiveQualityLabel(this.currentQn);
    if (kind === 'scale') return this.portraitScale === 'fill' ? '裁切铺满' : '完整显示';
    return this.portraitScaleScope === 'all' ? '所有竖屏直播' : '仅 9:16 竖屏直播';
  }

  private chooseLiveOption(kind: string, index: number): void {
    this.liveDropdown = false;
    this.showQualityPicker = false;
    if (kind === 'quality') {
      const quality = this.availableQualities[index];
      if (quality && quality.qn !== this.currentQn) this.switchQuality(quality.qn);
    } else if (kind === 'scale') { void this.setPortraitScale(index === 0 ? 'auto' : 'fill'); }
    else { void this.setPortraitScaleScope(index === 0 ? 'standard' : 'all'); }
  }

  private liveDropdownOptions(): MenuOptions {
    return playbackMenuOptions(this.isDarkMode, () => { this.liveDropdown = false; });
  }

  @Builder
  private LiveOptions(kind: string) {
    Menu() {
      ForEach(this.liveOptionLabels(kind), (label: string, index: number) => {
        MenuItem({ content: label, endIcon: this.liveSelectedLabel(kind) === label ?
          (this.isDarkMode ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.menuTextColor()).height(52).id(`live-menu-option-${kind}-${index}`)
          .onClick(() => this.chooseLiveOption(kind, index))
      }, (label: string) => label)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: this.isDarkMode ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  @Builder
  private LiveChoiceRow(icon: Resource, title: string, kind: string) {
    PlaybackMenuRow({ rowWidth: this.liveRowWidth(), rowId: `live-menu-${kind}`, icon: icon, title: title,
      detail: this.liveSelectedLabel(kind),
      onActivate: () => { this.liveChoice = kind; this.liveDropdown = true; }
    }).bindMenu(this.liveDropdown && this.liveChoice === kind, this.LiveOptions(kind), this.liveDropdownOptions())
  }

  @Builder
  private ShareChannel() {
    Column({ space: 10 }) {
      NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true,
        capsuleWidth: 42, capsuleHeight: 42, onActivate: () => { void this.shareLiveRoom(); } }) {
        Image($r('app.media.ref_share')).width(24).height(24).fillColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
      }
      Text('系统分享').fontSize(11).fontColor(this.menuTextColor()).maxLines(1)
    }.layoutWeight(1).id('live-system-share')
  }

  @Builder
  private MenuShortcut(icon: Resource, label: string, action: () => void) {
    Column({ space: 10 }) {
      NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: 42, capsuleHeight: 42, onActivate: action }) {
        PlaybackMenuIcon({ icon: icon, iconSize: 26 })
      }
      Text(label).fontSize(11).fontColor(this.menuTextColor()).maxLines(1)
    }.layoutWeight(1).id('live-menu-shortcut-' + label)
  }

  @Builder
  private PlaybackSettingsContent() {
    Column({ space: 0 }) {
      if (this.liveMenuPanel === 'share') {
        if (this.landscapeLayout()) {
          // 横屏菜单只占信息面板一列宽，六个入口分两排，胶囊不再互相压住
          Column({ space: 6 }) {
            Row() {
              this.ShareChannel()
              this.MenuShortcut($r('app.media.ref_ps_settings'), '播放设置', () => { this.liveMenuPanel = 'playback'; })
              this.MenuShortcut($r('app.media.live_menu_consumption'), '消费管理', () => this.unavailableLiveAction('当前客户端暂不支持直播消费管理'))
            }.width('100%')
            Row() {
              this.MenuShortcut($r('app.media.live_menu_effects'), '隐藏特效', () => this.unavailableLiveAction('当前播放器未展示礼物特效'))
              this.MenuShortcut($r('app.media.ref_ps_cast'), '投屏', () => this.unavailableLiveAction('当前客户端暂不支持直播投屏'))
              this.MenuShortcut($r('app.media.ref_ps_report'), '举报', () => this.unavailableLiveAction('请在哔哩哔哩官方直播间内提交举报'))
            }.width('100%')
          }.width('100%').padding({ left: 8, right: 8, top: 16, bottom: 10 })
        } else {
          Row() {
            this.ShareChannel()
            this.MenuShortcut($r('app.media.ref_ps_settings'), '播放设置', () => { this.liveMenuPanel = 'playback'; })
            this.MenuShortcut($r('app.media.live_menu_consumption'), '消费管理', () => this.unavailableLiveAction('当前客户端暂不支持直播消费管理'))
            this.MenuShortcut($r('app.media.live_menu_effects'), '隐藏特效', () => this.unavailableLiveAction('当前播放器未展示礼物特效'))
            this.MenuShortcut($r('app.media.ref_ps_cast'), '投屏', () => this.unavailableLiveAction('当前客户端暂不支持直播投屏'))
            this.MenuShortcut($r('app.media.ref_ps_report'), '举报', () => this.unavailableLiveAction('请在哔哩哔哩官方直播间内提交举报'))
          }.width('100%').padding({ left: 8, right: 8, top: 20, bottom: 14 })
        }
      } else {
        Row({ space: 12 }) {
          Row() {
          NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true,
            capsuleWidth: 40, capsuleHeight: 40, onActivate: () => { this.liveMenuPanel = 'share'; } }) {
            Image($r('app.media.ref_back')).width(22).height(22).fillColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
          }
          }.id('live-menu-back')
          Text('播放设置').fontSize(16).fontColor(this.menuTextColor()).fontWeight(FontWeight.Medium).layoutWeight(1)
          NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: 64, capsuleHeight: 36, onActivate: () => { this.showPlaybackSettings = false; } }) {
            Text('完成').fontSize(14).fontColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').padding({ left: 14, right: 14, top: 14, bottom: 16 })
        if (this.portraitRoom() && !this.landscapeLayout()) {
          Column({ space: 8 }) {
            this.LiveChoiceRow($r('app.media.ref_ps_settings'), '竖屏直播画面', 'scale')
            this.LiveChoiceRow($r('app.media.ref_ps_settings'), '生效范围', 'scope')
          }.width('100%').margin({ bottom: 16 })
        }
        Column() {
          PlaybackMenuRow({ rowWidth: this.liveRowWidth(), rowId: 'live-menu-background', icon: $r('app.media.ref_ps_headphones'),
            title: '后台播放', isToggle: true, checked: this.bgp,
            onToggle: (enabled: boolean) => { if (enabled !== this.bgp) this.toggleBackgroundPlayback(); } })
        }.width('100%').margin({ bottom: 14 })
      }
    }.width('100%').padding({ bottom: this.landscapeLayout() ? 14 : this.safeBottom + 12 })
      .onAreaChange((_old: Area, area: Area) => {
        const height = Number(area.height);
        if (height > 0 && Math.abs(height - this.liveMenuHeight) > 0.5) this.liveMenuHeight = height;
      })
  }

  @Builder
  private PlaybackSettings() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.liveMenuHeight > 0) {
        CommentMenuSurface({ surfaceWidth: this.settingsSurfaceWidth(), surfaceHeight: this.liveMenuHeight,
          radius: 24, interactive: false, followTouchLight: true }) {
          this.PlaybackSettingsContent()
        }
      } else {
        this.PlaybackSettingsContent()
      }
    }.width(this.landscapeLayout() ? this.landscapeMenuDockWidth() : '100%')
      // Edges 定位：分栏贴播放区右下、全屏沿收起态面板位
      .position({ left: this.landscapeLayout() ? this.landscapeMenuDockX() : 0, bottom: 0 })
      .zIndex(25)
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 240, curve: Curve.EaseOut }))
  }

  private settingsSurfaceWidth(): number {
    return this.landscapeLayout() ? this.landscapeMenuDockWidth() : (this.viewportWidth || this.screenWv());
  }

  // ==================== build ====================

  @Builder
  private LiveRoomViewport() {
    Stack() {
      Stack() {
        // 加载中
        if (this.loading) {
          Column() {
            LoadingProgress().width(48).height(48).color('#FFFFFF')
            Text('加载直播...').fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#000000')
        }

        // 错误提示（仅当无视频源时显示）
        if (this.errorMsg && !this.videoSrc) {
          Column() {
            Text('⚠️').fontSize(48).fontColor('#FF6600')
            Text(this.errorMsg).fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
            Text('点击返回').fontSize(14).fontColor('#007DFF').margin({ top: 24 })
              .onClick(() => this.goBack())
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#000000')
        }
      }
      // 横屏分栏时加载/错误只占播放区，不再铺到信息面板底下
      .width(this.landscapeLayout() ? this.landscapePlayerWidth() : '100%')
      .height('100%')
      .position({ x: this.landscapeLayout() ? this.landscapePlayerX() : 0, y: 0 })

      // 横屏控件统一叠在播放区（分栏与全屏同一套，支持显隐）
      if (!this.landscapeLayout()) {
        this.RoomInformation()
      }
    }.width('100%').height('100%').clip(true)
  }

  private slotWidth(slot: number): number {
    if (slot === this.activeSlot) return this.videoW();
    if (this.landscapeLayout()) return this.landscapeMediaWidth(this.previewWidth, this.previewHeight);
    const sw = this.viewportWidth || this.screenWv();
    const sh = this.viewportHeight || this.screenHv();
    const ratio = this.previewWidth / this.previewHeight;
    const fill = ratio < 1 && this.portraitWindow() && this.portraitScale === 'fill'
      && (this.portraitScaleScope === 'all' || Math.abs(ratio / (9 / 16) - 1) <= 0.001);
    return fill ? Math.max(sw, sh * ratio) : Math.min(sw, sh * ratio);
  }

  private slotHeight(slot: number): number {
    if (slot === this.activeSlot) return this.videoH();
    return this.slotWidth(slot) * this.previewHeight / Math.max(1, this.previewWidth);
  }

  private slotLeft(slot: number): number {
    if (slot === this.activeSlot) return this.videoLeft();
    if (this.landscapeLayout()) return this.landscapeMediaX(this.previewWidth, this.previewHeight);
    const sw = this.viewportWidth || this.screenWv();
    return (sw - this.slotWidth(slot)) / 2;
  }

  private slotTop(slot: number): number {
    if (slot === this.activeSlot) return this.videoTop();
    if (this.landscapeLayout()) return this.landscapeMediaY(this.previewWidth, this.previewHeight);
    const sh = this.viewportHeight || this.screenHv();
    return this.portraitWindow() && this.previewWidth >= this.previewHeight
      ? Math.max(this.safeTop + 86, sh * 0.237) : (sh - this.slotHeight(slot)) / 2;
  }

  private slotHasCurrentFrame(slot: number): boolean {
    // Read observed readiness before the plain player reference. On the first build
    // av is null; short-circuiting there leaves the opaque mask unsubscribed forever.
    if (slot === this.activeSlot) return this.activeFrameReady && this.av !== null;
    const adjacentRoom = this.roomIds[this.roomIds.indexOf(this.roomId) + this.roomSlideDirection];
    return this.previewReady && this.previewAV !== null && this.previewRoomId === adjacentRoom;
  }

  @Builder
  private LiveVideoSlot(slot: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      // 两个 Surface 始终位于同一节点；交换角色不更换控制器、不重建组件。
      XComponent({ id: slot === 0 ? 'live_video_xc' : 'live_video_spare',
        type: XComponentType.SURFACE, controller: slot === 0 ? this.xc : this.spareXc })
        .width(this.slotWidth(slot)).height(this.slotHeight(slot))
        .position({ x: this.slotLeft(slot), y: this.slotTop(slot) })
        .borderRadius(this.landscapeLayout() ? (this.liveFullscreen ? 0 : this.cardBorderRadius) : 0)
        .clip(true)
        .hitTestBehavior(HitTestMode.None)
      // Surface 复用后仍可能持有旧房间末帧；只有对应播放器的首帧能解除实色遮挡。
      if (!this.slotHasCurrentFrame(slot)) {
        Column().width('100%').height('100%').backgroundColor('#000000')
          .hitTestBehavior(HitTestMode.None)
      }
      if (slot === this.activeSlot) {
        this.LiveRoomViewport()
      } else if (!this.slotHasCurrentFrame(slot)) {
        Column({ space: 14 }) {
          LoadingProgress().width(36).height(36).color('#FFFFFF')
          Text('加载直播…').fontSize(14).fontColor('#CCCCCC')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#000000')
      }
    }.width('100%').height('100%').backgroundColor('#000000').clip(true)
    .translate({ y: slot === this.activeSlot ? this.roomOffset
      : this.roomOffset + this.roomSlideDirection * (this.viewportHeight || this.screenHv()) })
    .hitTestBehavior(slot === this.activeSlot ? HitTestMode.Default : HitTestMode.None)
  }



  build() {
    Stack() {
      this.LiveVideoSlot(0)
      this.LiveVideoSlot(1)

      // 横屏：播放区承载全部控件（可显隐），另一栏是详情/推荐 tab 面板，中间分界柄可调大小、可拖入全屏
      if (this.landscapeLayout()) {
        SplitPaneLayout({
          primary: () => { this.LandscapePlayerControls() },
          secondary: () => { this.LandscapeInformationPanel() },
          primaryWidth: this.landscapePlayerWidth(),
          primaryHeight: this.landscapeAreaHeight(),
          primaryX: this.landscapePlayerX(),
          primaryY: this.landscapeAreaTop(),
          secondaryWidth: this.landscapePanelWidth(),
          secondaryHeight: this.landscapePanelHeight(),
          secondaryX: this.landscapePanelX(),
          secondaryY: this.landscapePanelTop(),
          showHandle: !this.liveFullscreen,
          swapped: this.landscapeSwapped(),
          dividerTop: this.landscapeAreaTop(),
          dividerHeight: this.landscapeAreaHeight(),
          handleId: 'live-landscape-resize-handle',
          handleLabel: '拖动调节直播画面与信息区大小',
          onResizeStart: () => this.beginLandscapeResize(),
          onResizeUpdate: (offset: number) => this.landscapeResize(offset),
          onResizeEnd: (offset: number, cancelled: boolean) => this.finishLandscapeResize(offset, cancelled)
        })
      }

      if (this.showBottomHint) {
        Text(this.bottomHintText).fontSize(14).fontColor('#FFFFFF')
          .padding(12).backgroundColor('#CC24242B').borderRadius(12)
          .position({ bottom: this.safeBottom + 84 }).zIndex(40)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.showPlaybackSettings) {
        Column().width('100%').height('100%').backgroundColor('#44000000')
          .onClick(() => { this.showPlaybackSettings = false; })
        this.PlaybackSettings()
      }

      // 与视频播放共用液面/光点，左右均落在手指反侧。
      if (this.showGestureHint) {
        Column() {
          PlayerLevelBar({ progress: this.gestureHintProgress, kind: this.gestureHintType,
            adjusting: this.gestureHintActive, adjustmentMotion: this.gestureHintMotion, headphones: this.outputUsesHeadphones,
            headphoneIcon: this.outputHeadphoneIcon })
        }
        .position({
          x: this.gestureHintX(),
          y: Math.max(0, (this.viewportHeight - 144) / 2)
        })
        .transition(TransitionEffect.OPACITY)
        .hitTestBehavior(HitTestMode.None)
        .zIndex(10)
      }


    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .clip(true)
    .onAreaChange((_old, area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      const wasLandscape = this.landscapeLayout();
      // 全屏横向锁定期间不跟随物理旋转换布局：方向锁只会在两个横屏之间切换，
      // 手机转到竖屏方向不应把全屏页重置成竖屏。系统若仍短暂下发竖屏视口
      // （折叠屏 / 分屏边界），重新锁回横屏并保留原横屏几何与全屏态。
      if (this.liveFullscreenLocked && !this.pendingLandscapeFullscreen) {
        if (width < height) {
          try {
            if (this.mw) this.mw.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE).catch(() => {});
          } catch (_e) {}
          return;
        }
        this.viewportWidth = width;
        this.viewportHeight = height;
        return;
      }
      this.viewportWidth = width;
      this.viewportHeight = height;
      if ((width > height) !== wasLandscape) {
        clearTimeout(this.fullscreenExitTimer);
        this.fullscreenExitTimer = -1;
        // 旋转会换一套布局：拖动进度、全屏都是横屏临时态，不跨方向保留。
        this.landscapeExpand = 0;
        this.liveFullscreen = false;
        this.chatSlotHeight = 0;
        this.informationVisible = this.defaultInformationVisible();
        this.informationProgress = this.informationVisible ? 0 : 1;
        if (width > height && this.pendingLandscapeFullscreen) {
          // 竖屏点「全屏」→ 请求横屏完成：直接落到横屏全屏纯净观看态
          this.pendingLandscapeFullscreen = false;
          this.landscapeExpand = 1;
          this.liveFullscreen = true;
          this.informationVisible = false;
          this.informationProgress = 1;
        }
        // 分栏显示系统状态栏、竖屏/全屏隐藏：随新方向重新下发（同时刷新状态栏高度测量）
        this.applySystemBars();
      }
    })
    .onTouch(this.onVT)
  }
}
