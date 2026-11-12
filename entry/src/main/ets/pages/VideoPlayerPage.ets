import { ijkPlaybackRequested, supportsIjkPlayback, createPlaybackPlayer } from '../services/PlaybackFactory';
import { IjkPlaybackPlayer } from '../services/IjkPlaybackPlayer';
import { IjkWarmPool, IjkWarmTake } from '../services/IjkWarmPool';
import { PlaybackStallMonitor } from '../utils/PlaybackStallMonitor';
import type { PlaybackPlayer } from '../services/PlaybackPlayer';
import { AdjustmentMotion } from '../controlcenter/model/AdjustmentMotion';
import { PlaybackAudioOutputMonitor } from '../utils/PlaybackAudioOutput';
import { PlaybackMenuRow } from '../components/PlaybackMenuRow';
import { PlaybackControlSurface } from '../components/PlaybackControlSurface';
import { PlaybackGlassAction } from '../components/PlaybackGlassAction';
import { canDecodePlayUrl, selectDecodablePlayUrl } from '../services/PlaybackCodecSupport';
import { FollowGlassButton } from '../components/FollowGlassButton';
import { FeedAvatarImage } from '../components/FeedAvatarImage';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NativeComposerSurface } from '../components/NativeComposerSurface';
import Animator from '@ohos.animator';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { NativeGlassInput } from '../components/NativeGlassInput';
import { FloatingCommentEntry } from '../components/FloatingCommentEntry';
import { PageWallpaper } from '../components/PageWallpaper';
import { PageHeader } from '../components/PageHeader';
import { AppContinuation, ContinuationPage } from '../services/AppContinuation';
import { DanmakuInputBar } from '../components/DanmakuInputBar';
import { FloatingVideoTransition, FloatingVideoRect } from '../services/FloatingVideoTransition';
import { FloatingPiP } from '../services/FloatingPiP';
import { FloatingVideoSurface } from '../services/FloatingVideoSurface';
import { VideoListItem } from '../components/VideoListItem';
import { VideoCardMoreButton } from '../components/VideoCardMoreButton';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { ReferencePortraitSettings } from '../components/ReferencePortraitSettings';
import { getStoryRecommendVideos } from '../api/StoryRecommendApi';
import { ContinuousRecommendationState } from '../services/ContinuousRecommendationState';
import { PlaybackListPrefetch } from '../services/PlaybackListPrefetch';
import { startupPlaybackStrategy } from '../services/PlayerStartupPolicy';
import { ReferenceFeedGestures } from '../utils/ReferenceFeedGestures';
import { HOME_CHANNEL_CURVE, HOME_CHANNEL_DURATION } from '../utils/HomeChannelMotion';
import { VideoInteractionResult } from '../api/VideoInteractionApi';
// VideoPlayerPage.ets
import { router, curves, SegmentButton, SegmentButtonOptions, componentUtils, display, KeyboardAvoidMode, LengthMetrics, AnimatorResult } from '@kit.ArkUI';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { getVideoIntroCard, getVideoIntroTags, VideoIntroCard, VideoIntroTag, getVideoPlayUrl, invalidatePlayUrlCache, PlayUrlResult, getVideoDetail, getVideoComments, getCommentReplies, VideoDetail, VideoDetailOwner, VideoDetailStat, CommentItem, getVideoUserStatus, VideoPageItem, getFollowStatus, modifyFollow, clearFollowedMidsCache, getUserInfo, UserInfo, getPgcPlayUrl, getPgcSeasonInfo, getPgcEpisodeInfo, getPgcSeasonInfoByEpId, PgcSeasonInfo, PgcEpisode, getRelatedVideos, getRecommendVideos, addVideoComment, uploadCommentImage, sendDanmakuVideo, SeasonEpisode, SeasonSection, UgcSeason } from '../api/BilibiliApi';
import { CommentInputBar, CommentImageDraft, CommentInputBarCtrl } from '../components/CommentInputBar';
import { RecommendItem } from '../model/RecommendItem';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { VibrateUtils } from '../utils/VibrateUtils';
import { MaterialUtil } from '../utils/MaterialUtil';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import deviceInfo from '@ohos.deviceInfo';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import AVCastPicker from '@ohos.multimedia.avCastPicker';
import { AVCastPickerState } from '@ohos.multimedia.avCastPickerParam';
import { motion } from '@kit.MultimodalAwarenessKit';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import { http } from '@kit.NetworkKit';
import { VideoControls } from '../components/VideoControls';
import { playbackHdrUiRatio, playbackHdrUiFilter } from '../utils/PlaybackHdrUi';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { FullscreenVideoTransform, VideoTransformPoint } from '../utils/FullscreenVideoTransform';

import { predecodeImage, getCachedPixelMap, clearImageCache } from '../utils/ImageCache';
import { image } from '@kit.ImageKit';
import { WatchHistoryHelper, MIN_HEARTBEAT_PROGRESS_SEC } from '../model/WatchHistoryHelper';
import { WatchHistoryItem } from '../model/WatchHistoryItem';
import { PlaybackProgress } from '../utils/PlaybackProgress';
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';
import { bufferedTrack } from '../utils/BufferedTrack';
import { UserBehaviorService } from '../services/UserBehaviorService';
import { VideoShotService, SeekThumbFrame } from '../services/VideoShotService';
import { SeekThumb } from '../model/SeekThumb';
import { ObservableComment } from '../model/ObservableComment';
import { CommentDataSource } from '../model/CommentDataSource';
import { GenericDataSource } from '../model/GenericDataSource';
import { ReferenceEpisodeStrip } from '../components/ReferenceEpisodeStrip';
import { CommentItemComponent } from '../components/CommentItemComponent';
import { CommentThreadPanel } from '../components/CommentThreadPanel';
import { CommentConversationPanel } from '../components/CommentConversationPanel';
import { TextSelectionDialog } from '../components/TextSelectionDialog';
// ⭐ 弹幕组件
import { DanmakuView } from '../components/DanmakuView';
import { ReferenceDanmakuSettings } from '../components/ReferenceDanmakuSettings';
import { DanmakuConfig, DanmakuConfigInit, DanmakuItem, DanmakuType, DanmakuItemInit } from '../model/DanmakuItem';
// ⭐ 实况窗
import { LiveViewHelper } from '../services/LiveViewHelper';
// ⭐ DASH 转播站组装器（双流场景替代双 AVPlayer）
import { DashPlayerBridge } from '../services/DashPlayerBridge';
import { FeedPlaybackSession, FeedPlaybackHandles } from '../services/FeedPlaybackSession';
import { QualityPlaybackSession, RetiredPlayback, retirePlayback } from '../services/QualityPlaybackSession';
import { PlaybackWarmPlayer, WarmPlayback } from '../services/PlaybackWarmPlayer';
import { PlayerService, DashServerHandle } from '../services/PlayerService';
// ⭐ 离线缓存
import { OfflineCacheService } from '../services/OfflineCacheService';
import { OfflineCacheItem, CacheStatus } from '../model/OfflineCacheItem';
// ⭐ 本地文件播放需用文件描述符（createMediaSourceWithFd），fileUri 路径形式 AVPlayer 不识别
import { fileIo as fs } from '@kit.CoreFileKit';

// B站视频详情API响应接口
interface VideoDetailView {
  bvid: string;
  title: string;
  pic: string;
  aid: number;
}
interface VideoDetailData {
  View: VideoDetailView;
}
interface VideoDetailResponse {
  code: number;
  message: string;
  data: VideoDetailData;
}

interface VC { bvid: string; cid: number; title: string; cover: string; ownerName?: string; ownerFace?: string; duration?: number; pubdate?: number; view?: number; subTitle?: string; score?: string; indexShow?: string; badge?: string }
/**
 * 滑入页信息层的只读快照：和「当前页信息层」是两份独立数据，各自绑死自己的稿件。
 * 目标一旦确定就整体替换一次，整个拖动 + 提交周期里不再被单槽位详情/队列字段改写，
 * 否则拖动中会出现「灰占位 → 别人的头像 → 正确头像」三级跳。
 */
interface FeedChromeInfo {
  id: string
  face: string
  name: string
  title: string
  duration: number
  like: number
  coin: number
  favorite: number
  reply: number
}
interface QI { qn: number; label: string }
interface SO { label: string; mode: string }
interface ReferenceSubtitleCue { from: number; to: number; content: string }
interface ReferenceSubtitleTrack { subtitle_url: string; lan_doc: string }
interface ReferenceSubtitleList { subtitles?: ReferenceSubtitleTrack[] }
interface ReferenceSubtitleData { subtitle?: ReferenceSubtitleList }
interface ReferenceSubtitleInfo { code: number; data?: ReferenceSubtitleData }
interface ReferenceSubtitleBody { body: ReferenceSubtitleCue[] }
interface ReferenceActionResult { code: number; message?: string }
// ⭐ 画风选项（色彩风格）
interface CO { label: string; mode: string }
// ⭐ 更多菜单项（后续功能扩展：缓存、定时等）
interface MO { label: string; icon: Resource; action: () => void }
class ReferencePanelDataSource extends GenericDataSource<number> {
  constructor() {
    super();
    this.setRawItems([0, 1]);
  }
}
interface FullscreenSource {
  isLandscape: boolean;
  orientation: window.Orientation;
  feed: boolean;
  feedProgress: number;
  feedComments: boolean;
  infoHidden: boolean;
  panelOffset: number;
}
// 最小化视频播放状态
interface MinimizedVideoState {
  qualities?: QI[];
  playbackRate?: number;
  isOffline?: boolean;
  bvid: string;
  cid: number;
  title: string;
  cover: string;
  currentTime: number;
  duration: number;
  isPlaying: boolean;
  quality: number;
  qualityLabel: string;
  volume: number;
  mute: boolean;
  isLandscapeVertical: boolean;  // ⭐ 横屏竖屏视频模式状态
  videoAspectRatio: number;       // ⭐ 视频宽高比
  aid: number;                    // ⭐ 分集 aid（PGC 评论 oid；恢复播放页时补详情/评论）
  epId: number;                   // ⭐ PGC 分集 id
  seasonId: number;               // ⭐ PGC 季 id
}

// 画质偏好（Wi-Fi / 移动网络两档）由 QualityPreferenceService 在 EntryAbility.onCreate 里同步写入
// AppStorage 的 defaultVideoQn；这里不再 persistProp —— 持久化会让上次链路解析出的生效值反过来
// 覆盖本次换网后的判定（模块加载时 persistProp 会顶掉 AppStorage 里的新值）。
PersistentStorage.persistProp('playbackProgressV1', '[]')
PersistentStorage.persistProp('continuousRecommendationsV1', '[]')
PersistentStorage.persistProp('bgp', false)
PersistentStorage.persistProp('phoneLayoutToggle', false)
PersistentStorage.persistProp('lightsOffHideOnly', false)
PersistentStorage.persistProp('lightsOffShowBtn', false)
PersistentStorage.persistProp('lightsOffDanmakuOutside', true)

// ⭐「弹幕设置」面板的持久化 key（存 Preferences 'VPS' 库，值为 JSON 字符串）
const DM_SETTING_KEY: string = 'danmakuDisplaySettings'

/**
 * 连刷底部操作按钮（点赞/投币/收藏/评论）的单项宽度。
 * 原先四个按钮各带 layoutWeight(1)，会跟弹幕输入框一起按屏宽比例分配：手机上每项约 60vp 还算正常，
 * 平板上单项被拉到 200vp+，四个图标散成一条、间距随屏宽无限变大。
 * 现在改成「输入框吸收剩余宽度 + 按钮组固定宽度靠右」，图标间距在任何屏宽下都一致。
 */
const FEED_ACTION_ITEM_W: number = 54

/**
 * 连刷底部「发弹幕」输入胶囊的最大宽度。
 * 按钮组定宽后，剩下的宽度全给输入框；手机上刚好铺满，平板上会拉成一条空的超长胶囊，
 * 所以给个上限，超出的部分留成输入框与按钮之间的空隙（SpaceBetween 收尾对齐，按钮仍然贴右）。
 */
const FEED_DANMAKU_MAX_W: number = 360

/**
 * ⭐ 播放页实例身份。
 * 路由 path 只能说明「栈顶是不是播放页」，说明不了「栈顶是不是我」：
 * 播放页里点相关推荐会 push 出**另一个** `pages/VideoPlayerPage`，
 * A 被 B 覆盖时两页 path 完全相同，A 切后台时用 path 比对会误判自己仍在栈顶。
 * 这里给每个实例一个独立编号，并在 onPageShow 时登记为「当前最上层播放页」。
 * ⚠ 不能用模块级自增计数器：同一个页面模块可能被重复求值（两页各有一份模块作用域），
 *   两个实例会拿到同一个序号，判据就退化成「永远是我」。时间戳 + 随机数与之无关。
 */
function newVideoPlayerPageInstanceId(): string {
  return String(Date.now()) + '-' + String(Math.floor(Math.random() * 1000000));
}

/** AppStorage key：最后一次 onPageShow 的播放页实例编号（空 = 尚未登记）。 */
const TOP_PLAYER_PAGE_KEY: string = 'topVideoPlayerPageId'

/**
 * Bilibili CDN 图片缩放辅助：在 URL 后追加 `@Ww` 参数缩放到指定宽度
 * 仅对 hdslb.com 域名生效，其他 URL 原样返回
 */
function imageUrlResize(url: string, width: number): string {
  if (!url || !url.includes('hdslb.com')) {
    return url;
  }
  // ⚠️ 原实现 `!url.includes('@')`：URL 已带后缀时**整段跳过压缩** → 原图整张解码
  const at: number = url.indexOf('@');
  const base: string = (at > url.lastIndexOf('/') && url.indexOf('?') < 0) ? url.substring(0, at) : url;
  return base + `@${width}w`;
}

@Entry
@Component
struct VideoPlayerPage {
  @State fullscreenVideoScale: number = 1
  @State fullscreenVideoAngle: number = 0
  @State fullscreenVideoX: number = 0
  @State fullscreenVideoY: number = 0
  private fullscreenTransform: FullscreenVideoTransform = new FullscreenVideoTransform()
  // Keep ownership until every finger lifts, so the last finger cannot seek or toggle controls.
  private fullscreenTransformTouch: boolean = false
  private fullscreenTransformClickUntil: number = 0
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageProp('referenceLayout') referenceLayout: boolean = true
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0
  @State referenceIntroCard: VideoIntroCard | null = null
  @State referenceIntroTags: VideoIntroTag[] = []
  private referencePanelPages: ReferencePanelDataSource = new ReferencePanelDataSource();
  @State private referenceCommentsMounted: boolean = false;
  private referenceIntroRequest: string = '';
  @State referenceDescriptionExpanded: boolean = false
  @State referenceInfoHidden: boolean = false
  @State referencePortraitSettingsAnimating: boolean = false
  @State referenceSubtitleEnabled: boolean = false
  @State referenceSubtitleText: string = ''
  @State referenceSubtitleOptions: string[] = []
  @State referenceSubtitlePanelOpen: boolean = false
  @State referenceSubtitleLarge: boolean = false
  @State referenceSelectedSubtitleIndex: number = -1
  private referenceSubtitleSelectionRequest: number = 0;
  private referenceSubtitleMenuRequest: number = 0;
  @State private referenceSubtitleMenuLoading: boolean = false;
  @State private referenceSubtitleMenuFailed: boolean = false;
  @State private playbackPanelTopInset: number = 0;
  private onPlaybackAvoidAreaChanged = (data: window.AvoidAreaOptions): void => {
    if (data.type !== window.AvoidAreaType.TYPE_SYSTEM || !this.referenceAlive) return;
    this.updatePlaybackPanelInset(data.area);
  };

  private updatePlaybackPanelInset(area: window.AvoidArea): void {
    // Zero means hidden now. Do not replace it with the cached physical bar height.
    this.playbackPanelTopInset = Math.max(0, this.getUIContext().px2vp(area.topRect.height));
  }

  @State referenceLandscapeDanmakuOpen: boolean = false
  private referenceSubtitleTrackUrls: string[] = []
  private referenceSubtitleCues: ReferenceSubtitleCue[] = []
  private referenceShareController: systemShare.ShareController | null = null
  private referencePortraitMotionToken: number = 0
  /** 上一次实际下发给窗口的系统栏状态（status|navigation），相同则不再调用窗口 API。 */
  private sysBarKey_: string = ''
  @State @Watch('onPlaybackViewportChanged') referenceFeed: boolean = false
  @State referenceFeedProgress: number = 0
  @State private referenceTabProgress: number = 0
  @State private referencePanelHeaderRevision: number = 0
  @State private referenceIntroTabWidth: number = 28
  @State private referenceCommentTabWidth: number = 70
  @State referenceModeAnimating: boolean = false
  /**
   * ⭐ 连刷进出动画的代数号。
   * 改用渲染侧 animateTo（同 animateVidShrink）后没有 Animator 句柄可比较，
   * 而 onFinish 可能在新一轮已经开始之后才触发，只有代数号能丢弃过期收尾。
   */
  private referenceModeGen: number = 0
  private referencePanelSwiper: SwiperController = new SwiperController()
  @State @Watch('onPlaybackViewportChanged') referenceFeedComments: boolean = false
  @State private referenceFeedCommentProgress: number = 0
  @State private referenceFeedCommentAnimating: boolean = false
  private referenceFeedCommentGen: number = 0
  private playerPageVisible: boolean = true;
  /**
   * ⭐ 本播放页实例的唯一编号（见文件顶部 newVideoPlayerPageInstanceId）。
   * 栈里可能同时存在多个播放页（A 点相关推荐 push 出 B），path 区分不出谁在上面，
   * 只能靠实例编号判断「切后台时栈顶是不是我」。
   */
  private pageInstanceId_: string = newVideoPlayerPageInstanceId();
  // ⭐ 播放页被其它路由页覆盖（如进 UP 空间、点进另一个视频），区别于「应用整体切后台」：
  //    被覆盖时即使 appInBackground=true 也不允许后台续播。
  private pageCoveredByRoute_: boolean = false;
  private commentRequestSequence: number = 0;
  private commentRequestKey: string = '';
  @State referencePanelOffset: number = 0
  @State private referenceLandscapePlayerRatio: number = 2 / 3
  @State private referenceLandscapeExpandProgress: number = 0
  private referenceLandscapeResizeStart: number = 2 / 3
  private resizeStartedAt: number = 0
  private resizeEventCount: number = 0
  private resizeLayoutCount: number = 0
  private resizeLayoutLastAt: number = 0
  private resizeLayoutMaxGap: number = 0
  @State private referenceLandscapeResizeActive: boolean = false
  @State private referenceResizePanelWidth: number = 1
  @State private referenceResizeSurfaceW: number = 1
  @State private referenceResizeSurfaceH: number = 1
  @State referenceFeedLoading: boolean = false
  @State referenceFeedDragY: number = 0
  @State referenceFeedMotionDuration: number = 0
  @State referenceFeedPreview: RecommendItem | null = null
  @State referencePreviewDetail: VideoDetail | null = null
  /** 滑入页自己的一套信息层数据；切目标时整体换，拖动中不逐字段刷新。 */
  @State private referenceFeedNextChrome: FeedChromeInfo | null = null
  @State referencePreviewFrame: image.PixelMap | undefined = undefined
  @State referencePinnedFrame: image.PixelMap | undefined = undefined
  @State referencePinnedCover: string = ''
  @State referencePinnedAspectRatio: number = 1
  @State referencePinnedOpacity: number = 1
  @State referenceFeedSurfaceReady: boolean = false
  private referenceStillFrames: Map<string, image.PixelMap> = new Map()
  private referenceStillDetails: Map<string, VideoDetail> = new Map()
  /** 静帧位图的真实比例（pmRatio）：只给固定页/预览页那张 Image 用。 */
  private referenceStillRatios: Map<string, number> = new Map()
  /**
   * 解码器实测画幅（session.aspectRatio）：只给视频画面 ar 用。
   * 必须和 referenceStillRatios 分开：预热 surface 可能还挂着上一条的 buffer 尺寸，
   * 抓出来的位图比例（如 1.7766）和视频真实画幅（如 0.5625）能差一倍。
   * 拿位图比例当 ar → 视频拉伸；拿画幅当位图比例 → 静帧缩成小条，两种情况都出现过。
   */
  private referenceDecodeRatios: Map<string, number> = new Map()
  /** 备胎 surface 抓图时「画布比例仍是上一个盒子」的重抓计数，防止无上限重试。 */
  private referenceWarmStaleAttempts: Map<string, number> = new Map()
  // 邻片详情独立预热通道：信息层（头像/UP主/标题）只依赖详情，不该排在解码器和画幅锁后面。
  // key = 稿件 id，value = 在途请求（同一条只发一次）。
  private referenceDetailJobs: Map<string, Promise<VideoDetail | null>> = new Map()
  // 一张静帧可能同时被「缓存表」「滑入的预览页」「盖住画面的固定页」引用。
  // 表里被替换/淘汰后不能直接 release：来回切时固定页往往还拿着旧图，
  // 释放后 getImageInfoSync() 返回 undefined，交接直接抛异常、画面永久冻住。
  private pendingStillReleases: image.PixelMap[] = []
  private stillSweepTimer_: number = -1
  private playbackListPrefetch: PlaybackListPrefetch = new PlaybackListPrefetch(() =>
    this.referenceAlive && this.playerPageVisible && !this.waitingForFirstFrame && !this.isPgc_)
  @State referenceFeedPreviewPinned: boolean = false
  @State referencePreviewVisible: boolean = false
  @State referencePreviewAspectRatio: number = 1
  @State private referenceSecondSurfaceActive: boolean = false
  private referenceWarmSession: FeedPlaybackSession | null = null
  private referenceFeedSlotPending: boolean = false
  // 本次交接是否接的是预热实例：只有预热 surface 上已经停着那一帧，
  // 静帧硬切才是无缝的；冷启动的 surface 还是空的，硬切会闪一帧黑。
  private referenceFeedWarmAdopted_: boolean = false
  @State private referenceWarmAspectRatio: number = 1
  private referencePreviewReleaseJob: Promise<void> = Promise.resolve()
  private referencePreviewXc: XComponentController = new XComponentController()
  private referencePreviewSurfaceId: string = ''
  private referencePreviewRequestedId: string = ''
  private referencePreviewPreparing: boolean = false
  private neighborWarmTimer_: number = -1;
  private neighborWarmAttempts_: number = 0;
  private neighborWarmBypass_: boolean = false;
  private referencePreviewDecodingId: string = ''
  private referencePreviewDecodePromise: Promise<boolean> = Promise.resolve(false)
  @State referencePreviewFrameReady: boolean = false
  private referencePreviewGeneration: number = 0
  private referenceAlive: boolean = true
  @State private referencePlaybackCompleted: boolean = false
  private referenceFeedTapTimer: number = -1
  private referenceFeedTapGeneration: number = -1
  private referenceFeedDoubleTapUntil: number = 0
  private referenceSwitchGeneration: number = 0
  private referenceFeedMainFrameResolve: (() => void) | null = null
  private referenceFeedMainPreparedResolve: (() => void) | null = null
  private referenceFeedMainJob: Promise<void> = Promise.resolve()
  private referenceFeedMainCancel: (() => void) | null = null
  private referenceFeedMainPresentResolve: (() => void) | null = null
  private referenceFeedMainPresentAfter: number = 0
  private referenceFeedMainRetry_: number = 0
  private referenceFeedAnimator: AnimatorResult | null = null
  private referenceFeedMotionResolve: (() => void) | null = null
  private referenceFeedPreparingMain: boolean = false
  private referenceFeedAudioStartPending: boolean = false
  private referencePanelStart: number = 0
  private referencePanelBodyLastY: number = 0
  private referencePanelBodyStartY: number = 0
  private referencePanelBodyStartX: number = 0
  private referencePanelBodyCanDrag: boolean = false
  // 0: undecided, 1: horizontal pager, 2: vertical panel/content drag.
  private referencePanelBodyDirection: number = 0
  private referencePanelBodyStartOffset: number = 0
  /**
   * ⭐ 面板跟手锚点：方向确认时把起点前移到 10vp 方向死区的边界。
   *    死区那 10vp 作为 slop 吃掉（不补写），起步只消费「超出的部分」，
   *    之后每一帧都用同一个绝对映射 anchorOffset + (y - anchorY)，
   *    因此起步不跳、按住来回移动也不跳。与 dy 分开，进连刷/回弹的阈值不受影响。
   */
  private referencePanelDragAnchorY: number = 0
  private referencePanelDragAnchorOffset: number = 0
  private referenceTouchX: number = 0
  private referenceTouchY: number = 0
  private referenceVerticalSwipe: boolean = false
  private referenceFeedTouchStartedAt: number = 0
  private referenceFeedTouchDirection: number = 0
  private referenceFeedTouchAllowed: boolean = false
  private referenceFeedPanOwnsTouch: boolean = false
  private referenceFeedDragOriginY: number = 0
  // 手势起始于换页动画途中时，动画还会继续走，原点已经过期；等动画结束要重新锚定，
  // 否则手指一动页面会从动画终点跳回「半路 + 位移」。
  private referenceFeedOriginStale_: boolean = false
  /** 重新锚定时的累计位移基准：后续位移要减掉它，页面才不会跳。 */
  private referenceFeedDragBaseDy_: number = 0
  private referenceFeedDragEndResolve: (() => void) | null = null
  private referenceFeedTraceBucket: number = 0
  private referenceQueuedFeedStep: number = 0
  // 连续播放会话独有；不读取或改写首页列表、首页刷新索引。
  private referenceFeedQueue: RecommendItem[] = []
  private referenceFeedRecommendJob: Promise<void> | null = null
  private referenceFeedSessionId: string = `${Date.now().toString(16)}${Math.random().toString(16).substring(2, 10)}`

  @State vi: VC = { bvid: '', cid: 0, title: '', cover: '' }
  // ⭐ 从路由参数中获取的 aid（用于 saveWatchHistory，不依赖异步加载的 this.vd）
  private aidFromParams_: number = 0
  // ⭐ PGC（番剧/影视）播放状态：epId_=分集id, seasonId_=季id, isPgc_=是否PGC源
  private epId_: number = 0
  private seasonId_: number = 0
  @State isPgc_: boolean = false
  // ⭐ 离线播放：本地缓存文件路径（非空时 initP 走本地播放，跳过网络取流）
  private offlineVideoPath_: string = ''
  private offlineAudioPath_: string = ''
  // ⭐ 离线播放：已打开的本地文件 fd（release 时必须关闭）
  private offlineVideoFd_: fs.File | null = null
  private offlineAudioFd_: fs.File | null = null
  // ⭐ PGC 选集：与 vd.pages 下标一一对应的 ep_id 列表（切集时更新 epId_）
  private pgcEpIds_: number[] = []
  // ⭐ PGC 选集：与 vd.pages 下标一一对应的分集 aid 列表（番剧评论 oid 必须用 aid，不能用 ep_id）
  private pgcAids_: number[] = []
  private av: PlaybackPlayer | null = null; private avAudio: PlaybackPlayer | null = null; private sId: string = ''
  @StorageLink('floatingPiPActive') private floatingSystemActive: boolean = false;
  @State private floatingPausedFrame: image.PixelMap | undefined = undefined;
  private floatingXc: XComponentController = FloatingVideoSurface.controller;
  @State private floatingMorph: boolean = false;
  @State private floatingCompact: number = 0;
  @State private floatingReady: boolean = true;
  private floatingRestoring: boolean = false;
  private floatingRestoreFinishing: boolean = false;
  private floatingSource: FloatingVideoRect = { x: 0, y: 0, width: 1, height: 1 };
  private floatingTarget: FloatingVideoRect = { x: 0, y: 0, width: 1, height: 1 };

  private floatingRect(): FloatingVideoRect {
    const t = this.floatingCompact;
    return {
      x: this.floatingSource.x + (this.floatingTarget.x - this.floatingSource.x) * t,
      y: this.floatingSource.y + (this.floatingTarget.y - this.floatingSource.y) * t,
      width: this.floatingSource.width + (this.floatingTarget.width - this.floatingSource.width) * t,
      height: this.floatingSource.height + (this.floatingTarget.height - this.floatingSource.height) * t
    };
  }
  private prepareFloatingGeometry(): void {
    const wasMorphing = this.floatingMorph;
    this.floatingMorph = false;
    this.floatingSource = {
      x: this.ovRectX() + (this.ovRectW() - this.ovVideoW()) / 2,
      y: this.ovRectY() + (this.ovRectH() - this.ovVideoH()) / 2,
      width: this.ovVideoW(), height: this.ovVideoH()
    };
    const ratio = Number.isFinite(this.ar) && this.ar > 0 ? this.ar : 16 / 9;
    const saved = FloatingVideoTransition.mini;
    const safeTop = AppStorage.get<number>('statusBarHeight') || 40;
    const maxWidth = Math.min(this.cw - 16, (this.ch - safeTop - this.navIndicatorHeight - 16) * ratio);
    const width = Math.min(maxWidth, saved ? saved.width : Math.min(200, 224 * ratio));
    const height = width / ratio;
    this.floatingTarget = {
      x: Math.max(8, Math.min(this.cw - width - 8, saved ? saved.x : this.cw - 16 - width)),
      y: Math.max(safeTop + 8, Math.min(this.ch - this.navIndicatorHeight - height - 8,
        saved ? saved.y : this.ch - 60 - this.navIndicatorHeight - height)),
      width: width, height: height
    };
    this.floatingMorph = wasMorphing;
    FloatingVideoTransition.source = this.floatingSource;
    FloatingVideoTransition.remember(this.floatingTarget);
  }

  private finishFloatingRestore(): void {
    if (!this.floatingRestoring || !this.av || this.floatingRestoreFinishing) return;
    if (AppStorage.get<boolean>('floatingPiPActive')) {
      setTimeout(() => this.finishFloatingRestore(), 32);
      return;
    }
    this.floatingRestoreFinishing = true;
    this.prepareFloatingGeometry();
    this.pageEnterProgress = 1;
    this.contentVisible = true;
    this.floatingReady = true;
    AppStorage.set('videoMinimized', false);
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : (FloatingVideoTransition.restoreExpanded ? 32 : FloatingVideoTransition.DURATION), curve: Curve.EaseOut,
      onFinish: () => {
        const surface = (this.referenceSecondSurfaceActive ? this.referencePreviewXc : this.xc).getXComponentSurfaceId();
        if (surface && this.av) this.av.surfaceId = surface;
        FloatingVideoSurface.park();
        this.floatingMorph = false;
        this.floatingRestoring = false;
        FloatingVideoTransition.restoreExpanded = false;
        FloatingVideoTransition.finish();
        logInfo('[FloatingMorph] restore complete');
      }
    }, () => { this.floatingCompact = 0; });
  }

  pageTransition() {
    if (FloatingVideoTransition.active()) {
      PageTransitionEnter({ duration: FloatingVideoTransition.DURATION }).opacity(1)
      PageTransitionExit({ duration: FloatingVideoTransition.direction === 'minimize' ? 0 : FloatingVideoTransition.DURATION, curve: Curve.EaseOut })
        .opacity(1)

    }
  }

  private xc: XComponentController = new XComponentController()
  private nativeSurfaceId_: string = ''
  /** ⭐ DASH 转播站桥（DASH 双流场景用；FLV/离线时为 null） */
  private dashBridge_: DashPlayerBridge | null = null
  /** ⭐ 恢复接管时从 PlayerService 取回的转播站句柄（页面退出停服用） */
  private dashHandle_: DashServerHandle | null = null
  /** ⭐ 当前播放为 DASH 转播站模式（音画引擎内同步，skip 手动对齐） */
  private isDashStream_: boolean = false
  /** GL 渲染管线已禁用（当前设备/OS 不支持 OH_NativeImage 帧拦截） */
  private isGLInitialized_: boolean = false
  private glXcSurfaceId_: string = ''
  private glRenderTimer_: number = -1
  private mw: window.Window | null = null
  /** 进入页面时的原始窗口亮度，-1 = 系统自动亮度，>=0 = 手动亮度值 */
  private originalBrightness_: number = -1
  @State ld: boolean = true; @State err: string = ''; @Watch('onPlayChanged') @State play: boolean = true
  @State waitingForFirstFrame: boolean = true;
  @State ct: number = 0; @State dur: number = 0; @State rt: number = 1.0
  @State bufferedUntil: number = 0
  private progressSavedAt: number = 0
  private videoSeekPosition: number = -1
  private seekProgressPending: boolean = false
  private seekExpectedPosition: number = 0
  private restoringProgress: boolean = false
  private pgcProgressQueue: Promise<void> = Promise.resolve()
  @State mute: boolean = false; @State vol: number = 0.8; @State bri: number = 0.5
  @State cv: boolean = false; @State lk: boolean = false
  @State @Watch('onTransitionFlip') fs: boolean = false
  // ⭐ 评论区转场渐显：转场期间（全屏/旋转）评论区移出布局；全部转场结束后 0→1 渐显回来
  @State commentFade: number = 1
  // ⭐ 常驻播放器层矩形（非全屏由分支占位槽 onAreaChange 跟踪；全屏为整屏）
  @State ovX: number = 0
  @State ovY: number = 0
  @State ovW: number = 0
  @State ovH: number = 0
  // 内容 Column 全局锚点（占位槽全局坐标减去锚点 → Column 内坐标，即常驻层 position 坐标系）
  private ovAnchorX: number = 0
  private ovAnchorY: number = 0
  // ⭐ fs 期间内容分支冻结键（'portrait'|'lv'|'isLs'），进入全屏前快照
  private preFsBranch: string = 'portrait'
  private fullscreenSource: FullscreenSource | null = null
  @State private fullscreenRotationTransition: boolean = false
  private fullscreenRotationTarget: boolean | null = null
  private fullscreenRotationEntering: boolean = false
  // ⭐ 进出全屏连续几何插值：起点快照 + 方向（0=无 1=进入 2=退出）
  private fsLerpSnapX: number = 0
  private fsLerpSnapY: number = 0
  private fsLerpSnapW: number = 0
  private fsLerpSnapH: number = 0
  private fsLerpSnapVW: number = 0
  private fsLerpSnapVH: number = 0
  private fsLerpDir: number = 0
  // ⭐ 旋转进行中标志：旋转期间跳过评论头像预解码；退出全屏插值等待旋转完成
  @State @Watch('onTransitionFlip') rotationInProgress: boolean = false
  @State gh: boolean = false; @State ght: string = ''
  @State ghp: number = -1
  @State ghtType: string = ''
  // ⭐ 音量/亮度手势是否仍在进行（手指按着）。竖条只在 true 期间点亮白色边界与粒子；
  //   松手立刻转 false ⇒ 高光熄灭、粒子淡出、图标回白，提示本身仍按 800ms 残留。
  @State private outputUsesHeadphones: boolean = false;
  @State private outputHeadphoneIcon: string = 'headphones_fill';
  private audioOutputMonitor: PlaybackAudioOutputMonitor = new PlaybackAudioOutputMonitor((headphones: boolean, icon: string) => {
    this.outputUsesHeadphones = headphones;
    this.outputHeadphoneIcon = icon;
  }, () => this.getUIContext().getHostContext() as common.UIAbilityContext);
  @State ghActive: boolean = false
  // ⭐ 本次进度调节的**起点秒数**（拖动进度条 = 按下时的位置；视频区手势 = 手指落下的位置）。
  //   提示胶囊右侧据此显示"相对位移"（+10S 绿 / -10S 红）。-1 表示无效（不显示）
  @State ghb: number = -1
  @State bh: boolean = false; @State bhi: ResourceStr | undefined = undefined
  @State bht: string = ''; private bt: number = -1
  @State ub: boolean = false; private ubt: number = -1
  private handlingUnlockClick: boolean = false  // 防止解锁按钮点击事件冲突
  @State rh: boolean = false; @State rht: string = ''; private rhtm: number = -1
  // ⭐ 实况窗节流定时器
  private lvTimer_: number = -1
  // ⭐ 声画同步：恢复后自动检测视频落后并 2x 追赶
  private videoSpeedFixTimer_: number = -1
  private isSpeed2x_: boolean = false
  // ⭐ 上次声画同步 seek 的时间戳，防止频繁 seek 导致画面反复跳跃
  private lastSyncSeekTime_: number = 0
  // ⭐ seek 冷却期：上次 seek 后多久内不再 seek（毫秒）
  private readonly SYNC_SEEK_COOLDOWN_: number = 8000
  // ⭐ 2x 追赶期间不再切换为 seek，避免画面抽搐
  private isSpeedFixIn2xPhase_: boolean = false
  @State sm: string = 'auto'; @State vw: number = 0; @State vh: number = 0
  @State ar: number = 16 / 9; @State cw: number = 0; @State ch: number = 0
  @State lsvw: number = 0; @State lsvh: number = 0
  /**
   * ar 的来源：true = 路由参数/详情给的**显示尺寸**（已按 rotate 交换过），
   * false = 解码器或 DASH 元数据给的**编码尺寸**。
   *
   * ⚠️ 两者不能无条件互相覆盖：rotate=90 的源（手机竖拍很常见）编码尺寸是 1920x1080、
   *    显示尺寸是 1080x1920，两个比例恰好互为倒数。硬解帧是 AV_PIX_FMT_OHCODEC，
   *    不过 libavfilter（见 ff_ffplay.c 的 queue_picture 注释），autorotate 的 rotate
   *    filter 被绕过，上报的仍是编码尺寸；拿它盖掉显示尺寸，竖屏画面就会被塞进
   *    16:9 的 surface 里横向拉扁 —— 这是"被压成 16:9"的另一条成因。
   */
  private arFromMeta_: boolean = false;
  /** meta 对应的 cid：切集后旧详情不再算数，解码尺寸可以重新接管。 */
  private arMetaCid_: number = 0;
  /** ⭐ cardMargin 安全化：Preferences/AppStorage 可能出现 NaN/undefined/字符串，统一兜底为 12 */
  private safeCM(): number {
    const v = Number(this.cardMargin);
    if (!Number.isFinite(v)) return 12;
    return v;
  }

  /** ⭐ 播放页竖屏评论区：单图的适配框（见 CommentContentRenderer.picBoxW 注释）。0 = 不启用。 */
  private commentPicBoxW(): number {
    if (this.cw <= 0) return 0;
    // 横屏重排后按右侧面板计算图片宽度，避免仍使用整个窗口宽度。
    const width = this.referenceLayout && this.isLs && !this.fs
      ? this.referenceLandscapeTabWidth(1) + 2 * this.safeCM() : this.cw;
    return Math.max(1, width - 2 * this.safeCM() - 50);
  }
  private commentPicBoxH(): number {
    if (this.ch <= 0) return 0;
    return Math.max(120, this.ch * 0.45);
  }
  // XComponent 尺寸/位置计算（每个分支独立使用）
  /**
   * ⭐ 缩小（vidShrink > 0）时视频的显式几何。取代原先散落在 13 处的同一套表达式。
   *
   * 形态：缩到最小的终值由「小窗样式」决定（个性化 → 视频页动画）：
   *   circle（默认）= 直径 SHRINK_DIAMETER 的正圆；square = 同尺寸小圆角方窗；
   *   ratio = 保持画面比例的小矩窗；hidden = 收到 1vp（不显示小窗，只留还原浮标）。
   * 圆形要不变形，下面三件事必须同时满足：
   *   ① 容器/占位槽缩成**正方形**（`shrinkSlotW/H`）—— 圆是方框裁出来的，方框不方就裁不出正圆；
   *   ② 圆角取方框的**一半 = 正圆**（`shrinkRadius`），且随 vidShrink 从 cardBorderRadius 连续过渡，
   *      这样是"方角矩形慢慢收成圆形"而不是末帧突然变圆；
   *   ③ 视频本体**放大到盖满方框**（`shrinkFillW/H`，按 max 比例缩放）—— 否则 16:9 画面放进正方形
   *      会上下留黑边，裁成圆后圆里就是两道黑。多出的部分由容器的圆形 clip 裁掉（同封面圆形头像）。
   *      ⚠️ 这一条与 ① ② 是一体的：只做 ① ② 会得到"圆里带黑边"。
   *
   * 全部用 `vidShrink` 线性插值，所以 **vidShrink=0 时与旧的正常尺寸逐值相等**，非缩小态不受影响。
   *
   * ⚠️ 历史坑（改这里前先读）：原式宽只缩 30%、高缩 85%，盒子变成约 8:1 的横条而画面是 16:9，
   *    于是两侧各约三分之一是黑边；顶部还从 50 线性降到 10，被前置挖孔挡住。
   *    `shrinkVideoTop` 的"不低于顶部安全区"就是为后者加的，别再压回 10。
   */
  /** 圆形小窗直径（vp）的**出厂默认值**：实际值由「个性化 → 视频页动画 → 小窗大小」决定 */
  private readonly SHRINK_DIAMETER: number = 120;
  /** 正方形样式的圆角（vp）：圆角方窗，不是正圆（12 太方正，用户要求再大些 → 30） */
  private readonly SHRINK_SQUARE_RADIUS: number = 30;
  /** 等比样式的圆角（vp） */
  private readonly SHRINK_RATIO_RADIUS: number = 10;
  /** 缩小时的方框边长（不缩时夹在可用宽度内，避免小屏溢出） */
  private shrinkCircleD(): number {
    // ⭐ 尺寸可由用户调（AppStorage 'shrinkWindowSize'）：这里再夹一次范围，
    //    防止 Preferences 里存了脏值把 surface 弄成非法尺寸；窄屏还要再被 videoDisplayWidth 夹一次。
    const raw = Number.isFinite(this.shrinkWindowSize) ? this.shrinkWindowSize : this.SHRINK_DIAMETER;
    const size = Math.max(60, Math.min(240, raw));
    return Math.min(size, this.videoDisplayWidth);
  }
  /**
   * ⭐ 缩到最小后的**目标宽**（vp）：由「个性化 → 视频页动画 → 缩小后的小窗样式」决定
   *   circle/square → 120（正方形边长）；ratio → 120（等比时以宽为基准）；
   *   hidden → 1（等价于收起；**不能给 0** —— surface 尺寸非法会被系统杀掉，
   *   本文件其它路径也一律用 Math.max(1, ...) 兜底）。
   */
  private shrinkTargetW(): number {
    if (this.shrinkWindowStyle === 'hidden') return 1;
    return this.shrinkCircleD();
  }
  /**
   * ⭐ 缩到最小后的**目标高**（vp）：
   *   circle/square → 与宽相同（正方形，靠圆角半径区分为正圆 / 方窗）；
   *   ratio → 按画面真实比例 d × vh/vw（此时 fillScale 恰好等于该比例，视频正好铺满、无裁切）；
   *   hidden → 1。
   */
  private shrinkTargetH(): number {
    if (this.shrinkWindowStyle === 'hidden') return 1;
    const d = this.shrinkCircleD();
    if (this.shrinkWindowStyle === 'ratio') {
      const vw = Math.max(1, this.videoDisplayWidth);
      const vh = Math.max(1, this.videoDisplayHeight);
      return Math.max(1, d * vh / vw);
    }
    return d;
  }
  /** 缩小时的容器/占位槽宽：从视频原宽插值到目标宽 */
  private shrinkSlotW(): number {
    return this.videoDisplayWidth + (this.shrinkTargetW() - this.videoDisplayWidth) * this.vidShrink;
  }
  /** 缩小时的容器/占位槽高：从视频原高插值到目标高 */
  private shrinkSlotH(): number {
    return this.videoDisplayHeight + (this.shrinkTargetH() - this.videoDisplayHeight) * this.vidShrink;
  }
  /**
   * 缩小时的视频本体尺寸（盖满方框用）：按 `max(宽比, 高比)` 缩放。
   * vidShrink=0 时比例恰为 1 → 与正常尺寸逐值相等，正常态零影响。
   */
  private fillScale(): number {
    const w = this.shrinkSlotW();
    const h = this.shrinkSlotH();
    const vw = Math.max(1, this.videoDisplayWidth);
    const vh = Math.max(1, this.videoDisplayHeight);
    return Math.max(w / vw, h / vh);
  }
  private shrinkFillW(): number {
    return Math.max(1, this.videoDisplayWidth * this.fillScale());
  }
  private shrinkFillH(): number {
    return Math.max(1, this.videoDisplayHeight * this.fillScale());
  }
  /**
   * 缩小时的圆角：随 vidShrink 从卡片圆角连续过渡到样式对应的终值。
   *   circle → 边长一半（裁出正圆）；square → 12；ratio → 10；hidden → 0。
   */
  private shrinkRadius(): number {
    let r: number;
    if (this.shrinkWindowStyle === 'circle') {
      r = this.shrinkCircleD() / 2;
    } else if (this.shrinkWindowStyle === 'square') {
      r = this.SHRINK_SQUARE_RADIUS;
    } else if (this.shrinkWindowStyle === 'ratio') {
      r = this.SHRINK_RATIO_RADIUS;
    } else {
      r = 0;
    }
    const from = Number.isFinite(this.cardBorderRadius) ? this.cardBorderRadius : 20;
    return from + (r - from) * this.vidShrink;
  }
  /**
   * ⭐ 常驻播放层的透明度：**只**在「隐藏」样式下随缩小淡出。
   *   为什么需要：隐藏样式把目标尺寸收到 1vp（不能给 0 —— surface 尺寸非法会被系统杀），
   *   但 1vp 的黑底 + 盖满的视频仍会在屏幕上留一个肉眼可见的小点，所以必须整体淡出。
   *   圆形 / 正方形 / 等比 恒为 1（那三种本来就要看见小窗）。
   */
  private shrinkPlateOpacity(): number {
    if (this.shrinkWindowStyle !== 'hidden') return 1;
    return Math.max(0, 1 - this.vidShrink);
  }

  /** ⭐ 是否处于缩小态（阈值 0.5）：弹幕显隐、渲染开关都以它为准 */
  private isVidShrunk(): boolean {
    return this.vidShrink > 0.5;
  }
  private shrinkVideoTop(): number {
    const sb = Number(AppStorage.get<number>('statusBarHeight'));
    const safeTop = (Number.isFinite(sb) && sb > 0) ? sb : 40;   // 与 SmartGrip 取安全区的兜底值一致
    return Math.max(safeTop, 50 - 40 * this.vidShrink);
  }
  get xcW() {
    if (this.fs) return this.videoDisplayWidth;
    if (this.isLs || this.isLandscapeVertical) return this.lsvw;
    return this.shrinkSlotW(); // videoDisplayWidth 已含 cardMargin 扣减
  }
  get xcH() {
    if (this.fs) return this.videoDisplayHeight;
    if (this.isLs || this.isLandscapeVertical) return this.lsvh;
    return this.shrinkSlotH();
  }
  get xcRx() {
    if (this.fs) return (this.cw - this.videoDisplayWidth) / 2;
    if (this.isLandscapeVertical) {
      // 竖屏横看：Flex 布局，左侧按钮栏固定 80vp
      // 非镜像：按钮在左，播放器 x = 80
      // 镜像：按钮在右，播放器 x = cw - lsvw - 80
      return this.isLayoutSwapped ? (this.cw - this.lsvw - 80) : 80;
    }
    if (this.isLs) {
      // 横屏非全屏：Flex 布局
      // 非镜像：左边距 cardMargin
      // 镜像：播放器在右侧，x = cw - lsvw
      return this.isLayoutSwapped ? (this.cw - this.lsvw) : this.cardMargin;
    }
    return this.cardMargin; // portrait: left padding
  }
  get xcRy() {
    if (this.fs) return (this.ch - this.videoDisplayHeight) / 2;
    if (this.isLs || this.isLandscapeVertical) return this.cardMargin;
    return this.shrinkVideoTop(); // portrait: top padding
  }
  /** ⭐ 关灯模式：视频 fit 放大填满屏幕（保留最小边距），XComponent 实际改尺寸重绘放大 */
  private loVideoWidth(): number {
    if (this.isLightsOff) {
      const m = this.safeCM();
      const av = Math.max(1, this.cw - 2 * m);
      const ah = Math.max(1, this.ch - 2 * m);
      const arV = Number.isFinite(this.ar) && this.ar > 0 ? this.ar : 16 / 9;
      if (av / ah > arV) {
        return ah * arV;
      }
      return av;
    }
    if (this.fs) return this.videoDisplayWidth;
    if (this.isLs || this.isLandscapeVertical) return this.lsvw;
    return this.shrinkFillW(); // videoDisplayWidth 已含 cardMargin 扣减
  }
  private loVideoHeight(): number {
    if (this.isLightsOff) {
      const m = this.safeCM();
      const av = Math.max(1, this.cw - 2 * m);
      const ah = Math.max(1, this.ch - 2 * m);
      const arV = Number.isFinite(this.ar) && this.ar > 0 ? this.ar : 16 / 9;
      if (av / ah > arV) {
        return ah;
      }
      return av / arV;
    }
    if (this.fs) return this.videoDisplayHeight;
    if (this.isLs || this.isLandscapeVertical) return this.lsvh;
    return this.shrinkFillH();
  }

  /** ⭐ 常驻播放器层矩形：非全屏跟踪占位槽；全屏为整屏；进出全屏期间在两者间连续插值 */
  private ovRectX(): number {
    if (this.fsEntering) return this.fsLerpSnapX;
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      return this.referenceLandscapePlayerX() * (this.fs ? 1 - this.fsPanProgress : 1);
    }
    if (this.referenceLayout && !this.fs && !this.isLs) {
      return this.referenceFeed ? Math.max(0, (this.cw - this.referenceMediaWidth()) / 2) : 0;
    }
    if (!this.fs) return this.ovX;
    if (this.fsLerpDir === 1) return this.fsLerpSnapX * (1 - this.fsLerpT());
    if (this.fsLerpDir === 2) return this.ovX * (1 - this.fsPanProgress);
    return 0;
  }
  private ovRectY(): number {
    if (this.fsEntering) return this.fsLerpSnapY;
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      const target = this.referenceLandscapeAreaTop();
      return this.fs ? target + (0 - target) * this.fsPanProgress : target;
    }
    if (this.referenceLayout && !this.fs && !this.isLs) return Math.max(0, this.referenceMediaTop());
    if (!this.fs) return this.ovY;
    if (this.fsLerpDir === 1) return this.fsLerpSnapY * (1 - this.fsLerpT());
    if (this.fsLerpDir === 2) return this.ovY * (1 - this.fsPanProgress);
    return 0;
  }
  private ovRectW(): number {
    if (this.fsEntering) return Math.max(1, this.fsLerpSnapW);
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      const target = this.referenceLandscapeViewportWidth();
      return this.fs ? target + (this.cw - target) * this.fsPanProgress : target;
    }
    if (this.referenceLayout && !this.fs && !this.isLs) {
      // Half-screen controls use the screen-wide viewport; the centered surface and danmaku keep their media geometry.
      return Math.max(1, this.referenceFeed ? this.referenceMediaWidth() : this.cw);
    }
    if (!this.fs) return Math.max(1, this.ovW);
    if (this.fsLerpDir === 1) return Math.max(1, this.fsLerpSnapW + (this.cw - this.fsLerpSnapW) * this.fsLerpT());
    if (this.fsLerpDir === 2) return Math.max(1, this.cw + (this.ovW - this.cw) * (1 - this.fsPanProgress));
    return Math.max(1, this.cw);
  }
  private ovRectH(): number {
    if (this.fsEntering) return Math.max(1, this.fsLerpSnapH);
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      const target = this.referenceLandscapeAreaHeight();
      return this.fs ? target + (this.ch - target) * this.fsPanProgress : target;
    }
    if (this.referenceLayout && !this.fs && !this.isLs) return Math.max(1, this.referenceMediaHeight());
    if (!this.fs) return Math.max(1, this.ovH);
    if (this.fsLerpDir === 1) return Math.max(1, this.fsLerpSnapH + (this.ch - this.fsLerpSnapH) * this.fsLerpT());
    if (this.fsLerpDir === 2) return Math.max(1, this.ch + (this.ovH - this.ch) * (1 - this.fsPanProgress));
    return Math.max(1, this.ch);
  }
  /** ⭐ 常驻层内视频实际尺寸（复刻各分支原 XComponent 尺寸表达式；⚠ 不可经 get xcW/xcH 取——getter 在普通方法中返回 undefined）
     进出全屏期间连续插值，NaN/非正值兜底防 surface 被杀 */
  /**
   * 连刷里 surface 的实际尺寸（与 ovRect 的「视口」区分开）。
   *
   * IJK/puradual 的 native 渲染把解码帧**铺满** surface buffer，不像 AVPlayer 那样
   * 自己按 FIT_CROP 裁切；所以「填充」必须由 ArkUI 把 surface 撑成 cover 尺寸、再让
   * 上层裁掉溢出部分。之前 fill 直接给视口尺寸，等于把画面按屏幕比例拉伸：
   * 竖屏 9:16 在 440×744 的视口里纵向被压扁 ~5%，静帧（Image Cover 裁切）和 surface
   * 一交接，水印/画面就整体上下错位。
   */
  private feedSurfaceW(): number {
    const aspect = Math.max(0.2, this.ar || 16 / 9);
    const viewW = Math.max(1, this.referenceMediaWidth());
    const viewH = Math.max(1, this.referenceMediaHeight());
    switch (this.effectiveScaleMode()) {
      case 'stretch': return viewW;
      case 'fill': return Math.max(viewW, viewH * aspect);
      case 'fitHeight': return viewH * aspect;
      case 'fitWidth': return viewW;
      default: return viewW;
    }
  }

  private feedSurfaceH(): number {
    const aspect = Math.max(0.2, this.ar || 16 / 9);
    const viewW = Math.max(1, this.referenceMediaWidth());
    const viewH = Math.max(1, this.referenceMediaHeight());
    switch (this.effectiveScaleMode()) {
      case 'stretch': return viewH;
      case 'fill': return Math.max(viewH, viewW / aspect);
      case 'fitHeight': return viewH;
      case 'fitWidth': return viewW / aspect;
      default: return viewH;
    }
  }

  /**
   * ⭐ 竖屏播放区缩放：**固定基准 Surface + GPU scale**，不再逐帧改 Surface 宽高。
   *
   * 背景（真机拖动面板时的掉帧源）：
   *   上推/下拉简介面板、进出连刷、展开评论时播放区几何每帧变，原先 XComponent 的
   *   width/height 也跟着每帧变 —— native 侧每帧重配 surface buffer，弹幕 Canvas 也跟着
   *   每帧重建 surface，拖动时明显发涩。
   *
   * 为什么可以换成 scale：竖屏非全屏（半屏详情）的 effectiveScaleMode 恒为 auto（contain），
   *   视频任意时刻都是同一宽高比的等比缩放，所以固定一块「最大可视基准 buffer」，
   *   视觉尺寸用 .scale() 表达即可，画面不变形、不重建 surface。
   *   fill / stretch / fitWidth 等视口比例会变的模式仍走原逻辑（固定 buffer 会被拉伸）。
   *
   * 基准取值 = 竖屏最大可视区域下的 contain 尺寸（与连刷全屏时一致），
   * 因此缩放系数恒 ≤ 1，缩小显示不会损失清晰度。
   */
  private portraitScaleByTransform(): boolean {
    return this.referenceLayout && !this.fs && !this.isLs && !this.isLandscapeVertical &&
      !this.fsEntering && !this.referenceLandscapeResizeActive && !this.isLightsOff &&
      this.effectiveScaleMode() === 'auto';
  }
  private portraitBaseW(): number {
    const aspect = Math.max(0.2, this.ar || 16 / 9);
    return Math.max(1, Math.min(Math.max(1, this.cw), Math.max(1, this.ch) * aspect));
  }
  private portraitBaseH(): number {
    return Math.max(1, this.portraitBaseW() / Math.max(0.2, this.ar || 16 / 9));
  }
  /** 当前视觉尺寸 / 基准尺寸；非变换通道恒为 1 */
  private portraitScaleFactor(): number {
    if (!this.portraitScaleByTransform()) return 1;
    return Math.max(0.01, this.ovVideoW() / this.portraitBaseW());
  }

  private ovVideoW(): number {
    if (this.fsEntering) return Math.max(1, this.fsLerpSnapVW);
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      const target = this.referenceLandscapeMediaWidth();
      return this.fs ? target + (this.fsLerpSnapVW - target) * this.fsPanProgress : target;
    }
    if (this.referenceLayout && !this.fs && !this.isLs) {
      // 进入连刷的过渡帧仍按视口走：cover 尺寸会溢出 ovRect，动画期间会漏到详情页上。
      if (this.referenceFeedProgress < 0.999) {
        return this.effectiveScaleMode() === 'fitHeight' ? this.referenceAreaHeight() * Math.max(0.2, this.ar) : this.referenceMediaWidth();
      }
      return this.feedSurfaceW();
    }
    let t: number;
    if (this.fs) {
      // ⭐ 退出动画（dir=2）终点=非全屏目标尺寸（横屏=lsvw，竖屏=updatePortraitSize 已重算）：
      //    动画末帧与 fs=false 后的实际尺寸一致 → 不再突缩
      t = this.fsLerpDir === 2 ? (this.isLs ? this.lsvw : this.videoDisplayWidth) : this.videoDisplayWidth;
    } else if (this.isLightsOff && !this.isLandscapeVertical) {
      t = this.loVideoWidth();
    } else if (this.isLs || this.isLandscapeVertical) {
      t = this.lsvw;
    } else {
      // ⭐ videoDisplayWidth 已含 cardMargin 扣减（updatePortraitSize: cw-2*cardMargin），这里不再重复减
      t = this.shrinkFillW();
    }
    if (!Number.isFinite(t) || t <= 0) {
      logWarn(`[FSDBG] ovVideoW invalid t=${t} fs=${this.fs} dir=${this.fsLerpDir} lo=${this.isLightsOff} lv=${this.isLandscapeVertical} ls=${this.isLs} cm=${this.cardMargin} lsvw=${this.lsvw} vdw=${this.videoDisplayWidth} shrink=${this.vidShrink} cw=${this.cw} ch=${this.ch}`);
      t = this.isLs || this.isLandscapeVertical ? this.lsvw : Math.max(1, this.cw - 2 * this.safeCM());
    }
    if (!this.fs || this.fsLerpDir === 0) return Math.max(1, t);
    if (this.fsLerpDir === 1) return Math.max(1, this.fsLerpSnapVW + (t - this.fsLerpSnapVW) * this.fsLerpT());
    return Math.max(1, t + (this.fsLerpSnapVW - t) * this.fsPanProgress);
  }
  private ovVideoH(): number {
    if (this.fsEntering) return Math.max(1, this.fsLerpSnapVH);
    if (this.referenceLayout && this.isLs && (!this.fs || this.fsLerpDir === 2)) {
      const target = this.referenceLandscapeMediaHeight();
      return this.fs ? target + (this.fsLerpSnapVH - target) * this.fsPanProgress : target;
    }
    if (this.referenceLayout && !this.fs && !this.isLs) {
      if (this.referenceFeedProgress < 0.999) {
        return this.effectiveScaleMode() === 'fitWidth' ? this.cw / Math.max(0.2, this.ar) : this.referenceMediaHeight();
      }
      return this.feedSurfaceH();
    }
    let t: number;
    if (this.fs) {
      // ⭐ 退出动画（dir=2）终点=非全屏目标尺寸（横屏=lsvh，竖屏=updatePortraitSize 已重算）
      t = this.fsLerpDir === 2 ? (this.isLs ? this.lsvh : this.videoDisplayHeight) : this.videoDisplayHeight;
    } else if (this.isLightsOff && !this.isLandscapeVertical) {
      t = this.loVideoHeight();
    } else if (this.isLs || this.isLandscapeVertical) {
      t = this.lsvh;
    } else {
      t = this.shrinkFillH();
    }
    if (!Number.isFinite(t) || t <= 0) {
      logWarn(`[FSDBG] ovVideoH invalid t=${t} fs=${this.fs} dir=${this.fsLerpDir} lo=${this.isLightsOff} lv=${this.isLandscapeVertical} ls=${this.isLs} cm=${this.cardMargin} lsvh=${this.lsvh} vdh=${this.videoDisplayHeight} shrink=${this.vidShrink} cw=${this.cw} ch=${this.ch}`);
      t = this.isLs || this.isLandscapeVertical ? this.lsvh : Math.max(1, this.ch - 2 * this.safeCM());
    }
    if (!this.fs || this.fsLerpDir === 0) return Math.max(1, t);
    if (this.fsLerpDir === 1) return Math.max(1, this.fsLerpSnapVH + (t - this.fsLerpSnapVH) * this.fsLerpT());
    return Math.max(1, t + (this.fsLerpSnapVH - t) * this.fsPanProgress);
  }
  /**
   * ⭐ 全屏相关的圆角随过渡进度插值（原先都是 `fs ? A : B` 的布尔突变）。
   *
   * 为什么需要（真机现象："退出全屏后最后四个黑色的圆角会突然收起"）：
   *   退出全屏时几何（ovRect* / ovVideoW·H）是**逐帧连续插值**的，而圆角只在 fs 翻转的
   *   最后一帧从全屏值直接跳到非全屏值 —— 于是整个播放层带着圆角一路缩小、四角外侧一直是
   *   容器的纯黑底（color_player_background = #000000），末帧那四块黑色圆角被一刀切掉。
   *   ⚠️ 圆角属性写在 .animation() 之后，本就不受那条 120ms 隐式动画管辖 —— 这也是它表现为
   *      "瞬跳"而非"缓动"的原因；改成跟进度逐帧取值后，不需要任何隐式动画。
   *
   * @param fsRadius     全屏态的圆角
   * @param normalRadius 非全屏态（目标）的圆角
   *
   * 进度取值刻意与几何的分支保持一致（对照 ovVideoW / ovRectW 的同款判断）：
   *   dir=1 进入：用 fsLerpT()（手势中途接管时它才是相对本次过渡的真实进度）
   *   dir=2 退出：用 fsPanProgress（该分支的几何就是拿它算的：1=全屏 → 0=非全屏）
   *   dir=0 无过渡：直接取稳态值（瞬时切换时几何也是瞬跳，两者一致）
   */
  private fsLerpRadius(fsRadius: number, normalRadius: number): number {
    if (!this.fs) {
      return normalRadius;
    }
    if (this.fsLerpDir === 1) {
      return normalRadius + (fsRadius - normalRadius) * this.fsLerpT();
    }
    if (this.fsLerpDir === 2) {
      return normalRadius + (fsRadius - normalRadius) * Math.min(1, Math.max(0, this.fsPanProgress));
    }
    return fsRadius;
  }
  /** ⭐ 全屏黑板/视频背景随动画进度渐显渐隐：进入 0→黑、退出黑→0（仅插值期间），
     避免进/出全屏瞬间整屏或四周"先黑一片"、结束帧突变消失 */
  private ovPlateBg(): ResourceColor {
    if (!this.fs) return $r('app.color.color_player_background');
    if (this.fsLerpDir === 0) return $r('app.color.color_player_background');
    const p = Math.min(1, Math.max(0, this.fsPanProgress));
    const alpha = this.fsLerpDir === 1 ? p : (1 - p);
    return `rgba(0, 0, 0, ${alpha.toFixed(3)})`;
  }
  /** ⭐ 快照插值起点：进入时=当前槽矩形与视频尺寸，退出时=全屏矩形与全屏视频尺寸 */
  private captureFSSnapshot(): void {
    this.fsLerpSnapX = this.ovRectX();
    this.fsLerpSnapY = this.ovRectY();
    this.fsLerpSnapW = this.ovRectW();
    this.fsLerpSnapH = this.ovRectH();
    this.fsLerpSnapVW = this.ovVideoW();
    this.fsLerpSnapVH = this.ovVideoH();
    logInfo(`[FSDBG] snapshot fs=${this.fs} dir=${this.fsLerpDir} P=${this.fsPanProgress.toFixed(3)} rect=(${this.fsLerpSnapX.toFixed(1)},${this.fsLerpSnapY.toFixed(1)},${this.fsLerpSnapW.toFixed(1)},${this.fsLerpSnapH.toFixed(1)}) vid=(${this.fsLerpSnapVW.toFixed(1)},${this.fsLerpSnapVH.toFixed(1)}) ctx: ovW=${this.ovW.toFixed(1)} ovH=${this.ovH.toFixed(1)} VDW=${this.videoDisplayWidth.toFixed(1)} VDH=${this.videoDisplayHeight.toFixed(1)} ar=${this.ar.toFixed(3)} shrink=${this.vidShrink.toFixed(2)} isLs=${this.isLs} lsvw=${this.lsvw.toFixed(1)} lsvh=${this.lsvh.toFixed(1)} cw=${this.cw.toFixed(1)} ch=${this.ch.toFixed(1)} cardMargin=${this.cardMargin} isLightsOff=${this.isLightsOff} isLV=${this.isLandscapeVertical}`);
  }
  /**
   * ⭐ 常驻层弹幕画布尺寸 = **播放器区域**（不是整个常驻层，也不是视频画面本身）。
   *
   * 三者的区别（真机横屏 2120×1320 = 833×519vp 实测）：
   *   · 常驻层               = [0,0,2120,1320]（全屏态）/ 视频槽（非全屏态）
   *   · **播放器区域（要的就是它）** = 全屏＝整屏；横屏/竖屏横看＝视频槽；竖屏＝视频区
   *   · 视频画面             = 播放器区域内按画幅适配后的那块画面（4:3 全屏时只有 692×519vp）
   *
   * ⚠️ 踩过的两个坑，别再来回改：
   *   ① 原先非全屏分支返回 `this.cw/ch`（**窗口**宽高）而组件是 `.width('100%')` 铺满常驻层 ⇒
   *      传参与 surface 两套尺寸，横屏下弹幕画到右侧评论栏上（"右侧堆着一堆弹幕"）；
   *   ② 修 ① 时把全屏也收成了"视频画面"⇒ **左右黑边里没有弹幕**，用户反馈"非播放区域被裁掉了"。
   *   ⇒ 正确的口径就是"播放器区域"：全屏时黑边属于播放器，弹幕应当铺满；非全屏时不得越出视频槽。
   */
  private ovDanmakuCW(): number {
    if (this.referenceLayout && this.isLs && !this.fs) return this.referenceLandscapeViewportWidth();
    if (this.referenceLayout && !this.fs && !this.isLs) {
      if (this.referenceFeed) {
        // ⭐ 连刷：弹幕区 = 整屏宽，不随视频画幅收窄（「完整显示」的左右黑边、横片上下留白里都有弹幕）。
        //    评论展开时按 amount 收回视频区宽度，避免弹幕盖住下方的评论列表。
        const full = Math.max(1, this.cw);
        const media = Math.max(1, this.referenceMediaWidth());
        return full + (media - full) * this.referenceFeedCommentAmount();
      }
      return Math.max(1, this.referenceMediaWidth());
    }
    if (this.fs) return Math.max(1, this.cw);
    if (this.isLs || this.isLandscapeVertical) return Math.max(1, this.lsvw);
    if (this.isLightsOff && !this.isLandscapeVertical) return Math.max(1, this.loVideoWidth());
    return Math.max(1, this.videoDisplayWidth);
  }
  private ovDanmakuCH(): number {
    if (this.referenceLayout && this.isLs && !this.fs) return this.referenceLandscapeAreaHeight();
    if (this.referenceLayout && !this.fs && !this.isLs) {
      if (this.referenceFeed) {
        // ⭐ 连刷：弹幕区高度 = 整屏减顶部安全区（底部到底），同样不随画幅收窄；评论展开按 amount 收回。
        const full = Math.max(1, this.ch - this.referenceSafeTop());
        const media = Math.max(1, this.referenceMediaHeight() - this.ovDanmakuSafeTopInset());
        return full + (media - full) * this.referenceFeedCommentAmount();
      }
      return Math.max(1, this.referenceMediaHeight() - this.ovDanmakuSafeTopInset());
    }
    if (this.fs) return Math.max(1, this.ch);
    if (this.isLs || this.isLandscapeVertical) return Math.max(1, this.lsvh);
    if (this.isLightsOff && !this.isLandscapeVertical) return Math.max(1, this.loVideoHeight());
    return Math.max(1, this.videoDisplayHeight);
  }
  /** 弹幕层在常驻层内的偏移：播放器区域在常驻层里是居中的（Stack 默认 Center 对齐） */
  private ovDanmakuX(): number {
    return Math.max(0, (this.ovRectW() - this.ovDanmakuCW()) / 2);
  }
  private ovDanmakuSafeTopInset(): number {
    if (!this.referenceLayout || this.fs || this.isLs ||
      (!this.referenceFeed && this.referenceFeedProgress <= 0)) return 0;
    // 按当前视频区域实际侵入安全区的部分避让，兼容连刷过渡、居中画幅和评论展开。
    return Math.min(Math.max(0, this.referenceMediaHeight() - 1),
      Math.max(0, this.referenceSafeTop() - this.ovRectY()));
  }
  private ovDanmakuY(): number {
    if (this.referenceLayout && !this.fs && !this.isLs) return this.ovDanmakuSafeTopInset();
    return Math.max(0, (this.ovRectH() - this.ovDanmakuCH()) / 2);
  }
  /**
   * ⭐ 连刷弹幕层的定位（层内坐标）：整屏口径下按「页面坐标」反推，不能沿用 ovDanmakuX/Y 的
   *    「在常驻层内居中」口径 —— 连刷里常驻层原点就是视频区左上角，整屏画布必须向左上越出层边界
   *    （常驻层 .clip(false)，越界可渲染；页面级 .clip(referenceFeed) 兜住不画出屏幕）。
   *    x：页面 x=0 在层坐标系里的位置；y：安全区下沿在层坐标系里的位置（横片在层中部时为负）。
   *    评论展开时随 amount 收回到原视频区矩形（与 ovDanmakuCW/CH 的混合同参）。
   */
  private dmPositionX(): number {
    if (this.referenceLayout && !this.fs && !this.isLs && this.referenceFeed) {
      return (this.cw - this.ovDanmakuCW()) / 2 - this.ovRectX();
    }
    return this.ovDanmakuX();
  }
  private dmPositionY(): number {
    if (this.referenceLayout && !this.fs && !this.isLs && this.referenceFeed) {
      const full = this.referenceSafeTop() - this.ovRectY();
      const media = this.ovDanmakuY();
      return full + (media - full) * this.referenceFeedCommentAmount();
    }
    return this.ovDanmakuY();
  }
  /**
   * 弹幕画布的「固定基准 + scale」通道只保留给非连刷竖屏半屏（防面板拖动期逐帧重建 canvas surface）。
   * 连刷弹幕画布本身就是恒定整屏尺寸（浏览/进连刷过渡期间宽高不变），直接量尺寸即可，不再跟视频
   * surface 共用 portraitBase+scale —— 否则整屏口径会被 scale 因子重新压回视频画幅。
   */
  private dmTransformChannel(): boolean {
    return this.portraitScaleByTransform() && !this.referenceFeed;
  }
  private dmScaleFactor(): number {
    return this.dmTransformChannel() ? this.portraitScaleFactor() : 1;
  }
  /** ⭐ 首次 build 前同步估算常驻层矩形（首帧后由占位槽 onAreaChange 精确接管） */
  private initOverlayRectSync(): void {
    if (this.isLandscapeVertical) {
      this.ovW = this.lsvw;
      this.ovH = this.lsvh;
      this.ovX = this.isLayoutSwapped ? (this.cw - this.lsvw - 80 - this.cardMargin) : (80 + this.cardMargin);
      this.ovY = this.cardMargin;
    } else if (this.isLs) {
      this.ovW = this.lsvw;
      this.ovH = this.lsvh;
      this.ovX = this.isLayoutSwapped ? (this.cw - this.lsvw - this.cardMargin) : this.cardMargin;
      this.ovY = this.cardMargin;
    } else {
      const slotW = this.shrinkSlotW();
      this.ovW = slotW;
      this.ovH = this.shrinkSlotH();
      this.ovX = this.cardMargin + (this.cw - 2 * this.cardMargin - slotW) / 2;
      this.ovY = this.shrinkVideoTop();
    }
  }

  /**
   * ⭐ 「缩小 / 还原视频」的统一动画入口。
   * 三个触发点（悬浮按钮 / 评论上滑 / 滚动触发）与三处自动还原（切 tab、转横屏、左右滑切 tab）
   * 全部改走这里，保证行为一致。
   *
   * ⚠️ 用 `animateTo` 而不是自己 setInterval 逐帧推进 —— 这一点试错过两轮，别再改回去：
   *    逐帧推进虽然能让所有消费方读到同一个连续值（同步最好），但 **JS 定时器不对齐 vsync**，
   *    每次 tick 各自找时机渲染，帧间隔在 14/18/22ms 之间抖 → 观感是 judder（真机"卡卡的"），
   *    而且日志里每帧都会出现 `RSNode::AddChild(video_xcSurface)`。`animateTo` 是渲染侧动画、
   *    由 vsync 驱动，节奏天然均匀。
   *
   * 三层同步靠的是下面三件事，而不是逐帧推进：
   *   ① 全部 8 个写入点都走本方法 —— 同一个 animateTo 作用域，时长曲线完全一致；
   *   ② `shrinkAnimating` 期间把常驻播放层那两条隐式 `.animation()` 的时长改成与本方法**同参**
   *      （SHRINK_ANIM_DURATION + EaseOut）。⚠️ 不是降为 0：节点自带的 `.animation()` 会**覆盖**
   *      外层 animateTo —— 写 120 时它先到位、写 0 时它瞬跳，两者都不同步；只有同参才对齐；
   *   ③ 弹幕画布在动画期间冻结尺寸（`dmFreezeW/H`）—— 否则画布每帧重建 surface；
   *      同时整段关掉弹幕渲染（见下）。
   *   容器矩形仍走 onAreaChange 异步路径，跨一帧，但每帧只差总位移的约 3%，看不出来。
   */
  /**
   * ⭐ 缩小后自动暂停 / 还原后继续（个性化「缩小后暂停播放」开关）。
   *   - 只在**由本开关触发**的暂停上恢复：用户缩小前本来就是暂停态时不自动播放；
   *   - **不动 `userPaused_`**：那是「用户主动暂停」的语义，被别处用于自动播放判定，
   *     这里若改写它会造成"还原后不自动播放"之类的连带 bug。
   */
  private applyShrinkPause(shrunk: boolean): void {
    if (!this.shrinkPauseOnMinimize) return;
    if (!this.av) return;
    if (shrunk) {
      if (!this.play) return;
      this.shrinkPausedByPref_ = true;
      this.av.pause();
      this.avAudio?.pause();
      this.play = false;
      LiveViewHelper.updatePlayState(false);
    } else {
      if (!this.shrinkPausedByPref_) return;
      this.shrinkPausedByPref_ = false;
      // ⭐ 缩小期间视频可能已经播完：还原时不能把它从头拉起来（听起来就是“播完又从头出声”）。
      if (this.playbackIsTerminal()) {
        logInfo('[VideoPlayer] 缩小还原跳过起播：视频已播完');
        return;
      }
      this.markAutoPlay('shrink-restore');
      this.av.play();
      this.avAudio?.play();
      this.play = true;
      LiveViewHelper.updatePlayState(true);
    }
  }

  private animateVidShrink(target: number): void {
    // 重入：上一次动画若还在飞，先把它留下的状态补回来（弹幕开关、冻结），再从当前值继续。
    // ⚠️ 用代数号而不是定时器句柄：animateTo 的 onFinish 可能在新一轮已开始之后才触发，
    //    靠句柄无法区分，会导致新一轮的冻结/关闭被旧的收尾误清掉。
    this.shrinkAnimGen++;
    const gen = this.shrinkAnimGen;
    if (this.shrinkAnimating) {
      this.danmakuConfig.enable = this.isDanmakuEnabled;
    }
    const from = this.vidShrink;
    const to = Math.min(1, Math.max(0, target));
    if (Math.abs(to - from) < 0.001) {
      this.vidShrink = to;
      this.shrinkAnimating = false;
      this.dmFreezeW = 0;
      this.dmFreezeH = 0;
      this.applyShrinkPause(to > 0.5);
      return;
    }
    this.shrinkAnimating = true;
    // ⭐ 冻结弹幕画布尺寸（原因见 dmFreezeW 注释）：抓当前尺寸，动画期间不再跟随容器变化
    this.dmFreezeW = this.ovDanmakuCW();
    this.dmFreezeH = this.ovDanmakuCH();
    // ⭐ 关掉弹幕渲染循环：渲染循环是 60fps 的画布重绘，会和几何动画抢主线程。
    //    ⚠️ 不只是"动画这 300ms"—— 缩小态**全程**都要关（缩小后小窗很小（默认 120vp 正圆），弹幕看不到还占主线程），
    //       所以收尾时按目标状态决定是否恢复：目标是缩小就保持关闭，否则恢复用户原值。
    // ⚠️ 这里**不记录**"动画前的 enable"再恢复 —— 缩小态下 enable 本身已是 false，
    //    若在"还原动画"开始时记录，记到的就是被自己关掉的值，还原后弹幕永远回不来（真机踩过）。
    //    恢复一律以用户开关 `isDanmakuEnabled` 为准：它由 syncDanmakuEnabled 同步维护，
    //    语义就是"用户想不想显示弹幕"，且不受本动画的临时关闭污染。
    this.danmakuConfig.enable = false;

    const finish = (): void => {
      if (this.shrinkAnimGen !== gen) return;   // 已被更新的一轮取代，不要动它的状态
      this.vidShrink = to;                      // 收尾落到精确目标值（阈值判断依赖它）
      this.shrinkAnimating = false;
      this.dmFreezeW = 0;
      this.dmFreezeH = 0;
      // 缩小态：保持关闭；还原态：恢复**用户开关**（不是"动画前的值"——见下面那段注释）
      this.danmakuConfig.enable = (to > 0.5) ? false : this.isDanmakuEnabled;
      // ⭐ 缩小后暂停播放（在动画收尾时执行：动画期间还在播，缩到位才停）
      this.applyShrinkPause(to > 0.5);
    };
    try {
      this.getUIContext().animateTo(
        { expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.SHRINK_ANIM_DURATION, curve: Curve.EaseOut, onFinish: finish },
        () => { this.vidShrink = to; });
    } catch (_) {
      finish();
    }
  }

  /** ⭐ 内容 Column 全局锚点（旋转/分屏等导致页面偏移时保证常驻层坐标系正确） */
  private onColumnArea = (o: Area, n: Area) => {
    const gp = n.globalPosition;
    if (!gp) return;
    const ax = gp.x as number;
    const ay = gp.y as number;
    setTimeout(() => {
      this.ovAnchorX = ax;
      this.ovAnchorY = ay;
    }, 0);
  };
  /** ⭐ 分支占位槽：把当前分支视频容器的实际布局矩形同步给常驻播放器层 */
  private onSlotArea = (o: Area, n: Area) => {
    const w = n.width as number;
    const h = n.height as number;
    if (w <= 0 || h <= 0) return;
    const gp = n.globalPosition;
    const x = (gp ? (gp.x as number) : 0) - this.ovAnchorX;
    const y = (gp ? (gp.y as number) : 0) - this.ovAnchorY;
    if (x !== this.ovX || y !== this.ovY || w !== this.ovW || h !== this.ovH) {
      logInfo(`[FSDBG] slot rect=(${x.toFixed(1)},${y.toFixed(1)},${w.toFixed(1)},${h.toFixed(1)}) fs=${this.fs}`);
      // ⭐ 延迟到本帧渲染结束后应用（onAreaChange 期间改 @State 属渲染中改状态）
      setTimeout(() => {
        this.ovX = x;
        this.ovY = y;
        this.ovW = w;
        this.ovH = h;
      }, 0);
    }
  };

  /** ⭐ 内容分支键：非全屏时取当前布局状态；fs 期间冻结为进入前的快照分支 */
  private contentBranchKey(): string {
    if (this.fs || this.fsEntering || this.isAnimatingToFS) return this.preFsBranch;
    return this.isLandscapeVertical ? 'lv' : (this.isLs ? 'isLs' : 'portrait');
  }

  /** ⭐ 转场状态翻转（fs / rotationInProgress 任一变化）：转场中评论区瞬时隐藏并移出布局；
     全部转场结束后（非全屏且旋转完成）渐显回来 */
  private onTransitionFlip(): void {
    // 同方向的半屏/全屏切换没有旋转回调，也必须立即更新系统栏。
    this.manageSB(true);
    if (!this.fs || this.rotationInProgress) this.resetFullscreenVideo();
    this.onPlaybackViewportChanged();
    // ⭐ 全屏/旋转期间暂停封面流光定时器（封面 linearGradient 每帧重算抢主线程，影响全屏动画帧率）；
    //   转场结束后若封面仍显示（视频未就绪）则恢复流光
    if (this.fs || this.rotationInProgress) {
      if (this.coverGlowTimer) {
        clearInterval(this.coverGlowTimer);
        this.coverGlowTimer = 0;
      }
      this.commentFade = 0;
      return;
    }
    if (!this.coverGlowTimer && !this.contentVisible) {
      this.coverGlowTimer = setInterval(() => { this.coverGlowAngle = (this.coverGlowAngle + 3) % 360; }, 16);
    }
    setTimeout(() => {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.EaseOut }, () => {
        this.commentFade = 1;
      });
    }, 0);
  }

  /** ⭐ 视频就绪（封面永久隐藏）后停止流光定时器，避免定时器空转 */
  private onContentVisibleChange(): void {
    if (this.contentVisible && this.coverGlowTimer) {
      clearInterval(this.coverGlowTimer);
      this.coverGlowTimer = 0;
    }
  }

  /** ⭐ 评论区转场可见性：转场期间（全屏/旋转中）移出布局（不参与重排），结束后渐显 */
  private commentAreaVis(): Visibility {
    return (this.fs || this.rotationInProgress) ? Visibility.None : Visibility.Visible;
  }
  /** ⭐ 进入全屏前快照当前内容分支（fs 期间冻结渲染，退出后分支条件不变 → 零重挂载） */
  private snapshotPreFsBranch(): void {
    this.preFsBranch = this.isLandscapeVertical ? 'lv' : (this.isLs ? 'isLs' : 'portrait');
    this.fullscreenSource = {
      isLandscape: this.isLs,
      orientation: this.mw?.getPreferredOrientation() ?? window.Orientation.AUTO_ROTATION,
      feed: this.referenceFeed,
      feedProgress: this.referenceFeedProgress,
      feedComments: this.referenceFeedComments,
      infoHidden: this.referenceInfoHidden,
      panelOffset: this.referencePanelOffset
    };
  }
  /** ⭐ 内容分支常驻渲染：与常驻播放器层配合，旋转只改几何不换子树 */
  @Builder
  buildContentBranch() {
    this.ReferencePortrait()
  }

  /** ⭐ 关灯+竖屏非全屏（本布局分支内必为竖屏）+横画幅，且开启"关灯视频外弹幕"：弹幕平移到视频下方空白区 */
  private isLightsOffDanmakuOutside(): boolean {
    return this.isLightsOff && this.ar >= 1 && this.lightsOffDanmakuOutside;
  }
  /** ⭐ 关灯+竖屏横看（竖屏视频横屏非全屏）且开启"关灯视频外弹幕"：弹幕平移到右侧空白区 */
  private isLightsOffDanmakuRight(): boolean {
    return this.isLightsOff && this.isLandscapeVertical && this.ar < 1 && this.lightsOffDanmakuOutside;
  }
  @State sp: boolean = false; @State qp: boolean = false; @State rp: boolean = false; @State @Watch('onPlaybackViewportChanged') mp: boolean = false; @State mpb: boolean = false; @State cacheQnPopup: boolean = false; @State colorStylePopup: boolean = false; @State ip: boolean = false; @State cp: boolean = false  // ⭐ cp=全屏评论浮层开关
  // ⭐ 缓存提示条（可点击跳转缓存列表页）：visible=显示, done=是否已完成, paused=是否已暂停
  @State cacheHintVisible: boolean = false
  @State cacheHintDone: boolean = false
  @State cacheHintPaused: boolean = false
  // ⭐ 缓存提示条拖拽位置（可随意拖动，位置持久化）
  @StorageLink('cacheHintLeft') cacheHintLeft: number = 16
  @StorageLink('cacheHintBottom') cacheHintBottom: number = 96
  // ⭐ 缓存提示条拖拽状态
  @State private cacheHintDragStartX: number = 0
  @State private cacheHintDragStartY: number = 0
  // ⭐ 提示条关闭按钮点击标志（ClickEvent 无 stopPropagation，阻止冒泡触发跳转）
  private hintCloseClicked_: boolean = false
  @State cs: string = 'original' // 当前画风：original/vivid/leica/film
  @State icp: boolean = false  // instantClosePopup：退出全屏时弹窗瞬间关闭，不播放退出动画
  @State sw: number = 300; @State qn: number = 116; @State ql: string = '1080P60'
  /**
   * 用户偏好画质：只由设置项与手动切画质改变，取流始终以它为上限。
   * `qn` 是「当前这条实际下发的画质」，服务端降级会把它改小，但绝不回写这里；
   * 否则一条最高 720P 的稿件会把后续整串连刷锁死在 720P（画质棘轮）。
   */
  private preferredQn: number = 116
  @State private hdrUiHeadroom: number = 1;
  private hdrUiDisplayId: number = -1;
  private hdrUiSubscribed: boolean = false;
  private onHdrUiBrightness = (displayId: number, info: display.BrightnessInfo): void => {
    if (displayId !== this.hdrUiDisplayId) return;
    // Brightness ramps can emit every display frame. Only update UI when the
    // usable boost changes by a quarter step, and stop invalidating above the cap.
    const headroom = Number.isFinite(info.currentHeadroom) ?
      Math.floor(Math.max(1, Math.min(4, info.currentHeadroom)) * 4) / 4 : 1;
    if (Math.abs(this.hdrUiHeadroom - headroom) < 0.01) return;
    this.hdrUiHeadroom = headroom;
    console.info(`[PlaybackHdrUi] headroom=${headroom} sdrNits=${info.sdrNits} quality=${this.qn}`);
  };

  private startHdrUiBrightness(): void {
    if (!deviceInfo.apiAvailable(24)) return;
    try {
      this.hdrUiDisplayId = display.getDefaultDisplaySync().id;
      this.onHdrUiBrightness(this.hdrUiDisplayId, display.getBrightnessInfo(this.hdrUiDisplayId));
      display.on('brightnessInfoChange', this.onHdrUiBrightness);
      this.hdrUiSubscribed = true;
    } catch (error) { logWarn('读取 HDR 控件亮度失败', error); }
  }

  private stopHdrUiBrightness(): void {
    if (!this.hdrUiSubscribed) return;
    try { display.off('brightnessInfoChange', this.onHdrUiBrightness); } catch (_error) {}
    this.hdrUiSubscribed = false;
  }

  private hdrUiRatio(): number {
    return playbackHdrUiRatio(this.qn, this.hdrUiHeadroom);
  }
  @State qs: boolean = false; @State vd: VideoDetail | null = null
  @State relatedVideos: RecommendItem[] = []; @State relatedLoading: boolean = false; @State relatedPressedId: string = ''
  // ⭐ 相关推荐限量渲染：详情卡是异构 Scroll，无法整体改 List（LazyForEach 在 Scroll 里不生效）——
  //    首屏只挂载前 10 条，"展开更多"递增；旋转/全屏重布局负载与列表总长解耦
  @State relatedRenderCount: number = 10
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.relatedVideos = this.relatedVideos.filter(item => !VideoCardFeedback.isDismissed(item.id, item.ownerMid));
  }
  // ⭐ 评论区限量渲染：只挂载前 commentRenderCount 条，"展开更多评论"递增（负载与评论总数解耦）
  @State commentRenderCount: number = 20
  private commentRenderCountFull: number = 20  // 旋转前保存累积渲染配额，旋转结束恢复
  @State ldc: boolean = false; @State ldd: boolean = false
  @State private referenceCommentRefreshing: boolean = false;
  @State commentCursor: number = 0; @State hm: boolean = true; @State at: number = 0
  // 限流状态
  @State rateLimited: boolean = false;
  // ⭐ 评论加载更多锁（防止滚动到底部重复触发）
  @State isLoadingMore: boolean = false;
  // ⭐ 排序切换防抖
  private sortChangeTimer: number | undefined = undefined;
  // 评论数据源（用于 LazyForEach）
  private commentDataSource: CommentDataSource = new CommentDataSource();
  // ⭐ 延迟评论区加载（等页面入场动画完成后才加载）
  @State commentsInitialized: boolean = false;
  // 回复分页状态（已整合到 ObservableComment 中，此处保留用于兼容）
  @State replyPageMap: Map<number, number> = new Map();
  // ⭐ B站登录状态
  @StorageLink('biliCookie') biliCookie: string = '';
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') @Watch('rebuildSegmentOptions') customThemeColor: string = '#007DFF';
  @StorageLink('videoBgMode') videoBgMode: string = 'cover';
  @StorageLink('videoBgColor') videoBgColor: string = '#007DFF';
  @StorageLink('shrinkVideoOnScroll') shrinkVideoOnScroll: boolean = false;
  // ⭐ 缩小后的小窗样式（个性化 → 视频页动画）：circle / square / ratio / hidden
  @StorageLink('shrinkWindowStyle') shrinkWindowStyle: string = 'circle';
  // ⭐ 缩小后自动暂停播放（还原时按需继续）
  @StorageLink('shrinkPauseOnMinimize') shrinkPauseOnMinimize: boolean = false;
  // ⭐ 缩小后小窗的尺寸（vp，个性化 → 视频页动画 → 小窗大小）
  @StorageLink('shrinkWindowSize') shrinkWindowSize: number = 120;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('playerFollowTheme') @Watch('rebuildSegmentOptions') playerFollowTheme: boolean = false;
  @StorageLink('cardBgBlurAmount') cardBgBlurAmount: number = 24;
  @StorageLink('cardBgDarkness') cardBgDarkness: number = 50;
  @StorageLink('videoBgCustomWallpaper') videoBgCustomWallpaper: string = '';
  @StorageLink('videoBgCustomWallpaperBlur') videoBgCustomWallpaperBlur: number = 0;
  @StorageLink('videoBgCustomWallpaperDarkness') videoBgCustomWallpaperDarkness: number = 50;
  @StorageLink('cardTransparentStyleVideo') cardTransparentStyleVideo: boolean = false;
  @StorageLink('cardStyleVideoDetail') cardStyleVideoDetail: boolean = true;
  @StorageLink('cardStyleVideoCommentSection') cardStyleVideoCommentSection: boolean = true;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardMargin') @Watch('onCardMarginChange') cardMargin: number = 12;
  @StorageLink('cardBorderRadius') cardBorderRadius: number = 20;
  @StorageLink('cardStyleVideoDescription') cardStyleVideoDescription: boolean = true;
  @StorageLink('cardStyleVideoSegmentBtn') cardStyleVideoSegmentBtn: boolean = true;
  @StorageLink('cardStyleVideoInteractBtns') cardStyleVideoInteractBtns: boolean = true;
  @StorageLink('cardStyleVideoNavBtns') cardStyleVideoNavBtns: boolean = true;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  // ⭐ 全屏切换动画开关（统一为视频连续缩放平移；关闭=瞬时切换）
  @StorageLink('fsAnimOn') fsAnimOn: boolean = true;
  // ⭐ 页面加载动画模式
  @StorageLink('pageEnterAnim') pageEnterAnim: string = 'none';
  // ⭐ 页面加载动画最终参数（固定不可调）
  private readonly PE_ENTER_DURATION: number = 400;   // 名义时长 ms
  private readonly PE_ENTER_VELOCITY: number = 0.5;   // 弹簧初速：越大冲得越猛/回弹感越强
  private readonly PE_ENTER_DAMPING: number = 13;     // 弹簧阻尼：越大回弹越少
  @State pageEnterProgress: number = 0
  // ⭐ 全屏切换动画时长（ms，固定）
  private readonly FS_ANIM_DURATION: number = 200;
  // ⭐ 全屏手势回弹刚度（固定）
  private readonly FS_SPRING_STIFFNESS: number = 28;
  // ⭐ PC/2in1 屏幕窗口固定不旋转：全屏走"窗口内全屏"分支（跳过旋转 API，手动切横屏布局）
  private readonly isPcDevice: boolean = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'pc';
  private pcPreFsIsLs: boolean = false;  // PC 进入全屏前的 isLs，退出时恢复
  @StorageLink('da') da: boolean = false;

  // ═══ 页面加载动画计算方法（由 pageEnterProgress 驱动，0→1）═══
  private calcPageEnterScaleX(): number {
    const P = this.pageEnterProgress;
    if (this.pageEnterAnim === 'none') return 1;
    if (this.pageEnterAnim === 'scaleFade') return P;
    if (this.pageEnterAnim === 'cardStack') return 0.9 + 0.1 * P;
    if (this.pageEnterAnim === 'flip') return P;
    if (this.pageEnterAnim === 'minimizeCorner') return P;
    if (this.pageEnterAnim === 'diagonal') return P;
    return 0.85 + 0.15 * P;
  }
  private calcPageEnterScaleY(): number {
    const P = this.pageEnterProgress;
    if (this.pageEnterAnim === 'none') return 1;
    if (this.pageEnterAnim === 'scaleFade') return P;
    if (this.pageEnterAnim === 'cardStack') return 0.9 + 0.1 * P;
    if (this.pageEnterAnim === 'flip') return 1;
    if (this.pageEnterAnim === 'minimizeCorner') return P;
    if (this.pageEnterAnim === 'diagonal') return P;
    return 0.85 + 0.15 * P;
  }
  private calcPageEnterOffsetX(): number {
    if (this.pageEnterAnim === 'none') return 0;
    if (this.pageEnterAnim === 'slideLeftRight') return (1 - this.pageEnterProgress) * this.cw;
    if (this.pageEnterAnim === 'diagonal') return (1 - this.pageEnterProgress) * this.cw * 0.3;
    return 0;
  }
  private calcPageEnterOffsetY(): number {
    const P = this.pageEnterProgress;
    if (this.pageEnterAnim === 'none') return 0;
    if (this.pageEnterAnim === 'cardStack') return (1 - P) * this.ch * 0.3;
    if (this.pageEnterAnim === 'slideUpDown') return (1 - P) * this.ch;
    if (this.pageEnterAnim === 'diagonal') return (1 - P) * this.ch * 0.3;
    if (this.pageEnterAnim === 'minimizeCorner') return (1 - P) * (this.ch / 2);
    return 0;
  }
  private calcPageEnterOpacity(): number {
    if (this.pageEnterAnim === 'none') return 1;
    if (this.pageEnterAnim === 'scaleFade' || this.pageEnterAnim === 'blurFade') return this.pageEnterProgress;
    return 1;
  }
  private calcPageEnterBlur(): number {
    if (this.pageEnterAnim === 'none') return 0;
    if (this.pageEnterAnim === 'blurFade') return (1 - this.pageEnterProgress) * 15;
    return 0;
  }

  @State isBiliLoggedIn: boolean = false;
  @State hasMoreRepliesMap: Map<number, boolean> = new Map();
  @State loadingRepliesMap: Map<number, boolean> = new Map();
  // ⭐ SegmentButton 的 options 参数是 @ObjectLink，必须传状态变量（编译强制）；
  //   主题色/跟随开关变化由 @Watch('rebuildSegmentOptions') 重建保证生效
  @State tabOpt: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '详情' }, { text: '评论' }],
    fontColor: $r('app.color.color_player_text_secondary'),
    selectedFontColor: $r('app.color.color_player_text'),
    fontWeight: FontWeight.Normal,
    selectedFontWeight: FontWeight.Medium,
    backgroundColor: Color.Transparent,
    selectedBackgroundColor: this.playerFollowTheme ? this.customThemeColor : $r('app.color.color_bilibili_pink'),
    fontSize: 14,
    selectedFontSize: 14,
    buttonPadding: { top: 8, right: 16, bottom: 8, left: 16 },
  })
  @State tabSelIdx: number[] = [0]
  @State swipeProgress: number = 0   // 滑动偏移进度: 0=详情, -1=评论(左滑), 1=右滑
  @State isSwiping: boolean = false   // 是否正在执行滑动手势
  @State @Watch('onPlaybackViewportChanged') isLs: boolean = false
  @State isAnimatingToFS: boolean = false
  @State fsEntering: boolean = false  // 进入全屏旋转期间常驻层固定在快照位置
  @State fsPanProgress: number = 0
  @State fsLerpStartP: number = 0  // 全屏插值动画起点(手势全屏时=当前fsPanProgress,点击全屏时=0)
  private fsLerpT(): number { if (this.fsLerpStartP >= 1) return 1; return Math.min(1, Math.max(0, (this.fsPanProgress - this.fsLerpStartP) / (1 - this.fsLerpStartP))); }
  private fsHapticPrev: number = 0
  private detailScroller: Scroller = new Scroller()
  private episodeSwitchJob_: Promise<void> | null = null;
  private pendingEpisodeIndex_: number = -1;
  @State referenceEpisodeSelection: number = -1;
  private commentScroller: ListScroller = new ListScroller()  // 评论区滚动控制器（List 专用）
  private fsCommentScroller: ListScroller = new ListScroller() // 全屏评论浮层专用（与竖屏 List 隔离，避免同屏双 List 共用 scroller 互相污染滚动状态）
  private referenceIntroScrollState: ScrollState = ScrollState.Idle;
  @State isLandscapeVertical: boolean = false
  @StorageLink('phoneLayoutToggle') phoneLayoutToggle: boolean = false
  @State @Watch('onContentVisibleChange') contentVisible: boolean = false;
  @State coverGlowAngle: number = 0  // ⭐ 封面跑马灯流光角度
  private coverGlowTimer: number = 0  // ⭐ 流光动画定时器
  @State hdCoverReady: boolean = false  // ⭐ 1080w 封面预解码完成；未完成时封面回退原始 URL 秒显，避免黑屏
  // ⭐ 评论输入弹层（写评论/回复共用）
  @State commentThread: ObservableComment | null = null;
  @State commentDialog: ObservableComment | null = null;
  @State commentThreadRefresh: number = 0;
  @State @Watch('onDanmakuComposerChanged') commentSheetVisible: boolean = false;
  @State commentComposerHeight: number = 184;
  @State private commentComposerProgress: number = 0;
  @State private commentComposerClosing: boolean = false;
  private commentComposerAnimator: AnimatorResult | null = null;
  private composerKeyboardAnimator: AnimatorResult | null = null;
  private commentComposerStartTimer: number = 0;
  private commentComposerOrigin: number[] = [0, 0, 0, 40];
  @State commentSheetMode: string = 'new'  // 'new' = 写评论 | 'reply' = 回复
  @State replyRoot: number = 0
  @State replyParent: number = 0
  @State replyTargetName: string = ''
  // ⭐ 发弹幕弹层
  @State @Watch('onDanmakuComposerChanged') showDanmakuSheet: boolean = false
  private danmakuFocusTimer: number = 0;
  @State private danmakuKeyboardHeight: number = 0
  private landscapeComposerAvoidMode: KeyboardAvoidMode | null = null;
  private composerControlsWereVisible: boolean = false;
  // ⭐「更多 → 弹幕设置」详细面板（PiliPlus showSetDanmaku 同款）
  @State showDanmakuSettingSheet: boolean = false
  private dmSettingApplyTimer: number = 0   // 「应用设置」防抖句柄
  private dmSettingVersion: number = 0      // 递增版本号 → AppStorage → DanmakuView @Watch
  // ⭐ 用户是否已经动过弹幕设置。读取持久化是异步的（Preferences），若返回值晚于用户第一次
  //   拖动滑块，会把刚改的值覆盖回上次存档 —— 表现为"改了没生效，滑块却停在新位置"。
  //   一旦用户动过，就丢弃这次读盘结果（本次会话以用户输入为准）。
  private dmSettingsTouched: boolean = false
  @State dmComposerSettings: boolean = false
  @State dmMode: number = 1            // B站弹幕模式：1=滚动 4=底部 5=顶部
  @State selfDanmakuList: DanmakuItem[] = []  // 自发弹幕（发送成功后注入弹幕层上屏）
  @State expandedCommentIds: Set<number> = new Set()  // 当前展开的评论ID集合（支持多评论同时展开）
  private savedScrollOffsetMap: Map<number, number> = new Map()  // 每个展开评论记录的滚动位置
  @State repliesVersion: number = 0  // 用于强制ForEach刷新

  // ⭐ 智感握持 - 安全区域原始值（px→vp转换后）
  @State private gripSafeAreaBottom: number = 80;   // 默认值，仅兜底
  @State private gripSafeAreaRight: number = 24;    // 默认值，仅兜底
  @State private gripSafeAreaLeft: number = 24;     // 默认值，仅兜底
  // ⭐ 延迟加载评论：等页面入场动画完成后才加载
  private pendingCommentAid: number = 0;
  // ⭐ PGC 季信息复用缓存：ensurePgcContext() 为补 seasonId/aid 已经完整拉过一次季接口，
  //   而季接口在 API 层【没有缓存】，若不留下这份结果，接下来填详情卡片/评论会再发一次
  //   完全相同的请求（多 100~300ms 的无谓等待）。存下来给 fillPgcDetailFromSeason() 复用。
  private pgcSeasonInfoCache_: PgcSeasonInfo | null = null;
  // ⭐ 评论定位：从消息通知跳转时，滚动到指定评论
  private commentRootId_: number = 0;
  private commentSecondaryId_: number = 0;
  // ⭐ 智感握持 - 最终计算出的按钮定位（随热区和方向动态变化）
  @State private smartGripBottom: number = 120;     // 底部边距(vp)
  @State private smartGripRight: number = 32;       // 右侧边距(vp)
  @State private smartGripLeft: number = -1;        // 左侧边距(vp, -1=不启用)
  // ⭐ 智感握持 - 当前握持状态（LEFT_HAND_HELD/RIGHT_HAND_HELD…）
  @State private hand: number = 16;                 // motion.HoldingHandStatus.UNKNOWN_STATUS
  // ⭐ 智感握姿开关
  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  @StorageLink('floatBtnFollowTheme') floatBtnFollowTheme: boolean = true;
  // ⭐ 拖拽自定义按钮位置（智感握姿关闭时生效）
  @StorageLink('videoShrinkBtnSide') videoShrinkBtnSide: string = 'right';
  @StorageLink('videoShrinkBtnY') videoShrinkBtnY: number = 120;
  @StorageLink('videoLightBtnSide') videoLightBtnSide: string = 'right';
  @StorageLink('videoLightBtnY') videoLightBtnY: number = 120;
  // ⭐ 缩小按钮拖拽状态
  // ⭐ 关灯按钮拖拽状态
  @State private lightDragStartY: number = 0;
  @State private lightDragOffsetX: number = 0;
  @State private lightIsDragging: boolean = false;
  @State private maxFloatBtnBottom: number = 592; // 按钮顶部距屏幕顶部至少80vp
  // 是否已监听握持事件（防止重复监听）
  private gripListenerSubscribed: boolean = false;

  // ⭐ 互动状态（点赞、投币、收藏）
  @State isDisliked: boolean = false
  @State isLiked: boolean = false
  @State isCoined: boolean = false
  @State isFavorited: boolean = false
  @State likeCount: number = 0
  @State coinCount: number = 0
  @State favoriteCount: number = 0
  // ⭐ 关注状态
  @State isFollowed: boolean = false
  @State followScale: number = 1
  // ⭐ 按钮动画状态
  @State likeScale: number = 1
  @State coinScale: number = 1
  @State favoriteScale: number = 1
  @State darkModeScale: number = 1  // 深色模式切换缩放
  @State darkModePressed: boolean = false  // 深色模式按钮点击变色
  // ⭐ 最小化到悬浮按钮动画状态
  @State minimizeScale: number = 1
  @State minimizePressed: boolean = false
  // ⭐ 返回按钮动画状态（横屏竖屏模式左下角）

  // ⭐ 后台播放开关（持久化）
  @StorageLink('bgp') bgp: boolean = false
  // ⭐ 监听 onBackground 时间戳，确认切后台后恢复播放
  @StorageLink('appBackgroundTimestamp') @Watch('onAppBackgroundConfirmed') appBgTimestamp: number = 0
  // ⭐ 应用是否已切后台（EntryAbility.onBackground/onForeground 维护）：区分「跳页」与「真后台」
  @StorageLink('appInBackground') @Watch('onAppBackgroundFlagChanged') appInBackground: boolean = false

  // ⭐ 选集状态
  @State currentPageIndex: number = 0  // 当前分P索引
  @State showEpisodeSheet: boolean = false  // 选集弹窗显示状态
  // ⭐ 选集列表 scroller（弹窗打开时定位到当前播放集数）
  private episodeScroller_: Scroller = new Scroller()
  // ⭐ 选集分段：当前所在段索引（0=1-20, 1=21-40...），用于分段栏高亮
  @State episodeSegment: number = 0
  @State episodeSheetInitialIndex: number = 0;

  // ⭐ 合集状态
  @State showSeasonSheet: boolean = false  // 合集弹窗显示状态
  private seasonScroller_: Scroller = new Scroller()
  @State seasonSectionIndex: number = 0  // 当前合集分区索引
  @State seasonSheetInitialIndex: number = 0;
  /** 合集切集序号：只认最后一次切换的详情回包，避免连点/退出后旧响应覆盖当前集 */
  private seasonSwitchSeq_: number = 0;
  /** 当前 `vd` 属于哪条视频（bvid）。aid 入口时 `vi.bvid` 是数字串，不能直接拿它比 */
  private vdBvid_: string = '';

  // ⭐ 屏幕旋转模式状态
  @State rotationMode: string = 'system'  // 'system' | 'auto' | 'portrait' | 'landscape'
  private rotationFreeMode: string = 'system'
  @State rotationScale: number = 1  // 旋转按钮缩放动画
  @State rotationPressed: boolean = false  // 旋转按钮点击变色
  @StorageProp('landscapePlaybackSide') @Watch('onLandscapePlaybackSideChanged') landscapePlaybackSide: string = 'left';
  @State isLayoutSwapped: boolean = false  // 是否切换布局（横屏非全屏模式）
  @State layoutSwapScale: number = 1  // 布局切换按钮缩放动画
  @State layoutSwapPressed: boolean = false  // 布局切换按钮点击变色
  // ⭐ 全屏控制栏镜像状态（与 VideoControls 双向绑定）：比例/画质/更多弹窗跟随镜像换侧
  @State isMirrorControls: boolean = false
  @State referenceMirrorVideo: boolean = false
  @State referenceStopAtEnd: boolean = false
  @State referenceSleepMinutes: number = 0
  @State referenceSleepDeadline: number = 0
  @State referenceCustomSleep: string = ''
  @State referenceShowCustomSleep: boolean = false
  @State referencePlaybackMode: string = 'single'
  @State referenceFeedPortraitScaleMode: string = 'fill'
  @State referenceFeedPortraitScaleScope: string = 'standard'
  private referenceSleepTimer: number = -1

  // ⭐ 竖屏评论区上滑视频缩小状态
  @State vidShrink: number = 0  // 0=正常大小, 1=完全缩小到迷你尺寸（由 animateVidShrink 统一驱动）
  /**
   * ⭐ 缩小/还原动画进行中标志。**只用于把常驻播放层那两条隐式 `.animation()` 的时长
   * 改成与共享 animateTo 同参**（SHRINK_ANIM_DURATION + EaseOut）：
   * 节点自带的 `.animation()` 会覆盖外层 animateTo，不改就会各走各的（播放器 120ms 先到位）。
   * 必须是 @State —— 它是 `.animation()` 的参数，改了要能触发重渲染。
   */
  @State shrinkAnimating: boolean = false
  /**
   * 缩小/还原动画的代数号。animateTo 的 onFinish 可能在新一轮动画已经开始之后才触发，
   * 靠定时器句柄区分不了，会让旧一轮的收尾误清新一轮的冻结/弹幕开关状态。
   */
  private shrinkAnimGen: number = 0
  /** ⭐ 本次缩小是否由「缩小后暂停播放」触发的暂停（还原时据此决定是否继续） */
  private shrinkPausedByPref_: boolean = false
  private readonly SHRINK_ANIM_DURATION: number = 300
  /**
   * ⭐ 缩小/还原动画期间弹幕层的**冻结尺寸**（vp，0 = 不冻结、尺寸跟随容器）。
   *
   * 为什么必须冻结：`DanmakuView` 的 `Canvas` 是 `.width('100%')`（跟随本层容器），而缩小动画期间
   * 容器矩形是**每帧都在变**的（animateTo 驱动 + onAreaChange 回填），画布尺寸于是也跟着每帧变，
   * 而 `Canvas.onReady` 每次尺寸变化都会重新初始化：
   * `TrackManager 初始化轨道` + `RSCanvasDrawingNode::ResetSurface`（重建 GPU surface）。
   * 真机日志实测 300ms 内发生 **19 次**，必然掉帧。
   * 冻结后画布尺寸只在动画起、止各变一次；动画期间多出来的部分由外层容器的 `clip(true)` 裁掉
   * （观感是"弹幕被盒子边缘裁走"而不是随视频一起缩小）。
   */
  private dmFreezeW: number = 0
  private dmFreezeH: number = 0
  // ⚠️ 刻意**不持有**"缩小前的弹幕开关"快照：缩小态下 enable 已被置 false，
  //    记快照会把"被自己关掉的值"当成用户设置，导致还原后弹幕不恢复。一律以 isDanmakuEnabled 为准。
  @State floatBtnOpacity: number = 0  // 悬浮按钮延迟淡入
  @State floatBtnScale: number = 0  // 悬浮按钮弹入缩放
  @State floatBtnOffsetY: number = 12  // 悬浮按钮弹入Y偏移

  // ⭐ 横屏非全屏竖屏模式：评论区上滑详情卡片缩小状态

  // ⭐ 心跳上报定时器（每15秒上报一次观看进度）
  private heartbeatTimer: number = -1;
  private readonly HEARTBEAT_INTERVAL: number = 15000;  // 15秒
  private lastHeartbeatTime: number = 0;  // 上次心跳时的播放进度

  // ⭐ 评论排序状态：2=最热，1=最新
  @State commentSort: number = 2
  // ⭐ 排序栏版本号：每次切换排序时递增，强制刷新 UI
  @State sortBarVersion: number = 0
  // ⭐ 评论排序分段按钮选项（@State 理由同 tabOpt）
  @State commentSortOpt: SegmentButtonOptions = SegmentButtonOptions.capsule({
    buttons: [{ text: '最热' }, { text: '最新' }],
    fontColor: $r('app.color.color_player_text_secondary'),
    selectedFontColor: '#FFFFFF',
    fontWeight: FontWeight.Regular,
    selectedFontWeight: FontWeight.Medium,
    backgroundColor: Color.Transparent,
    selectedBackgroundColor: this.playerFollowTheme ? this.customThemeColor : $r('app.color.color_bilibili_pink'),
    fontSize: 12,
    selectedFontSize: 12,
    buttonPadding: { top: 9, right: 16, bottom: 9, left: 16 },
  })

  /** ⭐ 主题色/跟随开关变化时重建分段按钮 options（字段初始化器只拿到默认主题色，
      必须重建才能生效；aboutToAppear 首帧前同步调用一次，保证首次 build 即用正确主题色） */
  private rebuildSegmentOptions(): void {
    this.tabOpt = SegmentButtonOptions.capsule({
      buttons: [{ text: '详情' }, { text: '评论' }],
      fontColor: $r('app.color.color_player_text_secondary'),
      selectedFontColor: $r('app.color.color_player_text'),
      fontWeight: FontWeight.Normal,
      selectedFontWeight: FontWeight.Medium,
      backgroundColor: Color.Transparent,
      selectedBackgroundColor: this.playerFollowTheme ? this.customThemeColor : $r('app.color.color_bilibili_pink'),
      fontSize: 14,
      selectedFontSize: 14,
      buttonPadding: { top: 8, right: 16, bottom: 8, left: 16 },
    });
    this.commentSortOpt = SegmentButtonOptions.capsule({
      buttons: [{ text: '最热' }, { text: '最新' }],
      fontColor: $r('app.color.color_player_text_secondary'),
      selectedFontColor: '#FFFFFF',
      fontWeight: FontWeight.Regular,
      selectedFontWeight: FontWeight.Medium,
      backgroundColor: Color.Transparent,
      selectedBackgroundColor: this.playerFollowTheme ? this.customThemeColor : $r('app.color.color_bilibili_pink'),
      fontSize: 12,
      selectedFontSize: 12,
      buttonPadding: { top: 9, right: 16, bottom: 9, left: 16 },
    });
  }

  // ⭐ 弹幕开关状态
  @State isDanmakuEnabled: boolean = true  // 弹幕开关（默认开启）
  @State danmakuConfig: DanmakuConfig = new DanmakuConfig()  // 弹幕配置

  // ⭐ 详情卡片整卡下拉关灯状态（仿右滑全屏：整张卡片跟随手指下滑）
  private detailPullTouchAnchor: number = -1; // 本次下拉的触摸起点纵坐标（-1=未启动整卡下拉）
  private detailPullLastTouchY: number = -1; // 原始触摸纵坐标（上滑取消检测，不受手势竞争影响）
  private detailPullTouchStartX: number = -1; // 触摸按下点的横坐标（横向占优判定）
  private detailPullTouchStartY: number = -1; // 触摸按下点的纵坐标（横向占优判定）
  private detailPullTouchAtTop: boolean = false; // 按下时内容是否已在顶部（每次触摸仅查询一次）
  private detailPullPeakTouchY: number = -1; // 本次拖动触摸纵坐标峰值（累计回滑取消参照）
  private detailPullCanceled: boolean = false; // 回滑已取消（松手弹回，不触发关灯）
  private detailPullDragEngaged: boolean = false; // 本次触摸发生过整卡下拉（松手前锁定内部滚动）
  @State detailPullDrop: number = 0; // 下拉进度 0→1（卡片整体下移）
  @State detailPullHintPhase: number = 0; // 0=隐藏, 1=下拉关灯, 2=释放关灯

  // ⭐ 关灯模式（除视频区域外全黑）
  @State isLightsOff: boolean = false;
  @State lightBtnScale: number = 1;  // 开灯按钮点击弹性缩放
  @State lightbulbRotation: number = 0;  // 开灯图标旋转
  @StorageLink('lightsOffHideOnly') lightsOffHideOnly: boolean = false;  // 关灯模式仅隐藏组件（保留背景）
  @StorageLink('lightsOffShowBtn') lightsOffShowBtn: boolean = false;  // 关灯后显示开灯按钮（默认关闭）
  @StorageLink('lightsOffDanmakuOutside') lightsOffDanmakuOutside: boolean = true;  // 关灯视频外弹幕（默认开启）
  // ⭐ 关灯背景：封面/壁纸放大 + 模糊 + 压暗（仿 FullImagePreview rgba(0,0,0,0.72)）
  @State loBgScale: number = 1;
  @State loBgBlur: number = 0;
  @State loBgDim: number = 0;  // 0~0.72
  // ⭐ 开灯按钮自动隐藏
  @State lightBtnVisible: boolean = true;
  private lightBtnTimer_: number = -1;

  /** 关灯背景素材：优先当前背景模式（wallpaper 自定义壁纸，否则封面） */
  private lightsOffBgSrc(): string {
    if (this.videoBgMode === 'wallpaper' && this.videoBgCustomWallpaper) return 'file://' + this.videoBgCustomWallpaper;
    return imageUrlResize(this.vi.cover, 1080);
  }

  // ⭐ 触觉反馈
  private triggerHaptic(): void {
    VibrateUtils.vibrateTime(15);
  }


  // 同一视频的互动串行；结果只能回写发起请求时的页面和账号。
  private interactionPending: Set<string> = new Set<string>();
  private followPending: Set<number> = new Set<number>();
  private interactionRevision: number = 0;

  private async toggleLike(): Promise<void> {
    await this.runVideoInteraction('like', this.isLiked ? 'cancel' : 'add');
  }

  private async tripleAction(): Promise<void> {
    await this.runVideoInteraction('triple', 'add');
  }

  private async toggleCoin(multiply: number = 1): Promise<void> {
    if (this.isCoined) {
      this.getUIContext().getPromptAction().showToast({ message: '已投币，不能取消' });
      return;
    }
    await this.runVideoInteraction('coin', 'add', multiply);
  }

  private async toggleFavorite(): Promise<void> {
    await this.runVideoInteraction('favorite', this.isFavorited ? 'cancel' : 'add');
  }

  private async runVideoInteraction(type: 'like' | 'dislike' | 'coin' | 'favorite' | 'triple',
    action: 'add' | 'cancel', multiply: number = 1): Promise<void> {
    if (!this.vd || this.interactionPending.has(this.vi.bvid)) return;
    const bvid = this.vi.bvid;
    const detailAid: number = this.vd.aid;
    const generation = this.referenceSwitchGeneration;
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const prevLiked = this.isLiked;
    const prevDisliked = this.isDisliked;
    const prevCoined = this.isCoined;
    const prevFavorited = this.isFavorited;
    const prevLikes = this.likeCount;
    const prevCoins = this.coinCount;
    const prevFavorites = this.favoriteCount;
    const adding = action === 'add';
    this.interactionRevision++;
    if (type === 'like') {
      this.isLiked = adding;
      this.likeCount = Math.max(0, prevLikes + (adding ? 1 : -1));
      if (adding) this.isDisliked = false;
    } else if (type === 'dislike') {
      this.isDisliked = adding;
      if (adding && prevLiked) { this.isLiked = false; this.likeCount = Math.max(0, prevLikes - 1); }
    } else if (type === 'coin') {
      this.isCoined = true; this.coinCount += multiply;
    } else if (type === 'favorite') {
      this.isFavorited = adding; this.favoriteCount = Math.max(0, prevFavorites + (adding ? 1 : -1));
    }
    if (type === 'like' || type === 'triple') this.likeScale = 0.8;
    if (type === 'coin' || type === 'triple') this.coinScale = 0.8;
    if (type === 'favorite' || type === 'triple') this.favoriteScale = 0.8;
    setTimeout(() => { this.likeScale = 1; this.coinScale = 1; this.favoriteScale = 1; }, 160);
    this.interactionPending.add(bvid);
    let result: VideoInteractionResult;
    try {
      result = await UserBehaviorService.performInteraction({ bvid: bvid,
        aid: this.detailIsCurrentVideo() ? detailAid : (this.aidFromParams_ || detailAid),
        type: type, action: action, multiply: multiply });
    } catch (_) {
      result = { success: false, message: '操作未完成，请刷新状态后重试' };
    } finally { this.interactionPending.delete(bvid); }
    if (!this.referenceAlive || this.vi.bvid !== bvid || this.referenceSwitchGeneration !== generation ||
      cookie !== (AppStorage.get<string>('biliCookie') || '')) return;
    let message = result.message;
    if (!result.success) {
      this.isLiked = prevLiked; this.isDisliked = prevDisliked; this.isCoined = prevCoined;
      this.isFavorited = prevFavorited; this.likeCount = prevLikes;
      this.coinCount = prevCoins; this.favoriteCount = prevFavorites;
    } else if (type === 'triple' && result.triple) {
      const outcome = result.triple;
      this.isLiked = prevLiked || outcome.like;
      if (outcome.like) this.isDisliked = false;
      this.isCoined = prevCoined || outcome.coin;
      this.isFavorited = prevFavorited || outcome.fav;
      this.likeCount = prevLikes + (!prevLiked && outcome.like ? 1 : 0);
      this.coinCount = prevCoins + (outcome.coin ? outcome.multiply : 0);
      this.favoriteCount = prevFavorites + (!prevFavorited && outcome.fav ? 1 : 0);
    } else if (result.success) {
      if (type === 'like') message = adding ? '点赞成功' : '取消点赞';
      else if (type === 'dislike') message = adding ? '已标记不喜欢' : '已取消不喜欢';
      else if (type === 'coin') message = multiply === 2 ? '投币x2成功' : '投币成功';
      else if (type === 'favorite') message = adding ? '收藏成功' : '取消收藏';
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
      if (result.success) VibrateUtils.vibrateTime(50);
    } catch (error) { logWarn(`互动提示异常: ${errMsg(error)}`); }
  }

  // —— 开灯按钮自动隐藏/显示 ——
  private startLightBtnTimer(): void {
    this.clearLightBtnTimer();
    this.lightBtnTimer_ = setTimeout(() => {
      this.lightBtnVisible = false;
    }, 5000);
  }
  private clearLightBtnTimer(): void {
    if (this.lightBtnTimer_ !== -1) {
      clearTimeout(this.lightBtnTimer_);
      this.lightBtnTimer_ = -1;
    }
  }
  private toggleLightBtn(): void {
    if (this.lightBtnVisible) {
      this.lightBtnVisible = false;
      this.clearLightBtnTimer();
    } else {
      this.lightBtnVisible = true;
      this.startLightBtnTimer();
    }
  }

  // —— 切换深色/浅色模式 ——


  // —— 最小化到右下悬浮按钮 ——
  private async minimizeToFloating(): Promise<void> {
    if (this.floatingMorph || FloatingVideoTransition.active()) return;
    FloatingVideoTransition.begin('minimize');
    if (this.floatingPausedFrame && !this.play && !this.floatingMorph) {
      FloatingVideoTransition.pausedFrame = this.floatingPausedFrame;
    } else {
      if (FloatingVideoTransition.pausedFrame) {
        FloatingVideoTransition.pausedFrame.release().catch(() => {});
        FloatingVideoTransition.pausedFrame = undefined;
      }
      if (this.av && this.av.state !== 'playing') {
        try {
          FloatingVideoTransition.pausedFrame = await image.createPixelMapFromSurfaceWithTransformation(this.activeVideoSurfaceId(), true);
        } catch (_e) { logWarn('[FloatingMorph] paused frame readback unavailable'); }
      }
    }
    this.prepareFloatingGeometry();
    this.floatingCompact = 0;
    this.ub = false;
    // 点击动画
    this.minimizeScale = 0.9;
    this.minimizePressed = true;
    setTimeout(() => {
      this.minimizeScale = 1;
      this.minimizePressed = false;
    }, 150);
    this.triggerHaptic();

    // 保存当前播放状态到 AppStorage
    const minimizeState: MinimizedVideoState = {
      playbackRate: this.rt,
      isOffline: this.offlineVideoPath_.length > 0,
      bvid: this.vi.bvid,
      cid: this.vi.cid,
      title: this.vi.title,
      cover: this.vi.cover,
      currentTime: this.ct,
      duration: this.dur,
      isPlaying: this.play,
      quality: this.qn,
      qualityLabel: this.ql,
      qualities: this.getQlList().map((item: QI): QI => ({ qn: item.qn, label: item.label })),
      volume: this.vol,
      mute: this.mute,
      isLandscapeVertical: this.isLandscapeVertical,  // ⭐ 保存横屏竖屏视频模式
      videoAspectRatio: this.ar,                       // ⭐ 保存视频宽高比
      aid: this.detailIsCurrentVideo() ? (this.vd?.aid ?? this.aidFromParams_) : this.aidFromParams_,  // ⭐ 分集 aid（PGC 评论 oid）
      epId: this.epId_,                                // ⭐ PGC 分集 id
      seasonId: this.seasonId_,                        // ⭐ PGC 季 id
    };
    logInfo(`[Minimize] 保存播放状态: bvid=${this.vi.bvid}, title=${this.vi.title}, ct=${this.ct}s`);
    AppStorage.set('minimizedVideoState', JSON.stringify(minimizeState));
    // ⭐ 触发浮窗出现（aboutToAppear 会执行 animateIn 从右侧回弹滑入）
    AppStorage.set('videoMinimized', true);
    logInfo('[Minimize] AppStorage 状态已设置: videoMinimized=true');

    // Keep the player page alive until the system window has a real decoded Surface.
    const floatingPlayer = PlayerService.getInstance();
    floatingPlayer.takeoverPlayer(this.av, this.avAudio, minimizeState);
    FloatingVideoSurface.prepare(this.getUIContext(), this.floatingSource);
    this.floatingMorph = true;
    this.floatingReady = true;
    const opened = await FloatingPiP.getInstance().open(this.getUIContext(),
      this.av?.width || Math.round(this.ar * 1000), this.av?.height || 1000);
    if (!opened) {
      this.floatingMorph = false;
      FloatingVideoSurface.park();
      const sid = this.activeVideoSurfaceId();
      if (this.av && sid && this.av.surfaceId !== sid) this.av.surfaceId = sid;
      if (!this.play) this.floatingPausedFrame = FloatingVideoTransition.pausedFrame;
      floatingPlayer.videoPlayer = null;
      floatingPlayer.audioPlayer = null;
      floatingPlayer.playerState = null;
      floatingPlayer.hasActivePlayer = false;
      AppStorage.set('videoMinimized', false);
      AppStorage.set('minimizedVideoState', '');
      FloatingVideoTransition.finish();
      this.getUIContext().getPromptAction().showToast({ message: '系统小窗未能启动，请重试', duration: 2000 });
      return;
    }

    // Transfer ownership only after PiP has started; the decoder and audio keep running.
    if (this.av || this.avAudio) {
      // 先移除旧监听器，避免转移后回调引用已销毁的页面实例
      if (this.av) {
        this.av.off('stateChange');
        this.av.off('timeUpdate');
        this.av.off('error');
        this.av.off('videoSizeChange');
      }
      if (this.avAudio) {
        this.avAudio.off('stateChange');
        this.avAudio.off('seekDone');
        this.avAudio.off('error');
      }
      const ps = PlayerService.getInstance();

      // ⭐ DASH 转播站桥整体移交 PlayerService（桥实现 DashServerHandle=stop()），
      //    浮窗继续消费；页面置空避免 release 停服
      if (this.dashBridge_) {
        ps.setDashServer(this.dashBridge_);
        logInfo('[Minimize] 转播站桥已移交 PlayerService');
        this.dashBridge_ = null;
      }
      FloatingPiP.getInstance().takeoverPlayback();
      logInfo('[Minimize] 播放器与控制事件已移交系统小窗');
      // 置空页面内引用 → aboutToDisappear → release() 跳过
      this.av = null;
      this.avAudio = null;
    }

    // 结束实况窗（后台播放模式保留后台任务，保证切后台后继续播放）
    if (!this.bgp) {
      LiveViewHelper.end();
    } else {
      logInfo('[Minimize] 后台播放模式：保留实况窗和后台任务');
    }

    // ⭐ 保存观看历史再退出：关键节点绕过节流，保证退出一定落地
    this.saveWatchHistory(true);

    // The same system window remains visible over the app and desktop.
    router.back();
    FloatingVideoTransition.finish();
  }

  /**
   * 从最小化恢复 — 重新绑定 XComponent surface 并续播
   * 由 aboutToAppear 接管 PlayerService 后延时调用
   */
  /**
   * ⭐ PGC（番剧/影视）详情卡片 + 评论填充：按 epId 补 vd（标题/简介/制作方/统计/选集列表）
   *    和评论区 oid（= 当前分集的 aid）。
   *
   * 为什么必须有一条【独立于 cid】的路径（2026-09-15 修回归）：
   *   1. `loadD()` 对 PGC 直接 return（PGC 没有 bvid），所以 UGC 那条 "bvid→vd→评论" 的路走不通；
   *   2. PGC 的 vd/评论填充原先只写在 aboutToAppear 里 `if (!this.vi.cid || this.vi.cid <= 0)`
   *      的反查块【内部】—— 一旦来源页把 cid 一起带进来（观看历史那版补了 `cid: item.cid`），
   *      守卫为假 → 整块被跳过 → vd 从未赋值、pendingCommentAid 也从未设置
   *      → 详情卡片空、评论区空（实测回归：点番剧进去只有播放器）；
   *   3. `ensurePgcContext()` 只补 seasonId/aid，不碰 vd/评论，没有任何兜底能救回来。
   *   现在改为在 aboutToAppear 里无条件调用，靠下面"vd 已有则早退"来避免重复请求，
   *   所以 cid=0 的入口（首页番剧卡等）走完反查块后到这里会立即返回，行为不变。
   *
   * 季信息优先复用 ensurePgcContext() 留下的缓存（零网络），仅浮窗恢复等路径才会真正发请求。
   */
  private async fillPgcDetailFromSeason(): Promise<void> {
    if (this.epId_ <= 0) return;
    if (this.vd && this.vd.pages && this.vd.pages.length > 0) return;  // 已有详情，无需重拉
    let pgcInfo: PgcSeasonInfo | null = this.pgcSeasonInfoCache_;
    if (!pgcInfo) {
      pgcInfo = await getPgcSeasonInfoByEpId(this.epId_);
      if (pgcInfo) {
        this.pgcSeasonInfoCache_ = pgcInfo;
      }
    }
    if (!pgcInfo || pgcInfo.episodes.length <= 0) return;
    let matchedEp: PgcEpisode | null = null;
    for (const ep of pgcInfo.episodes) {
      if (ep.id === this.epId_) {
        matchedEp = ep;
        break;
      }
    }
    const targetEp: PgcEpisode = matchedEp ?? pgcInfo.episodes[0];
    if (targetEp.cid && targetEp.cid > 0 && (!this.vi.cid || this.vi.cid <= 0)) {
      this.setPlaybackCid(targetEp.cid);
    }
    this.seasonId_ = pgcInfo.seasonId;
    if (!this.vi.title && pgcInfo.title) this.vi.title = pgcInfo.title;
    if (!this.vi.cover && pgcInfo.cover) this.vi.cover = pgcInfo.cover;
    const owner: VideoDetailOwner = {
      mid: pgcInfo.upInfo.mid || 0,
      name: pgcInfo.upInfo.uname || (pgcInfo.staff || pgcInfo.actors || ''),
      face: pgcInfo.upInfo.avatar || ''
    };
    const stat: VideoDetailStat = {
      aid: 0,
      view: pgcInfo.stat.view,
      danmaku: pgcInfo.stat.danmaku,
      reply: pgcInfo.stat.reply,
      favorite: pgcInfo.stat.favorite,
      coin: pgcInfo.stat.coin,
      share: 0,
      like: pgcInfo.stat.like,
      dislike: 0
    };
    const pages: VideoPageItem[] = [];
    const pgcEpIds: number[] = [];
    const pgcAids: number[] = [];
    for (let i = 0; i < pgcInfo.episodes.length; i++) {
      const ep = pgcInfo.episodes[i];
      pages.push({
        cid: ep.cid || 0,
        page: i + 1,
        part: (ep.long_title || ep.title || `第${i + 1}话`),
        duration: ep.duration ? Math.floor(ep.duration / 1000) : 0,
        cover: ep.cover || ''
      });
      pgcEpIds.push(ep.id || 0);
      pgcAids.push(ep.aid || 0);
    }
    this.pgcEpIds_ = pgcEpIds;
    this.pgcAids_ = pgcAids;
    const targetEpAid = targetEp.aid || (pgcAids.length > 0 ? pgcAids[0] : 0);
    // ⭐ 历史记录/点赞等依赖 aidFromParams_（浮窗恢复路由 aid=0 时由分集 aid 补齐）
    this.aidFromParams_ = targetEpAid;
    const pgcDetail: VideoDetail = {
      bvid: '',
      aid: targetEpAid,
      title: pgcInfo.title,
      desc: pgcInfo.desc || `${pgcInfo.actors || ''} ${pgcInfo.staff || ''}`.trim(),
      pic: pgcInfo.cover,
      pubdate: pgcInfo.pubdate,
      ctime: pgcInfo.pubdate,
      duration: 0,
      owner: owner,
      stat: stat,
      cid: this.vi.cid,
      pages: pages
    };
    this.vd = pgcDetail;
    this.likeCount = stat.like;
    this.coinCount = stat.coin;
    this.favoriteCount = stat.favorite;
    // ⭐ 选集/历史记录定位到当前分集（第 N 话），而非第一集
    const matchedEpIdx = this.pgcEpIds_.indexOf(this.epId_);
    this.currentPageIndex = matchedEpIdx >= 0 ? matchedEpIdx : 0;
    // ⭐ PGC 评论 oid = 分集 aid
    this.commentCursor = 0;
    this.commentDataSource.clear();
    this.pendingCommentAid = targetEpAid;
    if (this.commentsInitialized && targetEpAid > 0) {
      this.loadC(targetEpAid);
      this.pendingCommentAid = 0;
    }
    logInfo(`[VideoPlayer] PGC 详情/评论填充: epId=${this.epId_}, seasonId=${this.seasonId_}, cid=${this.vi.cid}, 评论aid=${targetEpAid}, 集数=${pages.length}`);
  }

  private async resumeFromMinimized(): Promise<void> {
    if (!this.av) {
      logWarn('[VideoPlayer] resumeFromMinimized: 无播放器');
      return;
    }
    // ⭐ 兜底：播放器已被系统释放，回退到标准初始化流程
    if (this.av.state === 'released') {
      logWarn('[VideoPlayer] resumeFromMinimized: 播放器已释放，回退到标准初始化');
      this.err = '恢复播放失败，请重新打开';
      this.ld = false;
      return;
    }
    this.sId = this.activeVideoSurfaceId();
    if (!this.sId) {
      logWarn('[VideoPlayer] resumeFromMinimized: surfaceId 未就绪');
      setTimeout(() => this.resumeFromMinimized(), 300);
      return;
    }
    try {
      logInfo(`[VideoPlayer] 恢复播放: surfaceId=${this.sId}, state=${this.av.state}`);
      // 不 seek — 原版行为：设 surface 后解码器从停滞位置自然加速追赶
      if (!this.floatingRestoring || !AppStorage.get<boolean>('floatingPiPActive')) {
        const surface = this.floatingRestoring ? this.sId : (this.nativeSurfaceId_ || this.sId);
        if (this.av.surfaceId !== surface) this.av.surfaceId = surface;
      }
      this.ct = Math.max(0, (this.av.currentTime || 0) / 1000);
      if (this.floatingRestoring) this.finishFloatingRestore();

      // 更新时长
      this.dur = (this.av.duration || 0) / 1000;

      // ⭐ 创建实况窗：不阻塞恢复播放（fire-and-forget，内部已全 try/catch）
      LiveViewHelper.setControlHandlers({
        // ⭐ 显式语义：play 仅在未播放时播放，pause 仅在播放中暂停
        // （旧版 play/pause 都调 togglePP，后台已暂停时点通知栏"暂停"反而触发播放）
        play: () => { this.mediaSessionPlay(); },
        pause: () => { if (this.play) { this.togglePP(); } },
        seek: (time: number) => { this.seek(time / 1000, false); },
      });
      LiveViewHelper.create(this.getUIContext().getHostContext() as common.Context, this.vi.title, this.vi.cover,
        this.vi.bvid, this.dur, this.vd?.owner?.name ?? '').catch(() => {});

      // 恢复播放
      if (this.av.state === 'paused' && this.play) {
        this.markAutoPlay('resume-from-minimized');
        await this.av.play();
        logInfo('[VideoPlayer] 播放器恢复播放');
        if (this.avAudio && this.avAudio.state === 'paused') {
          await this.avAudio.play();
        }
      } else if (this.av.state === 'playing') {
        logInfo('[VideoPlayer] 播放器已在播放状态');
      }

      this.play = this.av.state === 'playing';
      this.ld = false;

      // ⭐ 设置 contentVisible=true，让 UI 从加载态切换到播放器界面
      // 正常流程中由 stateChange → 'prepared' 回调设置，但 PS 恢复时不会经过该回调
      if (!this.contentVisible) {
        if (this.pageEnterAnim !== 'none') {
          this.pageEnterProgress = 0;
        }
        animateTo({ duration: 0 }, () => {
          this.contentVisible = true;
        });
        if (this.pageEnterAnim !== 'none') {
          animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
            // ⭐ 页面加载回弹动画（固定参数）
            duration: this.PE_ENTER_DURATION,
            curve: curves.springCurve(this.PE_ENTER_VELOCITY, 1, Math.round(this.FS_SPRING_STIFFNESS * 2.1), this.PE_ENTER_DAMPING),
            onFinish: () => {
              this.commentsInitialized = true;
              if (this.pendingCommentAid > 0) {
                this.loadC(this.pendingCommentAid);
                this.pendingCommentAid = 0;
              }
              this.scheduleFloatBtnFadeIn();
            }
          }, () => {
            this.pageEnterProgress = 1;
          });
        } else {
          this.commentsInitialized = true;
          if (this.pendingCommentAid > 0) {
            this.loadC(this.pendingCommentAid);
            this.pendingCommentAid = 0;
          }
          this.scheduleFloatBtnFadeIn();
        }
      }

      // 同步音量：播放器内部增益固定 1.0，音量完全由系统媒体音量控制（避免 v² 双重衰减）
      try { this.av.setVolume(1.0); this.audioGain_ = 1; if (this.mute) this.setSystemVolume(0); } catch (e) {}
      // ⭐ 启动声画同步检测：5 秒后开始监视视频是否落后音频
      this.startVideoSpeedSync();
    } catch (e) {
      logError(`[VideoPlayer] resumeFromMinimized 恢复失败: ${e}`);
      this.err = '恢复播放失败';
    }
  }

  /**
   * 启动声画同步检测
   * 恢复后等待解码器稳定，检测视频是否落后音频，若落后则 2x 加速追赶
   */
  private startVideoSpeedSync(delayMs: number = 8000): void {
    this.cancelVideoSpeedSync();
    this.videoSpeedFixTimer_ = setTimeout(() => {
      this.videoSpeedFixTimer_ = -1;
      this.checkAndSyncSpeed();
    }, delayMs);
  }

  /**
   * 首次快速同步：播放启动后立即做一次声画对齐（不等定时器）
   * 用于初始加载场景，尽早缩小差距
   */
  private async initialSyncCheck(): Promise<void> {
    if (!this.av || !this.avAudio || this.av.state === 'released') {
      return;
    }
    // 等 300ms 让播放器稳定
    await new Promise<void>(r => setTimeout(r, 300));
    let videoPos: number = 0;
    let audioPos: number = 0;
    try { videoPos = this.av.currentTime; } catch (_e) {}
    try { audioPos = this.avAudio.currentTime; } catch (_e) {}
    if (videoPos <= 0 || audioPos <= 0) {
      return;
    }
    const diffMs: number = audioPos - videoPos;
    if (diffMs > 3000) {
      const seekTarget: number = Math.max(1000, audioPos - 500);
      try {
        this.av.seek(seekTarget, media.SeekMode.SEEK_PREV_SYNC);
        this.lastSyncSeekTime_ = Date.now();
        logInfo(`[VideoPlayer] 初始同步: 差距 ${(diffMs / 1000).toFixed(1)}s，seek 到 ${seekTarget}ms`);
      } catch (_e) {}
    } else if (diffMs > 800) {
      try { this.av.setSpeed(this.rateToSpeedIdx(2.0)); } catch (_e) {}
      this.isSpeed2x_ = true;
      this.isSpeedFixIn2xPhase_ = true;
      logInfo(`[VideoPlayer] 初始同步: 差距 ${(diffMs / 1000).toFixed(1)}s，2x 加速`);
    }
  }

  /**
   * 取消声画同步检测
   */
  private cancelVideoSpeedSync(): void {
    if (this.videoSpeedFixTimer_ !== -1) {
      clearTimeout(this.videoSpeedFixTimer_);
      clearInterval(this.videoSpeedFixTimer_);
      this.videoSpeedFixTimer_ = -1;
    }
    if (this.isSpeed2x_) {
      try { this.av?.setSpeed(this.rateToSpeedIdx(1.0)); } catch (_e) {}
      this.isSpeed2x_ = false;
      this.isSpeedFixIn2xPhase_ = false;
    }
  }

  /**
   * 重新排程声画同步检查（每 5 秒一次）
   */
  private rescheduleSpeedCheck_(): void {
    if (this.videoSpeedFixTimer_ !== -1) {
      clearInterval(this.videoSpeedFixTimer_);
    }
    this.videoSpeedFixTimer_ = setInterval(() => this.checkAndSyncSpeed(), 5000);
  }

  /**
   * 检查声画同步状态：视频落后音频则加速追赶，追上后恢复
   */
  private checkAndSyncSpeed(): void {
    if (!this.av || !this.avAudio) {
      return;
    }
    if (this.av.state === 'released' || this.avAudio.state === 'released') {
      return;
    }
    if (!this.play) {
      this.cancelVideoSpeedSync();
      return;
    }

    // ⭐ 用户已手动设置非 1.0 倍速（如长按加速 2x），同步系统不应篡改
    if (Math.abs(this.rt - 1.0) > 0.01) {
      this.rescheduleSpeedCheck_();
      return;
    }

    let videoPos: number = 0;
    let audioPos: number = 0;
    try { videoPos = this.av.currentTime; } catch (_e) {}
    try { audioPos = this.avAudio.currentTime; } catch (_e) {}

    if (videoPos <= 0 || audioPos <= 0) {
      this.rescheduleSpeedCheck_();
      return;
    }

    const diffMs: number = audioPos - videoPos;

    // ✅ 已同步（差距 < 300ms，双向判断），恢复 1x
    // ⭐ 必须用绝对值：音频落后视频时 diffMs 为负，旧逻辑恒进此分支导致永不修复
    if (Math.abs(diffMs) < 300) {
      if (this.isSpeed2x_) {
        try { this.av.setSpeed(this.rateToSpeedIdx(1.0)); } catch (_e) {}
        this.isSpeed2x_ = false;
        this.isSpeedFixIn2xPhase_ = false;
        logInfo('[VideoPlayer] 声画同步: 已追平，恢复 1x');
      }
      this.rescheduleSpeedCheck_();
      return;
    }

    // 2x 追赶阶段：坚持 2x 直到追平，不中途切换为 seek
    if (this.isSpeedFixIn2xPhase_) {
      // 差距仍在 300ms 以上，继续 2x 追赶
      if (this.isSpeed2x_) {
        // 已经在 2x，什么都不做
      } else {
        // 意外恢复 1x（如用户操作），重新启用 2x
        try { this.av.setSpeed(this.rateToSpeedIdx(2.0)); } catch (_e) {}
        this.isSpeed2x_ = true;
      }
      this.rescheduleSpeedCheck_();
      return;
    }

    // ⭐ 音频落后视频（diffMs < 0）：seek 音频前进追视频（音频 seek 开销远小于视频）
    if (diffMs < -3000 && (Date.now() - this.lastSyncSeekTime_) > this.SYNC_SEEK_COOLDOWN_) {
      const audioSeekTarget: number = Math.max(1000, videoPos - 500);
      try {
        this.avAudio?.seek(audioSeekTarget, media.SeekMode.SEEK_PREV_SYNC);
        this.lastSyncSeekTime_ = Date.now();
        logInfo(`[VideoPlayer] 声画同步: 音频落后 ${(-diffMs / 1000).toFixed(1)}s，音频 seek 到 ${audioSeekTarget}ms`);
      } catch (_e) {}
      this.rescheduleSpeedCheck_();
      return;
    }

    // 非 2x 阶段，差距 > 3s 且 seek 冷却期已过 → seek（视频落后音频）
    if (diffMs > 3000 && (Date.now() - this.lastSyncSeekTime_) > this.SYNC_SEEK_COOLDOWN_) {
      const seekTarget: number = Math.max(1000, audioPos - 500);
      try {
        this.av.seek(seekTarget, media.SeekMode.SEEK_PREV_SYNC);
        this.lastSyncSeekTime_ = Date.now();
        logInfo(`[VideoPlayer] 声画同步: 差距 ${(diffMs / 1000).toFixed(1)}s，seek 到 ${seekTarget}ms`);
      } catch (_e) {}
      this.rescheduleSpeedCheck_();
      return;
    }

    // 差距 > 1s 且不在 2x 阶段 → 启动 2x 追赶（仅视频落后音频时，音频 2x 会变调）
    if (diffMs > 1000 && !this.isSpeed2x_) {
      try { this.av.setSpeed(this.rateToSpeedIdx(2.0)); } catch (_e) {}
      this.isSpeed2x_ = true;
      this.isSpeedFixIn2xPhase_ = true;
      logInfo(`[VideoPlayer] 声画同步: 视频落后 ${(diffMs / 1000).toFixed(1)}s，2x 加速追赶`);
    }

    this.rescheduleSpeedCheck_();
  }

  // ⭐ 切换关注状态
  private async toggleFollow(): Promise<void> {
    if (!this.vd || this.followPending.has(this.vd.owner.mid)) return;
    const mid = this.vd.owner.mid;
    const bvid = this.vi.bvid;
    const generation = this.referenceSwitchGeneration;
    const cookie = AppStorage.get<string>('biliCookie') || '';

    // 点击动画
    this.followScale = 0.8;
    setTimeout(() => { this.followScale = 1.2; }, 80);
    setTimeout(() => { this.followScale = 1; }, 160);

    const newIsFollowed = !this.isFollowed;

    // 调用API修改关注状态
    this.interactionRevision++;
    this.followPending.add(mid);
    let success = false;
    try { success = await modifyFollow(mid, newIsFollowed ? 1 : 2); }
    finally { this.followPending.delete(mid); }
    if (!this.referenceAlive || this.vi.bvid !== bvid || this.referenceSwitchGeneration !== generation ||
      cookie !== (AppStorage.get<string>('biliCookie') || '')) return;

    if (success) {
      this.isFollowed = newIsFollowed;
      clearFollowedMidsCache();  // 同步清空 SearchPage 的缓存
      try {
        if (!this.fs) { this.getUIContext().getPromptAction().showToast({ message: newIsFollowed ? '关注成功' : '取消关注', duration: 1500 }); }
      } catch (err) {
        logWarn(`showToast 异常: ${errMsg(err)}`);
      }
    } else {
      try {
        if (!this.fs) { this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 1500 }); }
      } catch (err) {
        logWarn(`showToast 异常: ${errMsg(err)}`);
      }
    }

    // 震动反馈
    try {
      VibrateUtils.vibrateTime(50);
    } catch (e) {
      logWarn(`震动失败: ${e}`);
    }

    logInfo(`[互动] ${newIsFollowed ? '关注' : '取消关注'}: UP主 ${this.vd.owner.name} (mid=${this.vd.owner.mid})`);
  }

  // ⭐ 切换屏幕旋转模式（二态循环：自由 ↔ 锁定当前方向）


  // ⭐ 应用旋转模式
  private async applyRotationMode(): Promise<void> {
    if (!this.mw) return;

    try {
      let orientation: window.Orientation;

      switch (this.rotationMode) {
        case 'system':
          orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
          break;
        case 'portrait':
          orientation = window.Orientation.PORTRAIT;
          break;
        case 'landscape':
          // 允许横屏之间旋转
          orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
          break;
        case 'auto':
        default:
          orientation = window.Orientation.AUTO_ROTATION;
          break;
      }

      await this.mw.setPreferredOrientation(orientation);
    } catch (e) {
      logError(`[旋转模式] 应用失败: ${e}`);
    }
  }

  // ⭐ 获取旋转模式图标


  // ⭐ 切换布局（横屏非全屏模式）


  // ⭐ 获取旋转模式文字


  /**
   * ⭐ 异步读取弹幕数据源设置（grpc / xml）
   * 从 aboutToAppear 里挪出来的：以前用 `await preferences.getPreferences(...)` 写在
   * aboutToAppear 最前面，把整个同步段（参数解析/尺寸/initW/loadD）都堵在后面，
   * 现在改为 fire-and-forget，这里只负责"晚一点把值补上"。
   */
  private async refreshDanmakuApiSource(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(ctx, 'my_app_settings');
      const savedApiSource = await pref.get('danmakuApiSource', 'grpc') as string;
      if (savedApiSource === 'grpc' || savedApiSource === 'xml') {
        if (this.danmakuConfig.apiSource !== savedApiSource) {
          // ⚠️ 只改字段，**绝不整体替换对象**：DanmakuController 在构造时拿走了 config 的引用，
          //    换成新对象后，控制器 / 渲染器 / 轨道管理 / 过滤器仍指向旧对象 —— 之后对配置字段的
          //    任何修改都会静默失效（连弹幕开关用的 config.enable 都传不进去）。
          this.danmakuConfig.apiSource = savedApiSource;
        }
        AppStorage.set('danmakuApiSource', savedApiSource);
        logInfo(`[VideoPlayer] 弹幕数据源异步校正: ${savedApiSource}`);
      }
    } catch (e) {
      logError(`[VideoPlayer] 读取danmakuApiSource异常: ${e}`);
    }
  }

  // ⭐ 加载弹幕开关状态（从Preferences读取）
  private async loadDanmakuEnabledState(): Promise<void> {
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      const savedValue = await pf.get('danmakuEnabled', true); // 默认开启
      this.syncDanmakuEnabled(savedValue as boolean);
      // 同步到AppStorage（用于其他组件访问）
      AppStorage.setOrCreate<boolean>('danmakuEnabled', this.isDanmakuEnabled);
      logInfo(`[弹幕] 从本地存储加载状态: ${this.isDanmakuEnabled ? '开启' : '关闭'}`);
    } catch (e) {
      logError('加载弹幕开关状态失败', e);
      // 失败时使用默认值
      this.syncDanmakuEnabled(true);
    }
  }

  /**
   * 同步弹幕开关：@State 管 UI 显隐，**config.enable 管渲染链停帧**，两者必须一起改。
   *
   * ⚠️ 背景：DanmakuView 现在改为【常驻挂载】，开关不再卸载/重建组件
   *    （原先每次开启都新建 controller → 重新下载弹幕分段，万条弹幕约 4 秒空窗 + 重复流量）。
   *    只靠 visibility 隐藏的话，canvas 仍会以 60fps 绘制一块看不见的画面 ——
   *    所以必须同步 config.enable，渲染器与自调度链都靠它提前返回 / 停帧。
   */
  private syncDanmakuEnabled(v: boolean): void {
    this.isDanmakuEnabled = v
    this.danmakuConfig.enable = v
  }

  // ⭐ 切换弹幕开关
  private async toggleDanmaku(): Promise<void> {
    this.cancelDelayHide();
    this.syncDanmakuEnabled(!this.isDanmakuEnabled);

    // ⭐ 持久化弹幕开关状态到本地存储
    AppStorage.setOrCreate<boolean>('danmakuEnabled', this.isDanmakuEnabled);
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      await pf.put('danmakuEnabled', this.isDanmakuEnabled);
      await pf.flush();
    } catch (e) { logError('保存弹幕开关失败', e); }

    // 触觉反馈
    this.triggerHaptic();

    // 提示
    try {
      this.getUIContext().getPromptAction().showToast({
        message: this.isDanmakuEnabled ? '弹幕已开启' : '弹幕已关闭',
        duration: 1500
      });
    } catch (err) {
      logWarn(`showToast 异常: ${errMsg(err)}`);
    }

    logInfo(`[弹幕] ${this.isDanmakuEnabled ? '开启' : '关闭'}`);
  }

  // ⭐ 弹幕模式标签
  private dmModeLabel(mode: number): string {
    return mode === 4 ? '底部' : mode === 5 ? '顶部' : '滚动';
  }

  // ⭐ B站弹幕 mode → 内部类型
  private dmModeToType(mode: number): DanmakuType {
    return mode === 4 ? DanmakuType.BOTTOM : mode === 5 ? DanmakuType.TOP : DanmakuType.ROLL;
  }

  /**
   * 发送弹幕（POST /x/v2/dm/post），成功后注入本地弹幕流立即上屏
   * @param msg 弹幕文本（CommentInputBar 已还原表情标记）
   * @returns true=发送成功（由 onSend 返回，父层关弹层）
   */
  private async doSendDanmaku(msg: string, mode: number, color: number, fontSize: number): Promise<boolean> {
    const text = msg.trim();
    if (!text) {
      return false;
    }
    try {
      const result = await sendDanmakuVideo(this.vi.cid, this.vi.bvid || (this.vd?.bvid ?? ''), text, Math.floor(this.ct * 1000), mode, color, fontSize);
      logInfo(`[sendDanmaku] ${result.ok ? '成功' : '失败'} code=${result.code}, dmid=${result.dmid}`);
      if (result.ok) {
        // 本地注入，立即上屏
        const progress = Math.floor(this.ct * 1000);
        const init: DanmakuItemInit = {
          id: result.dmid || Date.now(),
          content: text,
          time: progress,
          type: this.dmModeToType(mode),
          color: color,
          fontSize: fontSize,
          sendTime: Date.now(),
          pool: 0,
          weight: 10
        };
        this.selfDanmakuList = [...this.selfDanmakuList, new DanmakuItem(init)];
        this.showDanmakuSheet = false;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '弹幕发送成功', duration: 1500 });
        } catch (_) {}
        return true;
      }
      try {
        this.getUIContext().getPromptAction().showToast({ message: result.message || '弹幕发送失败', duration: 1800 });
      } catch (_) {}
      return false;
    } catch (err) {
      logError(`[sendDanmaku] 异常: ${err}`);
      try {
        this.getUIContext().getPromptAction().showToast({ message: '网络异常，请稍后再试', duration: 1800 });
      } catch (_) {}
      return false;
    }
  }

  private onDanmakuKeyboardHeight = (height: number): void => {
    const target = Math.max(0, this.getUIContext().px2vp(height));
    this.composerKeyboardAnimator?.cancel();
    this.composerKeyboardAnimator = null;
    if (!this.commentSheetVisible && !this.showDanmakuSheet) {
      this.danmakuKeyboardHeight = target;
      return;
    }
    if (this.commentSheetVisible && target > 0 && !this.commentComposerClosing && this.commentComposerProgress === 0 && !this.commentComposerAnimator) {
      clearTimeout(this.commentComposerStartTimer);
      this.commentComposerStartTimer = 0;
      this.animateCommentComposer(1);
    }
    const from = this.danmakuKeyboardHeight;
    const animation = Animator.create({ duration: 260, easing: 'cubic-bezier(0.2, 0, 0, 1)',
      delay: 0, direction: 'normal', iterations: 1, fill: 'forwards', begin: 0, end: 1 });
    this.composerKeyboardAnimator = animation;
    animation.onframe = (progress: number) => { this.danmakuKeyboardHeight = from + (target - from) * progress; };
    animation.onfinish = () => {
      this.danmakuKeyboardHeight = target;
      this.composerKeyboardAnimator = null;
    };
    animation.play();
  };

  private onDanmakuComposerChanged(): void {
    if (!this.showDanmakuSheet) {
      clearTimeout(this.danmakuFocusTimer);
      this.danmakuFocusTimer = 0;
    }
    if (this.commentSheetVisible || this.showDanmakuSheet) {
      if (this.landscapeComposerAvoidMode === null) {
        this.composerControlsWereVisible = this.cv;
      }
      this.cancelDelayHide();
      this.cv = false;
      this.ip = true;
      if (this.landscapeComposerAvoidMode === null) {
        this.landscapeComposerAvoidMode = this.getUIContext().getKeyboardAvoidMode();
        this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
      }
      this.mw?.off('keyboardHeightChange', this.onDanmakuKeyboardHeight);
      this.mw?.on('keyboardHeightChange', this.onDanmakuKeyboardHeight);
    } else {
      this.mw?.off('keyboardHeightChange', this.onDanmakuKeyboardHeight);
      this.composerKeyboardAnimator?.cancel();
      this.composerKeyboardAnimator = null;
      this.danmakuKeyboardHeight = 0;
      if (this.landscapeComposerAvoidMode !== null) {
        this.getUIContext().setKeyboardAvoidMode(this.landscapeComposerAvoidMode);
        this.landscapeComposerAvoidMode = null;
      }
      this.ip = false;
      if (this.referenceAlive && this.playerPageVisible) {
        this.getUIContext().getFocusController().clearFocus();
        this.cv = this.composerControlsWereVisible;
        if (this.cv) this.resetCT();
      }
    }
  }

  private landscapeDanmakuComposerHeight(): number {
    return Math.min((this.dmComposerSettings ? 282 : 52) + this.danmakuComposerBottomInset(),
      Math.max(52, this.ch - this.danmakuKeyboardHeight - this.referenceSafeTop()));
  }

  private danmakuComposerBottomInset(): number {
    return this.isLs ? 0 : Math.max(0, this.navIndicatorHeight - this.danmakuKeyboardHeight);
  }

  private focusDanmakuComposer(): void {
    clearTimeout(this.danmakuFocusTimer);
    // Let the sheet's window and the measured native input scope finish gaining focus first.
    this.danmakuFocusTimer = setTimeout(() => {
      this.danmakuFocusTimer = 0;
      if (this.showDanmakuSheet && this.referenceAlive) {
        this.getUIContext().getFocusController().requestFocus('danmaku_text_input');
      }
    }, 120);
  }

  @Builder
  ReferenceLandscapeDanmakuComposer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .onClick(() => { this.showDanmakuSheet = false; })
      Column() {
        // 玻璃底板仍走 NativeComposerSurface 的原生 Navigation 作用域（panel 配方）。
        // 只在「A」展开样式设置时挂载：收起态就只剩评论页同款的一枚胶囊，外面没有框。
        NativeComposerSurface({ allCorners: true, active: this.dmComposerSettings }) {
          Scroll() { this.dmSheetContent() }
            .width('100%').height(this.landscapeDanmakuComposerHeight())
            .scrollBar(BarState.Off).clip(this.dmComposerSettings).id('landscape-danmaku-scroll')
        }
      }.width(Math.max(120, (this.isLs && !this.fs ? this.referenceLandscapeViewportWidth() : this.cw) - 24))
        .height(this.landscapeDanmakuComposerHeight()).borderRadius(12)
        .backgroundColor(Color.Transparent)
        .clip(this.dmComposerSettings)
        .position({ x: (this.isLs && !this.fs ? this.referenceLandscapePlayerX() : 0) + 12, y: Math.max(this.referenceSafeTop(),
          this.ch - this.danmakuKeyboardHeight - this.landscapeDanmakuComposerHeight() - 8) })
        .id('landscape-danmaku-composer')
        .onAppear(() => { this.focusDanmakuComposer(); })
    }.width('100%').height('100%').zIndex(100)
  }

  @Builder
  dmSheetContent() {
    DanmakuInputBar({
      ctrl: this.dmSheetEmoteCtrl,
      // Native glass mounts the input after width measurement; focus explicitly once its host is visible.
      autoFocus: false,
      materialEnabled: false,
      bottomInset: this.danmakuComposerBottomInset(),
      onSettingsChange: (open: boolean) => { this.dmComposerSettings = open; },
      onSend: (content: string, mode: number, color: number, fontSize: number) => {
        return this.doSendDanmaku(content, mode, color, fontSize);
      }
    })
  }

  /**
   * ⭐ 半模态面板内容根底色：设备支持沉浸光感材质时必须全透明
   * （材质层在 backgroundColor 之下，不透明底会把玻璃整层盖住——MaterialUtil 硬要求①）。
   * 不支持材质时原样返回，走原来的不透明降级底色。
   */
  private sheetRootBg(base: ResourceColor): ResourceColor {
    return MaterialUtil.sheetMaterial() !== undefined ? Color.Transparent : base;
  }

  updateIsLandscapeVertical(): void { this.isLandscapeVertical = this.isLs && !this.fs && this.ar < 1; }

  /** 预先解码头像（48w，轻量），避免分支切换时触发 JPEG 解码 */
  private predecodeKeyImages(): void {
    if (this.vd?.owner?.face) {
      predecodeImage(imageUrlResize(this.vd.owner.face, 48));
    }
  }

  /** ⭐ 预解码 1080w 封面（重）：延后到首帧后（startRenderFrame 触发），避免与起播抢下载/解码线程 */
  private predecodeCover(): void {
    // 当前布局不绘制封面，首帧后也不再下载封面或更新其响应式状态。
    if (this.referenceLayout) return;
    // 1080w：背景封面 + 加载占位封面共用（全屏清晰显示，避免 320w 拉伸模糊）
    const coverUrlHd = imageUrlResize(this.vi.cover, 1080);
    if (coverUrlHd) {
      predecodeImage(coverUrlHd).then(() => { this.hdCoverReady = true; });
    }
  }

  /** 封面源：1080w 高清预解码完成后用缓存 PixelMap；未就绪时回退到列表页原始 URL（框架缓存内秒显，防黑屏） */
  private coverSrc(): string | image.PixelMap | undefined {
    if (this.hdCoverReady) {
      const pm = getCachedPixelMap(imageUrlResize(this.vi.cover, 1080));
      if (pm) return pm;
    }
    return this.vi.cover || undefined;
  }

  updateLSVSize(): void {
    if (!this.isLs) return;
    if (this.referenceLayout) {
      this.lsvw = this.referenceLandscapeMediaWidth();
      this.lsvh = this.referenceLandscapeMediaHeight();
      return;
    }
    const arV = Number.isFinite(this.ar) && this.ar > 0 ? this.ar : 9 / 16;
    if (this.ar < 1) {
      // 竖屏视频：高度占满，宽度按实际宽高比
      const videoH = this.ch - 2 * this.cardMargin;
      this.lsvh = videoH;
      this.lsvw = videoH * arV;
    } else {
      // 横屏视频：宽度占67%，高度按实际宽高比
      this.lsvw = this.cw * 0.67;
      this.lsvh = this.lsvw / arV;
    }
  }

  @State videoDisplayWidth: number = 0
  @State videoDisplayHeight: number = 0

  private readonly ql_: QI[] = [{ qn: 16, label: '360P' }, { qn: 32, label: '480P' },
    { qn: 64, label: '720P' }, { qn: 80, label: '1080P' },
    { qn: 112, label: '1080P+' }, { qn: 116, label: '1080P60' }, { qn: 120, label: '4K' }]
  // Options belong to a specific video part; never offer a previous video's qualities.
  @State aq: QI[] = []
  @State private aqBvid: string = ''
  @State private aqCid: number = 0

  private applyAcceptQuality(result: PlayUrlResult): void {
    const qualities = result.acceptQuality || [];
    const descriptions = result.acceptDescription || [];
    const list: QI[] = [];
    for (let i = 0; i < qualities.length; i++) {
      const qn = qualities[i];
      if (qn <= 0 || list.some((item: QI) => item.qn === qn)) continue;
      const known = this.ql_.find((item: QI) => item.qn === qn);
      list.push({ qn: qn, label: descriptions[i] || known?.label || `${qn}` });
    }
    // Without an advertised list, only the returned stream is known to be supported.
    if (list.length === 0 && result.url && result.actualQn && result.actualQn > 0) {
      const known = this.ql_.find((item: QI) => item.qn === result.actualQn);
      list.push({ qn: result.actualQn, label: known?.label || `${result.actualQn}` });
    }
    this.aqBvid = this.vi.bvid;
    this.aqCid = this.vi.cid;
    this.aq = list;
  }

  private getQlList(): QI[] {
    // AV 快速起播后详情会补齐 BV 别名；CID 才是这份分 P 画质目录的归属。
    return this.aqCid > 0 && this.aqCid === this.vi.cid ? this.aq : [];
  }

  private getQlLabel(qn: number): string {
    const item = this.getQlList().find((quality: QI) => quality.qn === qn) || this.ql_.find((quality: QI) => quality.qn === qn);
    return item ? item.label : `${qn}`;
  }
  private readonly sl_: SO[] = [{ label: '自动', mode: 'auto' }, { label: '拉伸', mode: 'stretch' },
    { label: '填充', mode: 'fill' }, { label: '等高', mode: 'fitHeight' }, { label: '等宽', mode: 'fitWidth' }]
  // ⭐ 画风选项
  private readonly cl_: CO[] = [{ label: '原图', mode: 'original' }, { label: '鲜艳', mode: 'vivid' },
    { label: '徕卡', mode: 'leica' }, { label: '胶片', mode: 'film' }]
  // ⭐ 更多菜单项（后续功能扩展：缓存、定时等）
  private readonly mo_: MO[] = [
    { label: '缓存', icon: $r('app.media.ic_public_folder'), action: () => { this.startCacheCurrentVideo(); } },
    // 弹幕设置：横竖屏共用 ReferenceDanmakuSettings。
    { label: '弹幕设置', icon: $r('app.media.danmfas'), action: () => { this.openDanmakuSettingSheet(); } },
    { label: '投屏', icon: $r('app.media.ic_public_wireless_projection'), action: () => {} },
  ]
  // ⭐ 画风对应的颜色滤镜参数
  private get saturateVal_(): number {
    if (this.cs === 'vivid') return 1.5;
    if (this.cs === 'leica') return 0.85;
    if (this.cs === 'film') return 0.8;
    return 1.0;
  }
  private get contrastVal_(): number {
    if (this.cs === 'vivid') return 1.15;
    if (this.cs === 'leica') return 1.3;
    if (this.cs === 'film') return 0.9;
    return 1.0;
  }
  private get brightnessVal_(): number {
    if (this.cs === 'leica') return 0.88;
    if (this.cs === 'film') return 0.95;
    return 1.0;
  }
  private get sepiaVal_(): number {
    if (this.cs === 'film') return 0.55;
    return 0;
  }
  private get colorBlendVal_(): string {
    if (this.cs === 'leica') return 'rgba(60,30,10,0.12)';
    return 'rgba(0,0,0,0)';
  }
  private readonly rr_: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
  private ct_: number = -1; private gt_: number = -1; private lt_: number = -1
  private dt_: number = -1; private pb_: number = 0
  private dtwcv_: boolean = false // 双击用wcv_快照，防止第二击onTD覆盖
  private hc_: number = -1 // 延迟隐藏控制栏的timer（200ms），按钮回调中取消
  private sx_: number = 0; private sy_: number = 0; private st_: number = 0
  private playerTouchId_: number = -1
  private seekDragStartX_: number = 0
  private screenH_: number = 0  // 屏幕高度(vp)，用于手势灵敏度计算
  private density_: number = 3.0  // 屏幕密度(vp→px转换)
  /** ⭐ 设备媒体音量最大档位（readSystemVolume 时刷新） */
  private maxVol_: number = 15
  /** ⭐ AudioVolumeManager 实例（供 streamVolumeChange 监听/注销） */
  private volMgr_: audio.AudioVolumeManager | null = null
  /** ⭐ 是否已注册系统音量变化监听 */
  private volListening_: boolean = false
  private sk_: boolean = false; private sg_: boolean = false; private gm_: string = ''
  // ⭐ seek 补提交目标（last-wins）：seek 在途时到来的新目标记在这里，由 finally 补一次
  //   原先是直接 return 丢弃，表现为"点进度条点两次才生效 / 松手后跳回去"
  private pendingSeekTarget_: number = -1
  // 当前这轮 seek 是否交互路径（决定过期 seekDone 的容差：CLOSEST 很准，PREV_SYNC 会退一个 GOP）
  private seekFastMode_: boolean = false
  // ⭐ 音频淡变令牌 + 当前增益：连续 seek 时后一次淡变必须作废前一次的步进，
  //   否则两条 ramp 会互相把音量推回中间值（听感是"滋"一下的爆音）。
  private audioFadeToken_: number = 0
  private audioGain_: number = 1
  // ⭐ 观看进度上报节流：实测一次 seek 就上报一次（串行 HTTP + 主线程 JSON），
  //   连续快进快退会连发一串请求，是后半段发涩的来源之一。
  private lastHistoryPushAt_: number = 0
  // ⭐ 进度条拖动中标记：拖动期间冻结 ct、抑制控制栏自动隐藏，并让播放器手势与
  //   PanGesture（右滑进全屏）让位。stopPropagation 只能拦 onTouch，拦不住父节点的手势对象
  private sliderDragging_: boolean = false
  // ⭐ 进度条**触摸窗口**标记：从交互上报开始，一直保持到手指真正抬起（onVT 收到 Up/Cancel）。
  //   不能只用 sliderDragging_：提交发生在 onChange 的 End/Click，而实测它**早于** onTouch Up
  //     （序列：Begin → Down → Click → End → Up）
  //   若在提交时就撤守卫，Up 会掉进播放器的 onTU：
  //     1) onTU 第一行 `if (sk_ && av) { sk_ = false; seek(ct,...) }` 会把**在途 seek 的 sk_ 提前解冻**
  //        → timeUpdate 立刻把 ct 写回旧播放位置 → 表现为「时间显示没跳到目标」；
  //     2) onTD 因守卫没跑过，ml_ 是上一次手势的陈旧值 → Up 走"单击视频区"分支
  //        → 200ms 后隐藏控制栏、250ms 后再尝试显示 → 表现为「控制栏收缩一下」。
  private seekBarTouch_: boolean = false
  // 上述标记的看门狗：万一 Up/Cancel 没送达（系统抢事件），避免守卫永久生效把播放器手势锁死
  private seekBarTouchTimer_: number = -1
  // ⭐ 进度调节缩略图（拖动/滑动目标位置的画面）：
  //   与提示胶囊（gh/ght/ghp）同生共死 —— sGH() 时更新，提示 800ms 超时隐藏时一并隐藏。
  //   每次变化整体替换实例（@Link 对类对象改字段不触发刷新）
  @State thumb_: SeekThumb = new SeekThumb()
  // 缩略图请求令牌：拖动期间会连发多次异步查询，只有最后一次的结果才允许写回（否则会闪回旧帧）
  private shotToken_: number = 0
  // ⭐ 进度条提示胶囊/缩略图的刷新节流：Slider 的 Moving 上报约 90 次/秒，
  //   每次都写一遍 @State（提示胶囊 + 时间文本 + 缩略图切换）会把主线程塞满，
  //   拖动后半段"发涩"、松手后延迟一拍就是这个原因。20fps 已足够看清。
  private lastSeekHintAt_: number = 0
  // ⭐ 进度条按下瞬间的时间，用于判断"点了一下但没改位置"（不提交无意义的 seek）
  private seekDragAnchor_: number = -1
  // ⭐ 本次进度条手势已提交的目标：点滑轨会依次触发 Begin/Click/End，
  //   用它做"同一目标只提交一次"去重（-1 表示本次手势尚未提交）
  private lastSeekBarCommitV_: number = -1
  // ⭐ 手势 seek 的档位震动记录（与音量/亮度每 10% 震一次的手感对齐）
  private lastSeekHapticPct_: number = -1
  private os_: number = 1.0; private lp_: boolean = false
  private sz_: number = 0; private sv_: number = 0; private sb_: number = 0
  private ml_: boolean = false; private la_: boolean = false; private wcv_: boolean = false
  // ⭐ 全屏时顶部区域触摸标记：触摸起点在状态栏区域时跳过播放器手势，避免与下拉状态栏冲突
  private topAreaTouch_: boolean = false
  private swipeTimer_: number = -1 // 竖屏左右滑切换的延迟清理 timer
  private dtp_: boolean = false
  private initPInProgress_: boolean = false; // 防止重复初始化播放器
  private playbackStartupAt: number = Date.now();
  private playbackProfile: PlaybackSpan | null = null;
  private rc_: number = 0; private readonly mr_: number = 3; private ry_: boolean = false
  private rt_: number = -1; private so_: string = '跟随系统'
  private sh_: boolean = false; private sr_: boolean = false; private sti_: number = -1
  private fsAnimTimer_: number = -1
  private fsExitRetry_: number = 0  // 退出全屏时等待 isLs 稳定的重试计数
  private lastHapticPct_: number = -1 // 上次震动时的百分比 (0-100)，拖动时按档位震动
  // ⭐ 初始播放进度（从历史记录恢复）
  private initialProgress_: number = 0
  // ⭐ 长按文本选取弹窗（简介等）：openCustomDialog 返回的对话框 id，用于关闭
  private textSelectDialogId_: number = -1
  // ⭐ seek完成Promise的resolve函数
  private videoSeekResolve_: (() => void) | null = null
  private audioSeekResolve_: (() => void) | null = null
  // ⭐ 视频第一帧渲染完成的resolve函数
  private startRenderFrameResolve_: (() => void) | null = null
  // ⭐ 音视频同步定时器
  private syncTimer_: number = 0
  // ⭐ 上次视频位置（用于检测卡顿）
  private lastVideoPos_: number = 0
  // ⭐ 上次同步时间（避免频繁同步）
  private lastSyncTime_: number = 0
  // ⭐ 音频是否被静音（用于同步）
  private audioMutedForSync_: boolean = false

  // ⭐ 启动音视频同步定时器
  private startSyncTimer() {
    if (this.syncTimer_) return;
    this.syncTimer_ = setInterval(() => {
      this.syncAudioVideo();
    }, 300); // 每300ms同步一次（更频繁）
  }

  // ⭐ 停止同步定时器
  private stopSyncTimer() {
    if (this.syncTimer_) {
      clearInterval(this.syncTimer_);
      this.syncTimer_ = 0;
    }
    // 恢复音频（如果被静音）
    if (this.audioMutedForSync_ && this.avAudio) {
      this.avAudio.setVolume(1.0); this.audioGain_ = 1;
      this.audioMutedForSync_ = false;
    }
  }

  // ⭐ 音视频同步逻辑（更激进的策略）
  private async syncAudioVideo() {
    // ⭐ seek/sk_ 期间不参与同步：那时 currentTime 还没稳定，读到的旧值会让这里把音频
    //   seek 回上一个位置（既是可听见的跳变，也会和 seek 的音频对齐互相打架）。
    if (!this.av || !this.avAudio || !this.play || this.sg_ || this.sk_) return;
    // 抽屉开合只有 200ms 级，这两次 currentTime 读取 + 可能的音频 seek 会让动画掉帧，
    // 推迟到动画结束后的下一拍即可。
    if (this.referencePortraitSettingsAnimating) return;
    // ⭐ 播完收尾与 300ms 定时器有一次交叉：completed 之后读到的 currentTime 是旧值，
    //   继续同步会把音频 seek 到片尾/旧位置，表现就是“播完了声音又动起来”。
    if (this.av.state === 'completed' || this.avAudio.state === 'completed') return;

    // 限制同步频率：至少间隔500ms（更频繁）
    const now = Date.now();
    if (now - this.lastSyncTime_ < 500) return;

    try {
      // 获取视频和音频的当前播放位置
      const videoPos = await this.av.currentTime;
      const audioPos = await this.avAudio.currentTime;

      // 计算差异（毫秒）
      const diff = audioPos - videoPos;
      const absDiff = Math.abs(diff);

      // 死区：差异小于200ms，不做调整
      if (absDiff < 200) {
        this.lastSyncTime_ = now;
        return;
      }

      logWarn(`[Sync] 音视频偏差 ${absDiff.toFixed(0)}ms，重新同步`);

      // ===== 直接 seek 音频到视频位置（不暂停）=====
      // 这样可以减少卡顿，同时保持同步
      await this.avAudio.seek(videoPos, media.SeekMode.SEEK_CLOSEST);

      this.lastSyncTime_ = now;
    } catch (e) {
      // 同步失败，忽略
    }
  }

  private continuationRestore_: boolean = false;
  private continuationPaused_: boolean = false;
  private continuationRate_: number = 1;

  private registerContinuation(): void {
    AppContinuation.register(this, 'pages/VideoPlayerPage', (): ContinuationPage | null => {
      if (this.offlineVideoPath_ || (!this.vi.bvid && this.epId_ <= 0 && this.aidFromParams_ <= 0)) return null;
      const params: Record<string, string | number | boolean> = {
        'bvid': this.vi.bvid, 'aid': this.aidFromParams_, 'cid': this.vi.cid || 0,
        'epId': this.epId_, 'seasonId': this.seasonId_, 'title': this.vi.title,
        'initialProgress': this.av ? Math.max(0, this.av.currentTime / 1000) : Math.max(this.ct, this.initialProgress_),
        'continuationPaused': this.userPaused_ || !this.play, 'continuationRate': this.rt
      };
      const destination: ContinuationPage = { page: 'pages/VideoPlayerPage', params: params };
      return destination;
    });
  }

  async aboutToAppear() {
    // ⭐ 存活播放页计数（与 LivePlayerPage 共用）：退出时若还有别的播放页活着
    //    （播放页里点相关推荐 push 出下层实例），内容色必须回到白字而不是主题口径，
    //    否则下层播放页在浅色模式下被恢复成黑字（onPageShow 的白字会被这次恢复覆盖）。
    AppStorage.setOrCreate('immersivePlayerAliveCount',
      Math.max(0, (AppStorage.get<number>('immersivePlayerAliveCount') ?? 0)) + 1);
    this.startHdrUiBrightness();
    this.playbackProfile = PlaybackStartup.page();
    this.playbackStartupAt = Date.now();
    PlaybackStartup.trace('page', this.playbackStartupAt);
    // 必须在任何异步分支之前落地：initP 会在 await 之后立刻读 this.preferredQn 取流，
    // 而 initFromAid 的画质赋值在 getVideoDetail 之后；两者竞争时页面会用默认 116，
    // 与列表预取的缓存键（bvid_cid_qn_kernel）对不上，预取结果全部作废。
    this.applyDefaultQuality();
    this.registerContinuation();
    this.onLandscapePlaybackSideChanged();
    logInfo('[VPP] aboutToAppear 开始');
    if (FloatingVideoTransition.direction === 'restore' && FloatingVideoTransition.source && FloatingVideoTransition.mini) {
      this.floatingPausedFrame = FloatingVideoTransition.pausedFrame;
      const hosted = PlayerService.getInstance();
      this.play = hosted.videoPlayer ? hosted.videoPlayer.state === 'playing' : hosted.playbackState === 'playing';
      this.userPaused_ = !this.play;
      this.floatingRestoring = true;
      this.floatingMorph = true;
      this.floatingCompact = FloatingVideoTransition.restoreExpanded ? 0 : 1;
      this.floatingReady = false;
      this.floatingSource = FloatingVideoTransition.source;
      this.floatingTarget = FloatingVideoTransition.mini;
    }
    // ⭐ 同步预判 PGC（番剧/影视）：在任何 await 之前设 isPgc_，避免首次 build 用 16:9 渲染后跳到 3:4
    try {
      const _p0 = router.getParams() as Record<string, Object>;
      if (_p0) {
        this.referenceLandscapeRestoreRatio(_p0['landscapePlayerRatio']);
        const _ep = typeof _p0['epId'] === 'number' ? _p0['epId'] : parseInt(_p0['epId'] as string, 10) || 0;
        const _mid = typeof _p0['mediaId'] === 'number' ? _p0['mediaId'] : parseInt(_p0['mediaId'] as string, 10) || 0;
        if (_ep > 0 || _mid > 0) this.isPgc_ = true;
      }
    } catch (_e) { }
    // ⭐ 首帧前同步重建分段按钮 options（非 @State 字段，主题色需在首次 build 前应用）
    this.rebuildSegmentOptions();
    // ⭐ 注册系统音量变化监听（音量键调节时同步 app 内滑块）
    // ⭐ 启动封面跑马灯流光动画（setInterval 驱动 angle 持续变化；首帧后由 onContentVisibleChange 停止）
    if (!this.referenceLayout) {
      this.coverGlowTimer = setInterval(() => { this.coverGlowAngle = (this.coverGlowAngle + 3) % 360; }, 16);
    }
    this.so_ = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
    this.sh_ = AppStorage.get<boolean>('hideStatusBar') ?? false;
    // @StorageLink('bgp') 自动同步持久化值，无需手动读取

    // ⭐ 同步读取弹幕开关状态（从 AppStorage，避免异步加载前的默认 true 闪一下）
    const savedDmk = AppStorage.get<boolean>('danmakuEnabled');
    if (savedDmk !== undefined) {
      this.syncDanmakuEnabled(savedDmk);
    }

    // ⭐ 弹幕数据源设置
    // ⚠️ 这里【绝不能 await Preferences】：aboutToAppear 的 await 会让它后面的整段
    //   （路由参数解析 / 屏幕尺寸计算 / initW / loadD）推迟到"首帧渲染之后"才执行，
    //   首帧因此拿不到 cid、拿不到标题封面，等参数到位后再整体重排一次 —— 这是所有
    //   入口共有的固定起播延迟（实测该 await 占 ~20-40ms，且把网络发起也一起推迟）。
    //   弹幕数据源要到弹幕真正加载时才用得上，所以：先同步取 AppStorage 里的缓存值
   //   （HomePage 启动时已回填），再异步用 Preferences 校正。
   //   ⚠️ 校正时只能改 danmakuConfig 的**字段**，不能 `this.danmakuConfig = new DanmakuConfig()`：
   //      DanmakuController 持有构造时传入的那个对象引用，整体替换会让它从此读不到新配置。
    const cachedDmkSource = AppStorage.get<string>('danmakuApiSource');
    if (cachedDmkSource === 'grpc' || cachedDmkSource === 'xml') {
      // ⚠️ 同上：只改字段，不换对象（DanmakuController 持有的是构造时传进去的那个引用）
      this.danmakuConfig.apiSource = cachedDmkSource;
    }
    this.refreshDanmakuApiSource();
    this.loadDanmakuDisplaySettings();
    logInfo('[VPP] 同步段继续（弹幕数据源改异步，不阻塞参数解析）');

    // ⭐ 同步获取显示方向与尺寸，确保首次 build() 使用正确的 isLs/cw/ch/lsvw（不等 async initW）
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      this.cw = this.getUIContext().px2vp(defaultDisplay.width);
      this.ch = this.getUIContext().px2vp(defaultDisplay.height);
      this.sw = this.cw;
      this.screenH_ = this.ch;
      this.isLs = defaultDisplay.width > defaultDisplay.height;
      this.maxFloatBtnBottom = this.isLs ? 392 : 592;
      this.updateIsLandscapeVertical();
      this.updateLSVSize();       // ← 必须同步调用，否则 lsvw/lsvh=0 → xcW=0 → 视频容器宽度为0
      this.updateVideoSize();     // ← 同步计算 videoDisplayWidth/Height
      this.initOverlayRectSync(); // ⭐ 首帧前估算常驻播放器层矩形（首帧后由占位槽精确接管）
    } catch (_e) { }

    // ⭐ 初始化旋转模式状态
    const lockMode = this.so_;
    this.rotationFreeMode = lockMode === '自动旋转' ? 'auto' : 'system';
    if (lockMode === '锁定竖屏') {
      this.rotationMode = 'portrait';
    } else if (lockMode === '锁定横屏') {
      this.rotationMode = 'landscape';
    } else {
      this.rotationMode = this.rotationFreeMode;
    }

    const p = router.getParams() as Record<string, Object>;
    if (p?.['openComments'] === true) {
      this.at = 1;
      this.tabSelIdx = [1];
      this.referenceTabProgress = 1;
    }
    this.continuationRestore_ = typeof p?.['continuationPaused'] === 'boolean';
    this.continuationPaused_ = p?.['continuationPaused'] === true;
    this.continuationRate_ = typeof p?.['continuationRate'] === 'number' ? p['continuationRate'] as number : 1;
    if (this.continuationRestore_) {
      this.play = !this.continuationPaused_;
      this.userPaused_ = this.continuationPaused_;
    }
    this.referenceFeed = p?.['feedMode'] === true || AppStorage.get<boolean>('forceFeedMode') === true;
    this.referenceFeedProgress = this.referenceFeed ? 1 : 0;
    // 直接显示播放器，取流和首帧准备期间不叠加封面。
    if (this.referenceLayout) {
      this.contentVisible = true;
      // 常驻详情不经过旧的 prepared 入场动画，评论初始化不能等待该动画。
      this.commentsInitialized = true;
      this.pageEnterProgress = 1;
    }
    let aidFromParams = 0;
    if (p) {
      this.vi.bvid = (p['bvid'] as string) || '';
      this.setPlaybackCid(typeof p['cid'] === 'number' ? p['cid'] : parseInt(p['cid'] as string, 10));
      this.vi.title = (p['title'] as string) || '';
      this.vi.cover = (p['coverUrl'] as string) || '';
      const videoWidth = p['videoWidth'] as number;
      const videoHeight = p['videoHeight'] as number;
      if (Number.isFinite(videoWidth) && Number.isFinite(videoHeight) && videoWidth > 0 && videoHeight > 0) {
        // 路由尺寸在 RecommendItem / 详情解析时已按 rotate 交换过，属于显示尺寸：
        // 记成 meta 来源，后续解码尺寸（编码尺寸）不能把它盖成横版。
        if (this.setAspectFromMeta(videoWidth / videoHeight, this.vi.cid)) {
          this.updateIsLandscapeVertical();
          this.updateLSVSize();
          this.updateVideoSize();
        }
      }
      this.vi.ownerName = (p['ownerName'] as string) || '';
      this.vi.ownerFace = (p['ownerFace'] as string) || '';
      this.vi.duration = typeof p['duration'] === 'number' ? p['duration'] : (parseInt(p['duration'] as string, 10) || 0);
      this.vi.pubdate = typeof p['pubdate'] === 'number' ? p['pubdate'] : (parseInt(p['pubdate'] as string, 10) || 0);
      this.vi.view = typeof p['view'] === 'number' ? p['view'] : (parseInt(p['view'] as string, 10) || 0);
      this.vi.subTitle = (p['subTitle'] as string) || '';
      this.vi.score = (p['score'] as string) || '';
      this.vi.indexShow = (p['indexShow'] as string) || '';
      this.vi.badge = (p['badge'] as string) || '';
      // ⭐ 离线播放：本地缓存文件路径（非空时跳过网络取流）
      this.offlineVideoPath_ = (p['offlineVideoPath'] as string) || '';
      this.offlineAudioPath_ = (p['offlineAudioPath'] as string) || '';
      aidFromParams = typeof p['aid'] === 'number' ? p['aid'] : parseInt(p['aid'] as string, 10) || 0;
      this.commentRootId_ = typeof p['commentRootId'] === 'number' ? p['commentRootId'] : parseInt(p['commentRootId'] as string, 10) || 0;
      this.commentSecondaryId_ = typeof p['commentSecondaryId'] === 'number' ? p['commentSecondaryId'] : parseInt(p['commentSecondaryId'] as string, 10) || 0;
      // ⭐ PGC（番剧/影视）：支持 mediaId（季id，搜索跳转）或 epId（分集id）
      const mediaIdParam = typeof p['mediaId'] === 'number' ? p['mediaId'] : parseInt(p['mediaId'] as string, 10) || 0;
      const epIdParam = typeof p['epId'] === 'number' ? p['epId'] : parseInt(p['epId'] as string, 10) || 0;
      // ⭐ seasonId 可随 epId 一起传：省掉一次季接口反查，也避免 PGC 心跳缺 sid（会被 B 站静默丢弃）
      const seasonIdParam = typeof p['seasonId'] === 'number' ? p['seasonId'] : parseInt(p['seasonId'] as string, 10) || 0;
      if (epIdParam > 0) {
        this.epId_ = epIdParam;
        this.isPgc_ = true;
        if (seasonIdParam > 0) {
          this.seasonId_ = seasonIdParam;
        }
        // 只传 epId 未传 cid 时，需要反查 cid。
        // ⭐ 两个反查接口【并行】发起：getPgcEpisodeInfo 对本 App 的剧集 epId 实测常返回
        //   `[getPgcEpisodeInfo] data 为空`（例 epId=1231578 白等 ~190ms），串行会让每次进入
        //   播放页都多等这一整段；季接口 getPgcSeasonInfoByEpId 才是有数据的那个，且其返回
        //   还要用来填 vd/选集列表，所以以季接口为主、分集接口仅作 cid 兜底。
        if (!this.vi.cid || this.vi.cid <= 0) {
          logInfo(`[VPP] step1+step2 并行反查: epId=${epIdParam}`);
          const epInfoP: Promise<PgcEpisode | null> = getPgcEpisodeInfo(epIdParam);
          const pgcInfoP: Promise<PgcSeasonInfo | null> = getPgcSeasonInfoByEpId(epIdParam);
          const epInfo: PgcEpisode | null = await epInfoP;
          logInfo(`[VPP] step1: getPgcEpisodeInfo 完成`);
          if (epInfo && epInfo.cid && epInfo.cid > 0) {
            this.setPlaybackCid(epInfo.cid);
            logInfo(`[VideoPlayer] PGC epId=${epIdParam} 分集接口取到 cid=${this.vi.cid}`);
          }
          // ⭐ 无论分集接口是否给到 cid，都继续用季接口结果补详情/选集：
          //   原实现只在"分集接口失败"时才填 vd，分集接口成功的场景详情卡与选集按钮是空的。
          //   这个 await 命中的是上面已并行发起的请求，通常已返回，几乎不额外耗时。
          const pgcInfo: PgcSeasonInfo | null = await pgcInfoP;
          logInfo(`[VPP] step2: getPgcSeasonInfoByEpId 完成`);
          if (pgcInfo && pgcInfo.episodes.length > 0) {
            // 优先找匹配的 epId 分集，找不到用第一集
            let matchedEp: PgcEpisode | null = null;
            for (const ep of pgcInfo.episodes) {
              if (ep.id === epIdParam) {
                matchedEp = ep;
                break;
              }
            }
            const targetEp: PgcEpisode = matchedEp ?? pgcInfo.episodes[0];
            if (targetEp.cid && targetEp.cid > 0) {
              this.setPlaybackCid(targetEp.cid);
            }
            this.seasonId_ = pgcInfo.seasonId;
            if (!this.vi.title && pgcInfo.title) {
              this.vi.title = pgcInfo.title;
            }
            if (!this.vi.cover && pgcInfo.cover) {
              this.vi.cover = pgcInfo.cover;
            }
            // ⭐ 填充详情卡片数据（vd）：标题/简介/制作方/统计/分集列表（对齐 mediaId 分支）
            const owner: VideoDetailOwner = {
              mid: pgcInfo.upInfo.mid || 0,
              name: pgcInfo.upInfo.uname || (pgcInfo.staff || pgcInfo.actors || ''),
              face: pgcInfo.upInfo.avatar || ''
            };
            const stat: VideoDetailStat = {
              aid: 0,
              view: pgcInfo.stat.view,
              danmaku: pgcInfo.stat.danmaku,
              reply: pgcInfo.stat.reply,
              favorite: pgcInfo.stat.favorite,
              coin: pgcInfo.stat.coin,
              share: 0,
              like: pgcInfo.stat.like,
              dislike: 0
            };
            const pages: VideoPageItem[] = [];
            const pgcEpIds: number[] = [];
            const pgcAids: number[] = [];
            for (let i = 0; i < pgcInfo.episodes.length; i++) {
              const ep = pgcInfo.episodes[i];
              pages.push({
                cid: ep.cid || 0,
                page: i + 1,
                part: (ep.long_title || ep.title || `第${i + 1}话`),
                // ⭐ PGC season 接口 duration 为毫秒（UGC 为秒），转秒后再供 formatDuration 显示
                duration: ep.duration ? Math.floor(ep.duration / 1000) : 0,
                cover: ep.cover || ''
              });
              pgcEpIds.push(ep.id || 0);
              pgcAids.push(ep.aid || 0);
            }
            this.pgcEpIds_ = pgcEpIds;
            this.pgcAids_ = pgcAids;
            // ⭐ 番剧评论 oid 用当前分集的 aid（不能用 ep_id，否则查到的评论是错的）
            const targetEpAid = targetEp.aid || (pgcAids.length > 0 ? pgcAids[0] : 0);
            // ⭐ 历史记录/点赞等依赖 aidFromParams_（路由 aid=0 时由分集 aid 补齐）
            this.aidFromParams_ = targetEpAid;
            const pgcDetail: VideoDetail = {
              bvid: '',
              aid: targetEpAid,
              title: pgcInfo.title,
              desc: pgcInfo.desc || `${pgcInfo.actors || ''} ${pgcInfo.staff || ''}`.trim(),
              pic: pgcInfo.cover,
              pubdate: pgcInfo.pubdate,
              ctime: pgcInfo.pubdate,
              duration: 0,
              owner: owner,
              stat: stat,
              cid: this.vi.cid,
              pages: pages
            };
            this.vd = pgcDetail;
            // 互动统计初始化（点赞/投币/收藏数）
            this.likeCount = stat.like;
            this.coinCount = stat.coin;
            this.favoriteCount = stat.favorite;
            // ⭐ 选集/历史记录定位到当前分集（第 N 话），而非第一集
            const matchedEpIdx = this.pgcEpIds_.indexOf(this.epId_);
            this.currentPageIndex = matchedEpIdx >= 0 ? matchedEpIdx : 0;
            // ⭐ PGC 评论加载：不走 loadD（无 bvid），手动设置评论 oid（=分集 aid）
            this.commentCursor = 0;
            this.commentDataSource.clear();
            this.pendingCommentAid = targetEpAid;
            if (this.commentsInitialized && targetEpAid > 0) {
              this.loadC(targetEpAid);
              this.pendingCommentAid = 0;
            }
            logInfo(`[VideoPlayer] PGC epId=${epIdParam} 季接口回退: seasonId=${this.seasonId_}, cid=${this.vi.cid}, 评论aid=${targetEpAid}, title=${this.vi.title}`);
          }
        }
      } else if (mediaIdParam > 0) {
        // 只有 mediaId：先获取季信息取第一集
        this.seasonId_ = mediaIdParam;
        this.isPgc_ = true;
        logInfo(`[VPP] step3: getPgcSeasonInfo(mediaId=${mediaIdParam}) 开始`);
        const pgcInfo: PgcSeasonInfo | null = await getPgcSeasonInfo(mediaIdParam);
        logInfo(`[VPP] step3: getPgcSeasonInfo 完成`);
        if (pgcInfo && pgcInfo.episodes.length > 0) {
          const firstEp = pgcInfo.episodes[0];
          if (firstEp.id && firstEp.id > 0) {
            this.epId_ = firstEp.id;
          }
          if (firstEp.cid && firstEp.cid > 0) {
            this.setPlaybackCid(firstEp.cid);
          }
          if (!this.vi.title && pgcInfo.title) {
            this.vi.title = pgcInfo.title;
          }
          if (!this.vi.cover && pgcInfo.cover) {
            this.vi.cover = pgcInfo.cover;
          }
          // ⭐ 填充详情卡片数据（vd）：标题/简介/制作方/统计/分集列表
          const owner: VideoDetailOwner = {
            mid: pgcInfo.upInfo.mid || 0,
            name: pgcInfo.upInfo.uname || (pgcInfo.staff || pgcInfo.actors || ''),
            face: pgcInfo.upInfo.avatar || ''
          };
          const stat: VideoDetailStat = {
            aid: 0,
            view: pgcInfo.stat.view,
            danmaku: pgcInfo.stat.danmaku,
            reply: pgcInfo.stat.reply,
            favorite: pgcInfo.stat.favorite,
            coin: pgcInfo.stat.coin,
            share: 0,
            like: pgcInfo.stat.like,
            dislike: 0
          };
          const pages: VideoPageItem[] = [];
          const pgcEpIds: number[] = [];
          const pgcAids: number[] = [];
          for (let i = 0; i < pgcInfo.episodes.length; i++) {
            const ep = pgcInfo.episodes[i];
            pages.push({
              cid: ep.cid || 0,
              page: i + 1,
              part: (ep.long_title || ep.title || `第${i + 1}话`),
              // ⭐ PGC season 接口 duration 为毫秒（UGC 为秒），转秒后再供 formatDuration 显示
              duration: ep.duration ? Math.floor(ep.duration / 1000) : 0,
              // ⭐ 分集封面（选集弹窗显示）
              cover: ep.cover || ''
            });
            pgcEpIds.push(ep.id || 0);
            pgcAids.push(ep.aid || 0);
          }
          this.pgcEpIds_ = pgcEpIds;
          this.pgcAids_ = pgcAids;
          // ⭐ 番剧评论 oid 用该集的 aid（不能用 ep_id，否则查到的评论是错的）
          const firstEpAid = pgcAids.length > 0 ? pgcAids[0] : 0;
          const pgcDetail: VideoDetail = {
            bvid: '',
            aid: firstEpAid,  // 番剧评论 oid = 分集 aid
            title: pgcInfo.title,
            desc: pgcInfo.desc || `${pgcInfo.actors || ''} ${pgcInfo.staff || ''}`.trim(),
            pic: pgcInfo.cover,
            pubdate: pgcInfo.pubdate,
            ctime: pgcInfo.pubdate,
            duration: 0,
            owner: owner,
            stat: stat,
            cid: this.vi.cid,
            pages: pages
          };
          this.vd = pgcDetail;
          // 互动统计初始化（点赞/投币/收藏数）
          this.likeCount = stat.like;
          this.coinCount = stat.coin;
          this.favoriteCount = stat.favorite;
          this.currentPageIndex = 0;
          // ⭐ PGC 评论加载：不走 loadD（无 bvid），手动设置评论 oid（=分集 aid）
          this.commentCursor = 0;
          this.commentDataSource.clear();
          this.pendingCommentAid = firstEpAid;
          if (this.commentsInitialized && firstEpAid > 0) {
            // 入场动画已完成 → 直接加载
            this.loadC(firstEpAid);
            this.pendingCommentAid = 0;
          }
          logInfo(`[VideoPlayer] PGC季信息: mediaId=${mediaIdParam}, 共${pgcInfo.episodes.length}集, 取第一集 epId=${this.epId_}, cid=${this.vi.cid}, title=${this.vi.title}, 制作方=${owner.name}, 播放=${stat.view}`);
          // ⭐ seasonId 以接口返回为准修正：路由 mediaId 可能是 media_id 而非 season_id
          //   （实测 media_id 当 sid 也能落库，但用真实 season_id 更稳）
          if (pgcInfo.seasonId > 0 && pgcInfo.seasonId !== this.seasonId_) {
            logInfo(`[VideoPlayer] seasonId 修正: ${this.seasonId_} → ${pgcInfo.seasonId}`);
            this.seasonId_ = pgcInfo.seasonId;
          }
        } else {
          logWarn(`[VideoPlayer] PGC季信息获取失败 mediaId=${mediaIdParam}`);
        }
        // 季信息第一集缺 cid 时兜底
        if (this.epId_ > 0 && (!this.vi.cid || this.vi.cid <= 0)) {
          logInfo(`[VPP] step4: getPgcEpisodeInfo 兜底(epId=${this.epId_}) 开始`);
          const epInfo = await getPgcEpisodeInfo(this.epId_);
          logInfo(`[VPP] step4: getPgcEpisodeInfo 兜底完成`);
          if (epInfo && epInfo.cid && epInfo.cid > 0) {
            this.setPlaybackCid(epInfo.cid);
            logInfo(`[VideoPlayer] PGC epId=${this.epId_} 分集接口兜底取到 cid=${this.vi.cid}`);
          }
        }
      }
      // ⭐⭐ PGC 必须保证 seasonId / aid / cid 齐全（进页就解析，不等到心跳/退出）：
      //   B 站的 type=4 心跳缺 sid 会被**静默丢弃**（code=0 但云端 progress 不动），
      //   表现为"播放时正常、退出后官方历史变 0、重进只能定位到集"。
      //   epId 入口（HomePage 番剧卡 / 动态页 / UP空间页）原先只在 cid 缺失时才查季接口，
      //   走了分集接口快路就把 seasonId 漏掉了，所以这里统一兜底。
      if (this.isPgc_ && this.epId_ > 0) {
        await this.ensurePgcContext();
        // ⭐⭐ PGC 详情卡片 + 评论：必须在上面那个反查块【之外】、无条件调用。
        //   反查块被 `!cid || cid<=0` 守卫，来源页把 cid 一起带进来时（观看历史）整块被跳过，
        //   vd / pendingCommentAid 就永远填不上 —— 表现为"点番剧进去只有播放器，没有详情卡和评论"。
        //   这里的季信息刚刚被 ensurePgcContext 缓存，调用是零网络的纯同步填充。
        await this.fillPgcDetailFromSeason();
      }
      // ⭐ 获取初始播放进度（从历史记录恢复）
      this.initialProgress_ = typeof p['initialProgress'] === 'number' ? p['initialProgress'] : 0;
      logInfo(`[VideoPlayer] 路由参数: bvid=${this.vi.bvid}, aid=${aidFromParams}, pgc=${this.isPgc_}, epId=${this.epId_}, seasonId=${this.seasonId_}, initialProgress=${this.initialProgress_}`);
      if (this.initialProgress_ > 0) {
        logInfo(`[VideoPlayer] 从历史记录恢复播放进度: ${this.initialProgress_}秒`);
      }
    }

    // Opening a full player replaces the existing native PiP session before taking its decoder.
    if (!this.floatingRestoring && AppStorage.get<boolean>('floatingPiPActive')) await FloatingPiP.getInstance().detach();

    // ⭐ 清除最小化标志（PlayerService 接管了恢复逻辑，旧状态仅用于清理）
    if (!this.floatingRestoring) AppStorage.set('videoMinimized', false);

    // ⭐ 检查 PlayerService — 不匹配的播放器先释放
    const ps = PlayerService.getInstance();
    if (ps.hasActivePlayer && ps.playerState && (this.continuationRestore_ || ps.playerState.bvid !== this.vi.bvid)) {
      logInfo('[VideoPlayer] PlayerService 中的播放器属于不同视频，释放');
      ps.release();
    }

    // ⭐ 检查 PlayerService 是否有存活播放器（从最小化恢复时无缝续播）
    if (ps.hasActivePlayer && ps.playerState && ps.playerState.bvid === this.vi.bvid) {
      logInfo('[VideoPlayer] 接管 PlayerService 已有播放器，跳过网络请求');
      // 从保存的状态恢复播放参数
      this.vi.bvid = ps.playerState.bvid;
      this.setPlaybackCid(ps.playerState.cid);
      this.vi.title = ps.playerState.title;
      this.vi.cover = ps.playerState.cover;
      // ⭐ 恢复 PGC/详情参数（浮窗恢复时路由参数为空，否则下方参数校验失败跳过详情/评论加载）
      this.aidFromParams_ = ps.playerState.aid;
      this.epId_ = ps.playerState.epId;
      this.seasonId_ = ps.playerState.seasonId;
      this.isPgc_ = this.epId_ > 0;
      // ⭐ 使用 AVPlayer 当前实时进度（播放器一直在后台运行），而非最小化时的快照
      const realTimeMs: number = ps.videoPlayer ? ps.videoPlayer.currentTime : 0;
      this.initialProgress_ = realTimeMs / 1000;
      logInfo(`[VideoPlayer] 实时进度: ${realTimeMs}ms = ${this.initialProgress_}s (快照: ${ps.playerState.currentTime}s)`);
      this.qn = ps.playerState.quality;
      this.ql = ps.playerState.qualityLabel;
      this.aq = ps.playerState.qualities || [];
      this.aqBvid = this.vi.bvid;
      this.aqCid = this.vi.cid;
      this.vol = ps.playerState.volume;
      this.mute = ps.playerState.mute;
      this.play = ps.playbackState === 'playing';
      this.userPaused_ = !this.play;
      // ⭐ 恢复横屏竖屏视频模式和宽高比
      this.isLandscapeVertical = ps.playerState.isLandscapeVertical;
      this.ar = ps.playerState.videoAspectRatio;
      // 恢复的是一路算下来的显示尺寸：打上 meta 标记，避免 setupL 的画幅快照在
      // rotate=90 的源上把竖屏比例改成编码尺寸（1.778）——那是同一条源的另一种写法。
      this.arFromMeta_ = this.ar > 0.05 && this.ar < 20;
      this.arMetaCid_ = this.vi.cid;

      // 接管播放器引用
      this.av = ps.videoPlayer;
      this.avAudio = ps.audioPlayer;
      this.waitingForFirstFrame = false;
      this.referenceSpareSurfaceMounted = true;

      // ⭐ DASH 转播站句柄从 PlayerService 取回（桥已移交；句柄的 stop() 供页面退出停服）
      //    播放器恢复后继续消费转播站流，server 生命周期此刻归本页面。
      const dashServer = ps.takeDashServer();
      this.dashHandle_ = dashServer;
      this.isDashStream_ = dashServer !== null;
      if (dashServer) {
        logInfo('[VideoPlayer] 恢复接管：转播站句柄已取回（服务继续运行）');
      } else {
        this.isDashStream_ = false;
      }

      // 清除 PlayerService 状态
      ps.hasActivePlayer = false;
      ps.videoPlayer = null;
      ps.audioPlayer = null;
      ps.playerState = null;

      // 注册新页面的事件监听器
      this.setupL();
      this.setupAudioL();

      // 延迟绑定 XComponent surface 并恢复播放（build 后 surface 才就绪）
      setTimeout(() => {
        this.resumeFromMinimized();
      }, this.floatingRestoring ? 16 : 500);

      // ⭐ 浮窗恢复：PGC 补详情/评论（loadD 仅 UGC，bvid 空时直接 return，不会加载 PGC 详情）
      if (this.isPgc_ && this.epId_ > 0) {
        this.fillPgcDetailFromSeason();
      }
    }

    // ⭐ 智感握持初始化（在所有早返回之前执行，确保所有路径都订阅）
    // 动态请求手势权限（需真机HarmonyOS 6+）
    this.requestGesturePermission();
    // 初始化智感握持位置（查询系统安全区域）
    this.initSmartGripPosition();
    // 订阅握持状态变化
    this.subscribeGripChanges();

    // 检查参数有效性：需要bvid、aid、或 PGC（epId_）
    if (!this.vi.bvid && !aidFromParams && !(this.isPgc_ && this.epId_ > 0)) {
      this.err = '参数错误：缺少视频ID';
      this.ld = false;
      return;
    }

    // ⭐ PGC（番剧/影视）模式：跳过 bvid/aid 转换，直接使用 epId_ + cid
    // 无需 return：下方公共流程（qn/音量/弹幕状态/initW/loadD/心跳）对 PGC 同样适用
    if (this.isPgc_) {
      if (!this.vi.cid || this.vi.cid <= 0) {
        logWarn('[VideoPlayer] PGC cid 无效，尝试从 epId 获取 cid');
      }
      logInfo(`[VideoPlayer] PGC 模式: epId=${this.epId_}, seasonId=${this.seasonId_}, cid=${this.vi.cid}, title=${this.vi.title}`);
    }

    // 如果没有bvid、或者bvid是数字（实际上是aid），通过aid获取视频信息
    // 心跳上报需要真实的BV格式bvid，否则B站API返回-400
    const isNumericBvid: boolean = /^\d+$/.test(this.vi.bvid);
    if ((!this.vi.bvid || isNumericBvid) && aidFromParams) {
      if (isNumericBvid) {
        logInfo('[VideoPlayer] bvid是数字格式(实际是aid)，通过aid获取真实bvid:', aidFromParams);
      } else {
        logInfo('[VideoPlayer] 通过aid获取视频信息:', aidFromParams);
      }
      logInfo(`[VPP] 走 initFromAid 分支, aid=${aidFromParams}`);
      this.initFromAid(aidFromParams);
      return;
    }

    if (isNaN(this.vi.cid)) {
      this.setPlaybackCid(0);  // 默认cid，后续会通过API获取
    }
    // 偏好画质与显示画质一起落地；applyDefaultQuality 幂等，只读 AppStorage。
    this.applyDefaultQuality();
    this.readSystemVolume();
    const sm = AppStorage.get<boolean>('globalMuted');
    if (sm !== undefined) this.mute = sm;
    // ⭐ 读取弹幕开关状态（优先从Preferences读取持久化值）
    this.loadDanmakuEnabledState();
    // ⭐ 读取控制栏镜像布局状态
    this.loadMirrorControlsState();
    this.loadSM();
    logInfo('[VPP] 走 bvid 主分支, 即将调用 initW/loadD/checkBiliLoginStatus');
    this.initW().then(() => {
      logInfo('[VPP] initW 完成');
      if (this.mw) this.manageSB();
      // ⭐ initW 已设置 isLs/cw/ch 并调用了 updateIsLandscapeVertical + updateVideoSize
      // 这里只确保系统栏状态正确
    });
    this.activateAudioSession();
    this.resetCT();
    logInfo('[VPP] 即将调用 loadD');
    this.loadD();
    this.initP();
    // ⭐ 启动心跳定时器
    this.startHeartbeat();
    // ⭐ 检测B站登录状态（调用API验证）
    logInfo('[VPP] 即将调用 checkBiliLoginStatus');
    this.checkBiliLoginStatus();
    // ⭐ 封面预解码已延后到首帧后（startRenderFrame → predecodeCover），此处不再与起播抢资源
    logInfo('[VPP] aboutToAppear 同步部分完成');
    this.playbackProfile?.mark('appear-sync-end');
  }

  /** 尝试初始化 GL 渲染管线 — 已禁用（当前设备/OS 不支持帧拦截） */
  private tryInitGL_(xcSurfaceId: string): void {
    logInfo(`[VideoFilter] GL disabled, using direct XComponent rendering`);
    return;
  }

  private startGLRenderLoop(): void { /* 已禁用 */ }
  private stopGLRenderLoop(): void { /* 已禁用 */ }
  private releaseGL_(): void { /* 已禁用 */ }

  // ⭐ 检测B站登录状态（调用API验证）
  private async checkBiliLoginStatus(): Promise<void> {
    logInfo('[VPP] checkBiliLoginStatus 开始');
    try {
      // 先快速检查Cookie是否含SESSDATA
      if (!this.biliCookie.includes('SESSDATA')) {
        this.isBiliLoggedIn = false;
        logInfo('[VideoPlayer] Cookie无SESSDATA，未登录');
        return;
      }
      // Cookie有SESSDATA，再调用API验证
      logInfo('[VPP] checkBiliLoginStatus: 调用 getUserInfo 开始');
      const userInfo = await getUserInfo();
      logInfo('[VPP] checkBiliLoginStatus: getUserInfo 完成');
      if (userInfo && userInfo.isLogin) {
        this.isBiliLoggedIn = true;
        logInfo('[VideoPlayer] API验证登录成功, mid=' + userInfo.mid);
      } else {
        this.isBiliLoggedIn = false;
        logInfo('[VideoPlayer] API验证登录失败，Cookie已失效');
      }
    } catch (err) {
      logError('[VideoPlayer] 检测登录状态异常: ' + err);
      // 保底：用Cookie判断
      this.isBiliLoggedIn = this.biliCookie.includes('SESSDATA');
    }
    logInfo('[VPP] checkBiliLoginStatus 完成');
  }

  // ⭐ 智感握持 - 查询系统安全区域（异步，仅查询原始px值）
  private async initSmartGripPosition(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win: window.Window = await window.getLastWindow(context);
      // 获取底部导航指示器（手势横条 → 决定按钮底部边距）
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const bottomPx = navArea?.bottomRect?.height ?? 0;
      this.gripSafeAreaBottom = this.getUIContext().px2vp(bottomPx) + 8; // 略高于手势横条，避免冲突
      // 获取侧边手势区域（返回手势 → 决定按钮右侧/左侧边距）
      const gestureArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
      const rightPx = gestureArea?.rightRect?.width ?? 0;
      this.gripSafeAreaRight = (rightPx > 0 ? this.getUIContext().px2vp(rightPx) : 0) + 16;
      const leftPx = gestureArea?.leftRect?.width ?? 0;
      this.gripSafeAreaLeft = (leftPx > 0 ? this.getUIContext().px2vp(leftPx) : 0) + 16;
      // 获取系统避让区（状态栏/刘海/挖孔）左侧安全区 → 全屏时左侧锁定按钮避开前置摄像头
      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const sysLeftPx = sysArea?.leftRect?.width ?? 0;
      const sysLeftSafe: number = sysLeftPx > 0 ? this.getUIContext().px2vp(sysLeftPx) : 0;
      AppStorage.setOrCreate('safeAreaLeft', sysLeftSafe);
      logInfo(`[SmartGrip] TYPE_SYSTEM leftSafe=${sysLeftSafe}vp`);
    } catch (e) {
      logWarn('[SmartGrip] 安全区域查询失败，使用默认值');
    }
    // 无论是否查询成功，都用当前容器尺寸重算按钮位置
    this.recalcSmartGripPosition();
  }

  /** 全屏后重新查询左侧安全区（规避前置摄像头/挖孔） */
  private async refreshSafeAreaLeft(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win: window.Window = await window.getLastWindow(context);
      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      // 横屏时优先用 leftRect，部分设备把前置挖孔报在 topRect 中
      const leftPx = sysArea?.leftRect?.width ?? 0;
      const topPx = sysArea?.topRect?.width ?? 0;
      const rawPx = leftPx > topPx ? leftPx : topPx;
      const safeVp: number = rawPx > 0 ? this.getUIContext().px2vp(rawPx) : 0;
      // 如果系统没返回安全区，用 statusBarHeight 作为兜底（与前置挖孔宽度大致相当）
      const sbHeight: number = AppStorage.get<number>('statusBarHeight') ?? 40;
      const fallback: number = sbHeight > 0 ? sbHeight : 40;
      const finalValue: number = safeVp > 0 ? safeVp : fallback;
      AppStorage.setOrCreate('safeAreaLeft', finalValue);
      logInfo(`[SafeArea] 全屏左侧安全区=${finalValue}vp (left=${leftPx} top=${topPx} fallback=${fallback})`);
    } catch (e) {
      logWarn('[SafeArea] 查询失败', e);
    }
  }

  // ⭐ 智感握持 - 根据方向+容器尺寸+握持手计算拇指热区按钮位置（同步，可频繁调用）
  private recalcSmartGripPosition(): void {
    const bottomSafe = this.gripSafeAreaBottom;
    const screenH = this.ch > 0 ? this.ch : 800; // 兜底

    // 计算通用底部边距
    if (this.isLs) {
      // 横屏/全屏 → 拇指握持在屏幕右侧，按钮在右下角的20%高度区
      this.smartGripBottom = Math.max(bottomSafe + 24, screenH * 0.20);
    } else {
      // 竖屏 → 拇指自然在右下角，按钮在底部15%高度区（比之前6%更高）
      this.smartGripBottom = Math.max(bottomSafe + 12, screenH * 0.15);
    }

    // ⭐ 根据握持手切换按钮左右位置
    // 两边始终保持有效值，避免 position 跳变触发平移动画
    this.smartGripLeft = this.gripSafeAreaLeft + 16;
    this.smartGripRight = this.gripSafeAreaRight + 8;
  }

  // ⭐ 订阅握持状态变化（motion.on 智感握持）
  private subscribeGripChanges(): void {
    if (this.gripListenerSubscribed) return;
    if (!this.smartGripEnabled) return;
    try {
      motion.on('holdingHandChanged', (data: motion.HoldingHandStatus) => {
        if (data !== this.hand && (data === motion.HoldingHandStatus.LEFT_HAND_HELD || data === motion.HoldingHandStatus.RIGHT_HAND_HELD)) {
          this.hand = data;
          this.recalcSmartGripPosition();
          logInfo(`[SmartGrip] motion握持状态变化: ${data}`);
        }
      });
      logInfo('[SmartGrip] 已订阅motion握持变化事件');
      this.gripListenerSubscribed = true;
    } catch (err) {
      const error = err as BusinessError;
      logError(`[SmartGrip] motion订阅失败. Code: ${error.code}, message: ${error.message}`);
      // 不设置 gripListenerSubscribed = true，让后续 onPageShow 可以重试
    }
  }

  // ⭐ 动态申请手势检测权限（敏感权限，需运行时请求）
  private async requestGesturePermission(): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(this.getUIContext().getHostContext() as common.UIAbilityContext,
        ['ohos.permission.DETECT_GESTURE']);
      logInfo('[SmartGrip] 手势权限已授权');
    } catch (e) {
      const err = e as BusinessError;
      logWarn(`[SmartGrip] 手势权限被拒绝: ${err.code}`);
    }
  }

  // ⭐ 取消订阅握持状态变化
  private unsubscribeGripChanges(): void {
    if (!this.gripListenerSubscribed) return;
    // motion.off('holdingHandChanged') 是全局操作，会移除所有页面的监听器
    // 因此让 Index.ets 管理全局生命周期，本页只复位标记
    this.gripListenerSubscribed = false;
    logInfo('[SmartGrip] 标记已取消（保留全局监听）');
  }

  /**
   * 通过aid初始化视频信息
   * 当历史记录只有aid没有bvid时使用
   */
  /**
   * ⭐ aid 入口（App 推荐 feed 只有 aid，没有真 bvid）
   * 旧实现自己 `http.createHttp()` 打 `/x/web-interface/view/detail?aid=`，解析出 bvid 后
   *   loadD 又打了一次 `/x/web-interface/view?bvid=` —— **同一个稿件请求两次**，且都在起播关键路径上。
   * 现在改走带缓存 + 请求去重的 getVideoDetail(aid)：
   *   - 来源页"点卡片"时预热过就命中缓存/复用在飞请求，0 网络；
   *   - 返回里的 cid 一并写进 vi.cid：cid 是起播硬前提，越早拿到越早能发 playurl；
   *   - loadD 随后用 bvid 再查会命中同一条缓存，不再重复请求。
   */
  /** 把偏好画质同步应用到 this.qn；只读 AppStorage，不触发任何异步。 */
  private applyDefaultQuality(): void {
    const dq: number | undefined = AppStorage.get<number>('defaultVideoQn');
    if (dq === undefined || dq <= 0) return;
    this.preferredQn = dq;
    this.qn = dq;
    const it = this.ql_.find(q => q.qn === dq);
    if (it) this.ql = it.label;
  }

  /** AV/CID 卡片无需等待详情即可准备播放器；详情仍负责 BV、简介及心跳。 */
  private startAidPlayback(): void {
    // 连刷/推荐卡片（只有 aid）同样以设置里的偏好画质取流。
    this.applyDefaultQuality();
    this.readSystemVolume();
    const sm = AppStorage.get<boolean>('globalMuted');
    if (sm !== undefined) this.mute = sm;
    this.loadSM();
    this.initW().then(() => {
      if (this.mw) this.manageSB();
      // ⭐ initW 已设置 isLs/cw/ch 并调用了 updateIsLandscapeVertical + updateVideoSize
    });
    this.activateAudioSession();
    this.resetCT();
    this.initP();
    this.loadDanmakuEnabledState();
    this.loadMirrorControlsState();
  }

  private async initFromAid(aid: number) {
    logInfo('[initFromAid] 开始获取视频信息, aid:', aid);
    const generation = this.referenceSwitchGeneration;
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const startedPlayback: boolean = this.vi.cid > 0;
    if (startedPlayback) {
      this.vi.bvid = String(aid);
      this.startAidPlayback();
    }
    try {
      const d: VideoDetail | null = await getVideoDetail(String(aid));
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration ||
        cookie !== (AppStorage.get<string>('biliCookie') || '')) return;
      if (!d || !d.bvid) {
        if (startedPlayback) return;
        logError('[initFromAid] 获取视频信息失败');
        this.err = '获取视频信息失败';
        this.ld = false;
        logInfo('[VPP] initFromAid 完成');
        return;
      }
      this.vi.bvid = d.bvid;
      this.applyDetailDimension(d);
      if (!this.vi.title && d.title) this.vi.title = d.title;
      if (!this.vi.cover && d.pic) this.vi.cover = d.pic;
      if ((!this.vi.cid || this.vi.cid <= 0) && d.cid && d.cid > 0) {
        this.setPlaybackCid(d.cid);
      }
      if ((!this.vi.cid || this.vi.cid <= 0) && d.pages && d.pages.length > 0) {
        this.setPlaybackCid(d.pages[0].cid || 0);
      }
      logInfo(`[initFromAid] 获取到bvid: ${this.vi.bvid}, cid=${this.vi.cid}`);

      if (!startedPlayback) this.startAidPlayback();
      this.loadD();
      this.startHeartbeat();
    } catch (e) {
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration ||
        cookie !== (AppStorage.get<string>('biliCookie') || '')) return;
      logError('[initFromAid] 异常:', JSON.stringify(e));
      if (startedPlayback) return;
      this.err = '加载失败';
      this.ld = false;
    }
    logInfo('[VPP] initFromAid 完成');
  }

  // ⭐ 用户是否主动点击了暂停（区别于系统 onPageHide 暂停）
  private userPaused_: boolean = false
  // ⭐ 后台播放：onPageHide 中暂时暂停，onBackground 确认后恢复
  private bgpPausedByPageHide_: boolean = false
  // ⭐ 播完（completed）的时刻 + 最近一次自动起播的调用点：
  //    两者配合，出现「播完又从头出声」时日志能直接指出是谁把播放器拉起来的。
  private playbackCompletedAt_: number = 0
  private lastAutoPlaySite_: string = ''

  private pagePlaybackAllowed(): boolean {
    // ⭐ 页面被其它路由页覆盖时，一律不允许启动/恢复播放：
    //    appInBackground 只能证明「应用切后台」，不能证明「播放器仍是最上层页面」。
    return this.referenceAlive && !this.pageCoveredByRoute_ &&
      (this.playerPageVisible || (this.bgp && this.appInBackground));
  }

  /**
   * 播完是终态。
   * AVPlayer 在 completed 态被 play() 会从片头重播（IJK 则表现为无反应），两条路径行为还不一致，
   * 所以除「用户显式重播」（referenceReplay / 重播按钮 / 循环模式）与用户 seek 外，
   * 任何自动恢复（回前台、后台确认、缩小还原、连刷兜底、媒体会话补发 play）都先问过这里。
   */
  private playbackIsTerminal(): boolean {
    return this.referencePlaybackCompleted || this.av?.state === 'completed';
  }

  /** 记录一次自动起播的调用点（只用于诊断，不改变行为）。 */
  private markAutoPlay(site: string): void {
    this.lastAutoPlaySite_ = site;
    logInfo(`[VideoPlayer] auto-play: ${site} state=${this.av?.state ?? 'none'} completed=${this.referencePlaybackCompleted}`);
  }

  private normalizeRoutePath(path: string): string {
    return path.replace(/^\//, '').replace(/\.(ets|js|ts)$/, '');
  }

  /** 页面隐藏瞬间的路由栈顶；pushUrl 尚未完成时可能仍是本页，故只作辅助判断。 */
  private currentTopPage(): string {
    try {
      const state = router.getState();
      const raw = state.path.endsWith('/') ? `${state.path}${state.name}` : state.path;
      return this.normalizeRoutePath(raw);
    } catch (_e) {
      return '';
    }
  }

  /** 切后台那一刻的栈顶，由 EntryAbility.onBackground 记录，路由栈此时已稳定。 */
  private backgroundTopPage(): string {
    const recorded = AppStorage.get<string>('appBackgroundTopPage') ?? '';
    return recorded.length > 0 ? this.normalizeRoutePath(recorded) : this.currentTopPage();
  }

  /** 最后一次 onPageShow 的播放页实例编号（空串 = 从未登记）。 */
  private topPlayerPageInstanceId(): string {
    return AppStorage.get<string>(TOP_PLAYER_PAGE_KEY) ?? '';
  }

  /**
   * 本实例是否就是「当前最上层的播放页」。
   * 未登记（空串）时按「是」处理：保留原来的 path 单一判据，避免历史路径失效后后台播放全哑。
   */
  private isTopPlayerPageInstance(): boolean {
    const topId = this.topPlayerPageInstanceId();
    return topId.length === 0 || topId === this.pageInstanceId_;
  }

  /** 播放页已被覆盖时确保没有残留播放（视频轨 + 音频轨 + 状态 + 实况窗）。 */
  private pausePlaybackForCoveredPage(): void {
    if (this.av?.state === 'playing') this.av.pause().catch(() => {});
    if (this.avAudio?.state === 'playing') this.avAudio.pause().catch(() => {});
    this.play = false;
    // 媒体会话是进程级单例（LiveViewHelper）：被覆盖的旧页在这里写「暂停」，
    // 会把正在后台播放的新页在通知栏/锁屏上显示成已暂停。只有本页仍是最上层时才写。
    if (this.isTopPlayerPageInstance()) LiveViewHelper.updatePlayState(false);
  }

  // Native play() and startup seeks can finish after a route has covered this page.
  private async startPagePlayback(player: PlaybackPlayer, withAudio: boolean = true): Promise<boolean> {
    if (this.av !== player || !this.pagePlaybackAllowed() || this.userPaused_) return false;
    // ⭐ 这里被 onPageShow / onBackground 确认两条自动路径共用：
    //    对 completed 的播放器调 play() 会直接从头重播，必须先拦。
    if (this.playbackIsTerminal()) {
      logInfo(`[VideoPlayer] startPagePlayback 跳过：已播完 state=${player.state}`);
      return false;
    }
    if (player.state !== 'playing') {
      this.markAutoPlay('startPagePlayback');
      await player.play();
    }
    if (this.av !== player) return false;
    if (!this.pagePlaybackAllowed() || this.userPaused_) {
      if (player.state === 'playing') await player.pause();
      return false;
    }
    const audio = this.avAudio;
    if (withAudio && audio && (audio.state === 'prepared' || audio.state === 'paused')) await audio.play();
    if (this.av !== player) return false;
    if (!this.pagePlaybackAllowed() || this.userPaused_) {
      if (player.state === 'playing') await player.pause();
      if (audio?.state === 'playing') await audio.pause();
      return false;
    }
    return true;
  }

  /**
   * ⭐ 屏幕常亮：播放中保持屏幕不锁，暂停/隐藏/退出时关闭（防止播放中被自动锁屏）
   */
  private updateKeepScreen(): void {
    this.mw?.setWindowKeepScreenOn(this.play).catch(() => {});
  }

  /** play 状态变化时同步屏幕常亮 */
  private onPlayChanged(): void {
    if (this.play) this.floatingPausedFrame = undefined;
    this.updateKeepScreen();
  }

  /**
   * 页面隐藏时（切后台/跳转其他页面）：根据后台播放开关决定是否暂停
   * 后台播放只允许真正切后台，页面跳转始终暂停，包括尚未准备完成的播放器。
   */
  onPageHide(): void {
    this.playerPageVisible = false;
    // ⭐ 记录本次隐藏的成因：栈顶已变成别的页面就是跳页，不是切后台；
    //    pushUrl 时序可能让这里仍读到本页，故 onBackground 确认时会用 Ability 记录的栈顶复核。
    //    同一路由的另一个播放页（点相关推荐 push 出的 B）path 与本节相同，还得靠实例编号区分。
    const topOnHide = this.currentTopPage();
    this.pageCoveredByRoute_ = topOnHide.length > 0 &&
      (topOnHide !== 'pages/VideoPlayerPage' || !this.isTopPlayerPageInstance());
    // ⭐ 提前一步恢复状态栏内容色：pop 出栈或被普通页面覆盖时，此刻路由栈已指向目标页，
    //    立即恢复主题口径（直用 this.mw，少一次 getLastWindow 中转），别等 aboutToDisappear
    //    ——那时转场动画已经跑起来，颜色切换会明显滞后。目标页还是播放页（同路由另一实例
    //    或直播页）则交给对方的 onPageShow 强制白字，这里不下发主题口径。
    if (topOnHide.length > 0 && topOnHide !== 'pages/VideoPlayerPage' && topOnHide !== 'pages/LivePlayerPage') {
      StatusBarUtils.restoreThemeStatusBarContent(
        this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
    }
    this.playbackListPrefetch.pause();
    this.releaseReferenceFeedPreview();
    // ⭐ 页面隐藏即释放屏幕常亮（后台播放/跳页时屏幕可正常锁屏）
    this.mw?.setWindowKeepScreenOn(false).catch(() => {});
    // 播放器已转移至 PlayerService（最小化场景），页面不再控制播放
    if (PlayerService.getInstance().hasActivePlayer) {
      logInfo('[VideoPlayer] onPageHide → 播放器已转移至 PlayerService，跳过');
      return;
    }
    if (!this.av) {
      return;
    }
    if (this.bgp) {
      // ⭐ 后台播放仅针对「真正切后台」：已确认（onBackground 先行）则保持播放；
      // 页面跳转（pushUrl 覆盖本页，如进个人空间/切换视频）不触发 onBackground，
      // 先暂停，等待 onBackground 确认后再恢复，避免新旧视频声音重叠
      if (this.appInBackground) {
        logInfo('[VideoPlayer] onPageHide → 后台播放模式（已切后台），保持播放');
        return;
      }
      logInfo('[VideoPlayer] onPageHide → 后台播放模式：先暂停，onBackground 确认后恢复');
      this.bgpPausedByPageHide_ = true;
      if (this.av.state === 'playing') this.av.pause().catch(() => {});
      if (this.avAudio?.state === 'playing') this.avAudio.pause().catch(() => {});
      this.play = false;
      LiveViewHelper.updatePlayState(false);
      return;
    }
    // 暂停播放，防止切换到其他页面后旧视频仍在播放
    logInfo('[VideoPlayer] onPageHide → 暂停播放');
    if (this.av.state === 'playing') this.av.pause().catch(() => {});
    if (this.avAudio?.state === 'playing') this.avAudio.pause().catch(() => {});
    this.play = false;
    LiveViewHelper.updatePlayState(false);
  }

  /**
   * onBackground 确认回调（通过 @Watch 监听 appBackgroundTimestamp 变化触发）
   * 备用方案：用于 bgpPausedByPageHide_ 被设置的极少数兜底场景
   */
  onAppBackgroundConfirmed(): void {
    if (this.appBgTimestamp === 0) return;
    // ⭐ 关键复核：这次 onBackground 发生时，本页是否仍是「最上层的播放页实例」。
    //    1) 路由栈顶不是播放页 → 被其它页面覆盖（进 UP 空间、动态详情等）；
    //    2) 路由栈顶是播放页但不是本实例 → 被同路由的另一个播放页覆盖
    //       （播放页里点相关推荐 push 出 B，两页 path 都是 pages/VideoPlayerPage）。
    //    第 2 条是「旧视频暂停后一熄屏/切后台又自己响起来」的根因：path 比对对同路由无效，
    //    旧页把自己当成栈顶，于是把 onPageHide 时为等 onBackground 而临时暂停的视频重新拉起，
    //    和新页的后台播放叠成两条音轨。
    const topOnBackground = this.backgroundTopPage();
    const topIsPlayerPage = topOnBackground === 'pages/VideoPlayerPage';
    const coveredByOtherPage = !topIsPlayerPage || !this.isTopPlayerPageInstance();
    this.pageCoveredByRoute_ = coveredByOtherPage;
    if (coveredByOtherPage) {
      // pending 标记只是跳页/换视频时留下的，这里必须一并清掉，否则下次切后台会被误用。
      this.bgpPausedByPageHide_ = false;
      logInfo(`[VideoPlayer] onBackground 确认 → 栈顶=${topOnBackground || '未知'}`
        + ` topInstance=${this.topPlayerPageInstanceId()} self=${this.pageInstanceId_}，播放页已被覆盖，保持暂停`);
      this.pausePlaybackForCoveredPage();
      return;
    }
    if (!this.bgpPausedByPageHide_) return;
    this.bgpPausedByPageHide_ = false;
    if (!this.bgp) return;
    if (!this.av) return;
    logInfo('[VideoPlayer] onBackground 确认 → 后台播放模式，恢复播放');
    if (this.av.state === 'paused' || this.av.state === 'prepared') {
      const player = this.av;
      this.startPagePlayback(player).then((started: boolean) => {
        if (this.av === player && started) {
          this.play = true;
          LiveViewHelper.updatePlayState(true);
        }
      }).catch(() => {});
    }
  }

  /** 回到前台时若播放页仍被其它页面覆盖，兜底确保没有后台续播残留。 */
  private onAppBackgroundFlagChanged(): void {
    if (this.appInBackground || !this.pageCoveredByRoute_) return;
    logInfo('[VideoPlayer] 回前台 → 播放页仍被覆盖，保持暂停');
    this.pausePlaybackForCoveredPage();
  }

  /**
   * 页面显示时恢复播放（从后台/其他页面返回时）
   */
  onPageShow(): void {
    this.playerPageVisible = true;
    // ⭐ 登记「我是当前最上层的播放页实例」。被 push 出来的同路由页会覆盖这个值，
    //    被覆盖的旧页因此在切后台时不会误判自己仍在栈顶（见 onAppBackgroundConfirmed）。
    const previousTopId = this.topPlayerPageInstanceId();
    AppStorage.setOrCreate<string>(TOP_PLAYER_PAGE_KEY, this.pageInstanceId_);
    logInfo(`[VideoPlayer] page shown instance=${this.pageInstanceId_} prevTop=${previousTopId}`);
    this.pageCoveredByRoute_ = false;
    this.registerContinuation();
    // 清除 bgp 暂停标记（如果是页面跳转场景，onBackground 不会触发，标记仍存在）
    if (this.bgpPausedByPageHide_) {
      this.bgpPausedByPageHide_ = false;
      // 页面跳转回来（非后台），此时播放已被 onPageHide 暂停，按需恢复
    }
    if (!this.play && !this.userPaused_ && !this.restoringProgress && this.av &&
      (this.av.state === 'paused' || this.av.state === 'prepared')) {
      logInfo('[VideoPlayer] onPageShow → 恢复播放');
      const player = this.av;
      this.startPagePlayback(player).then((started: boolean) => {
        if (this.av === player && started) this.play = true;
      }).catch(() => {});
    }
    // ⭐ 屏幕常亮：回到页面按当前播放状态恢复
    this.updateKeepScreen();
    // ⭐ 从缓存页返回时同步缓存提示条：暂停后「继续」走的是 resume() 的新下载，
    // 最初 svc.download 的回调已结束，须按条目真实状态刷新完成文案
    this.syncCacheHintStatus();
    // ⭐ 页面恢复时重新订阅智感握持（上次订阅失败时可重试）
    if (!this.gripListenerSubscribed) {
      this.subscribeGripChanges();
    }
    // ⭐ 从后台切回来时强制恢复系统栏状态
    // onForeground → setupImmersiveWindow 依赖 AppStorage.isLandscape，
    // 但横屏时窗口实际尺寸可能仍是竖屏，导致 isLandscape=false → 错误显示状态栏。
    // 页面自身知道 fs/isLs 真实状态，force=true 强制覆盖。
    this.playerPageVisible = true;
    this.referenceWarmUpcomingFrames();
    logInfo('[VideoPlayer] onPageShow → manageSB(force=true)');
    if (this.mw) this.manageSB(true);
    // ⭐ 状态栏内容色强制白字：状态栏压在视频画面上，浅色模式的全局黑字（首页口径）会消失。
    //    必须与 manageSB 同拍同步下发：转场启动帧内发出窗口属性，IPC 落地在首帧后 1~3 帧
    //    （对齐原版「动画开始没几帧就变色」）。不能延迟中段下发——转场跑一半时再触发
    //    avoidArea 重算会顿掉动画一拍（观感「点击后没立即跳转」）；也不能更早（initW
    //    跑在转场首帧之前，会变成首页满屏时就变色）。已持有 mw 就直传，省一跳中转。
    StatusBarUtils.setPlayerStatusBarContent(
      this.getUIContext().getHostContext() as common.UIAbilityContext, this.mw ?? undefined);
    // ⭐ 延迟 1s 再次强制恢复，覆盖系统在窗口完全显示后（~568ms）才发的避让区通知
    setTimeout(() => {
      logInfo('[VideoPlayer] onPageShow → delayed manageSB');
      if (this.mw) this.manageSB(true);
    }, 1000);
  }

  aboutToDisappear() {
    if (this.neighborWarmTimer_ !== -1) {
      clearTimeout(this.neighborWarmTimer_);
      this.neighborWarmTimer_ = -1;
    }
    clearInterval(this.playbackDiagnosticTimer_);
    this.playbackDiagnosticTimer_ = -1;
    this.stopHdrUiBrightness();
    this.playbackListPrefetch.pause();
    clearTimeout(this.danmakuFocusTimer);
    this.danmakuFocusTimer = 0;
    clearTimeout(this.commentComposerStartTimer);
    this.commentComposerStartTimer = 0;
    this.commentComposerAnimator?.cancel();
    this.commentComposerAnimator = null;
    this.composerKeyboardAnimator?.cancel();
    this.composerKeyboardAnimator = null;
    AppContinuation.unregister(this);
    this.mw?.off('avoidAreaChange', this.onPlaybackAvoidAreaChanged);
    this.mw?.off('keyboardHeightChange', this.onDanmakuKeyboardHeight);
    if (this.landscapeComposerAvoidMode !== null) {
      this.getUIContext().setKeyboardAvoidMode(this.landscapeComposerAvoidMode);
      this.landscapeComposerAvoidMode = null;
    }
    // 动画改由 animateTo（渲染侧）驱动后没有句柄可 cancel，用代数号让收尾失效。
    this.referenceFeedCommentGen++;
    this.referenceFeedCommentAnimating = false;
    this.referenceModeGen++;
    this.referenceModeAnimating = false;
    this.referenceSetSleep(0);
    PlaybackStartup.finish(this.playbackProfile, 'exit');
    this.referenceAlive = false;
    this.initializationDeadline_?.cancel();
    this.referenceCancelFeedTap();
    this.playerPageVisible = false;
    this.referenceStopFeedMotion();
    this.referenceFeedMainCancel?.();
    this.referenceFeedDragEndResolve?.();
    this.referenceFeedDragEndResolve = null;
    const stillFrames = Array.from(this.referenceStillFrames.values());
    if (this.referencePreviewFrame) stillFrames.push(this.referencePreviewFrame);
    if (this.referencePinnedFrame) stillFrames.push(this.referencePinnedFrame);
    this.referencePreviewFrame = undefined;
    this.referencePinnedFrame = undefined;
    this.referenceStillFrames.clear();
    this.referenceStillDetails.clear();
    this.referenceStillRatios.clear();
    this.referenceDecodeRatios.clear();
    this.referenceWarmStaleAttempts.clear();
    this.referenceDetailJobs.clear();
    stillFrames.forEach((frame: image.PixelMap) => { this.retireStillFrame(frame); });
    this.referenceSwitchGeneration++;
    this.releaseReferenceFeedPreview();
    // ⭐ 进度调节缩略图：先松开 UI 引用再整体释放位图（避免释放后仍被组件引用）
    this.shotToken_++;
    this.thumb_ = new SeekThumb();
    VideoShotService.release();
    // ⭐ 注销系统音量变化监听
    if (this.coverGlowTimer) { clearInterval(this.coverGlowTimer); this.coverGlowTimer = 0; }
    // ⭐ 缩小/还原动画（animateVidShrink）：页面销毁时若动画还没收尾，弹幕是被关着的状态，
    //    必须补恢复（后台播放场景下 controller/配置可能被 PlayerService 继续持有）。
    //    非定时器动画，无需 clearInterval；代数号自增即可让迟到的 onFinish 失效。
    if (this.shrinkAnimating) {
      this.shrinkAnimGen++;
      this.shrinkAnimating = false;
      this.dmFreezeW = 0;
      this.dmFreezeH = 0;
      this.danmakuConfig.enable = this.isDanmakuEnabled;
    }
    this.unregisterVolumeListener();
    this.audioOutputMonitor.dispose();
    // ⭐ 页面销毁时清除全屏标志
    AppStorage.set('isFullscreen', false);
    // ⭐ 释放 GL 渲染资源
    this.releaseGL_();
    // ⭐ 停止心跳定时器
    this.stopHeartbeat();
    // ⭐ 停止音视频同步定时器
    this.stopSyncTimer();
    // ⭐ 取消声画同步（2x 追赶）
    this.cancelVideoSpeedSync();
    this.saveWatchHistory();
    this.reportWatchBehavior();  // ⭐ 上报观看行为
    this.clrT();
    this.clearLightBtnTimer(); // ⭐ 清除开灯按钮自动隐藏定时器
    this.release();
    this.restoreS();
    if (this.mw) this.mw.setWindowBrightness(this.originalBrightness_);
    // ⭐ 页面销毁时关闭屏幕常亮，避免占用窗口资源
    if (this.mw) this.mw.setWindowKeepScreenOn(false).catch(() => {});
    if (this.fsAnimTimer_ !== -1) {
      clearTimeout(this.fsAnimTimer_);
      this.fsAnimTimer_ = -1;
    }
    // ⭐ 取消智感握持监听
    this.unsubscribeGripChanges();
    // ⭐ 结束实况窗（后台播放模式保留后台任务和媒体会话）
    if (!this.bgp) {
      LiveViewHelper.end();
    } else {
      logInfo('[VideoPlayer] aboutToDisappear → 后台播放模式，保留实况窗和后台任务');
      // 系统小窗服务持有媒体控制回调，不再引用已销毁的页面。
    }
    // ⭐ 清除实况窗节流定时器
    if (this.lvTimer_ !== -1) {
      clearTimeout(this.lvTimer_);
      this.lvTimer_ = -1;
    }
    // ⭐ 释放预解码的图像缓存
    clearImageCache();
  }

  /**
   * ⭐ 启动心跳定时器
   * 每15秒向B站上报一次观看进度，让推荐算法实时学习用户偏好
   */
  private startHeartbeat(): void {
    if (this.heartbeatTimer !== -1) return;

    this.heartbeatTimer = setInterval(() => {
      this.sendHeartbeat();
    }, this.HEARTBEAT_INTERVAL);

    logInfo(`[心跳] 已启动心跳定时器，间隔${this.HEARTBEAT_INTERVAL / 1000}秒`);
  }

  /**
   * ⭐ 停止心跳定时器
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
      logInfo('[心跳] 已停止心跳定时器');
    }
  }

  /**
   * ⭐ 发送心跳
   * 只有当播放进度有变化时才上报，避免无效请求
   */
  private async sendHeartbeat(): Promise<void> {
    // 条件检查：必须有视频信息、正在播放、有进度变化
    // ⭐ PGC（番剧/影视）bvid 为空：改判 epId，走番剧专用上报（type=4 + epid/sid + csrf）
    const isPgc: boolean = this.isPgc_ && this.epId_ > 0;
    if ((!this.vi.bvid && !isPgc) || !this.play || this.referencePlaybackCompleted || this.ct <= 0 || this.dur <= 0) return;

    // 检查进度是否有变化（至少变化5秒才上报）
    if (Math.abs(this.ct - this.lastHeartbeatTime) < 5) return;

    this.lastHeartbeatTime = this.ct;

    try {
      const watchTime = Math.floor(this.ct);
      const duration = Math.floor(this.dur);
      const cid = this.vi.cid || 0;
      const progress = Math.floor((watchTime / duration) * 100);

      // ⭐ 番剧/影视：进度必须按分集上报（type=4 + epid/sid），否则 B 站只记「看过这一集」而位置丢失
      if (isPgc) {
        logInfo(`[心跳] 上报番剧进度: epId=${this.epId_}, ${watchTime}秒/${duration}秒`);
        await this.reportPgcHeartbeat(watchTime);
        return;
      }

      logInfo(`[心跳] 上报进度: ${this.vi.bvid}, ${watchTime}秒/${duration}秒 (${progress}%)`);

      // 调用上报服务
      this.saveWatchHistory();
    } catch (err) {
      logError(`[心跳] 上报失败: ${err}`);
    }
  }

  /**
   * ⭐ 确保 PGC（番剧/影视）上报所需的上下文齐全：seasonId（季 id）+ 当前分集 aid/cid
   *
   * **为什么必须有**：B 站的 `/x/click-interface/web/heartbeat` 在 `type=4` 时**缺 sid 会静默丢弃**
   * —— 返回 `code=0`（看起来成功）但云端 `progress` 保持 0。用真机 Cookie 对拍实测：
   *   缺 sid → progress 不动；补 sid（season_id 或 media_id 均可，只要非 0）→ 立即落库。
   * 于是所有 PGC 上报前都必须先拿到 sid，否则用户看到的正是
   * "播放时位置正常、退出后官方历史变 0、再进只能定位到集"。
   *
   * 为什么容易缺：只有 `mediaId` 入口（番剧频道页/搜索/HomePage 季卡）会把 seasonId_ 直接赋值；
   * 而 `epId` 入口原先**只在 cid 缺失时**才去查季接口，走了分集接口快路就漏掉 seasonId_
   * （HomePage 番剧卡、动态页、UP空间页都只传 epId）。
   *
   * @returns true 表示 context 可用（seasonId 已知）
   */
  private async ensurePgcContext(): Promise<boolean> {
    const needSeason: boolean = this.seasonId_ <= 0;
    const needAid: boolean = (this.vd?.aid ?? 0) <= 0 && this.aidFromParams_ <= 0;
    const needCid: boolean = (this.vi.cid || 0) <= 0;
    if (!needSeason && !needAid && !needCid) return true;
    if (this.epId_ <= 0) return false;
    try {
      const info: PgcSeasonInfo | null = await getPgcSeasonInfoByEpId(this.epId_);
      if (!info) {
        logWarn(`[PGC] 季信息反查失败 (epId=${this.epId_})：seasonId 仍为 ${this.seasonId_}，进度会被 B 站丢弃`);
        return this.seasonId_ > 0;
      }
      // ⭐ 留下这份完整季信息：本方法只为 seasonId/aid 而来，但它是唯一一次季接口请求，
      //   详情卡片（vd）与评论同样需要它，缓存后调用方可以零网络复用（季接口无 API 缓存）。
      this.pgcSeasonInfoCache_ = info;
      if (this.seasonId_ <= 0 && info.seasonId > 0) {
        this.seasonId_ = info.seasonId;
        logInfo(`[PGC] 反查补全 seasonId=${this.seasonId_} (epId=${this.epId_})`);
      }
      // 定位当前分集，补齐 aid / cid（上报要求 epid 与 aid 指向同一分集）
      let matched: PgcEpisode | null = null;
      for (let i = 0; i < info.episodes.length; i++) {
        if (info.episodes[i].id === this.epId_) {
          matched = info.episodes[i];
          break;
        }
      }
      if (matched === null && info.episodes.length > 0) {
        matched = info.episodes[0];
      }
      if (matched !== null) {
        const epCid: number = matched.cid ?? 0;
        const epAid: number = matched.aid ?? 0;
        if ((this.vi.cid || 0) <= 0 && epCid > 0) {
          this.setPlaybackCid(epCid);
        }
        if (epAid > 0 && (this.vd?.aid ?? 0) <= 0 && this.aidFromParams_ <= 0) {
          this.aidFromParams_ = epAid;
          logInfo(`[PGC] 反查补全 aid=${epAid} (epId=${this.epId_})`);
        }
      }
    } catch (e) {
      logError(`[PGC] 季信息反查异常: ${errMsg(e)}`);
    }
    return this.seasonId_ > 0;
  }

  /**
   * ⭐ 上报番剧/影视（PGC）观看进度
   * 走 /x/click-interface/web/heartbeat，带 aid + cid + epid + sid + type=4 + csrf，
   * 这样历史记录里该分集的观看位置才能被记住（否则重进只能定位到"哪一集"，定位不到时间）。
   */
  private async reportPgcHeartbeat(watchTime: number): Promise<void> {
    const generation = this.referenceSwitchGeneration;
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const task = this.pgcProgressQueue.then(async () => {
      if (generation === this.referenceSwitchGeneration) await this.uploadPgcHeartbeat(watchTime, cookie);
    });
    this.pgcProgressQueue = task.catch(() => {});
    return task;
  }

  private async uploadPgcHeartbeat(watchTime: number, cookie: string): Promise<void> {
    if (!cookie) return;
    if (this.epId_ <= 0) return;
    // ⭐ 绝不上报"还没真正看过"的进度。
    //   为什么致命：B 站对同一部番剧**只保留一条历史记录**（键 kid = 心跳的 sid = season_id），
    //   这一季任何一集的心跳都会覆盖这唯一一条。切集时播放器把进度重置成 0（floor(0.4)=0），
    //   若照发就把整季记录清零 —— 实测云端会立刻变成 `ep=新集, progress=0`，
    //   连原来那集的续播点都查不回来（playurl 返回 watch_progress 回落 0）。
    //   这正是用户报的"退出播放页后官方历史变成 0、再进去只能定位到集却定位不到时间"。
    const generation = this.referenceSwitchGeneration;
    const played: number = watchTime === -1 ? -1 : Math.max(0, Math.floor(watchTime));
    if (played !== -1 && played < MIN_HEARTBEAT_PROGRESS_SEC) {
      logInfo(`[心跳] PGC 进度仅 ${played}s（<${MIN_HEARTBEAT_PROGRESS_SEC}s），跳过一次上报，`
        + `避免覆盖整季共用记录 (epId=${this.epId_})`);
      return;
    }
    // ⭐ sid 是 PGC 心跳的硬前提（缺了 B 站静默丢弃），先确保上下文齐全
    const ok: boolean = await this.ensurePgcContext();
    if (generation !== this.referenceSwitchGeneration) return;
    if (!ok) {
      logError(`[心跳] PGC 上报无法取得 seasonId (epId=${this.epId_})，本次跳过（否则进度会被静默丢弃）`);
      return;
    }
    const cid: number = this.vi.cid || 0;
    const aid: number = this.vd?.aid ?? this.aidFromParams_;
    if (aid <= 0 || cid <= 0) {
      logWarn(`[心跳] PGC 上报缺少 aid/cid (aid=${aid}, cid=${cid}, epId=${this.epId_})，跳过`);
      return;
    }
    const item = new WatchHistoryItem();
    item.aid = aid;
    item.cid = cid;
    item.bvid = this.vi.bvid;
    item.title = this.vi.title || (this.vd?.title ?? '');
    item.playProgress = played;
    item.totalDuration = Math.floor(this.dur);
    item.watchedAt = Math.floor(Date.now() / 1000);
    item.epId = this.epId_;
    item.seasonId = this.seasonId_;

    const helper = WatchHistoryHelper.getInstance();
    helper.setCookie(cookie);
    await helper.saveWatchRecord(item);
  }

  /**
   * ⭐ 用 playurl 返回的服务端续播点恢复播放位置
   *
   * 为什么需要：历史记录的 progress 只覆盖「从历史记录进入」这一条路径；从番剧页 / 推荐 / 搜索
   * 进入时路由不带进度。B 站 playurl 会**按 cid（番剧按分集）**返回该视频自己的观看位置
   * （UGC: data.last_play_time；PGC: result.play_view_business_info.user_status.watch_progress），
   * 据此恢复即可 —— 番剧/影视多集续播正是靠这一点（每集各有一份续播点，无需跨集传参）。
   *
   * 优先级：本机最新进度 > 路由进度 > 服务端续播点（取流缓存可能带旧值）。完成记录从头播放。
   */
  private applyServerResumePoint(result: PlayUrlResult): void {
    if (this.stallResumeMs_ >= 0) {
      this.initialProgress_ = this.stallResumeMs_ / 1000;
      this.stallResumeMs_ = -1;
      return;
    }
    if (this.continuationRestore_) return;
    if (this.referenceFeedPreparingMain) return;
    const local = PlaybackProgress.read(AppStorage.get<string>('playbackProgressV1') || '[]', this.playbackProgressKey());
    if (local) {
      this.initialProgress_ = local.completed ? 0 : local.position;
      logInfo(`[PlaybackProgress] restore cid=${this.vi.cid} position=${this.initialProgress_} completed=${local.completed}`);
      return;
    }
    if (this.initialProgress_ > 0) return;   // 路由已带进度，尊重它
    const ms: number = result.lastPlayTimeMs ?? 0;
    if (ms <= 0) return;
    const sec: number = ms / 1000;
    if (this.dur > 0 && sec >= this.dur - 3) {
      logInfo(`[VideoPlayer] 服务端续播点 ${sec}s 已到片尾，忽略`);
      return;
    }
    this.initialProgress_ = sec;
    logInfo(`[VideoPlayer] 服务端续播点恢复播放位置: ${sec}s (pgc=${this.isPgc_}, epId=${this.epId_})`);
  }

  /**
   * @param force 关键节点（退出页面 / 播完 / 连刷换片）必须绕过节流，其余路径默认节流。
   *   连续快进快退时 seekDone、seek 收尾、状态回调会在同一秒内各调一次，
   *   串行 HTTP 队列（WatchHistoryHelper.progressQueue）会被灌满 —— 实测 5 次拖动
   *   连发 5+ 个「上报观看进度」，是拖动后半段发涩、松手后延迟的来源之一。
   */
  private saveWatchHistory(force: boolean = false): void {
    if (((this.sk_ || this.sg_ || this.seekProgressPending) && !this.referencePlaybackCompleted) || this.restoringProgress || this.initialProgress_ > 0 || this.referenceFeedPreparingMain) return;
    this.saveLocalPlaybackProgress();
    // ⭐ 放开 PGC（番剧 bvid 为空但 epId 有效）：投稿靠 bvid，PGC 靠 epId
    //   ⚠️ 阈值必须是 MIN_HEARTBEAT_PROGRESS_SEC 而不是 `> 0`：打开页面就退出时 ct≈0.4，
    //   `ct <= 0` 拦不住，floor 后变成 played_time=0 会把该视频/该季原有进度抹掉
    if ((!this.vi.bvid && !(this.isPgc_ && this.epId_ > 0)) || this.ct < MIN_HEARTBEAT_PROGRESS_SEC) return;
    // ⭐ 云端心跳节流（本地进度不受影响，上面已经写过）
    const nowPush = Date.now();
    if (!force && nowPush - this.lastHistoryPushAt_ < 3000) return;
    this.lastHistoryPushAt_ = nowPush;

    // 获取Cookie
    const cookie = AppStorage.get<string>('biliCookie') || '';
    if (!cookie) {
      logWarn('[saveWatchHistory] 用户未登录，无法保存观看历史');
      return;
    }

    // ⭐ PGC（番剧/影视）：统一交给 reportPgcHeartbeat —— 它会先确保 seasonId 已解析。
    //   缺 sid 的 type=4 心跳会被 B 站**静默丢弃**（返回 code=0 但云端 progress 不变），
    //   这正是"播放时正常、退出后官方历史变 0"的原因，所以这里绝不能少 sid 就发。
    if (this.isPgc_ && this.epId_ > 0) {
      this.reportPgcHeartbeat(this.referencePlaybackCompleted ? -1 : Math.floor(this.ct))
        .catch((e: Error) => logError(`[saveWatchHistory] PGC 进度上报异常: ${e.message}`));
      return;
    }

    // 获取aid（从VideoDetail中获取，或从bvid转换）
    // 注意：B站API需要aid而不是bvid
    // ⭐ 合集切集途中 vd 还是上一条视频的 aid，必须用切集时记下的 aid
    let aid = this.detailIsCurrentVideo() ? (this.vd?.aid || 0) : (this.aidFromParams_ || 0);
    if (!aid && this.vi.bvid) {
      // 如果没有aid，尝试从bvid转换（简化处理，实际应该调用API转换）
      logWarn('[saveWatchHistory] 缺少aid，无法上报到B站');
      return;
    }

    const item = new WatchHistoryItem();
    item.aid = aid;
    item.cid = this.vi.cid || 0;
    item.bvid = this.vi.bvid;
    item.title = this.vi.title || (this.vd?.title ?? '');
    item.coverUrl = this.vi.cover || '';
    item.playProgress = this.referencePlaybackCompleted ? -1 : Math.floor(this.ct);
    item.totalDuration = this.dur;
    item.watchedAt = Math.floor(Date.now() / 1000); // B站使用秒级时间戳
    item.ownerName = this.vd?.owner?.name ?? '';
    // ⭐ PGC（番剧）历史记录：保存 epId/seasonId，恢复播放时走 PGC 路径（bvid 为空）
    item.epId = this.epId_;
    item.seasonId = this.seasonId_;

    // 设置Cookie并保存
    const helper = WatchHistoryHelper.getInstance();
    helper.setCookie(cookie);
    helper.saveWatchRecord(item);
  }

  private playbackProgressKey(): string {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const account = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/);
    return PlaybackProgress.key(account ? account[1] : '', this.vi.bvid, this.vi.cid || 0, this.epId_);
  }

  private saveLocalPlaybackProgress(): void {
    if (this.seekProgressPending && !this.referencePlaybackCompleted) return;
    if (this.referenceFeedPreparingMain || this.restoringProgress || this.initialProgress_ > 0 || (this.sk_ && !this.referencePlaybackCompleted) || this.dur <= 0 || !this.vi.cid) return;
    if (!this.av || (this.av.state !== 'playing' && this.av.state !== 'paused' && this.av.state !== 'completed')) return;
    const position = this.referencePlaybackCompleted ? this.dur : this.ct;
    if (!Number.isFinite(position) || position < 0) return;
    const raw = AppStorage.get<string>('playbackProgressV1') || '[]';
    AppStorage.set('playbackProgressV1', PlaybackProgress.write(raw, {
      key: this.playbackProgressKey(), position: position, duration: this.dur,
      completed: this.referencePlaybackCompleted, updatedAt: Date.now()
    }));
  }

  /**
   * ⭐ 上报观看行为到B站推荐系统
   * 这是实现个性化推荐的关键！
   */
  private async reportWatchBehavior(): Promise<void> {
    // Progress is uploaded by saveWatchHistory; recommendation tracking must not
    // send a second heartbeat that can overwrite the final position.
    if (!this.isPgc_ && this.vi.bvid && this.ct >= MIN_HEARTBEAT_PROGRESS_SEC) {
      UserBehaviorService.addWatchedVideo(this.vi.bvid);
    }
  }

  // ⭐★ 提示弹层**转交**过来的返回（2026-09-24 真机实证，修"侧滑返回被吃掉"）：
  //   四个提示（seek / 音量 / 亮度 / 长按加速）走 bindPopup 弹层，而弹层默认挂在
  //   **应用窗口根节点层** ⇒ 它属于 OverlayManager 的返回键路由，会把返回键 / 系统侧滑返回
  //   **吃掉**（hilog：`OnBackPressed called` → `Overlay consumed backpressed event`；
  //   这正是官方架构指南《侧滑无法关闭弹窗》给的判据）。此时本页 `onBackPress()`
  //   **根本不会被调用** ⇒ 该退全屏的没退、该返回的没返回，要按两次返回。
  //   ⚠️ 只把弹层 `onWillDismiss` 设成 `false` 没用：那只能挡住"弹层自己关"，
  //      挡不住事件进 Overlay 路由（实测 hide popup 改由我们自己的 800ms 定时器收，
  //      但 `Overlay consumed backpressed event` 照旧）。
  //   ✅ 现在四个弹层用 `onWillDismiss` 的**函数形式**，官方文档保证侧滑/返回键/路由跳转/Esc
  //      都会以 `reason === DismissReason.PRESS_BACK` 回调进来，回调里调这里把返回转交页面。
  private ovBackTs_: number = 0;
  /**
   * ⭐ 输入弹层的表情面板控制器（见 CommentInputBarCtrl）：
   *    表情面板展开时，侧滑返回/返回键应**先收起面板**，而不是把整个输入弹层关掉。
   *    两个弹层各自一份（评论/回复 与 发弹幕 的输入栏是两个独立实例）。
   */
  private cmSheetEmoteCtrl: CommentInputBarCtrl = new CommentInputBarCtrl();
  private dmSheetEmoteCtrl: CommentInputBarCtrl = new CommentInputBarCtrl();
  private closePlaybackOptionPanel(): boolean {
    if (!this.qp && !this.rp && !this.sp) return false;
    this.qp = false;
    this.rp = false;
    this.sp = false;
    this.ip = false;
    this.cv = true;
    this.resetCT();
    return true;
  }

  private onOverlayBack_(): void {
    if (this.lk) { this.toggleLock(); return; }
    if (this.commentSheetVisible) {
      this.backCommentComposer();
      return;
    }
    if (this.showDanmakuSheet) {
      if (!this.dmSheetEmoteCtrl.collapseEmote()) this.showDanmakuSheet = false;
      return;
    }
    if (this.closePlaybackOptionPanel()) return;
    if (this.commentThread) { this.closeCommentThread(); return; }
    if (this.isLightsOff) { this.turnLightsOn(); return; }
    if (this.fs) { this.toggleFS(); return; }
    // ⚠️ 防重入：官方文档把"路由跳转"也算作 PRESS_BACK 的触发源 ⇒ 我们主动 router.back()
    //   有可能再打回同一个回调（双重返回）；800ms 内的重复调用一律丢弃。
    //   用户的"第二次滑动"此时页面早已退出，不会被误吞。
    const now: number = Date.now();
    if (now - this.ovBackTs_ < 800) return;
    this.ovBackTs_ = now;
    this.goBack();
  }

  onBackPress(): boolean {
    // 锁定时先解锁并消费本次返回，保留当前播放布局。
    if (this.lk) { this.toggleLock(); return true; }
    if (this.commentSheetVisible) {
      this.backCommentComposer();
      return true;
    }
    if (this.floatingMorph) return true;
    if (this.showDanmakuSheet) {
      if (!this.dmSheetEmoteCtrl.collapseEmote()) this.showDanmakuSheet = false;
      return true;
    }
    if (this.referenceSubtitlePanelOpen) {
      this.closeLandscapeSubtitlePanel();
      return true;
    }
    if (this.referenceLandscapeDanmakuOpen) {
      this.referenceLandscapeDanmakuOpen = false;
      this.ip = false;
      this.cv = true;
      this.resetCT();
      this.saveDanmakuDisplaySettings();
      return true;
    }
    if (this.closePlaybackOptionPanel()) return true;
    if (this.mp) { this.referenceClosePortraitSettings(); return true; }
    if (this.commentThread) { this.closeCommentThread(); return true; }
    if (this.referenceFeedComments) { this.referenceSetFeedComments(false); return true; }
    if (this.referenceFeed && !this.fs) { this.referenceSetFeed(false); return true; }
    // ⭐ 关灯模式下，返回（含侧滑返回）改为开灯，不退出页面
    if (this.isLightsOff) {
      this.turnLightsOn();
      return true;
    }
    // 如果是全屏模式，退出全屏
    if (this.fs) {
      this.toggleFS();
      return true;
    }
    return false;
  }

  /** ⭐ 开灯：恢复背景与视频尺寸（关灯模式下通过返回/侧滑触发） */
  private turnLightsOn(): void {
    // ⭐ 与 toggleFS 同理：页面不发生跳转但要重新显示背景/视频 ⇒ 提示收掉，
    //   且与开灯动画同帧启动（不要在触摸被取消那一刻提前收，见 onTC）
    this.clearGestureHint_();
    this.clearLightBtnTimer();
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.Ease }, () => {
      this.isLightsOff = false;
      this.loBgScale = 1;
      this.loBgBlur = 0;
      this.loBgDim = 0;
    });
    // ⭐ 开灯：恢复状态栏（竖屏恢复，横屏仍隐藏）
    setTimeout(() => { this.manageSB(true); }, 50);
  }

  private async restoreS() {
    // ⭐ 存活计数先减自己：还有别的播放页活着（相关推荐 push 出的下层实例）就不能恢复
    //    主题口径——下层实例的 onPageShow 已设白字，这次恢复若后到会让浅色模式下层播放页
    //    闪黑；改为主动回写白字，保证最后一个写窗口的是白。
    const remaining = Math.max(0, (AppStorage.get<number>('immersivePlayerAliveCount') ?? 1) - 1);
    AppStorage.setOrCreate('immersivePlayerAliveCount', remaining);
    if (!this.mw) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (remaining > 0) {
        await StatusBarUtils.setPlayerStatusBarContent(context, this.mw);
      } else {
        // ⭐ 回到普通页面恢复主题口径的状态栏内容色（浅色黑字/深色白字），首页等普通页面靠它。
        //    播放页期间强制白字压视频，不恢复会让浅色模式下的普通页面也变成看不见的白字。
        await StatusBarUtils.restoreThemeStatusBarContent(context, this.mw);
      }
      // 退出后由全局偏好决定显隐，不能用播放页尚未恢复的横屏尺寸覆盖首页。
      const hideStatusBar = AppStorage.get<boolean>('hideStatusBar') ?? false;
      await StatusBarUtils.setSystemBars(this.mw, !hideStatusBar, true);
      // 恢复用户在个性化设置中的屏幕方向锁定
      const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
      let orientation: window.Orientation;
      switch (lock) {
        case '跟随系统':
          orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
          break;
        case '锁定竖屏':
          orientation = window.Orientation.PORTRAIT;
          break;
        case '锁定横屏':
          // 允许横屏之间旋转
          orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
          break;
        default:
          orientation = window.Orientation.AUTO_ROTATION;
          break;
      }
      await this.mw.setPreferredOrientation(orientation);
    } catch (e) { }
  }

  private async loadSM() {
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      this.sm = await pf.get('sm', 'auto') as string;
      const feedScale = await pf.get('feedPortraitScaleMode', 'fill') as string;
      this.referenceFeedPortraitScaleMode = feedScale === 'auto' ? 'auto' : 'fill';
      const feedScope = await pf.get('feedPortraitScaleScope', 'standard') as string;
      this.referenceFeedPortraitScaleScope = feedScope === 'all' ? 'all' : 'standard';
    } catch (e) { }
  }

  private async saveSM() {
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      await pf.put('sm', this.sm);
      await pf.flush();
    } catch (e) { }
  }

  private async saveFeedPortraitScaleMode(): Promise<void> {
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      await pf.put('feedPortraitScaleMode', this.referenceFeedPortraitScaleMode);
      await pf.put('feedPortraitScaleScope', this.referenceFeedPortraitScaleScope);
      await pf.flush();
    } catch (e) { }
  }

  private loadInitialVideoInteractions(detail: VideoDetail, bvid: string, generation: number, revision: number): void {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const current = (): boolean => this.referenceAlive && this.vi.bvid === bvid &&
      this.referenceSwitchGeneration === generation && this.interactionRevision === revision &&
      cookie === (AppStorage.get<string>('biliCookie') || '');
    if (!current()) return;
    // 互不依赖的请求同时发起，每一路失败均不阻断其它内容。
    if (detail.owner.mid) {
      getFollowStatus(detail.owner.mid).then((followed: boolean) => {
        if (current()) this.isFollowed = followed;
      }).catch((error: Error) => { logWarn('[VideoPlayer] 关注状态加载失败', error); });
    }
    if (detail.req_user && detail.req_user.dislike !== undefined) {
      this.isLiked = !!detail.req_user.like;
      this.isDisliked = !!detail.req_user.dislike;
      this.isCoined = (detail.req_user.coin || 0) > 0;
      this.isFavorited = !!detail.req_user.favorite;
    } else {
      getVideoUserStatus(bvid, detail.aid).then((status) => {
        if (!current() || !status) return;
        this.isLiked = status.like;
        this.isDisliked = status.dislike || false;
        this.isCoined = status.coin > 0;
        this.isFavorited = status.favorite;
      }).catch((error: Error) => { logWarn('[VideoPlayer] 互动状态加载失败', error); });
    }
  }

  private async loadD(preloadedDetail?: VideoDetail) {
    logInfo('[VPP] loadD 开始');
    const requestedBvid = this.vi.bvid;
    const requestedGeneration = this.referenceSwitchGeneration;
    const interactionRevision = this.interactionRevision;
    const requestedCookie = AppStorage.get<string>('biliCookie') || '';
    // ⭐ PGC（番剧）不在此加载详情：vd.pages（分集列表）由 PGC 分支按季接口填充，
    //   若 bvid 非空（历史记录 PGC 场景）仍走 UGC 详情会覆盖 vd.pages → 选集按钮消失
    if (!this.vi.bvid || this.isPgc_) {
      logInfo('[VPP] loadD 跳过（PGC 或无 bvid）');
      return;
    }
    // 重置评论相关状态（切换视频时清除旧状态）
    this.commentThread = null;
    this.commentDialog = null;
    this.expandedCommentIds.clear();
    this.savedScrollOffsetMap.clear();
    this.replyPageMap.clear();
    this.hasMoreRepliesMap.clear();
    this.loadingRepliesMap.clear();
    this.repliesVersion = 0;
    this.commentCursor = 0;
    this.commentDataSource.clear();
    this.ldd = true;
    this.floatBtnOpacity = 0;
    this.floatBtnScale = 0;
    this.floatBtnOffsetY = 12;
    try {
      const d = preloadedDetail ?? await getVideoDetail(requestedBvid);
      if (!this.referenceAlive || this.vi.bvid !== requestedBvid || this.referenceSwitchGeneration !== requestedGeneration ||
        requestedCookie !== (AppStorage.get<string>('biliCookie') || '')) return;
      if (d) {
        this.vd = d;
        this.vdBvid_ = d.bvid || '';
        if (this.referenceLayout && !this.referenceFeed && !this.isPgc_) this.loadReferenceIntroExtras();
        this.applyDetailDimension(d);
        // ⭐ 预解码 up 主头像
        this.predecodeKeyImages();
        if (!this.vi.title && d.title) this.vi.title = d.title;
        if (!this.vi.cover && d.pic) this.vi.cover = d.pic;
        const detailCid = d.cid || d.pages?.[0]?.cid || 0;
        if (!this.vi.cid && detailCid > 0) {
          this.setPlaybackCid(detailCid);
          // 只有在播放器未初始化且未在初始化中时才调用initP
          if (!this.av && !this.initPInProgress_) this.initP();
        }
        // ⭐ 根据当前cid确定分P索引
        if (d.pages && d.pages.length > 0) {
          const idx = d.pages.findIndex(p => p.cid === this.vi.cid);
          this.currentPageIndex = idx >= 0 ? idx : 0;
        }

        // ⭐ 初始化互动状态
        if (interactionRevision === this.interactionRevision) {
          this.likeCount = d.stat.like;
          this.coinCount = d.stat.coin;
          this.favoriteCount = d.stat.favorite;
        }

        // 状态查询独立完成，不阻塞评论、推荐和详情加载态。
        this.loadInitialVideoInteractions(d, requestedBvid, requestedGeneration, interactionRevision);

        // ⭐ 延迟加载评论区：等页面入场动画完成后才加载
        this.pendingCommentAid = d.aid;
        if (this.commentsInitialized) {
          this.pendingCommentAid = 0;
          this.loadC(d.aid);
        }

        // ⭐ 加载相关视频
        this.fetchRelatedVideos(d.bvid);
      }
    } catch (e) { }
    finally {
      if (this.vi.bvid === requestedBvid && this.referenceSwitchGeneration === requestedGeneration) this.ldd = false;
      logInfo('[VPP] loadD 完成');
    }
  }

  private scheduleFloatBtnFadeIn(): void {
    this.floatBtnOpacity = 0;
    this.floatBtnScale = 0;
    this.floatBtnOffsetY = 12;
    setTimeout(() => {
      if (!this.ldd) {
        this.floatBtnOpacity = 1;
        this.floatBtnScale = 1;
        this.floatBtnOffsetY = 0;
      }
    }, 500);
  }

  private async fetchRelatedVideos(bvid: string): Promise<void> {
    this.relatedLoading = true;
    try {
      const videos = await getRelatedVideos(bvid);
      if (this.vi.bvid !== bvid) return;
      this.relatedVideos = videos;
      this.referencePrefetchPlaylistUrls();
      this.relatedRenderCount = 10;  // ⭐ 新视频重置限量渲染
    } catch (e) {
      logError(`[RelatedVideos] 获取相关视频失败: ${e}`);
      this.relatedVideos = [];
      this.relatedRenderCount = 10;
    } finally {
      this.relatedLoading = false;
    }
  }

  private onRelatedVideoClick(item: RecommendItem): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: item.id,
        aid: item.aid,
        cid: item.cid,
        title: item.title,
        ownerName: item.ownerName,
        duration: item.duration,
        pubdate: item.pubdate,
        view: item.playCount,
        coverUrl: item.coverUrl,
        landscapePlayerRatio: this.referenceLandscapePlayerRatio
      }
    }).catch((err: Error) => { logError(`跳转相关视频失败: ${err.message}`); });
  }

  private async loadC(aid: number) {
    const generation = this.referenceSwitchGeneration;
    const cursor = this.commentCursor;
    const sort = this.commentSort;
    const key = `${generation}:${aid}:${cursor}:${sort}`;
    if (this.ldc && this.commentRequestKey === key) return;
    this.commentRequestKey = key;
    const request = ++this.commentRequestSequence;
    this.commentRenderCount = 20;  // ⭐ 新视频重置评论区限量渲染
    this.ldc = true;
    this.rateLimited = false;
    try {
      // 映射排序模式：commentSort=2(最热)→mode=3, commentSort=1(最新)→mode=2
      const mode: number = this.commentSort === 2 ? 3 : 2;
      logInfo(`[loadC] 开始加载评论: aid=${aid}, cursor=${this.commentCursor}, mode=${mode}`);
      const result = await getVideoComments(aid, cursor, 20, mode);
      if (request !== this.commentRequestSequence || generation !== this.referenceSwitchGeneration || this.vd?.aid !== aid) return;
      logInfo(`[loadC] 评论加载结果: ${result ? (result.comments ? result.comments.length : 0) : 0}条`);
      if (result === null) {
        // 被限流，保留 hm 为 true 以便用户重试
        logWarn('[loadC] API限流，标记限流状态');
        this.rateLimited = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '评论被限流，请等待片刻后重试', duration: 2000 });
        } catch (err) {
          logWarn(`showToast 异常: ${errMsg(err)}`);
        }
      } else if (result.comments && result.comments.length > 0) {
        // 转换为 ObservableComment
        const observableComments = result.comments.map(item => ObservableComment.from(item));

        if (cursor === 0) {
          this.commentDataSource.setComments(observableComments);
        } else {
          this.commentDataSource.appendComments(observableComments);
        }

        this.commentCursor = result.nextCursor;
        this.hm = !result.isEnd;
        // ⭐ 从消息通知跳转时，滚动到指定评论
        if (this.commentRootId_ > 0) {
          this.scrollToTargetComment();
        }
        // ⭐ 逐个预解码评论头像（间隔 50ms），避免 30 张并发 CPU 软解导致的掉帧
        // 旋转期间跳过（rotationInProgress=true），避免与窗口旋转抢解码资源
        if (!this.rotationInProgress) {
          for (const c of observableComments) {
            if (c.member?.avatar) {
              predecodeImage(imageUrlResize(c.member.avatar, 48));
            }
            await new Promise<void>(r => setTimeout(r, 50));
          }
        }
      } else {
        this.hm = false;
        // 如果是第一页且没有评论，可能是Cookie失效或API错误
        if (this.commentCursor === 0) {
          logWarn('[loadC] 第一页评论为空，可能Cookie失效或API限流');
        }
      }
    } catch (e) {
      if (request !== this.commentRequestSequence || generation !== this.referenceSwitchGeneration || this.vd?.aid !== aid) return;
      logError(`[loadC] 加载评论异常: ${e}`);
      // 加载失败时，如果是第一页，提示用户
      if (this.commentCursor === 0) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '评论加载失败，请检查网络或重新登录', duration: 2000 });
        } catch (err) {
          logWarn(`showToast 异常: ${errMsg(err)}`);
        }
      }
    }
    finally {
      if (request === this.commentRequestSequence && generation === this.referenceSwitchGeneration) this.ldc = false;
    }
  }

  private async scrollToTargetComment(): Promise<void> {
    if (this.commentRootId_ <= 0) return;
    // 先在当前已加载的评论中查找
    let index = this.commentDataSource.findCommentIndexByRoot(this.commentRootId_);
    if (index < 0 && this.commentSecondaryId_ > 0) {
      index = this.commentDataSource.findCommentIndex(this.commentSecondaryId_);
    }
    if (index >= 0) {
      logInfo(`[scrollToTargetComment] 在当前页找到评论 rootId=${this.commentRootId_}, index=${index}`);
      this.commentScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
      this.commentRootId_ = 0;
      this.commentSecondaryId_ = 0;
      return;
    }
    // 当前页未找到，切换到"最新"排序重新加载评论（消息通知中的回复通常在最新排序的前几页）
    if (this.vd && this.vd.aid && this.commentSort !== 1) {
      logInfo(`[scrollToTargetComment] 当前页未找到，切换到最新排序重新加载 rootId=${this.commentRootId_}`);
      this.commentSort = 1;  // 1 = 最新排序
      this.commentCursor = 0;
      this.commentDataSource.clear();
      await this.loadC(this.vd.aid);
      // 加载完后再查找
      index = this.commentDataSource.findCommentIndexByRoot(this.commentRootId_);
      if (index < 0 && this.commentSecondaryId_ > 0) {
        index = this.commentDataSource.findCommentIndex(this.commentSecondaryId_);
      }
      if (index >= 0) {
        logInfo(`[scrollToTargetComment] 最新排序找到评论 index=${index}`);
        this.commentScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
        this.commentRootId_ = 0;
        this.commentSecondaryId_ = 0;
        return;
      }
      // 最新排序第一页也没找到，继续加载更多页
      for (let page = 0; page < 5; page++) {
        if (!this.hm || this.ldc) break;
        await this.loadMC();
        index = this.commentDataSource.findCommentIndexByRoot(this.commentRootId_);
        if (index < 0 && this.commentSecondaryId_ > 0) {
          index = this.commentDataSource.findCommentIndex(this.commentSecondaryId_);
        }
        if (index >= 0) {
          logInfo(`[scrollToTargetComment] 最新排序第${page + 2}页找到评论 index=${index}`);
          this.commentScroller.scrollToIndex(index, false, ScrollAlign.CENTER);
          this.commentRootId_ = 0;
          this.commentSecondaryId_ = 0;
          return;
        }
      }
    }
    logInfo(`[scrollToTargetComment] 未能定位评论 rootId=${this.commentRootId_}, secId=${this.commentSecondaryId_}`);
  }

  private async loadMC() {
    if (!this.hm || this.ldc || !this.vd || this.isLoadingMore) return;
    const generation = this.referenceSwitchGeneration;
    const requestedAid = this.vd.aid;
    this.isLoadingMore = true;
    // 映射排序模式
    const mode: number = this.commentSort === 2 ? 3 : 2;
    try {
      logInfo(`[loadMC] 加载更多评论: aid=${this.vd.aid}, cursor=${this.commentCursor}, mode=${mode}`);
      const result = await getVideoComments(requestedAid, this.commentCursor, 20, mode);
      if (generation !== this.referenceSwitchGeneration || this.vd?.aid !== requestedAid) return;
      logInfo(`[loadMC] 更多评论结果: ${result ? (result.comments ? result.comments.length : 0) : 0}条`);
      if (result === null) {
        // 限流，hm 保持不变，下次可继续重试
        logWarn('[loadMC] 被限流');
        this.rateLimited = true;
        try {
          this.getUIContext().getPromptAction().showToast({ message: '加载更多评论被限流，请稍后重试', duration: 1500 });
        } catch (err) {
          logWarn(`showToast 异常: ${errMsg(err)}`);
        }
      } else if (result.comments && result.comments.length > 0) {
        // 转换为 ObservableComment 并追加
        const observableComments = result.comments.map(item => ObservableComment.from(item));
        this.commentDataSource.appendComments(observableComments);
        this.commentRenderCount += observableComments.length;  // 上拉加载更多后同步放开渲染配额，新评论立即进入 ForEach 渲染范围
        this.commentCursor = result.nextCursor;
        this.hm = !result.isEnd;
        this.rateLimited = false;
      } else {
        this.hm = false;
      }
    } catch (e) {
      logError(`[loadMC] 加载更多评论异常: ${e}`);
    } finally {
      if (generation === this.referenceSwitchGeneration) this.isLoadingMore = false;
    }
  }

  // ⭐ 切换评论排序（最热/最新），带 300ms 防抖防止快速点击触发限流
  private switchCommentSort(sort: number) {
    if (sort === this.commentSort) return;
    if (this.sortChangeTimer !== undefined) {
      clearTimeout(this.sortChangeTimer);
    }
    this.sortChangeTimer = setTimeout(() => {
      this.sortChangeTimer = undefined;
      this._doSwitchCommentSort(sort);
    }, 300);
  }

  private _doSwitchCommentSort(sort: number) {
    logInfo(`[switchCommentSort] 排序切换: ${this.commentSort} → ${sort}`);
    this.commentSort = sort;
    this.commentCursor = 0;
    this.commentThread = null;
    this.commentDialog = null;
    this.expandedCommentIds.clear();
    this.savedScrollOffsetMap.clear();
    this.repliesVersion++;
    this.sortBarVersion++;
    this.commentDataSource.clear();
    if (this.vd) {
      this.loadC(this.vd.aid);
    }
  }

  /** ⭐ 评论区限量渲染：只返回前 commentRenderCount 条（与相关推荐同款思路，负载与总长解耦） */
  private commentSlice(): ObservableComment[] {
    const total = this.commentDataSource.totalCount();
    const n = Math.min(this.commentRenderCount, total);
    const out: ObservableComment[] = [];
    for (let i = 0; i < n; i++) {
      out.push(this.commentDataSource.getData(i));
    }
    return out;
  }

  // ⭐ 展开评论 — 只加载第一页回复，后续通过"展开更多回复"按钮分页加载
  // 避免一次性循环加载所有页导致被 B站 API 限流
  private openCommentThread(comment: ObservableComment): void {
    if (!this.referenceLayout) {
      this.expandCommentAndLoadFirstPage(comment);
      return;
    }
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 280, curve: Curve.EaseOut }, () => {
      this.commentDialog = null;
      this.commentThread = comment;
    });
  }

  private closeCommentThread(): void {
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 280, curve: Curve.EaseOut }, () => {
      if (this.commentDialog) this.commentDialog = null;
      else this.commentThread = null;
    });
  }

  @Builder
  commentThreadView() {
    if (this.commentThread) {
      Stack({ alignContent: Alignment.TopStart }) {
        CommentThreadPanel({ comment: this.commentThread, videoDetail: this.vd,
          bottomInset: this.isLs || this.fs ? 0 : this.navIndicatorHeight,
          refreshVersion: this.commentThreadRefresh,
          onClose: () => { this.closeCommentThread(); },
          onViewConversation: (reply: ObservableComment) => {
            this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 280, curve: Curve.EaseOut }, () => { this.commentDialog = reply; });
          },
          onReply: (root: number, parent: number, name: string) => {
            this.openCommentSheet('reply', root, parent, name);
          } })
          .hitTestBehavior(this.commentDialog ? HitTestMode.None : HitTestMode.Default)
        if (this.commentDialog) {
          CommentConversationPanel({ root: this.commentThread, selected: this.commentDialog, videoDetail: this.vd,
            bottomInset: this.isLs || this.fs ? 0 : this.navIndicatorHeight,
            refreshVersion: this.commentThreadRefresh,
            onClose: () => { this.closeCommentThread(); },
            onReply: (root: number, parent: number, name: string) => {
              this.openCommentSheet('reply', root, parent, name);
            } })
            .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 280, curve: Curve.EaseOut }))
        }
      }.width('100%').height('100%')
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 280, curve: Curve.EaseOut }))
    }
  }

  private async expandCommentAndLoadFirstPage(comment: ObservableComment) {
    logInfo('[expandComment] 开始执行（仅加载第一页）');
    const rpid = comment.rpid;

    // ⭐ 记录当前滚动位置到该评论的专属位置映射中
    try {
      const offset = this.commentScroller.currentOffset();
      this.savedScrollOffsetMap.set(rpid, offset?.yOffset ?? 0);
    } catch (e) {
      this.savedScrollOffsetMap.set(rpid, 0);
    }
    logInfo(`[expandComment] 记录评论 ${rpid} 的展开前位置: ${this.savedScrollOffsetMap.get(rpid)}`);

    const existingReplies = comment.replies || [];
    const rcount = comment.rcount || 0;

    // 如果总回复数 <= 现有回复数，不需要加载，直接展开
    if (rcount <= existingReplies.length) {
      logInfo('[expandComment] 无需加载更多');
      comment.hasMoreReplies = false;
      this._addToExpanded(rpid);
      return;
    }

    // 检查是否正在加载
    if (comment.loadingReplies || !this.vd) return;

    comment.loadingReplies = true;
    try {
      // ⭐ 只加载第一页，不再循环加载全部
      logInfo('[expandComment] 加载第1页回复');
      const replies = await getCommentReplies(this.vd.aid, rpid, 1, 20);
      logInfo(`[expandComment] 第1页返回${replies ? replies.length : 0}条`);

      if (replies && replies.length > 0) {
        const commentIndex = this.commentDataSource.findCommentIndex(rpid);
        if (commentIndex !== -1) {
          const oldComment = this.commentDataSource.getData(commentIndex);
          oldComment.updateReplies(replies);
          oldComment.replyPage = 1;
          // ⭐ 如果还有更多页，标记 hasMoreReplies=true，让"展开更多回复"按钮出现
          oldComment.hasMoreReplies = replies.length >= 20 && rcount > replies.length;

          this.commentDataSource.notifyDataChange(commentIndex);
          this._addToExpanded(rpid);
        }
      } else {
        comment.hasMoreReplies = false;
      }
    } catch (err) {
      logError(`[expandComment] 加载失败: ${err}`);
      comment.hasMoreReplies = false;
    } finally {
      comment.loadingReplies = false;
    }
  }

  // ⭐ 将评论ID加入展开集合
  private _addToExpanded(rpid: number): void {
    const newSet = new Set<number>(this.expandedCommentIds);
    newSet.add(rpid);
    this.expandedCommentIds = newSet;
    this.repliesVersion++;
  }

  // ⭐ 统一的收起评论逻辑：从展开集合中移除，并恢复该评论展开前记录的滚动位置
  private _doRemoveExpandedComment(rpid: number): void {
    if (!this.expandedCommentIds.has(rpid)) return;
    logInfo(`[_doRemoveExpandedComment] 收起评论 ${rpid}`);
    // 恢复该评论展开时记录的位置
    const savedOffset = this.savedScrollOffsetMap.get(rpid);
    if (savedOffset !== undefined) {
      try {
        this.commentScroller.scrollTo({ xOffset: 0, yOffset: savedOffset, animation: { duration: 300 } });
      } catch (e) {
        this.commentScroller.scrollBy(0, savedOffset);
      }
    }
    this.savedScrollOffsetMap.delete(rpid);
    const newSet = new Set<number>(this.expandedCommentIds);
    newSet.delete(rpid);
    this.expandedCommentIds = newSet;
    this.repliesVersion++;
  }

  // 加载更多回复
  private async loadMoreReplies(comment: ObservableComment) {
    logInfo('[loadMoreReplies] 开始执行');
    if (!this.vd) {
      logWarn('[loadMoreReplies] vd为空');
      return;
    }
    const rpid = comment.rpid;
    logInfo(`[loadMoreReplies] rpid=${rpid}`);

    // 检查是否正在加载
    if (comment.loadingReplies) {
      logInfo('[loadMoreReplies] 正在加载中');
      return;
    }

    // 获取当前页码
    let page = comment.replyPage || 0;

    // 如果是第一次加载（page=0），加载第1页
    // 否则加载下一页
    if (page === 0) {
      page = 1;
    } else {
      page++;
    }

    logInfo(`[loadMoreReplies] 加载第${page}页`);

    // 设置加载状态
    comment.loadingReplies = true;

    try {
      logInfo(`[loadMoreReplies] 调用API: aid=${this.vd.aid}, rpid=${rpid}, page=${page}`);
      const replies = await getCommentReplies(this.vd.aid, rpid, page, 20);
      logInfo(`[loadMoreReplies] API返回${replies ? replies.length : 0}条`);

      if (replies && replies.length > 0) {
        // 找到对应评论并追加回复
        const commentIndex = this.commentDataSource.findCommentIndex(rpid);
        logInfo(`[loadMoreReplies] 评论索引=${commentIndex}`);
        if (commentIndex !== -1) {
          const oldComment = this.commentDataSource.getData(commentIndex);

          // 合并新旧回复并更新
          const existingReplyIds = new Set(oldComment.replies.map(r => r.rpid));
          const newRepliesToAdd = replies.filter(r => !existingReplyIds.has(r.rpid));
          const allReplies = [...oldComment.replies.map(r => r.toCommentItem()), ...newRepliesToAdd];
          oldComment.updateReplies(allReplies);
          oldComment.replyPage = page;
          oldComment.hasMoreReplies = replies.length >= 20;

          // 通知数据变化
          this.commentDataSource.notifyDataChange(commentIndex);
          this.repliesVersion++;
        }
      } else {
        comment.hasMoreReplies = false;
      }
    } catch (e) {
      logError('加载回复失败:', e);
    } finally {
      comment.loadingReplies = false;
    }
  }

  switchTab = (i: number) => {
    // 如果正在滑动手势中，切换到新的tab时需要重置手势状态
    if (this.isSwiping) {
      this.isSwiping = false;
      this.swipeProgress = 0;
    }
    // 先更新tabSelIdx — SegmentButton用自己的内置动画驱动指示器过渡
    // 不要放入animateTo，否则组件会跳过内置动画导致指示器跳变
    this.tabSelIdx = [i];
    this.getUIContext()?.animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 350, curve: Curve.FastOutSlowIn }, () => {
      this.at = i;
    });
    // 切换到非评论tab时，动画恢复视频大小
    if (i !== 1 && this.vidShrink > 0) {
      this.animateVidShrink(0);
    }
  }

  // 详情卡片水平偏移量（百分比）
  getDetailOffset = (): string => {
    if (this.isSwiping) {
      // 跟随手指：at=0时从0%→-100%，at=1时从-100%→0%
      const base = this.at === 0 ? 0 : -100;
      return `${base + this.swipeProgress * 100}%`;
    }
    return this.at === 0 ? '0%' : '-100%';
  }

  // 评论区水平偏移量（百分比）
  getCommentOffset = (): string => {
    if (this.isSwiping) {
      // 跟随手指：at=0时从100%→0%，at=1时从0%→100%
      const base = this.at === 1 ? 0 : 100;
      return `${base + this.swipeProgress * 100}%`;
    }
    return this.at === 1 ? '0%' : '100%';
  }

  // 获取切换tab的容器宽度，用于将offsetX归一化到[-1, 1]
  getLayoutWidth = (): number => {
    // 竖屏典型宽度（父容器padding左右各12）
    return 360;
  }

  private clrT() {
    [this.ct_, this.gt_, this.lt_, this.dt_, this.bt, this.ubt, this.rhtm,
      this.rt_, this.sti_].forEach(t => { if (t !== -1) clearTimeout(t) });
    this.ct_ = this.gt_ = this.lt_ = this.dt_ = this.bt = this.ubt = this.rhtm =
      this.rt_ = this.sti_ = -1;
  }

  private schedAH() {
    if (this.ct_ !== -1) clearTimeout(this.ct_);
    if (this.cv && !this.lk && !this.ip) this.ct_ = setTimeout(() => {
      if (!this.lk && !this.ip) { this.cv = false; this.ct_ = -1; }
    }, 15000);
  }

  private resetCT() {
    if (this.lk || !this.cv) return;
    if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
    this.schedAH();
  }

  private showCR() {
    if (this.lk) return;
    // 取消任何待处理的延迟隐藏
    this.cancelDelayHide();
    if (!this.cv) this.cv = true;
    if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
    this.schedAH();
  }

  // 取消延迟隐藏控制栏（按钮回调调用，阻止onTU中的延迟隐藏生效）
  private cancelDelayHide() {
    if (this.hc_ !== -1) { clearTimeout(this.hc_); this.hc_ = -1; }
  }

  /**
   * ⭐ 进度条交互回调（由 VideoControls 的 Slider 在 onChange 的 Begin/Moving/End/Click
   * 以及 onTouch 的 Cancel 上调用）。约定：`active=true` 表示"交互进行中"，`false` 表示"交互结束"。
   *
   * `active=true`（Begin / Moving）：
   * 1. 冻结 ct：进度条由独立组件持有，原先拖动时页面侧 sk_ 仍为 false，
   *    timeUpdate（约 1 次/秒）会把 ct 写回真实播放位置 —— 而 Slider 的 value 就绑在 ct 上，
   *    于是拇指被"拉回"、时间数字跳动。
   * 2. 置 ip：抑制 schedAH() 的 15 秒自动隐藏，否则长视频上连续拖动时控制栏会在手指底下消失。
   *
   * `active=false`（End / Click，以及 onTouch 的 Cancel）：
   * 3. 提交**一次** seek。原先 Click 与 End 都调 seekTo → 一次点击发起两次 seek；
   *    现在用"同一目标只提交一次"去重（点滑轨会依次触发 Begin/Click/End）。
   * 4. 锚点取**交互开始那一刻的 ct**（不是回调传进来的值）：点击滑轨时 Begin 的 value 可能
   *    已经是跳转后的新值，用它当锚点会把"位移判定"算成没动，从而吞掉提交。
   *
   * ⚠️ 不要改回"用 onTouch 的 Up 提交"：官方事件模型中触摸事件派发先于手势识别回调，
   *    点击滑轨时 Up 早于 Slider 自身的 click-jump，那时 value 还是旧值，提交必然失效（已实测复现）。
   */
  private onSeekBarInteract_ = (active: boolean, time: number): void => {
    // ⭐ 开启/续期"进度条触摸窗口"：从第一次上报一直到手指抬起（由 onVT 在 Up/Cancel 时撤销）。
    //   提交（End/Click）早于 Up，所以这里不能只依赖 sliderDragging_ —— 详见 seekBarTouch_ 字段注释。
    this.seekBarTouch_ = true;
    if (this.seekBarTouchTimer_ !== -1) clearTimeout(this.seekBarTouchTimer_);
    this.seekBarTouchTimer_ = setTimeout(() => {
      this.seekBarTouch_ = false;
      this.seekBarTouchTimer_ = -1;
    }, 1500);

    // ⭐ 拖动/点击底部进度条也弹「时间 + 小进度条」提示，与视频区手势 seek 的手感保持一致：
    //   - 拖动期间每条 Moving 上报都会续期（与手势路径同频，sGH 本来就是这么用的），
    //     所以整段拖动期间常驻，松手后 800ms 自然淡出；
    //   - 点击滑轨时 End/Click 那次上报会让提示闪一下，确认"已跳到目标"；
    //   - 时长未知时不弹（与手势路径的 dur<=0 守卫一致），避免"拖了像没反应"。
    if (this.dur > 0) {
      // ⭐ 拖动中按 20fps 刷新提示胶囊/缩略图（Moving 上报 ~90fps）；收尾那一次（End/Click）
      //   必须无条件刷新，否则最后停在哪儿没有反馈。
      const nowHint = Date.now();
      if (!active || nowHint - this.lastSeekHintAt_ >= 45) {
        this.lastSeekHintAt_ = nowHint;
        this.sGH(this.formatDuration(Math.round(time)), time / this.dur, 'seek');
        // ⭐ 缩略图预览：与上面的提示胶囊同一套显隐（sGH 超时隐藏时会一并隐藏）
        this.updateSeekThumb_(time);
      }
    }

    if (active) {
      // Moving 阶段会以 ~90 次/秒高频上报，已在交互中就直接返回，避免重复写状态
      if (this.sliderDragging_) return;
      this.sliderDragging_ = true;
      this.seekDragAnchor_ = this.ct;   // ⭐ 锚点 = 交互开始前的位置
      // ⭐ 提示胶囊右侧"相对位移"的起点（= 拖动锚点；必须在 sGH 之前写好，否则首帧会拿旧值算）
      this.ghb = this.seekDragAnchor_;
      this.lastSeekBarCommitV_ = -1;    // 新手势：清空"已提交目标"去重记录
      this.sk_ = true;    // 冻结 ct，阻止 timeUpdate 回写
      this.ip = true;     // 抑制自动隐藏
      if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
      this.cancelDelayHide();
      return;
    }
    // ---- 交互结束 ----
    // ⚠️ 这里**只有"本次没有提交 seek"才允许自己解冻 sk_**：若刚提交的 seek 仍在途（sg_ 为 true），
    //   sk_ 归 seek() 的 finally 复位。否则 timeUpdate 会立刻把 ct 写回**旧播放位置** ——
    //   Slider 的 value 与时间文本随之回退，用户看到的现象是"点了/拖了进度条，时间没有跳到目标"。
    if (Math.abs(time - this.lastSeekBarCommitV_) < 0.25) {
      // 同一手势的重复上报（Click 之后紧跟 End，值相同）→ 只收尾，不再 seek
      this.sliderDragging_ = false;
      this.ip = false;
      if (!this.sg_) this.sk_ = false;
      if (this.cv) this.resetCT();
      return;
    }
    const anchor = this.seekDragAnchor_ >= 0 ? this.seekDragAnchor_ : this.ct;
    this.seekDragAnchor_ = -1;
    this.sliderDragging_ = false;
    this.ip = false;
    // 位置没变（点了一下滑块但没移动）→ 不提交，避免无意义的 seek + 画面闪一下
    if (Math.abs(time - anchor) < 0.25) {
      if (!this.sg_) this.sk_ = false;
      if (this.cv) this.resetCT();
      return;
    }
    this.lastSeekBarCommitV_ = time;
    // 播放器未就绪时 seek() 会直接 return（不会进入它的 finally 复位 sk_）→ 这里兜底解冻，
    // 否则 sk_ 永久为 true、ct 被冻结、进度条彻底不刷新
    if (!this.av) {
      if (!this.sg_) this.sk_ = false;
      if (this.cv) this.resetCT();
      return;
    }
    // 提交一次；seek 内部会接管 sk_ 并在完成后复位
    this.seek(time, false, true);
    if (this.cv) this.resetCT();
  }

  // ⭐ 镜像切换回调（VideoControls 按钮点击触发）：取消 200ms 延迟隐藏 + 持久化镜像布局状态
  private async onMirrorToggle(): Promise<void> {
    this.cancelDelayHide();
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      await pf.put('mirrorControls', this.isMirrorControls);
      await pf.flush();
    } catch (e) {
      logError('保存镜像布局状态失败', e);
    }
  }

  // ⭐ 加载控制栏镜像状态（从Preferences读取，默认标准布局）
  private async loadMirrorControlsState(): Promise<void> {
    try {
      const pf = await preferences.getPreferences(this.getUIContext().getHostContext() as common.Context, 'VPS');
      const savedValue = await pf.get('mirrorControls', false);
      this.isMirrorControls = savedValue as boolean;
      logInfo(`[镜像] 从本地存储加载状态: ${this.isMirrorControls ? '镜像' : '标准'}`);
    } catch (e) {
      logError('加载镜像布局状态失败', e);
      this.isMirrorControls = false;
    }
  }

  private sBH(img: ResourceStr | undefined, txt: string) {
    if (this.bt !== -1) clearTimeout(this.bt);
    this.bhi = img;
    this.bht = txt;
    this.bh = true;
    this.bt = setTimeout(() => { this.bh = false; this.bt = -1; }, 2000);
  }

  @State private ghMotion: AdjustmentMotion = { sequence: 0, delta: 0, velocity: 0 };
  private levelInputTotal: number = 0;
  private levelInputAt: number = 0;

  private sampleLevelInput(total: number): void {
    const now: number = Date.now();
    const delta: number = this.ghActive ? total - this.levelInputTotal : total;
    const elapsed: number = this.ghActive ? Math.max(16, now - this.levelInputAt) : 16;
    this.levelInputTotal = total;
    this.levelInputAt = now;
    this.ghMotion = { sequence: this.ghMotion.sequence + 1,
      delta: delta, velocity: delta * 1000 / elapsed };
  }

  private sGH(txt: string, progress: number = -1, type: string = '') {
    this.ght = txt;
    this.gh = true;
    this.ghp = progress;
    this.ghtType = type;
    // ⭐ 只有音量/亮度是真·按住调节；seek 与长按提示的竖条不存在，一律视为未按住。
    this.ghActive = type === 'volume' || type === 'brightness';
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = -1;
    // 音量/亮度持续按住时保留提示和汇流，松手后才开始隐藏计时。
    if (this.ghActive) return;
    this.gt_ = setTimeout(() => {
      this.gh = false;
      this.gt_ = -1;
      this.ghActive = false;
      // ⭐ 缩略图与提示胶囊同生共死：提示淡出时一并隐藏，不用再单独维护一个计时器
      this.hideSeekThumb_();
    }, 800);
  }

  private finishLevelGesture_(): void {
    const wasAdjusting: boolean = this.ghActive;
    this.ghActive = false;
    if (!wasAdjusting || !this.gh) return;
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = setTimeout(() => {
      this.gh = false;
      this.gt_ = -1;
    }, 800);
  }

  /**
   * ⭐ 更新进度调节缩略图（拖动进度条 / 视频区左右滑动时调用）
   *
   * 拖动期间会以 ~90 次/秒的节奏调用，所以：
   * - 结果按"令牌"取最后一次：拖动时异步请求会并发返回，只认最新的，否则画面会闪回旧帧；
   * - 查不到时不改 `pm`（沿用上一张），避免网络/解码期间缩略图闪白。
   */
  private updateSeekThumb_(sec: number): void {
    const bvid: string = this.vi.bvid || (this.vd?.bvid ?? '');
    const cid: number = this.vi.cid;
    if (!bvid || !cid || cid <= 0) return;
    const token: number = ++this.shotToken_;
    VideoShotService.getFrame(bvid, cid, sec).then((frame: SeekThumbFrame | undefined) => {
      if (token !== this.shotToken_) return;   // 已有更新的请求，丢弃这次结果
      // 同一张位图且已在显示中 → 不必重建对象，省掉一次无意义的组件刷新
      if (frame && frame.pm === this.thumb_.pm && this.thumb_.show) return;
      const t: SeekThumb = new SeekThumb();
      if (frame) {
        t.pm = frame.pm;
        t.aspect = frame.aspect;
      } else {
        t.pm = this.thumb_.pm;                 // 拿不到就沿用上一张（不闪白）
        t.aspect = this.thumb_.aspect;
      }
      t.show = true;
      this.thumb_ = t;
    }).catch(() => {
    });
  }

  /** 隐藏缩略图（提示胶囊淡出时调用）。保留位图，下次拖动可直接显示、不用等解码 */
  private hideSeekThumb_(): void {
    this.shotToken_++;                         // 让在途结果失效
    if (!this.thumb_.show) return;
    const t: SeekThumb = new SeekThumb();
    t.pm = this.thumb_.pm;
    t.aspect = this.thumb_.aspect;
    t.show = false;
    this.thumb_ = t;
  }

  /**
   * ⭐ 预取缩略图列表（起播后延迟调用）。
   * 延迟是为了避开起播阶段的解码/网络竞争；精灵图不在此时下载，等真正拖动时再按需取。
   */
  private prefetchVideoShot_(): void {
    const bvid: string = this.vi.bvid || (this.vd?.bvid ?? '');
    const cid: number = this.vi.cid;
    if (!bvid || !cid || cid <= 0) return;
    // 换集/换视频：先松开上一集的位图引用，再整体释放缓存
    this.hideSeekThumb_();
    this.thumb_ = new SeekThumb();
    VideoShotService.setOwner(bvid, cid);
    setTimeout(() => {
      VideoShotService.prefetch(bvid, cid);
    }, 1500);
  }


  private tglUB() {
    logInfo('[VideoPlayer] tglUB called, current ub:', this.ub);
    // 在锁定状态下，点击屏幕切换解锁按钮的显示/隐藏状态
    if (this.ub) {
      // 如果按钮当前显示，则立即隐藏
      this.ub = false;
      logInfo('[VideoPlayer] Hide unlock button immediately');
      // 清除现有定时器
      if (this.ubt !== -1) { clearTimeout(this.ubt); this.ubt = -1; }
    } else {
      // 如果按钮当前隐藏，则显示并设置5秒后自动隐藏
      this.ub = true;
      logInfo('[VideoPlayer] Show unlock button');
      // 清除现有定时器
      if (this.ubt !== -1) { clearTimeout(this.ubt); this.ubt = -1; }
      // 设置5秒后自动隐藏
      this.ubt = setTimeout(() => {
        logInfo('[VideoPlayer] Auto-hide unlock button after 5 seconds');
        this.ub = false;
        this.ubt = -1;
      }, 5000);
    }
  }

  private manageSB(force: boolean = false) {
    if (!this.mw || !this.referenceAlive || !this.playerPageVisible) return;
    // Ability 回前台时使用同一全屏状态，避免把全屏误恢复成半屏的系统栏。
    AppStorage.setOrCreate('isFullscreen', this.fs);
    if (!force && this.fs) return;
    const feed = this.referenceLayout && this.referenceFeed && !this.fs && !this.isLs;
    const visible = !this.fs && (this.referenceLayout || !this.isLs) &&
      (feed ? !this.referenceInfoHidden : !this.sh_ && !this.isLightsOff);
    // 横屏播放独立隐藏导航条，顶部状态栏继续遵循原有显隐逻辑。
    // 目标状态没变就不要下发窗口指令：每次调用都会让窗口服务重算 avoidArea，
    // 菜单这种「打开前顺手刷新一次」的操作会白等一轮系统栏布局，动画首帧就掉。
    const key = `${visible}|${visible && !this.isLs}`;
    if (!force && key === this.sysBarKey_) return;
    this.sysBarKey_ = key;
    StatusBarUtils.setSystemBars(this.mw, visible, visible && !this.isLs);
  }

  async initW() {
    logInfo('[VPP] initW 开始');
    try {
      this.mw = await window.getLastWindow(this.getUIContext().getHostContext() as common.Context);
      this.mw.off('avoidAreaChange', this.onPlaybackAvoidAreaChanged);
      this.mw.on('avoidAreaChange', this.onPlaybackAvoidAreaChanged);
      // ⭐ 状态栏内容色不在这里下发：initW 跑在 push 转场首帧之前，立即设白会让首页还
      //    满屏时状态栏就变色。统一由 onPageShow 延迟一拍下发（见 onPageShow）。
      this.updatePlaybackPanelInset(this.mw.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM));
      // ⭐ 窗口背景色与页面底色一致：旋转瞬间不再露出系统默认底色（闪白）
      try {
        this.mw.setWindowBackgroundColor('#000000');
      } catch (_e) { }
      // ⭐ 窗口就绪后立即按当前播放状态设置屏幕常亮（onPageShow 早于 mw 就绪，不能依赖那次调用）
      this.updateKeepScreen();
      const b = this.mw.getWindowProperties().brightness;
      this.originalBrightness_ = b;
      if (b !== -1) this.bri = b;
      const r = this.mw.getWindowProperties().windowRect;
      this.sw = this.getUIContext().px2vp(r.width);
      this.cw = this.getUIContext().px2vp(r.width);
      this.ch = this.getUIContext().px2vp(r.height);
      this.screenH_ = this.getUIContext().px2vp(r.height);
      // ⭐ 根据窗口尺寸设置横竖屏状态（onAreaChange 在此之前可能尚未触发）
      this.isLs = r.width > r.height;
      this.maxFloatBtnBottom = this.isLs ? 392 : 592;
      this.updateIsLandscapeVertical();
      this.updateLSVSize();       // ← 补充：确保 lsvw/lsvh 正确
      this.updateVideoSize();
    } catch (e) { }
    logInfo('[VPP] initW 函数体完成');
  }

  private async activateAudioSession() {
    try {
      const audioManager = audio.getAudioManager();
      const sessionManager = audioManager.getSessionManager();
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
      };
      await sessionManager.activateAudioSession(strategy);
    } catch (e) { }
  }

  /**
   * 释放播放器 — 如果 av/avAudio 已被转移到 PlayerService 则跳过
   */
  async release(cancelQuality: boolean = true): Promise<void> {
    clearTimeout(this.startupFrameTimer_);
    clearInterval(this.playbackDiagnosticTimer_);
    this.playbackDiagnosticTimer_ = -1;
    this.initializationDeadline_?.cancel();
    if (cancelQuality) this.qualityDeadline_?.cancel();
    if (cancelQuality) this.qualitySession_?.release().catch(() => {});
    this.referenceFeedAudioStartPending = false;
    this.startupResumePlayer_ = null;
    this.startupResumeMs_ = 0;
    this.startupSourceDurationMs_ = 0;
    const pending: Promise<void>[] = [];
    // ⭐ 停止同步定时器
    this.stopSyncTimer();
    if (this.av) {
      this.av.off('stateChange');
      // release() tears down the subscription. off('timeUpdate') synchronously
      // calls the media service and stalls the UI thread at the end of router pop.
      // The callback rejects retired players through its captured player identity.
      this.av.off('error');
      this.av.off('videoSizeChange');
      this.av.off('startRenderFrame');
      this.av.off('seekDone');
      pending.push(this.av.release().catch((error: Error) => { logWarn('释放视频播放器失败', error); }));
      this.av = null;
    }
    if (this.avAudio) {
      this.avAudio.off('stateChange');
      this.avAudio.off('error');
      this.avAudio.off('seekDone');
      pending.push(this.avAudio.release().catch((error: Error) => { logWarn('释放音频播放器失败', error); }));
      this.avAudio = null;
    }
    // ⭐ DASH 转播站桥：页面持有则停；恢复接管存的句柄同样停
    if (this.dashBridge_) {
      this.dashBridge_.stopIfRunning();
      this.dashBridge_ = null;
    }
    if (this.dashHandle_) {
      this.dashHandle_.stop();
      this.dashHandle_ = null;
    }
    this.isDashStream_ = false;
    // ⭐ 离线播放：关闭本地文件 fd
    if (this.offlineVideoFd_) {
      try { fs.closeSync(this.offlineVideoFd_); } catch (e) { }
      this.offlineVideoFd_ = null;
    }
    if (this.offlineAudioFd_) {
      try { fs.closeSync(this.offlineAudioFd_); } catch (e) { }
      this.offlineAudioFd_ = null;
    }
    await Promise.all(pending);
  }

  private setPlaybackCid(cid: number): void {
    this.vi.cid = cid;
    if (cid > 0) this.cidReady_?.();
  }

  private async waitForPlaybackCid(deadline: PlaybackDeadline): Promise<void> {
    if (this.vi.cid > 0) return;
    let timer: number = -1;
    let notify: () => void = () => {};
    const ready = new Promise<void>((resolve, reject) => {
      notify = resolve;
      this.cidReady_ = notify;
      timer = setTimeout(() => reject(new Error('获取视频CID超时，请重试')), 5000);
    });
    try {
      await deadline.wait(ready, '获取视频CID');
    } finally {
      clearTimeout(timer);
      if (this.cidReady_ === notify) this.cidReady_ = null;
    }
  }

  async initP() {
    if (this.initPInProgress_ || this.av || !this.referenceAlive) return;
    const profile = this.playbackProfile;
    const initGeneration = this.referenceSwitchGeneration;
    const deadline = new PlaybackDeadline();
    this.initializationDeadline_ = deadline;
    PlaybackStartup.trace('init', this.playbackStartupAt);
    // 防止重复初始化
    // ⭐ 先设置标志，防止竞态条件
    this.initPInProgress_ = true;

    this.waitingForFirstFrame = true;
    let playerTask: Promise<PlaybackPlayer | null> | null = null;
    let playerAdopted = false;
    let bridge: DashPlayerBridge | null = null;
    let bridgeTask: Promise<string | null> | null = null;
    // 点击时已在宿主 surface 上 prepare 好的实例：命中就完全跳过创建/取流/建站。
    let warm: WarmPlayback | null = null;
    try {
      // 空播放器无需 Surface/CID；与详情、取流和首次布局同时准备。
      if (!this.offlineVideoPath_ && !ijkPlaybackRequested()) {
        const creation = PlaybackStartup.span('player-create', profile);
        playerTask = media.createAVPlayer().then((player: PlaybackPlayer) => {
          creation?.end();
          PlaybackStartup.trace('player', this.playbackStartupAt);
          return player;
        }).catch(() => null);
      }
      profile?.mark('cid-wait-start');
      if (!this.vi.cid) await this.waitForPlaybackCid(deadline);
      if (!this.referenceAlive || initGeneration !== this.referenceSwitchGeneration) return;
      profile?.mark('cid-ready');
      if (!this.vi.cid) throw new Error('获取视频CID失败');
      // ⭐ 离线播放：本地缓存文件（用 fdSrc 属性，兼容 API 24/26；createMediaSourceWithUrl/Fd 均不跨版本通用）
      if (this.offlineVideoPath_) {
        this.av = await media.createAVPlayer();
        if (!this.av) throw new Error('no player');
        this.setupL();
        // 打开本地视频文件获取 fd 并作为数据源
        this.offlineVideoFd_ = fs.openSync(this.offlineVideoPath_, fs.OpenMode.READ_ONLY);
        const vFd: media.AVFileDescriptor = { fd: this.offlineVideoFd_.fd, offset: 0 };
        this.av.fdSrc = vFd;
        if (this.offlineAudioPath_) {
          this.avAudio = await media.createAVPlayer();
          if (this.avAudio) {
            this.setupAudioL();
            this.offlineAudioFd_ = fs.openSync(this.offlineAudioPath_, fs.OpenMode.READ_ONLY);
            const aFd: media.AVFileDescriptor = { fd: this.offlineAudioFd_.fd, offset: 0 };
            this.avAudio.fdSrc = aFd;
          }
        }
      } else {
      profile?.mark('playurl-call');
      // ⭐ 取流用「偏好画质」而不是 `qn`：`qn` 可能已被上一条的服务端降级改写，
      //   拿它当请求上限会让降级沿连刷一路传染（画质棘轮）。
      const fetched: PlayUrlResult = this.isPgc_
        ? await deadline.wait(getPgcPlayUrl(this.epId_, this.vi.cid, this.preferredQn, this.seasonId_), '获取播放地址')
        : await deadline.wait(getVideoPlayUrl(this.vi.bvid, this.vi.cid, this.preferredQn), '获取播放地址');
      const result = selectDecodablePlayUrl(fetched);
      if (!this.referenceAlive || initGeneration !== this.referenceSwitchGeneration) return;
      profile?.mark('url-ready');
      profile?.mark('source-kind', result.audioUrl && result.dash ? 1 : 0);
      profile?.mark('actual-quality', result.actualQn || this.qn);
      const url = result.url;
      PlaybackStartup.trace('url', this.playbackStartupAt);
      if (!url) throw new Error('no url');
      const mediaHeaders: Record<string, string> = {
        'User-Agent': result.mediaUserAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      };
      const mediaReferer = result.mediaReferer ?? 'https://www.bilibili.com/';
      if (mediaReferer) mediaHeaders['Referer'] = mediaReferer;
      // ⭐ 服务端续播点兜底：路由未带进度（从番剧页/推荐/搜索进入）时，用该集自己的观看位置恢复
      this.applyServerResumePoint(result);
      this.startupSourceDurationMs_ = result.dash?.timelength || 0;
      profile?.mark('resume-ms', Math.round(this.initialProgress_ * 1000));
      // 更新为服务器实际返回的画质（可能被降级）。只描述当前这条：
      // 取流上限是 preferredQn，这里绝不回写它，否则降级会沿连刷一路传染。
      this.qn = result.actualQn || this.qn;
      this.applyAcceptQuality(result);
      this.ql = this.getQlLabel(this.qn);
      // ⭐ DASH 双流：走「探测→MPD→转播站→单 AVPlayer」，替代双 AVPlayer 手动同步
      const resumeMs: number = Math.max(0, Math.round(this.initialProgress_ * 1000));
      if (!supportsIjkPlayback(result) && result.dash !== undefined && result.dash !== null && this.vi.cid > 0) {
        // 画质对不上就别等了：立即取消预热，直接冷启动。
        const warmQuality: number = PlaybackWarmPlayer.get().peekQuality(this.vi.cid);
        if (warmQuality !== 0 && warmQuality !== result.dash.quality) {
          PlaybackWarmPlayer.get().abort();
        } else {
          // 到这里地址已经就绪：预热通常也已经备好，命中就不再有等待。
          warm = await PlaybackWarmPlayer.get().take(this.vi.cid, 1500);
        }
      }
      if (warm !== null && result.dash !== undefined && result.dash !== null && warm.quality !== result.dash.quality) {
        // 预热用的画质和页面最终拿到的不是同一档（切了清晰度/服务端降级）：放弃预热，走冷路径。
        warm.release();
        warm = null;
      }
      if (warm !== null) {
        if (playerTask !== null) {
          // 预热命中：并行创建的空播放器直接释放，不让它和预热实例抢解码器。
          playerTask.then((unused: PlaybackPlayer | null) => {
            try { unused?.release(); } catch (e) { }
          }).catch(() => {});
          playerTask = null;
        }
        const took: boolean = await this.adoptWarmPlayback(warm, result, initGeneration, resumeMs);
        warm = null;
        if (took) {
          return;
        }
      }
      if (!supportsIjkPlayback(result) && result.audioUrl && result.dash) {
        bridge = new DashPlayerBridge(profile);
        bridgeTask = bridge.buildAndStart(
          result.dash, result.mediaReferer ?? 'https://www.bilibili.com/',
          result.mediaUserAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          AppStorage.get<string>('biliCookie') || '',
          // ⭐ 起播位（续播点）传给转播站做「分段预取」：起播时为 0 无副作用，
          //    有续播点时把覆盖该时刻的分段在 prepare 期间先拉好，seek 时直接命中缓存
          resumeMs).catch(() => null);
        PlaybackStartup.setPath('cold');
      }
      // IJK 单槽实例池：列表阶段已 prepare 到首帧，命中就只换 surface。
      // 连刷里不能拿：池实例是给首页卡片准备的（宿主 2x2 surface、FIT、静音），
      // 接到连刷的第二个 surface 上会先 initialized→prepared 再被 pause，
      // 首帧回调扑空，表现就是切过去一直转圈。连刷自己的预热走 referenceWarmSession。
      let ijkWarm: IjkWarmTake | null = null;
      if (!this.offlineVideoPath_ && !this.referenceFeed && this.vi.cid > 0 && supportsIjkPlayback(result)) {
        ijkWarm = await IjkWarmPool.get().takeOrWait(this.vi.cid, result.dash?.quality ?? 0, 600);
      }
      // 索引探测已开始，不必先等播放器创建完成。
      const player = ijkWarm !== null ? ijkWarm.handles.video
        : (playerTask ? await deadline.wait(playerTask, '创建播放器') : await deadline.wait(createPlaybackPlayer(result), '创建播放器'));
      if (!this.referenceAlive || initGeneration !== this.referenceSwitchGeneration) return;
      if (!player) throw new Error('no player');
      const playerUrl = bridgeTask ? await deadline.wait(bridgeTask, '准备媒体索引') : url;
      if (!this.referenceAlive || initGeneration !== this.referenceSwitchGeneration) return;
      if (!playerUrl) throw new Error('DASH 转播站启动失败');
      this.av = player;
      playerAdopted = true;
      this.setupL();
      if (player instanceof IjkPlaybackPlayer) {
        this.isDashStream_ = true;
        if (ijkWarm !== null) {
          let warmSurface: string = this.activeVideoSurfaceId();
          for (let i = 0; i < 20 && warmSurface.length === 0; i++) {
            await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 50));
            warmSurface = this.activeVideoSurfaceId();
          }
          if (warmSurface.length === 0 || !this.referenceAlive ||
            initGeneration !== this.referenceSwitchGeneration) {
            // 拿不到页面 surface 就别硬接：交给错误路径释放后重来，避免渲染到隐藏 surface。
            throw new Error('IJK 预热实例改绑失败');
          }
          this.sId = warmSurface;
          try {
            if (player.surfaceId !== warmSurface) player.surfaceId = warmSurface;
          } catch (e) {
            logWarn('[VideoPlayer] IJK 预热实例改绑 surface 失败: ' + errMsg(e));
          }
          // ⚠️ 池实例在 prepare 阶段就把 videoSizeChange 发完了（ff_ffplay.c 在 prepared
          //    之前用 codecpar 发一次、videothread 首帧 alloc 再发一次），take() 时
          //    FeedPlaybackSession.detachListeners 把监听摘掉；页面 setupL 重新注册时
          //    事件已经过去，之后除非解码器真改尺寸否则不会再发。
          //    ⇒ 画幅必须在这里主动回灌，否则 ar 停在默认 16/9，而 IJK 是把帧铺满
          //      surface 的（videoScaleType 只存字段、不下发 native），竖屏画面就被
          //      拉伸成一条 16:9 的横条。
          this.adoptWarmAspect(player, ijkWarm.aspectRatio);
          // 换完 surface 立刻 seek 一下：渲染线程是「被帧唤醒」的，
          // 停在 paused 时窗口换了也没人重建 EGL，屏幕会一直黑。
          try {
            player.seek(0, media.SeekMode.SEEK_CLOSEST);
          } catch (e) {
            logWarn('[VideoPlayer] 预热实例 seek 失败: ' + errMsg(e));
          }
          this.startupSourceDurationMs_ = result.dash?.timelength || 0;
          this.applyServerResumePoint(result);
          PlaybackStartup.setPath('ijk-warm');
          // 池实例在 prepare 之前已按列表阶段的历史进度 setPlaybackRange，解出的首帧
          // 就是续播点的帧。与本次起播点一致时登记「续播点已预置」：applyPreparedState
          // 会跳过 seek + 等 seekDone（真机实测这段要多花 ~900ms 才出首帧）。
          // 不一致（历史进度刚被改写、服务端续播点覆盖）时退回原来的 seek 路径。
          const warmResumeMs: number = ijkWarm.resumeMs;
          if (warmResumeMs > 0 && Math.abs(warmResumeMs - this.initialProgress_ * 1000) < 100) {
            this.startupResumePlayer_ = player;
            this.startupResumeMs_ = warmResumeMs;
          }
          const warmAdoptAt: number = Date.now();
          let warmFrameLogged: boolean = false;
          player.on('startRenderFrame', () => {
            if (warmFrameLogged) return;
            warmFrameLogged = true;
            hilog.info(0x0000, 'Bilibili', '%{public}s',
              `[VideoPlayer] 预热实例首帧 ${Date.now() - warmAdoptAt}ms`);
          });
          hilog.info(0x0000, 'Bilibili', '%{public}s',
            `[VideoPlayer] 接管 IJK 预热实例 cid=${this.vi.cid} qn=${result.dash?.quality ?? 0}`);
          await this.applyPreparedState(player, initGeneration);
          hilog.info(0x0000, 'Bilibili', '%{public}s',
            `[VideoPlayer] 预热实例起播完成 ${Date.now() - warmAdoptAt}ms`);
          // 预热实例在池里已经渲染过首帧，IJK 不会再补一次 RENDER_START；
          // 这里直接摘掉「正在加载视频」的遮罩，否则它会一直盖在画面上。
          if (this.waitingForFirstFrame) {
            this.waitingForFirstFrame = false;
            this.ld = false;
            PlaybackStartup.trace('frame', this.playbackStartupAt);
            PlaybackStartup.deactivate(this.playbackProfile);
            PlaybackStartup.report('frame');
          }
          return;
        }
        PlaybackStartup.setPath('ijk-direct');
        player.load(result);
      } else if (bridge) {
        this.isDashStream_ = true;
        this.dashBridge_ = bridge;
        bridge = null;
        PlaybackStartup.trace('bridge', this.playbackStartupAt);
        const src = media.createMediaSourceWithUrl(playerUrl, {
          'User-Agent': result.mediaUserAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://www.bilibili.com/'
        });
        profile?.mark('set-source-call');
        const startupStrategy = startupPlaybackStrategy();
        profile?.mark('startup-buffer-ms', Math.round((startupStrategy.preferredBufferDurationForPlaying ?? -1) * 1000));
        await deadline.wait(this.av.setMediaSource(src, startupStrategy), '设置播放源');
        profile?.mark('set-source-return');
      } else {
        this.isDashStream_ = false;
        const src = media.createMediaSourceWithUrl(url, mediaHeaders);
        profile?.mark('set-source-call');
        await deadline.wait(this.av.setMediaSource(src), '设置播放源');
        profile?.mark('set-source-return');
        if (result.audioUrl) {
          this.avAudio = await media.createAVPlayer();
          if (this.avAudio) {
            this.setupAudioL();
            const audioSrc = media.createMediaSourceWithUrl(result.audioUrl, mediaHeaders);
            await this.avAudio.setMediaSource(audioSrc);
          }
        }
      }
      }
    } catch (e) {
      if (!deadline.isCancelled() && this.referenceAlive && initGeneration === this.referenceSwitchGeneration) {
        logError('[VideoPlayer] initialization failed:', errMsg(e));
        profile?.mark('init-error');
        this.err = e instanceof Error ? e.message : 'init fail';
        this.ld = false;
        // Retire callbacks before a late native completion can restart this attempt.
        const releaseJob = this.release().catch(() => {});
        if (!this.offlineVideoPath_ && !this.userPaused_ && !this.ry_ && !this.referenceFeedPreparingMain) {
          releaseJob.then(() => {
            if (this.referenceAlive && initGeneration === this.referenceSwitchGeneration && !this.av && !this.initPInProgress_) {
              profile?.mark('startup-initialization-retry');
              this.recoverPlaybackStall(null);
            }
          });
        }
      }
    } finally {
      // Cleanup must not hold the initialization lock behind the promise that failed
      // to settle. Late resources are disposed when they eventually arrive.
      const unusedWarm = warm;
      if (unusedWarm !== null) {
        unusedWarm.release();
      }
      const unusedBridge = bridge;
      if (unusedBridge) {
        unusedBridge.stopIfRunning().catch(() => {});
      }
      if (playerTask && !playerAdopted) {
        playerTask.then((unusedPlayer: PlaybackPlayer | null) => unusedPlayer?.release()).catch(() => {});
      }
      if (this.initializationDeadline_ === deadline) {
        this.initializationDeadline_ = null;
        this.initPInProgress_ = false;
      }
    }
  }

  private setupAudioL() {
    if (!this.avAudio) return;
    const audioPlayer = this.avAudio;
    this.audioOutputMonitor.bind(audioPlayer, audio.StreamUsage.STREAM_USAGE_MUSIC);
    this.avAudio.on('stateChange', async (st: string) => {
      if (this.avAudio !== audioPlayer) return;
      if (st === 'prepared' || st === 'playing') this.audioOutputMonitor.bind(audioPlayer, audio.StreamUsage.STREAM_USAGE_MUSIC);
      if (st === 'initialized') {
        await this.avAudio?.prepare();
      } else if (st === 'prepared') {
        try { this.avAudio?.setVolume(1.0); this.audioGain_ = 1; if (this.mute) this.setSystemVolume(0); } catch (e) { }
        // ⭐ 同步播放速率（关键！否则音频可能以错误速度播放）
        try {
          await this.avAudio?.setSpeed(this.rateToSpeedIdx(this.rt));
          logInfo(`[VideoPlayer] 音频播放器设置播放速率: ${this.rt}x`);
        } catch (e) { }
        if (this.referenceFeedAudioStartPending && this.avAudio === audioPlayer && this.pagePlaybackAllowed() &&
          !this.playbackIsTerminal()) {
          this.referenceFeedAudioStartPending = false;
          await audioPlayer.play();
        }
        // ⭐ 不在这里自动播放，由视频播放器的prepared状态统一控制
        // 但需要确保音频播放器处于正确的seek位置
      } else if (st === 'playing' && !this.pagePlaybackAllowed()) {
        await audioPlayer.pause();
      }
    });
    // ⭐ 注册seekDone回调，用于同步等待seek完成
    this.avAudio.on('seekDone', (pos: number) => {
      logInfo(`[VideoPlayer] audio seekDone: ${pos}ms`);
      if (this.audioSeekResolve_) {
        this.audioSeekResolve_();
        this.audioSeekResolve_ = null;
      }
    });
    this.avAudio.on('error', (e: BusinessError) => { });
  }

  /**
   * 接管点击时预热好的播放实例：改绑 surface → 复用冷启动的 prepared 收尾。
   * 返回 false 表示没能接管（调用方继续走冷路径）。
   */
  private async adoptWarmPlayback(warm: WarmPlayback, result: PlayUrlResult, generation: number,
    resumeMs: number): Promise<boolean> {
    const player = warm.player;
    let surfaceId: string = this.activeVideoSurfaceId();
    for (let i = 0; i < 20 && surfaceId.length === 0; i++) {
      await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 50));
      surfaceId = this.activeVideoSurfaceId();
    }
    if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || surfaceId.length === 0) {
      warm.release();
      return false;
    }
    this.av = player;
    this.dashBridge_ = warm.bridge;
    this.isDashStream_ = true;
    this.sId = surfaceId;
    // 同一个坑：预热实例的 videoSizeChange 在池里就发完了，页面注册时收不到。
    // AVPlayer 的 width/height 在 prepared 之后由系统填好，直接拿它回灌。
    this.adoptWarmAspect(player, 0);
    this.startupSourceDurationMs_ = result.dash?.timelength || 0;
    this.applyServerResumePoint(result);
    PlaybackStartup.setPath('warm');
    const rebindAt: number = Date.now();
    try {
      if (player.surfaceId !== surfaceId) {
        player.surfaceId = surfaceId;
      }
    } catch (e) {
      logError('[VideoPlayer] 预热实例改绑 surface 失败:', errMsg(e));
    }
    this.playbackProfile?.mark('rebind-ms', Date.now() - rebindAt);
    logInfo(`[VideoPlayer] 接管预热实例 cid=${warm.cid} qn=${warm.quality} rebind=${Date.now() - rebindAt}ms`);
    this.setupL();
    if (resumeMs > 0) {
      warm.bridge.prefetchResume(resumeMs).catch(() => {});
    }
    await this.applyPreparedState(player, generation);
    return true;
  }

  /** 已 prepared 后的统一收尾：冷启动与预热接管共用，避免两套逻辑漂移。 */
  private async applyPreparedState(player: PlaybackPlayer, generation: number): Promise<void> {
    // 冷启动这里 ar 已被 videoSizeChange 修正过（delta≈0，无操作）；
    // 预热接管则靠这一次把池里错过的画幅补上。
    this.syncAspectFromPlayer(player);
    this.playbackProfile?.once('prepared');
    PlaybackStartup.trace('prepared', this.playbackStartupAt);
    this.ld = false;
    // 播放器报 0 时长时（4K fMP4 常见）不能让 dur 变成 0：进度条 max 会塌成 1，
    // 心跳/续播/卡顿判定也都依赖 dur。用本 CID 的 MPD 时长兜底，再退回视频元数据。
    const playerDurMs: number = this.av?.duration || 0;
    const fallbackDurSec: number = this.startupSourceDurationMs_ > 0
      ? this.startupSourceDurationMs_ / 1000 : (this.vi.duration || 0);
    this.dur = this.referenceFeed ? (this.vd?.duration || this.vi.duration || Math.ceil(playerDurMs / 1000))
      : (playerDurMs > 0 ? playerDurMs / 1000 : fallbackDurSec);
    // ⭐ 进度调节缩略图：起播后延迟预取列表（失败/无缩略图的视频静默降级）
    this.prefetchVideoShot_();
    // ⭐ 注册媒体控制回调（通知栏播放/暂停/拖动 -> 控制视频）
    LiveViewHelper.setControlHandlers({
      // ⭐ 显式语义：play 仅在未播放时播放，pause 仅在播放中暂停
      // （旧版 play/pause 都调 togglePP，后台已暂停时点通知栏"暂停"反而触发播放）
      play: () => { if (!this.play) { this.togglePP(); } },
      pause: () => { if (this.play) { this.togglePP(); } },
      seek: (time: number) => { this.seek(time / 1000, false); },
    });
    // ⭐ 创建实况窗：不阻塞起播（fire-and-forget，内部已全 try/catch；媒体会话在首帧后数百 ms 内就绪）
    LiveViewHelper.create(this.getUIContext().getHostContext() as common.Context, this.vi.title, this.vi.cover, this.vi.bvid, this.dur, this.vd?.owner?.name ?? '').catch(() => {});
    try { this.av?.setVolume(this.referenceFeedPreparingMain ? 0 : 1.0); if (this.mute) this.setSystemVolume(0); } catch (e) { }
    try {
      // 根据用户选择的缩放模式动态设置 videoScaleType
      const scaleType = this.getVideoScaleType();
      this.av!.videoScaleType = scaleType;
    } catch (e) { }
    if (this.referenceFeedPreparingMain) {
      this.referenceFeedPreparingMain = false;
      this.initialProgress_ = 0;
      // Some sources emit a still frame in prepared; others need a muted render
      // start. Both readiness signals must complete before the surface is revealed.
      if (this.referenceFeedMainFrameResolve && this.av?.state === 'prepared') {
        this.markAutoPlay('feed-muted-first-frame');
        await this.av.play();
      }
      if (this.av !== player || generation !== this.referenceSwitchGeneration) return;
      this.referenceFeedMainPreparedResolve?.();
      this.referenceFeedMainPreparedResolve = null;
      return;
    }
    // The quality-switch owner restores position and play/pause together.
    // Do not start a second seek/play sequence from this callback.
    if (this.qs) { this.initialProgress_ = 0; return; }
    // ⭐ 如果有初始进度，跳转到该位置
    const preparedProgress = PlaybackProgress.resume(this.initialProgress_, this.dur);
    const resumeAlreadyPrepared = this.startupResumePlayer_ === player &&
      Math.abs(this.startupResumeMs_ - preparedProgress * 1000) < 100;
    if (resumeAlreadyPrepared) this.playbackProfile?.mark('resume-prepared', this.startupResumeMs_);
    this.initialProgress_ = 0;
    const continuePaused = this.userPaused_ || (this.continuationRestore_ && this.continuationPaused_);
    if (this.continuationRestore_) await this.setRate(this.continuationRate_, false);
    this.continuationRestore_ = false;
    if (continuePaused) {
      if (preparedProgress > 0) {
        this.av?.seek(preparedProgress * 1000, media.SeekMode.SEEK_CLOSEST);
        this.avAudio?.seek(preparedProgress * 1000, media.SeekMode.SEEK_CLOSEST);
      }
      this.ct = preparedProgress;
      this.play = false;
      this.userPaused_ = true;
    } else if (preparedProgress > 0 && this.dur > 0 && preparedProgress < this.dur && !resumeAlreadyPrepared) {
      logInfo(`[VideoPlayer] 跳转到目标进度: ${preparedProgress}秒`);
      const seekPos = preparedProgress;
      this.restoringProgress = true;
      // 同时seek视频和音频播放器，确保音画同步
      try {
        // 创建等待seekDone的Promise
        const videoSeekDone = new Promise<void>(resolve => { this.videoSeekResolve_ = resolve; });
        const audioSeekDone = this.avAudio
          ? new Promise<void>(resolve => { this.audioSeekResolve_ = resolve; })
          : Promise.resolve();

        // 执行seek操作
        // ⭐ 恢复历史进度必须用 SEEK_CLOSEST：默认 SEEK_PREV_SYNC 会退到上一关键帧，
        //   长 GOP 片源上"续播点"能偏出十几秒，用户感知为"记录的时间对不上"
        this.playbackProfile?.mark('seek-call', Math.round(seekPos * 1000));
        this.av?.seek(seekPos * 1000, media.SeekMode.SEEK_CLOSEST);
        if (this.avAudio) {
          this.avAudio.seek(seekPos * 1000, media.SeekMode.SEEK_CLOSEST);
        }

        // 等待两个seekDone回调，最多等待2秒
        let seekTimedOut = false;
        const timeout = new Promise<void>(resolve => setTimeout(() => {
          seekTimedOut = true;
          resolve();
        }, 2000));
        await Promise.race([Promise.all([videoSeekDone, audioSeekDone]), timeout]);
        this.playbackProfile?.mark('seek-wait-end', seekTimedOut ? 1 : 0);
        // ⭐ 超时分支同样要摘掉 resolve，否则残留 resolver 会被后续 seekDone 误触发
        this.videoSeekResolve_ = null;
        this.audioSeekResolve_ = null;

        // ⚠️ 这行日志必须区分「真完成」与「2 秒兜底超时」：
        //    原先无论哪个分支都打"都完成"，于是排查「进播放页慢」时会被它误导成
        //    "seek 已完成，慢在别处" —— 实测这里打完之后 811ms 才收到真正的 seekDone。
        logInfo(seekTimedOut
          ? `[VideoPlayer] seek 等待超时(2s)，先继续；seekDone 可能稍后才到`
          : `[VideoPlayer] 两个seekDone都完成`);

        // 创建等待startRenderFrame的Promise
        const startRenderFrameDone = new Promise<void>(resolve => { this.startRenderFrameResolve_ = resolve; });

        // 先播放视频
        this.playbackProfile?.mark('play-call');
        if (!await this.startPagePlayback(player, false)) return;
        this.playbackProfile?.mark('play-return');

        // 等待视频第一帧渲染完成（最多等待3秒）
        const renderTimeout = new Promise<void>(resolve => setTimeout(resolve, 3000));
        await Promise.race([startRenderFrameDone, renderTimeout]);

        logInfo('[VideoPlayer] 视频第一帧已渲染，开始播放音频');


        // ⭐ 播放音频（不再seek，直接播放）
        if (!await this.startPagePlayback(player)) return;
        this.play = true;

        // ⭐ 首次快速同步：不等定时器，立刻检查
        this.initialSyncCheck();
        this.startVideoSpeedSync(500);
      } catch (e) {
        logError(`[VideoPlayer] seek失败: ${e}`);
        // seek失败，尝试直接播放
        if (!this.qs && !this.sg_) {
          if (await this.startPagePlayback(player)) this.play = true;
        }
      } finally {
        this.restoringProgress = false;
      }
    } else if (!this.qs && !this.sg_) {
      this.playbackProfile?.mark('play-call');
      if (!await this.startPagePlayback(player)) return;
      this.playbackProfile?.mark('play-return');
      // ⭐ 同时播放音频
      this.play = true;
      // ⭐ 启用声画同步监控
      this.startVideoSpeedSync();
    }
    if (!this.contentVisible) {
      if (this.pageEnterAnim !== 'none') {
        this.pageEnterProgress = 0;
      }
      animateTo({ duration: 0 }, () => {
        this.contentVisible = true;
      });
      if (this.pageEnterAnim !== 'none') {
        animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
          // ⭐ 页面加载回弹动画（固定参数）
      duration: this.PE_ENTER_DURATION,
      curve: curves.springCurve(this.PE_ENTER_VELOCITY, 1, Math.round(this.FS_SPRING_STIFFNESS * 2.1), this.PE_ENTER_DAMPING),
          onFinish: () => {
            this.commentsInitialized = true;
            if (this.pendingCommentAid > 0) {
              this.loadC(this.pendingCommentAid);
              this.pendingCommentAid = 0;
            }
            this.scheduleFloatBtnFadeIn();
          }
        }, () => {
          this.pageEnterProgress = 1;
        });
      } else {
        this.commentsInitialized = true;
        if (this.pendingCommentAid > 0) {
          this.loadC(this.pendingCommentAid);
          this.pendingCommentAid = 0;
        }
        this.scheduleFloatBtnFadeIn();
      }
    }
  }

  /**
   * 首帧确认的统一收尾（native 回调 / 时钟已走 两条路共用）。
   * ⭐ native 的 startRenderFrame **不是每条绑定路径都会补报**（实测 IJK 换绑 surface 后可能一次都不来）。
   *    只认这个回调，会让「首帧看门狗」把正常播放误判成卡死：15s 后释放并重建播放器；
   *    如果那一刻视频刚好播完，续播点会被算成 0 —— 现象就是「视频播放结束了，声音又从头开始」。
   */
  private confirmFirstFrame(player: PlaybackPlayer): void {
    if (this.av !== player) return;
    if (this.waitingForFirstFrame) {
      this.playbackProfile?.once('frame');
      PlaybackStartup.deactivate(this.playbackProfile);
      PlaybackStartup.trace('frame', this.playbackStartupAt);
      PlaybackStartup.report('frame');
    }
    clearTimeout(this.startupFrameTimer_);
    this.waitingForFirstFrame = false;
  }

  private setupL() {
    if (!this.av) return;
    const player = this.av;
    this.audioOutputMonitor.bind(this.avAudio ?? player, this.avAudio ? audio.StreamUsage.STREAM_USAGE_MUSIC : audio.StreamUsage.STREAM_USAGE_MOVIE);
    const generation = this.referenceSwitchGeneration;
    // 首帧判据的时钟基准：只要 currentTime 从这个值往后走了 500ms，就说明画面确实在出。
    const clockStart: number = player.currentTime;
    clearTimeout(this.startupFrameTimer_);
    this.startupFrameTimer_ = setTimeout(() => {
      if (this.av !== player || !this.referenceAlive || !this.waitingForFirstFrame || this.err || this.userPaused_) return;
      // ⭐ 时钟在走 = 画面早就出了，只是 native 没补报 startRenderFrame。
      //    这种情况下绝不能重建播放器（播完时重建会把续播点算成 0，直接从头重播）。
      if (player.state === 'playing' && player.currentTime >= clockStart + 500) {
        this.confirmFirstFrame(player);
        logInfo('[VideoPlayer] 首帧看门狗：时钟已在走，按已出帧收尾');
        return;
      }
      this.playbackProfile?.mark('first-frame-timeout');
      if (!this.offlineVideoPath_ && !this.referenceFeedPreparingMain) {
        this.recoverPlaybackStall(player);
        return;
      }
      this.err = '等待视频首帧超时，请重试';
      this.ld = false;
      this.release().catch(() => {});
    }, 15000);
    this.bufferedUntil = 0;
    const stallMonitor = new PlaybackStallMonitor();
    stallMonitor.reset(player.currentTime, this.bufferedUntil * 1000, Date.now());
    let rebuffering: boolean = false;
    clearInterval(this.playbackDiagnosticTimer_);
    this.playbackDiagnosticTimer_ = setInterval(() => {
      if (this.av !== player || !this.referenceAlive || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      const now = Date.now();
      const position = player.currentTime;
      // ⭐ 时钟已在走就说明首帧出了：立刻摘掉「等首帧」状态与看门狗，
      //    避免 15s 定时器把正常播放误判成卡死（IJK 可能不补报 startRenderFrame）。
      if (this.waitingForFirstFrame && player.state === 'playing' && position >= clockStart + 500) {
        this.confirmFirstFrame(player);
      }
      if (player.state === 'playing' && !this.userPaused_ && !this.ry_ && !this.err &&
        !this.waitingForFirstFrame && !this.sg_ && !this.sk_ && !this.qs &&
        // 菜单开合动画期间不发投机预取：一次预取就是一轮 IO/解码排队，会把动画切成几段。
        !this.referencePortraitSettingsAnimating) {
        const bridge: DashServerHandle | null = this.dashBridge_ || this.dashHandle_;
        bridge?.prefetchForPlayback?.(position, this.rt);
      }
      if (player.state !== 'playing' || this.waitingForFirstFrame || this.userPaused_ || this.sg_ || this.sk_ ||
        this.qs || this.ry_ || this.err || !this.playerPageVisible || this.referenceFeedLoading ||
        (player.duration > 0 && position >= player.duration - 1000)) {
        stallMonitor.reset(position, this.bufferedUntil * 1000, now);
        return;
      }
      if (stallMonitor.stalled(position, this.bufferedUntil * 1000, rebuffering, now)) this.recoverPlaybackStall(player);
    }, 1000);
    this.av.off('bufferingUpdate');
    this.av.on('bufferingUpdate', (type: media.BufferingInfoType, value: number) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      if (type === media.BufferingInfoType.BUFFERING_START) rebuffering = true;
      if (type === media.BufferingInfoType.BUFFERING_END) rebuffering = false;
      if (type === media.BufferingInfoType.CACHED_DURATION) {
        this.bufferedUntil = Math.min(this.dur, Math.max(0, player.currentTime / 1000 + value / 1000));
      }
    });
    this.av.on('stateChange', async (st: string) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      if ((st === 'prepared' || st === 'playing') && !this.avAudio) {
        this.audioOutputMonitor.bind(player, audio.StreamUsage.STREAM_USAGE_MOVIE);
      }
      this.playbackProfile?.mark(`state-${st}`, player.currentTime);
      if (st === 'initialized' || st === 'prepared' || st === 'playing') this.referencePlaybackCompleted = false;
      switch (st) {
        case 'initialized':
          this.playbackProfile?.once('initialized');
          if (this.sId) {
            await this.bindS();
          } else {
            const id = this.activeVideoSurfaceId();
            if (id) {
              this.sId = id;
              logInfo('[VideoPlayer] 兜底获取 surfaceId 成功');
              await this.bindS();
            } else {
              logWarn('[VideoPlayer] initialized 但 surfaceId 未就绪，延迟重试...');
              setTimeout(async () => {
                const retryId = this.activeVideoSurfaceId();
                if (retryId && this.av && this.av.state === 'initialized') {
                  this.sId = retryId;
                  logInfo('[VideoPlayer] 延迟重试获取 surfaceId 成功');
                  await this.bindS();
                } else {
                  logError('[VideoPlayer] 延迟重试失败，surfaceId 仍不可用');
                }
              }, 500);
            }
          }
          break;
        case 'prepared':
          await this.applyPreparedState(player, generation);
          break;
        case 'completed':
          this.referencePlaybackCompleted = true;
          this.playbackCompletedAt_ = Date.now();
          // ⭐ DASH 双流时音频是独立实例：视频轨播完必须同时收掉音频轨，
          //    否则音频会继续播（下一次 play() 还会单独从头出声）。
          if (this.avAudio?.state === 'playing') this.avAudio.pause().catch(() => {});
          this.ct = this.dur;
          this.play = false;
          LiveViewHelper.updateProgress(this.ct);
          LiveViewHelper.updatePlayState(false);
          this.saveWatchHistory(true);   // 播完必须上报（-1），不能被节流吞掉
          this.cv = true;
          this.cancelDelayHide();
          if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
          if (this.referenceLayout) this.referenceOnCompleted();
          break;
        case 'paused':
          LiveViewHelper.updatePlayState(false);
          if (!this.referenceFeedLoading) this.saveWatchHistory();
          break;
        case 'playing':
          // ⭐ 播完又被拉起：正常路径不会发生（completed 是终态），一旦出现说明有自动恢复
          //    绕过了守卫。把调用点写进日志，下次复发能直接定位是谁干的。
          if (this.playbackCompletedAt_ > 0) {
            const sinceEnd: number = Date.now() - this.playbackCompletedAt_;
            if (sinceEnd < 10000 && player.currentTime < 5000) {
              logError(`[VideoPlayer] ⚠ 播完 ${sinceEnd}ms 后又从 ${player.currentTime}ms 起播，调用点=${this.lastAutoPlaySite_ || 'unknown'}`);
            }
            this.playbackCompletedAt_ = 0;
          }
          if (!this.pagePlaybackAllowed()) {
            await player.pause();
            if (this.avAudio?.state === 'playing') await this.avAudio.pause();
            this.play = false;
            LiveViewHelper.updatePlayState(false);
            break;
          }
          LiveViewHelper.updatePlayState(true);
          break;
        case 'error':
          this.err = '播放器内部错误';
          this.ld = false;
          this.sr_ = false;
          // ⭐ 播放器内部错误：作废本视频 playurl 缓存，避免下次重试命中坏地址。
          //   缓存键按「请求画质」生成，取流用的是 preferredQn。
          invalidatePlayUrlCache(this.vi.bvid, this.vi.cid, this.preferredQn);
          break;
      }
    });
    // ⭐ 注册seekDone回调，用于同步等待seek完成
    this.av.on('seekDone', (pos: number) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      // ⭐ 丢弃「被顶掉的那次 seek」迟到的回调：IJK 在目标被新 seek 取代后仍可能补报**上一个**
      //   位置。旧实现拿它去完成新一轮的等待，结果 ct 被写成旧位置（进度条先跳回去一下），
      //   而真正那次 seekDone 就没人等了（实测 `seek end target=55 landed=148`）。
      //   判据只用「与当前目标的位置差」：SEEK_CLOSEST 落点很近，SEEK_PREV_SYNC 允许退一个 GOP。
      if (this.sg_ && this.seekExpectedPosition >= 0 &&
        Math.abs(pos / 1000 - this.seekExpectedPosition) > (this.seekFastMode_ ? 4 : 10)) {
        logInfo(`[VideoPlayer] 忽略过期 seekDone ${pos}ms（目标 ${this.seekExpectedPosition}s）`);
        return;
      }
      this.videoSeekPosition = pos / 1000;
      const savePending = this.seekProgressPending;
      this.seekProgressPending = false;
      this.playbackProfile?.mark('seek-done', pos);
      logInfo(`[VideoPlayer] video seekDone: ${pos}ms`);
      if (this.videoSeekResolve_) {
        this.videoSeekResolve_();
        this.videoSeekResolve_ = null;
      }
      if (savePending && !this.sg_) {
        this.ct = this.videoSeekPosition;
        this.referencePlaybackCompleted = player.state === 'completed';
        this.saveWatchHistory();
      }
    });
    // ⭐ 注册startRenderFrame回调，用于检测视频第一帧渲染完成
    this.av.on('startRenderFrame', () => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      this.confirmFirstFrame(player);
      logInfo(`[VideoPlayer] video startRenderFrame - 第一帧已渲染`);
      this.referenceSpareSurfaceMounted = true;
      this.referenceFeedMainFrameResolve?.();
      this.referenceFeedMainFrameResolve = null;
      if (this.startRenderFrameResolve_) {
        this.startRenderFrameResolve_();
        this.startRenderFrameResolve_ = null;
      }
      // ⭐ 首帧后：1080w 封面预解码挪到这里，不再与起播抢网络/解码线程
      this.predecodeCover();
      this.referenceWarmUpcomingFrames();
    });
    this.av.on('timeUpdate', (t: number) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      if (t > 0 && this.playbackProfile?.seen('frame')) this.playbackProfile.once('time-update', t);
      // 抽屉开合动画期间进度条与字幕层都被盖住：不写这些 state，
      // 否则每次 timeUpdate 都要带着整块不可见 UI 重新布局，动画就会被切成几段。
      const uiFrozen = this.referencePortraitSettingsAnimating;
      if (this.referenceSubtitleEnabled) {
        const cue = this.referenceSubtitleCues.find((item: ReferenceSubtitleCue) => item.from <= t / 1000 && item.to >= t / 1000);
        if (!uiFrozen) this.referenceSubtitleText = cue?.content || '';
      }
      if (this.referenceFeedMainPresentResolve && t > this.referenceFeedMainPresentAfter) {
        this.referenceFeedMainPresentResolve();
        this.referenceFeedMainPresentResolve = null;
      }
      this.referenceCheckSleep();
      if (!this.sk_) {
        if (!uiFrozen) this.ct = t / 1000;
        if (this.seekProgressPending && !this.sg_ && Math.abs(t / 1000 - this.seekExpectedPosition) < 2) {
          this.seekProgressPending = false;
          this.referencePlaybackCompleted = player.state === 'completed';
          this.saveWatchHistory();
        }
        if (Date.now() - this.progressSavedAt >= 2000) {
          this.progressSavedAt = Date.now();
          this.saveLocalPlaybackProgress();
        }
        // ⭐ 实况窗：更新进度（每 5 秒节流一次）
        if (!uiFrozen && this.lvTimer_ === -1) {
          this.lvTimer_ = setTimeout(() => {
            this.lvTimer_ = -1;
            LiveViewHelper.updateProgress(this.ct);
          }, 5000);
        }
      }
    });
    this.av.on('error', (e: BusinessError) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      PlaybackStartup.trace(`error-${e.code}`, this.playbackStartupAt);
      this.playbackProfile?.mark('player-error', e.code, player.currentTime);
      if (e.code !== 5400102) { this.err = `播放错误:${e.message}`; this.ld = false; }
    });
    this.av.on('videoSizeChange', (w: number, h: number) => {
      if (this.av !== player || (this.referenceFeed && generation !== this.referenceSwitchGeneration)) return;
      logInfo(`[VideoPlayer] videoSizeChange: ${w}x${h}`);
      this.vw = w;
      this.vh = h;
      if (w > 0 && h > 0) {
        const aspect = w / h;
        // ⚠️ 解码尺寸不是永远比已有画幅可信：rotate=90 的源上报的是编码尺寸，
        //    而路由/详情给的是显示尺寸，两者互为倒数。meta 仍对当前 cid 有效时
        //    保留显示画幅，否则竖屏会被这条事件改回 16:9 横版。
        if (this.decoderAspectIgnored(aspect)) {
          logInfo(`[VideoPlayer] 保留显示画幅 ${this.ar.toFixed(4)}，忽略解码画幅 ${aspect.toFixed(4)}`);
          return;
        }
        // 解码尺寸会修正初始 16:9 比例，视频和简介面板共同过渡，避免面板突然跳位。
        this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.referenceLayout && !this.waitingForFirstFrame && !this.referenceFeedPreviewPinned && !this.fs && !this.isLs ? 220 : 0,
          curve: Curve.EaseOut }, () => {
          this.ar = aspect;
          this.updateIsLandscapeVertical();
          this.updateLSVSize();
          this.updateVideoSize();
          if (this.referenceFeed) player.videoScaleType = this.getVideoScaleType();
        });
      } else {
        // 视频尺寸为0，可能是DASH模式下视频流尚未就绪
        logWarn('[VideoPlayer] Video size is 0x0, video stream may not be ready');
      }
    });
    // 监听注册完再看一眼播放器当前尺寸：预热接管 / 浮窗恢复 / 切集都可能在这之前
    // 就已经把尺寸定好了，事件过去了就永远等不到。幂等，冷启动时 delta≈0 无操作。
    this.syncAspectFromPlayer(player);
  }

  private preparingPlayer_: PlaybackPlayer | null = null;
  private startupFrameTimer_: number = -1;
  private playbackDiagnosticTimer_: number = -1;
  private stallRecoveryKey_: string = '';
  private stallResumeMs_: number = -1;
  private initializationDeadline_: PlaybackDeadline | null = null;
  private cidReady_: (() => void) | null = null;
  private qualityDeadline_: PlaybackDeadline | null = null;
  private qualitySession_: QualityPlaybackSession | null = null;
  private prepareTask_: Promise<void> | null = null;
  private startupResumePlayer_: PlaybackPlayer | null = null;
  private startupResumeMs_: number = 0;
  private startupSourceDurationMs_: number = 0;
  // Create the spare after the main first frame, then retain it across all switches.
  @State private referenceSpareSurfaceMounted: boolean = false;

  private async bindS() {
    const player = this.av;
    const surfaceId = this.nativeSurfaceId_ || this.sId;
    if (!player || !surfaceId) {
      logWarn('[VideoPlayer] bindS: player or surfaceId is null');
      return;
    }
    if (this.preparingPlayer_ === player && this.prepareTask_) return this.prepareTask_;
    try {
      logInfo(`[VideoPlayer] Binding surface: ${surfaceId}, player state: ${player.state}`);
      player.surfaceId = surfaceId;
      if (player.state === 'initialized') {
        this.preparingPlayer_ = player;
        const task = this.prepareAtStartupPosition(player);
        this.prepareTask_ = task;
        await task;
        if (this.av !== player) return;
        this.playbackProfile?.mark('prepare-return');
        logInfo('[VideoPlayer] Player prepared successfully');
      }
    } catch (e) {
      if (this.av !== player) return;
      logError('[VideoPlayer] bindS error:', e);
      this.err = e instanceof Error ? e.message : '渲染失败';
      this.ld = false;
    } finally {
      if (this.preparingPlayer_ === player) { this.preparingPlayer_ = null; this.prepareTask_ = null; }
    }
  }

  private async prepareAtStartupPosition(player: PlaybackPlayer): Promise<void> {
    const deadline = new PlaybackDeadline();
    const target = Math.round(this.initialProgress_ * 1000);
    // Use this CID's actual MPD duration, not the video's possibly multi-part total.
    const duration = this.startupSourceDurationMs_;
    if (deviceInfo.sdkApiVersion >= 18 && this.isDashStream_ && target > 0 && duration > target + 2000 &&
      !(this.qs && !this.play) &&
      !(this.continuationRestore_ && this.continuationPaused_)) {
      try {
        this.playbackProfile?.mark('range-call', target);
        await deadline.wait(player.setPlaybackRange(target, -1, media.SeekMode.SEEK_CLOSEST), '恢复播放位置');
        if (this.av !== player) return;
        this.startupResumePlayer_ = player;
        this.startupResumeMs_ = target;
        this.playbackProfile?.mark('range-return', target);
      } catch (error) {
        if (deadline.isExpired()) throw error as Error;
        logWarn('[VideoPlayer] early resume unavailable:', errMsg(error));
        this.playbackProfile?.mark('range-fallback');
      }
    }
    if (this.av !== player) return;
    this.playbackProfile?.mark('prepare-call');
    PlaybackStartup.trace('prepare', this.playbackStartupAt);
    await deadline.wait(player.prepare(), '准备播放器');
  }

  private referenceWarmSurfaceWidth(): number {
    return Math.max(1, Math.min(this.cw, this.referenceAreaHeight() * Math.max(0.2, this.referenceWarmAspectRatio)));
  }

  private referenceWarmSurfaceHeight(): number {
    return this.referenceWarmSurfaceWidth() / Math.max(0.2, this.referenceWarmAspectRatio);
  }

  private activeVideoSurfaceId(): string {
    if (this.floatingMorph && this.floatingXc.getXComponentSurfaceId()) return this.floatingXc.getXComponentSurfaceId();
    return (this.referenceSecondSurfaceActive ? this.referencePreviewXc : this.xc).getXComponentSurfaceId();
  }

  private onPlaybackSurfaceLoaded(second: boolean): void {
    if (second === this.referenceSecondSurfaceActive) this.onXC();
    else this.onReferencePreviewXc();
  }

  onXC = () => {
    const id = this.activeVideoSurfaceId();
    if (!id) return;
    this.playbackProfile?.once('surface-ready');

    // 尝试初始化 GL（即使 surface 未变化也可能首次异步就绪）
    this.tryInitGL_(id);

    // 如果Surface ID没有变化且播放器已绑定，则跳过
    if (id === this.sId && this.av && this.av.state !== 'idle') {
      return;
    }

    this.sId = id;

    // 初始化播放器（如果尚未初始化）
    if (!this.av && !this.initPInProgress_) {
      this.initP();
    } else if (this.av && this.av.state === 'initialized') {
      // 播放器已存在且已初始化，绑定Surface
      this.bindS();
    }
    // ⭐ XComponent 常驻单实例：surface 不再随布局分支切换重建，无需换 surface/强制出帧兜底
  }

  /**
   * 媒体会话（通知栏 / 锁屏 / 耳机 / 车机）的 play 请求。
   * ⭐ 播完后系统仍可能补发 play（耳机重连、车机重连、媒体会话恢复）：旧实现会走
   *    togglePP → referenceReplay，表现就是「视频早播完了，声音又从头开始」，
   *    而且 App 内没有任何操作痕迹，几乎无法复现。播完是终态，这里直接忽略。
   */
  private mediaSessionPlay(): void {
    if (this.playbackIsTerminal()) {
      logInfo('[VideoPlayer] 媒体会话 play 忽略：视频已播完');
      return;
    }
    if (!this.play) this.togglePP();
  }

  async togglePP() {
    if (!this.av) return;
    this.playbackProfile?.mark(this.play ? 'user-pause' : 'user-play', this.av.currentTime);
    if (this.referencePlaybackCompleted) {
      await this.referenceReplay();
      return;
    }
    // ⭐ seek 在途：seek() 会把 play 临时置 false（用来停掉旧内容），
    //   此时还用 this.play 判断方向会反掉 —— 用户按「暂停」反而起播，看起来就是「点了没反应」。
    //   userPaused_ 才是「用户意图」的唯一真相：按它翻转，并让 seek 收尾尊重这个意图。
    if (this.sg_) {
      const wantPause = !this.userPaused_;
      this.userPaused_ = wantPause;
      this.play = !wantPause;
      try {
        if (wantPause) {
          await this.av.pause();
          await this.avAudio?.pause();
        } else {
          this.markAutoPlay('togglePP-seek-play');
          await this.av.play();
          await this.avAudio?.play();
        }
      } catch (_e) { }
      this.rampAudio_(1, 0);
      LiveViewHelper.updatePlayState(this.play);
      this.cancelDelayHide();
      if (this.cv) this.resetCT();
      return;
    }
    if (this.play) {
      this.userPaused_ = true;    // 用户主动暂停
      await this.av.pause();
      await this.avAudio?.pause();
      this.play = false;
    } else {
      this.userPaused_ = false;   // 用户主动播放
      this.markAutoPlay('togglePP-play');
      await this.av.play();
      await this.avAudio?.play();
      this.play = true;
    }
    // ⭐ 实况窗：更新播放状态
    LiveViewHelper.updatePlayState(this.play);
    this.cancelDelayHide();
    if (this.cv) this.resetCT();
  }

  /**
   * 速率值 → PlaybackSpeed 枚举索引映射
   * HarmonyOS AVPlayer.setSpeed() 接受枚举整型索引，而非直接浮点值。
   * AVPlaybackSpeed: 0=0.75x, 1=1.0x, 2=1.25x, 3=1.75x, 4=2.0x, 5=0.5x, 6=1.5x, 7=3.0x
   */
  private rateToSpeedIdx(rate: number): number {
    if (rate <= 0.625) return 5;  // 0.5x
    if (rate <= 0.875) return 0;  // 0.75x
    if (rate <= 1.125) return 1;  // 1.0x
    if (rate <= 1.375) return 2;  // 1.25x
    if (rate <= 1.625) return 6;  // 1.5x
    if (rate <= 1.875) return 3;  // 1.75x
    if (rate <= 2.5) return 4;    // 2.0x
    return 7;                     // 3.0x
  }

  async setRate(r: number, sh: boolean = true) {
    if (!this.av) return;
    this.rt = r;
    // ⭐ 弹幕速度跟随播放倍速（官方/PiliPlus：滚动时长 `duration / playbackSpeed`）。
    //   不联动的话 2 倍速播放时弹幕还是 1 倍速的爬行感，与官方明显不同。
    //   ⚠️ 只能改字段、不能整体替换 danmakuConfig 对象（controller/renderer 持有旧引用）。
    this.danmakuConfig.speed = r;
    try {
      const speedIdx: number = this.rateToSpeedIdx(r);
      await this.av.setSpeed(speedIdx);
      await this.avAudio?.setSpeed(speedIdx);
    } catch (e) { }
    this.cancelDelayHide();
    if (this.cv) this.resetCT();
  }

  toggleMute() {
    if (!this.av) return;
    this.mute = !this.mute;
    const v = this.mute ? 0 : this.vol;
    const s = this.av.state;
    if (s === 'prepared' || s === 'playing' || s === 'paused' || s === 'completed') {
      try {
        this.av.setVolume(1.0);
        this.avAudio?.setVolume(1.0);
        this.audioGain_ = 1;
      } catch (e) { }
    }
    this.setSystemVolume(v);
    if (!this.mute) this.vol = v;
    AppStorage.setOrCreate('globalVolume', this.vol);
    AppStorage.setOrCreate('globalMuted', this.mute);
    this.cancelDelayHide();
    if (this.cv) this.resetCT();
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
          if (this.maxVol_ > 0) {
            const sysVol: number = this.volMgr_?.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC) ?? 0;
            this.vol = Math.min(1, Math.max(0, sysVol / this.maxVol_));
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

  toggleLock() {
    this.cancelDelayHide();
    logInfo('[VideoPlayer] toggleLock called, current lk:', this.lk, 'ub:', this.ub, 'cv:', this.cv);
    this.lk = !this.lk;
    logInfo('[VideoPlayer] toggleLock after toggle, new lk:', this.lk);
    if (this.lk) {
      if (this.ct_ !== -1) clearTimeout(this.ct_);
      this.cv = false;
      // 锁定后立即显示解锁按钮5秒钟
      this.ub = true;
      logInfo('[VideoPlayer] Locked: cv=false, ub=true');
      if (this.ubt !== -1) { clearTimeout(this.ubt); this.ubt = -1; }
      this.ubt = setTimeout(() => {
        logInfo('[VideoPlayer] Hide unlock button after 5 seconds');
        this.ub = false;
        this.ubt = -1;
      }, 5000);
      this.sBH($r('app.media.ic_public_unlock'), '已锁定');
    } else {
      this.cv = true;
      this.ub = false;
      logInfo('[VideoPlayer] Unlocked: cv=true, ub=false');
      if (this.ubt !== -1) { clearTimeout(this.ubt); this.ubt = -1; }
      this.resetCT();
      this.sBH($r('app.media.ic_public_lock'), '已解锁');
    }
  }

  toggleBackgroundPlayback() {
    this.bgp = !this.bgp;
    AppStorage.set<boolean>('bgp', this.bgp);
    // 持久化到 Preferences（进程重启后仍保留）
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      preferences.getPreferences(context, 'my_app_settings').then((pref) => {
        pref.put('bgp', this.bgp);
        pref.flush();
      });
    } catch (e) {
      logError('[bgp] 持久化保存失败', e);
    }
    this.sBH($r('app.media.headphones_fill'), this.bgp ? '后台播放已开启' : '后台播放已关闭');
    this.cancelDelayHide();
    if (this.cv) this.resetCT();
  }

  // ⭐ 长按文本选取弹窗内容（可选中 → 复制/搜索）
  @Builder
  textSelectDialog(title: string, text: string) {
    TextSelectionDialog({
      title: title,
      text: text,
      onSearchText: (keyword: string) => {
        if (this.textSelectDialogId_ >= 0) {
          this.getUIContext().getPromptAction().closeCustomDialog(this.textSelectDialogId_);
          this.textSelectDialogId_ = -1;
        }
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/SearchPage',
          params: { keyword: keyword }
        }).catch((err: Error) => {
          logWarn(`[VideoPlayer] 搜索页跳转失败: ${errMsg(err)}`);
        });
      }
    })
  }

  /** 打开文本选取弹窗（long press 用） */
  private showTextSelection(title: string, text: string) {
    if (!text || text.length === 0) return;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.textSelectDialog(title, text);
      },
      autoCancel: true,
      // ⭐ 沉浸光感（官方"对话框通道"）：THICK 玻璃 + 无光效（复用面板材质配置）
      backgroundColor: Color.Transparent,
      systemMaterial: MaterialUtil.sheetMaterial()
    }).then((id: number) => {
      this.textSelectDialogId_ = id;
    }).catch((err: Error) => {
      logWarn(`[VideoPlayer] 文本弹窗打开失败: ${errMsg(err)}`);
    });
  }

  /** 超时兜底辅助（Promise.race 用，避免 await 永久悬挂） */
  private delayMs_(ms: number): Promise<void> {
    return new Promise<void>(resolve => setTimeout(resolve, ms));
  }

  /**
   * 音频增益淡变（0↔1）。
   *
   * 为什么需要：seek 必须 pause → seek → play，而直接 pause 会把音频输出截断在
   * 半个波形上、直接 play 又从任意采样点起振，两次都会「啪」一声。连续快进快退时
   * 每轮都爆一下，听起来就是一串爆音。在掐断前用 ~40ms 淡出、起播后 ~120ms 淡入，
   * 把这两次跳变都变成听不见的斜坡。
   *
   * 目标只有 0 和 1；令牌（audioFadeToken_）保证后一次淡变立刻作废前一次的步进 ——
   * 否则连续 seek 时两条 ramp 会互相把音量推到中间值，反而更响。
   *
   * 取 `avAudio ?? av`：DASH 双流的音频在 avAudio 上，IJK/单流播放器的音频在 av 上
   * （AVPlayer.setVolume 只作用于音频轨，画面亮度不受影响）。
   */
  private rampAudio_(to: number, ms: number): void {
    const p = this.avAudio ?? this.av;
    if (!p || this.mute) return;
    const token = ++this.audioFadeToken_;
    const from = this.audioGain_;
    if (ms <= 0 || Math.abs(to - from) < 0.02) {
      try { p.setVolume(to); } catch (_e) { }
      this.audioGain_ = to;
      return;
    }
    const stepMs = Math.max(1, Math.round(ms / 6));
    const steps = Math.max(2, Math.round(ms / stepMs));
    let i = 0;
    const tick = (): void => {
      if (token !== this.audioFadeToken_) return;
      i++;
      const gain = from + (to - from) * (i / steps);
      try { p.setVolume(gain); } catch (_e) { }
      this.audioGain_ = gain;
      if (i < steps) setTimeout(tick, stepMs);
      else logInfo(`[VideoPlayer] audio ramp → ${to.toFixed(2)} done`);
    };
    setTimeout(tick, stepMs);
  }

  /**
   * 跳转到指定位置。
   * @param v    目标秒数
   * @param rs   完成后是否重置控制栏自动隐藏计时
   * @param fast 交互路径（点/拖进度条、手势松手）：SEEK_CLOSEST + 更短的等待上限。
   *             音画微偏差交给 syncAudioVideo 与"按实际帧对齐音频"兜底。
   *
   * 关键约束（都是实测踩出来的，改之前先看注释）：
   * 1. 单流/IJK 不 pause/play —— 停起音频设备就是快进快退那串爆音的来源；
   * 2. 在途 seek 期间**不能补发** seek —— IJK 的 `stream_seek` 会静默丢弃新请求；
   * 3. 被顶掉那次迟到的 seekDone 必须丢弃，否则会把 ct 写成旧位置；
   * 4. 结束前增益一定要回到 1，否则下次起播是"静音播放"。
   */
  async seek(v: number, rs: boolean = true, fast: boolean = false) {
    if (!this.av) return;
    this.floatingPausedFrame = undefined;
    // ⭐ seek 期间可能整条视频被换掉（连刷切换/退出）：后面每个 await 之后都要确认
    //   还是同一个播放器、同一条稿件，否则会把旧片的进度写进新片（续播点被污染），
    //   甚至去 play() 新片、打断交接。
    const seekPlayer = this.av;
    const seekGeneration = this.referenceSwitchGeneration;
    const stillSeeking = (): boolean => this.av === seekPlayer && this.referenceSwitchGeneration === seekGeneration;
    // ⭐ 从「播完」状态拖动进度条：必须先清掉完成标志。
    //   否则 resume 为 false 时不会补 play()，finally 又把 ct 固定回 dur，
    //   表现就是画面跳到了目标帧、时间却停在结尾、重播蒙层不消失（短片的连刷里尤其明显）。
    const wasCompleted = this.referencePlaybackCompleted;
    if (wasCompleted) {
      this.referencePlaybackCompleted = false;
      // 显式 seek（含重播/循环归零）之后不再算「播完后的异常起播」。
      this.playbackCompletedAt_ = 0;
      this.cv = false;
    }
    // ⭐ 连拖合并（last-wins）：seek 在途时只记目标，由**在途那一次**跑完后立刻改打最新目标。
    //   ⚠️ 绝不能在这里再发一次 seek：IJK 的 `stream_seek` 是 `if (!is->seek_req) {...}`，
    //   进行中的 seek 还没被读线程取走时，新请求会被**静默丢弃**。
    //   实测 5 次连点各发一次 → 只有第一次(174s)生效，最后停在 2:54 而不是用户点的 6:19。
    if (this.sg_) {
      this.pendingSeekTarget_ = v;
      this.ct = v;
      this.bufferedUntil = v;
      this.videoSeekPosition = -1;
      this.seekProgressPending = true;
      this.seekExpectedPosition = v;
      this.seekFastMode_ = fast;
      logInfo(`[VideoPlayer] seek merge → ${v.toFixed(2)}s（等在途 seek 落地后再打）`);
      return;
    }
    logInfo(`[VideoPlayer] seek start ${v.toFixed(2)}s fast=${fast} audio=${this.avAudio !== null}`);
    // 用户手动 seek 时取消自动声画同步
    this.cancelVideoSpeedSync();
    this.ct = v;
    this.bufferedUntil = v;
    this.videoSeekPosition = -1;
    this.seekProgressPending = true;
    this.seekExpectedPosition = v;
    this.seekFastMode_ = fast;
    this.sg_ = true;
    this.sk_ = true;
    const seekAudio = this.avAudio;
    const resume = this.play || seekPlayer.state === 'playing' || wasCompleted;
    // ⭐ 交互路径收紧等待（原 1500/600/500）：单轮 700ms 已覆盖绝大多数 seekDone，
    //   没回来的直接进入下一轮/由合并循环收口，不再让用户等满一轮超时。
    const videoWait = fast ? 700 : 1500;
    const audioWait = fast ? 250 : 500;
    const renderWait = fast ? 450 : 3000;
    const reseekWait = fast ? 250 : 500;
    // ⭐ 交互 seek 用 SEEK_CLOSEST（跳最近帧）；默认 SEEK_PREV_SYNC 只跳上一关键帧，
    //   长 GOP 片源上会明显"跳不到点"
    const seekMode = fast ? media.SeekMode.SEEK_CLOSEST : media.SeekMode.SEEK_PREV_SYNC;
    let target = v;
    try {
      // ⭐ 只有 DASH 双流（avAudio 是独立实例）才需要"暂停 → 各自 seek → 再起播"。
      //   单流/ IJK 播放器**绝不 pause**：
      //     1) 音频输出设备停/起各一次，就是快进快退时那串「啪」的爆音（淡变只能压住一部分）；
      //     2) pause 之后要等 seekDone 才 play，中间是真空静音 + 整段延迟；
      //     3) IJK 在播放中 seek 本来就会自己冲刷重解码，pause 纯属多余。
      if (resume && seekAudio) {
        // 淡出 40ms 再停：直接把音频缓冲截断在半波上就是那声「啪」
        this.rampAudio_(0, 40);
        await this.delayMs_(40);
        if (!stillSeeking()) return;
        await Promise.all([seekPlayer.pause(), seekAudio.pause()]);
        if (!stillSeeking()) return;
        this.play = false;
      } else if (resume) {
        // ⭐ 单流（IJK）不暂停，但 seek 会清空音频缓冲、从任意采样点接续，半波截断照样会「啪」。
        //   所以这里只把增益淡出 40ms 再发 seek，落地后淡入 —— 不换设备、不留静音间隙。
        this.rampAudio_(0, 40);
        await this.delayMs_(40);
        if (!stillSeeking()) return;
      }
      // ⭐ 合并循环：每轮**等这一次真的落地**（seekDone 或超时）再改打最新目标。
      //   在途时补发的 seek 会被 IJK 丢掉，所以宁可少发、不能乱发。
      for (let round = 0; round < 4; round++) {
        this.videoSeekResolve_ = null;
        this.audioSeekResolve_ = null;
        let landed = false;
        const videoSeekDone = new Promise<void>(resolve => {
          this.videoSeekResolve_ = (): void => { landed = true; resolve(); };
        });
        const audioSeekDone = seekAudio ? new Promise<void>(resolve => { this.audioSeekResolve_ = resolve; }) : undefined;
        seekPlayer.seek(target * 1000, seekMode);
        seekAudio?.seek(target * 1000);
        // Wait for paused/completed seeks too, before saving the actual position or replaying.
        // 第 2 轮起放宽：此时大概率是在等上一次真正落位，催太紧只会把 seek 丢掉。
        await Promise.race([videoSeekDone, this.delayMs_(round === 0 ? videoWait : videoWait + 500)]);
        if (!stillSeeking()) return;
        if (audioSeekDone) {
          await Promise.race([audioSeekDone, this.delayMs_(audioWait)]);
          if (!stillSeeking()) return;
        }
        this.videoSeekResolve_ = null;
        this.audioSeekResolve_ = null;
        const next = this.pendingSeekTarget_;
        this.pendingSeekTarget_ = -1;
        if (next >= 0 && Math.abs(next - target) > 0.05) {
          target = next;
          this.ct = next;
          this.bufferedUntil = next;
          this.videoSeekPosition = -1;
          this.seekExpectedPosition = next;
          // ⭐ 上一轮是超时收的（seekDone 没回来）说明读线程可能还在处理它；IJK 会丢掉
          //   这期间的新 seek。留一拍让它先清掉 seek_req，再打最新目标 —— 否则最后这一下
          //   会被丢掉，画面停在旧目标上（实测 5 连点停在第一次点的时间）。
          if (!landed) {
            await this.delayMs_(200);
            if (!stillSeeking()) return;
          }
          continue;
        }
        break;
      }
      // 视频已被换掉：不要再 play 新片、更不要拿旧片的进度写新片的续播点。
      if (!stillSeeking()) return;
      // 单流：seek 已落地，把增益淡回来（150ms 斜坡，避免从 0 直接跳到 1 又是一下「啪」）
      if (!seekAudio) this.rampAudio_(1, 150);
      // ⭐ resume 是进入 seek 那一刻的意图；用户在这期间按了暂停必须以 userPaused_ 为准，
      //   否则收尾的 play() 会把用户的暂停操作吃掉（现象就是「点了暂停没反应」）。
      // ⭐ 单流播放器在播时**根本不需要再 play()**：刚才没停过，多调一次只会多一次状态跳变。
      //   只有「停在片尾 / 之前被暂停 / DASH 被主动 pause 过」才需要补。
      // ⚠️ 但**落在片尾例外**：等待 seek 落地的这段时间里播放器可能已经走到 completed，
      //   上面「state !== playing」就会把它当成「被暂停过」而补发 play() ——
      //   AVPlayer/IJK 都会从片头重播，表现就是「视频播完了，声音又从头开始」（实测可复现）。
      const endedAtEof: boolean = seekPlayer.state === 'completed' ||
        (this.dur > 0 && target >= this.dur - 1.5);
      const needPlay = resume && !this.userPaused_ && !endedAtEof &&
        (seekAudio !== null || wasCompleted || seekPlayer.state !== 'playing');
      if (needPlay) {
        this.markAutoPlay('seek-need-play');
        await seekPlayer.play();
        if (!stillSeeking()) return;
        this.rampAudio_(1, 120);   // 起播后淡入，不 await：不能被淡入拖慢
        // ⭐ 只有 DASH 双流（avAudio 是独立实例）才需要等首帧、再把音频对齐到视频实际帧。
        //   IJK/单流播放器的音画在同一个实例里，seek 后继续播已经同步；
        //   再等 450~3000ms 纯属白等（实测占快拖链路约 40%）。
        //   与初始进度路径（initialProgress_）同一套已验证逻辑。
        if (seekAudio) {
          const startRenderFrameDone = new Promise<void>(resolve => { this.startRenderFrameResolve_ = resolve; });
          await Promise.race([startRenderFrameDone, this.delayMs_(renderWait)]);
          if (this.startRenderFrameResolve_) {
            this.startRenderFrameResolve_ = null;  // 超时未触发时清理，避免悬挂
          }
          if (!stillSeeking()) return;
          const actualPos: number = seekPlayer.currentTime;
          if (Math.abs(actualPos - target * 1000) > 120) {
            logInfo(`[VideoPlayer] seek后按实际帧对齐音频: 目标=${target * 1000}ms, 实际=${actualPos}ms`);
            const audioReseekDone = new Promise<void>(resolve => { this.audioSeekResolve_ = resolve; });
            // ⭐ 对齐到视频**实际**帧位置：必须用 SEEK_CLOSEST 精确落点，
            //   默认 SEEK_PREV_SYNC 会退到前一个关键帧，反而在"对齐"这一步又造出偏差
            seekAudio.seek(actualPos, media.SeekMode.SEEK_CLOSEST);
            await Promise.race([audioReseekDone, this.delayMs_(reseekWait)]);
            if (this.audioSeekResolve_) {
              this.audioSeekResolve_ = null;
            }
          }
          await seekAudio.play();
        }
        // A seek to the last frame can complete during the render-frame wait.
        this.play = seekPlayer.state === 'playing';
      }
    } catch (_e) {
      // 中途异常（seek 抛错/播放器被释放）：绝对不能把增益停在 0，否则下次起播是"静音"
      this.rampAudio_(1, 0);
    } finally {
      logInfo(`[VideoPlayer] seek end target=${target.toFixed(2)}s landed=${this.videoSeekPosition.toFixed(2)}s gain=${this.audioGain_.toFixed(2)}`);
      this.videoSeekResolve_ = null;
      this.audioSeekResolve_ = null;
      this.sg_ = false;
      this.sk_ = false;
      // 换片之后的善后不能落在新片上：同一个 av + 同一代际才回写进度。
      const sameVideo = stillSeeking();
      const pending = this.pendingSeekTarget_;
      this.pendingSeekTarget_ = -1;
      if (pending < 0) {
        if (sameVideo && seekPlayer.state !== 'error' && this.videoSeekPosition >= 0 && target < this.dur - 1) {
          this.seekProgressPending = false;
          // Playback can reach EOF while the seek's render-frame wait is still pending.
          // Do not erase the completed callback's replay state when that wait unwinds.
          // 但只在「确实落在片尾」时才认这个状态：否则 seek 之后 state 还是旧的 completed，
          // 会把 ct 又固定回 dur，进度条看起来没动。
          const endedDuringSeek = seekPlayer.state === 'completed' && target >= this.dur - 1.5;
          this.referencePlaybackCompleted = endedDuringSeek;
          // currentTime can still contain the pre-seek value inside seekDone.
          this.ct = endedDuringSeek ? this.dur : Math.max(0, this.videoSeekPosition);
          // ⭐ 本地进度即时写；云端心跳由 saveWatchHistory 内部按 3 秒节流
          //   （连续快进快退不再一次 seek 一个请求，见该方法注释）
          this.saveWatchHistory();
        }
      } else if (sameVideo && Math.abs(pending - target) > 0.05) {
        // 合并循环到上限仍有排队目标（极少见）：延后一拍再提交，避免在 finally 内递归重入
        setTimeout(() => {
          if (this.av === seekPlayer && !this.sg_) this.seek(pending, rs, fast);
          else this.sk_ = false;
        }, 0);
      }
      // ⭐ 淡出后没能恢复播放（被换片 / 用户暂停 / 落在片尾 / 中途异常）：增益必须回到 1，
      //   否则下一次起播是「静音播放」，看起来像音频坏了。
      //   正在播放时交给 play 之后的淡入收尾，这里不抢。
      if (this.audioGain_ < 0.99 && (!sameVideo || this.userPaused_ || seekPlayer.state !== 'playing')) {
        this.rampAudio_(1, 0);
      }
      // ⭐ seek 刚完成：重置同步节流，避免 syncAudioVideo 在视频 currentTime 稳定前
      // 读到旧值并把音频 seek 回错误位置
      this.lastSyncTime_ = Date.now();
    }
    this.cancelDelayHide();
    if (rs && this.cv) this.resetCT();
  }

  applyFSResistance(raw: number): number {
    const c = Math.max(0, Math.min(1, raw));
    // ⭐ 重阻尼：幂次 1.5，初段明显拖不动、越拉越重（下拉关灯与右滑全屏共用此曲线）
    return Math.min(1, Math.pow(c, 1.5));
  }

  private fireHaptic(durationMs: number = 15) {
    try {
      VibrateUtils.vibrateTime(durationMs);
    } catch (e) { }
  }

  updateFSPanProgress(raw: number) {
    const resisted = this.applyFSResistance(raw);
    this.fsPanProgress = resisted;
    if ((this.fsHapticPrev < 0.62 && resisted >= 0.62) ||
      (this.fsHapticPrev >= 0.62 && resisted < 0.62)) {
      this.fireHaptic(18);
    }
    this.fsHapticPrev = resisted;
  }

  async startFSAnimation() {
    if (this.fs || this.isAnimatingToFS) return;
    if (!this.isLs && this.ar < 1) { this.fsPanProgress = 0; return; }
    if (this.fsAnimTimer_ !== -1) {
      clearTimeout(this.fsAnimTimer_);
      this.fsAnimTimer_ = -1;
    }
    // ⭐ 快照当前内容分支：fs 期间冻结渲染该分支，避免旋转切分支导致重挂载+解码风暴
    this.snapshotPreFsBranch();
    // ⭐ 快照插值起点（进入前的槽矩形，须在旋转开始前捕捉）
    this.captureFSSnapshot();
    this.fsEntering = true;
    this.fsHapticPrev = 0;
    if (this.referenceLayout && !this.isPcDevice && (this.ar >= 1) !== this.isLs &&
      (!this.fsAnimOn || this.fsPanProgress >= 0.62)) {
      this.isAnimatingToFS = true;
      await this.rotateReferenceFullscreen(true);
      return;
    }
    // ⭐ 'none' 模式：瞬时切换，无过渡动画
    if (!this.fsAnimOn) {
      await this.prepareFullscreenEnvironment();
      this.pcSyncLayoutToFs(true);  // ⭐ PC：窗口内全屏
      this.fs = true;
      this.fsPanProgress = 1;  // ⭐ 瞬时切换也须置全屏进度，否则视频区域仍按非全屏尺寸渲染
      this.fsEntering = false;  // ⭐ 必须重置，否则 ovRectW/ovVideoW 持续返回快照值卡在非全屏
      this.updateVideoSize();  // ⭐ 全屏尺寸重算（黑板常挂载后不再有 onAreaChange 触发）
      this.isAnimatingToFS = false;
      if (this.mw) this.manageSB(true);
      return;
    }
    this.isAnimatingToFS = true;
    const reached = this.fsPanProgress >= 0.62;
    if (reached) {
      // ⭐ 等待系统旋转完成后再翻转全屏（和点击全屏一致）
      await this.prepareFullscreenEnvironment();
      this.fsEntering = false;
      this.pcSyncLayoutToFs(true);  // ⭐ PC：窗口内全屏
      // ⭐ 从当前手势位置继续动画到全屏(不重置fsPanProgress避免详情卡闪现)
      this.fsLerpStartP = this.fsPanProgress;
      this.fsLerpDir = 1;
      this.fs = true;
      this.updateIsLandscapeVertical();
      this.updateVideoSize();  // ⭐ 全屏尺寸重算（黑板常挂载后不再有 onAreaChange 触发）
      this.refreshSafeAreaLeft();
      if (this.mw) this.manageSB(true);
      logInfo(`[FSDBG] enter(gesture): fs=true P=${this.fsPanProgress} dir=${this.fsLerpDir} ovVideo=(${this.ovVideoW().toFixed(1)},${this.ovVideoH().toFixed(1)}) ovRect=(${this.ovRectW().toFixed(1)},${this.ovRectH().toFixed(1)}) animDur=${this.FS_ANIM_DURATION} da=${this.da}`);
      animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.FS_ANIM_DURATION, curve: Curve.FastOutSlowIn }, () => {
        this.fsPanProgress = 1;
      });
      this.fsAnimTimer_ = setTimeout(() => {
        this.isAnimatingToFS = false;
        this.fsAnimTimer_ = -1;
      }, this.FS_ANIM_DURATION);
      return;
    }
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      duration: 700,
      curve: curves.springCurve(0.08, 1.3, this.FS_SPRING_STIFFNESS, 10)
    }, () => {
      this.fsPanProgress = 0;
      this.isAnimatingToFS = false;
      this.fsAnimTimer_ = -1;
    });
  }

  /** ⭐ PC/2in1：无旋转回调，手动切换布局方向（fsOn=true 进入横屏全屏，false 恢复进入前方向） */
  private pcSyncLayoutToFs(fsOn: boolean): void {
    if (!this.isPcDevice) return;
    if (fsOn) {
      this.pcPreFsIsLs = this.isLs;
      this.isLs = true;
    } else {
      this.isLs = this.pcPreFsIsLs;
    }
    this.updateIsLandscapeVertical();
  }

  // ⭐ 预准备多窗口横屏环境（配合 preferMultiWindowOrientation: landscape_auto）
  private fullscreenTargetLandscape(): boolean {
    // 横屏半屏进入全屏时保留窗口方向，不能按竖片比例转回竖屏。
    return this.ar >= 1 || (this.referenceLayout && (this.fullscreenSource?.isLandscape ?? this.isLs));
  }

  private async prepareFullscreenEnvironment(): Promise<void> {
    if (!this.mw || this.isPcDevice) return;  // ⭐ PC：窗口不旋转，跳过旋转准备（窗口内全屏）
    try {
      // 告知系统应用进入横屏全屏播放状态（小窗模式下将切换为横向悬浮窗）
      await this.mw.enableLandscapeMultiWindow();
      // 设置方向为横屏（允许横屏间旋转）
      await this.mw.setPreferredOrientation(
        this.fullscreenTargetLandscape() ? window.Orientation.AUTO_ROTATION_LANDSCAPE
                     : window.Orientation.AUTO_ROTATION_PORTRAIT
      );
    } catch (_e) {
      logError('prepareFullscreenEnvironment 失败', _e);
    }
  }

  // ⭐ 退出全屏后恢复系统栏、屏幕方向和多窗口横屏状态
  private async restoreOrientationAndBars(): Promise<void> {
    await this.restoreOrientationOnly();
    if (this.mw) {
      this.manageSB();
    }
  }

  // ⭐ 仅恢复屏幕方向和多窗口横屏状态（不管理状态栏），用于退出全屏动画期间提前执行
  private async restoreOrientationOnly(): Promise<void> {
    if (!this.mw || this.isPcDevice) return;  // ⭐ PC：无旋转概念，跳过恢复
    try {
      // 告知系统退出横屏全屏播放状态（小窗恢复为竖向悬浮窗）
      await this.mw.disableLandscapeMultiWindow();
      if (this.referenceLayout && this.fullscreenSource) {
        const sourceOrientation = this.fullscreenRotationTransition
          ? (this.fullscreenSource.isLandscape ? window.Orientation.AUTO_ROTATION_LANDSCAPE : window.Orientation.PORTRAIT)
          : this.fullscreenSource.orientation;
        await this.mw.setPreferredOrientation(sourceOrientation);
        return;
      }
      const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
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
      if (lock === '锁定竖屏') {
        this.isLs = false;
        this.isLandscapeVertical = false;
      }
      await this.mw.setPreferredOrientation(orientation);
    } catch (_e) {}
  }

  private restoreFullscreenSource(): void {
    const source = this.fullscreenSource;
    if (!source || !this.referenceLayout) return;
    this.referenceFeed = source.feed;
    this.referenceFeedProgress = source.feedProgress;
    this.referenceFeedComments = source.feedComments;
    this.referenceInfoHidden = source.infoHidden;
    this.referencePanelOffset = source.panelOffset;
  }

  /** Window orientation APIs resolve before the viewport changes. Wait for the actual layout. */
  private async waitForFullscreenViewport(landscape: boolean): Promise<boolean> {
    let stableSince = 0;
    for (let attempt = 0; attempt < 100; attempt++) {
      const matches = this.cw > 0 && this.ch > 0 && (this.cw > this.ch) === landscape && this.isLs === landscape;
      if (matches && !this.rotationInProgress) {
        if (stableSince === 0) stableSince = Date.now();
        if (Date.now() - stableSince >= 80) return true;
      } else stableSince = 0;
      await new Promise<void>(resolve => setTimeout(resolve, 20));
    }
    return false;
  }

  /** Commit at the destination layout callback, so no intermediate portrait fullscreen/feed is rendered. */
  private commitFullscreenRotationLayout(): void {
    if (!this.fullscreenRotationTransition || this.fullscreenRotationTarget !== this.isLs ||
      (this.cw > this.ch) !== this.fullscreenRotationTarget) return;
    if (!this.fullscreenRotationEntering) this.restoreFullscreenSource();
    this.fs = this.fullscreenRotationEntering;
    this.fsPanProgress = this.fullscreenRotationEntering ? 1 : 0;
    this.fsLerpDir = 0;
    this.fsEntering = false;
    this.updateIsLandscapeVertical();
    this.updateVideoSize();
    if (!this.fs) this.initOverlayRectSync();
  }

  /** Let the system own rotation; a second rectangle animation after rotation causes jumps. */
  private async rotateReferenceFullscreen(entering: boolean): Promise<void> {
    const target = entering ? this.fullscreenTargetLandscape() : (this.fullscreenSource?.isLandscape ?? false);
    this.fullscreenRotationTransition = true;
    this.fullscreenRotationEntering = entering;
    this.fullscreenRotationTarget = target;
    this.fsEntering = true;
    this.fsLerpDir = 0;
    logInfo(`[FSDBG] native rotation begin entering=${entering} sourceFeed=${this.fullscreenSource?.feed} targetLandscape=${target}`);
    try {
      if (entering) {
        this.fs = true;
        this.fsPanProgress = 1;
        await this.prepareFullscreenEnvironment();
      } else {
        this.resetFullscreenVideo();
        await this.restoreOrientationOnly();
      }
      const ready = await this.waitForFullscreenViewport(target);
      if (ready) {
        this.commitFullscreenRotationLayout();
        if (!entering && this.mw && this.fullscreenSource) {
          await this.mw.setPreferredOrientation(this.fullscreenSource.orientation);
        }
      } else {
        logWarn('[FSDBG] viewport rotation timed out; retain current orientation and restore source layout');
        this.restoreFullscreenSource();
        this.fs = false;
        this.fsPanProgress = 0;
      }
      if (this.mw) this.manageSB(true);
    } finally {
      this.fsEntering = false;
      this.fullscreenRotationTarget = null;
      this.fullscreenRotationTransition = false;
      this.fsLerpDir = 0;
      this.isAnimatingToFS = false;
      logInfo(`[FSDBG] native rotation end fs=${this.fs} feed=${this.referenceFeed} progress=${this.referenceFeedProgress} viewport=${this.cw}x${this.ch}`);
    }
  }

  // ⭐ 带动画进入全屏（常驻层几何插值，surface 不重建）
  private async enterFullscreenAnimated(): Promise<void> {
    if (this.fs || this.isAnimatingToFS) return;
    if (!this.isLs && this.ar < 1) return;
    this.isAnimatingToFS = true;
    if (this.fsAnimTimer_ !== -1) {
      clearTimeout(this.fsAnimTimer_);
      this.fsAnimTimer_ = -1;
    }
    if (!this.mw) { this.isAnimatingToFS = false; return; }

    // ⭐ 快照当前内容分支：fs 期间冻结渲染该分支，避免旋转切分支导致重挂载+解码风暴
    this.snapshotPreFsBranch();
    // ⭐ 快照插值起点（进入前的槽矩形，须在旋转开始前捕捉）
    this.captureFSSnapshot();
    this.fsEntering = true;
    if (this.referenceLayout && !this.isPcDevice && this.fullscreenTargetLandscape() !== this.isLs) {
      await this.rotateReferenceFullscreen(true);
      return;
    }
    // ⭐ 等待系统环境准备完成（旋转、状态栏），避免旋转黑帧泄露
    await this.prepareFullscreenEnvironment();
    this.fsEntering = false;
    this.fsLerpStartP = 0;
    // ⭐ PC：无旋转回调 → 手动切横屏布局（窗口内全屏）
    this.pcSyncLayoutToFs(true);

    // ⭐ 动画关闭：瞬时切换，无过渡动画
    if (!this.fsAnimOn) {
      this.fs = true;
      this.updateIsLandscapeVertical();
      this.updateVideoSize();  // ⭐ 全屏尺寸重算（黑板常挂载后不再有 onAreaChange 触发）
      this.fsPanProgress = 1;
      this.isAnimatingToFS = false;
      return;
    }

    // ⭐ 翻转全屏状态：常驻层从快照矩形连续缩放平移至全屏矩形（统一动画，无 surface 重建）
    this.fsLerpDir = 1;
    this.fs = true;
    this.updateIsLandscapeVertical();
    this.updateVideoSize();  // ⭐ 全屏尺寸重算（黑板常挂载后不再有 onAreaChange 触发）
    logInfo(`[FSDBG] enter(click): fs=true P=${this.fsPanProgress} dir=${this.fsLerpDir} ovVideo=(${this.ovVideoW().toFixed(1)},${this.ovVideoH().toFixed(1)}) ovRect=(${this.ovRectW().toFixed(1)},${this.ovRectH().toFixed(1)}) animDur=${this.FS_ANIM_DURATION} da=${this.da}`);

    if (this.da) {
      this.fsPanProgress = 1;
      this.isAnimatingToFS = false;
      return;
    }

    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.FS_ANIM_DURATION, curve: Curve.FastOutSlowIn }, () => {
      this.fsPanProgress = 1;
    });

    // 动画结束后清理动画状态
    await new Promise<void>(resolve => {
      this.fsAnimTimer_ = setTimeout(() => {
        this.isAnimatingToFS = false;
        this.fsAnimTimer_ = -1;
        resolve();
      }, this.FS_ANIM_DURATION);
    });
  }

  // ⭐ 退出全屏（优化：先动画驱动 fsPanProgress，再切换布局避免 XComponent 闪黑）
  private async exitFullscreenAnimated(): Promise<void> {
    if (!this.fs || this.isAnimatingToFS) return;
    this.isAnimatingToFS = true;
    if (this.fsAnimTimer_ !== -1) {
      clearTimeout(this.fsAnimTimer_);
      this.fsAnimTimer_ = -1;
    }
    if (!this.mw) { this.isAnimatingToFS = false; return; }

    // ⭐ 弹窗瞬间关闭
    this.icp = true;
    this.sp = false;
    this.qp = false;
    this.mp = false;
    this.mpb = false;
    this.cacheQnPopup = false;
    this.colorStylePopup = false;
    this.cp = false;
    this.ip = false;
    this.showEpisodeSheet = false;
    setTimeout(() => { this.icp = false; }, 0);
    if (this.cv) this.resetCT();

    if (this.referenceLayout && !this.isPcDevice && this.fullscreenSource &&
      this.fullscreenSource.isLandscape !== this.isLs) {
      this.captureFSSnapshot();
      await this.rotateReferenceFullscreen(false);
      return;
    }

    // ⭐ 动画关闭：瞬时切换，无过渡动画
    if (!this.fsAnimOn) {
      this.fsPanProgress = 0;  // ⭐ 复位全屏进度，避免非全屏布局读到残值
      this.restoreOrientationOnly();
      this.fs = false;
      this.pcSyncLayoutToFs(false);  // ⭐ PC：恢复进入前布局方向
      this.updateIsLandscapeVertical();
      this.updateVideoSize();  // ⭐ 恢复非全屏视频尺寸（fs 期间被全屏 fit 覆盖）
      await new Promise<void>(resolve => {
        setTimeout(() => {
          if (this.mw) this.manageSB();
          this.isAnimatingToFS = false;
          this.fsAnimTimer_ = -1;
          resolve();
        }, 50);
      });
      return;
    }

    // ⭐ 快照全屏插值起点 → 提前旋转窗口 → 等旋转稳定 → 视频连续缩放平移回槽矩形
    this.captureFSSnapshot();
    this.fsLerpDir = 2;
    logInfo(`[FSDBG] exit: dir=2 P=${this.fsPanProgress} ovVideo=(${this.ovVideoW().toFixed(1)},${this.ovVideoH().toFixed(1)}) ovRect=(${this.ovRectW().toFixed(1)},${this.ovRectH().toFixed(1)}) plateVis=${this.fs && this.fsLerpDir !== 2}`);
    await this.restoreOrientationOnly();
    // ⭐ 等旋转完成再开始几何插值（旋转期间视频随窗口旋转持续渲染，无黑屏）
    await this.waitRotationStable();
    // ⭐ PC：无旋转 → 提前恢复进入前布局方向，使插值目标矩形按原布局计算
    this.pcSyncLayoutToFs(false);
    // ⭐ 恢复非全屏视频尺寸（fs 期间 videoDisplayWidth 被全屏 fit 覆盖，退出插值目标需要竖屏尺寸）
    if (!this.isLs) {
      this.updatePortraitSize();
    } else {
      // ⭐ 横屏退出：动画开始前刷新 lsvw/lsvh 为恢复后窗口的目标值——
      //    否则动画终点沿用旧值，fs=false 后 XComponent 跳到新 lsvw → 末帧又"缩一下"
      this.updateLSVSize();
      // ⭐ 退出全屏到横屏时，提前设置目标 ov 值——动画期间 ovRectX/ovRectW 用 ovX/ovW 插值，
      //    若沿用旧值（进入前竖屏portrait的ovX），动画终点与fs=false后initOverlayRectSync跳变
      if (this.ar < 1) {
        this.ovW = this.lsvw; this.ovH = this.lsvh;
        this.ovX = this.isLayoutSwapped ? (this.cw - this.lsvw - 80 - this.cardMargin) : (80 + this.cardMargin);
        this.ovY = this.cardMargin;
      } else {
        this.ovW = this.lsvw; this.ovH = this.lsvh;
        this.ovX = this.isLayoutSwapped ? (this.cw - this.lsvw - this.cardMargin) : this.cardMargin;
        this.ovY = this.cardMargin;
      }
    }
    logInfo(`[FSDBG] exit: rotation stable, start lerp P=${this.fsPanProgress} animDur=${this.FS_ANIM_DURATION} da=${this.da} plateVis=${this.fs && this.fsLerpDir !== 2} ovRect=(${this.ovRectW().toFixed(1)},${this.ovRectH().toFixed(1)})`);
    if (this.da) {
      this.fsPanProgress = 0;
    } else {
      animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.FS_ANIM_DURATION, curve: Curve.FastOutSlowIn }, () => {
        this.fsPanProgress = 0;
      });
    }
    await new Promise<void>(resolve => {
      this.fsAnimTimer_ = setTimeout(() => {
        this.fs = false;
        this.fsLerpStartP = 0;
        this.updateIsLandscapeVertical();
        this.updateVideoSize();  // ⭐ 恢复非全屏视频尺寸（fs 期间被全屏 fit 覆盖）
        // ⭐ 同步重算占位槽矩形：避免 fs=false 后 onAreaChange 异步更新 ovW/ovH 造成末帧几何跳变
        this.initOverlayRectSync();
        this.fsLerpDir = 0;
        logInfo(`[FSDBG] exit: fs=false P=${this.fsPanProgress} plateVis=${this.fs && this.fsLerpDir !== 2} ovRect=(${this.ovRectW().toFixed(1)},${this.ovRectH().toFixed(1)}) ovVideo=(${this.ovVideoW().toFixed(1)},${this.ovVideoH().toFixed(1)})`);
        // 恢复系统栏（屏幕方向已在提前阶段恢复）
        if (this.mw) this.manageSB();
        this.isAnimatingToFS = false;
        this.fsAnimTimer_ = -1;
        resolve();
      }, this.FS_ANIM_DURATION);
    });
  }

  /** ⭐ 等待旋转完成（rotationInProgress 清除）再开始退出插值；锁定横屏跳过（窗口不旋转） */
  private waitRotationStable(): Promise<void> {
    return new Promise<void>(resolve => {
      if (this.isPcDevice) { resolve(); return; }  // ⭐ PC：无旋转，直接继续
      const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
      if (lock === '锁定横屏') { resolve(); return; }
      const tryCheck = (retries: number): void => {
        if (!this.rotationInProgress || retries <= 0) { resolve(); return; }
        this.fsAnimTimer_ = setTimeout(() => { tryCheck(retries - 1); }, 100);
      };
      tryCheck(15);
    });
  }

  async toggleFS() {
    this.cancelDelayHide();
    // ⭐ 全屏切换会整体改变布局（提示的锚点/尺寸全都按旧布局算的）⇒ 手势提示必须收掉，
    //   而且**在这一刻收**才正确：它的 110ms 淡出与全屏转场同帧启动 = "直接换内容"。
    //   （触摸被系统取消时不清提示、只在这里清 —— 见 onTC 的长注释）
    this.clearGestureHint_();
    if (!this.mw || this.isAnimatingToFS || this.referenceModeAnimating) return;
    // 竖片详情的全屏入口展开为竖屏连刷；横片继续走普通全屏播放器。
    if (!this.fs && this.referenceLayout && !this.isLs && this.ar < 1) {
      this.cv = false;
      this.referenceFeedComments = false;
      this.referenceSetFeed(true);
      logInfo('[ReferenceFeed] portrait fullscreen opens continuous mode');
      return;
    }
    if (!this.fs && this.referenceLayout && this.referenceFeed) {
      this.referenceStopFeedMotion();
      this.referenceFeedDragY = 0;
      this.referenceQueuedFeedStep = 0;
      this.referenceVerticalSwipe = false;
      this.referenceFeedPanOwnsTouch = false;
      this.referencePreviewVisible = false;
      this.referenceFeedDragEndResolve?.();
      this.referenceFeedDragEndResolve = null;
      this.referenceInfoHidden = false;
      logInfo('[ReferenceFeed] enter normal fullscreen; feed gestures suspended');
    }
    // ⭐ 全屏控制栏的"上一集/下一集"按钮可见性完全由这两个值决定，日志留痕便于排查
    logInfo(`[VideoPlayer] toggleFS: 分集数=${this.vd?.pages?.length ?? 0}, 当前索引=${this.currentPageIndex}, `
      + `hasNext=${this.hasNextEpisode()}, hasPrev=${this.currentPageIndex > 0}`);
    if (!this.fs) {
      await this.enterFullscreenAnimated();
    } else {
      await this.exitFullscreenAnimated();
    }
  }
  goBack() {
    if (this.commentThread) { this.closeCommentThread(); return; }
    if (this.fs) {
      this.toggleFS().finally(() => setTimeout(() => router.back(), 300));
    } else {
      this.release();
      router.back();
    }
  }

  goHome() {
    AppStorage.setOrCreate<boolean>('goHome', true);
    if (this.fs) {
      this.toggleFS().finally(() => setTimeout(() => router.back({ url: 'pages/Index' }), 300));
    } else {
      this.release();
      router.back({ url: 'pages/Index' });
    }
  }

  private async traceQualityTrack(player: PlaybackPlayer, requested: number, actual: number): Promise<void> {
    try {
      const tracks = await player.getTrackDescription();
      if (this.av !== player) return;
      const video = tracks.find((track: media.MediaDescription) => Number(track['width']) > 0);
      if (!video) return;
      // Numeric track metadata only; never include media URLs or account identifiers.
      hilog.debug(0x0000, 'PlayerQuality', '%{public}s', JSON.stringify({
        requested: requested, actual: actual, width: Number(video['width']),
        // MD_KEY_FRAME_RATE is measured in frames per 100 seconds.
        height: Number(video['height']), fps: Number(video['frame_rate']) / 100
      }));
    } catch (_) { }
  }

  async switchQ(n: number) {
    if (this.qs || n === this.qn) return;
    if (!this.getQlList().some((item: QI) => item.qn === n)) return;
    const old = this.av;
    if (!old || this.waitingForFirstFrame || this.floatingMorph || this.floatingRestoring) return;
    this.qs = true;
    const generation = this.referenceSwitchGeneration;
    const bvid = this.vi.bvid;
    const cid = this.vi.cid;
    const profile = PlaybackStartup.begin('quality-switch');
    const deadline = new PlaybackDeadline(20000);
    this.qualityDeadline_ = deadline;
    profile.mark('requested-quality', n);
    let candidate: QualityPlaybackSession | null = null;
    try {
      this.playbackListPrefetch.pause();
      const result = await deadline.wait(this.isPgc_
        ? getPgcPlayUrl(this.epId_, cid, n, this.seasonId_)
        : getVideoPlayUrl(bvid, cid, n, 0), '获取画质地址');
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== old) return;
      profile.mark('returned-quality', result.actualQn);
      if (!result.url) throw new Error('未获取到播放地址');
      this.applyAcceptQuality(result);
      if (result.actualQn !== n || !canDecodePlayUrl(result)) {
        this.getUIContext().getPromptAction().showToast({
          message: `当前无法播放${this.getQlLabel(n)}，已保留${this.getQlLabel(this.qn)}`, duration: 3000
        });
        return;
      }
      await deadline.wait(this.releaseReferenceFeedPreview(), '释放备用播放器');
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== old) return;
      this.referenceSpareSurfaceMounted = true;
      this.referenceWarmAspectRatio = this.ar;
      for (let i = 0; !this.referencePreviewSurfaceId && i < 60; i++) {
        await deadline.wait(new Promise<void>((resolve) => setTimeout(resolve, 16)), '准备备用画面');
      }
      const surface = this.referencePreviewSurfaceId;
      if (!surface) throw new Error('备用画面未就绪');
      const target = Math.max(0, Math.min(old.duration - 1000,
        old.currentTime + (old.state === 'playing' ? 5000 * this.rt : 0)));
      candidate = new QualityPlaybackSession(bvid, surface, result, target);
      this.qualitySession_ = candidate;
      profile.mark('background-prepare', old.currentTime);
      const prepared = await deadline.wait(candidate.prepare(this.getVideoScaleType(),
        AppStorage.get<string>('biliCookie') || ''), '准备目标画质');
      if (!prepared) throw new Error('目标画质准备失败');
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== old) return;
      profile.mark('candidate-frame-ready', old.currentTime);
      if (!await deadline.wait(candidate.align(old, this.rateToSpeedIdx(this.rt), this.rt), '对齐目标画质')) {
        throw new Error('目标画质进度尚未对齐');
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== old || deadline.isCancelled()) return;
      profile.mark('candidate-aligned', Math.round(candidate.driftMs));
      const handles = candidate.take();
      if (!handles) throw new Error('目标画质交接失败');
      const outgoing: RetiredPlayback = { video: old, audioPlayer: this.avAudio,
        bridge: this.dashBridge_ || this.dashHandle_ };
      // Both Surfaces already contain decoded frames. Only swap their roles after
      // the replacement is aligned; the original kept running throughout prepare.
      this.stopSyncTimer();
      clearTimeout(this.startupFrameTimer_);
      old.setVolume(0);
      this.avAudio?.setVolume(0);
      this.av = handles.video;
      this.avAudio = handles.audioPlayer;
      this.dashBridge_ = handles.bridge;
      this.dashHandle_ = null;
      this.isDashStream_ = handles.bridge !== null;
      const previousSurface = this.sId;
      this.sId = surface;
      this.referenceSecondSurfaceActive = !this.referenceSecondSurfaceActive;
      this.referencePreviewSurfaceId = previousSurface;
      this.waitingForFirstFrame = false;
      this.ld = false;
      this.err = '';
      this.play = handles.video.state === 'playing';
      this.ct = handles.video.currentTime / 1000;
      this.dur = handles.video.duration / 1000;
      this.setupL();
      if (this.avAudio) this.setupAudioL();
      handles.video.setVolume(this.mute ? 0 : 1);
      this.avAudio?.setVolume(this.mute ? 0 : 1);
      this.qn = result.actualQn;
      this.ql = this.getQlLabel(this.qn);
      // 手动切画质只作用于本次会话：后续连刷沿用这一档，但绝不写 defaultVideoQn。
      // defaultVideoQn 是 QualityPreferenceService 按当前链路解析出的生效值，只有设置页里
      // 「Wi-Fi 画质 / 移动网络画质」两个菜单能改，这里写它等于替用户改设置。
      this.preferredQn = n;
      profile.mark('surface-swapped', handles.video.currentTime);
      // Keep the exiting native buffer alive through the Surface role update.
      const retirement = new Promise<void>((resolve) => {
        setTimeout(() => { retirePlayback(outgoing).finally(resolve); }, 100);
      });
      this.referencePreviewReleaseJob = Promise.all([this.referencePreviewReleaseJob, retirement]).then(() => {});
      this.traceQualityTrack(handles.video, n, result.actualQn);
      this.startVideoSpeedSync();
      this.sBH(undefined, this.ql);
    } catch (error) {
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || deadline.isCancelled()) return;
      profile.mark('switch-error');
      logError('[VideoPlayer] background quality preparation failed:', errMsg(error));
      this.getUIContext().getPromptAction().showToast({ message: '目标画质准备失败，已保留当前播放', duration: 3000 });
    } finally {
      await candidate?.release();
      if (this.qualitySession_ === candidate) this.qualitySession_ = null;
      profile.end();
      PlaybackStartup.deactivate(profile);
      if (this.qualityDeadline_ === deadline) {
        this.qualityDeadline_ = null;
        this.qs = false;
        if (this.referenceAlive && generation === this.referenceSwitchGeneration) this.referenceWarmUpcomingFrames();
      }
    }
  }

  private async recoverPlaybackStall(player: PlaybackPlayer | null): Promise<void> {
    if (this.av !== player || !this.referenceAlive || this.initPInProgress_ || this.userPaused_ || this.ry_ || this.qs) return;
    // ⭐ 播完是终态：任何「卡住」判定都不该把已播完的播放器重建 ——
    //    重建后的续播点会按「已完成」算成 0，用户听到的就是「播完了又从头出声」。
    if (this.referencePlaybackCompleted || (player && player.state === 'completed')) {
      logInfo('[VideoPlayer] recoverPlaybackStall 跳过：视频已播完');
      return;
    }
    const key = `${this.referenceSwitchGeneration}:${this.vi.bvid}:${this.vi.cid}`;
    const position = Math.max(0, player ? player.currentTime : Math.round((this.ct || 0) * 1000),
      this.waitingForFirstFrame ? Math.round((this.initialProgress_ || 0) * 1000) : 0,
      this.waitingForFirstFrame ? (this.startupResumeMs_ || 0) : 0);
    // One automatic rebuild per content session. A second stall must be actionable,
    // rather than repeatedly restarting a broken source behind a loading indicator.
    if (this.stallRecoveryKey_ === key) {
      this.playbackProfile?.mark('stall-recovery-exhausted', position);
      this.err = '播放持续卡住，请点击重试';
      this.ld = false;
      this.release().catch(() => {});
      return;
    }
    this.stallRecoveryKey_ = key;
    if (this.waitingForFirstFrame) {
      // 起播源卡住：作废的是「按偏好画质请求」的那条缓存，随后 initP 仍用 preferredQn 重取。
      invalidatePlayUrlCache(this.vi.bvid, this.vi.cid, this.preferredQn);
      this.playbackProfile?.mark('startup-refresh-source');
    }
    this.playbackProfile?.mark('stall-reload', position);
    this.ry_ = true;
    this.err = '';
    this.ld = true;
    this.waitingForFirstFrame = true;
    const generation = this.referenceSwitchGeneration;
    const deadline = new PlaybackDeadline(5000);
    try {
      await deadline.wait(this.release(), '释放卡住的播放器');
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av) return;
      this.stallResumeMs_ = position;
      this.ct = position / 1000;
      await this.initP();
    } catch (error) {
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      this.playbackProfile?.mark('stall-reload-failed');
      this.err = errMsg(error);
      this.ld = false;
    } finally {
      this.ry_ = false;
      if (generation === this.referenceSwitchGeneration) {
        this.stallResumeMs_ = -1;
      }
    }
  }

  private retry() {
    if (this.ry_) return;
    if (this.rc_ >= this.mr_) {
      this.err = '播放失败，已达到最大重试次数';
      this.ld = false;
      return;
    }
    this.ry_ = true;
    this.rc_++;
    this.ld = true;
    this.err = '';
    if (this.rt_ !== -1) clearTimeout(this.rt_);
    this.rt_ = setTimeout(async () => {
      this.rt_ = -1;
      const generation = this.referenceSwitchGeneration;
      await this.release();
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) { this.ry_ = false; return; }
      this.ry_ = false;
      await this.initP();
    }, 1000);
  }

  fmtT = (s: number): string => {
    if (isNaN(s)) s = 0;
    const sec = Math.floor(s);
    const m = Math.floor(sec / 60);
    const rs = sec % 60;
    return `${m.toString().padStart(2, '0')}:${rs.toString().padStart(2, '0')}`;
  }

  fmtTA = (ts: number): string => {
    const d = Math.floor(Date.now() / 1000) - ts;
    if (d < 60) return '刚刚';
    if (d < 3600) return `${Math.floor(d / 60)}分钟前`;
    if (d < 86400) return `${Math.floor(d / 3600)}小时前`;
    if (d < 2592000) return `${Math.floor(d / 86400)}天前`;
    const dt = new Date(ts * 1000);
    return `${dt.getFullYear()}-${(dt.getMonth() + 1).toString().padStart(2, '0')}-${dt.getDate().toString().padStart(2, '0')}`;
  }

  fmtN = (n: number): string => {
    if (n >= 10000) return `${(n / 10000).toFixed(1)}万`;
    return n.toString();
  }

  // 根据播放量返回颜色
  getPlayCountColor = (count: number): string => {
    if (count >= 10000000) return '#FF0000';
    if (count >= 3000000) return '#C2185B';
    if (count >= 1000000) return '#FF8C00';
    if (count >= 100000) return '#FFB800';
    if (count >= 50000) return '#4A90D9';
    return '#999999';
  }

  // 获取 LV 等级背景色
  getLevelBgColor = (level: number): string => {
    switch (level) {
      case 0: return '#9E9E9E';
      case 1: return '#62D560';
      case 2: return '#62D560';
      case 3: return '#40B5FF';
      case 4: return '#FFB800';
      case 5: return '#FF8C00';
      case 6: return '#FF4444';
      default: return '#9E9E9E';
    }
  }

  private updatePortraitSize() {
    const containerWidth = this.cw - 2 * this.cardMargin;
    const containerHeight = this.ch;
    if (containerWidth <= 0 || containerHeight <= 0) return;
    const videoAspect = this.ar || 16 / 9;
    let dw = containerWidth;
    let dh = containerHeight;
    // ⭐ 与横屏一致：容器严格按视频真实宽高比适配（SCALED_ASPECT 自动模式 → 无黑边）
    if (containerWidth / containerHeight > videoAspect) {
      dh = containerHeight;
      dw = containerHeight * videoAspect;
    } else {
      dw = containerWidth;
      dh = containerWidth / videoAspect;
    }
    // 竖屏视频时，限制高度不超过屏幕高度的60%
    if (videoAspect < 1 && dh > containerHeight * 0.6) {
      dh = containerHeight * 0.6;
      dw = dh * videoAspect;
    }
    this.videoDisplayWidth = Math.max(1, dw);
    this.videoDisplayHeight = Math.max(1, dh);
  }

  /** cardMargin 变化时重新计算竖屏视频尺寸 */
  onCardMarginChange(): void {
    if (!this.isLs && !this.fs) {
      this.updatePortraitSize();
    }
  }

  private updateVideoSizeByScaleMode() {
    const containerWidth = this.cw;
    const containerHeight = this.ch;
    if (containerWidth <= 0 || containerHeight <= 0) return;
    const videoAspect = this.ar || 16 / 9;
    let dw = containerWidth;
    let dh = containerHeight;
    switch (this.effectiveScaleMode()) {
      case 'stretch':
        // 拉伸模式：使用完整容器尺寸，不受padding影响
        dw = this.cw;
        dh = this.ch;
        break;
      case 'fill':
        if (containerWidth / containerHeight > videoAspect) {
          dh = containerWidth / videoAspect;
        } else {
          dw = containerHeight * videoAspect;
        }
        break;
      case 'fitHeight':
        dw = containerHeight * videoAspect;
        dh = containerHeight;
        break;
      case 'fitWidth':
        dw = containerWidth;
        dh = containerWidth / videoAspect;
        break;
      default:
        if (containerWidth / containerHeight > videoAspect) {
          dw = containerHeight * videoAspect;
        } else {
          dh = containerWidth / videoAspect;
        }
        break;
    }
    this.videoDisplayWidth = Math.max(1, dw);
    this.videoDisplayHeight = Math.max(1, dh);
  }

  // 根据当前缩放模式获取对应的 VideoScaleType
  private effectiveScaleMode(aspect: number = this.ar): string {
    const continuous = this.referenceLayout && this.referenceFeed && aspect < 1 && !this.isLs &&
      (!this.referenceFeedComments || this.referenceFeedCommentAnimating) && !this.mp;
    if (this.fs) return this.sm;
    // 标准 9:16 允许千分之一的编码取整误差，其余画幅默认完整显示。
    const applies = this.referenceFeedPortraitScaleScope === 'all' || Math.abs(aspect / (9 / 16) - 1) <= 0.001;
    return continuous && applies ? this.referenceFeedPortraitScaleMode : 'auto';
  }

  private onPlaybackViewportChanged(): void {
    if (!this.fullscreenVideoTransformAvailable()) this.resetFullscreenVideo();
    // 抽屉开合动画期间不碰视频缩放：换缩放类型要重配渲染管线，
    // 会与 translate 动画抢渲染线程，动画收尾时再统一生效。
    if (this.referencePortraitSettingsAnimating) return;
    this.applyPlaybackScaleType();
  }

  /** 缩放类型没变就不重设：IJK 每次赋值都要走一遍属性下发，没必要白跑。 */
  private applyPlaybackScaleType(): void {
    if (!this.av) return;
    try {
      const target = this.getVideoScaleType();
      if (this.av.videoScaleType === target) return;
      this.av.videoScaleType = target;
    } catch (_error) { }
  }

  private getVideoScaleType(): media.VideoScaleType {
    switch (this.effectiveScaleMode()) {
      case 'stretch':
        // 拉伸模式：强制拉伸视频至窗口大小，不保持宽高比
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
      case 'fill':
      case 'fitHeight':
        // 填充模式/等高模式：保持宽高比，裁剪填充
        return media.VideoScaleType.VIDEO_SCALE_TYPE_FIT_CROP;
      case 'auto':
      case 'fitWidth':
      default:
        // ⭐ 自动模式：保持宽高比完整显示（与横屏一致，全屏竖屏不再裁剪填充）
        return media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
    }
  }

  private updateVideoSize() {
    if (!this.isLs && !this.fs) { this.updatePortraitSize(); return; }
    if (this.cw <= 0 || this.ch <= 0) return;
    const hPad = (!this.isLs && !this.fs) ? 24 : 0;
    const containerWidth = this.cw - hPad;
    const containerHeight = this.ch;
    const videoAspect = this.ar || 16 / 9;
    let dw = containerWidth;
    let dh = containerHeight;
    switch (this.effectiveScaleMode()) {
      case 'stretch':
        // 拉伸模式：忽略视频宽高比，直接拉伸到容器大小
        dw = this.cw;
        dh = this.ch;
        break;
      case 'fill':
        if (containerWidth / containerHeight > videoAspect) {
          dh = containerWidth / videoAspect;
        } else {
          dw = containerHeight * videoAspect;
        }
        break;
      case 'fitHeight':
        dw = containerHeight * videoAspect;
        dh = containerHeight;
        break;
      case 'fitWidth':
        dw = containerWidth;
        dh = containerWidth / videoAspect;
        break;
      default:
        // ⭐ 自动模式：保持视频真实宽高比完整显示（横屏/竖屏全屏统一，不留裁剪）
        if (containerWidth / containerHeight > videoAspect) {
          dw = containerHeight * videoAspect;
        } else {
          dh = containerWidth / videoAspect;
        }
        break;
    }
    this.videoDisplayWidth = Math.max(1, dw);
    this.videoDisplayHeight = Math.max(1, dh);
  }

  private onCA = (o: Area, n: Area) => {
    const w = n.width as number;
    const h = n.height as number;
    // ⭐ onAreaChange 在布局阶段回调：@State 更新延迟到本帧渲染结束后，避免“渲染中改状态”
    //    框架报错与评论区/详情卡闪烁（onSlotArea/onColumnArea 同理）
    setTimeout(() => {
      const was = this.isLs;
      this.cw = w;
      this.ch = h;
      // ⭐ 横竖屏切换：XComponent 常驻单实例，surface 不再重建，直接切换布局；
      //    rotationInProgress 供退出全屏插值等待旋转完成 + 旋转期间暂停评论头像预解码
      if (w > h !== was) {
        this.rotationInProgress = true;
        this.commentRenderCountFull = this.commentRenderCount;
        this.commentRenderCount = 20;  // 旋转期间降到20：旧分支卸载多余条目，transition退场只淡出20条不卡
        this.applyOrientationState(w, h, was);
        setTimeout(() => {
          this.rotationInProgress = false;
          // 分批恢复累积配额，避免一次性 ForEach 增量挂载 N-20 条卡顿
          const target = this.commentRenderCountFull;
          const step = () => {
            if (this.commentRenderCount < target) {
              this.commentRenderCount = Math.min(this.commentRenderCount + 20, target);
              setTimeout(step, 30);
            }
          };
          step();
        }, 450);
      } else {
        // 尺寸变化但方向未翻转：直接同步更新布局
        this.applyOrientationState(w, h, was);
      }
    }, 0);
  }

  /** 根据新的窗口尺寸更新方向相关布局状态（isLs → build 分支切换） */
  private applyOrientationState(w: number, h: number, was: boolean): void {
    this.isLs = w > h;
    this.commitFullscreenRotationLayout();
    this.updateIsLandscapeVertical();
    // ⭐ force：旋转后重新管理状态栏（全屏 fs=true 时非 force 的 manageSB 直接 return，
    //   旋转会重置系统状态栏显示——force 确保全屏/横屏旋转后仍隐藏状态栏）
    if (this.isLs !== was) this.manageSB(true);
    this.updateVideoSize();
    if (this.isLs) {
      this.updateLSVSize();
      // 切到横屏时恢复视频大小（竖屏评论区上滑的缩小模式不适用于横屏）
      if (this.vidShrink > 0) {
        this.animateVidShrink(0);
      }
    }
    // ⭐ 方向/尺寸变化时重新计算拇指热区位置
    this.recalcSmartGripPosition();
  }

  private resetFullscreenVideo(): void {
    this.fullscreenTransform.reset();
    this.fullscreenVideoScale = 1;
    this.fullscreenVideoAngle = 0;
    this.fullscreenVideoX = 0;
    this.fullscreenVideoY = 0;
  }

  private fullscreenVideoChanged(): boolean {
    return Math.abs(this.fullscreenVideoScale - 1) > 0.001 || Math.abs(this.fullscreenVideoAngle) > 0.1 ||
      Math.abs(this.fullscreenVideoX) > 0.5 || Math.abs(this.fullscreenVideoY) > 0.5;
  }

  private fullscreenVideoTransformAvailable(): boolean {
    return this.fs || (this.referencePortraitFeedActive() && !this.referenceFeedComments);
  }

  private handleFullscreenTransform(e: TouchEvent): boolean {
    if (!this.fullscreenTransformTouch &&
      (!this.fullscreenVideoTransformAvailable() || this.lk || this.ip || this.referenceFeedLoading ||
        this.sliderDragging_ || this.seekBarTouch_ || e.touches.length < 2)) return false;
    if (!this.fullscreenTransformTouch) {
      this.fullscreenTransformTouch = true;
      this.fullscreenTransformClickUntil = Date.now() + 300;
      if (this.referencePortraitFeedActive()) {
        this.referenceStopFeedMotion();
        this.referenceVerticalSwipe = false;
        this.referenceQueuedFeedStep = 0;
        this.referenceFeedDragY = 0;
        this.referencePreviewVisible = false;
        this.referenceFeedPanOwnsTouch = true;
      }
      // Cancel the pending one-finger interaction before taking over the touch stream.
      if (this.sk_) { this.ct = this.st_; this.sk_ = false; }
      this.onTC();
      this.clearGestureHint_();
      this.cancelDelayHide();
      if (this.dt_ !== -1) { clearTimeout(this.dt_); this.dt_ = -1; }
      if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
      this.topAreaTouch_ = false;
    }
    // Up may still include the lifted pointer in touches on some platform versions.
    const remaining = e.type === TouchType.Cancel ? [] : e.touches.filter(touch =>
      e.type !== TouchType.Up || !e.changedTouches.some(changed => changed.id === touch.id));
    if (this.fullscreenVideoTransformAvailable() && !this.lk && remaining.length === 2 && e.type !== TouchType.Up) {
      const points: VideoTransformPoint[] = remaining.map((touch: TouchObject): VideoTransformPoint => ({ id: touch.id, x: touch.windowX, y: touch.windowY }));
      this.fullscreenTransform.update(points, this.ovRectX() + this.ovRectW() / 2, this.ovRectY() + this.ovRectH() / 2);
      this.fullscreenVideoScale = this.fullscreenTransform.scale;
      this.fullscreenVideoAngle = this.fullscreenTransform.angle;
      this.fullscreenVideoX = this.fullscreenTransform.x;
      this.fullscreenVideoY = this.fullscreenTransform.y;
    } else this.fullscreenTransform.end();
    if (remaining.length === 0) {
      this.fullscreenTransformTouch = false;
      this.fullscreenTransformClickUntil = Date.now() + 300;
      this.ml_ = false;
      if (this.fs && !this.lk && this.fullscreenVideoChanged()) this.cv = true;
      if (this.referencePortraitFeedActive() && this.fullscreenVideoChanged()) this.referenceInfoHidden = false;
      if (this.cv) this.resetCT();
    }
    return true;
  }

  private onVT = (e: TouchEvent) => {
    if (this.handleFullscreenTransform(e)) return;
    // ⭐ 进度条交互期间播放器手势必须整体让位。
    //   `sliderDragging_` 覆盖「按下 → 提交」，`seekBarTouch_` 再覆盖「提交 → 手指抬起」那一小段
    //   （提交发生在 onChange 的 End/Click，实测早于 onTouch Up，详见字段注释）。
    //   官方明确"终止冒泡并不会中断父组件对手势的响应处理"，所以父节点的 PanGesture 只能靠
    //   页面侧显式 return 让位（几处 PanGesture 里都加了同样的守卫）。
    if (this.sliderDragging_ || this.seekBarTouch_) {
      // ⭐ 触摸真正结束（Up/Cancel）时才撤窗口标记 —— 提交那一刻就撤会让 Up 掉进 onTU，
      //   导致在途 seek 被提前解冻（时间显示回退）+ 控制栏闪一下
      if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.seekBarTouch_ = false;
        if (this.seekBarTouchTimer_ !== -1) {
          clearTimeout(this.seekBarTouchTimer_);
          this.seekBarTouchTimer_ = -1;
        }
      }
      return;
    }
    // 仅竖屏连续模式接管刷视频；全屏/横屏交回普通播放器的音量、亮度和进度手势。
    if (this.referencePortraitFeedActive()) {
      this.referenceHandleFeedTouch(e);
      return;
    }
    if (this.lk) {
      // 锁定状态下不处理触摸事件，由Stack的onClick统一处理解锁按钮的显示/隐藏/解锁
      // 不return，允许事件继续传播到子组件（如解锁按钮Row的onClick）
    } else {
      // 非锁定状态下的触摸处理
      switch (e.type) {
        case TouchType.Down:
          // ⭐ 全屏时，触摸起点在顶栏实测高度内（fullscreenTopBarHeight 由 VideoControls 写入，横屏/竖屏/密度自适应）→ 跳过播放器手势，防止点击穿透误触发单击隐藏控制栏
          const topBarBottom = (AppStorage.get<number>('fullscreenTopBarHeight') ?? 96) + 16;
          if (this.fs && e.touches.length > 0 && e.touches[0].windowY < topBarBottom) {
            this.topAreaTouch_ = true;
            return;
          }
          this.topAreaTouch_ = false;
          this.onTD(e);
          break;
        case TouchType.Move:
          if (this.topAreaTouch_) return;
          this.onTM(e);
          break;
        case TouchType.Up:
          if (this.topAreaTouch_) { this.topAreaTouch_ = false; return; }
          this.onTU(e);
          break;
        case TouchType.Cancel:
          if (this.topAreaTouch_) { this.topAreaTouch_ = false; return; }
          this.onTC();
          break;
      }
    }
  }

  private onTD(e: TouchEvent) {
    if (e.touches.length !== 1) { this.onTC(); return; }
    const t = e.touches[0];
    this.playerTouchId_ = t.id;
    this.gm_ = '';
    this.sx_ = t.windowX;
    this.sy_ = t.windowY;
    this.st_ = this.ct;
    this.sv_ = this.vol;
    this.sb_ = this.bri;
    this.ml_ = false;
    this.la_ = false;
    this.dtp_ = false;
    this.wcv_ = this.cv;

    // 双击检测：如果上次抬起到这次按下在250ms内，视为双击
    if (this.dt_ !== -1) {
      clearTimeout(this.dt_);
      this.dt_ = -1;
      this.dtp_ = true;

      // 立即触发双击：暂停/播放
      this.togglePP();

      // 清除之前可能设置的延迟隐藏timer
      this.cancelDelayHide();

      // 无需撤销控制栏——dt_已被清除，cv从未被设为true，绝无闪现
      return;
    }

    // 第一次点击，设置长按计时器
    this.lt_ = setTimeout(() => {
      if (!this.ml_ && !this.lk) {
        this.la_ = true;
        this.lp_ = true;
        this.os_ = this.rt;
        this.setRate(2.0, false);
        // 直接设置手势提示，不用 sGH（sGH 会 800ms 后自动隐藏）
        this.ght = '长按加速';
        this.gh = true;
        this.ghp = -1;
        this.ghtType = '';
        if (this.gt_ !== -1) { clearTimeout(this.gt_); this.gt_ = -1; }
      }
    }, 500);
  }

  private onTM(e: TouchEvent) {
    if (this.playerTouchId_ === -1) return;
    if (e.touches.length !== 1 || e.touches[0].id !== this.playerTouchId_) {
      this.onTC();
      return;
    }
    const t = e.touches[0];
    const dx = t.windowX - this.sx_;
    const dy = this.sy_ - t.windowY;
    const adx = Math.abs(dx);
    const ady = Math.abs(dy);
    if (adx > 10 || ady > 10) {
      this.ml_ = true;
      if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    }
    if (this.la_ || this.dtp_) return;
    if (this.gm_ === '') {
      // 横滑须越过 24vp 且明显横向；斜向意图不明时继续等待，避免轻触抖动或竖滑误调进度。
      if (adx >= 24 && adx >= ady * 1.5) {
          if (this.dur <= 0) return;
          this.gm_ = 'seek';
          // 识别门槛不计入进度位移，越过门槛时不会突然跳一段。
          this.seekDragStartX_ = this.sx_ + (dx > 0 ? 24 : -24);
          this.lastSeekHapticPct_ = -1;  // 重置档位震动追踪，让拖动中第一次反馈正常触发
          this.triggerHaptic();  // 触觉反馈：开始拖拽进度
      } else if (ady >= 12 && ady >= adx * 1.2) {
          // 根据播放器模式确定触控区域中心点
          let centerX: number;
          if (this.isLandscapeVertical) {
            // 横屏非全屏竖屏视频：播放器起始x=150vp，宽度=lsvw
            centerX = 150 + this.lsvw / 2;
          } else {
            // 其他模式：使用屏幕宽度的一半
            centerX = this.cw / 2;
          }
          if (t.windowX < centerX) {
            this.gm_ = 'brightness';
          } else {
            this.gm_ = 'volume';
          }
          // 重置档位震动追踪，让拖动过程中的第一次震动正常触发
          this.lastHapticPct_ = -1;
          this.triggerHaptic();  // 触觉反馈：开始调节音量/亮度
      } else return;
    }
    if (this.gm_ === 'seek') {
      // ⭐ 时长未知（加载中 / 直播）时不能按比例换算：原先 nt 恒等于按下位置，
      //   却照样弹手势提示并震动，看起来"拖了没反应"
      if (this.dur <= 0) return;
      // ⭐ 提示胶囊右侧"相对位移"的起点 = 手指落下时的播放位置
      //   （st_ 在 onTD 里记录，整个手势内不变；重复赋值开销可忽略）
      this.ghb = this.st_;
      // ⭐ 灵敏度按时长自适应：原先固定 dur * 0.3 —— 2 小时视频整屏宽滑 = 36 分钟，
      //   1vp ≈ 35 秒，想微调 5 秒物理上做不到
      const secPerScreen = this.dur <= 600 ? this.dur * 0.5
        : (this.dur <= 3600 ? this.dur * 0.3 : Math.max(this.dur * 0.12, 600));
      // ⭐ 分母用播放器实际可滑动宽度：横屏非全屏竖屏视频模式下播放器只有 lsvw 宽、起点 x=150，
      //   用整屏宽 cw 会让该模式的手感与其它模式不一致
      //   （音量/亮度区域判定已区分该模式，见上方 centerX，seek 这里原先漏了）
      const trackW = this.isLandscapeVertical ? Math.max(1, this.lsvw) : Math.max(1, this.cw);
      let nt = this.st_ + ((t.windowX - this.seekDragStartX_) / trackW) * secPerScreen;
      nt = Math.min(Math.max(nt, 0), this.dur);
      this.ct = nt;
      this.sk_ = true;
      // ⭐ 档位震动：与音量/亮度"每跨越 10% 震一次"的手感对齐
      //   （原先 seek 全程只在手势起点震一次，三种手势反馈不对称）
      const seekPct = Math.round(nt / this.dur * 100);
      if (this.lastSeekHapticPct_ === -1 || Math.abs(seekPct - this.lastSeekHapticPct_) >= 10) {
        this.fireHaptic(10);
        this.lastSeekHapticPct_ = seekPct;
      }
      this.sGH(`${this.formatDuration(Math.round(nt))}`, nt / this.dur, 'seek');
      // ⭐ 缩略图预览：显示目标位置的画面（与提示胶囊同一套显隐）
      this.updateSeekThumb_(nt);
    } else if (this.gm_ === 'volume') {
      // 灵敏度：screenH_ 与 dy 同单位（vp），直接用高度×系数
      // ×0.7 让满屏滑动 ≈ 143%变化（边界clamp到0~1），手势更灵敏
      const volSensitivity = this.screenH_ > 0 ? this.screenH_ * 0.7 : 700
      let v = this.sv_ + dy / volSensitivity;
      v = Math.min(1, Math.max(0, v));
      this.vol = v;
      if (this.av) {
        const s = this.av.state;
        if (s === 'prepared' || s === 'playing' || s === 'paused' || s === 'completed')
          try { this.av.setVolume(1.0); this.audioGain_ = 1; } catch (e) { }
      }
      if (this.avAudio) {
        try { this.avAudio.setVolume(1.0); this.audioGain_ = 1; } catch (e) { }
      }
      this.setSystemVolume(v);
      this.mute = (v === 0);
      AppStorage.setOrCreate('globalVolume', this.vol);
      AppStorage.setOrCreate('globalMuted', this.mute);
      this.sampleLevelInput(dy / volSensitivity);
      this.sGH(`${Math.round(v * 100)}%`, v, 'volume');
      // 每跨越10%档位震动一次
      const volPct = Math.round(v * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(volPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = volPct;
      }
    } else if (this.gm_ === 'brightness') {
      // 灵敏度：screenH_ 与 dy 同单位（vp），直接用高度×系数
      // ×0.7 让满屏滑动 ≈ 143%变化（边界clamp到0~1），手势更灵敏
      const briSensitivity = this.screenH_ > 0 ? this.screenH_ * 0.7 : 700
      let b = this.sb_ + dy / briSensitivity;
      b = Math.min(1, Math.max(0, b));
      this.bri = b;
      this.mw?.setWindowBrightness(b);
      this.sampleLevelInput(dy / briSensitivity);
      this.sGH(`${Math.round(b * 100)}%`, b, 'brightness');
      // 每跨越10%档位震动一次
      const briPct = Math.round(b * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(briPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = briPct;
      }
    }
  }

  private onTU(e: TouchEvent) {
    if (this.playerTouchId_ === -1) return;
    this.playerTouchId_ = -1;
    // 保存长按状态，用于后续判断
    const wasLongPress = this.la_;
    const wasMoved = this.ml_;

    if (this.lp_) {
      this.lp_ = false;
      this.setRate(this.os_, false);
    }
    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    this.la_ = false;
    // 长按结束时隐藏加速提示
    if (wasLongPress) {
      if (this.gt_ !== -1) { clearTimeout(this.gt_); this.gt_ = -1; }
      this.gh = false;
    }
    // ⭐ 手势拖动结束：走交互快速路径（SEEK_CLOSEST + 更短首帧等待）
    if (this.sk_ && this.av) { this.sk_ = false; this.seek(this.ct, false, true); }

    // 单击处理：控制栏已显示时200ms后隐藏，按钮回调可取消
    if (!this.dtp_ && !wasMoved && !wasLongPress) {
      if (this.cv) {
        this.ip = false;
        // 取消之前待处理的延迟隐藏
        this.cancelDelayHide();
        // 200ms后隐藏控制栏，按钮的onClick可以在之前取消
        this.hc_ = setTimeout(() => {
          this.cv = false;
          this.hc_ = -1;
        }, 200);
      } else {
        // 不立即显示控制栏——由dt_超时（250ms）确认无双击后再显示，彻底避免闪现
        this.cancelDelayHide();
        if (this.ct_ !== -1) { clearTimeout(this.ct_); this.ct_ = -1; }
      }

      // 设置250ms双击等待窗口
      if (this.dt_ !== -1) { clearTimeout(this.dt_); }
      this.dtwcv_ = this.wcv_;  // 标记本次单击时cv的状态：false→dt_负责显示，true→dt_纯等待双击
      this.dt_ = setTimeout(() => {
        this.dt_ = -1;
        // 如果cv尚未显示且本次单击时cv为false，说明是"单击显示"场景
        if (!this.cv && !this.dtwcv_) {
          this.cv = true;
          this.schedAH();
        }
      }, 250);
    }
    this.gm_ = '';
    this.ml_ = false;
    // 松手立即熄光，保留提示以呈现粒子淡出与暗淡填充。
    this.finishLevelGesture_();
  }

  private onTC() {
    this.playerTouchId_ = -1;
    if (this.lp_) {
      this.lp_ = false;
      this.setRate(this.os_, false);
    }
    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    const wasLongPress: boolean = this.la_;
    this.la_ = false;
    // ⭐ 触摸被取消时**只有长按加速提示必须立刻收**（2026-09-24 按用户反馈重构，见下）
    //   理由：长按提示是 onTD 的 lt_ 分支**直接** `gh = true` 的，同时把 `gt_` 清成 -1
    //   ⇒ 它**根本没有 800ms 自动隐藏定时器**，只能靠 onTU/onTC 显式清，不清就永久留在屏幕上。
    if (wasLongPress) {
      if (this.gt_ !== -1) { clearTimeout(this.gt_); this.gt_ = -1; }
      this.gh = false;
    }
    // 系统接管触摸时保留提示的退场尾段；真正离开由 clearGestureHint_ 与页面转场同步收起。
    if (this.gm_ === 'seek' && this.sk_) {
      // 系统接管、手势竞争或多指触摸只撤销预览，明确松手才提交。
      this.ct = this.st_;
      this.clearGestureHint_();
    }
    this.gm_ = '';
    this.sk_ = false;
    this.ml_ = false;
    // 取消同样熄光，并从此刻开始保留 800ms 收尾。
    this.finishLevelGesture_();
  }

  /**
   * ⭐ 立刻收掉手势提示（含 800ms 自动隐藏定时器与 seek 缩略图）。
   *
   * 只在"用户**真的要离开**当前画面"时调用：退出/进入全屏、关灯→开灯、页面 pop。
   * 目的是把提示的退场动画（弹层淡出 + 内容卷帘收起）**并进转场**：两者同一帧启动 ⇒ 读起来是"直接换内容"，
   * 而不是"提示先退出去、中间空一下、才轮到转场"（见 onTC 的长注释）。
   * ⚠️ 不要拿它当 onTC 的替代 —— 触摸被系统取消并不等于用户要离开。
   */
  private clearGestureHint_(): void {
    if (this.gt_ !== -1) { clearTimeout(this.gt_); this.gt_ = -1; }
    this.gh = false;
    this.ghActive = false;
    this.hideSeekThumb_();
  }

  // ⭐ 镜像布局：比例/画质/更多弹窗跟随全屏控制栏镜像（面板改从左侧滑入、关闭区换到右侧）
  private mirrorPopup(): boolean {
    return this.isMirrorControls && this.fs;
  }

  @Builder
  bSP() {
    if (this.referenceLayout && this.fs && this.isLs) {
      this.ReferenceLandscapeScalePanel()
    } else {
      this.bLegacySP()
    }
  }

  @Builder
  ReferenceLandscapeScalePanel() {
    Stack() {
      Column().width('77%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => { this.sp = false; this.ip = false; this.cv = true; this.resetCT(); })
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.sl_, (item: SO) => {
            Row() {
              Text(item.label).fontSize(14).maxLines(1).textAlign(TextAlign.Center).width('100%')
                .fontColor(this.sm === item.mode ? '#D34E7E' : '#FFFFFF')
            }.width('100%').height(52).padding({ left: 8, right: 8 })
              .borderRadius(10).backgroundColor('#202126')
              .onClick(() => {
                this.referencePortraitAction(`scale:${item.label}`);
                this.sp = false;
                this.ip = false;
                this.cv = true;
                this.resetCT();
              })
          }, (item: SO) => item.mode)
        }.width('100%').padding({ top: 24, bottom: 24 })
      }.width('23%').height('100%').padding({ right: 8 })
        .align(Alignment.Center).scrollBar(BarState.Off).position({ right: 0, top: 0 })
    }.width('100%').height('100%').zIndex(30)
  }

  @Builder
  bLegacySP() {
    Stack() {
      // ⭐ 点击关闭区域 — 透明（镜像布局时在右侧）
      Column().width(this.isLs ? '60%' : '50%').height('100%')
        .position(this.mirrorPopup() ? { right: 0, top: 0 } : { left: 0, top: 0 })
        .onClick(() => { this.sp = false; this.ip = false; if (this.cv) this.resetCT(); });

      // ⭐ 渐变背景 — 加宽 + 多段渐变（镜像布局时滑入方向与渐变反向）
      Column() {
        // 标题（白色，不跟随系统主题）
        Text('画面比例').fontSize(16).fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .padding({ left: 4, right: 4, top: 0, bottom: 12 })
          .offset({ x: this.mirrorPopup() ? 14 : -14, y: -12 });

        // 每个选项是独立圆角矩形，依次从右侧滑入
        ForEach(this.sl_, (it: SO, index: number) => {
          Row() {
            Text(it.label).fontSize(15)
              .fontColor(this.sm === it.mode ? this.playerFollowTheme ? this.customThemeColor : '#FB7299' : Color.White)
              .fontWeight(this.sm === it.mode ? FontWeight.Bold : FontWeight.Normal);
          }
          .height(48)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 36, right: 36 })
          .backgroundColor(this.sm === it.mode ? this.playerFollowTheme ? '#' + this.opacityToHexAlpha(15) + this.customThemeColor.slice(1) : 'rgba(255, 85, 170, 0.15)' : 'rgba(0, 0, 0, 0.35)')
          .border({ width: this.sm === it.mode ? 1.5 : 0, color: this.playerFollowTheme ? this.customThemeColor : '#FB7299' })
          .borderRadius(12)
          .margin({ bottom: 12 })
          .onClick(() => {
            const previousMode = this.sm;
            this.sm = it.mode;
            const isSwitchingToStretch = it.mode === 'stretch';
            const isSwitchingFromStretch = previousMode === 'stretch' && it.mode !== 'stretch';

            if (isSwitchingToStretch) {
              try { if (this.av) { this.av.videoScaleType = this.getVideoScaleType(); } } catch (e) { }
            }
            this.saveSM();
            this.sp = false;
            this.ip = false;
            if (this.cv) this.resetCT();
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              if (!isSwitchingFromStretch) {
                try { if (this.av) { this.av.videoScaleType = this.getVideoScaleType(); } } catch (e) { }
              }
              this.updateVideoSize();
            });
            if (isSwitchingFromStretch) {
              setTimeout(() => {
                try { if (this.av) { this.av.videoScaleType = this.getVideoScaleType(); } } catch (e) { }
              }, 200);
            }
          })
          // 进入：从右侧较远位置依次滑入；退出：依次向右滑出
          .transition(
            this.icp ? TransitionEffect.IDENTITY :
              TransitionEffect.asymmetric(
                TransitionEffect.translate({ x: this.mirrorPopup() ? -60 : 60 }).combine(TransitionEffect.opacity(0))
                  .animation({ duration: 450, curve: Curve.EaseOut, delay: index * 100 }),
                TransitionEffect.translate({ x: this.mirrorPopup() ? -40 : 40 }).combine(TransitionEffect.opacity(0))
                  .animation({ duration: 300, curve: Curve.EaseIn, delay: index * 100 })
              )
          )
          .offset({ x: this.mirrorPopup() ? 14 : -14 });
        }, (it: SO) => it.mode);
      }
      .width(this.fs && this.isLs ? '24%' : this.isLs ? '30%' : '50%')
      .height('100%')
      .linearGradient({
        direction: this.mirrorPopup() ? GradientDirection.Left : GradientDirection.Right,
        colors: [
          ['rgba(0,0,0,0)', 0],
          ['rgba(0,0,0,0)', 0.25],
          ['rgba(0,0,0,0.95)', 1]
        ]
      })
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 60, left: this.mirrorPopup() ? 50 : 48, right: this.mirrorPopup() ? 48 : 50 })
      .position(this.mirrorPopup() ? { left: 0, top: 0 } : { right: 0, top: 0 });
    }
    .width('100%').height('100%')
    .transition(
      this.icp ? TransitionEffect.IDENTITY :
        TransitionEffect.asymmetric(
          TransitionEffect.translate({ x: this.mirrorPopup() ? '-100%' : '100%' }).combine(TransitionEffect.opacity(0))
            .animation({ duration: 400, curve: Curve.EaseOut }),
          TransitionEffect.opacity(0)
            .animation({ duration: 700, curve: Curve.EaseIn })
        )
    );
  }

  @Builder
  bQP() {
    if (this.referenceLayout && this.fs && this.isLs) {
      this.ReferenceQualityPanel()
    } else {
      this.bLegacyQP()
    }
  }

  @Builder
  ReferenceQualityPanel() {
    Stack() {
      Column().width('77%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => { this.qp = false; this.ip = false; this.cv = true; this.resetCT(); })
      Stack() { PlaybackControlSurface() {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.getQlList(), (item: QI) => {
              PlaybackGlassAction({ actionId: `player-bottom-quality-${item.qn}`, onActivate: () => {
                this.qp = false; this.ip = false; this.cv = true; this.resetCT(); this.switchQ(item.qn);
              } }) {
                Text(item.label).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center).width('100%').padding({ left: 8, right: 8 })
                  .fontColor(this.qn === item.qn ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
              }
            }, (item: QI) => `${item.qn}`)
          }.width('100%').padding({ top: 24, bottom: 24, left: 8, right: 8 })
        }.width('100%').height('100%').align(Alignment.Center).scrollBar(BarState.Off)
      } }.width('23%').height('100%').position({ right: 0, top: 0 })
    }.width('100%').height('100%').zIndex(30)
  }

  @Builder
  bLegacyQP() {
    Stack() {
      // 左侧点击区域 — 透明，仅用于点击关闭弹窗
      Column().width(this.isLs ? '60%' : '50%').height('100%')
        .position(this.mirrorPopup() ? { right: 0, top: 0 } : { left: 0, top: 0 })
        .onClick(() => { this.qp = false; this.ip = false; if (this.cv) this.resetCT(); });

      // ⭐ 渐变背景 — 加宽 + 多段渐变（镜像布局时滑入方向与渐变反向）
      Column() {
        // 标题（白色，不跟随系统主题）
        Text('画质选择').fontSize(16).fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
          .padding({ left: 4, right: 4, top: 0, bottom: 12 })
          .offset({ x: this.mirrorPopup() ? 14 : -14, y: -12 });

        // 每个选项是独立圆角矩形，依次从右侧滑入
        ForEach(this.getQlList(), (it: QI, index: number) => {
          Row() {
            Text(it.label).fontSize(15)
              .fontColor(this.qn === it.qn ? this.playerFollowTheme ? this.customThemeColor : '#FB7299' : Color.White)
              .fontWeight(this.qn === it.qn ? FontWeight.Bold : FontWeight.Normal);
          }
          .height(48)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 36, right: 36 })
          .backgroundColor(this.qn === it.qn ? this.playerFollowTheme ? '#' + this.opacityToHexAlpha(15) + this.customThemeColor.slice(1) : 'rgba(255, 85, 170, 0.15)' : 'rgba(0, 0, 0, 0.35)')
          .border({ width: this.qn === it.qn ? 1.5 : 0, color: this.playerFollowTheme ? this.customThemeColor : '#FB7299' })
          .borderRadius(12)
          .margin({ bottom: 12 })
          .onClick(() => { this.qp = false; this.ip = false; this.switchQ(it.qn); })
          // 进入：从右侧较远位置依次滑入；退出：依次向右滑出
          .transition(
            this.icp ? TransitionEffect.IDENTITY :
              TransitionEffect.asymmetric(
                TransitionEffect.translate({ x: this.mirrorPopup() ? -40 : 40 }).combine(TransitionEffect.opacity(0))
                  .animation({ duration: 300, curve: Curve.EaseIn, delay: index * 100 }),
                TransitionEffect.translate({ x: this.mirrorPopup() ? -40 : 40 }).combine(TransitionEffect.opacity(0))
                  .animation({ duration: 300, curve: Curve.EaseIn, delay: index * 100 })
              )
          )
          .offset({ x: this.mirrorPopup() ? 14 : -14 });
        }, (it: QI) => it.qn.toString());
      }
      .width(this.fs && this.isLs ? '24%' : this.isLs ? '30%' : '50%')
      .height('100%')
      .linearGradient({
        direction: this.mirrorPopup() ? GradientDirection.Left : GradientDirection.Right,
        colors: [
          ['rgba(0,0,0,0)', 0],
          ['rgba(0,0,0,0)', 0.25],
          ['rgba(18,18,22,0.88)', 1]
        ]
      })
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 60, left: this.mirrorPopup() ? 50 : 48, right: this.mirrorPopup() ? 48 : 50 })
      .position(this.mirrorPopup() ? { left: 0, top: 0 } : { right: 0, top: 0 });
    }
    .width('100%').height('100%')
    .transition(
      this.icp ? TransitionEffect.IDENTITY :
        TransitionEffect.asymmetric(
          TransitionEffect.translate({ x: this.mirrorPopup() ? '-100%' : '100%' }).combine(TransitionEffect.opacity(0))
            .animation({ duration: 400, curve: Curve.EaseOut }),
          TransitionEffect.opacity(0)
            .animation({ duration: 700, curve: Curve.EaseIn })
        )
    );
  }

  @Builder
  bRP() {
    Stack() {
      Column().width('77%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => { this.rp = false; this.ip = false; this.cv = true; this.resetCT(); })
      Stack() { PlaybackControlSurface() {
        Scroll() {
          Column({ space: 8 }) {
            ForEach([2.0, 1.5, 1.25, 1.0, 0.75, 0.5], (rate: number) => {
              PlaybackGlassAction({ actionId: `player-bottom-rate-${rate}`, onActivate: () => {
                this.setRate(rate); this.rp = false; this.ip = false; this.cv = true; this.resetCT();
              } }) {
                Text(`${rate.toFixed(2).replace(/0$/, '')}X`).fontSize(14)
                  .fontColor(Math.abs(this.rt - rate) < 0.01 ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
                  .textAlign(TextAlign.Center).width('100%')
              }
            }, (rate: number) => `${rate}`)
          }.width('100%').padding({ left: 8, right: 8, top: 24, bottom: 24 })
        }.width('100%').height('100%').align(Alignment.Center).scrollBar(BarState.Off)
      } }.width('23%').height('100%').position({ right: 0, top: 0 })
    }.width('100%').height('100%').zIndex(30)
  }

  private referenceSetSleep(minutes: number): void {
    if (this.referenceSleepTimer !== -1) clearInterval(this.referenceSleepTimer);
    this.referenceSleepTimer = -1;
    this.referenceSleepMinutes = minutes;
    this.referenceSleepDeadline = minutes > 0 ? Date.now() + minutes * 60000 : 0;
    if (minutes > 0) {
      this.referenceSleepTimer = setInterval(() => this.referenceCheckSleep(), 1000);
    }
  }

  private referenceCheckSleep(): void {
    if (this.referenceSleepDeadline > 0 && Date.now() >= this.referenceSleepDeadline) {
      this.referenceSetSleep(0);
      this.referencePause();
    }
  }

  private async referencePause(): Promise<void> {
    this.userPaused_ = true;
    this.play = false;
    try { if (this.av?.state === 'playing') await this.av.pause(); } catch (_e) {}
    try { if (this.avAudio?.state === 'playing') await this.avAudio.pause(); } catch (_e) {}
    LiveViewHelper.updatePlayState(false);
  }

  private async referenceOnCompleted(): Promise<void> {
    if (this.referenceStopAtEnd) {
      this.referenceStopAtEnd = false;
      this.referenceSetSleep(0);
      this.referencePause();
      return;
    }
    // 播放模式：自动连播 / 列表循环 / 单集循环 / 播完暂停。
    // 前两者的区别只在队尾——自动连播停住，列表循环回到列表头（详见 referencePlayNextEpisode）。
    const mode = this.referencePlaybackMode;
    if (mode === 'single') return;
    if (mode === 'loop') {
      await this.seek(0);
      if (!this.referenceAlive) return;
      try {
        this.userPaused_ = false;
        this.markAutoPlay('loop-replay');
        await this.av?.play();
        await this.avAudio?.play();
        this.play = true;
      } catch (_e) {}
      return;
    }
    // 连刷且非番剧：自动连播 = story 队列的下一条（队列边看边追加；真的到队尾时兜底回队首）。
    // 番剧进不了连刷（referenceNextVideo 会直接弹回），这里也把它挡在外面，让它走分集连播。
    if (this.referencePortraitFeedActive() && !this.isPgc_) {
      const queue = await this.ensureReferenceRecommendQueue();
      const index = queue.findIndex((item: RecommendItem) => item.id === this.vi.bvid);
      if (index === queue.length - 1 && queue.length > 1) {
        this.referenceFeedQueue = [queue[index], ...queue.slice(0, index)];
      }
      await this.referenceNextVideo(1);
      return;
    }
    // 非连刷（竖屏详情/横屏分栏/全屏）：分P → 合集下一集，不接推荐
    await this.referencePlayNextEpisode(this.referencePlaybackMode === 'listLoop');
  }

  /**
   * 非连刷的连播顺序：当前稿件还有下一个分P → 合集还有下一集 → 队尾。
   * 到队尾时 `wrap`（列表循环）回到列表头：有合集先回合集第一集，否则回本稿件第 1 个 P；
   * 没有 `wrap`（自动连播）直接停住，不碰相关推荐。
   */
  private async referencePlayNextEpisode(wrap: boolean): Promise<void> {
    if (!this.referenceAlive) return;
    // 离线缓存只存了当前这一个文件：切集会拿旧文件去播新的 cid，宁可停在片尾
    if (this.offlineVideoPath_.length > 0) {
      logInfo('[VideoPlayer] 自动连播跳过：离线缓存播放');
      return;
    }
    const pages = this.pagesForCurrentVideo();
    if (pages.length > 1 && this.currentPageIndex + 1 < pages.length) {
      logInfo(`[VideoPlayer] 自动连播 → 分P ${this.currentPageIndex + 2}/${pages.length}`);
      this.referencePlaybackCompleted = false;   // 播完是终态，切下一条前必须解除，否则新片起播被拦
      await this.switchEpisode(this.currentPageIndex + 1);
      return;
    }
    const next = this.seasonNeighborEpisode(1);
    if (next) {
      logInfo(`[VideoPlayer] 自动连播 → 合集下一集 ${next.bvid}`);
      this.referencePlaybackCompleted = false;
      await this.switchSeasonEpisode(next);
      return;
    }
    if (!wrap) {
      logInfo('[VideoPlayer] 自动连播到底：列表结束，停在当前画面');
      return;
    }
    // 只有当前剧集确实属于这个合集时才回第一集；不在合集里（seasonNeighborEpisode(0) 为空）就别乱跳
    const first = this.seasonNeighborEpisode(0) ? this.seasonFirstEpisode() : null;
    if (first && first.bvid && first.bvid !== this.vi.bvid) {
      logInfo(`[VideoPlayer] 列表循环 → 回到合集第一集 ${first.bvid}`);
      this.referencePlaybackCompleted = false;
      await this.switchSeasonEpisode(first);
      return;
    }
    if (pages.length > 1 && this.currentPageIndex !== 0) {
      logInfo('[VideoPlayer] 列表循环 → 回到分P 1');
      this.referencePlaybackCompleted = false;
      await this.switchEpisode(0);
    }
  }

  /** 合集扁平化后的相邻分集（step=1 下一集、-1 上一集；当前集不在合集里或越界返回 null） */
  private seasonNeighborEpisode(step: number): SeasonEpisode | null {
    const sections = this.vd?.ugc_season?.sections;
    if (!sections || sections.length === 0) return null;
    const flat: SeasonEpisode[] = [];
    for (const section of sections) {
      for (const ep of section.episodes || []) flat.push(ep);
    }
    const index = flat.findIndex((ep: SeasonEpisode) => this.isCurrentSeasonEpisode(ep));
    if (index < 0) return null;
    const target = index + step;
    return target >= 0 && target < flat.length ? flat[target] : null;
  }

  /** 合集第一集（跨分区取第一个非空分区的首项） */
  private seasonFirstEpisode(): SeasonEpisode | null {
    const sections = this.vd?.ugc_season?.sections;
    if (!sections) return null;
    for (const section of sections) {
      const episodes = section.episodes || [];
      if (episodes.length > 0) return episodes[0];
    }
    return null;
  }

  private async referenceReplay(): Promise<void> {
    if (!this.av || this.referenceFeedLoading || this.sg_) return;
    this.referenceCancelFeedTap();
    const player = this.av;
    const generation = this.referenceSwitchGeneration;
    await this.seek(0, false);
    if (!this.referenceAlive || this.av !== player || generation !== this.referenceSwitchGeneration) return;
    try {
      this.userPaused_ = false;
      this.markAutoPlay('replay-button');
      await player.play();
      await this.avAudio?.play();
      this.referencePlaybackCompleted = false;
      this.play = true;
      LiveViewHelper.updatePlayState(true);
      logInfo('[ReferenceFeed] replay started');
    } catch (error) { logWarn(`重播失败: ${error}`); }
  }

  private referenceSetMoreDrawer(open: boolean): void {
    this.cancelDelayHide();
    if (open) this.cv = false;
    this.referenceAnimateMenu(open);
    if (!open) {
      this.cv = true;
      this.resetCT();
    }
  }

  // ⭐ 缓存当前视频（「更多」菜单触发 → 先选清晰度）
  private startCacheCurrentVideo(): void {
    if (!this.vi || !this.vi.bvid || this.vi.cid <= 0) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '当前视频无法缓存', duration: 1500 });
      } catch (err) {
        logWarn(`showToast 异常: ${errMsg(err)}`);
      }
      return;
    }
    // 缓存与播放共用当前视频实际返回的画质列表。
    this.cacheQnPopup = true;
    this.ip = true;
  }

  // ⭐ 按所选清晰度开始缓存
  private startCacheWithQuality(qn: number): void {
    const svc = OfflineCacheService.getInstance();
    // ⭐ 惰性初始化：注入沙箱 filesDir（首次缓存前必须 init，否则目录创建失败）
    try {
      svc.init(this.getUIContext().getHostContext() as common.Context);
    } catch (err) {
      logWarn(`[OfflineCache] init 异常: ${errMsg(err)}`);
    }
    const item: OfflineCacheItem = {
      bvid: this.vi.bvid,
      cid: this.vi.cid,
      title: this.vi.title || '未命名视频',
      cover: this.vi.cover || '',
      quality: qn > 0 ? qn : 116,
      qualityLabel: this.getQlLabel(qn),
      status: CacheStatus.WAIT,
      totalBytes: 0,
      downloadedBytes: 0,
      videoPath: '',
      audioPath: '',
      createTime: Date.now(),
      updateTime: Date.now()
    };
    // ⭐ 显示可点击的缓存提示条（开始：正在缓存）
    this.cacheHintVisible = true;
    this.cacheHintDone = false;
    this.cacheHintPaused = false;
    svc.download(item, (d: number, t: number) => {
      logInfo(`[缓存] ${item.title} ${d}/${t}`);
    }).then((ok: boolean) => {
      if (ok) {
        // ⭐ 缓存完成：提示条保留，文案切换为「缓存完成·点击查看」，手动关闭
        this.cacheHintDone = true;
        this.cacheHintPaused = false;
      } else {
        // ⭐ 区分「被暂停」与「真失败」：缓存中被暂停（列表页/播放页触发 pause）不算失败
        const fresh = svc.getCachedItem(item.bvid, item.cid);
        if (fresh && fresh.status === CacheStatus.PAUSED) {
          // ⭐ 暂停：文案切换为「已暂停·点击查看」，保留提示条，不弹「缓存失败」
          this.cacheHintDone = false;
          this.cacheHintPaused = true;
        } else {
          // 失败：隐藏提示条
          this.cacheHintVisible = false;
        }
      }
      if (ok) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '缓存完成', duration: 2000 });
        } catch (err) {
          logWarn(`showToast 异常: ${errMsg(err)}`);
        }
      }
    });
  }

  // ⭐ 跳转到离线缓存列表页（提示条点击）
  private goToOfflineCachePage(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/OfflineCachePage' }).catch((err: Error) => {
      logWarn(`[OfflineCache] 跳转缓存页失败: ${errMsg(err)}`);
    });
  }

  // ⭐ 按当前视频的缓存条目真实状态刷新提示条（完成→文案切换；暂停→已暂停；失败→保持可见待处理）
  private syncCacheHintStatus(): void {
    try {
      if (!this.cacheHintVisible || !this.vi || !this.vi.bvid || this.vi.cid <= 0) {
        return;
      }
      const fresh = OfflineCacheService.getInstance().getCachedItem(this.vi.bvid, this.vi.cid);
      if (fresh) {
        this.cacheHintDone = fresh.status === CacheStatus.COMPLETED;
        this.cacheHintPaused = fresh.status === CacheStatus.PAUSED;
      }
    } catch (e) {
      logWarn(`[VideoPlayer] 同步缓存提示条异常: ${JSON.stringify(e)}`);
    }
  }

  // ⭐ 更多弹窗内容（bindSheet 半模态，样式与选集弹窗一致）
  @Builder
  moreSheetContent() {
    Column() {
      // 标题
      Text('更多').fontSize(16).fontColor($r('app.color.color_player_text'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 4 })
      // 菜单项
      Column() {
        ForEach(this.mo_, (it: MO, index: number) => {
          if (it.label === '投屏') {
            Stack() {
              Row() {
                Image(it.icon).width(20).height(20).fillColor($r('app.color.color_player_text')).margin({ right: 12 });
                Text(it.label).fontSize(15).fontColor($r('app.color.color_player_text'));
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)

              AVCastPicker({
                sessionType: 'video',
                onStateChange: (state: AVCastPickerState) => {
                  if (state === AVCastPickerState.STATE_DISAPPEARING) {
                    this.mpb = false; this.ip = false; if (this.cv) this.resetCT();
                  }
                }
              })
                .opacity(0)
                .width('100%')
                .height(48)
            }
            .width('100%')
            .height(48)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.getComponentBg(this.cardStyleVideoNavBtns))
            .borderRadius(20)
            .margin({ bottom: 10 })
            .clip(true)
          } else {
            Row() {
              Image(it.icon).width(20).height(20).fillColor($r('app.color.color_player_text')).margin({ right: 12 });
              Text(it.label).fontSize(15).fontColor($r('app.color.color_player_text'));
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.getComponentBg(this.cardStyleVideoNavBtns))
            .borderRadius(20)
            .margin({ bottom: 10 })
            .onClick(() => {
              this.mpb = false;
              this.ip = false;
              if (this.cv) this.resetCT();
              it.action();
            })
          }
        }, (it: MO) => it.label)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.sheetRootBg($r('app.color.color_comment_background')))
  }

  // 横竖屏复用同一套弹幕设置；竖屏仅由外层 sheet 控制高度。
  @Builder
  danmakuSettingSheetContent() {
    Column() {
      ReferenceDanmakuSettings({
        config: $danmakuConfig,
        onChanged: () => { this.notifyDanmakuSettingsChanged(); }
      })
    }
    .width('100%')
    .height('100%')
    // Keep the native glass rim inside the system Sheet's own rounded clipping area.
    .padding(16)
    .backgroundColor(Color.Transparent)
  }

  /** 打开「弹幕设置」面板 */
  private openDanmakuSettingSheet(): void {
    this.cancelDelayHide();
    // Both the bottom control and more menu use the same host for this viewport.
    if (this.referenceLayout && this.isLs && !this.isLightsOff) {
      this.showDanmakuSettingSheet = false;
      this.cv = false;
      this.ip = true;
      this.referenceLandscapeDanmakuOpen = true;
    } else {
      this.referenceLandscapeDanmakuOpen = false;
      this.showDanmakuSettingSheet = true;
    }
  }

  /**
   * ⭐ 面板里任意一项被改动后的统一出口。
   *
   * 为什么必须 debounce 200ms：拖滑块时 `Slider.onChange(Moving)` 每秒几十次回调，
   *   而每一次"应用"都会让 renderer 清空文本宽度/字体缓存并让 trackManager 重算轨道
   *   （DragBar 拖满一屏 = 几十次全量重建），主线程会被吃满、弹幕出现明显卡顿。
   *   合并到"手停下来"之后执行一次，观感上是"松手即生效"。
   *
   * ① AppStorage('danmakuSettingVersion')++ → `DanmakuView` 的 @Watch →
   *   `controller.applyDisplaySettings()` → 按新字号/显示区/行高重算轨道几何（就地，不重建弹幕）；
   * ② 落盘 Preferences，下次进任意视频自动沿用。
   */
  private notifyDanmakuSettingsChanged(): void {
    this.dmSettingsTouched = true
    if (this.dmSettingApplyTimer) {
      clearTimeout(this.dmSettingApplyTimer)
    }
    this.dmSettingApplyTimer = setTimeout(() => {
      this.dmSettingApplyTimer = 0
      this.dmSettingVersion += 1
      AppStorage.setOrCreate<number>('danmakuSettingVersion', this.dmSettingVersion)
      this.saveDanmakuDisplaySettings()
    }, 200)
  }

  /**
   * 持久化弹幕显示设置（JSON 字符串存单个 key，避免为每个字段建一条 Preferences 记录）
   */
  private async saveDanmakuDisplaySettings(): Promise<void> {
    try {
      const c = this.danmakuConfig
      // 手动拼串：规避 ArkTS 里 Record<string, Object> 对 boolean/number 装箱的类型限制
      const json = '{"blockWeight":' + c.blockWeight +
        ',"showScroll":' + c.showScroll +
        ',"showTop":' + c.showTop +
        ',"showBottom":' + c.showBottom +
        ',"showAdvanced":' + c.showAdvanced +
        ',"blockColorful":' + c.blockColorful +
        ',"blockCounted":' + c.blockCounted +
        ',"hideDuplicates":' + c.hideDuplicates +
        ',"keywordFilterEnabled":' + c.keywordFilterEnabled +
        ',"blockKeywords":' + JSON.stringify(c.blockKeywords) +
        ',"displayArea":' + c.displayArea +
        ',"opacity":' + c.opacity +
        ',"fontSize":' + c.fontSize +
        ',"fullScreenFontScale":' + c.fullScreenFontScale +
        ',"lineHeight":' + c.lineHeight +
        ',"fontWeight":' + c.fontWeight +
        ',"borderWidth":' + c.borderWidth +
        ',"scrollDuration":' + c.scrollDuration +
        ',"staticDuration":' + c.staticDuration +
        ',"varyFontSize":' + c.varyFontSize +
        ',"massiveMode":' + c.massiveMode +
        ',"static2Scroll":' + c.static2Scroll +
        ',"scrollFixedVelocity":' + c.scrollFixedVelocity +
        '}'
      const ctx = this.getUIContext().getHostContext() as common.Context
      const pf = await preferences.getPreferences(ctx, 'VPS')
      await pf.put(DM_SETTING_KEY, json)
      await pf.flush()
    } catch (e) {
      logWarn(`[VideoPlayer] 保存弹幕设置失败: ${errMsg(e)}`)
    }
  }

  /**
   * ⭐ 读取持久化的弹幕显示设置（fire-and-forget，不阻塞首帧）。
   * 逐字段写回 —— **绝不整体替换 danmakuConfig 对象**（见 danmakuConfig 声明处注释）。
   */
  private async loadDanmakuDisplaySettings(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context
      const pf = await preferences.getPreferences(ctx, 'VPS')
      const raw = await pf.get(DM_SETTING_KEY, '') as string
      if (!raw || raw.length < 2) {
        return
      }
      const o = JSON.parse(raw) as DanmakuConfigInit
      // ⭐ 读盘是异步的：如果用户已经先动过面板，这次读到的旧存档必须丢弃，
      //   否则会把刚改的值覆盖回去（滑块显示新值、画面用旧值的经典错位）。
      if (this.dmSettingsTouched) {
        logInfo('[VideoPlayer] 用户已改动弹幕设置，跳过本次读盘覆盖')
        return
      }
      const c = this.danmakuConfig
      if (o.blockWeight !== undefined) c.blockWeight = Math.round(Math.min(11, Math.max(0, o.blockWeight)))
      if (o.showScroll !== undefined) c.showScroll = !!o.showScroll
      if (o.showTop !== undefined) c.showTop = !!o.showTop
      if (o.showBottom !== undefined) c.showBottom = !!o.showBottom
      if (o.showAdvanced !== undefined) c.showAdvanced = !!o.showAdvanced
      if (o.blockColorful !== undefined) c.blockColorful = !!o.blockColorful
      if (o.blockCounted !== undefined) c.blockCounted = !!o.blockCounted
      if (o.hideDuplicates !== undefined) c.hideDuplicates = !!o.hideDuplicates
      if (o.keywordFilterEnabled !== undefined) c.keywordFilterEnabled = !!o.keywordFilterEnabled
      if (o.blockKeywords !== undefined) c.blockKeywords = o.blockKeywords.filter((word: string) => word.length > 0)
      if (o.displayArea !== undefined) c.displayArea = Math.min(1, Math.max(0.1, o.displayArea))
      if (o.opacity !== undefined) c.opacity = Math.min(1, Math.max(0, o.opacity))
      // ⚠️ 量程必须覆盖默认字号 28：早期版本上限 32 曾把 37 静默钳到 32（Slider 的隐含约束，这里同源）
      if (o.fontSize !== undefined) c.fontSize = Math.round(Math.min(48, Math.max(12, o.fontSize)))
      if (o.fullScreenFontScale !== undefined) c.fullScreenFontScale = Math.min(2, Math.max(1, o.fullScreenFontScale))
      if (o.lineHeight !== undefined) c.lineHeight = Math.min(2.5, Math.max(1, o.lineHeight))
      if (o.fontWeight !== undefined) c.fontWeight = Math.min(900, Math.max(100, Math.round(o.fontWeight / 100) * 100))
      if (o.borderWidth !== undefined) c.borderWidth = Math.min(5, Math.max(0, o.borderWidth))
      if (o.scrollDuration !== undefined) c.scrollDuration = Math.min(20000, Math.max(3000, Math.round(o.scrollDuration)))
      if (o.staticDuration !== undefined) c.staticDuration = Math.min(10000, Math.max(1000, Math.round(o.staticDuration)))
      if (o.varyFontSize !== undefined) c.varyFontSize = !!o.varyFontSize
      if (o.massiveMode !== undefined) c.massiveMode = !!o.massiveMode
      if (o.static2Scroll !== undefined) c.static2Scroll = !!o.static2Scroll
      if (o.scrollFixedVelocity !== undefined) c.scrollFixedVelocity = !!o.scrollFixedVelocity
      // ⭐ 恢复完必须补发一次"设置已变更"：
      //   读盘可能在 DanmakuView 首个 Canvas 尺寸之后就返回，此时轨道已经按**默认值**算好，
      //   不补这一下，上次保存的显示区域/字号要等用户再动一次面板才会生效。
      this.dmSettingVersion += 1
      AppStorage.setOrCreate<number>('danmakuSettingVersion', this.dmSettingVersion)
      logInfo('[VideoPlayer] 已恢复弹幕显示设置')
    } catch (e) {
      logWarn(`[VideoPlayer] 读取弹幕设置失败: ${errMsg(e)}`)
    }
  }

  // ⭐ 缓存画质选择弹窗内容（bindSheet 半模态，样式与更多弹窗一致）
  @Builder
  cacheQnSheetContent() {
    Column() {
      // 标题
      Text('选择缓存画质').fontSize(16).fontColor($r('app.color.color_player_text'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 4 })
      // 画质选项
      Column() {
        ForEach(this.getQlList(), (it: QI, index: number) => {
          Row() {
            Text(it.label).fontSize(15)
              .fontColor(this.qn === it.qn ? this.playerFollowTheme ? this.customThemeColor : '#FB7299' : $r('app.color.color_player_text'))
              .fontWeight(this.qn === it.qn ? FontWeight.Bold : FontWeight.Normal);
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.qn === it.qn ? this.playerFollowTheme ? '#' + this.opacityToHexAlpha(15) + this.customThemeColor.slice(1) : 'rgba(255, 85, 170, 0.15)' : this.getComponentBg(this.cardStyleVideoNavBtns))
          .borderRadius(20)
          .margin({ bottom: 10 })
          .onClick(() => {
            this.cacheQnPopup = false;
            this.ip = false;
            if (this.cv) this.resetCT();
            this.startCacheWithQuality(it.qn);
          })
        }, (it: QI) => it.qn.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.sheetRootBg($r('app.color.color_comment_background')))
  }

  // ⭐ 整卡下拉关灯：全部由原始触摸坐标驱动——卡片双向跟随手指（下拉下移、回滑上移），
  //    回滑累计回落 ≥6vp 记为"已取消"，松手只弹回不关灯


  // ⭐ 松手触发关灯：卡片弹回的同时进入关灯
  private doLightsOff() {
    this.detailPullHintPhase = 0;
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 600, curve: curves.springMotion(0.6, 0.8) }, () => {
      this.detailPullDrop = 0; // 卡片弹回的同时进入关灯
      this.isLightsOff = true;
      this.lightbulbRotation = 0; // 重置灯泡角度，从 180° 转回 0°
      this.lightBtnVisible = this.lightsOffShowBtn; // 是否显示开灯按钮（设置项控制）
      this.startLightBtnTimer();   // 启动5秒自动隐藏
      // ⭐ 背景压暗：当前背景 + 模糊 + 黑色压暗
      this.loBgScale = 1;
      this.loBgBlur = 150;
      this.loBgDim = 0.72;
    });
    // ⭐ 关灯：隐藏状态栏（竖屏也隐藏）
    setTimeout(() => { this.manageSB(true); }, 50);
  }

  // ⭐ 卡片平滑弹回（未达阈值 / 上滑取消 / 触摸中断）
  private springBackDetailPull() {
    this.detailPullHintPhase = 0;
    this.getUIContext()?.animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 350, curve: curves.springMotion(0.3, 0.7) }, () => {
      this.detailPullDrop = 0;
    });
  }

  /**
   * 弹幕组件Builder - 统一管理弹幕实例，避免重复创建
   */


  // ═══ 常驻播放器层：XComponent 单实例（全文件唯一），跨布局分支常驻，只改几何不改挂载 ═══
  @Builder
  buildFullscreenResetButton() {
    if (this.fullscreenVideoTransformAvailable() && this.fullscreenVideoChanged()) {
      Row() {
      Button('还原屏幕')
        .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
        .fontSize(14).fontColor(Color.White)
        .backgroundColor('#80000000').borderRadius(18).height(36)
        .padding({ left: 16, right: 16 })
        .onTouch((event: TouchEvent) => {
          event.stopPropagation();
          this.fullscreenTransformClickUntil = Date.now() + 300;
          this.cancelDelayHide();
        })
        .onClick(() => {
          this.fullscreenTransformClickUntil = Date.now() + 300;
          this.cancelDelayHide();
          this.resetFullscreenVideo();
          this.cv = true;
          this.resetCT();
        })
      }.width('100%').height(36).justifyContent(FlexAlign.Center)
        .position({ left: 0, bottom: this.isLs ? 100 : 200 }).zIndex(10)
        .hitTestBehavior(HitTestMode.Transparent)
        .visibility((this.fs ? this.cv : !this.referenceInfoHidden) && !this.lk && !this.ip &&
          !this.mp && !this.isLightsOff ? Visibility.Visible : Visibility.Hidden)
    }
  }

  @Builder
  buildPlayerOverlay() {
    Stack() {
      XComponent({ id: 'video_xc', type: XComponentType.SURFACE, controller: this.xc })
        .onLoad(() => this.onPlaybackSurfaceLoaded(false))
        .width(this.referenceSecondSurfaceActive ? (this.portraitScaleByTransform() ? this.portraitBaseW() : this.referenceWarmSurfaceWidth()) : (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceW : (this.portraitScaleByTransform() ? this.portraitBaseW() : this.ovVideoW())))
        .height(this.referenceSecondSurfaceActive ? (this.portraitScaleByTransform() ? this.portraitBaseH() : this.referenceWarmSurfaceHeight()) : (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceH : (this.portraitScaleByTransform() ? this.portraitBaseH() : this.ovVideoH())))
        // ⚠️ 这里必须写成"缩小动画期间 = SHRINK_ANIM_DURATION"，**不能写 0**。
        //    实测结论：节点自带的 .animation() 会**覆盖**外层 animateTo（不是相反）——
        //      duration 写 120 → 这一层只走 120ms，比详情卡/评论区先到位（最初的现象）；
        //      duration 写 0   → 这一层直接瞬跳到位，反而更不同步。
        //    所以只能让它与 animateVidShrink 里那条共享 animateTo **完全同参**（300ms + EaseOut）。
        //    其余场景（旋转/分支切换）仍走 120ms，保持不变。
        // Reference layouts share gesture/animateTo progress with the divider
        // and detail panel. A per-node animation makes the Surface lag behind.
        .animation(this.fullscreenRotationTransition || this.referenceLayout ? undefined :
          { duration: this.shrinkAnimating ? this.SHRINK_ANIM_DURATION : 120, curve: Curve.EaseOut })
        .constraintSize({ minWidth: 1, minHeight: 1 }) // ⭐ 窗口模式切换瞬时 0 尺寸布局时保底，防 surface 被杀
        .borderRadius(this.referenceLayout ? (this.isLs ? this.fsLerpRadius(0, this.cardBorderRadius) : 0) : this.fsLerpRadius(this.cardBorderRadius, 0))
        .clip(true)
        .backgroundColor(this.ovPlateBg())
        .scale({ x: (this.referenceMirrorVideo ? -1 : 1) * this.fullscreenVideoScale * (this.referenceLandscapeResizeActive ? this.ovVideoW() / this.referenceResizeSurfaceW : 1) * this.portraitScaleFactor(), y: this.fullscreenVideoScale * (this.referenceLandscapeResizeActive ? this.ovVideoH() / this.referenceResizeSurfaceH : 1) * this.portraitScaleFactor() })
        .rotate({ angle: this.fullscreenVideoAngle })
        .translate({ x: this.fullscreenVideoX, y: this.fullscreenVideoY })
        .opacity(this.referenceSecondSurfaceActive ? 0 : 1)
        // Native Surface composition may ignore opacity; keep the spare slot offscreen.
        .position({ x: this.floatingMorph || this.referenceSecondSurfaceActive || (this.referenceFeedPreviewPinned && !this.referenceFeedSurfaceReady) ? -this.cw * 3 : (this.ovRectW() - (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceW : (this.portraitScaleByTransform() ? this.portraitBaseW() : this.ovVideoW()))) / 2,
          y: this.referenceSecondSurfaceActive ? 0 : (this.ovRectH() - (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceH : (this.portraitScaleByTransform() ? this.portraitBaseH() : this.ovVideoH()))) / 2 })
        .hitTestBehavior(HitTestMode.None)
        .animation(undefined)

      if (this.referenceSpareSurfaceMounted || this.referenceSecondSurfaceActive || !this.referenceLayout) {
      XComponent({ id: 'reference_feed_video_xc', type: XComponentType.SURFACE, controller: this.referencePreviewXc })
        .onLoad(() => this.onPlaybackSurfaceLoaded(true))
        .width(this.referenceSecondSurfaceActive ? (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceW : (this.portraitScaleByTransform() ? this.portraitBaseW() : this.ovVideoW())) : (this.portraitScaleByTransform() ? this.portraitBaseW() : this.referenceWarmSurfaceWidth()))
        .height(this.referenceSecondSurfaceActive ? (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceH : (this.portraitScaleByTransform() ? this.portraitBaseH() : this.ovVideoH())) : (this.portraitScaleByTransform() ? this.portraitBaseH() : this.referenceWarmSurfaceHeight()))
        // ⚠️ 这里必须写成"缩小动画期间 = SHRINK_ANIM_DURATION"，**不能写 0**。
        //    实测结论：节点自带的 .animation() 会**覆盖**外层 animateTo（不是相反）——
        //      duration 写 120 → 这一层只走 120ms，比详情卡/评论区先到位（最初的现象）；
        //      duration 写 0   → 这一层直接瞬跳到位，反而更不同步。
        //    所以只能让它与 animateVidShrink 里那条共享 animateTo **完全同参**（300ms + EaseOut）。
        //    其余场景（旋转/分支切换）仍走 120ms，保持不变。
        .animation(this.fullscreenRotationTransition || this.referenceLayout ? undefined :
          { duration: this.shrinkAnimating ? this.SHRINK_ANIM_DURATION : 120, curve: Curve.EaseOut })
        .constraintSize({ minWidth: 1, minHeight: 1 }) // ⭐ 窗口模式切换瞬时 0 尺寸布局时保底，防 surface 被杀
        .borderRadius(this.referenceLayout ? (this.isLs ? this.fsLerpRadius(0, this.cardBorderRadius) : 0) : this.fsLerpRadius(this.cardBorderRadius, 0))
        .clip(true)
        .backgroundColor(this.ovPlateBg())
        .scale({ x: (this.referenceMirrorVideo ? -1 : 1) * this.fullscreenVideoScale * (this.referenceLandscapeResizeActive ? this.ovVideoW() / this.referenceResizeSurfaceW : 1) * this.portraitScaleFactor(), y: this.fullscreenVideoScale * (this.referenceLandscapeResizeActive ? this.ovVideoH() / this.referenceResizeSurfaceH : 1) * this.portraitScaleFactor() })
        .rotate({ angle: this.fullscreenVideoAngle })
        .translate({ x: this.fullscreenVideoX, y: this.fullscreenVideoY })
        .opacity(this.referenceSecondSurfaceActive ? 1 : 0)
        .position({ x: !this.floatingMorph && this.referenceSecondSurfaceActive && (!this.referenceFeedPreviewPinned || this.referenceFeedSurfaceReady) ? (this.ovRectW() - (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceW : (this.portraitScaleByTransform() ? this.portraitBaseW() : this.ovVideoW()))) / 2 : -this.cw * 3,
          y: this.referenceSecondSurfaceActive ? (this.ovRectH() - (this.referenceLandscapeResizeActive ? this.referenceResizeSurfaceH : (this.portraitScaleByTransform() ? this.portraitBaseH() : this.ovVideoH()))) / 2 : 0 })
        .hitTestBehavior(HitTestMode.None)
        .animation(undefined)

      }
      if (this.floatingPausedFrame && !this.play) {
        Image(this.floatingPausedFrame).width(this.ovVideoW()).height(this.ovVideoH()).objectFit(ImageFit.Fill)
          .position({ x: (this.ovRectW() - this.ovVideoW()) / 2, y: (this.ovRectH() - this.ovVideoH()) / 2 })
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.referenceLayout && this.referenceFeedPreviewPinned && !this.referencePortraitFeedActive()) {
        Image(this.referencePinnedFrame || this.referencePinnedCover || this.vi.cover).width(this.ovVideoW()).height(this.ovVideoH())
          .syncLoad(true).objectFit(this.effectiveScaleMode() === 'stretch' ? ImageFit.Fill : this.effectiveScaleMode() === 'fill' ? ImageFit.Cover : ImageFit.Contain).backgroundColor(Color.Black).hitTestBehavior(HitTestMode.None)
          .scale({ x: (this.referenceMirrorVideo ? -1 : 1) * this.fullscreenVideoScale, y: this.fullscreenVideoScale })
          .rotate({ angle: this.fullscreenVideoAngle })
          .translate({ x: this.fullscreenVideoX, y: this.fullscreenVideoY })
      }
      if (this.referenceSubtitleEnabled && this.referenceSubtitleText && !this.referenceCleanViewing()) {
        Text(this.referenceSubtitleText).fontSize(this.referenceSubtitleLarge ? 20 : 16).fontColor(Color.White).textAlign(TextAlign.Center)
          .textShadow({ radius: 2, color: '#000000', offsetX: 1, offsetY: 1 })
          .width(Math.max(1, this.ovVideoW() - 24)).position({ left: this.ovDanmakuX() + 12, bottom: 18 })
          .hitTestBehavior(HitTestMode.None)
      }

      // 旧版布局保留加载预览，当前播放布局直接等待视频首帧。

      // ⭐ 弹幕层（叠加在视频上；关灯+视频外弹幕由分支内的外移实例承接）
      //   挂载条件只保留"数据可用性 + 布局分支"，【开关状态不再参与卸载】。
      //   原先 `isDanmakuEnabled` 在这里 → 开关弹幕 = 组件销毁重建 = 新建 controller
      //   + 重新下载弹幕分段（万条弹幕约 4 秒空窗 + 重复流量）。
      //   现在常驻挂载，显隐用 visibility，停帧用 config.enable（渲染链自带该判断）。
      //   ⚠️ 必须用 Hidden 而不是 None：None 会让 Canvas 量不到尺寸，
      //      onCanvasReady 走进"尺寸无效"分支，canvasReady 永远为 false → 弹幕永不初始化。
      if (this.vi.cid > 0 &&
        !(this.isLightsOffDanmakuOutside() && !this.isLs && !this.fs) && !this.isLightsOffDanmakuRight()) {
        // ⭐ 弹幕层自己的定位容器：**尺寸 = 播放器区域**（全屏＝整屏，含左右黑边），居中于常驻层。
        //    之前直接铺满常驻层 → 非全屏横屏下会越出视频槽，把弹幕画到右侧评论栏上。
        Stack() {
          ForEach([this.vi.cid], (cid: number) => {
          DanmakuView({
            cid: cid,
            aid: this.vd?.aid || 0,
            duration: this.dur * 1000,
            currentTime: this.ct * 1000,
            isPlaying: this.play,
            cookie: AppStorage.get<string>('biliCookie') || '',
            // ⚠️ 传参必须与容器同源（同一套尺寸），否则又是两套尺寸
            canvasWidth: this.dmTransformChannel() ? this.portraitBaseW() : this.ovDanmakuCW(),
            canvasHeight: this.dmTransformChannel() ? this.portraitBaseH() : this.ovDanmakuCH(),
            // ⭐ 字号 ×1.2 的唯一判据：真·全屏 / 横屏。**不能用画布比例代替** ——
            //   竖屏播放页的视频区本身就是 16:9，比例判定会把它也当成横屏（100% 变 34 号字）。
            isFullscreen: this.fs || this.isLs,
            config: $danmakuConfig,
            selfDanmaku: $selfDanmakuList,
          })
            .width('100%')
            .height('100%')
          // ⭐ **缩小态全程**隐藏弹幕（不只是那 300ms 动画期间）：缩小后是个 120vp 的小窗（默认正圆），
          //    弹幕在里面既看不清也只剩几条，还会持续占主线程 —— 用户明确要求缩小时不显示弹幕。
          //    配合 animateVidShrink 里把 config.enable 也置 false（停掉渲染循环，而不只是不绘制）。
            //    ⚠️ 用 Hidden 而不是 None —— None 会让 Canvas 量不到尺寸，canvasReady 永远为 false，
            //       弹幕就再也初始化不起来了（见上方挂载条件的注释）。
            .visibility(this.isDanmakuEnabled && !this.isVidShrunk() ? Visibility.Visible : Visibility.Hidden)
          }, (cid: number) => cid.toString())
        }
        // ⭐ 缩小/还原动画期间用冻结尺寸（见 dmFreezeW 注释）：画布尺寸逐帧变化会让 ArkUI
        //    每帧重建 surface + 重建轨道（实测 300ms 内 19 次 → 掉帧）。
        // ⭐ 竖屏播放区缩放同理：固定基准画布 + scale，拖动面板时不再重建 canvas surface。
        .width(this.shrinkAnimating && this.dmFreezeW > 0 ? this.dmFreezeW : (this.dmTransformChannel() ? this.portraitBaseW() : this.ovDanmakuCW()))
        .height(this.shrinkAnimating && this.dmFreezeH > 0 ? this.dmFreezeH : (this.dmTransformChannel() ? this.portraitBaseH() : this.ovDanmakuCH()))
        .position({
          x: this.shrinkAnimating && this.dmFreezeW > 0
            ? Math.max(0, (this.ovRectW() - this.dmFreezeW) / 2)
            : (this.dmTransformChannel() ? (this.ovRectW() - this.portraitBaseW()) / 2 : this.dmPositionX()),
          y: this.shrinkAnimating && this.dmFreezeH > 0
            ? Math.max(0, (this.ovRectH() - this.dmFreezeH) / 2)
            : (this.dmTransformChannel() ? (this.ovRectH() - this.portraitBaseH()) / 2 : this.dmPositionY())
        })
        .scale({ x: this.dmScaleFactor(), y: this.dmScaleFactor() })
        .clip(true)   // 兜底：任何情况下都不画到视频画面外
      }
      VideoControls({
        hdrUiRatio: this.hdrUiRatio(),
        isCompleted: this.referencePlaybackCompleted,
        bufferedUntil: this.bufferedUntil,
        onReplay: () => { this.referenceReplay(); },
        referenceHalfScreen: this.referenceHalfScreenControlsActive(),
        referenceLandscapeHalfScreen: this.referenceHalfScreenControlsActive() && this.isLs,
        referenceLandscapeFullscreen: this.referenceLayout && this.fs && this.isLs,
        hidePlaybackControls: this.referenceLayout && !this.fs && !this.isLs && (this.referenceFeed || this.referenceModeAnimating),
        isPlaying: $play,
        videoTitle: this.vd?.title || this.vi.title || '',
        videoOwnerFace: this.vd?.owner?.face ? imageUrlResize(this.vd.owner.face, 48) : '',
        videoOwnerName: this.vd?.owner?.name ?? '',
        isFollowed: this.isFollowed,
        followColor: this.playerFollowTheme ? this.customThemeColor : '#FB7299',
        toggleFollow: () => { this.toggleFollow(); },
        currentTime: $ct,
        duration: $dur,
        isControlsVisible: $cv,
        isLocked: $lk,
        isFullscreen: $fs,
        isMirrorControls: $isMirrorControls,
        isMuted: $mute,
        playbackRate: $rt,
        showGestureHint: $gh,
        gestureHintMainText: $ght,
        gestureHintProgress: $ghp,
        gestureHintType: $ghtType,
        // ⭐ 手指是否仍按着（音量/亮度竖条的亮光与粒子只在调节期出现）
        gestureHintActive: $ghActive,
        gestureHintMotion: this.ghMotion,
        outputUsesHeadphones: this.outputUsesHeadphones,
        outputHeadphoneIcon: this.outputHeadphoneIcon,
        // ⭐ 本次进度调节的起点秒数（提示胶囊右侧显示 +10S / -10S 用）
        gestureHintBase: $ghb,
        // ⭐ 进度调节缩略图（与上面那组提示同源；无缩略图的视频该对象恒为 show=false，不占位）
        thumb: $thumb_,
        showBottomHint: $bh,
        bottomHintImage: $bhi,
        bottomHintText: $bht,
        showUnlockButton: this.ub,
        // ⭐ 提示弹层把"返回"转交回本页（弹层吃掉了系统返回键/侧滑，见 VideoControls 弹层注释）
        onOverlayBack: () => { this.onOverlayBack_(); },
        onBackPress: () => { if (this.fs) { this.toggleFS(); } else { this.goBack(); } },
        onHomePress: () => { this.goHome(); },
        togglePlayPause: () => { this.togglePP(); },
        seekTo: (time: number) => { this.seek(time, false, true); },
        // ⭐ 进度条交互（Slider 的 Down / Up / Cancel）：拖动中冻结 ct 并抑制控制栏自动隐藏，
        //   松手统一提交一次。详见 onSeekBarInteract_
        onSeekBarInteract: this.onSeekBarInteract_,
        formatTime: this.fmtT,
        setPlaybackRate: (rate: number) => { this.setRate(rate); },
        toggleLock: () => { this.handlingUnlockClick = true; this.toggleLock(); },
        onMirrorToggle: () => { this.onMirrorToggle(); },
        toggleMute: () => { this.toggleMute(); },
        hasNextEpisode: this.hasNextEpisode(),
        hasPreviousEpisode: this.currentPageIndex > 0,
        togglePreviousEpisode: () => { this.cancelDelayHide(); this.triggerHaptic(); this.switchEpisode(this.currentPageIndex - 1); },
        toggleNextEpisode: () => { this.cancelDelayHide(); this.triggerHaptic(); this.switchEpisode(this.currentPageIndex + 1); },
        toggleFullscreen: () => { this.toggleFS(); },
        showColorStyleOptions: () => { /* 暂禁用，等 SDK 更新后启用 */ },
        showScaleOptions: () => { this.cancelDelayHide(); if (!this.sp) { this.cv = false; } this.sp = !this.sp; this.ip = this.sp; },
        bottomQualities: this.getQlList(), bottomQuality: this.qn,
        bottomSubtitleTracks: this.referenceSubtitleOptions, bottomSubtitleIndex: this.referenceSelectedSubtitleIndex,
        bottomSubtitleLarge: this.referenceSubtitleLarge, bottomSubtitleLoading: this.referenceSubtitleMenuLoading,
        bottomSubtitleFailed: this.referenceSubtitleMenuFailed,
        onBottomMenuVisible: (visible: boolean) => { if (visible) this.cancelDelayHide(); else this.resetCT(); },
        onBottomRate: (rate: number) => { this.setRate(rate); },
        onBottomQuality: (qn: number) => { this.switchQ(qn); },
        onBottomSubtitlePrepare: () => { this.referenceOpenLandscapeSubtitles(true); },
        onBottomSubtitle: (index: number) => { this.referenceSelectSubtitle(index); },
        onBottomSubtitleLarge: (large: boolean) => { this.referenceSubtitleLarge = large; },
        showQualityOptions: () => { this.cancelDelayHide(); if (!this.qp) { this.cv = false; } this.qp = !this.qp; this.ip = this.qp; },
        showSpeedOptions: () => {
          this.cancelDelayHide();
          if (!this.rp) {
            this.cv = false;
            this.rp = true;
            this.ip = true;
          } else {
            this.rp = false;
            this.ip = false;
            this.cv = true;
            this.resetCT();
          }
        },
        // ⭐ 更多菜单
        onMorePress: () => {
          this.cancelDelayHide();
          if (this.fs) {
            if (this.referenceLayout && !this.mp) {
              this.cv = false;
              // Let the triggering pointer-up finish before the full-screen drawer is mounted;
              // otherwise its full-screen dismiss layer can consume the same tap and close it.
              setTimeout(() => { this.referenceSetMoreDrawer(true); }, 180);
            } else {
              this.mp = !this.mp;
              this.ip = this.mp;
            }
          } else {
            if (!this.mpb) { this.cv = false; }
            this.mpb = !this.mpb;
            this.ip = this.mpb;
          }
        },
        // ⭐ 弹幕开关
        isDanmakuEnabled: $isDanmakuEnabled,
        toggleDanmaku: () => { this.toggleDanmaku(); },
        onDanmakuPress: () => { this.showDanmakuSheet = true; },
        onDanmakuSettingsPress: () => { this.openDanmakuSettingSheet(); },
        onSubtitlePress: () => {
          if (this.referenceLayout && this.isLs) this.referenceOpenLandscapeSubtitles();
          else this.referenceSetSubtitles(!this.referenceSubtitleEnabled);
        },
        onSharePress: () => { this.referencePortraitAction('share:player'); },
        onScreenshotPress: () => {
          this.getUIContext().getPromptAction().showToast({ message: '请使用系统截屏保存当前画面' });
        },
        onLikePress: () => { this.toggleLike(); },
        onDislikePress: () => { this.referenceDislike(); },
        onCoinPress: () => { this.toggleCoin(1); },
        isLiked: this.isLiked,
        isDisliked: this.isDisliked,
        isCoined: this.isCoined,
        isSubtitleEnabled: this.referenceSubtitleEnabled,
        likeCountLabel: this.fmtN(this.likeCount),
        onEpisodePress: () => { this.cancelDelayHide(); this.triggerHaptic(); this.openEpisodeSheet(); },
        // ⭐ 全屏评论浮层开关：打开时 ip=true + cancelDelayHide 保控制栏不自动隐藏，关闭后恢复延迟隐藏
        onCommentPress: () => { this.cancelDelayHide(); this.cp = !this.cp; this.ip = this.cp; if (!this.cp && this.cv) { this.resetCT(); } this.cv = !this.cp; },
        hasMultipleEpisodes: this.pagesForCurrentVideo().length > 1,
        isBackgroundPlayback: $bgp,
        qualityLabel: this.ql,
        toggleBackgroundPlayback: () => { this.toggleBackgroundPlayback(); }
      }).width('100%').height('100%')
        .visibility(this.referenceCleanViewing() ? Visibility.Hidden : Visibility.Visible)
        .opacity(this.fs && this.isLightsOff ? 0 : 1)
        .hitTestBehavior(this.fs && this.isLightsOff ? HitTestMode.Block : HitTestMode.Default)
        .animation(this.referenceLayout ? undefined : { duration: 300 })

      // ⭐ 手势提示（原全屏/竖屏分支各自挂载，现统一在常驻层；关灯时全屏隐藏、竖屏保留原样）
      if (this.referenceLayout && (this.waitingForFirstFrame || (this.ld && !this.referenceFeed)) && !this.err && !this.referenceFeedPreviewPinned) {
        Column({ space: 8 }) {
          LoadingProgress().width(28).height(28).color('#FFFFFF')
          Text('正在加载视频…').fontSize(12).fontColor('#D8D8D8')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
      }
      if (this.referenceLayout && this.err && !this.referenceFeedPreviewPinned) {
        Column({ space: 12 }) {
          Text('视频暂时无法播放').fontSize(14).fontColor('#E7E9EB')
          Button('点击重试').fontSize(13).fontColor('#FFFFFF').backgroundColor('#803D4148')
            .onClick(() => { this.retry(); })
        }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      }
      if (this.rh && (!this.isLightsOff || !this.fs) && !this.referenceCleanViewing()) {
        Column() {
          Text(this.rht).fontSize(24).fontColor($r('app.color.color_player_text'))
            .fontWeight(FontWeight.Bold).opacity(0.9)
            .padding({ left: 20, right: 20, top: 12, bottom: 12 })
            .backgroundColor($r('app.color.color_overlay_dark')).borderRadius(16);
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      }
    }
    .position({ x: this.ovRectX(), y: this.ovRectY() })
    .width(this.ovRectW())
    .height(this.ovRectH())
    .clip(false)
    // ⚠️ 同 XComponent：缩小/还原期间必须与共享 animateTo **同参**（300ms + EaseOut），不能写 0。
    //    原因见 XComponent 那条注释 —— 节点自带的 .animation() 覆盖外层 animateTo，
    //    写 0 会让这一层瞬跳、写 120 会让它先到位，两者都不同步。
    .animation(this.fullscreenRotationTransition || this.referenceLayout ? undefined :
      { duration: this.shrinkAnimating ? this.SHRINK_ANIM_DURATION : 120, curve: Curve.EaseOut })
    // ⭐ 透明度必须在 .animation() 之后：这样它由外层 animateTo 驱动，与 vidShrink 同步 300ms 淡出；
    //    若写在 .animation() 之前，会被那条 120ms 的隐式动画接管而先到位。
    .opacity(this.shrinkPlateOpacity())
    // ⭐ 圆角：非全屏时改由 shrinkRadius() 给值 —— 缩小时它随 vidShrink 从卡片圆角连续过渡到
    //    方框边长的一半（= 正圆），配合 shrinkSlotW/H 的正方形外框裁出圆形小窗。
    //    全屏时仍走原来的 fsLerpRadius（20 ↔ 卡片圆角）。非缩小时两者取值相同，行为不变。
    .borderRadius(this.referenceLayout ? (this.isLs ? this.fsLerpRadius(0, this.cardBorderRadius) : 0) : (this.fs ? this.fsLerpRadius(20, this.cardBorderRadius) : this.shrinkRadius()))
    // In the continuous feed, transformed video can extend into the original letterboxing.
    // The page still clips to the screen; details and comment layouts keep their slot clipping.
    .clip(!this.referencePortraitFeedActive() || this.referenceFeedComments)
    .backgroundColor($r('app.color.color_player_background'))
    // A grouped offscreen layer also crops overflow to its texture bounds, even with clip(false).
    // HDR controls must reach the HDR compositor without an ancestor's SDR
    // group cache flattening their extended-range foreground into a texture.
    .renderGroup(this.qn !== 125 && this.qn !== 126 &&
      (!this.referencePortraitFeedActive() || this.referenceFeedComments))
    .saturate(this.saturateVal_)
    .contrast(this.contrastVal_)
    .brightness(this.brightnessVal_)
    .sepia(this.sepiaVal_)
    .colorBlend(this.colorBlendVal_)
    .onTouch((event: TouchEvent) => {
      if (this.referenceLayout && this.referenceFeed && !this.fs && !this.isLs) return;
      this.onVT(event);
    })
    .onClick(() => {
      if (this.lk) this.tglUB();
      else if (this.referenceFeed && !this.fs && !this.isLs && !this.mp) this.referenceHandleFeedClick();
    })
    // ⭐ 横屏/竖屏横看：右滑进全屏——手势起点在视频上时由常驻层识别（视频区已不再属于分支容器）
    .gesture(
      PanGesture({ direction: PanDirection.Right, distance: 20 })
        .onActionUpdate((event: GestureEvent) => {
          if (this.referencePortraitFeedActive()) return;
          if (this.fs || (!this.isLs && !this.isLandscapeVertical)) return;
          // ⭐ 进度条交互中让位（官方：stopPropagation 只拦 onTouch，拦不住父节点的手势对象）
          if (this.sliderDragging_) return;
          if (this.gm_ === 'seek') return;
          let p = Math.min(1, Math.pow(event.offsetX / 195, 1.2));
          if (p > 0.02) this.updateFSPanProgress(p);
        })
        .onActionEnd(() => {
          if (this.referencePortraitFeedActive()) return;
          if (this.fs || (!this.isLs && !this.isLandscapeVertical)) return;
          if (this.gm_ === 'seek') {
            animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 260, curve: Curve.EaseOut }, () => { this.fsPanProgress = 0; });
            return;
          }
          if (this.fsPanProgress > 0.3) this.startFSAnimation();
          else animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 260, curve: Curve.EaseOut }, () => { this.fsPanProgress = 0; });
        })
        .onActionCancel(() => {
          if (this.referencePortraitFeedActive()) return;
          if (this.fs || (!this.isLs && !this.isLandscapeVertical)) return;
          animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 200, curve: Curve.EaseOut }, () => { this.fsPanProgress = 0; });
          this.fireHaptic(18);
        })
    )
  }

  // ⭐ 横屏非全屏布局（自 build() 抽出，供内容分支常驻渲染复用）

  // ⭐ 横屏评论区（直板机布局开关共用）—— List 真懒加载（Scroll+Column 中 LazyForEach 不生效）


  private commentComposerViewportHeight(): number {
    return Math.min(this.commentComposerHeight,
      Math.max(100, this.ch - this.danmakuKeyboardHeight - this.referenceSafeTop()));
  }

  private commentComposerTargetWidth(): number {
    return this.isLs && !this.fs ? this.referenceLandscapeViewportWidth() : this.cw;
  }

  private commentComposerFrameWidth(): number {
    return this.commentComposerOrigin[2] +
      (this.commentComposerTargetWidth() - this.commentComposerOrigin[2]) * this.commentComposerProgress;
  }

  private commentComposerFrameHeight(): number {
    return 40 + (this.commentComposerViewportHeight() - 40) * this.commentComposerProgress;
  }

  private commentComposerFrameX(): number {
    const target = this.isLs && !this.fs ? this.referenceLandscapePlayerX() : 0;
    return this.commentComposerOrigin[0] + (target - this.commentComposerOrigin[0]) * this.commentComposerProgress;
  }

  private commentComposerFrameY(): number {
    const target = Math.max(this.referenceSafeTop(), this.ch - this.danmakuKeyboardHeight - this.commentComposerHeight);
    return this.commentComposerOrigin[1] + (target - this.commentComposerOrigin[1]) * this.commentComposerProgress;
  }

  private captureCommentComposerOrigin(mode: string): void {
    const width = this.commentComposerTargetWidth();
    const left = this.isLs && !this.fs ? this.referenceLandscapePlayerX() : 0;
    this.commentComposerOrigin = [left + width * 0.03, this.ch - this.navIndicatorHeight - 48, width * 0.94, 40];
    if (mode !== 'new') return;
    try {
      const utils = this.getUIContext().getComponentUtils();
      const source = utils.getRectangleById('floating-comment-entry');
      const host = utils.getRectangleById('video-player-page');
      const x = this.getUIContext().px2vp(source.windowOffset.x - host.windowOffset.x);
      const y = this.getUIContext().px2vp(source.windowOffset.y - host.windowOffset.y);
      const w = this.getUIContext().px2vp(source.size.width);
      const h = this.getUIContext().px2vp(source.size.height);
      if (w > 0 && h > 0 && y >= 0 && y + h <= this.ch + 1) {
        this.commentComposerOrigin = [x, y, w, h];
      }
    } catch (_) {}
  }

  private animateCommentComposer(target: number): void {
    this.commentComposerAnimator?.cancel();
    const from = this.commentComposerProgress;
    const animation = Animator.create({ duration: target === 1 ? 300 : 240,
      easing: target === 1 ? 'cubic-bezier(0.2, 0, 0, 1)' : 'cubic-bezier(0.4, 0, 0.2, 1)',
      delay: 0, direction: 'normal', iterations: 1, fill: 'forwards', begin: 0, end: 1 });
    this.commentComposerAnimator = animation;
    animation.onframe = (progress: number) => { this.commentComposerProgress = from + (target - from) * progress; };
    animation.onfinish = () => {
      this.commentComposerProgress = target;
      this.commentComposerAnimator = null;
      if (target === 0 && this.commentComposerClosing) {
        // Keep the same editor and native material mounted until the return to the capsule completes.
        this.commentSheetVisible = false;
        this.commentComposerClosing = false;
      }
    };
    animation.play();
  }

  private closeCommentComposer(): void {
    if (!this.commentSheetVisible || this.commentComposerClosing) return;
    this.commentComposerClosing = true;
    clearTimeout(this.commentComposerStartTimer);
    this.commentComposerStartTimer = 0;
    this.getUIContext().getFocusController().clearFocus();
    this.animateCommentComposer(0);
  }

  private backCommentComposer(): void {
    if (this.commentComposerClosing || this.cmSheetEmoteCtrl.collapseEmote()) return;
    if (this.danmakuKeyboardHeight > 1) {
      this.getUIContext().getFocusController().clearFocus();
      return;
    }
    this.closeCommentComposer();
  }

  @Builder
  ReferenceCommentComposer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .opacity(this.commentComposerProgress)
        .onClick(() => { this.closeCommentComposer(); })
      // The native rim belongs to the viewport, not the scrollable editor content.
      Column() {
        NativeComposerSurface({ rounding: 20 - 8 * this.commentComposerProgress,
          lowerRounding: 20 * (1 - this.commentComposerProgress) }) {
          Scroll() { this.commentSheetContent() }
            .scrollBar(BarState.Off).width('100%').height(this.commentComposerFrameHeight())
            .opacity(Math.max(0, Math.min(1, (this.commentComposerProgress - 0.15) / 0.65)))
            .backgroundColor(Color.Transparent).clip(true).id('comment-composer-scroll')
        }
      }.width(this.commentComposerFrameWidth())
        .height(this.commentComposerFrameHeight())
        .borderRadius({ topLeft: 20 - 8 * this.commentComposerProgress, topRight: 20 - 8 * this.commentComposerProgress,
          bottomLeft: 20 * (1 - this.commentComposerProgress), bottomRight: 20 * (1 - this.commentComposerProgress) }).clip(true)
        .position({ x: this.commentComposerFrameX(), y: this.commentComposerFrameY() })
        .enabled(!this.commentComposerClosing)
        .id('comment-composer')
        .onAppear(() => {
          this.commentComposerStartTimer = setTimeout(() => {
            this.commentComposerStartTimer = 0;
            if (this.commentSheetVisible && !this.commentComposerClosing && this.referenceAlive) {
              this.getUIContext().getFocusController().requestFocus('comment_rich_editor');
              // Start with the keyboard height event, so expansion and lift share the same first frame.
              // A hardware keyboard may not emit a height event; still allow the editor to open.
              this.commentComposerStartTimer = setTimeout(() => {
                this.commentComposerStartTimer = 0;
                if (this.commentSheetVisible && !this.commentComposerClosing && this.referenceAlive &&
                  this.commentComposerProgress === 0 && !this.commentComposerAnimator) this.animateCommentComposer(1);
              }, 320);
            }
          }, 32);
        })
    }.width('100%').height('100%').zIndex(100)
  }

  // ⭐ 评论排序按钮组（最热 / 最新）
  @Builder
  commentSheetContent() {
    Column() {
      CommentInputBar({
        materialEnabled: false,
        autoFocus: false,
        ctrl: this.cmSheetEmoteCtrl,
        onHeightChange: (height: number) => { this.commentComposerHeight = height; },
        placeholder: this.commentSheetMode === 'reply' ? `回复 @${this.replyTargetName}：` : '发一条友善的评论',
        showImageButton: this.commentSheetMode !== 'reply',
        onSend: (content: string, pictures: CommentImageDraft[]) => {
          return this.handleCommentSend(content, pictures);
        }
      })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
  }

  /** 发送评论/回复：图片草稿先逐张上传图床，随文本一起提交；成功返回 true（父层关弹层） */
  private async handleCommentSend(content: string, pictures: CommentImageDraft[]): Promise<boolean> {
    const aid = this.vd?.aid || 0;
    if (!aid) {
      this.getUIContext().getPromptAction().showToast({ message: '评论失败：缺少视频ID' });
      return false;
    }
    // 图片先逐张上传到图床，得到 URL/宽高后再随评论提交
    let picturesJson = '';
    if (pictures.length > 0) {
      const imgs: string[] = [];
      for (const p of pictures) {
        const up = await uploadCommentImage(p.path, p.mime, p.ext);
        if (!up || !up.url) {
          this.getUIContext().getPromptAction().showToast({ message: '图片上传失败' });
          return false;
        }
        imgs.push(JSON.stringify({ img_src: up.url, img_width: up.width, img_height: up.height }));
      }
      picturesJson = '[' + imgs.join(',') + ']';
    }
    const publishedRoot = this.replyRoot;
    const res = await addVideoComment(aid, content, publishedRoot, this.replyParent, picturesJson);
    if (!res.ok) {
      this.getUIContext().getPromptAction().showToast({ message: res.message || '发表失败，请稍后再试', duration: 2000 });
      return false;
    }
    this.getUIContext().getPromptAction().showToast({ message: this.commentSheetMode === 'reply' ? '回复成功' : '评论成功' });
    this.closeCommentComposer();
    this.replyRoot = 0;
    this.replyParent = 0;
    this.replyTargetName = '';
    if (this.commentThread && this.commentThread.rpid === publishedRoot) {
      this.commentThread.rcount++;
      this.commentThreadRefresh++;
      return true;
    }
    // ⭐ 游标归零后重载第一页，保持当前排序（最热/最新）
    this.commentCursor = 0;
    this.loadC(aid);
    return true;
  }

  /** 打开评论输入弹层（写评论或回复），未登录先拦截 */
  private openCommentSheet(mode: string, root: number, parent: number, targetName: string): void {
    if (!this.biliCookie.includes('SESSDATA')) {
      this.getUIContext().getPromptAction().showToast({ message: '请先登录' });
      return;
    }
    if (this.commentSheetVisible) return;
    this.captureCommentComposerOrigin(mode);
    this.commentComposerProgress = 0;
    this.commentComposerClosing = false;
    this.commentComposerHeight = 184;
    this.commentSheetMode = mode;
    this.replyRoot = root;
    this.replyParent = parent;
    this.replyTargetName = targetName;
    this.commentSheetVisible = true;
  }

  /** ⭐ 评论区核心（排序栏+List+LazyForEach+加载更多/空态/限态）：竖屏分支与全屏评论浮层共用；
   *  hideOnTransition=true（竖屏）：转场期移出布局+渐显；浮层传 false（显隐由浮层自身条件挂载控制） */
  @Builder
  commentListCore(hideOnTransition: boolean, useFsScroller: boolean, inRefresh: boolean = false) {
      List({ scroller: useFsScroller ? this.fsCommentScroller : this.commentScroller }) {
        ListItem() { Column() { this.commentSortBar() }.width('100%').padding({ left: 12, right: 12 }) }
        if (this.commentDataSource.totalCount() > 0) {
          LazyForEach(this.commentDataSource, (c: ObservableComment, i: number) => {
            ListItem() {
              Column() {
                CommentItemComponent({
                  picBoxW: this.commentPicBoxW(), picBoxH: this.commentPicBoxH(),
                  comment: c,
                  isLast: i === this.commentDataSource.totalCount() - 1,
                  videoDetail: this.vd,
                  isExpanded: this.expandedCommentIds.has(c.rpid),
                  repliesVersion: this.repliesVersion,
                  onExpandComment: (comment: ObservableComment) => {
                    this.openCommentThread(comment);
                  },
                  onCollapseComment: (rpid: number) => { this._doRemoveExpandedComment(rpid); },
                  onLoadMoreReplies: (comment: ObservableComment) => {
                    this.loadMoreReplies(comment);
                  },
                  onReplyTap: (root: number, parent: number, targetName: string) => {
                    this.openCommentSheet('reply', root, parent, targetName);
                  }
                })
              }
              .width('100%')
              .padding({ left: this.referenceLayout ? 0 : 12, right: this.referenceLayout ? 0 : 12 })
            }
          }, (c: ObservableComment, i: number) => c.rpid > 0 ? c.rpid.toString() : 'empty_' + i)
          if (this.hm) {
            ListItem() {
              Column() {
                Row() {
                  if (this.ldc) {
                    LoadingProgress().width(16).height(16).color(this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'));
                    Text('加载中...').fontSize(12).fontColor($r('app.color.color_player_text_secondary')).margin({ left: 6 });
                  } else {
                    Text('上拉加载更多').fontSize(12).fontColor($r('app.color.color_player_text_secondary'));
                  }
                }
                .width('100%').justifyContent(FlexAlign.Center)
                .padding({ top: 12, bottom: 12 })
              }
              .width('100%').padding({ left: 12, right: 12 })
            }
          }
        } else if (this.ldc) {
          ListItem() {
            Column() { LoadingProgress().width(20).height(20).color(this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink')); }
            .width('100%').height(80).justifyContent(FlexAlign.Center)
          }
        } else if (this.rateLimited) {
          ListItem() {
            Column() {
              Text('评论被限流，请等待片刻')
                .fontSize(13)
                .fontColor($r('app.color.color_player_text_secondary'))
                .margin({ bottom: 16 });
              Button() {
                Row({ space: 4 }) {
                  Image($r('app.media.arrow_clockwise'))
                    .width(14)
                    .height(14)
                    .fillColor(this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'))
                  Text('点击重试')
                    .fontSize(12)
                    .fontColor(this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'))
                }
                .alignItems(VerticalAlign.Center)
              }
              .backgroundColor('rgba(251, 114, 153, 0.15)')
              .borderRadius(999)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => {
                if (this.vd) {
                  this.commentCursor = 0;
                  this.loadC(this.vd.aid);
                }
              })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 40, bottom: 40, left: 12, right: 12 })
          }
        } else {
          ListItem() {
            Column() {
              Text('暂无评论').fontSize(13).fontColor($r('app.color.color_player_text_secondary'))
              Button('重新加载')
                .fontSize(12)
                .fontColor(this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'))
                .backgroundColor('transparent')
                .border({ width: 1, color: this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'), radius: 4 })
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ top: 12 })
                .onClick(() => {
                  if (this.vd) {
                    this.commentCursor = 0;
                    this.loadC(this.vd.aid);
                  }
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 40 })
            .padding({ left: 12, right: 12 })
          }
        }
        ListItem() { Column().width('100%').height(0) }
      }
      .listDirection(Axis.Vertical)
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .contentEndOffset(inRefresh ? 56 + this.navIndicatorHeight : 0)
      // 与动态页一致：List 直接作为 Refresh 子节点，由原生建立滚动联动。
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: inRefresh })
      .cachedCount(inRefresh ? 4 : 1)

      .visibility(hideOnTransition ? this.commentAreaVis() : Visibility.Visible)
      .opacity(hideOnTransition ? this.commentFade : 1)
      .onScrollFrameBegin((offset: number) => {
        // 半屏评论上滑先收播放区，到最小尺寸后由同一列表继续滚动。
        if (this.referenceLayout && !this.fs && !this.isLs && !this.referenceFeedComments &&
          this.at === 1 && offset > 0 && this.referencePanelOffset > this.referenceMinimumPanelOffset()) {
          return { offsetRemain: 0 };
        }
        return { offsetRemain: offset };
      })
      .onWillScroll((xOffset: number, yOffset: number) => {
        if (this.at === 1 && !this.fs && !this.isLs) {
          const shrinkEnabled: boolean = !this.referenceLayout && (AppStorage.get<boolean>('shrinkVideoOnScroll') ?? false);
          if (shrinkEnabled && yOffset > 15 && this.vidShrink < 0.5) {
            this.triggerHaptic();
            this.animateVidShrink(1);
          }
        }
      })
      .onReachEnd(() => {
        if (this.hm && !this.ldc && this.commentDataSource.totalCount() > 0) {
          this.loadMC();
        }
      })
  }

  @Builder
  commentAreaCore(hideOnTransition: boolean, useFsScroller: boolean, cardShell: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
    if (this.fs || !this.referenceLayout) { this.ContentPanelWallpaper() }
    Column() {
      this.commentListCore(hideOnTransition, useFsScroller)
    }
    .width('100%')
    .height('100%')
    // cardShell=true（竖屏页）：评论卡片外壳（背景/边框/圆角/clip）；浮层传 false——裁剪交给面板自身，内容可滚到面板边缘
    .backgroundColor(cardShell ? this.getCardContainerBg(this.cardStyleVideoCommentSection) : Color.Transparent)
    .border(cardShell ? this.getCardContainerBorder(this.cardStyleVideoCommentSection) : { width: 0 })
    .borderRadius(cardShell ? this.cardBorderRadius : 0)
    .clip(cardShell)
    .backdropBlur(useFsScroller ? 25 : 0)
      // 当前半屏布局由 ReferencePanel 唯一持有详情层，避免横屏时内外各挂一份。
      if (this.fs || (!this.referenceLayout && this.isLs)) { this.commentThreadView() }
    }.width('100%').height('100%')
  }

  /** ⭐ 全屏评论浮层：直接显示评论卡片（commentAreaCore 自带卡片外壳），横向右侧竖条/竖向底部横条；
   *  简单条件显隐，不做布局属性动画（避免与 fsPanProgress 全屏动画叠加掉帧） */
  @Builder
  fsCommentPanel() {
    Stack() {
      // 关闭点击区 — 透明占满，点击空白关闭
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => { this.cp = false; this.ip = false; this.cv = true; if (this.cv) this.resetCT(); });

      // 评论卡片（commentAreaCore 自带卡片背景+圆角+clip）
      Column() {
        this.commentAreaCore(false, true, true)
      }
      .width(this.cw > this.ch ? this.cw / 3 : '100%')
      .height(this.cw > this.ch ? '100%' : this.ch / 3)
      .position(this.cw > this.ch
        ? (this.mirrorPopup() ? { left: 0, top: 0 } : { right: 0, top: 0 })
        : { left: 0, bottom: 0 })
    }
    .width('100%')
    .height('100%')
    .transition(
      this.cw > this.ch
        ? TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.EaseInOut })
            .combine(TransitionEffect.translate({ x: this.mirrorPopup() ? '-100%' : '100%' }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.EaseInOut }))
        : TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.EaseInOut })
            .combine(TransitionEffect.translate({ y: '100%' }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 300, curve: Curve.EaseInOut }))
    )
  }


  @Builder
  commentSortBar() {
    Row() {
      Text(this.commentSort === 2 ? '热门评论' : '最新评论').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
      Blank()
      Text(this.commentSort === 2 ? '☰ 按热度' : '☰ 按时间').fontSize(12).fontColor('#757A81')
        .onClick(() => this.switchCommentSort(this.commentSort === 2 ? 1 : 2))
    }.width('100%').height(44).padding({ top: 4, bottom: 4 })
  }

  /** ⭐ 加载等待期预览信息区：封面+时长+UP主+播放量（与视频页背景模式无关，纯色/自定义下也显示） */

  build() {
    Stack() {
    Stack() {
      // ⭐ 关灯背景：当前封面/壁纸 + 模糊 + 黑色压暗（仿 FullImagePreview rgba(0,0,0,0.72)）
      // 常驻渲染（opacity 控制显隐），避免关灯时首次插入 Image 解码导致最后一帧闪烁
      if (this.videoBgMode === 'wallpaper' || this.vi.cover) {
        Image(this.lightsOffBgSrc())
          .width('100%').height('100%')
          .objectFit(ImageFit.Cover)
          .blur(this.loBgBlur)
          .scale({ x: this.loBgScale, y: this.loBgScale })
          .opacity(this.isLightsOff && !this.lightsOffHideOnly ? 1 : 0)
        Column()
          .width('100%').height('100%')
          .backgroundColor(`rgba(0,0,0,${this.loBgDim})`)
          .opacity(this.isLightsOff && !this.lightsOffHideOnly ? 1 : 0)
      }
      // 播放区域保持当前黑色背景；简介面板壁纸由 ContentPanelWallpaper 承载。
      Column().width('100%').height('100%').backgroundColor('#000000');
      // 背景明暗覆盖层
      if (this.cardBgDarkness < 50) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(`rgba(0,0,0,${(50 - this.cardBgDarkness) / 50})`);
      } else if (this.cardBgDarkness > 50) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(`rgba(255,255,255,${(this.cardBgDarkness - 50) / 50})`);
      }

      // ⭐ 更多弹窗挂载容器（独立节点，与选集弹窗 bindSheet 分离）
      Column().width(1).height(1).opacity(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.mpb, this.moreSheetContent(), {
          // ⭐ 高度按菜单项数量算：标题区 ~110 + 每项 48+10，避免新增菜单项后最后一项被裁切
          height: 110 + this.mo_.length * 58,
          backgroundColor: Color.Transparent,
          systemMaterial: MaterialUtil.sheetMaterial(),
          dragBar: true,
          showClose: false,
          onDisappear: () => {
            this.mpb = false;
          }
        })

      // ⭐ 弹幕设置面板挂载容器（与「更多」弹窗分离，避免 mpb/mp 关闭联动）
      Column().width(1).height(1).opacity(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showDanmakuSettingSheet, this.danmakuSettingSheetContent(), {
          height: this.isLs ? SheetSize.LARGE : this.portraitSettingsHeight(),
          backgroundColor: Color.Transparent,
          // The content owns the sole glass surface; Sheet only hosts and positions it.
          blurStyle: BlurStyle.NONE,
          shadow: { radius: 0, color: Color.Transparent },
          dragBar: true,
          showClose: false,
          onDisappear: () => {
            this.showDanmakuSettingSheet = false;
            this.saveDanmakuDisplaySettings();
          }
        })

      // ⭐ 缓存画质弹窗挂载容器（另一个独立节点，与 mpb/选集弹窗均分离）
      Column().width(1).height(1).opacity(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.cacheQnPopup, this.cacheQnSheetContent(), {
          // ⭐ 高度按画质选项数量动态计算，避免底部选项被裁切（标题~36 + 选项数*(48+10) + 底部留白）
          height: 90 + this.getQlList().length * 58,
          backgroundColor: Color.Transparent,
          systemMaterial: MaterialUtil.sheetMaterial(),
          dragBar: true,
          showClose: false,
          onDisappear: () => {
            this.cacheQnPopup = false;
          }
        })

      // ⭐ 合集弹窗挂载容器（独立节点，与选集弹窗 bindSheet 分离）
      Column().width(1).height(1).opacity(0).hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.showSeasonSheet, this.seasonSheetContent(), {
          height: this.selectionSheetHeight(400),
          backgroundColor: Color.Transparent,
          systemMaterial: MaterialUtil.sheetMaterial(),
          dragBar: true,
          showClose: false,
          onDisappear: () => {
            this.showSeasonSheet = false;
          }
        })

      // 主要内容区域（初始为缩小 + 透明，加载完成后居中弹出）
      // ⭐ 用 Stack 而非 Column：全屏黑板需要真正盖住内容分支（Column 流式布局会把黑板排到内容下方）
      Stack() {
        if (this.referenceLayout) {
          Stack() {
            this.ReferenceFeedPreviewPage()
          }
            .width('100%').height('100%')
            .opacity(this.referencePortraitFeedActive() && !this.referenceFeedComments && this.referencePreviewVisible ? 1 : 0)
            .offset({ y: this.referenceFeedTouchDirection * this.ch + this.referenceFeedDragY })
            .animation({ duration: this.referenceLayout && this.referenceFeed ? this.referenceFeedMotionDuration : 0, curve: Curve.EaseOut })
            .zIndex(0)
            .hitTestBehavior(HitTestMode.None)
        }
        Stack() {
          Stack() {
            // ⭐ 内容分支常驻渲染：fs 期间冻结在进入前的分支（preFsBranch 快照），
            // 旋转不再切分支 → 详情页零重挂载、无封面重解码风暴；冻结分支被下方背景板盖住
            this.buildContentBranch()
            // ⭐ 全屏背景板：常挂载保持子树稳定（挂载/卸载会使常驻层兄弟位置变化导致重建抖动），
            //    仅全屏时可见；退出插值期间提前隐藏，让内容渐显过程可见；并承接窗口旋转回调 onCA
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.ovPlateBg())
              .visibility(this.fs && this.fsLerpDir !== 2 ? Visibility.Visible : Visibility.Hidden)
              .onAreaChange(this.onCA)
            // ⭐ 常驻播放器层（XComponent 单实例，跨分支常驻，几何随状态驱动）
            this.buildPlayerOverlay()
            if (this.referencePortraitFeedActive() && this.referenceFeedPreviewPinned) { this.ReferenceFeedPinnedPage() }
            if (this.referenceLayout && !this.fs && !this.isLs && !this.referenceInfoHidden && !this.floatingMorph) { this.ReferenceChrome() }
            this.ReferenceFeedPlaybackOverlay()
            // Above the feed information gradient, which otherwise intercepts reset taps.
            this.buildFullscreenResetButton()
            if (this.referenceLayout && this.isLs && !this.fs && !this.floatingMorph && !this.isLightsOff) {
              this.ReferenceLandscapeResizeHandle()
            }
          }
          // Keep feed dragging on its own node so the page-entry offset below cannot overwrite it.
          // 显式尺寸：裁剪框按页面边界算，不能跟着子节点推导出来的盒子走。
          .width('100%').height('100%')
          .offset({ y: this.referencePortraitFeedActive() && !this.referenceFeedComments ? this.referenceFeedDragY : 0 })
          // ⭐ 连刷翻页时整页会被拖出屏幕。播放 Surface 是按 cover 撑大的（见 feedSurfaceW/H：
          //    IJK 把解码帧铺满 buffer，做不到 native 裁切，填充只能放大 surface 再由上层裁掉），
          //    溢出的那一条此前只被「整屏」裁剪兜住；页面一旦上移，溢出带就落到下一页顶部
          //    （用户截图里「本该被裁掉却盖住下一个视频」的那一条，翻页收尾还会残留一两帧）。
          //    裁剪必须挂在这个带 offset 的节点上：裁剪框随页面一起移动，溢出止于页边界。
          //    ⚠️ 不要改成裁到视频视口（ovRect）：连刷里双指放大要能扩进原始黑边。
          .animation({ duration: this.referenceLayout && this.referenceFeed ? this.referenceFeedMotionDuration : 0, curve: Curve.EaseOut })
          // 放在 .animation() 之后：裁剪不是可动画属性，别让它进隐式动画节点（HDR 画面经不起额外的图层包裹）。
          .clip(this.referenceFeed)
        }
        .opacity(this.fs ? 1 : (this.contentVisible ? this.calcPageEnterOpacity() : 0))
        .scale({
          x: this.fs ? 1 : (this.contentVisible ? this.calcPageEnterScaleX() : 1),
          y: this.fs ? 1 : (this.contentVisible ? this.calcPageEnterScaleY() : 1)
        })
        .offset({
          x: this.fs ? 0 : (this.contentVisible ? this.calcPageEnterOffsetX() : 0),
          y: this.fs ? 0 : (this.contentVisible ? this.calcPageEnterOffsetY() : 0)
        })
        .blur(this.fs ? 0 : (this.contentVisible ? this.calcPageEnterBlur() : 0))
        .onAreaChange(this.onColumnArea)
        if (this.referenceLayout && !this.fs && !this.floatingMorph) { this.ReferenceTopBar() }
      }
      .width('100%').height('100%').clip(true)
      .onClick(() => {
        if (this.referenceLayout && this.referenceFeed && !this.referenceFeedComments && !this.fs && !this.isLs && !this.mp) {
          this.referenceHandleFeedClick();
        }
      })
      .onTouch((event: TouchEvent) => {
        if (this.referencePortraitFeedActive() && this.handleFullscreenTransform(event)) return;
        if (event.type === TouchType.Down && event.touches.length === 1) {
          this.referenceFeedPanOwnsTouch = false;
          this.referenceFeedTouchAllowed = this.referenceInfoHidden || event.touches[0].windowY >= this.referenceSafeTop();
        }
      })
      .gestureModifier(new ReferenceFeedGestures({
        active: this.referencePortraitFeedActive() && !this.referenceFeedComments,
        distance: this.getUIContext().vp2px(8),
        onDoubleTap: (event: GestureEvent) => this.referenceHandleFeedDoubleTap(event),
        onStart: (event: GestureEvent) => {
          const finger = event.fingerList[0];
          this.referenceBeginFeedDrag(finger ? finger.globalX - event.offsetX : 0,
            finger ? finger.globalY - event.offsetY : this.referenceSafeTop(), true);
          this.referenceUpdateFeedDrag(event.offsetY);
        },
        onUpdate: (event: GestureEvent) => this.referenceUpdateFeedDrag(event.offsetY),
        onEnd: (event: GestureEvent) => this.referenceFinishFeedDrag(event.offsetY, Math.abs(event.velocityY) / 1000),
        onCancel: () => this.referenceCancelFeedDrag()
      }))
      .onGestureJudgeBegin((info: GestureInfo, event: BaseGestureEvent) => {
        if (info.tag === 'reference-feed-pan' && (!this.referencePortraitFeedActive() ||
          this.fullscreenTransformTouch || this.referenceFeedComments || this.mp || this.lk || this.la_ || !this.referenceFeedTouchAllowed)) return GestureJudgeResult.REJECT;
        return GestureJudgeResult.CONTINUE;
      })
      // 全屏切换动画由常驻播放器层几何插值实现（见 buildPlayerOverlay）

      // ⭐ 视频缩小/恢复悬浮按钮（沉浸光感版，仅竖屏评论区）

      if (this.commentSheetVisible) { this.ReferenceCommentComposer() }
      if (this.showDanmakuSheet) { this.ReferenceLandscapeDanmakuComposer() }
      // ⭐ 比例/画质底部弹窗
      if (this.referenceSubtitlePanelOpen && this.referenceLayout && this.isLs && !this.isLightsOff) { this.ReferenceLandscapeSubtitlePanel() }
      if (this.referenceLandscapeDanmakuOpen && this.referenceLayout && this.isLs && !this.isLightsOff) { this.ReferenceLandscapeDanmakuPanel() }
      if (this.rp && this.referenceLayout && this.isLs && !this.isLightsOff) { this.bRP() }
      if (this.sp && !this.isLightsOff) { this.bSP() }

      if (this.qp && !this.isLightsOff) { this.bQP() }
      // ⭐ 更多菜单
      // Keep the native parent/child materials prepared offscreen. Recreating
      // them during entry briefly gives child buttons the window's white
      // backdrop before their parent material is available to sample.
      if (this.referenceLayout && !this.isLightsOff) { this.ReferencePortraitDrawer() }

      // ⭐ 全屏评论浮层（复用评论区核心；转场期随条件卸载隐藏，退出全屏自动关闭）
      if (this.cp && this.fs && !this.rotationInProgress) { this.fsCommentPanel() }


      // ⭐ 缓存提示条（可点击跳转离线缓存列表页；完成时文案切换；右侧关闭按钮）
      if (this.cacheHintVisible) {
        Row() {
          // 图标：下载中为转圈，完成后为对勾，暂停为黄色圆形白色暂停
          if (this.cacheHintDone) {
            Image($r('app.media.checkmark_circle_fill'))
              .width(18).height(18)
              .fillColor('#34C759')
          } else if (this.cacheHintPaused) {
            Image($r('app.media.pause_circle_fill'))
              .width(18).height(18)
              .fillColor('#FFD60A')
          } else {
            LoadingProgress()
              .width(18).height(18)
              .color('#FFFFFF')
          }
          Text(this.cacheHintDone ? '缓存完成·点击查看' : (this.cacheHintPaused ? '已暂停·点击查看' : '正在缓存·点击查看'))
            .fontSize(13)
            .fontColor(Color.White)
            .margin({ left: 8 })
          // ⭐ 红色圆圈+白色叉号关闭按钮（18×18 与左侧状态图标左右对称；ClickEvent 无 stopPropagation，用标志位阻止冒泡跳转）
          Column() {
            Image($r('app.media.xmark_circle_fill'))
              .width(18).height(18)
              .fillColor('#FF453A')
          }
          .width(24).height(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ left: 10 })
          .onClick(() => {
            this.hintCloseClicked_ = true;
            this.cacheHintVisible = false;
          })
        }
        .padding({ left: 16, right: 12, top: 8, bottom: 8 })
        .backgroundColor('rgba(0,0,0,0.7)')
        .borderRadius(20)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.hintCloseClicked_) {
            this.hintCloseClicked_ = false;
            return;
          }
          this.goToOfflineCachePage();
        })
        .position({ bottom: this.cacheHintBottom, left: this.cacheHintLeft })
        .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
        .zIndex(20)
        .gesture(
          // ⭐ 提示条可随意拖动（水平+垂直），拖动结束位置持久化
          PanGesture({ direction: PanDirection.All, distance: 5 })
            .onActionStart(() => {
              this.cacheHintDragStartX = this.cacheHintLeft;
              this.cacheHintDragStartY = this.cacheHintBottom;
            })
            .onActionUpdate((event: GestureEvent) => {
              // 水平边界：左侧 8，右侧留 8；垂直边界：底部 20，顶部到状态栏下
              const maxLeft = Math.max(8, this.cw - 220 - 8);
              this.cacheHintLeft = Math.max(8, Math.min(maxLeft, this.cacheHintDragStartX + Math.round(event.offsetX)));
              this.cacheHintBottom = Math.max(20, Math.min(this.maxFloatBtnBottom, this.cacheHintDragStartY - Math.round(event.offsetY)));
            })
            .onActionEnd(() => {
              AppStorage.set('cacheHintLeft', this.cacheHintLeft);
              AppStorage.set('cacheHintBottom', this.cacheHintBottom);
              this.saveCacheHintPrefs();
            })
        )
      }
      // ⭐ 关灯模式下的开灯按钮（智感握持定位，悬浮按钮）
      // 分两套点击方案：
      //   1. 按钮可见时 → 四边死区覆盖层，只黑边区域切换显隐，视频区域不受影响
      //   2. 按钮隐藏后 → 全屏透明覆盖层，点任何位置都能重新显示按钮
      // ⭐ 仅当"开灯按钮显示"设置开启时渲染开灯按钮区域；关闭时靠侧滑返回开灯
      if (this.isLightsOff && this.lightsOffShowBtn) {
        if (this.lightBtnVisible) {
          // ── 方案1：按钮可见 → 四边死区覆盖层（视频区域不覆盖） ──
          // 顶部死区（视频上方黑边）
          if (this.xcRy > 0) {
            Column()
              .width('100%')
              .height(this.xcRy)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.triggerHaptic();
                this.toggleLightBtn();
              })
          }
          // 底部死区（视频下方黑边）
          if (this.ch - this.xcRy - this.xcH > 0) {
            Column()
              .width('100%')
              .height(this.ch - this.xcRy - this.xcH)
              .position({ top: this.xcRy + this.xcH })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.triggerHaptic();
                this.toggleLightBtn();
              })
          }
          // 左侧死区（视频左边黑边）
          if (this.xcRx > 0) {
            Column()
              .width(this.xcRx)
              .height(this.xcH)
              .position({ top: this.xcRy })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.triggerHaptic();
                this.toggleLightBtn();
              })
          }
          // 右侧死区（视频右边黑边）
          if (this.cw - this.xcRx - this.xcW > 0) {
            Column()
              .width(this.cw - this.xcRx - this.xcW)
              .height(this.xcH)
              .position({ left: this.xcRx + this.xcW, top: this.xcRy })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                this.triggerHaptic();
                this.toggleLightBtn();
              })
          }
        } else {
          // ── 方案2：按钮已隐藏 → 全屏透明覆盖层，点任意位置重新显示按钮 ──
          Column()
            .width('100%').height('100%')
            .hitTestBehavior(HitTestMode.Transparent)
            .onClick(() => {
              this.triggerHaptic();
              this.toggleLightBtn();
            })
        }
        if (this.lightBtnVisible) {
          if (this.isLs) {
            // 横屏：智感握姿不生效，始终可拖拽
            Button() {
              Image($r('app.media.lightbulb'))
                .width(24).height(24)
                .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : Color.White)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
                .rotate({ angle: this.lightbulbRotation })
            }
            .width(48).height(48)
            .borderRadius(24)
            .backgroundColor('rgba(255,255,255,0.15)')
            .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
            .scale({ x: this.lightBtnScale, y: this.lightBtnScale })
            .position(this.videoLightBtnSide === 'left'
              ? { bottom: this.videoLightBtnY, left: 32 }
              : { bottom: this.videoLightBtnY, right: 32 })
            .animation(this.lightIsDragging ? { duration: 0 } : { duration: 300, curve: Curve.Ease })
            .translate({ x: this.lightDragOffsetX })
            .gesture(
              PanGesture({ direction: PanDirection.All, distance: 5 })
                .onActionStart(() => {
                  this.lightIsDragging = true;
                  this.lightDragStartY = this.videoLightBtnY;
                  this.lightDragOffsetX = 0;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.videoLightBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.lightDragStartY - Math.round(event.offsetY)));
                  this.lightDragOffsetX = Math.round(event.offsetX);
                })
                .onActionEnd(() => {
                  this.lightIsDragging = false;
                  const totalOffsetX: number = this.lightDragOffsetX;
                  let newSide: string = this.videoLightBtnSide;
                  let sideChanged: boolean = false;
                  if (totalOffsetX < -60) {
                    newSide = 'left';
                    sideChanged = true;
                  } else if (totalOffsetX > 60) {
                    newSide = 'right';
                    sideChanged = true;
                  }
                  if (sideChanged || totalOffsetX !== 0) {
                    animateTo({ duration: 300, curve: Curve.Ease }, () => {
                      this.lightDragOffsetX = 0;
                      if (sideChanged) {
                        this.videoLightBtnSide = newSide;
                      }
                    });
                  } else {
                    this.lightDragOffsetX = 0;
                  }
                  AppStorage.set('videoLightBtnSide', this.videoLightBtnSide);
                  AppStorage.set('videoLightBtnY', this.videoLightBtnY);
                  this.saveVideoFloatBtnPrefs();
                })
            )
            .onClick(() => {
              this.triggerHaptic();
              this.clearLightBtnTimer();
              animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                this.lightBtnScale = 0.8;
              });
              setTimeout(() => {
                animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                  this.lightBtnScale = 1;
                });
              }, 100);
              animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8) }, () => {
                this.lightbulbRotation = 180;
              });
              setTimeout(() => {
                animateTo({ duration: 300, curve: Curve.Ease }, () => {
                  this.isLightsOff = false;
                  this.loBgScale = 1;
                  this.loBgBlur = 0;
                  this.loBgDim = 0;
                });
                this.manageSB(true);
              }, 620);
            })
          } else {
            // 竖屏：左右按钮淡入淡出
            if (this.smartGripEnabled) {
              // ── 智感握姿 ON：左右双按钮 ──
              Button() {
                Image($r('app.media.lightbulb'))
                  .width(24).height(24)
                  .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : Color.White)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
                  .rotate({ angle: this.lightbulbRotation })
              }
              .width(48).height(48)
              .borderRadius(24)
              .backgroundColor('rgba(255,255,255,0.15)')
              .position({ bottom: this.videoLightBtnY, left: this.smartGripLeft })
              .opacity(this.hand === 1 ? 1 : 0)
              .translate({ x: this.hand === 1 ? 0 : -20 })
              .hitTestBehavior(this.hand === 1 ? HitTestMode.Default : HitTestMode.None)
              .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
              .scale({ x: this.lightBtnScale, y: this.lightBtnScale })
              .animation(this.lightIsDragging ? { duration: 0 } : { duration: 300, curve: curves.springMotion(0.3, 0.4) })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical, distance: 5 })
                  .onActionStart(() => {
                    this.lightIsDragging = true;
                    this.lightDragStartY = this.videoLightBtnY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.videoLightBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.lightDragStartY - Math.round(event.offsetY)));
                  })
                  .onActionEnd(() => {
                    this.lightIsDragging = false;
                    AppStorage.set('videoLightBtnY', this.videoLightBtnY);
                    this.saveVideoFloatBtnPrefs();
                  })
              )
              .onClick(() => {
                this.triggerHaptic();
                this.clearLightBtnTimer();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.lightBtnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.lightBtnScale = 1;
                  });
                }, 100);
                animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8) }, () => {
                  this.lightbulbRotation = 180;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: Curve.Ease }, () => {
                    this.isLightsOff = false;
                    this.loBgScale = 1;
                    this.loBgBlur = 0;
                    this.loBgDim = 0;
                  });
                  this.manageSB(true);
                }, 620);
              })
              // 右侧按钮
              Button() {
                Image($r('app.media.lightbulb'))
                  .width(24).height(24)
                  .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : Color.White)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
                  .rotate({ angle: this.lightbulbRotation })
              }
              .width(48).height(48)
              .borderRadius(24)
              .backgroundColor('rgba(255,255,255,0.15)')
              .position({ bottom: this.videoLightBtnY, right: this.smartGripRight })
              .opacity(this.hand !== 1 ? 1 : 0)
              .translate({ x: this.hand !== 1 ? 0 : 20 })
              .hitTestBehavior(this.hand !== 1 ? HitTestMode.Default : HitTestMode.None)
              .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
              .scale({ x: this.lightBtnScale, y: this.lightBtnScale })
              .animation(this.lightIsDragging ? { duration: 0 } : { duration: 300, curve: curves.springMotion(0.3, 0.4) })
              .gesture(
                PanGesture({ direction: PanDirection.Vertical, distance: 5 })
                  .onActionStart(() => {
                    this.lightIsDragging = true;
                    this.lightDragStartY = this.videoLightBtnY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.videoLightBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.lightDragStartY - Math.round(event.offsetY)));
                  })
                  .onActionEnd(() => {
                    this.lightIsDragging = false;
                    AppStorage.set('videoLightBtnY', this.videoLightBtnY);
                    this.saveVideoFloatBtnPrefs();
                  })
              )
              .onClick(() => {
                this.triggerHaptic();
                this.clearLightBtnTimer();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.lightBtnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.lightBtnScale = 1;
                  });
                }, 100);
                animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8) }, () => {
                  this.lightbulbRotation = 180;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: Curve.Ease }, () => {
                    this.isLightsOff = false;
                    this.loBgScale = 1;
                    this.loBgBlur = 0;
                    this.loBgDim = 0;
                  });
                  this.manageSB(true);
                }, 620);
              })
            } else {
              // ── 智感握姿 OFF：单个可拖拽按钮 ──
              Button() {
                Image($r('app.media.lightbulb'))
                  .width(24).height(24)
                  .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : Color.White)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
                  .rotate({ angle: this.lightbulbRotation })
              }
              .width(48).height(48)
              .borderRadius(24)
              .backgroundColor('rgba(255,255,255,0.15)')
              .shadow({ radius: 16, color: '#40000000', offsetY: 4 })
              .scale({ x: this.lightBtnScale, y: this.lightBtnScale })
              .position(this.videoLightBtnSide === 'left'
                ? { bottom: this.videoLightBtnY, left: 32 }
                : { bottom: this.videoLightBtnY, right: 32 })
              .animation(this.lightIsDragging ? { duration: 0 } : { duration: 300, curve: Curve.Ease })
              .translate({ x: this.lightDragOffsetX })
              .gesture(
                PanGesture({ direction: PanDirection.All, distance: 5 })
                  .onActionStart(() => {
                    this.lightIsDragging = true;
                    this.lightDragStartY = this.videoLightBtnY;
                    this.lightDragOffsetX = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.videoLightBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.lightDragStartY - Math.round(event.offsetY)));
                    this.lightDragOffsetX = Math.round(event.offsetX);
                  })
                  .onActionEnd(() => {
                    this.lightIsDragging = false;
                    const totalOffsetX: number = this.lightDragOffsetX;
                    let newSide: string = this.videoLightBtnSide;
                    let sideChanged: boolean = false;
                    if (totalOffsetX < -60) {
                      newSide = 'left';
                      sideChanged = true;
                    } else if (totalOffsetX > 60) {
                      newSide = 'right';
                      sideChanged = true;
                    }
                    if (sideChanged || totalOffsetX !== 0) {
                      animateTo({ duration: 300, curve: Curve.Ease }, () => {
                        this.lightDragOffsetX = 0;
                        if (sideChanged) {
                          this.videoLightBtnSide = newSide;
                        }
                      });
                    } else {
                      this.lightDragOffsetX = 0;
                    }
                    AppStorage.set('videoLightBtnSide', this.videoLightBtnSide);
                    AppStorage.set('videoLightBtnY', this.videoLightBtnY);
                    this.saveVideoFloatBtnPrefs();
                  })
              )
              .onClick(() => {
                this.triggerHaptic();
                this.clearLightBtnTimer();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.lightBtnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.lightBtnScale = 1;
                  });
                }, 100);
                animateTo({ duration: 600, curve: curves.springMotion(0.6, 0.8) }, () => {
                  this.lightbulbRotation = 180;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: Curve.Ease }, () => {
                    this.isLightsOff = false;
                    this.loBgScale = 1;
                    this.loBgBlur = 0;
                    this.loBgDim = 0;
                  });
                  this.manageSB(true);
                }, 620);
              })
            }
          }
        }
      }
    }.width('100%').height('100%').backgroundColor(this.isLightsOff && !this.lightsOffHideOnly ? Color.Black : $r('app.color.color_player_background'))
    .id('video-player-page')
    .opacity(1)
    .hitTestBehavior(this.floatingMorph ? HitTestMode.None : HitTestMode.Default)
    .bindSheet($$this.showEpisodeSheet, this.episodeSheetContent(), {
      height: this.selectionSheetHeight(this.pagesForCurrentVideo().length > 4 ? 400 : 280),
      backgroundColor: Color.Transparent,
      systemMaterial: MaterialUtil.sheetMaterial(),
      dragBar: true,
      showClose: false,
      onDisappear: () => {
        this.showEpisodeSheet = false;
      }
    })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }

  // ⭐ 选集弹窗内容
  private selectionSheetHeight(preferred: number): number {
    return Math.max(120, Math.min(preferred, this.ch - this.referenceSafeTop() - this.navIndicatorHeight - 16));
  }

  private openEpisodeSheet(): void {
    const count = this.pagesForCurrentVideo().length;
    if (count === 0) return;
    const selected = this.referenceEpisodeSelection >= 0 ? this.referenceEpisodeSelection : this.currentPageIndex;
    const index = Math.max(0, Math.min(count - 1, selected));
    this.episodeSegment = Math.floor(index / 20);
    this.episodeSheetInitialIndex = index % 20;
    this.showEpisodeSheet = true;
  }

  private openSeasonSheet(): void {
    const sections = this.vd?.ugc_season?.sections;
    if (!sections || sections.length === 0) return;
    // 先按 cid 跨分区精确匹配（同一合集里 cid 唯一），再退回 bvid/aid：
    // 多P分集播放 P2 时 ep.cid 是 P1，只能靠 bvid 命中。
    let sectionIndex = 0;
    let episodeIndex = 0;
    let found = false;
    for (let pass = 0; pass < 2 && !found; pass++) {
      for (let s = 0; s < sections.length && !found; s++) {
        const episodes = sections[s].episodes || [];
        for (let i = 0; i < episodes.length; i++) {
          const ep = episodes[i];
          const hit = pass === 0 ? (this.vi.cid > 0 && ep.cid === this.vi.cid) : this.isCurrentSeasonEpisode(ep);
          if (hit) {
            sectionIndex = s;
            episodeIndex = i;
            found = true;
            break;
          }
        }
      }
    }
    this.seasonSectionIndex = sectionIndex;
    this.seasonSheetInitialIndex = episodeIndex;
    this.showSeasonSheet = true;
  }

  @Builder
  episodeSheetContent() {
    Column() {
      // ⭐ 顶部 8vp 空白占位（避免第一项贴弹窗顶部）
      Column().width('100%').height(8)
      Row() {
        // ⭐ 左侧分段快速定位（每 20 集一段：1-20 / 21-40 / 41-60...），集数多时方便跳段
        if (this.pagesForCurrentVideo().length > 20) {
          List({ space: 6, initialIndex: this.episodeSegment }) {
              ForEach(this.episodeSegList(), (seg: number) => {
                ListItem() {
                Text(this.episodeSegLabel(seg))
                  .fontSize(11)
                  .fontWeight(this.episodeSegment === seg ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.episodeSegment === seg
                    ? (this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'))
                    : $r('app.color.color_player_text_secondary'))
                  .padding({ left: 8, right: 8, top: 7, bottom: 7 })
                  .backgroundColor(this.episodeSegment === seg ? $r('app.color.color_comment_selected') : Color.Transparent)
                  .borderRadius(14)
                  .onClick(() => {
                    this.triggerHaptic();
                    this.episodeSheetInitialIndex = 0;
                    this.episodeSegment = seg;
                    // ⭐ 切段后 List 只渲染本段 20 集，回到段内顶部
                    this.episodeScroller_.scrollToIndex(0, false);
                  })
                }
              }, (seg: number) => seg.toString())
          }
          .padding({ top: 8, bottom: 8 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .width(64)
          .height('100%')
        }
        // 选集列表（⭐ 只渲染当前分段内的集数）
        if (this.pagesForCurrentVideo().length > 0) {
          List({ scroller: this.episodeScroller_, initialIndex: this.episodeSheetInitialIndex }) {
          ForEach(this.episodeSegPages(), (page: VideoPageItem, localIndex: number) => {
            ListItem() {
              Row() {
                // ⭐ 分集封面缩略图（PGC 分集有封面）
                if (page.cover) {
                  Image(page.cover)
                    .width(72).height(44)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(6)
                    .backgroundColor('#E8E8E8')
                    .margin({ right: 8 })
                }
                Text(`P${page.page}`).fontSize(14).fontColor(
                  this.isCurrentEpisode(localIndex) ? this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink') : $r('app.color.color_player_text_secondary')
                ).width(36)
                Text(page.part).fontSize(14).fontColor(
                  this.isCurrentEpisode(localIndex) ? this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink') : $r('app.color.color_player_text')
                ).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).margin({ left: 4 })
                Text(this.formatDuration(page.duration)).fontSize(12)
                  .fontColor($r('app.color.color_player_text_secondary')).margin({ left: 8 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor(this.isCurrentEpisode(localIndex) ?
                $r('app.color.color_comment_selected') : Color.Transparent)
              .borderRadius(20)
              .onClick(() => {
                if (!this.isCurrentEpisode(localIndex)) {
                  this.triggerHaptic();
                  this.switchEpisode(this.episodeSegGlobalIndex(localIndex));
                  this.showEpisodeSheet = false;
                }
              })
            }
          }, (page: VideoPageItem) => page.cid.toString())
        }
        // ⭐ Row 中 List 仅用 layoutWeight(1) 撑满右侧（不再 width('100%')，避免按整行宽计算超宽）
        .layoutWeight(1)
        .padding({ left: 8, right: 8 })
        .height('100%')
        .scrollBar(BarState.Off)
        .id('episode-sheet-list')
      }
      }
      // ⭐ Row 撑满 Column 剩余高度：否则 List 高度自适应内容会撑破弹窗，底部占位被挤出
      .layoutWeight(1)
      .width('100%')
      // ⭐ 底部 8vp 空白占位（避免最后一项贴弹窗底部）
      Column().width('100%').height(8)
    }
    .width('100%')
    // 手机底部 SheetPage 首轮按整屏测量，百分比会使 initialIndex 按过大的视口回填。
    // 与 bindSheet 共用确定高度，列表第一次布局就使用实际内容区尺寸。
    .height(this.selectionSheetHeight(this.pagesForCurrentVideo().length > 4 ? 400 : 280))
    .backgroundColor(this.sheetRootBg($r('app.color.color_comment_background')))
  }

  // ⭐ 合集弹窗内容
  @Builder
  seasonSheetContent() {
    Column() {
      Column().width('100%').height(8)
      // 合集标题
      if (this.vd?.ugc_season?.title) {
        Text(this.vd.ugc_season.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_player_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 16, right: 16, bottom: 12 })
      }
      Row() {
        // 分区 Tab（多分区时显示）
        if (this.vd?.ugc_season?.sections && this.vd.ugc_season.sections.length > 1) {
          List({ space: 6, initialIndex: this.seasonSectionIndex }) {
              ForEach(this.vd.ugc_season.sections, (section: SeasonSection, index: number) => {
                ListItem() {
                Text(section.title || `分区${index + 1}`)
                  .fontSize(11)
                  .fontWeight(this.seasonSectionIndex === index ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.seasonSectionIndex === index
                    ? (this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink'))
                    : $r('app.color.color_player_text_secondary'))
                  .padding({ left: 8, right: 8, top: 7, bottom: 7 })
                  .backgroundColor(this.seasonSectionIndex === index ? $r('app.color.color_comment_selected') : Color.Transparent)
                  .borderRadius(14)
                  .onClick(() => {
                    this.triggerHaptic();
                    this.seasonSheetInitialIndex = 0;
                    this.seasonSectionIndex = index;
                    this.seasonScroller_.scrollToIndex(0, false);
                  })
                }
              }, (section: SeasonSection, index: number) => `${index}`)
          }
          .padding({ top: 8, bottom: 8 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .width(64)
          .height('100%')
        }
        // 当前分区的分集列表
        if (this.vd?.ugc_season?.sections && this.vd.ugc_season.sections.length > 0) {
          List({ scroller: this.seasonScroller_, initialIndex: this.seasonSheetInitialIndex }) {
            ForEach(this.seasonCurrentEpisodes(), (ep: SeasonEpisode, localIndex: number) => {
              ListItem() {
                Row() {
                  if (ep.arc?.pic || ep.cover) {
                    Image(ep.arc?.pic || ep.cover)
                      .width(72).height(44)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(6)
                      .backgroundColor('#E8E8E8')
                      .margin({ right: 8 })
                  }
                  Text(`${localIndex + 1}`).fontSize(14).fontColor(
                    this.isCurrentSeasonEpisode(ep) ? this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink') : $r('app.color.color_player_text_secondary')
                  ).width(36)
                   Text(ep.title || '').fontSize(14).fontColor(
                    this.isCurrentSeasonEpisode(ep) ? this.playerFollowTheme ? this.customThemeColor : ('app.color.color_bilibili_pink') : $r('app.color.color_player_text')
                  ).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).margin({ left: 4 })
                  Text(this.formatDuration(ep.duration || ep.arc?.duration || 0)).fontSize(12)
                    .fontColor($r('app.color.color_player_text_secondary')).margin({ left: 8 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor(this.isCurrentSeasonEpisode(ep) ? $r('app.color.color_comment_selected') : Color.Transparent)
                .borderRadius(20)
                .onClick(() => {
                  if (!this.isCurrentSeasonEpisode(ep)) {
                    this.triggerHaptic();
                    this.switchSeasonEpisode(ep);
                    this.showSeasonSheet = false;
                  }
                })
              }
            }, (ep: SeasonEpisode) => `${ep.aid}-${ep.cid}-${ep.bvid}`)
          }
          .layoutWeight(1)
          .padding({ left: 8, right: 8 })
          .height('100%')
          .scrollBar(BarState.Off)
          .id('season-sheet-list')
        }
      }
      .layoutWeight(1)
      .width('100%')
      Column().width('100%').height(8)
    }
    .width('100%')
    .height(this.selectionSheetHeight(400))
    .backgroundColor(this.sheetRootBg($r('app.color.color_comment_background')))
  }

  // ⭐ 切换分P
  /**
   * ⭐ 当前视频自己的分P/番剧选集。**与 ugc_season 合集的分界就在这里**：
   *   合集切集后 `vi.bvid` 已指向新视频，而 `vd` 要等详情回包才替换；
   *   这段时间若继续把旧 `vd.pages` 当分P 用，选集条就会拿上一条视频的 cid 配新集的 bvid 取流。
   */
  private pagesForCurrentVideo(): VideoPageItem[] {
    if (this.isPgc_) return this.vd?.pages || [];
    if (!this.vd || !this.vd.pages || !this.detailIsCurrentVideo()) return [];
    return this.vd.pages;
  }

  /** `vd` 是否描述当前这条视频（合集切集途中为 false） */
  private detailIsCurrentVideo(): boolean {
    if (this.isPgc_) return true;
    if (!this.vd) return false;
    if (!this.vdBvid_) return true;
    // aid 入口：vi.bvid 存的是数字 aid，用详情自己的 aid 兜底
    if (this.vi.bvid && (this.vi.bvid === this.vdBvid_ || this.vi.bvid === String(this.vd.aid))) return true;
    return false;
  }

  /** ⭐ 是否有下一集（多P分P / 番剧分集） */
  private hasNextEpisode(): boolean {
    return this.currentPageIndex + 1 < this.pagesForCurrentVideo().length;
  }

  /** ⭐ 选集分段数（每 20 集一段） */
  private episodeSegCount(): number {
    return Math.ceil(this.pagesForCurrentVideo().length / 20);
  }

  // ⭐ 合集辅助方法

  /** 当前分区的分集列表 */
  private seasonCurrentEpisodes(): SeasonEpisode[] {
    if (!this.vd?.ugc_season?.sections || this.vd.ugc_season.sections.length === 0) return [];
    const section = this.vd.ugc_season.sections[this.seasonSectionIndex];
    if (!section || !section.episodes) return [];
    return section.episodes;
  }

  /** 合集总集数（跨分区）：接口的 ep_count 已在解析时归一到 epCount */
  private seasonTotalEpisodeCount(): number {
    const season = this.vd?.ugc_season;
    if (!season) return 0;
    if ((season.epCount || 0) > 0) return season.epCount || 0;
    let total = 0;
    for (const section of season.sections || []) {
      total += (section.episodes || []).length;
    }
    return total;
  }

  /** 当前播放分集在合集里的全局序号（跨分区累计；找不到返回 0） */
  private seasonCurrentEpisodeIndex(): number {
    const sections = this.vd?.ugc_season?.sections;
    if (!sections || sections.length === 0) return 0;
    let base = 0;
    for (let s = 0; s < sections.length; s++) {
      const episodes = sections[s].episodes || [];
      for (let i = 0; i < episodes.length; i++) {
        if (this.isCurrentSeasonEpisode(episodes[i])) return base + i;
      }
      base += episodes.length;
    }
    return 0;
  }

  /**
   * 是否为当前播放分集。
   * ⭐ 先比 bvid（合集里每条分集是独立视频，bvid 才是稳定身份），再比 cid；
   *   `vd.aid` 只作兜底，且要求 `vd` 已描述当前视频 —— 合集切集途中它还是上一条的 aid。
   */
  private isCurrentSeasonEpisode(ep: SeasonEpisode): boolean {
    if (ep.bvid && this.vi.bvid && ep.bvid === this.vi.bvid) return true;
    if (ep.cid && this.vi.cid > 0 && ep.cid === this.vi.cid) return true;
    if (ep.aid && this.detailIsCurrentVideo() && ep.aid === this.vd?.aid) return true;
    return false;
  }

  /** 目标分集所在的分区索引 */
  private seasonSectionIndexOfEpisode(target: SeasonEpisode): number {
    const sections = this.vd?.ugc_season?.sections;
    if (!sections) return 0;
    for (let s = 0; s < sections.length; s++) {
      const episodes = sections[s].episodes || [];
      for (let i = 0; i < episodes.length; i++) {
        const ep = episodes[i];
        if ((target.bvid && ep.bvid === target.bvid) || (target.cid && ep.cid === target.cid) ||
          (target.aid && ep.aid === target.aid)) return s;
      }
    }
    return 0;
  }

  /** 切换合集分集。
   * ⭐ 合集里每条分集是**另一条视频**（自己的 aid/bvid/简介/统计/分P），不是同一详情下的选集：
   *   必须像连刷换片那样整份替换 `vd`。只改播放上下文会让简介、统计、BV 号、分P 全停在上一条，
   *   而且旧分P 还能点，点下去就是「新 bvid + 旧 cid」取流。
   */
  private async switchSeasonEpisode(ep: SeasonEpisode): Promise<void> {
    const bvid = ep.bvid || '';
    // 没有 bvid 就没法换视频；宁可不切，也不能拿旧 cid 硬播
    if (!this.referenceAlive || !bvid || bvid === this.vi.bvid) return;
    // 先让进行中的分P 切换收尾，避免它随后用旧 page.cid 覆盖新集
    if (this.episodeSwitchJob_) {
      await this.episodeSwitchJob_.catch(() => {});
    }
    if (!this.referenceAlive) return;
    const requestId = ++this.seasonSwitchSeq_;
    await this.release();
    if (!this.referenceAlive || requestId !== this.seasonSwitchSeq_) return;
    // 分P 状态属于上一条视频：索引、高亮、分段全部归零
    this.currentPageIndex = 0;
    this.referenceEpisodeSelection = -1;
    this.episodeSegment = 0;
    this.episodeSheetInitialIndex = 0;
    this.pendingEpisodeIndex_ = -1;
    // 播放上下文先指向新分集（详情还没回来时也能起播）
    this.vi.bvid = bvid;
    this.setPlaybackCid(ep.cid || 0);
    this.aidFromParams_ = ep.aid || 0;
    if (ep.title) this.vi.title = ep.title;
    const cover = ep.arc?.pic || ep.cover || '';
    if (cover) this.vi.cover = cover;
    const duration = ep.duration || ep.arc?.duration || 0;
    if (duration > 0) this.vi.duration = duration;
    const epView = ep.arc?.stat?.view;
    if (epView !== undefined) this.vi.view = epView;
    this.seasonSectionIndex = this.seasonSectionIndexOfEpisode(ep);
    // 评论属于上一条视频：先清空，等新详情回来再按它的 aid 拉
    this.commentCursor = 0;
    this.commentDataSource.clear();
    // ⭐ 切集：清掉上一集的进度，改由新一集的 playurl 续播点恢复
    this.initialProgress_ = 0;
    this.ct = 0;
    this.lastHeartbeatTime = 0;
    // 播放与详情并行：先按 ep 的 cid 起播，详情回来再整份提交这条视频的简介/统计/分P
    const detailTask = this.loadSeasonEpisodeDetail(bvid, requestId);
    // release() 只 cancel deadline，上一次 initP 要下一拍才清 initPInProgress_；
    // 不等它清掉，新集的 initP 会在入口直接 return（表现就是切完一直转圈）。
    const idle = await this.waitInitPIdle(requestId);
    if (!idle && requestId !== this.seasonSwitchSeq_) return;
    await this.initP();
    await detailTask;
  }

  /** 等上一次 initP 收尾；期间又被切换取代/退出页面则返回 false */
  private async waitInitPIdle(requestId: number): Promise<boolean> {
    for (let i = 0; i < 80; i++) {
      if (!this.referenceAlive || requestId !== this.seasonSwitchSeq_) return false;
      if (!this.initPInProgress_) return true;
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 25));
    }
    return !this.initPInProgress_;
  }

  /** 拉取合集新分集的详情并整份提交（bvid 不匹配 / 已退出 / 被下一次切换取代时丢弃） */
  private async loadSeasonEpisodeDetail(bvid: string, requestId: number): Promise<void> {
    const detail = await getVideoDetail(bvid);
    if (!detail || !this.referenceAlive || requestId !== this.seasonSwitchSeq_ || this.vi.bvid !== bvid) return;
    this.vd = detail;
    this.vdBvid_ = detail.bvid || bvid;
    this.applyDetailDimension(detail);
    this.predecodeKeyImages();
    // 简介的 UP 卡片/标签是挂在页面上的，换视频后不会重新 onAppear，必须主动重取
    if (this.referenceLayout && !this.referenceFeed && !this.isPgc_) this.loadReferenceIntroExtras();
    const pages = detail.pages || [];
    // 合集条目偶尔缺 cid：用详情补上，别让 initP 一直等 cid
    if (this.vi.cid <= 0) {
      const cid = detail.cid || (pages.length > 0 ? pages[0].cid : 0);
      if (cid > 0) this.setPlaybackCid(cid);
    }
    const index = pages.findIndex((item: VideoPageItem) => item.cid === this.vi.cid);
    this.currentPageIndex = index >= 0 ? index : 0;
    if (detail.aid > 0) this.aidFromParams_ = detail.aid;
    this.likeCount = detail.stat.like;
    this.coinCount = detail.stat.coin;
    this.favoriteCount = detail.stat.favorite;
    this.loadInitialVideoInteractions(detail, bvid, this.referenceSwitchGeneration, this.interactionRevision);
    if (detail.aid > 0) this.loadC(detail.aid);
    this.fetchRelatedVideos(bvid);
    logInfo(`[VideoPlayer] 合集切集详情: bvid=${bvid}, aid=${detail.aid}, 分P=${pages.length}, 选中=${this.currentPageIndex}`);
  }

  /** ⭐ 选集分段索引列表（0, 1, 2...） */
  private episodeSegList(): number[] {
    const n = this.episodeSegCount();
    const list: number[] = [];
    for (let i = 0; i < n; i++) {
      list.push(i);
    }
    return list;
  }

  /** ⭐ 当前分段内的 pages 子集（List 只渲染本段，最多 20 集） */
  private episodeSegPages(): VideoPageItem[] {
    const pages = this.pagesForCurrentVideo();
    if (pages.length === 0) return [];
    const start = this.episodeSegStart(this.episodeSegment);
    const end = Math.min(start + 20, pages.length);
    const list: VideoPageItem[] = [];
    for (let i = start; i < end; i++) {
      list.push(pages[i]);
    }
    return list;
  }

  /** ⭐ 段内索引 → 全局索引（切集用全局索引） */
  private episodeSegGlobalIndex(localIndex: number): number {
    return this.episodeSegStart(this.episodeSegment) + localIndex;
  }

  /** ⭐ 该段内项是否为当前播放集（高亮判断） */
  private isCurrentEpisode(localIndex: number): boolean {
    return this.currentPageIndex === this.episodeSegGlobalIndex(localIndex);
  }

  /** ⭐ 分段起始集索引（第 seg 段从 seg*20 开始） */
  private episodeSegStart(seg: number): number {
    return seg * 20;
  }

  /** ⭐ 分段标签（1-20 / 21-40 / 41-60...） */
  private episodeSegLabel(seg: number): string {
    const start = this.episodeSegStart(seg) + 1;
    const end = Math.min(this.episodeSegStart(seg) + 20, this.pagesForCurrentVideo().length);
    return `${start}-${end}`;
  }

  private switchEpisode(index: number): Promise<void> {
    if (!this.pagesForCurrentVideo()[index] || !this.referenceAlive ||
      (index === this.currentPageIndex && !this.episodeSwitchJob_)) return Promise.resolve();
    this.referenceEpisodeSelection = index;
    this.pendingEpisodeIndex_ = index;
    if (!this.episodeSwitchJob_) this.episodeSwitchJob_ = this.runEpisodeSwitches();
    return this.episodeSwitchJob_;
  }

  private async runEpisodeSwitches(): Promise<void> {
    try {
      while (this.referenceAlive && this.pendingEpisodeIndex_ >= 0) {
        const index = this.pendingEpisodeIndex_;
        this.pendingEpisodeIndex_ = -1;
        await this.applyEpisodeSwitch(index);
      }
    } finally {
      this.pendingEpisodeIndex_ = -1;
      this.referenceEpisodeSelection = -1;
      this.episodeSwitchJob_ = null;
    }
  }

  private async applyEpisodeSwitch(index: number): Promise<void> {
    const pages = this.pagesForCurrentVideo();
    if (index === this.currentPageIndex || !pages[index]) return;
    const page = pages[index];
    if (!page) return;
    this.resetFullscreenVideo();

    // ⭐ 切集前先按**旧 epId** 把这一集的进度落库一次。
    //   必须放在改动 epId_ / release() 之前：否则 epId_ 已指向新集、ct 又被播放器重置成 0，
    //   上报就退化成"新集 0 秒"，而 B 站整季只有一条记录，会把上一集的位置直接清零
    //   （详见 reportPgcHeartbeat 的说明）。放这里还能把最多 15s 的心跳间隔损失补回来。
    if (this.isPgc_ && this.epId_ > 0 && this.ct >= MIN_HEARTBEAT_PROGRESS_SEC) {
      try {
        await this.reportPgcHeartbeat(this.ct);
        logInfo(`[VideoPlayer] 切集前落库上一集进度: epId=${this.epId_}, ${Math.floor(this.ct)}秒`);
      } catch (e) {
        logError(`[VideoPlayer] 切集前落库上一集进度失败: ${errMsg(e)}`);
      }
    }

    // 释放当前播放器
    if (!this.referenceAlive) return;
    await this.release();
    if (!this.referenceAlive) return;

    this.currentPageIndex = index;
    this.setPlaybackCid(page.cid);
    // ⭐ PGC 选集：同步更新 epId_（取流用）与评论 oid（vd.aid=分集 aid）
    if (this.isPgc_) {
      const newEpId = index >= 0 && index < this.pgcEpIds_.length ? this.pgcEpIds_[index] : 0;
      const newEpAid = index >= 0 && index < this.pgcAids_.length ? this.pgcAids_[index] : 0;
      if (newEpId > 0) {
        this.epId_ = newEpId;
        logInfo(`[VideoPlayer] PGC 切集: 第${index + 1}话 epId=${this.epId_}, cid=${this.vi.cid}, 评论oid=${newEpAid}`);
      }
      // 仅更新播放/评论上下文，保留同一份简介、分集数组和推荐列表。
      this.aidFromParams_ = newEpAid;
      if (this.vd) {
        this.vd.aid = newEpAid;
        this.vd.cid = page.cid;
      }
      // 切集后评论需要重新加载（oid 变了）
      this.commentCursor = 0;
      this.commentDataSource.clear();
      if (newEpAid > 0) {
        this.loadC(newEpAid);
      }
    }
    // ⭐ 切集：清掉上一集的进度，改由新一集的 playurl 续播点恢复（否则会把上一集的位置带过来）
    this.initialProgress_ = 0;
    // ⭐ 进度与心跳基准一并归零：新集在真正播到阈值前，绝不能带着上一集的秒数参与任何上报
    //   （PGC 整季共用一条历史记录，带错秒数会覆盖掉正确位置）
    this.ct = 0;
    this.lastHeartbeatTime = 0;
    // 重新加载视频
    await this.initP();
  }

  // ⭐ 格式化时长
  private formatDuration(seconds: number): string {
    const whole = Math.max(0, Math.floor(seconds));
    const min = Math.floor(whole / 60);
    const sec = whole % 60;
    return `${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
  }

  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  private getComponentBg(componentEnabled: boolean): string {
    if (this.cardCustomColor && this.cardCustomColor !== '#007DFF') {
      if (this.cardTransparentStyleVideo && componentEnabled) {
        return '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1);
      }
      return this.cardCustomColor;
    }
    if (this.cardTransparentStyleVideo && componentEnabled) {
      return this.isDarkMode
        ? `rgba(0,0,0,${this.cardBgOpacity / 100})`
        : `rgba(255,255,255,${this.cardBgOpacity / 100})`;
    }
    return this.isDarkMode ? '#1A1A1A' : '#E0E0E0';
  }

  private contentPanelWallpaperActive(): boolean {
    return this.pageWallpaperEnabled && this.contentCardMaterialActive();
  }

  @Builder
  ContentPanelWallpaper() {
    if (this.contentPanelWallpaperActive()) {
      PageWallpaper({ embedded: true, orientation: this.isLs ? 'landscape' : 'portrait' })
    }
  }

  private contentCardMaterialActive(): boolean {
    // Retain the existing wallpaper lifecycle throughout the normal-panel transition.
    return !this.referenceFeedComments && (!this.referenceFeed || this.referenceModeAnimating);
  }

  private getCardContainerBg(componentEnabled: boolean): string {
    if (this.cardCustomColor && this.cardCustomColor !== '#007DFF') {
      if (this.cardTransparentStyleVideo && componentEnabled) {
        return '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1);
      }
      return this.cardCustomColor;
    }
    if (this.cardTransparentStyleVideo && componentEnabled) {
      return this.isDarkMode
        ? `rgba(0,0,0,${this.cardBgOpacity / 100})`
        : `rgba(255,255,255,${this.cardBgOpacity / 100})`;
    }
    return this.isDarkMode ? '#2C2C2C' : '#E8E8E8';
  }

  private getCardContainerBorder(componentEnabled: boolean): BorderOptions {
    if (this.cardTransparentStyleVideo && componentEnabled) {
      return {
        width: this.cardBorderWidth,
        color: this.cardBorderFollowTheme
          ? ('#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1))
          : (this.isDarkMode ? `rgba(255,255,255,${this.cardBorderOpacity / 100})` : 'rgba(255,255,255,0.25)')
      };
    }
    return { width: 0, color: Color.Transparent };
  }

  private async saveVideoFloatBtnPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('videoShrinkBtnSide', this.videoShrinkBtnSide);
      await pref.put('videoShrinkBtnY', this.videoShrinkBtnY);
      await pref.put('videoLightBtnSide', this.videoLightBtnSide);
      await pref.put('videoLightBtnY', this.videoLightBtnY);
      await pref.flush();
    } catch (e) {
      logError('保存视频页悬浮按钮位置失败', e);
    }
  }

  // ⭐ 持久化缓存提示条拖拽位置
  private async saveCacheHintPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('cacheHintLeft', this.cacheHintLeft);
      await pref.put('cacheHintBottom', this.cacheHintBottom);
      await pref.flush();
    } catch (e) {
      logError('保存缓存提示条位置失败', e);
    }
  }

  private referenceSafeTop(): number {
    return AppStorage.get<number>('realStatusBarHeight') || AppStorage.get<number>('statusBarHeight') || 40;
  }

  private applyDetailDimension(detail: VideoDetail): void {
    // 优先采用当前分P尺寸；详情已预取，不必等待解码器报告宽高。
    const page = detail.pages?.find((item: VideoPageItem) => item.cid === this.vi.cid);
    const dimension = page?.dimension || (detail.cid === this.vi.cid || !this.vi.cid ? detail.dimension : undefined);
    if (!dimension || !Number.isFinite(dimension.width) || !Number.isFinite(dimension.height) ||
      dimension.width <= 0 || dimension.height <= 0) return;
    // 连刷的画幅由静帧/解码提交（committedRatio）单独管理，首帧后不要插进来改几何；
    // 普通播放页必须允许迟到修正：原来这里卡着 waitingForFirstFrame，预热命中后
    // 几百毫秒就置 false，详情稍晚返回就被丢掉，ar 便永久停在 16:9。
    if (this.referenceFeed && !this.waitingForFirstFrame) return;
    const rotated = Math.abs(dimension.rotate || 0) % 180 === 90;
    if (!this.setAspectFromMeta(rotated ? dimension.height / dimension.width : dimension.width / dimension.height,
      this.vi.cid)) return;
    this.updateIsLandscapeVertical();
    this.updateLSVSize();
    this.updateVideoSize();
  }

  /**
   * 记录来自路由参数/详情的「显示尺寸」，返回是否真的改了 ar（决定要不要重算几何）。
   * 只要拿到过显示尺寸就打标：之后解码尺寸想覆盖，必须先过 decoderAspectIgnored。
   */
  private setAspectFromMeta(aspect: number, cid: number): boolean {
    if (!Number.isFinite(aspect) || aspect <= 0.05 || aspect >= 20) return false;
    this.arFromMeta_ = true;
    this.arMetaCid_ = cid;
    if (Math.abs(aspect / this.ar - 1) <= 0.005) return false;
    this.ar = aspect;
    return true;
  }

  /**
   * 解码/元数据尺寸是否该被忽略。
   *
   * 只在「显示尺寸仍对当前 cid 有效」时拦截：比例互为倒数（rotate=90）或只差取整
   * 误差（编码补边）都属于同一条源，不该动已提交的画幅；差异真的很大（例如切集后
   * 详情还没回来、旧 meta 已过期）则放行，让解码尺寸纠正。
   */
  private decoderAspectIgnored(aspect: number): boolean {
    if (!this.arFromMeta_ || this.arMetaCid_ !== this.vi.cid) return false;
    if (!Number.isFinite(aspect) || aspect <= 0) return false;
    return Math.abs(aspect * this.ar - 1) <= 0.02 || Math.abs(aspect / this.ar - 1) <= 0.02;
  }

  /**
   * 预热实例的画幅回灌。
   *
   * 池实例在 prepare 阶段就把 videoSizeChange 发完了（ff_ffplay.c 在 prepared 之前
   * 用 codecpar 发一次、videothread 首帧 alloc 再发一次），take() 后监听被摘掉，
   * 页面注册时已经收不到。这里用播放器当前尺寸（IJK 在 load 时按 DASH 元数据填好、
   * 400 事件后更新；AVPlayer 在 prepared 后由系统填好），拿不到再用会话实测值。
   */
  private adoptWarmAspect(player: PlaybackPlayer, measured: number): void {
    if (this.referenceFeed) return;   // 连刷有自己的画幅提交
    const w: number = player.width || 0;
    const h: number = player.height || 0;
    let aspect: number = 0;
    if (w > 0 && h > 0) aspect = w / h;
    // 会话值是 videoSizeChange 实测，但初始值为 1（正方形）——不能拿它当"未知"用。
    else if (Number.isFinite(measured) && Math.abs(measured - 1) > 0.001) aspect = measured;
    if (!(aspect > 0.05 && aspect < 20)) return;
    if (this.decoderAspectIgnored(aspect)) return;
    if (Math.abs(aspect / this.ar - 1) <= 0.002) return;
    logInfo(`[VideoPlayer] 预热画幅回灌 ${this.ar.toFixed(4)} -> ${aspect.toFixed(4)} (${w}x${h})`);
    this.ar = aspect;
    this.updateIsLandscapeVertical();
    this.updateLSVSize();
    this.updateVideoSize();
  }

  /** 用播放器当前尺寸补一次画幅：预热接管 / 浮窗恢复 / 切集后事件已过期的情况。 */
  private syncAspectFromPlayer(player: PlaybackPlayer | null): void {
    if (!player || this.referenceFeed) return;
    const w: number = player.width || 0;
    const h: number = player.height || 0;
    if (!(w > 0 && h > 0)) return;
    const aspect: number = w / h;
    if (this.decoderAspectIgnored(aspect)) return;
    if (Math.abs(aspect / this.ar - 1) <= 0.002) return;
    logInfo(`[VideoPlayer] 播放器画幅快照 ${this.ar.toFixed(4)} -> ${aspect.toFixed(4)} (${w}x${h})`);
    this.ar = aspect;
    this.updateIsLandscapeVertical();
    this.updateLSVSize();
    this.updateVideoSize();
  }

  // 半屏控件按播放模式选择；横竖屏只负责重排，不切回旧版控件。
  private referenceHalfScreenControlsActive(): boolean {
    return this.referenceLayout && !this.fs &&
      (this.isLs || (!this.referenceFeed && !this.referenceModeAnimating));
  }

  private onLandscapePlaybackSideChanged(): void {
    this.isLayoutSwapped = this.landscapePlaybackSide === 'right';
  }

  private referenceLandscapeRestoreRatio(value: Object | undefined): void {
    if (typeof value === 'number' && Number.isFinite(value) && value > 0 && value < 1) {
      this.referenceLandscapePlayerRatio = value;
    }
  }

  private referenceLandscapePlayerX(): number {
    return (this.isLayoutSwapped ? this.cw - this.referenceLandscapePlayerWidth() : 0) +
      this.safeCM() * (1 - (this.referenceLandscapeExpandProgress || 0));
  }

  private referenceLayoutPixel(value: number): number {
    const context = this.getUIContext();
    return context.px2vp(Math.round(context.vp2px(value)));
  }

  private referenceLandscapePanelX(): number {
    return this.referenceLayoutPixel((this.isLayoutSwapped ? -(this.referenceLandscapePanelWidth() + 2 * this.safeCM()) *
      (this.referenceLandscapeExpandProgress || 0) : this.referenceLandscapePlayerWidth()) + this.safeCM());
  }

  private referenceLandscapeTabWidth(tab: number): number {
    // The offscreen Swiper page stays mounted, but need not reflow for every pan
    // sample. Synchronize it once on release, or immediately if it becomes active.
    if (this.referenceLandscapeResizeActive && this.at !== tab) return this.referenceResizePanelWidth;
    return this.referenceLandscapePanelWidth();
  }

  private referenceLandscapePanelWidth(): number {
    return Math.max(1, this.referenceLayoutPixel(this.cw - this.referenceLandscapeClampedWidth(
      this.cw * (this.referenceLandscapePlayerRatio ?? 2 / 3)) - 2 * this.safeCM()));
  }

  private referenceLandscapePlayerWidth(): number {
    const base = this.referenceLandscapeClampedWidth(this.cw * (this.referenceLandscapePlayerRatio ?? 2 / 3));
    return base + (this.cw - base) * (this.referenceLandscapeExpandProgress || 0);
  }

  private referenceLandscapeClampedWidth(width: number): number {
    const minimum = Math.min(280, this.cw * 0.4);
    const panelMinimum = Math.min(220, this.cw * 0.3);
    return Math.max(1, Math.max(minimum, Math.min(this.cw - panelMinimum, width)));
  }

  private referenceLandscapeResize(offset: number): void {
    if (!this.isLs || this.fs || this.isAnimatingToFS || this.cw <= 0) return;
    if (this.referenceLandscapeResizeActive) this.resizeEventCount++;
    const delta = this.isLayoutSwapped ? -offset : offset;
    const proposed = this.referenceLayoutPixel(this.cw * this.referenceLandscapeResizeStart + delta);
    const maximum = this.referenceLandscapeClampedWidth(this.cw);
    this.referenceLandscapePlayerRatio = this.referenceLandscapeClampedWidth(proposed) / this.cw;
    this.referenceLandscapeExpandProgress = Math.max(0, Math.min(1, (proposed - maximum) / (this.cw - maximum)));
  }

  private referenceLandscapeBeginResize(): void {
    if (this.fs || this.isAnimatingToFS) return;
    this.referenceLandscapeResizeStart = this.referenceLandscapePlayerWidth() / this.cw;
    this.referenceResizePanelWidth = this.referenceLandscapePanelWidth();
    this.referenceResizeSurfaceW = Math.max(1, this.ovVideoW());
    this.referenceResizeSurfaceH = Math.max(1, this.ovVideoH());
    this.resizeStartedAt = Date.now();
    this.resizeEventCount = 0;
    this.resizeLayoutCount = 0;
    this.resizeLayoutLastAt = this.resizeStartedAt;
    this.resizeLayoutMaxGap = 0;
    this.referenceLandscapeResizeActive = true;
  }

  private async referenceLandscapeFinishResize(offset: number, cancel: boolean = false): Promise<void> {
    if (!this.referenceLandscapeResizeActive) return;
    const elapsed = Math.max(1, Date.now() - this.resizeStartedAt);
    hilog.info(0x0000, 'ResizeMetrics', '%{public}s', `[ResizeMetrics] ms=${elapsed} events=${this.resizeEventCount} layouts=${this.resizeLayoutCount} eventHz=${(this.resizeEventCount * 1000 / elapsed).toFixed(1)} layoutHz=${(this.resizeLayoutCount * 1000 / elapsed).toFixed(1)} maxGap=${this.resizeLayoutMaxGap}`);
    this.referenceLandscapeResizeActive = false;
    if (cancel) {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 200, curve: Curve.EaseOut }, () => {
        this.referenceLandscapePlayerRatio = this.referenceLandscapeResizeStart;
        this.referenceLandscapeExpandProgress = 0;
      });
      return;
    }
    this.referenceLandscapeResize(offset);
    if (this.referenceLandscapeExpandProgress >= 0.62) {
      // Capture the held Surface before fullscreen changes its geometry. The
      // existing fullscreen animation continues from this exact rectangle.
      await this.enterFullscreenAnimated();
      if (this.fs) this.referenceLandscapePlayerRatio = this.referenceLandscapeResizeStart;
      this.referenceLandscapeExpandProgress = 0;
    } else {
      this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.referenceLandscapeExpandProgress = 0;
      });
    }
  }

  private referenceLandscapeDividerX(): number {
    return this.isLayoutSwapped ? this.cw - this.referenceLandscapePlayerWidth() : this.referenceLandscapePlayerWidth();
  }

  private referenceLandscapeHandleX(): number {
    return this.referenceLandscapePanelX() + (this.isLayoutSwapped ? this.referenceLandscapePanelWidth() : 0) - 16;
  }

  private referenceLandscapeViewportWidth(): number {
    return Math.max(1, this.referenceLandscapePlayerWidth() -
      2 * this.safeCM() * (1 - (this.referenceLandscapeExpandProgress || 0)));
  }

  private referenceLandscapeAreaTop(): number {
    return this.referenceSafeTop() * (1 - (this.referenceLandscapeExpandProgress || 0));
  }

  private referenceLandscapeAreaHeight(): number {
    // 画面延伸到窗口底边；手势区仅由控制层避让，不再缩短视频 Surface。
    return Math.max(1, this.ch - this.referenceLandscapeAreaTop());
  }

  private referenceLandscapeMediaWidth(): number {
    return Math.max(1, Math.min(this.referenceLandscapeViewportWidth(),
      this.referenceLandscapeAreaHeight() * Math.max(0.2, this.ar)));
  }

  private referenceLandscapeMediaHeight(): number {
    return this.referenceLandscapeMediaWidth() / Math.max(0.2, this.ar);
  }

  private referenceFeedCommentAmount(): number {
    return this.referenceFeedCommentAnimating ? this.referenceFeedCommentProgress : (this.referenceFeedComments ? 1 : 0);
  }
  private referenceSetFeedComments(open: boolean): void {
    if (open && (this.referenceModeAnimating || !this.referenceFeed || this.fs || this.isLs)) return;
    const target = open ? 1 : 0;
    const origin = this.referenceFeedCommentAmount();
    // ⭐ 渲染侧 animateTo 驱动，不再逐帧 JS 回调（同 animateVidShrink 的结论）：
    //    播放区宽度跟着评论面板逐帧收缩时，JS 定时器与 vsync 不对齐会让整段缩放发涩。
    this.referenceFeedCommentGen++;
    const gen = this.referenceFeedCommentGen;
    if (origin === target) {
      this.referenceFeedCommentAnimating = false;
      this.referenceFeedComments = open;
      this.onPlaybackViewportChanged();
      return;
    }
    this.referenceFeedCommentProgress = origin;
    this.referenceFeedCommentAnimating = true;
    // 关闭收尾前保持评论树，避免面板尚未离屏就切回简介。
    this.referenceFeedComments = true;
    this.cv = false;
    const finish = (): void => {
      if (this.referenceFeedCommentGen !== gen) return;
      this.referenceFeedCommentProgress = target;
      this.referenceFeedComments = open;
      this.referenceFeedCommentAnimating = false;
      this.onPlaybackViewportChanged();
    };
    try {
      this.getUIContext().animateTo({
        duration: Math.max(120, 320 * Math.abs(target - origin)),
        curve: curves.cubicBezierCurve(0.2, 0, 0, 1),
        onFinish: finish
      }, () => { this.referenceFeedCommentProgress = target; });
    } catch (_) {
      finish();
    }
  }

  private referenceAreaHeight(): number {
    const top = this.referenceSafeTop();
    if (this.mp && !this.fs && !this.isLs) return Math.max(100, this.ch * 0.39 - top);
    if (this.referenceFeedComments) {
      const target = Math.max(100, this.ch * 0.34);
      return this.referenceFeed ? this.ch + (target - this.ch) * this.referenceFeedCommentAmount() : target;
    }
    // 播放区域与面板共用边界，包括松手进入连刷的每一帧。
    if (this.referenceFeedProgress >= 1) return Math.max(1, this.ch);
    return Math.max(1, Math.min(this.ch, this.referenceDetailPanelTop() - this.referenceAreaTop()));
  }

  private referenceDetailBaseHeight(): number {
    return Math.max(this.cw * 9 / 16, Math.min(this.ch * 0.52, this.cw / Math.max(0.2, this.ar)));
  }

  private referenceMinimumPanelOffset(): number {
    return this.cw * 9 / 16 - this.referenceDetailBaseHeight();
  }

  private referencePanelDragOffset(offset: number): number {
    // 上推到屏幕等宽的 16:9 区域即停止，不再向更小的视频区域回弹越界。
    return Math.max(this.referenceMinimumPanelOffset(),
      offset > 110 ? 110 + Math.min(50, (offset - 110) * 0.25) : offset);
  }

  private referenceDetailAreaHeight(): number {
    // ⚠️ 这个下限不能拆：它保证播放区高度 >= 16:9 区域高度，
    //    从而 referenceMediaWidth = min(cw, areaH*ar) 对 16:9 恒等于 cw。
    //    拆掉后 16:9 会被算成窄画面，出现「两侧黑边」的稳态（真机反馈）。
    return Math.max(this.cw * 9 / 16, this.referenceDetailBaseHeight() + this.referencePanelOffset);
  }

  private referenceDetailPanelTop(): number {
    if (this.referenceFeedComments) {
      const target = this.referenceSafeTop() + Math.max(100, this.ch * 0.34);
      return this.referenceFeed ? this.ch + 12 + (target - this.ch - 12) * this.referenceFeedCommentAmount() : target;
    }
    const detail = this.referenceSafeTop() + this.referenceDetailAreaHeight();
    return detail + (this.ch + 12 - detail) * this.referenceFeedProgress;
  }

  private referenceMediaWidth(aspect: number = this.ar): number {
    if (this.referenceFeed && this.referenceFeedComments) {
      const start = this.effectiveScaleMode(aspect) === 'auto' ? Math.min(this.cw, this.ch * Math.max(0.2, aspect)) : this.cw;
      const end = Math.min(this.cw, Math.max(100, this.ch * 0.34) * Math.max(0.2, aspect));
      return start + (end - start) * this.referenceFeedCommentAmount();
    }
    if (this.referencePortraitCropTransition(aspect)) {
      const contained = Math.max(1, Math.min(this.cw, this.referenceAreaHeight() * Math.max(0.2, aspect)));
      return contained + (Math.max(1, this.cw) - contained) * this.referenceFeedProgress;
    }
    if (this.effectiveScaleMode(aspect) !== 'auto') return Math.max(1, this.cw);
    return Math.max(1, Math.min(this.cw, this.referenceAreaHeight() * Math.max(0.2, aspect)));
  }

  private referenceMediaHeight(aspect: number = this.ar): number {
    if (this.referenceFeed && this.referenceFeedComments) {
      const start = this.effectiveScaleMode(aspect) === 'auto' ? Math.min(this.ch, this.cw / Math.max(0.2, aspect)) : this.ch;
      const end = Math.min(Math.max(100, this.ch * 0.34), this.cw / Math.max(0.2, aspect));
      return start + (end - start) * this.referenceFeedCommentAmount();
    }
    if (this.referencePortraitCropTransition(aspect)) {
      const area = this.referenceAreaHeight();
      const contained = Math.max(1, Math.min(this.cw, area * Math.max(0.2, aspect))) / Math.max(0.2, aspect);
      return contained + (area - contained) * this.referenceFeedProgress;
    }
    if (this.effectiveScaleMode(aspect) !== 'auto') return this.referenceAreaHeight();
    return this.referenceMediaWidth(aspect) / Math.max(0.2, aspect);
  }

  private referencePortraitCropTransition(aspect: number): boolean {
    // referenceFeed 在动画开始就翻转；裁切幅度必须跟随进度，不能随布尔值瞬间铺满。
    // 进度为 0 时 Surface 仍是完整画幅，切换原生 crop/contain 不会改变可见内容。
    return !this.fs && this.referenceModeAnimating && aspect < 1 && this.effectiveScaleMode(aspect) === 'fill';
  }

  private referenceAreaTop(aspect: number = this.ar): number {
    if (this.referenceFeed && this.referenceFeedComments) {
      const height = this.effectiveScaleMode(aspect) === 'auto' ? Math.min(this.ch, this.cw / Math.max(0.2, aspect)) : this.ch;
      const start = Math.max(0, this.ch * (aspect >= 1 ? 0.4 : 0.5) - height / 2);
      const end = this.referenceSafeTop() + Math.max(0, Math.max(100, this.ch * 0.34) -
        Math.min(Math.max(100, this.ch * 0.34), this.cw / Math.max(0.2, aspect))) / 2;
      return start + (end - start) * this.referenceFeedCommentAmount();
    }
    const top = this.referenceSafeTop() + (this.referenceFeedComments || this.mp ? 0 : Math.max(0, this.referencePanelOffset) * 0.4);
    if (this.referenceFeedComments || this.mp) return top;
    // 原版横片中心位于屏幕约 40% 处；竖片仍按整屏容纳。
    // 使用最终画幅计算目标位置，不能用正在变大的高度反算目标位置。
    const feedHeight = this.effectiveScaleMode(aspect) === 'auto' ? Math.min(this.ch, this.cw / Math.max(0.2, aspect)) : this.ch;
    const center = Math.max(0, this.ch * (aspect >= 1 ? 0.4 : 0.5) - feedHeight / 2);
    return top + (center - top) * this.referenceFeedProgress;
  }

  private referenceMediaTop(aspect: number = this.ar): number {
    // 区域边界独立于画面位置，避免居中偏移反过来缩小可用高度。
    // 半屏上下均分留白；进入连刷时连续过渡到原有画面位置。
    const inset = Math.max(0, this.referenceAreaHeight() - this.referenceMediaHeight(aspect)) / 2;
    return this.referenceAreaTop(aspect) + inset * (1 - this.referenceFeedProgress);
  }

  private referenceFullscreenButtonTop(aspect: number = this.ar): number {
    return Math.min(this.ch - 240, this.referenceMediaTop(aspect) + this.referenceMediaHeight(aspect) + 10);
  }

  private onReferencePreviewXc = (): void => {
    const surfaceId = (this.referenceSecondSurfaceActive ? this.xc : this.referencePreviewXc).getXComponentSurfaceId();
    // 诊断：这条不出现 = 备用 XComponent 从未加载，预览预热就永远没有 surface 可用。
    logInfo(`[ReferenceFeed] preview xc surface=${surfaceId || 'EMPTY'} active=${this.referenceSecondSurfaceActive} spare=${this.referenceSpareSurfaceMounted} preview=${this.referenceFeedPreview?.id || '-'}`);
    if (!surfaceId) return;
    this.referencePreviewSurfaceId = surfaceId;
    if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
    else if (this.referenceLayout) {
      this.ensureReferenceRecommendQueue().then(() => {
        if (!this.referenceAlive || this.referencePreviewRequestedId) return;
        this.referenceFeedPreview = this.referenceFeedNeighbor(1);
        if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
      });
    }
  }

  private referenceFeedAspect(detail: VideoDetail, cid: number, fallback: number): number {
    const page = detail.pages?.find((item: VideoPageItem) => item.cid === cid);
    const dimension = page?.dimension || detail.dimension;
    if (!dimension || dimension.width <= 0 || dimension.height <= 0) return fallback;
    return Math.abs(dimension.rotate || 0) % 180 === 90
      ? dimension.height / dimension.width : dimension.width / dimension.height;
  }

  private referencePreviewPresentationLocked(): boolean {
    return this.referenceVerticalSwipe || this.referenceFeedLoading || !!this.referenceFeedAnimator;
  }

  /**
   * 邻片详情预热：只拿详情，不绑定解码器 / Surface / 画幅。
   * 信息层要的东西（头像、UP主、标题、各项计数）全在详情里，和"能不能出画面"无关。
   * 之前详情只在静帧解码成功后随 referencePublishStill 一起发布，于是：
   *   - 刚切换完 referenceFeedSlotPending 期间解码通道是关的，拖动时详情还是空的；
   *   - 拖动途中详情回来了，又被 referencePreviewPresentationLocked() 拦住不发布。
   * 两个窗口叠加，信息层就只能先退到队列兜底字段，翻完页才跳成正确的。
   */
  private requestReferenceDetail(id: string): Promise<VideoDetail | null> {
    if (!id || !this.referenceAlive || this.qs) return Promise.resolve(null);
    const cached = this.referenceStillDetails.get(id);
    if (cached) return Promise.resolve(cached);
    const running = this.referenceDetailJobs.get(id);
    if (running) return running;
    const job: Promise<VideoDetail | null> = getVideoDetail(id).then((detail: VideoDetail | null) => {
      this.referenceDetailJobs.delete(id);
      if (!detail || !this.referenceAlive) return null;
      // 详情往往比静帧早到几百毫秒：先入缓存并发布，信息层立刻可用；
      // 之后静态帧解码完，referencePublishStill 只等 frame，不会再重置文案。
      this.referenceStillDetails.set(id, detail);
      this.trimReferenceDetails(id);
      this.publishReferencePreviewDetail(id, detail);
      // 两级邻片详情到达后预解码头像；冷缓存由 FeedAvatarImage 在身份校验后补齐。
      const faceUrl = imageUrlResize(detail.owner?.face || '', 48);
      if (faceUrl && !getCachedPixelMap(faceUrl)) predecodeImage(faceUrl);
      logInfo(`[ReferenceFeed] detail ready ${id} title=${detail.title} up=${detail.owner?.name}`);
      return detail;
    }).catch((error: Error) => {
      this.referenceDetailJobs.delete(id);
      logWarn(`连续播放详情预热失败 ${id}: ${error?.message ?? error}`);
      return null;
    });
    this.referenceDetailJobs.set(id, job);
    return job;
  }

  /** 信息层数据独立发布：只有画幅（aspect）需要跟 presentation lock，文案/头像随时可换。 */
  private publishReferencePreviewDetail(id: string, detail: VideoDetail): void {
    if (id !== this.referencePreviewRequestedId) return;
    // 快照幂等且必须先保证：detail 与上一条相同时下面的 early-return 会跳过，
    // 但快照可能刚被「换目标」清掉，不能一起跳过。
    this.publishFeedNextChrome(id, detail);
    const current = this.referencePreviewDetail;
    if (current && current.bvid === detail.bvid && current.owner?.face === detail.owner?.face &&
      current.owner?.name === detail.owner?.name && current.title === detail.title) return;
    this.referencePreviewDetail = detail;
  }

  /**
   * 滑入页信息层的「一次性锁定」：目标确定后整份快照只在这里整体替换。
   * 提交时当前页用的也是同一个 detail，所以两套信息层交接前后字节一致，硬切看不出来。
   */
  private publishFeedNextChrome(id: string, detail: VideoDetail): void {
    if (id !== this.referencePreviewRequestedId) return;
    // 头像统一用 resize 后的 URL 作为缓存 key（预解码在 requestReferenceDetail 里统一发起，
    // 覆盖两级预取的所有稿件，避免这里重复发一次 HTTP）。
    const faceUrl = imageUrlResize(detail.owner?.face || '', 48);
    const next: FeedChromeInfo = {
      id: id,
      face: faceUrl,
      name: detail.owner?.name || '',
      title: detail.title || '',
      duration: detail.duration || 0,
      like: detail.stat?.like || 0,
      coin: detail.stat?.coin || 0,
      favorite: detail.stat?.favorite || 0,
      reply: detail.stat?.reply || 0
    };
    const cur = this.referenceFeedNextChrome;
    if (cur && cur.id === id && cur.face === next.face && cur.name === next.name &&
      cur.title === next.title && cur.duration === next.duration && cur.like === next.like &&
      cur.coin === next.coin && cur.favorite === next.favorite && cur.reply === next.reply) return;
    this.referenceFeedNextChrome = next;
    logInfo(`[ReferenceFeed] next chrome locked ${id} up=${next.name} title=${next.title}`);
  }

  /** 渲染前再校验一次：快照必须属于当前滑入页，绝不拿上一条的头像顶坑。 */
  private feedNextChrome(): FeedChromeInfo | null {
    const item = this.referenceFeedPreview;
    const info = this.referenceFeedNextChrome;
    return item && info && info.id === item.id ? info : null;
  }

  /**
   * 连刷信息层与屏幕底边的距离：与顶部控件同一套安全区口径。
   * 顶部控件固定在 referenceSafeTop()（状态栏下沿），信息层底部就用同一个值；
   * 系统手势条更高时取手势条，避免操作栏压进手势区。
   */
  private referenceChromeInset(): number {
    return Math.max(this.referenceSafeTop(), this.navIndicatorHeight + 4);
  }

  /**
   * 两套信息层共用的位置：固定在屏幕底部，不再贴「全屏播放」按钮或按画幅收
   * （平板上的宽画幅视频会被压成中间一条，跟着画幅走会让整块信息飘到屏幕中间）。
   * 滑入页额外带一个「跟手提前量」：信息层钉在页面底部，页面没滑到位前整块还在屏幕外，
   * 于是拖动中只能看到下一条的画面、看不到它的信息，翻完页才突然出现（用户说的跳一下）。
   * 这里按滑入进度把它相对页面上移，让它跟着画面一起进视口；滑到位时提前量收敛到 0，
   * 与当前页信息层落在同一个位置，提交瞬间两层交接不会错位。
   */
  private feedChromeTop(preview: boolean = false): number {
    // 固定在屏幕底部，不再跟着画幅走：平板上的宽画幅视频会被压成中间一条，
    // 原先用「视频底边 + 34」当上限，整块信息会跟着视频飘到屏幕中间、下面空一大片。
    const base = Math.max(0, this.ch - 244 - this.referenceChromeInset());
    if (!preview) return base;
    const progress = Math.min(1, Math.abs(this.referenceFeedDragY) / Math.max(1, this.ch));
    return Math.max(0, base - (1 - progress) * this.ch * 0.45);
  }

  /** 详情缓存只留最近的几条，保留正在用/相邻的那几个。 */
  private trimReferenceDetails(keepId: string): void {
    if (this.referenceStillDetails.size <= 6) return;
    const keep: string[] = [this.vi.bvid, keepId, this.referencePreviewRequestedId,
      this.referenceFeedNeighbor(1)?.id || '', this.referenceFeedNeighbor(-1)?.id || ''];
    const overflow = this.referenceStillDetails.size - 6;
    const evict: string[] = [];
    this.referenceStillDetails.forEach((_detail: VideoDetail, id: string) => {
      if (evict.length >= overflow) return;
      if (keep.indexOf(id) >= 0) return;
      // 还有静帧挂在表里的条目不能删：referencePublishStill 需要 frame + detail 同时在。
      if (this.referenceStillFrames.has(id)) return;
      evict.push(id);
    });
    for (const id of evict) this.referenceStillDetails.delete(id);
  }

  private referencePublishStill(id: string, initialize: boolean = false): boolean {
    const frame = this.referenceStillFrames.get(id);
    const detail = this.referenceStillDetails.get(id);
    if (!frame || !detail) return false;
    // 翻页提交时静帧还没解出来：之后到达的「当前片」静帧要补给固定页。
    // 固定页在不透明层最上面，不补的话这张图会被它挡住，只剩黑底转圈。
    if (id === this.vi.bvid && this.referenceFeedPreviewPinned && !this.referencePinnedFrame) {
      this.referencePinnedFrame = frame;
      this.referencePinnedCover = '';
      const ratio = this.referenceStillRatios.get(id);
      if (ratio && ratio > 0) this.referencePinnedAspectRatio = ratio;
    }
    if (id !== this.referencePreviewRequestedId) return false;
    if (!initialize && this.referencePreviewPresentationLocked()) return true;
    logInfo(`[ReferenceFeed] preview publish ${id} title=${detail.title} frame=${!!frame} req=${this.referencePreviewRequestedId}`);
    this.referencePreviewFrame = frame;
    this.referencePreviewDetail = detail;
    this.referencePreviewAspectRatio = this.referenceStillRatios.get(id) ?? 1;
    this.referencePreviewFrameReady = true;
    return true;
  }

  /**
   * 邻片预热的节奏：-1 = 不预热，0 = 立即，>0 = 正片稳住后延迟多少毫秒。
   * 连刷里的「下一条」不是投机流量，是用户马上要看的正片：蜂窝/计费网络同样要预热，
   * 否则每次上滑都退回冷启动，表现就是一直转圈。仍然只保留一条邻片，
   * 翻页/退出即释放；`--ps neighborWarm off` 可整体关闭。
   */
  private neighborWarmMode(): number {
    if (AppStorage.get<boolean>('playbackNeighborWarm') === false) return -1;
    return 0;
  }

  /** 延迟版邻片预热：正片没稳住就顺延，最多三次，避免和起播抢带宽。 */
  private scheduleNeighborWarm(item: RecommendItem, delayMs: number): void {
    if (this.neighborWarmTimer_ !== -1) clearTimeout(this.neighborWarmTimer_);
    this.neighborWarmTimer_ = setTimeout(() => {
      this.neighborWarmTimer_ = -1;
      if (!this.referenceAlive || !this.playerPageVisible || !this.play ||
        this.waitingForFirstFrame || this.qs || this.ld) {
        if (this.referenceAlive && this.playerPageVisible && this.neighborWarmAttempts_ < 3) {
          this.neighborWarmAttempts_++;
          this.scheduleNeighborWarm(item, 1500);
        }
        return;
      }
      // 队列可能已经翻页：目标变了就放弃这次排队。
      const target = this.referenceFeedPreview || this.referenceFeedNeighbor(1);
      if (!target || target.id !== item.id || this.referenceWarmSession?.id === item.id) return;
      this.neighborWarmAttempts_ = 0;
      logInfo(`[ReferenceFeed] neighbor warm start delay=${delayMs}ms id=${item.id}`);
      this.neighborWarmBypass_ = true;
      this.referenceDecodeStill(item).then((ready: boolean) => {
        this.neighborWarmBypass_ = false;
        if (ready) this.referencePublishStill(item.id);
      }, () => { this.neighborWarmBypass_ = false; });
    }, delayMs);
  }

  private referenceDecodeStill(item: RecommendItem): Promise<boolean> {
    if (this.referenceFeedSlotPending) return Promise.resolve(false);
    const mode = this.neighborWarmMode();
    if (mode < 0) return Promise.resolve(false);
    // 真手势/预加载需要立刻出图，不走延迟；其余情况先排队，等正片稳住。
    if (mode > 0 && !this.neighborWarmBypass_ && !this.referenceVerticalSwipe && !this.referenceFeedLoading) {
      this.scheduleNeighborWarm(item, mode);
      return Promise.resolve(false);
    }
    if (this.referencePreviewPreparing && this.referencePreviewDecodingId === item.id) return this.referencePreviewDecodePromise;
    const generation = ++this.referencePreviewGeneration;
    this.referencePreviewDecodingId = item.id;
    this.referencePreviewPreparing = true;
    // Release the prior owner before a new decoder binds the inactive Surface.
    const retired = this.referenceWarmSession;
    this.referenceWarmSession = null;
    if (retired) {
      this.referencePreviewReleaseJob = Promise.all([this.referencePreviewReleaseJob, retired.release()]).then(() => {});
    }
    this.referencePreviewDecodePromise = this.referencePreviewReleaseJob.then(() =>
      this.prepareReferenceFeedPreview(item, generation)).then((ready: boolean) => {
      if (generation === this.referencePreviewGeneration) {
        this.referencePreviewPreparing = false;
        if (ready) this.referenceWarmUpcomingFrames();
      }
      return ready;
    });
    return this.referencePreviewDecodePromise;
  }

  private referenceWarmUpcomingFrames(): void {
    this.referencePrefetchPlaylistUrls();
    if (this.qs) return;
    if (!this.referenceAlive || !this.playerPageVisible || !this.referenceLayout) return;
    // ⭐ 详情预热不排在任何画面条件后面：它不占解码器、不占带宽（命中接口缓存时是内存读）。
    //   首帧前 / 刚切换完 slotPending 期间都要跑，否则用户在这两个窗口里拖动，
    //   信息层连"下一条是谁"都不知道。
    const upcoming = this.referenceFeedPreview || this.referenceFeedNeighbor(1);
    if (upcoming) this.requestReferenceDetail(upcoming.id);
    const afterUpcoming = this.referenceFeedNeighbor(2);
    if (afterUpcoming) this.requestReferenceDetail(afterUpcoming.id);
    if (this.waitingForFirstFrame || this.referenceFeedSlotPending || this.referencePreviewPreparing || !this.referencePreviewSurfaceId) return;
    const queue = this.referenceFeedQueue;
    const current = queue.findIndex((item: RecommendItem) => item.id === this.vi.bvid);
    if (current < 0) return;
    if (queue.length - current <= 6) this.referenceAppendRecommendations();
    // One decoded neighbour only: keep its complete session for direct handoff.
    const pending = this.referenceFeedPreview || this.referenceFeedNeighbor(1);
    if (pending && this.referenceWarmSession?.id !== pending.id) this.referenceDecodeStill(pending);
  }

  private referencePrefetchPlaylistUrls(): void {
    if (!this.referenceAlive || !this.playerPageVisible || this.waitingForFirstFrame || this.isPgc_ || this.qs) {
      this.playbackListPrefetch.pause();
      return;
    }
    const feedQueue = this.referenceFeedQueue.length > 1;
    const queue = feedQueue ? this.referenceFeedQueue : this.relatedVideos;
    const current = queue.findIndex((item: RecommendItem) => item.id === this.vi.bvid);
    // Complete small queues, prioritizing the forward neighbours; retain backward entries too.
    const ordered = [...queue.slice(current + 1), ...queue.slice(0, Math.max(0, current))];
    this.playbackListPrefetch.update(ordered, feedQueue ? this.preferredQn : (AppStorage.get<number>('defaultVideoQn') ?? 116));
  }

  private requestReferenceFeedPreview(item: RecommendItem): void {
    if (this.qs) return;
    if (!item.id) return;
    const sameTarget = this.referencePreviewRequestedId === item.id;
    if (!sameTarget) logInfo(`[ReferenceFeed] preview target ${item.id} was=${this.referencePreviewRequestedId}`);
    this.referencePreviewRequestedId = item.id;
    // ⭐ 换目标先作废旧快照：宁可这一帧不显示信息层，也绝不能让上一条的头像顶坑
    //   （用户看到的「他人头像」就是这么来的）。下面同一个同步块里会立刻填上新目标的数据。
    const oldChrome = this.referenceFeedNextChrome;
    if (oldChrome && oldChrome.id !== item.id) this.referenceFeedNextChrome = null;
    const cachedDetail = this.referenceStillDetails.get(item.id);
    if (cachedDetail) {
      // 同步发布：预览页信息层从它进入视口的第一帧起就是最终数据。
      this.referencePreviewDetail = cachedDetail;
      this.publishFeedNextChrome(item.id, cachedDetail);
    } else if (!sameTarget) {
      this.referencePreviewDetail = null;
    }
    // ⭐ 详情先走独立的轻量通道：信息层（头像/UP主/标题）不依赖预览 Surface 和解码器。
    //   原来这里 Surface 没就绪就直接 return，连刷刚进来的那一下拖动连详情都不发，
    //   信息层只能空着等翻完页。
    this.requestReferenceDetail(item.id);
    // 再往前多预热一条：连续快切时永远有两条余量，拖动前不可能撞上「详情还没回来」。
    const afterNext = this.referenceFeedNeighbor(2);
    if (afterNext) this.requestReferenceDetail(afterNext.id);
    const cached = this.referencePublishStill(item.id, !sameTarget);
    if (!cached && !sameTarget) {
      this.referencePreviewFrameReady = false;
      this.referencePreviewDetail = this.referenceStillDetails.get(item.id) || null;
      this.referencePreviewFrame = undefined;
      // A cold neighbour must never inherit the preceding neighbour's geometry.
      this.referencePreviewAspectRatio = this.referenceStillRatios.get(item.id) ||
        (item.videoWidth > 0 && item.videoHeight > 0 ? item.videoWidth / item.videoHeight : 1);
    }
    // 画面（静帧/解码器）才需要预览 Surface，详情已经发在上面了。
    if (!this.referencePreviewSurfaceId) return;
    if (this.referenceWarmSession?.id === item.id && this.referenceWarmSession.ready) {
      return;
    }
    // 首帧前只响应真实切换手势；后台邻片预解码等当前视频出画面后再启动。
    if (this.waitingForFirstFrame && !this.referenceVerticalSwipe && !this.referenceFeedLoading) return;
    this.referenceDecodeStill(item).then((ready: boolean) => {
      return ready && this.referencePublishStill(item.id);
    });
  }

  /**
   * 将复用 Surface 抓图还原为真实画幅。
   * AVPlayer 的 SCALED_ASPECT 会补黑边，按画幅裁边；IJK 整帧铺满 buffer，
   * 即使 buffer 沿用上一条比例也须保留完整内容，通过缩放还原，不能当黑边裁掉。
   */
  private async cropStillToPicture(pm: image.PixelMap, contentRatio: number,
    stretchedBuffer: boolean = false): Promise<image.PixelMap> {
    try {
      const info = pm.getImageInfoSync();
      const w = info.size?.width || 0;
      const h = info.size?.height || 0;
      if (!w || !h || !(contentRatio > 0)) return pm;
      const canvasRatio = w / h;
      if (Math.abs(canvasRatio / contentRatio - 1) <= 0.02) return pm;
      let rw = w;
      let rh = h;
      if (contentRatio < canvasRatio) rw = Math.max(2, Math.min(w, Math.round(h * contentRatio)));
      else rh = Math.max(2, Math.min(h, Math.round(w / contentRatio)));
      if (rw === w && rh === h) return pm;
      // IJK 的 videoScaleType 不参与原生渲染：整帧铺满 buffer，并没有 FIT 黑边。
      // 复用旧比例 buffer 时须还原整张画面的比例，裁中央会丢掉真实内容。
      if (stretchedBuffer) {
        await pm.scale(rw / w, rh / h);
        logInfo(`[ReferenceFeed] still restore ${w}x${h} -> ${rw}x${rh} real=${contentRatio.toFixed(4)}`);
        return pm;
      }
      // PixelMap.crop 是原地裁切（Promise<void>），返回同一张位图。
      await pm.crop({
        x: Math.round((w - rw) / 2), y: Math.round((h - rh) / 2),
        size: { width: rw, height: rh }
      });
      logInfo(`[ReferenceFeed] still crop ${w}x${h} -> ${rw}x${rh} canvas=${canvasRatio.toFixed(4)} real=${contentRatio.toFixed(4)}`);
      return pm;
    } catch (error) {
      logWarn(`[ReferenceFeed] still crop failed: ${error}`);
      return pm;
    }
  }

  private async prepareReferenceFeedPreview(item: RecommendItem, generation: number): Promise<boolean> {
    if (!this.referenceAlive || generation !== this.referencePreviewGeneration || !this.referencePreviewSurfaceId) return false;
    let session: FeedPlaybackSession | null = null;
    try {
      const detail = await this.requestReferenceDetail(item.id);
      if (!this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      const cid = item.cid || detail?.cid || detail?.pages?.[0]?.cid || 0;
      if (!detail || cid <= 0) return false;
      item.cid = cid;
      // Publish geometry before waiting for signed URLs, decoding or a Surface capture.
      // The cover and the decoded still must use the destination video's aspect.
      const aspect = this.referenceFeedAspect(detail, cid, this.referencePreviewAspectRatio);
      this.referenceWarmAspectRatio = aspect;
      if (this.referencePreviewRequestedId === item.id) {
        // 信息层与画幅解耦：文案/头像拖动途中也立刻要正确；
        // 比例必须等手势结束，否则静帧会在手指底下改尺寸（水印跳位）。
        this.publishReferencePreviewDetail(item.id, detail);
        if (!this.referencePreviewPresentationLocked()) {
          this.referencePreviewAspectRatio = this.referenceStillRatios.get(item.id) || aspect;
        }
      }
      // 邻片也按偏好画质取流：这里若用 `qn`，当前条被降级就会把下一条一起拖低。
      const result = await getVideoPlayUrl(item.id, cid, this.preferredQn);
      if (!this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      if (!result.url) return false;
      // ⭐ 预热盒子的比例一旦确定就先让布局落一帧，再让解码器绑上 surface。
      //   备胎 surface 是「上一条刚播完的那块」——它最后一次分配 buffer 用的是上一目标的盒子。
      //   盒子改了但 surface 在同一次布局里被复用，buffer 尺寸就可能停在旧比例（实测 1320x743）。
      //   先等布局落地，surface 才会按新盒子重新分配，抓图拿到的才是目标尺寸。
      await new Promise<void>((resolve) => setTimeout(resolve, 32));
      if (!this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      session = new FeedPlaybackSession(item.id, this.referencePreviewSurfaceId, result);
      session.aspectRatio = aspect;
      this.referenceWarmSession = session;
      // 解码器实测画幅（videoSizeChange）。注意不能直接读 session.aspectRatio：
      // 上面刚被赋成目标值，回调没来时它看起来「已经匹配」，等于没等。
      // 也不在这里改 referenceWarmAspectRatio —— 那是布局状态，准备途中改它会让
      // 备胎 surface 在解码器绑着的时候换盒子，buffer 尺寸就随机了。
      let decoderAspect = 0;
      session.onSizeChanged = (real: number) => {
        decoderAspect = real;
        logInfo(`[ReferenceFeed] decoder ${item.id} size aspect=${real.toFixed(4)} declared=${aspect.toFixed(4)}`);
      };
      // Capture a complete frame; the Image applies the destination crop exactly once.
      const ready = await session.prepare(media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT, AppStorage.get<string>('biliCookie') || '');
      if (!ready || !this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      // ⭐ 先等解码器把画幅真正切过来再抓图：预热 surface 会沿用上一条（可能是横屏）的 buffer
      //   尺寸，竖屏视频这时被输出到横屏 buffer 里，抓下来的就是**已经被拉伸的画面**，
      //   切过去先显示这张静帧 → 用户看到「首帧拉伸」，等 Surface 出真帧才恢复。
      //   横切横时 videoSizeChange 不会触发，最多等 400ms 就照抓，不拖慢预热。
      //   400ms 而不是 120ms：实测 120ms 时竖屏视频仍拿到上一条横屏的 buffer（1320x743），
      //   抓出来的静帧比例 1.7766 与画幅 0.5625 不符，切到 Surface 必然跳一次。
      const aspectDeadline = Date.now() + 400;
      while (Date.now() < aspectDeadline) {
        if (decoderAspect > 0 && Math.abs(decoderAspect / aspect - 1) <= 0.02) break;
        await new Promise<void>((resolve) => setTimeout(resolve, 16));
        if (!this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      }
      // Allow the inactive Surface to adopt the decoded aspect before taking its fallback frame.
      await new Promise<void>((resolve) => setTimeout(resolve, 32));
      if (!this.referenceAlive || generation !== this.referencePreviewGeneration) return false;
      // The x86 emulator does not expose a consistent decoder readback orientation.
      // Keep its warm decoder, but use the target cover instead of caching corrupt stills.
      if (deviceInfo.abiList.includes('x86_64')) {
        this.referenceStillDetails.set(item.id, detail);
        this.referenceStillRatios.set(item.id, session.aspectRatio);
        if (this.referencePreviewRequestedId === item.id && !this.referencePreviewPresentationLocked()) this.referencePreviewAspectRatio = session.aspectRatio;
        logInfo(`[ReferenceFeed] warm ready ${item.id} surface=${session.surfaceId} cover fallback`);
        return true;
      }
      // Decoder buffers may carry a vertical flip/rotation in their Surface transform.
      // Preserve the displayed orientation when that buffer becomes an Image.
      const captured = await image.createPixelMapFromSurfaceWithTransformation(session.surfaceId, true);
      if (!this.referenceAlive || generation !== this.referencePreviewGeneration) {
        captured.release().catch(() => {});
        return false;
      }
      // ⭐ 抓到的画布比例 = 这块 surface **上一次**布局的盒子，而不是当前盒子时，说明新盒子还没落到
      //   这块隐藏的 XComponent 上：位图既不是目标尺寸、画面也被按旧盒子重新排过版。
      //   裁黑边只能把「比例」凑对，凑不了「缩放」—— 切到真 surface 时画面照样跳。
      //   这种情况先不发布静帧，等布局落地后重抓（最多两轮）；两轮还不行才退回裁边。
      const capInfo = captured.getImageInfoSync();
      const capRatio = capInfo.size && capInfo.size.height > 0 ? capInfo.size.width / capInfo.size.height : 0;
      const boxRatio = this.referenceWarmSurfaceHeight() > 0
        ? this.referenceWarmSurfaceWidth() / this.referenceWarmSurfaceHeight() : 0;
      const stretchedBuffer = supportsIjkPlayback(result);
      // IJK 允许整帧铺到旧 buffer；下方按解码比例还原，无须重复释放、重建播放器。
      const staleCanvas = !stretchedBuffer && boxRatio > 0 && capRatio > 0 && Math.abs(capRatio / boxRatio - 1) > 0.03;
      const staleAttempt = this.referenceWarmStaleAttempts.get(item.id) || 0;
      if (staleCanvas && staleAttempt < 2) {
        this.referenceWarmStaleAttempts.set(item.id, staleAttempt + 1);
        logWarn(`[ReferenceFeed] still stale ${item.id} canvas=${capRatio.toFixed(4)} box=${boxRatio.toFixed(4)} attempt=${staleAttempt + 1} — surface 未按新盒子重建，重抓`);
        captured.release().catch(() => {});
        if (this.referenceWarmSession === session) this.referenceWarmSession = null;
        await session.release();
        setTimeout(() => {
          if (this.referenceAlive) this.requestReferenceFeedPreview(item);
        }, 180 * (staleAttempt + 1));
        return false;
      }
      if (staleCanvas) logWarn(`[ReferenceFeed] still stale fallback ${item.id} canvas=${capRatio.toFixed(4)} box=${boxRatio.toFixed(4)} — 重抓两轮仍未重建`);
      this.referenceWarmStaleAttempts.delete(item.id);
      // 按实际播放器的输出方式还原完整画面，再交给 Image 应用目标缩放模式。
      const still = await this.cropStillToPicture(captured,
        decoderAspect > 0 ? decoderAspect : session.aspectRatio, stretchedBuffer);
      const oldFrame = this.referenceStillFrames.get(item.id);
      if (oldFrame && (oldFrame === this.referencePinnedFrame ||
        (oldFrame === this.referencePreviewFrame && this.referencePreviewPresentationLocked()))) {
        still.release().catch(() => {});
        return true;
      }
      this.referenceStillFrames.set(item.id, still);
      if (oldFrame && oldFrame !== still) this.retireStillFrame(oldFrame);
      const info = still.getImageInfoSync();
      const pmRatio = info.size && info.size.height > 0 ? info.size.width / info.size.height : 0;
      // ⭐ 两个比例分开存，各管各的：
      //   stillRatio（= 裁掉黑边后的位图比例）只给固定页/预览页那张 Image；
      //   decodeRatio（= 解码器实测画幅）只给视频 ar。
      const stillRatio = pmRatio > 0 ? pmRatio : session.aspectRatio;
      const decodeRatio = decoderAspect > 0 ? decoderAspect : session.aspectRatio;
      this.referenceDecodeRatios.set(item.id, decodeRatio);
      logInfo(`[ReferenceFeed] still ${item.id} surface=${session.surfaceId} pm=${info.size?.width}x${info.size?.height} pmRatio=${pmRatio.toFixed(4)} session=${session.aspectRatio.toFixed(4)} decoder=${decoderAspect.toFixed(4)} declared=${aspect.toFixed(4)} pick=${stillRatio.toFixed(4)} warmBox=${this.referenceWarmSurfaceWidth().toFixed(0)}x${this.referenceWarmSurfaceHeight().toFixed(0)} areaH=${this.referenceAreaHeight().toFixed(0)} second=${this.referenceSecondSurfaceActive}`);
      this.referenceStillDetails.set(item.id, detail);
      this.referenceStillRatios.set(item.id, stillRatio);
      this.referencePublishStill(item.id);
      while (this.referenceStillFrames.size > 4) {
        const previousId = this.referenceFeedNeighbor(-1)?.id || '';
        const evict = Array.from(this.referenceStillFrames.keys()).find((id: string) =>
          id !== this.vi.bvid && id !== previousId && id !== item.id && id !== this.referencePreviewRequestedId);
        if (!evict) break;
        const retired = this.referenceStillFrames.get(evict);
        this.referenceStillFrames.delete(evict);
        this.referenceStillDetails.delete(evict);
        this.referenceStillRatios.delete(evict);
        this.referenceDecodeRatios.delete(evict);
        this.retireStillFrame(retired);
      }
      logInfo(`[ReferenceFeed] warm ready ${item.id} surface=${session.surfaceId} dash=${!!result.dash}`);
      return true;
    } catch (error) {
      logWarn(`连续播放预热失败: ${error}`);
      return false;
    } finally {
      if (session && !session.reserved && (!session.ready || generation !== this.referencePreviewGeneration || !this.referenceAlive)) {
        if (this.referenceWarmSession === session) this.referenceWarmSession = null;
        await session.release();
      }
    }
  }

  private async releaseReferenceFeedPreview(): Promise<void> {
    this.referencePreviewGeneration++;
    this.referencePreviewRequestedId = '';
    this.referenceFeedNextChrome = null;
    this.referencePreviewPreparing = false;
    this.referencePreviewFrameReady = false;
    this.referencePreviewFrame = undefined;
    this.sweepStillFrames();
    const session = this.referenceWarmSession;
    this.referenceWarmSession = null;
    if (session) await session.release();
    await Promise.all([this.referencePreviewDecodePromise, this.referencePreviewReleaseJob]);
  }

  /**
   * 静帧位图延迟释放：先排队，等下一次巡检确认没有组件还引用它才真正 release。
   * 任何时候被新的固定页/预览页选中都会重新算作「在用」。
   */
  private retireStillFrame(frame: image.PixelMap | undefined | null): void {
    if (!frame) return;
    if (this.pendingStillReleases.indexOf(frame) >= 0) return;
    this.pendingStillReleases.push(frame);
    this.scheduleStillSweep(300);
  }

  private scheduleStillSweep(delay: number): void {
    if (this.stillSweepTimer_ !== -1) return;
    this.stillSweepTimer_ = setTimeout(() => {
      this.stillSweepTimer_ = -1;
      this.sweepStillFrames();
    }, delay);
  }

  private stillFrameInUse(frame: image.PixelMap): boolean {
    if (frame === this.referencePreviewFrame || frame === this.referencePinnedFrame) return true;
    let used = false;
    this.referenceStillFrames.forEach((item: image.PixelMap) => { if (item === frame) used = true; });
    return used;
  }

  private sweepStillFrames(): void {
    if (this.pendingStillReleases.length === 0) return;
    const remain: image.PixelMap[] = [];
    for (const frame of this.pendingStillReleases) {
      if (this.stillFrameInUse(frame)) { remain.push(frame); continue; }
      try { frame.release().catch(() => {}); } catch (_e) { }
    }
    this.pendingStillReleases = remain;
    // 还被固定页拿着就先留着，等它交接完/换页后再收。
    if (remain.length > 0) this.scheduleStillSweep(800);
  }

  private referenceSetFeed(value: boolean): void {
    if (!value) this.loadReferenceIntroExtras();
    if (this.fs || this.fsEntering || this.isAnimatingToFS) return;
    if (!this.referenceModeAnimating && this.referenceFeed === value && this.referenceFeedProgress === (value ? 1 : 0)) return;
    this.resetFullscreenVideo();
    this.referenceModeGen++;
    this.referenceInfoHidden = false;
    this.referenceQueuedFeedStep = 0;
    this.referenceVerticalSwipe = false;
    this.referenceFeedDragEndResolve?.();
    this.referenceFeedDragEndResolve = null;
    this.referenceFeedCommentGen++;
    this.referenceFeedCommentAnimating = false;
    this.referenceFeedCommentProgress = 0;
    this.referenceFeedComments = false;
    this.vidShrink = 0;
    this.isLightsOff = false;
    this.referenceModeAnimating = true;
    // 两种状态共用常驻视频和详情面板，以同一进度连续移动，不在切换瞬间卸载。
    this.referenceFeed = true;
      if (value) {
        this.referenceFeedTouchDirection = 1;
        this.referencePreviewVisible = false;
        // ⭐ 备用 XComponent（reference_feed_video_xc）的挂载条件是
        //   `referenceSpareSurfaceMounted || referenceSecondSurfaceActive || !referenceLayout`。
        //   这个标记只在「第一帧渲染」回调里置位，而进连刷时它经常还是 false →
        //   备用 surface 不挂载 → onReferencePreviewXc 从不触发 → referencePreviewSurfaceId 永远为空 →
        //   邻片静帧从头到尾预热不了（实测 retry 日志：surface=EMPTY），切过去只能拿封面。
        //   进连刷就意味着接下来要切页，必须提前把备胎 surface 挂上。
        this.referenceSpareSurfaceMounted = true;
        this.referenceFeedPreview = this.referenceFeedNeighbor(1);
        // ⭐ 进连刷就把邻片详情拉起来：不能等预览 Surface 就绪（它可能一直不创建）。
        //   否则第一次上滑时信息层还没「下一条是谁」，只能等松手提交后才刷新。
        if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
        // ⭐ 预览 Surface 在进连刷那一刻经常还没就绪，requestReferenceFeedPreview 会直接返回，
        //   而首帧回调早已发生在详情页阶段 —— 之后没有任何东西再触发，静帧就一直不预热，
        //   切过去只能拿封面（实测日志：preview target 打了，11 秒内 still 一条都没有）。
        //   重试三次，每次都把被挡的原因打出来，方便定位到底卡在 surface 还是别的分支。
        const retryDelays: number[] = [700, 1600, 3200];
        retryDelays.forEach((delayMs: number, index: number) => {
          setTimeout(() => {
            if (!this.referenceAlive || !this.referenceFeed) return;
            const target = this.referenceFeedPreview;
            if (!target) return;
            if (this.referenceStillFrames.has(target.id) || this.referenceWarmSession?.id === target.id) return;
            logInfo(`[ReferenceFeed] preview warm retry#${index + 1} ${target.id} surface=${this.referencePreviewSurfaceId ? 'ok' : 'EMPTY'} slotPending=${this.referenceFeedSlotPending} waitingFrame=${this.waitingForFirstFrame} preparing=${this.referencePreviewPreparing}`);
            this.requestReferenceFeedPreview(target);
          }, delayMs);
        });
        if (!this.referenceFeedPreview) {
          this.ensureReferenceRecommendQueue().then(() => {
            if (!this.referenceAlive || !this.referenceFeed) return;
            this.referenceFeedPreview = this.referenceFeedNeighbor(1);
            if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
          });
        }
      }
    // ⭐ 用渲染侧 animateTo 而不是 Animator 逐帧回调（与 animateVidShrink 同一结论）：
    //    播放区几何、面板位置都挂在 referenceFeedProgress 上，@State 在 animateTo 中
    //    逐帧插值，节奏由 vsync 决定，不再有 JS 定时器抖出的 judder。
    const origin = this.referenceFeedProgress;
    const target = value ? 1 : 0;
    const gen = this.referenceModeGen;
    const finish = (): void => {
      if (this.referenceModeGen !== gen) return;
      this.referenceFeedProgress = target;
      this.referenceFeed = value;
      this.referencePanelOffset = 0;
      this.referenceModeAnimating = false;
      logInfo(`[ReferenceMotion] mode settled feed=${value} progress=${this.referenceFeedProgress}`);
      if (!value) {
        this.referencePreviewVisible = false;
        this.referenceFeedPreview = null;
        this.referenceFeedNextChrome = null;
        this.referenceFeedPreviewPinned = false;
        this.referencePinnedFrame = undefined;
        this.releaseReferenceFeedPreview();
      }
      this.manageSB(true);
    };
    if (Math.abs(origin - target) < 0.001) {
      finish();
      logInfo(`[ReferenceFeed] active=${value} canvas=${this.cw}x${this.ch} video=${this.referenceMediaWidth()}x${this.referenceMediaHeight()} top=${this.referenceMediaTop()}`);
      return;
    }
    try {
      this.getUIContext().animateTo(
        { duration: 320, curve: Curve.EaseInOut, onFinish: finish },
        () => { this.referenceFeedProgress = target; });
    } catch (_) {
      finish();
    }
    this.manageSB(true);
    logInfo(`[ReferenceFeed] active=${value} canvas=${this.cw}x${this.ch} video=${this.referenceMediaWidth()}x${this.referenceMediaHeight()} top=${this.referenceMediaTop()}`);
  }

  private referenceStopFeedMotion(): void {
    const animator = this.referenceFeedAnimator;
    this.referenceFeedAnimator = null;
    animator?.cancel();
    this.referenceFeedMotionResolve?.();
    this.referenceFeedMotionResolve = null;
  }

  // Keep the model at the actually displayed position so a new drag can interrupt
  // settling without inheriting an offscreen animation target as its origin.
  private referenceAnimateFeedTo(target: number, duration: number): Promise<void> {
    this.referenceStopFeedMotion();
    this.referenceFeedMotionDuration = 0;
    const origin = this.referenceFeedDragY;
    return new Promise<void>((resolve) => {
      const animator = this.getUIContext().createAnimator({ duration: duration, easing: 'linear',
        delay: 0, fill: 'forwards', direction: 'normal', iterations: 1, begin: 0, end: 1 });
      this.referenceFeedAnimator = animator;
      this.referenceFeedMotionResolve = resolve;
      animator.onFrame = (value: number) => {
        if (this.referenceFeedAnimator !== animator) return;
        const eased = 1 - Math.pow(1 - value, 3);
        this.referenceFeedDragY = origin + (target - origin) * eased;
      };
      animator.onFinish = () => {
        if (this.referenceFeedAnimator !== animator) return;
        this.referenceFeedDragY = target;
        this.referenceFeedAnimator = null;
        this.referenceFeedMotionResolve = null;
        resolve();
      };
      animator.play();
    });
  }

  /**
   * 等页面彻底停下：手指还按着就先等抬手，抬手后再等回弹/翻页动画收尾，返回静止时的位移。
   * 翻页动画被新手势取消时会立刻 resolve（停在半路），所以提交前必须再确认一次落点，
   * 否则内容会在手指底下换掉再被回弹拉回——来回切看到的就是一次闪跳。
   */
  private async settleFeedTransition(generation: number): Promise<number> {
    const deadline = Date.now() + 1600;
    while (this.referenceAlive && generation === this.referenceSwitchGeneration &&
      this.referenceVerticalSwipe && Date.now() < deadline) {
      await new Promise<void>((resolve) => {
        let settled = false;
        const finish = () => {
          if (settled) return;
          settled = true;
          if (this.referenceFeedDragEndResolve === finish) this.referenceFeedDragEndResolve = null;
          resolve();
        };
        this.referenceFeedDragEndResolve = finish;
        setTimeout(finish, 500);
      });
    }
    while (this.referenceAlive && generation === this.referenceSwitchGeneration &&
      this.referenceFeedAnimator && Date.now() < deadline) {
      await new Promise<void>((resolve) => setTimeout(resolve, 16));
    }
    return this.referenceFeedDragY;
  }

  private referenceFeedBounceBack(): void {
    // The adjacent card leaves with the rebound. A pinned surface is the current
    // video's still frame and must stay attached until the main player is ready.
    this.referencePreviewVisible = true;
    const generation = this.referenceSwitchGeneration;
    this.referenceAnimateFeedTo(0, 280).then(async () => {
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.referenceVerticalSwipe ||
        this.referenceFeedPreviewPinned || Math.abs(this.referenceFeedDragY) > 1 || this.userPaused_ || this.av?.state !== 'paused') return;
      try {
        const player = this.av;
        player.setVolume(1.0);
        this.audioGain_ = 1;
        this.markAutoPlay('feed-bounce-back');
        await player.play();
        if (generation !== this.referenceSwitchGeneration || this.av !== player) return;
        if (this.avAudio?.state === 'paused' || this.avAudio?.state === 'prepared') await this.avAudio.play();
        this.play = true;
      } catch (error) { logWarn(`连续播放回弹恢复失败: ${error}`); }
    });
  }

  private referenceBeginFeedDrag(x: number, y: number, recognized: boolean): void {
    if (this.fullscreenTransformTouch) return;
    if (!this.referencePortraitFeedActive()) return;
    if ((!this.referenceInfoHidden && y < this.referenceSafeTop()) || this.referenceFeedComments || this.lk || this.la_) return;
    // 翻页动画在跑的时候不要掐断它：手指此时拖不动页面（见 referenceUpdateFeedDrag），
    // 但动画必须继续走到目标页；掐断会让页面停在半路，随后整次翻页被判为中断。
    if (!this.referenceFeedLoading) this.referenceStopFeedMotion();
    this.referenceTouchX = x;
    this.referenceTouchY = y;
    this.referenceFeedTouchStartedAt = Date.now();
    this.referenceVerticalSwipe = recognized;
    this.referenceQueuedFeedStep = 0;
    this.referenceFeedMotionDuration = 0;
    this.referenceFeedDragOriginY = this.referenceFeedDragY;
    this.referenceFeedOriginStale_ = this.referenceFeedLoading;
    this.referenceFeedDragBaseDy_ = 0;
    this.referenceFeedTraceBucket = 0;
    this.referencePreviewVisible = true;
    if (!this.referenceFeedLoading && !recognized) {
      this.referenceFeedTouchDirection = 1;
      this.referenceFeedPreview = this.referenceFeedNeighbor(1);
      if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
    }
    if (recognized) {
      this.referenceCancelFeedTap();
      this.referenceFeedPanOwnsTouch = true;
      this.sliderDragging_ = false;
      this.seekBarTouch_ = false;
      if (!this.sg_) this.sk_ = false;
      this.clearGestureHint_();
      logInfo(`[ReferenceFeed] drag start loading=${this.referenceFeedLoading} pinned=${this.referenceFeedPreviewPinned}`);
    }
    clearTimeout(this.lt_);
  }

  private referenceUpdateFeedDrag(dy: number): void {
    if (this.fullscreenTransformTouch) return;
    if (!this.referencePortraitFeedActive() || !this.referenceVerticalSwipe) return;
    const step = dy < 0 ? 1 : -1;
    if (this.referenceFeedLoading) {
      // ⭐ 正在换页时手指给了反方向：页面上此时只有「当前页 + 一张预览页」，
      //   反向拖动会让预览页留在另一侧，屏幕上直接露出一条底色；
      //   而把预览页换成反向邻片又会在提交前改掉目标。所以这里只记方向，
      //   松开时按 referenceQueuedFeedStep 排队，等这次换页结束再整页翻过去。
      // ⚠️ 这里绝对不能动 referenceFeedTouchDirection：它决定预览页挂在当前页的哪一侧。
      //   换页途中把它改成反向，预览页会瞬间跳到两页之外，当前页又已经被拖出一屏，
      //   中间那一整屏就是黑底——来回切时看到的那一帧全黑就是这么来的。
      return;
    }
    this.referenceFeedTouchDirection = step;
    const neighbor = this.referenceFeedNeighbor(step);
    if (this.referenceFeedPreview?.id !== neighbor?.id) {
      this.referenceFeedPreview = neighbor;
      if (neighbor) this.requestReferenceFeedPreview(neighbor);
    }
    if (this.referenceFeedOriginStale_) {
      // 换页动画已经结束（loading 清零），以当前落点重新锚定；
      // 累计位移也要从这一刻重新算，否则页面会按「手势起点→现在」整段跳一下。
      this.referenceFeedOriginStale_ = false;
      this.referenceFeedDragOriginY = this.referenceFeedDragY;
      this.referenceFeedDragBaseDy_ = dy;
    }
    const localDy = dy - this.referenceFeedDragBaseDy_;
    const maxDrag = Math.max(120, this.ch * 0.98);
    const delta = Math.sign(localDy) * Math.min(Math.abs(localDy), maxDrag);
    this.referenceFeedMotionDuration = 0;
    this.referenceFeedDragY = this.referenceFeedDragOriginY + delta;
    const bucket = Math.floor(Math.abs(delta) / 64);
    if (bucket !== this.referenceFeedTraceBucket) {
      this.referenceFeedTraceBucket = bucket;
      logInfo(`[ReferenceFeed] follow dy=${dy.toFixed(1)} offset=${this.referenceFeedDragY.toFixed(1)} loading=${this.referenceFeedLoading}`);
    }
  }

  private referenceFinishFeedDrag(dy: number, velocity: number): void {
    if (!this.referencePortraitFeedActive() || !this.referenceVerticalSwipe) return;
    this.referenceVerticalSwipe = false;
    this.gm_ = '';
    this.ml_ = true;
    const step = dy < 0 ? 1 : -1;
    if (Math.abs(dy) > Math.max(100, this.ovVideoH() * 0.24) || (Math.abs(dy) > 12 && velocity > 0.70)) {
      if (this.referenceFeedLoading) {
        this.referenceQueuedFeedStep = step;
        logInfo(`[ReferenceFeed] drag release while preparing step=${step} offset=${this.referenceFeedDragY}`);
      } else this.referenceNextVideo(step);
    } else {
      this.referenceQueuedFeedStep = 0;
      this.referenceFeedBounceBack();
    }
    this.referenceFeedDragEndResolve?.();
    this.referenceFeedDragEndResolve = null;
  }

  private referenceCancelFeedDrag(): void {
    if (!this.referenceVerticalSwipe) return;
    this.referenceVerticalSwipe = false;
    this.referenceQueuedFeedStep = 0;
    this.gm_ = '';
    // 换页途中手势被系统取消：不要回弹，让在途动画自己走到目标页。
    if (!this.referenceFeedLoading) this.referenceFeedBounceBack();
    this.referenceFeedDragEndResolve?.();
    this.referenceFeedDragEndResolve = null;
  }

  private referenceHandleFeedTouch(e: TouchEvent): boolean {
    if (!this.referencePortraitFeedActive()) return false;
    if (e.type === TouchType.Down && e.touches.length === 1) {
      this.referenceBeginFeedDrag(e.touches[0].windowX, e.touches[0].windowY, false);
    } else if (e.type === TouchType.Move && e.touches.length === 1) {
      const dx = e.touches[0].windowX - this.referenceTouchX;
      const dy = e.touches[0].windowY - this.referenceTouchY;
      if (!this.referenceVerticalSwipe && Math.abs(dy) > 8 && Math.abs(dy) > Math.abs(dx) * 1.15 &&
        (this.referenceInfoHidden || this.referenceTouchY >= this.referenceSafeTop()) && !this.referenceFeedComments && !this.lk) this.referenceVerticalSwipe = true;
      this.referenceUpdateFeedDrag(dy);
    } else if (e.type === TouchType.Up && this.referenceVerticalSwipe) {
      const touch = e.changedTouches[0];
      const dy = touch ? touch.windowY - this.referenceTouchY : 0;
      this.referenceFinishFeedDrag(dy, Math.abs(dy) / Math.max(1, Date.now() - this.referenceFeedTouchStartedAt));
    } else if (e.type === TouchType.Cancel || e.touches.length > 1) this.referenceCancelFeedDrag();
    return true;
  }

  private referenceIntroScrollOffset(offset: number): number {
    if (this.isLs) return offset;
    // 原始触摸负责移动面板，Scroll 只接收播放区域到达最小后的滚动量。
    if (offset > 0 && this.referencePanelOffset > this.referenceMinimumPanelOffset()) return 0;
    // 内容到顶后的下拉由面板接管，禁用内部回弹以免同时移动。
    if (offset < 0 && this.referencePanelBodyCanDrag && this.detailScroller.currentOffset().yOffset <= 0) return 0;
    return offset;
  }

  private referencePanelTouchIntercept(event: TouchEvent): HitTestMode {
    if (event.type !== TouchType.Down || event.touches.length !== 1) return HitTestMode.Default;
    // 评论与动态页一致，完整交给原生 Refresh/List 处理新触摸和惯性。
    // 不对评论执行原位 scrollTo；这会把新一轮纵向手势也截断。
    if (this.referenceFeedComments || this.at !== 0 || this.referenceIntroScrollState !== ScrollState.Fling) return HitTestMode.Default;
    const scroller = this.detailScroller;
    const offset = scroller.currentOffset();
    if (!Number.isFinite(offset.xOffset) || !Number.isFinite(offset.yOffset)) return HitTestMode.Default;
    // 必须在子列表的命中测试之前终止旧惯性；onTouch 已晚于原生手势初始化，
    // 旧滚动会直接占有新触摸，吞掉同一次纵向拖动和 Swiper 横向切页。
    // 原位无动画 scrollTo 会停止原生动效，不重建列表、不回顶，也不自己翻页。
    scroller.scrollTo({ xOffset: offset.xOffset, yOffset: offset.yOffset, animation: false });
    return HitTestMode.Default;
  }

  private referencePanelBodyTouch(e: TouchEvent): void {
    // 半屏评论同样先上推播放区；触顶下拉仍交给原生 Refresh，不从评论进入连刷。
    if (this.isLs || this.referenceFeedComments) { this.referencePanelBodyCanDrag = false; return; }
    const comments = this.at === 1;
    const scroller = comments ? this.commentScroller : this.detailScroller;
    if (e.type === TouchType.Down && e.touches.length > 0) {
      this.referencePanelBodyStartY = e.touches[0].windowY;
      this.referencePanelBodyLastY = this.referencePanelBodyStartY;
      this.referencePanelBodyStartX = e.touches[0].windowX;
      this.referencePanelBodyStartOffset = this.referencePanelOffset;
      this.referencePanelDragAnchorY = this.referencePanelBodyStartY;
      this.referencePanelDragAnchorOffset = this.referencePanelBodyStartOffset;
      this.referencePanelBodyDirection = 0;
      const atTop = scroller.currentOffset().yOffset <= 0;
      // 即使内容已滚动，上滑也先将播放区收至最小。
      this.referencePanelBodyCanDrag = (!comments && atTop) ||
        this.referencePanelOffset > this.referenceMinimumPanelOffset();
      return;
    }
    const touch = e.type === TouchType.Up || e.type === TouchType.Cancel
      ? (e.changedTouches.length > 0 ? e.changedTouches[0] : undefined)
      : (e.touches.length > 0 ? e.touches[0] : undefined);
    if (!touch) return;
    const movingDown = touch.windowY > this.referencePanelBodyLastY;
    this.referencePanelBodyLastY = touch.windowY;
    let dy = touch.windowY - this.referencePanelBodyStartY;
    const dx = touch.windowX - this.referencePanelBodyStartX;
    if (e.type === TouchType.Move && this.referencePanelBodyDirection === 0) {
      // Decide once, before changing panel geometry. Previously a 10vp vertical
      // drift moved the video/panel before the 18vp horizontal check restored it.
      // Ambiguous diagonal input stays with the native scroll/pager recognizers.
      if (Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy) * 1.15) {
        this.referencePanelBodyDirection = 1;
      } else if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx) * 1.15) {
        this.referencePanelBodyDirection = 2;
        // ⭐ 锚点定在死区边界：本帧 dy 已 >10，若直接写 startOffset+dy 会一次跳 10+vp
        //    （起步跳动，与起步位置无关）。吃掉 slop 后本帧只走 dy-10，
        //    后续每帧沿用同一映射，起步与来回移动都连续。
        const slop = dy > 0 ? 10 : -10;
        this.referencePanelDragAnchorY = this.referencePanelBodyStartY + slop;
        this.referencePanelDragAnchorOffset = this.referencePanelBodyStartOffset;
      }
    }
    // 横向由原生 Swiper 连续跟手；不能在 Move 阶段直接翻转 at 卸载旧页。
    if (this.referencePanelBodyDirection !== 2) {
      if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.referencePanelBodyDirection = 0;
        this.referencePanelBodyCanDrag = false;
      }
      return;
    }
    if (e.type === TouchType.Move) {
      const contentOffset = scroller.currentOffset().yOffset;
      if ((comments || contentOffset > 0) && this.referencePanelOffset <= this.referenceMinimumPanelOffset()) {
        // 视频已收至最小时先让列表消费手势，包括同一次触摸中的反向滚动。
        this.referencePanelBodyCanDrag = false;
      } else if (!comments && !this.referencePanelBodyCanDrag && contentOffset <= 0 && movingDown) {
        // 列表在本次下拉中触顶后立即接管；从交接点累计位移，避免跳用已被列表消费的距离。
        this.referencePanelBodyCanDrag = true;
        this.referencePanelBodyStartY = touch.windowY;
        this.referencePanelBodyStartOffset = this.referencePanelOffset;
        // 交接点同步锚点，避免接管那一帧把之前累计的 dy 又补写一次。
        this.referencePanelDragAnchorY = touch.windowY;
        this.referencePanelDragAnchorOffset = this.referencePanelOffset;
        dy = 0;
      }
    }
    if (!this.referencePanelBodyCanDrag) return;
    // ⭐ 同一处 slop 的两端：起步（死区内不写、确认帧一次性补 dy）与
    //    按住来回移动（|dy| 落回 10 以内不写、穿过死区后补写）都会跳。
    //    现在每帧都按锚点绝对映射写入，方向仍由 referencePanelBodyDirection 锁一次。
    if (e.type === TouchType.Move) {
      const proposed = this.referencePanelDragAnchorOffset + (touch.windowY - this.referencePanelDragAnchorY);
      // 评论只从当前尺寸向上收缩，反向可跟手回到起点，触顶下拉保留刷新。
      this.referencePanelOffset = this.referencePanelDragOffset(comments
        ? Math.min(this.referencePanelDragAnchorOffset, proposed) : proposed);
    } else if (e.type === TouchType.Up) {
      if (!comments && dy > 90 && this.referencePanelBodyStartOffset >= -20) this.referenceSetFeed(true);
      else if (this.referencePanelOffset > 0) {
        // 与把手 onActionEnd 同口径：下拉回起点，上推保持无级。
        this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => { this.referencePanelOffset = 0; });
      }
      this.referencePanelBodyCanDrag = false;
    } else if (e.type === TouchType.Cancel) {
      this.referencePanelBodyCanDrag = false;
      this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => { this.referencePanelOffset = this.referencePanelBodyStartOffset; });
    }
  }

  private referenceFeedNeighbor(step: number): RecommendItem | null {
    const queue = this.referenceFeedQueue;
    const current = queue.findIndex((item: RecommendItem) => item.id === this.vi.bvid);
    if (current < 0) return null;
    const index = current + step;
    return index >= 0 && index < queue.length ? queue[index] : null;
  }

  private async ensureReferenceRecommendQueue(): Promise<RecommendItem[]> {
    if (!this.vi.bvid || !this.referenceAlive) return this.referenceFeedQueue;
    // 首页 App 卡片可能用 aid 入场；先解析规范 bvid，防止同一稿件重复种入队列。
    const detail = this.vi.bvid.startsWith('BV') ? null : await getVideoDetail(this.vi.bvid);
    if (!this.referenceAlive) return this.referenceFeedQueue;
    const bvid = detail?.bvid || this.vi.bvid;
    if (!bvid.startsWith('BV')) return this.referenceFeedQueue;
    if (!this.referenceFeedQueue.some((item: RecommendItem) => item.id === bvid)) {
      const current = new RecommendItem();
      current.id = bvid; current.cid = detail?.cid || this.vi.cid;
      current.aid = detail?.aid || this.vd?.aid || 0;
      current.title = this.vi.title; current.coverUrl = this.vi.cover;
      this.referenceFeedQueue = [current, ...this.referenceFeedQueue];
      ContinuousRecommendationState.markVisited(bvid, current.aid);
    }
    if (this.referenceFeedQueue.length < 2) await this.referenceAppendRecommendations();
    this.referencePrefetchPlaylistUrls();
    return this.referenceFeedQueue;
  }

  private async referenceAppendRecommendations(): Promise<void> {
    if (this.referenceFeedRecommendJob) return this.referenceFeedRecommendJob;
    const job = this.referenceFetchRecommendations();
    this.referenceFeedRecommendJob = job;
    try { await job; }
    finally { if (this.referenceFeedRecommendJob === job) this.referenceFeedRecommendJob = null; }
  }

  private async referenceFetchRecommendations(): Promise<void> {
    const account = ContinuousRecommendationState.account();
    const history = ContinuousRecommendationState.syncRecentHistory(account);
    const seen = new Set<string>();
    for (const item of this.referenceFeedQueue) {
      seen.add(item.id);
      if (item.aid > 0) seen.add(item.aid.toString());
    }
    const added: RecommendItem[] = [];
    // Story 每页较少；最多连续取三页，空页也推进，避免反复拿同一页。
    for (let page = 0; page < 3 && added.length < 4; page++) {
      const index = ContinuousRecommendationState.reservePage(account);
      const batches = await Promise.all([getStoryRecommendVideos(index, this.referenceFeedSessionId), history]);
      const recommended = batches[0];
      if (!this.referenceAlive || account !== ContinuousRecommendationState.account()) return;
      const excluded = ContinuousRecommendationState.excluded(account);
      for (const item of recommended) {
        if (ContinuousRecommendationState.isExcluded(item, seen) ||
          ContinuousRecommendationState.isExcluded(item, excluded) ||
          VideoCardFeedback.isDismissed(item.id, item.ownerMid) ||
          (item.aid > 0 && VideoCardFeedback.isDismissed(item.aid.toString(), item.ownerMid))) continue;
        seen.add(item.id);
        if (item.aid > 0) seen.add(item.aid.toString());
        added.push(item);
      }
    }
    this.referenceFeedQueue = [...this.referenceFeedQueue, ...added];
    this.referencePrefetchPlaylistUrls();
    logInfo(`[ReferenceFeed] independent recommendations added=${added.length} total=${this.referenceFeedQueue.length}`);
  }

  private async referenceNextVideo(step: number): Promise<void> {
    if (!this.referencePortraitFeedActive()) return;
    if (this.referenceFeedLoading) {
      this.referenceQueuedFeedStep = step;
      return;
    }
    if (this.isPgc_) {
      this.referenceFeedBounceBack();
      return;
    }
    this.referenceFeedLoading = true;
    const generation = ++this.referenceSwitchGeneration;
    this.referenceFeedMainRetry_ = 0;
    this.qualityDeadline_?.cancel();
    this.qualitySession_?.release().catch(() => {});
    this.referenceFeedMainCancel?.();
    const switchStarted = Date.now();
    let committed = false;
    // 翻页途中被新手势按住/拖回：这次翻页没有真正完成，不能提交内容。
    let interrupted = false;
    try {
      let queue = await this.ensureReferenceRecommendQueue();
      let current = queue.findIndex((item: RecommendItem) => item.id === this.vi.bvid);
      if (step > 0 && current + step >= queue.length) {
        await this.referenceAppendRecommendations();
        queue = this.referenceFeedQueue;
      }
      const nextIndex = current + step;
      if (nextIndex < 0 || nextIndex >= queue.length) {
        this.referenceFeedBounceBack();
        this.getUIContext().getPromptAction().showToast({ message: step < 0 ? '已经是第一条视频' : '暂时没有更多视频，请稍后重试' });
        return;
      }
      const next = queue[nextIndex];
      this.referenceFeedTouchDirection = step;
      this.referenceFeedPreview = next;
      logInfo(`[ReferenceFeed] switch ${generation} begin ${next.id}`);
      // Resolve identity before committing target chrome; media readiness is independent.
      // 优先用已经到手的详情（预览槽位 → 详情缓存 → 现拉），提交这一刻不再空等网络。
      let detail: VideoDetail | null = this.referencePreviewRequestedId === next.id
        ? this.referencePreviewDetailFor(next) : null;
      if (!detail) detail = this.referenceStillDetails.get(next.id) ?? null;
      if (!detail) detail = await this.requestReferenceDetail(next.id);
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      const nextCid = next.cid || detail?.cid || detail?.pages?.[0]?.cid || 0;
      if (!detail || nextCid <= 0) throw new Error('无法获取下一条视频信息');
      // let 变量在后续闭包（.then 回调）里不会被收窄，这里固化成不可变引用。
      const targetDetail: VideoDetail = detail;
      if (this.referencePreviewRequestedId !== next.id) this.requestReferenceFeedPreview(next);
      // Page motion must not wait for a decoder: use the target cover on a warm miss.
      const previewMatches = this.referencePreviewRequestedId === next.id;
      const targetRatio = this.referenceStillRatios.get(next.id) ||
        this.referenceFeedAspect(detail, nextCid, next.videoWidth > 0 && next.videoHeight > 0 ? next.videoWidth / next.videoHeight : 1);
      // 滑入的那一页（预览页）信息层只认「已解析的详情」：
      //   预热 detail 可能还没落地（referencePreviewDetail 为空 / 是别的稿件），
      //   这时信息层会退回到推荐队列里的兜底字段——story 队列的 title 常常是话题串、
      //   owner 也可能是另一条视频的，表现就是翻页瞬间标题跳到别的视频再跳回来。
      //   这里在动画开始前把刚解析到的 detail 发布出去，并补齐画幅。
      if (this.referencePreviewDetail?.bvid !== detail.bvid) {
        this.referencePreviewDetail = detail;
        logInfo(`[ReferenceFeed] preview detail publish ${detail.bvid} title=${detail.title}`);
      }
      if (!previewMatches || !this.referenceStillRatios.get(next.id)) {
        this.referencePreviewAspectRatio = targetRatio;
      }
      const targetCover = next.coverUrl || detail.pic;
      // Keep the incoming card and committed still at identical bounds, including cold misses.
      const presentationRatio = this.referencePreviewAspectRatio;
      if (this.referenceVerticalSwipe) {
        await new Promise<void>((resolve) => { this.referenceFeedDragEndResolve = resolve; });
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      }
      this.referencePreviewVisible = true;
      const pageStep = Math.max(this.ch, 120);
      await this.referenceAnimateFeedTo(-step * pageStep, 360);
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      if (!this.referencePortraitFeedActive()) return;
      // ⭐ 动画被新手势打断时 referenceAnimateFeedTo 会立刻 resolve（停在半路）。
      //   此时直接提交，内容会在手指底下换掉，随后又被回弹拉回原位 —— 来回切看起来
      //   就是一次莫名的闪跳。等手势与回弹都停下，只有落在目标页才提交。
      const restingOffset = await this.settleFeedTransition(generation);
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      if (!this.referencePortraitFeedActive()) return;
      // ⭐ 还没提交就被反向手势抵掉（上滑途中又下滑）：用户其实想留在原来那条。
      //   以前这种情况会把新片提交上去，紧接着排队的那次切换再翻回来 —— 屏幕上连着闪两下，
      //   中间那条视频还会被拉起解码再丢进回收，正是「来回切」最容易出问题的地方。
      //   净位移为零就直接取消本次翻页，原视频一直在后面播，不用重新起播。
      if (this.referenceQueuedFeedStep === -step) {
        this.referenceQueuedFeedStep = 0;
        logInfo(`[ReferenceFeed] switch ${generation} cancel by reverse offset=${restingOffset.toFixed(0)}`);
        this.referenceFeedTouchDirection = 1;
        this.referenceFeedPreview = this.referenceFeedNeighbor(1);
        if (this.referenceFeedPreview && this.referencePreviewRequestedId !== this.referenceFeedPreview.id) {
          this.requestReferenceFeedPreview(this.referenceFeedPreview);
        }
        this.referenceFeedBounceBack();
        return;
      }
      if (Math.abs(restingOffset + step * pageStep) > 1) {
        interrupted = true;
        const queuedStep = this.referenceQueuedFeedStep;
        if (queuedStep !== 0) {
          // 抬手时还排着一次切换（多半是反向的手势）：别先弹回原位再翻，
          // 让排队那次从当前落点接着走，页面只动一次。
          logInfo(`[ReferenceFeed] switch ${generation} hand over step=${queuedStep} offset=${restingOffset.toFixed(0)}`);
        } else {
          logInfo(`[ReferenceFeed] switch ${generation} abort offset=${restingOffset.toFixed(0)} target=${(-step * pageStep).toFixed(0)}`);
          await this.referenceAnimateFeedTo(0, 240);
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        }
        return;
      }
      this.saveWatchHistory(true);   // 连刷换片：离开这条时把进度锚定住，不能被节流吞掉
      this.reportWatchBehavior();
      const preserveDrag = this.referenceVerticalSwipe || this.referenceQueuedFeedStep !== 0;
      const destinationOffset = preserveDrag ? this.referenceFeedDragY + step * Math.max(this.ch, 120) : 0;
      if (preserveDrag) this.referenceFeedDragOriginY += step * Math.max(this.ch, 120);
      this.clearGestureHint_();
      this.resetFullscreenVideo();
      this.referencePlaybackCompleted = false;
      this.vi = { bvid: detail.bvid || next.id, cid: nextCid, title: detail.title || next.title,
        cover: detail.pic || next.coverUrl, ownerName: detail.owner.name, ownerFace: detail.owner.face,
        duration: detail.duration, pubdate: detail.pubdate, view: detail.stat.view };
      // Publish identity and detail before exposing the current page's chrome.
      // FeedAvatarImage gives each identity its own synchronously loaded Image node.
      this.vd = detail;
      this.vdBvid_ = detail.bvid || '';
      logInfo(`[ReferenceFeed] chrome commit ${this.vi.bvid} title=${this.vi.title} still=${presentationRatio} target=${targetRatio} previewMatch=${previewMatches}`);
      ContinuousRecommendationState.markVisited(this.vi.bvid, detail.aid);
      this.referenceSubtitleEnabled = false;
      this.referenceSubtitleCues = [];
      this.referenceSubtitleText = '';
      // ⭐ 视频画幅用「解码器实测比例」（referenceDecodeRatios），不是静帧位图比例：
      //   位图比例可能来自还没切画幅的 surface（1.7766），拿它当 ar 会把竖屏视频整屏拉伸。
      //   实测没有时才退回 targetRatio / 接口 dimension。
      const committedRatio = this.referenceDecodeRatios.get(next.id) || targetRatio;
      logInfo(`[ReferenceFeed] ratio commit ${next.id} decode=${(this.referenceDecodeRatios.get(next.id) ?? -1).toFixed(4)} target=${targetRatio.toFixed(4)} pick=${committedRatio.toFixed(4)} preview=${presentationRatio.toFixed(4)}`);
      if (committedRatio > 0) {
        this.ar = committedRatio;
        this.vh = 1000;
        this.vw = this.ar * this.vh;
        this.updateIsLandscapeVertical();
        this.updateLSVSize();
        this.updateVideoSize();
      }
      // ⭐ 几何归零（让当前页 chrome 露出）挪到整个提交块的最后一步：
      //   vi/vd/画幅/播放状态全部先落地，避免分批刷新时露出半套旧信息。
      // ⭐ 静帧到提交时再取：翻页动画有 360ms，期间缓存表可能换图并把旧图排队释放。
      //    提前抓到局部变量的话，提交时这张位图可能已经被回收（硬切静默降级或直接抛异常）。
      const targetFrame = this.referenceStillFrames.get(next.id) ||
        (previewMatches ? this.referencePreviewFrame : undefined);
      this.referencePinnedFrame = targetFrame;
      this.referencePinnedCover = targetCover;
      // 保持原设计：静帧跟「预览页当前比例」走（previewMatches 为真时就是滑入页那一套），
      // 否则退回 targetRatio。不要强行拉成和 ar 一致 —— 那会在硬切瞬间把静帧整体缩一次。
      this.referencePinnedAspectRatio = presentationRatio;
      this.referencePinnedOpacity = 1;
      this.referenceFeedSurfaceReady = false;
      this.referenceFeedPreviewPinned = true;
      // vi / vd 已在几何归零之前提交（见 chrome commit 上方）。
      this.aidFromParams_ = detail.aid;
      this.ct = 0;
      this.dur = detail.duration || next.duration;
      this.initialProgress_ = 0;
      this.lastHeartbeatTime = 0;
      this.currentPageIndex = 0;
      // Muted decoder preparation is internal; the destination is set to autoplay.
      this.play = true;
      this.userPaused_ = false;
      this.ld = false;
      this.err = '';
      this.cv = false;
      this.at = 0;
      this.referenceTabProgress = 0;
      this.referenceFeedComments = false;
      this.referencePanelOffset = 0;
      this.isLiked = false;
      this.isDisliked = false;
      this.isCoined = false;
      this.isFavorited = false;
      this.isFollowed = false;
      this.likeCount = detail.stat.like;
      this.coinCount = detail.stat.coin;
      this.favoriteCount = detail.stat.favorite;
      this.commentCursor = 0;
      this.commentDataSource.clear();
      this.selfDanmakuList = [];
      this.isLoadingMore = false;
      this.ldc = false;
      this.relatedVideos = [];
      this.pendingCommentAid = 0;
      const warm = this.referenceWarmSession?.id === next.id
        ? this.referenceWarmSession : null;
      warm?.reserve();
      this.referenceFeedSlotPending = true;
      const retiring = this.referenceWarmSession;
      this.referenceWarmSession = null;
      this.referencePreviewGeneration++;
      this.referencePreviewPreparing = false;
      if (retiring && retiring !== warm) {
        this.referencePreviewReleaseJob = Promise.all([this.referencePreviewReleaseJob, retiring.release()]).then(() => {});
      }
      const neighborStep = this.referenceQueuedFeedStep || (this.referenceVerticalSwipe ? this.referenceFeedTouchDirection : 1);
      this.referenceFeedTouchDirection = neighborStep;
      this.referenceFeedPreview = this.referenceFeedNeighbor(neighborStep);
      logInfo(`[ReferenceFeed] next preview ${this.referenceFeedPreview?.id} step=${neighborStep} current=${this.vi.bvid}`);
      this.referencePreviewVisible = true;
      if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
      this.loadD(detail);
      this.loadC(detail.aid);
      const previousMain = this.referenceFeedMainJob;
      this.referenceFeedMainJob = previousMain.catch(() => {}).then(() => this.referencePrepareFeedMain(targetDetail, generation, warm));
      // ⭐ 所有信息层 / 画幅 / 播放状态已落地，最后一步才归零露出当前页 chrome。
      this.referenceFeedMotionDuration = 0;
      this.referenceFeedDragY = destinationOffset;
      committed = true;
      logInfo(`[ReferenceFeed] switch ${generation} visual committed ${this.vi.bvid} ${Date.now() - switchStarted}ms`);
    } catch (error) {
      logError('连续播放切换失败', error);
      if (this.referenceAlive) {
        if (this.referenceFeedPreviewPinned && this.referencePinnedFrame) {
          this.referenceFeedMainFrameResolve = null;
          this.getUIContext().getPromptAction().showToast({ message: '正在继续准备视频' });
          return;
        }
        this.referenceAnimateFeedTo(0, 360);
        this.referenceFeedPreviewPinned = false;
        this.referencePinnedFrame = undefined;
        this.referencePreviewVisible = false;
        this.referenceFeedTouchDirection = 1;
        this.referenceFeedPreview = this.referenceFeedNeighbor(1);
        if (this.referenceFeedPreview && this.referencePreviewRequestedId !== this.referenceFeedPreview.id) {
          this.requestReferenceFeedPreview(this.referenceFeedPreview);
        }
        this.getUIContext().getPromptAction().showToast({ message: '切换失败，请重试' });
      }
    } finally {
      if (generation === this.referenceSwitchGeneration) {
        this.referenceFeedLoading = false;
        const queuedStep = this.referenceQueuedFeedStep;
        this.referenceQueuedFeedStep = 0;
        // 被打断但用户已经滑到了另一页（hand over）时也要把那次切换接上，
        // 否则页面停在新的一页上却永远不提交。
        if ((committed || interrupted) && queuedStep !== 0 && this.referenceAlive && this.referencePortraitFeedActive() && !this.referenceFeedComments) {
          this.referenceNextVideo(queuedStep);
        }
      }
    }
  }

  private async referencePrepareFeedMain(detail: VideoDetail, generation: number, warm: FeedPlaybackSession | null = null): Promise<void> {
    const started = Date.now();
    if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) {
      await warm?.release();
      return;
    }
    let cancelWait: (() => void) | null = null;
    try {
      while (this.initPInProgress_ && this.referenceAlive && generation === this.referenceSwitchGeneration) {
        await new Promise<void>((resolve) => setTimeout(resolve, 16));
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      this.initialProgress_ = 0;
      this.referenceFeedPreparingMain = true;
      let frameArrived = false;
      let preparedArrived = false;
      let resolveFrame: (() => void) | null = null;
      let resolvePrepared: (() => void) | null = null;
      const frame = new Promise<void>((resolve) => { resolveFrame = resolve; });
      const prepared = new Promise<void>((resolve) => { resolvePrepared = resolve; });
      this.referenceFeedMainFrameResolve = () => { frameArrived = true; resolveFrame?.(); };
      this.referenceFeedMainPreparedResolve = () => { preparedArrived = true; resolvePrepared?.(); };
      cancelWait = () => {
        resolveFrame?.();
        resolvePrepared?.();
        this.referenceFeedMainPresentResolve?.();
        this.referenceFeedDragEndResolve?.();
        // A new swipe must also interrupt a slow, reserved preheat preparation.
        warm?.release().catch(() => {});
      };
      this.referenceFeedMainCancel = cancelWait;
      // 连刷要的是「两个播放器」：下一条已经在另一个 Surface 上解码、暂停好，
      // 当前这条一直播到交接完成才释放。先 release 再等预热，等于亲手把唯一在播的
      // 实例杀掉，屏幕上只剩黑底转圈——这就是上一版的回归。
      if (warm && !warm.ready) {
        logInfo(`[ReferenceFeed] main ${generation} waiting for existing preheat ${detail.bvid}`);
        await warm.prepare(media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT, AppStorage.get<string>('biliCookie') || '');
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) {
        await warm?.release();
        return;
      }
      const handles = warm?.take() || null;
      // 交接棒已在新播放器手里，旧实例这时才可以下线（它占用的 Surface 留给下一次预热）。
      await this.release();
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) {
        // release() 期间被下一次切换取代：take() 之后会话不再负责释放，
        // 这里必须自己收，否则每打断一次就漏掉一整个播放器实例。
        await this.disposeFeedHandles(handles);
        return;
      }
      if (handles && warm) {
        // A slow decoder may discover dimensions after the visual page committed.
        // Its native geometry can settle behind the independently pinned poster.
        // ⚠ 静帧还盖在上面时改 ar 会让整张静帧立刻缩放（水印位置跳一下）。
        //    解码尺寸与已提交画幅只差一点点时（编码补边、对齐取整）保持画幅不变；
        //    只有真正换了方向/画幅（>2%）才更新，那属于必须纠正的错误几何。
        const adopted = warm.aspectRatio;
        if (Number.isFinite(adopted) && adopted > 0) {
          const delta = this.ar > 0 ? Math.abs(adopted / this.ar - 1) : 1;
          if (delta > 0.02) {
            logInfo(`[ReferenceFeed] aspect adopt ${this.ar} -> ${adopted} delta=${delta.toFixed(4)}`);
            this.ar = adopted;
            this.vh = 1000;
            this.vw = this.ar * this.vh;
            this.updateIsLandscapeVertical();
            this.updateLSVSize();
            this.updateVideoSize();
          } else if (delta > 0.0008) {
            logInfo(`[ReferenceFeed] aspect keep ${this.ar} decoder=${adopted} delta=${delta.toFixed(4)}`);
          }
        }
        this.av = handles.video;
        this.avAudio = handles.audioPlayer;
        this.dashBridge_ = handles.bridge;
        this.isDashStream_ = handles.bridge !== null;
        // 预热 surface 上停着的就是静帧那一帧 → 允许无缝硬切。
        this.referenceFeedWarmAdopted_ = true;
        const oldSurface = this.sId;
        this.sId = warm.surfaceId;
        this.referenceSecondSurfaceActive = !this.referenceSecondSurfaceActive;
        this.referencePreviewSurfaceId = oldSurface;
        this.referenceFeedPreparingMain = false;
        // 同样只记当前条的实际画质；连刷下一条仍按 preferredQn 取流。
        this.qn = warm.source.actualQn || this.qn;
        this.applyAcceptQuality(warm.source);
        this.ql = this.getQlLabel(this.qn);
        this.dur = detail.duration || this.vi.duration || Math.ceil((handles.video.duration || 0) / 1000);
        this.waitingForFirstFrame = false;
        this.setupL();
        if (this.avAudio) this.setupAudioL();
        handles.video.videoScaleType = this.getVideoScaleType();
        await handles.video.setSpeed(this.rateToSpeedIdx(this.rt));
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        LiveViewHelper.setControlHandlers({
          play: () => { this.mediaSessionPlay(); },
          pause: () => { if (this.play) this.togglePP(); },
          seek: (time: number) => { this.seek(time / 1000, false); }
        });
        LiveViewHelper.create(this.getUIContext().getHostContext() as common.Context,
          this.vi.title, this.vi.cover, this.vi.bvid, this.dur, detail.owner.name).catch(() => {});
        this.prefetchVideoShot_();
        logInfo(`[ReferenceFeed] warm adopted ${detail.bvid} surface=${this.sId} ${Date.now() - started}ms`);
      } else {
        // A cached still can survive a decoder failure; retain the cold path as fallback.
        this.referenceFeedWarmAdopted_ = false;
        await Promise.all([this.initP(), Promise.race([
          Promise.all([frame, prepared]), new Promise<void>((resolve) => setTimeout(resolve, 6000))
        ])]);
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        if (!frameArrived || !preparedArrived) throw new Error('主播放器准备超时，保留目标静帧');
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
      // The outgoing decoder has been released and the slot role swap is complete.
      this.referenceFeedSlotPending = false;
      if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
      const player = this.av;
      if (!player) return;
      if (player.state === 'playing') {
        await player.pause();
        const pausedDeadline = Date.now() + 1500;
        while (player.state === 'playing' && Date.now() < pausedDeadline) {
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
          await new Promise<void>((resolve) => setTimeout(resolve, 16));
        }
      }
      logInfo(`[ReferenceFeed] main ${generation} behind still state=${player.state} ${Date.now() - started}ms`);
      // A held finger or rebound keeps its still. New visual switches cancel this
      // wait and proceed independently; only the latest destination may play.
      let stillCut = false;
      while (this.referenceAlive && generation === this.referenceSwitchGeneration) {
        while (!this.playerPageVisible || this.userPaused_ || this.referenceVerticalSwipe || this.referenceFeedAnimator || this.referenceFeedLoading || Math.abs(this.referenceFeedDragY) > 1) {
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
          await new Promise<void>((resolve) => setTimeout(resolve, 16));
        }
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        // ⭐ 先让暂停帧归位、撤掉静帧，再开始播。静帧就是这个 surface 抓的同一帧，
        //    硬切不可见；原顺序先 play、等时钟前进 100~300ms 才露 surface，用户会看到
        //    「静帧(t0) → 已播出几百毫秒的画面」，这正是连刷起播"跳一下"的来源。
        if (!stillCut) stillCut = await this.revealFeedPinnedStill(generation);
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        if (!this.playerPageVisible || this.userPaused_ || this.referenceVerticalSwipe || this.referenceFeedAnimator || Math.abs(this.referenceFeedDragY) > 1) {
          if (stillCut) {
            this.referencePinnedOpacity = 1;
            this.referenceFeedSurfaceReady = false;
            stillCut = false;
          }
          continue;
        }
        this.referenceFeedMainPresentAfter = player.currentTime;
        let advancing = false;
        const presented = new Promise<void>((resolve) => {
          this.referenceFeedMainPresentResolve = () => { advancing = true; resolve(); };
        });
        // pause() can complete before its stateChange notification. Do not skip
        // resume by reading the old 'playing' state and then end up paused forever.
        if (handles && this.avAudio) {
          const audioPlayer = this.avAudio;
          const audioSeek = new Promise<void>((resolve) => { this.audioSeekResolve_ = resolve; });
          audioPlayer.seek(player.currentTime, media.SeekMode.SEEK_CLOSEST);
          await Promise.race([audioSeek, new Promise<void>((resolve) => setTimeout(resolve, 500))]);
          this.audioSeekResolve_ = null;
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== player) return;
          await audioPlayer.setSpeed(this.rateToSpeedIdx(this.rt));
          await audioPlayer.play();
        }
        // 交接拿到的实例若已经是 completed（旧实例没换掉 / 0 时长源），
        // play() 会把它从头拉起来：这条必须是错误，交给上层重试或保留静帧。
        if (player.state === 'completed') throw new Error('主播放器已播完，拒绝从头起播');
        if (player.state !== 'playing') {
          this.markAutoPlay('feed-handover');
          await player.play();
        }
        logInfo(`[ReferenceFeed] main ${generation} resume state=${player.state} after=${this.referenceFeedMainPresentAfter}${stillCut ? ' still=cut' : ''}`);
        await Promise.race([presented, new Promise<void>((resolve) => setTimeout(resolve, 15000))]);
        if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
        if (!advancing) {
          if (this.err) throw new Error(this.err);
          logWarn(`[ReferenceFeed] main ${generation} still buffering; keep destination poster`);
          // 硬切之后时钟没走：可能是 surface 还没真正出帧，恢复静帧继续等。
          if (stillCut) {
            this.referencePinnedOpacity = 1;
            this.referenceFeedSurfaceReady = false;
            stillCut = false;
          }
          continue;
        }
        if (!stillCut) {
          // 没有可用静帧（只有封面）时保留原来的保护：确认时钟确实前进后才露 surface。
          this.referenceFeedSurfaceReady = true;
          await new Promise<void>((resolve) => setTimeout(resolve, 64));
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
          if (!this.playerPageVisible || this.userPaused_ || this.referenceVerticalSwipe || this.referenceFeedAnimator || Math.abs(this.referenceFeedDragY) > 1) {
            this.referenceFeedSurfaceReady = false;
            if (player.state === 'playing') await player.pause();
            continue;
          }
        }
        if (this.referencePinnedOpacity > 0) {
          this.getUIContext().animateTo({ duration: 180, curve: Curve.Linear }, () => { this.referencePinnedOpacity = 0; });
          await new Promise<void>((resolve) => setTimeout(resolve, 180));
          if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
          if (!this.playerPageVisible || this.userPaused_ || this.referenceVerticalSwipe || this.referenceFeedAnimator || Math.abs(this.referenceFeedDragY) > 1) {
            this.referencePinnedOpacity = 1;
            this.referenceFeedSurfaceReady = false;
            stillCut = false;
            if (player.state === 'playing') await player.pause();
            continue;
          }
        }
        break;
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== player) return;
      this.referenceFeedPreviewPinned = false;
      this.referencePinnedFrame = undefined;
      this.referencePinnedCover = '';
      player.setVolume(this.mute ? 0 : 1.0);
      if (this.avAudio) {
        this.avAudio.setVolume(this.mute ? 0 : 1.0);
        if (this.avAudio.state === 'prepared' || this.avAudio.state === 'paused') await this.avAudio.play();
        else if (this.avAudio.state !== 'playing') this.referenceFeedAudioStartPending = true;
      }
      if (!this.referenceAlive || generation !== this.referenceSwitchGeneration || this.av !== player) return;
      this.play = true;
      this.pendingCommentAid = detail.aid;
      this.startVideoSpeedSync();
      logInfo(`[ReferenceFeed] main ${generation} playing ${this.vi.bvid} ${Date.now() - started}ms`);
    } catch (error) {
      if (this.referenceAlive && generation === this.referenceSwitchGeneration) {
        logError('连续播放主播放器交接失败', error);
        // 冷路径超时后没有任何东西会再来触发这一条，不重试就是永久转圈。
        // 只重试一次：预热若已就绪就优先接管，否则重建一个实例。
        if (this.referenceFeedMainRetry_ < 1) {
          this.referenceFeedMainRetry_++;
          setTimeout(() => {
            if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return;
            const session = this.referenceWarmSession?.id === detail.bvid ? this.referenceWarmSession : null;
            this.referencePrepareFeedMain(detail, generation, session).catch(() => {});
          }, 500);
        } else {
          // 重试也用尽：宁可接受一次跳变，也不能把画面永久冻在静帧上。
          logWarn(`[ReferenceFeed] main ${generation} give up still, play directly`);
          this.referenceFeedFallbackPlay();
        }
      }
    } finally {
      await warm?.release();
      if (this.referenceFeedMainCancel === cancelWait) this.referenceFeedMainCancel = null;
      if (generation === this.referenceSwitchGeneration) {
        this.referenceFeedSlotPending = false;
        this.referenceFeedPreparingMain = false;
        this.referenceFeedMainFrameResolve = null;
        this.referenceFeedMainPreparedResolve = null;
        this.referenceFeedMainPresentResolve = null;
        // 主路径（12759 附近）清 slotPending 时会立刻给下一条发起预览请求，这里之前漏了。
        // 一旦走进异常/超时分支，下一条的静帧预热就再没人启动 → 切过去只有封面，
        // 表现就是「先出封面（还被 Contain 成小条）→ 再出画面」。补一次，幂等。
        if (this.referenceFeedPreview) this.requestReferenceFeedPreview(this.referenceFeedPreview);
      }
    }
  }

  /** take() 之后会话不再负责释放；交接被取代时由页面自己回收这三个句柄。 */
  private async disposeFeedHandles(handles: FeedPlaybackHandles | null): Promise<void> {
    if (!handles) return;
    const pending: Promise<void>[] = [handles.video.release().catch(() => {})];
    if (handles.audioPlayer) pending.push(handles.audioPlayer.release().catch(() => {}));
    if (handles.bridge) pending.push(handles.bridge.stopIfRunning().catch(() => {}));
    await Promise.all(pending);
  }

  /** 交接连续失败时的兜底：撤掉静帧直接播。宁可看到一次跳变，也不能永久停住。 */
  private referenceFeedFallbackPlay(): void {
    this.referencePinnedOpacity = 0;
    this.referencePinnedFrame = undefined;
    this.referencePinnedCover = '';
    this.referenceFeedPreviewPinned = false;
    this.referenceFeedSurfaceReady = true;
    this.referenceFeedPreparingMain = false;
    const player = this.av;
    if (!player) return;
    // ⭐ 兜底路径拿到的可能是一条已经播完的旧实例（交接失败时 av 还没换掉）：
    //    对 completed 调 play() 会从头重播，听起来就是“播完又从头出声”。宁可停在静帧。
    if (player.state === 'completed') {
      logWarn('[ReferenceFeed] fallback 跳过起播：当前实例已播完');
      return;
    }
    try {
      player.setVolume(this.mute ? 0 : 1.0);
    } catch (_e) { }
    this.markAutoPlay('feed-fallback');
    this.userPaused_ = false;
    player.play().then(() => {
      if (this.av !== player) return;
      this.play = true;
      if (this.avAudio) {
        try { this.avAudio.setVolume(this.mute ? 0 : 1.0); } catch (_e) { }
        this.avAudio.play().catch(() => {});
      }
    }).catch((error: Error) => {
      logWarn(`[ReferenceFeed] fallback play failed: ${error?.message}`);
    });
  }

  /** 静帧必须和 surface 用同一套映射，否则水印/画面会在硬切瞬间位移。 */
  private feedStillFit(aspect: number): ImageFit {
    switch (this.effectiveScaleMode(aspect)) {
      case 'stretch': return ImageFit.Fill;
      case 'fill':
      case 'fitHeight': return ImageFit.Cover;
      default: return ImageFit.Contain;
    }
  }

  /**
   * 固定页静帧的填充方式：位图比例和视频画幅差 >5% 时，说明抓图那一刻预热 surface 还是
   * 上一条的盒子（竖屏帧被 letterbox 进了横屏 buffer，两侧留黑）。这时用 Cover 把黑边裁掉，
   * 正好留下中间的真实画面；用 Contain 会把整张位图缩进去，画面变成细细一条（实测出现过）。
   * 位图比例与画幅一致时（绝大多数情况）保持原来的 fit，行为不变。
   */
  private stillFitForBitmap(bitmapRatio: number, targetAspect: number): ImageFit {
    if (bitmapRatio > 0 && targetAspect > 0 && Math.abs(bitmapRatio / targetAspect - 1) > 0.05) {
      return ImageFit.Cover;
    }
    return this.feedStillFit(targetAspect);
  }

  private feedStillWidth(aspect: number): number {
    return this.effectiveScaleMode(aspect) === 'fitHeight'
      ? this.referenceAreaHeight() * Math.max(0.2, aspect) : this.referenceMediaWidth(aspect);
  }

  private feedStillHeight(aspect: number): number {
    return this.effectiveScaleMode(aspect) === 'fitWidth'
      ? this.cw / Math.max(0.2, aspect) : this.referenceMediaHeight(aspect);
  }

  /**
   * 把预热 surface 上的暂停帧铺回播放位，再撤掉覆盖在上面的静帧。
   *
   * 静帧本来就是从这个 surface 抓的同一帧，所以这一步是无缝硬切；随后 play() 从
   * 该帧继续，不会出现「静帧(t0) → 已播出几百毫秒的 live 帧」的跳变。
   * 返回 true 表示 surface 已在播放位且静帧已撤（调用方不要再走淡出）。
   */
  private async revealFeedPinnedStill(generation: number): Promise<boolean> {
    if (this.referenceFeedSurfaceReady) return false;
    // 冷启动的 surface 上没有现成画面：硬切会在第一帧到达前漏出黑底，
    // 交给调用方的「等时钟前进再露 surface」路径，期间保持封面/静帧。
    if (!this.referenceFeedWarmAdopted_) {
      logInfo('[ReferenceFeed] still cut skip: cold surface');
      return false;
    }
    if (!this.referencePinnedFrame) {
      logInfo('[ReferenceFeed] still cut skip: no decoded frame (cover only)');
      return false;
    }
    const pinnedFrame = this.referencePinnedFrame;
    let frameInfo: image.ImageInfo | undefined = undefined;
    try {
      frameInfo = pinnedFrame.getImageInfoSync();
    } catch (_e) {
      frameInfo = undefined;
    }
    if (!frameInfo || !frameInfo.size) {
      // 位图已被释放（例如缓存表替换时旧图被回收）：这一步不能抛，
      // 抛出去会让整条交接失败、画面永远停在静帧上。
      logWarn('[ReferenceFeed] still cut skip: pinned frame released');
      if (this.referencePinnedFrame === pinnedFrame) this.referencePinnedFrame = undefined;
      return false;
    }
    const pmRatio = frameInfo.size.height > 0 ? frameInfo.size.width / frameInfo.size.height : 0;
    logInfo(`[ReferenceFeed] still cut geom ar=${this.ar} pinned=${this.referencePinnedAspectRatio} pm=${frameInfo.size?.width}x${frameInfo.size?.height} pmRatio=${pmRatio} progress=${this.referenceFeedProgress} mode=${this.effectiveScaleMode()}/${this.effectiveScaleMode(this.referencePinnedAspectRatio)} box=${this.referenceMediaWidth()}x${this.referenceMediaHeight()} still=${this.feedStillWidth(this.ar)}x${this.feedStillHeight(this.ar)} areaTop=${this.referenceAreaTop()} mediaTop=${this.referenceMediaTop()} areaH=${this.referenceAreaHeight()} cw=${this.cw} ch=${this.ch}`);
    const started = Date.now();
    this.referenceFeedSurfaceReady = true;
    // 联调：--ps feedStillHold 5000 时在硬切前后各停一段时间，便于逐帧截图对比几何。
    const hold = AppStorage.get<number>('feedStillHoldMs') ?? 0;
    // Surface 的 position 变更要等合成器下一帧才落到屏幕上；等两帧再撤静帧。
    await this.delayMs_(hold > 0 ? hold : 34);
    if (!this.referenceAlive || generation !== this.referenceSwitchGeneration) return false;
    this.referencePinnedOpacity = 0;
    await this.delayMs_(hold > 0 ? hold : 17);
    logInfo(`[ReferenceFeed] still cut done ${Date.now() - started}ms hold=${hold}`);
    return this.referenceAlive && generation === this.referenceSwitchGeneration;
  }

  @Builder
  ReferenceFeedPinnedPage() {
    Stack() {
      if (this.referencePinnedFrame) {
      Image(this.referencePinnedFrame)
        .syncLoad(true)
        .objectFit(this.stillFitForBitmap(this.referencePinnedAspectRatio, this.ar))
        .width(this.feedStillWidth(this.ar))
        .height(this.feedStillHeight(this.ar))
        .position({ x: (this.cw - this.feedStillWidth(this.ar)) / 2,
          y: this.referenceMediaTop(this.ar) })
      } else if (this.referencePinnedCover) {
        // 没有解出静帧时先铺目标封面：黑底转圈既不告诉用户翻到了哪条，
        // 也把下面已经解好的预览帧全挡住。
        Image(this.referencePinnedCover)
          .objectFit(this.stillFitForBitmap(this.referencePinnedAspectRatio, this.ar))
          .width(this.feedStillWidth(this.ar))
          .height(this.feedStillHeight(this.ar))
          .position({ x: (this.cw - this.feedStillWidth(this.ar)) / 2,
            y: this.referenceMediaTop(this.ar) })
      }
      // 已保留真实首帧时，交接期间直接呈现画面；仅无画面时提示加载。
      if (!this.referencePinnedFrame && !this.referencePinnedCover && !this.referenceFeedSurfaceReady) {
        LoadingProgress().width(28).height(28).color('#FFFFFF')
      }
    }.width('100%').height('100%').backgroundColor(Color.Black)
      .opacity(this.referencePinnedOpacity).clip(true).hitTestBehavior(HitTestMode.None)
  }

  @Builder
  ReferenceFeedPreviewPage() {
    Stack() {
      if (this.referencePreviewFrame) {
        Stack() {
        Image(this.referencePreviewFrame)
        .syncLoad(true)
        .objectFit(this.effectiveScaleMode(this.referencePreviewAspectRatio) === 'stretch' ? ImageFit.Fill : this.effectiveScaleMode(this.referencePreviewAspectRatio) === 'fill' ? ImageFit.Cover : ImageFit.Contain)
        .width(this.effectiveScaleMode(this.referencePreviewAspectRatio) === 'fitHeight' ? this.referenceAreaHeight() * Math.max(0.2, this.referencePreviewAspectRatio) : this.referenceMediaWidth(this.referencePreviewAspectRatio))
        .height(this.effectiveScaleMode(this.referencePreviewAspectRatio) === 'fitWidth' ? this.cw / Math.max(0.2, this.referencePreviewAspectRatio) : this.referenceMediaHeight(this.referencePreviewAspectRatio))
        }.width(this.referenceMediaWidth(this.referencePreviewAspectRatio))
        .height(this.referenceMediaHeight(this.referencePreviewAspectRatio)).clip(true)
        .position({
          x: (this.cw - this.referenceMediaWidth(this.referencePreviewAspectRatio)) / 2,
          y: this.referenceMediaTop(this.referencePreviewAspectRatio)
        })
        .hitTestBehavior(HitTestMode.None)
      } else if (this.referenceFeedPreview) {
        // ⭐ 冷命中（这条视频还没被预热、静帧没抓下来）时别留纯黑+转圈：
        //    屏幕上既看不出翻到了哪条，来回切的时候还会连续闪过几帧全黑。
        //    先用队列里的封面铺满画幅，静帧到达后这一支整体被上面的分支替换。
        Stack() {
          if (this.referencePreviewCoverUrl()) {
            Image(this.referencePreviewCoverUrl())
              .objectFit(this.effectiveScaleMode(this.referencePreviewAspectRatio) === 'stretch' ? ImageFit.Fill : ImageFit.Cover)
              .width(this.referenceMediaWidth(this.referencePreviewAspectRatio))
              .height(this.referenceMediaHeight(this.referencePreviewAspectRatio))
          }
          LoadingProgress().width(28).height(28).color('#FFFFFF')
        }
        .width(this.referenceMediaWidth(this.referencePreviewAspectRatio))
        .height(this.referenceMediaHeight(this.referencePreviewAspectRatio))
        .clip(true)
        .position({
          x: (this.cw - this.referenceMediaWidth(this.referencePreviewAspectRatio)) / 2,
          y: this.referenceMediaTop(this.referencePreviewAspectRatio)
        })
        .hitTestBehavior(HitTestMode.None)
      }
      if (this.referenceFeedPreview && !this.referenceInfoHidden) {
        this.ReferencePreviewChrome(this.referenceFeedPreview)
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .clip(true)
  }

  private referencePreviewCoverUrl(): string {
    return this.referenceFeedPreview?.coverUrl || '';
  }

  private referencePreviewDetailFor(item: RecommendItem): VideoDetail | null {
    const detail = this.referencePreviewDetail;
    return detail && (detail.bvid === item.id || detail.aid.toString() === item.id) ? detail : null;
  }

  @Builder
  ReferencePreviewChrome(item: RecommendItem) {
    if (this.referencePreviewAspectRatio >= 1) {
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.ref_fullscreen')).width(12).height(12).fillColor('#FFFFFF')
          Text('全屏播放').fontSize(12).fontColor('#FFFFFF')
        }.padding(8).borderRadius(18).backgroundColor('#AA17181A')
      }.width('100%').justifyContent(FlexAlign.Center)
        .position({ x: 0, y: this.referenceFullscreenButtonTop(this.referencePreviewAspectRatio) })
    }
    // ⭐ 这一页的信息层只认「属于本页的完整快照」：没有就整块不渲染。
    //   不画灰圆、不回退队列字段、不沿用上一条的头像 —— 从源头消掉
    //   「灰占位 → 别人的头像 → 正确头像」三级跳。快照在拖动前就已锁定，正常路径下必然存在。
    if (this.feedNextChrome()) {
      Column({ space: 6 }) {
        Row({ space: 10 }) {
          FeedAvatarImage({ videoId: this.feedNextChrome()!.id, face: this.feedNextChrome()!.face })
          Text(this.feedNextChrome()!.name).fontSize(14).fontColor('#FFFFFF')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          FollowGlassButton({ buttonWidth: 72, buttonHeight: 26, fontSize: 12,
            accent: '#D34E7E', fill: '#D34E7E' })
        }.width('100%').padding({ top: 10, bottom: 10 })
        Row() {
          Text(this.feedNextChrome()!.title).fontSize(14).fontColor('#FFFFFF').maxLines(2).layoutWeight(1)
          Stack() { Image($r('app.media.ref_chevron_up')).width(16).height(16).fillColor('#FFFFFF') }
            .width(30).height(30).borderRadius(15).backgroundColor('#CC252525')
        }.width('100%')
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ref_pause')).width(22).height(22).fillColor('#FFFFFF')
          }.width(40).height(40)
          Text(`00:00 / ${this.formatDuration(this.feedNextChrome()!.duration)}`)
            .fontSize(12).fontColor('#EEEEEE').maxLines(1)
        }.width('100%').height(40)
        Stack({ alignContent: Alignment.Start }) {
          Rect().width('100%').height(2).fill('#45494F')
          Circle().width(5).height(5).fill('#D34E7E')
        }.width('100%').height(20)
        Row() {
          Row() {
            // 连刷预览浮层的弹幕输入入口：与评论页输入胶囊同款 capsule 材质、全圆角。
            NativeGlassInput({ inputHeight: 34 }) {
              Row({ space: 10 }) {
                Image($r('app.media.ref_danmaku_checked')).width(23).height(23)
                Rect().width(0.5).height(13).fill('#888888')
                Text('发弹幕').fontSize(13).fontColor('#E7E9EB')
              }.width('100%').height('100%').padding({ left: 12, right: 12 })
            }
          }.layoutWeight(1).constraintSize({ maxWidth: FEED_DANMAKU_MAX_W })
          // 与当前页操作行同一口径：按钮组固定宽度靠右，翻页交接时图标位置不会跳。
          Row() {
            ReferencePlayerAction({ icon: $r('app.media.ref_like'), label: this.fmtN(this.feedNextChrome()!.like), light: true })
            ReferencePlayerAction({ icon: $r('app.media.ref_coin'), label: this.fmtN(this.feedNextChrome()!.coin), light: true })
            ReferencePlayerAction({ icon: $r('app.media.ref_favorite'), label: this.fmtN(this.feedNextChrome()!.favorite), light: true })
            ReferencePlayerAction({ icon: $r('app.media.ref_comment_fill'), label: this.fmtN(this.feedNextChrome()!.reply), light: true })
          }.width(FEED_ACTION_ITEM_W * 4)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
      }.width('100%').height(244 + this.referenceChromeInset()).justifyContent(FlexAlign.End)
        .padding({ left: 8, right: 8, bottom: this.referenceChromeInset() })
        .position({ x: 0, y: this.feedChromeTop(true) })
        .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 0.5], ['#FF000000', 1]] })
    }
  }

  private referenceVideoLink(): string {
    return this.isPgc_ ? `https://www.bilibili.com/bangumi/play/ep${this.epId_}` :
      `https://www.bilibili.com/video/${this.vi.bvid}`;
  }

  private async referenceCopyLink(): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.referenceVideoLink());
      await pasteboard.getSystemPasteboard().setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制视频链接' });
    } catch (error) { logError('复制视频链接失败', error); }
  }

  private async referenceDislike(): Promise<void> {
    await this.runVideoInteraction('dislike', this.isDisliked ? 'cancel' : 'add');
  }

  private loadReferenceIntroExtras(): void {
    const bvid = this.vi.bvid;
    const mid = this.vd?.owner.mid || 0;
    if (!bvid || !mid || this.isPgc_ || this.vd?.bvid !== bvid || this.referenceIntroRequest === bvid) return;
    this.referenceIntroRequest = bvid;
    this.referenceIntroCard = null;
    this.referenceIntroTags = [];
    this.referenceDescriptionExpanded = false;
    getVideoIntroCard(mid).then((card) => {
      if (this.referenceAlive && this.vi.bvid === bvid && this.referenceIntroRequest === bvid) this.referenceIntroCard = card;
    });
    getVideoIntroTags(bvid).then((tags) => {
      if (this.referenceAlive && this.vi.bvid === bvid && this.referenceIntroRequest === bvid) this.referenceIntroTags = tags;
    });
  }

  /** 简介统计：合集切集途中详情还没换成当前视频，不能继续显示上一条的数字 */
  private referenceIntroStat(kind: string): string {
    if (this.detailIsCurrentVideo() && this.vd) {
      return this.fmtN(kind === 'danmaku' ? this.vd.stat.danmaku : this.vd.stat.view);
    }
    if (kind === 'view' && this.vi.view !== undefined) return this.fmtN(this.vi.view);
    return '—';
  }

  private referencePublishTime(): string {
    const timestamp = this.detailIsCurrentVideo() ? (this.vd?.pubdate || this.vi.pubdate || 0) : (this.vi.pubdate || 0);
    if (!timestamp) return '';
    const date = new Date(timestamp * 1000);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  private referenceCurrentAvatarFace(): string {
    const detail = this.vd;
    const matches = detail && (detail.bvid === this.vi.bvid || detail.aid.toString() === this.vi.bvid);
    return imageUrlResize((matches ? detail.owner.face : this.vi.ownerFace) || '', 48);
  }

  /** UP 主页入口的统一跳转（头像与昵称共用；mid 缺失时不跳） */
  private referenceOpenUpSpace(): void {
    if (this.vd?.owner.mid) router.pushUrl({ url: 'pages/UpSpacePage', params: {
      mid: this.vd.owner.mid, upName: this.vd.owner.name, upFace: this.vd.owner.face
    } });
  }

  @Builder
  ReferenceUpRow(compact: boolean) {
    Row({ space: 10 }) {
      // 主页入口覆盖头像高度内的头像、资料及留白；关注按钮为独立的相邻触点。
      // ⚠️ 连刷信息层（compact）例外：行内留白不能进空间 —— 连刷的单击语义是显隐信息层，
      //    与详情页简介「整行进空间」不同，留白点击必须透传给页面级 referenceHandleFeedClick。
      //    两层收窄（都只在 compact 生效，非 compact 保持 Default 整行入口）：
      //    ① 入口行 hitTestBehavior(None)：只把容器自身移出触摸测试（onClick 随之失效），
      //       子节点照常命中（见 referenceFeedChromeHitTest 注释）；
      //    ② 主页触点必须是「头像 + 昵称 Text」本身 —— 不能挂在昵称 Column 上：
      //       它 layoutWeight(1) 的命中框从头像铺到关注按钮，留白全在框里，
      //       点哪里进空间、点哪里透传就变成「概率」行为（真机踩过）。
      Row({ space: 10 }) {
        if (compact) {
          FeedAvatarImage({ videoId: this.vi.bvid, face: this.referenceCurrentAvatarFace() })
            .onClick(() => this.referenceOpenUpSpace())
        } else {
          // 详情页简介头部仍按原来的 URL 渲染，不参与连刷的位图交接。
          Image(getCachedPixelMap(imageUrlResize(this.vd?.owner.face || this.vi.ownerFace || '', 48)) ??
            imageUrlResize(this.vd?.owner.face || this.vi.ownerFace || '', 48))
            .width(28).height(28).borderRadius(20).objectFit(ImageFit.Cover)
        }
        Column({ space: 3 }) {
          Text(this.vd?.owner.name || this.vi.ownerName || '').fontSize(compact ? 14 : 13)
            .fontColor(compact ? '#FFFFFF' : '#D34E7E').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => this.referenceOpenUpSpace())
          if (!compact && this.referenceIntroCard) {
            Text(`${this.fmtN(this.referenceIntroCard.card?.fans || 0)}粉丝  ${this.referenceIntroCard.archive_count || 0}视频`)
              .fontSize(10).fontColor('#757A81').maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).height(compact ? 34 : 28)
        .onClick(() => this.referenceOpenUpSpace())
        .hitTestBehavior(compact ? HitTestMode.None : HitTestMode.Default)
      FollowGlassButton({ followed: this.isFollowed, buttonWidth: 72, buttonHeight: 26, fontSize: 12,
        accent: this.isFollowed ? '#45494F' : '#D34E7E', fill: this.isFollowed ? '#45494F' : '#D34E7E',
        onActivate: () => this.toggleFollow() })
    }.width('100%').height(compact ? 54 : 62)
  }

  @Builder
  ReferenceIntro() {
    List({ scroller: this.detailScroller }) {
      ListItem() {
      Column() {
        if (!this.isPgc_ || (this.vd?.owner.mid || 0) > 0) {
          this.ReferenceUpRow(false)
        }
        Column({ space: 7 }) {
          Row({ space: 8 }) {
            Text((this.detailIsCurrentVideo() ? this.vd?.title : '') || this.vi.title || '').fontSize(16).lineHeight(22)
              .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
              .maxLines(this.referenceDescriptionExpanded ? 10 : 1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.ref_chevron_up')).width(18).height(18).fillColor('#757A81')
              .rotate({ angle: this.referenceDescriptionExpanded ? 0 : 180 })
          }.width('100%').onClick(() => { this.referenceDescriptionExpanded = !this.referenceDescriptionExpanded; })
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
            Row() { ReferenceIntroStat({ icon: $r('app.media.ref_play'), value: this.referenceIntroStat('view') }) }.margin({ right: 8 })
            Row() { ReferenceIntroStat({ icon: $r('app.media.ref_danmaku'), value: this.referenceIntroStat('danmaku') }) }.margin({ right: 8 })
            Text(this.referencePublishTime()).fontSize(10).fontColor('#757A81').maxLines(1)
          }.width('100%')
          if (this.detailIsCurrentVideo() && this.vd?.argue_info?.argue_msg) {
            Row({ space: 4 }) {
              Text('ⓘ').fontSize(13).fontColor('#757A81')
              Text(this.vd.argue_info.argue_msg).fontSize(11).fontColor('#757A81')
            }.width('100%')
          }
          if (this.referenceDescriptionExpanded) {
            Row({ space: 8 }) {
              Text(this.isPgc_ ? `ep${this.epId_}` : this.vi.bvid).fontSize(10).fontColor('#757A81')
              if (this.detailIsCurrentVideo() && this.vd?.rights?.no_reprint === 1) {
                Text('⊘ 未经作者授权禁止转载').fontSize(10).fontColor('#757A81')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              }
            }.width('100%')
            Text(this.detailIsCurrentVideo() ? (this.vd?.desc || '') : '').fontSize(12).lineHeight(19).fontColor('#757A81').width('100%')
              .gesture(LongPressGesture().onAction(() => {
                this.showTextSelection('文本工具 · 简介', this.detailIsCurrentVideo() ? (this.vd?.desc || '') : '');
              }))
            if (this.isPgc_ && !(this.vd?.owner.mid || 0) && this.vd?.owner.name &&
              !this.vd.desc.includes(this.vd.owner.name)) {
              Text(this.vd.owner.name).fontSize(12).lineHeight(19).fontColor('#757A81').width('100%')
            }
          }
        }.width('100%').padding({ top: 10, bottom: 12 })
        Row() {
          ReferencePlayerAction({ icon: $r('app.media.ref_like'), label: this.fmtN(this.likeCount), selected: this.isLiked, intro: true, onAction: () => this.toggleLike() })
          ReferencePlayerAction({ icon: $r('app.media.ref_dislike'), label: this.isDisliked ? '取消不喜欢' : '不喜欢', selected: this.isDisliked, intro: true, onAction: () => this.referenceDislike() })
          ReferencePlayerAction({ icon: $r('app.media.ref_coin'), label: this.fmtN(this.coinCount), selected: this.isCoined, intro: true, onAction: () => this.toggleCoin(1) })
          ReferencePlayerAction({ icon: $r('app.media.ref_favorite'), label: this.fmtN(this.favoriteCount), selected: this.isFavorited, intro: true, onAction: () => this.toggleFavorite() })
          ReferencePlayerAction({ icon: $r('app.media.ref_share_solid'), label: this.fmtN(this.detailIsCurrentVideo() ? (this.vd?.stat.share || 0) : 0), intro: true, onAction: () => { this.referencePortraitAction('share:intro'); } })
        }.width('100%').padding({ top: 4, bottom: 12 })
        if (this.vd?.ugc_season?.id) {
          Row({ space: 6 }) {
            Text(`合集 · ${this.vd.ugc_season.title || ''}`).fontSize(14)
              .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Text(`${this.seasonCurrentEpisodeIndex() + 1}/${this.seasonTotalEpisodeCount()}`)
              .fontSize(11).fontColor('#757A81')
            Image($r('app.media.ref_chevron_right')).width(16).height(16).fillColor('#757A81')
          }.width('100%').height(34).padding({ left: 12, right: 10 }).borderRadius(4)
            .backgroundColor(this.isDarkMode ? '#101112' : '#F1F2F3')
            .onClick(() => { this.openSeasonSheet(); })
            .margin({ bottom: 12 })
        }
        if (this.pagesForCurrentVideo().length > (this.isPgc_ ? 0 : 1)) {
          ReferenceEpisodeStrip({ pages: this.pagesForCurrentVideo(), isDarkMode: this.isDarkMode,
            playing: this.play && !this.waitingForFirstFrame,
            selectedIndex: this.referenceEpisodeSelection >= 0 ? this.referenceEpisodeSelection : this.currentPageIndex,
            onSelect: (index: number) => { this.triggerHaptic(); this.switchEpisode(index); },
            onShowAll: () => { this.openEpisodeSheet(); }
          }).margin({ bottom: 12 })
        }
        if (this.referenceIntroTags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.referenceDescriptionExpanded ? this.referenceIntroTags : this.referenceIntroTags.slice(0, 1), (tag: VideoIntroTag) => {
              Row({ space: 6 }) {
                Text('#').fontSize(14).fontColor('#A2A7AE')
                Text(tag.tag_name).fontSize(11).fontColor('#757A81').maxLines(1)
                Image($r('app.media.ref_chevron_right')).width(12).height(12).fillColor('#757A81')
              }.height(26).padding({ left: 10, right: 8 }).borderRadius(16)
                .backgroundColor(this.isDarkMode ? '#202224' : '#F1F2F3').margin({ right: 8, bottom: 8 })
                .onClick(() => { router.pushUrl({ url: 'pages/SearchPage', params: { keyword: tag.tag_name } }); })
            }, (tag: VideoIntroTag) => tag.tag_id.toString())
          }.width('100%').margin({ bottom: 2 })
        }
        Column().height(10)
      }.width('100%')
      }.width('100%')
        ForEach(this.relatedVideos, (item: RecommendItem) => {
          ListItem() {
          VideoListItem({
            availableWidth: Math.max(1, (this.isLs ? this.referenceLandscapeTabWidth(0) : this.cw) - 24),
            title: item.title, cover: item.coverUrl, duration: item.duration,
            videoId: item.pgcSeasonId > 0 ? '' : item.id, ownerMid: item.ownerMid,
            owner: item.ownerName, playCount: item.playCount,
            onActivate: () => this.onRelatedVideoClick(item)
          })
          }.width('100%')
        }, (item: RecommendItem) => item.id)
        // 末尾占位代替 List 的 bottom padding：ArkUI 内边距会把视口内缩，
        // 内容在距屏幕底边约 20vp 处被裁出一条空带；占位项让列表贴到面板底边，
        // 滚到底时仍保留同样的收尾留白。
        ListItem() {
          Column().width('100%').height(20)
        }
    }.id('reference-intro').width(this.isLs ? this.referenceLandscapeTabWidth(0) : this.cw).height('100%').padding({ left: 12, right: 12 }).cachedCount(2).scrollBar(BarState.Off)
      // Keep the first short body at the same origin before related videos arrive.
      .align(Alignment.TopStart)
      .edgeEffect(EdgeEffect.None)
      .onScrollFrameBegin((offset: number) => ({ offsetRemain: this.referenceIntroScrollOffset(offset) }))
      .onDidScroll((_offset: number, state: ScrollState) => { this.referenceIntroScrollState = state; })
      .onScrollStop(() => { this.referenceIntroScrollState = ScrollState.Idle; })
      .onAppear(() => this.loadReferenceIntroExtras())
  }

  @Builder
  ReferencePanel() {
    Stack({ alignContent: Alignment.TopStart }) {
    this.ContentPanelWallpaper()
    Column() {
      Column() {
        PageHeader({ showSurface: !this.referenceFeed && !this.referenceFeedComments,
          withTabs: true, hideBottomEdge: true, scopeId: 'video-panel-tabs-native-scope',
          surfaceRevision: this.referencePanelHeaderRevision }) {
          Column({ space: 6 }) {
            Row() {
              Row().width(42).height(4).borderRadius(2).backgroundColor('#45494F')
            }.width('100%').height(this.isLs ? 8 : 20).visibility(this.isLs ? Visibility.Hidden : Visibility.Visible).justifyContent(FlexAlign.Center)
              .id('reference-portrait-resize-handle')
              // ⭐ distance 与横屏 referenceLandscapeResize 一样取 1vp：
              //    GestureEvent.offsetY 是从按下点算起的累计量，原来的 distance: 8
              //    会让第一次 onActionUpdate 直接带 8vp，起步首帧凭空补 8vp（跳一下）。
              //    取 1vp 后首帧只有 1vp、肉眼不可见，且 `referencePanelStart + offsetY`
              //    与 onActionEnd 的 90 / 45 / 850 判定仍在同一坐标系，阈值语义完全不变。
              //    PanDirection.Vertical 已排除横向手势，把手 Row 内也没有点击目标。
              .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 1 })
                .onActionStart(() => { this.referencePanelStart = this.referencePanelOffset; })
                .onActionUpdate((event: GestureEvent) => {
                  if (this.isLs) return;
                  if (!this.referenceFeedComments) {
                    const offset = this.referencePanelStart + event.offsetY;
                    this.referencePanelOffset = this.referencePanelDragOffset(offset);
                  }
                })
                .onActionEnd((event: GestureEvent) => {
                  if (this.isLs) return;
                  if (this.referenceFeedComments) {
                    if (event.offsetY > 80 || (event.offsetY > 30 && event.velocityY > 850)) this.referenceSetFeedComments(false);
                    return;
                  }
                  if (this.referencePanelOffset > 90 || (event.offsetY > 45 && event.velocityY > 850)) {
                    this.referenceSetFeed(true);
                  } else if (this.referencePanelOffset > 0) {
                    // 下拉是「进连刷」手势通道，没到阈值就回起点；否则 16:9 会停在
                    // 「区域变高、画面不放大」的大黑边中间态。
                    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => { this.referencePanelOffset = 0; });
                  }
                  // 上推方向保持手指松开时的比例（无级），不再吸附到 0 / 最小两档。
                  // 进连刷由 referenceSetFeed 收尾归零，取消手势仍回 referencePanelStart。
                })
                .onActionCancel(() => {
                  if (this.isLs) return;
                  this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => { this.referencePanelOffset = this.referencePanelStart; });
                }))
            Row() {
              if (!this.referenceFeedComments) {
                ForEach(['简介', '评论'], (label: string, index: number) => {
                  Column({ space: 6 }) {
                    Text() {
                      Span(label).fontSize(14)
                      if (index === 1) { Span(` ${this.fmtN(this.vd?.stat.reply || 0)}`).fontSize(10).fontWeight(FontWeight.Normal) }
                    }.fontSize(14)
                      .fontWeight(Math.abs(this.referenceTabProgress - index) < 0.5 ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(Math.abs(this.referenceTabProgress - index) < 0.5 ? (this.isDarkMode ? '#E7E9EB' : '#18191C') : '#757A81')
                      .onAreaChange((_old: Area, area: Area) => {
                        if (index === 0) this.referenceIntroTabWidth = Number(area.width);
                        else this.referenceCommentTabWidth = Number(area.width);
                      })
                    Row().width(16).height(3).borderRadius(2).backgroundColor(index === 0 ? '#D34E7E' : Color.Transparent)
                      .translate({ x: index === 0 ? this.referenceTabProgress *
                        (this.referenceIntroTabWidth / 2 + 20 + this.referenceCommentTabWidth / 2) : 0 })
                  }.height(32).justifyContent(FlexAlign.End).margin({ right: 20 })
                    .onClick(() => { this.referencePanelSwiper.changeIndex(index, true); })
                })
                Blank()
                Row() {
                  // 竖屏 Tab 栏弹幕输入入口：沿用评论页输入胶囊的 capsule 材质与次级前景色。
                  NativeGlassInput({ inputHeight: 28 }) {
                    Row({ space: 8 }) {
                      Text('点我发弹幕').fontSize(11).fontColor($r('app.color.color_player_text_secondary')).height('100%')
                        .onClick(() => { this.showDanmakuSheet = true; })
                      Rect().width(0.5).height(22).fill(this.isDarkMode ? '#303234' : '#E3E5E7')
                      Image(this.isDanmakuEnabled ? $r('app.media.ref_danmaku_checked') : $r('app.media.ref_apk_danmaku_off')).width(23).height(23)
                        .onClick(() => { this.toggleDanmaku(); })
                    }.width('100%').height('100%').padding({ left: 12, right: 8 })
                  }
                }.width(126).visibility(this.isLs ? Visibility.None : Visibility.Visible)
              } else {
                Text('评论').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                Blank()
                Image($r('app.media.ref_close')).width(24).height(24).fillColor('#757A81')
                  .onClick(() => this.referenceSetFeedComments(false))
              }
            }.width('100%').padding({ left: 14, right: 12 })
          }.width('100%').height(this.isLs ? 46 : 58)
        }
      }.width('100%').height(this.isLs ? 46 : 58).zIndex(1)
      // Keep scrolling cards and reply previews within the body, below the native title surface.
      Column() {
        if (!this.isLs && this.referenceFeedComments) {
          this.ReferenceCommentPage()
        } else {
          Swiper(this.referencePanelSwiper) {
            LazyForEach(this.referencePanelPages, (page: number) => {
              Column() {
                if (page === 0) {
                  this.ReferenceIntro()
                } else {
                  this.ReferenceCommentPage()
                }
              }.width('100%').height('100%')
                .onAppear(() => {
                  if (page === 1) this.referenceCommentsMounted = true;
                })
            }, (page: number) => page.toString())
          }.index(this.at).loop(false).indicator(false)
            // Native lazy mounting prepares the destination during a real swipe.
            // Once visited, retain both pages and their scroll/image nodes.
            .cachedCount(this.referenceCommentsMounted ? 1 : 0)
            .duration(HOME_CHANNEL_DURATION).curve(HOME_CHANNEL_CURVE)
            .width('100%').layoutWeight(1)
            .onAnimationEnd((_index: number) => {
              // Swiper moves cached render nodes. Drop the header's old backdrop only after
              // settling (including a cancelled swipe), keeping the glass during the motion
              // and preserving both pages, their images, and their scroll positions.
              this.referencePanelHeaderRevision += 1;
            })
            .onContentDidScroll((_selectedIndex: number, index: number, position: number, _length: number) => {
              this.referenceTabProgress = Math.max(0, Math.min(1, index - position));
            })
            .onChange((index: number) => {
              this.at = index;
              if (index === 1 && this.vd?.aid && !this.ldc && this.commentDataSource.totalCount() === 0) {
                this.pendingCommentAid = 0;
                this.loadC(this.vd.aid);
              }
              logInfo(`[ReferenceMotion] panel tab=${index}`);
            })
            .onTouch((event: TouchEvent) => this.referencePanelBodyTouch(event))
        }
      }.width('100%').layoutWeight(1).constraintSize({ minHeight: 0 }).clip(true)
        .onTouchIntercept((event: TouchEvent) => this.referencePanelTouchIntercept(event))
    }.width('100%').height('100%').backgroundColor(this.isDarkMode ? '#17181A' : '#FFFFFF')
      .clip(true)
        .hitTestBehavior(this.commentThread ? HitTestMode.None : HitTestMode.Default)
      this.commentThreadView()
    }.width('100%').height('100%')
  }

  @Builder
  ReferenceCommentPage() {
    Stack({ alignContent: Alignment.Bottom }) {
      Refresh({ refreshing: $$this.referenceCommentRefreshing }) {
        this.commentListCore(false, !this.isLs && this.referenceFeedComments, true)
      }.width('100%').height('100%')
        .onRefreshing(() => this.refreshReferenceComments())
      FloatingCommentEntry({ bottomInset: this.navIndicatorHeight,
        entryWidth: this.referenceLayoutPixel((this.isLs && !this.fs ? this.referenceLandscapeTabWidth(1) : this.cw) * 0.94),
        onOpen: () => this.openCommentSheet('new', 0, 0, '') })
        .opacity(this.commentSheetVisible ? 0 : 1)
    }.width(this.isLs && !this.fs ? this.referenceLandscapeTabWidth(1) : '100%').height('100%').layoutWeight(1)
  }

  private async refreshReferenceComments(): Promise<void> {
    try {
      const scroller = !this.isLs && this.referenceFeedComments ? this.fsCommentScroller : this.commentScroller;
      const offset = scroller.currentOffset().yOffset;
      if (!Number.isFinite(offset) || offset > 0.5 || !this.vd?.aid || this.ldc || this.isLoadingMore) return;
      this.commentCursor = 0;
      this.hm = true;
      await this.loadC(this.vd.aid);
    } finally {
      this.referenceCommentRefreshing = false;
    }
  }

  @Builder
  ReferenceLandscapeResizeHandle() {
    Row() {
      Row().width(4).height(42).borderRadius(2).backgroundColor('#45494F')
        .translate({ x: this.isLayoutSwapped ? -2 : 2 })
    }.width(32).height(72).justifyContent(FlexAlign.Center)
      .id('reference-landscape-resize-handle')
      .accessibilityText('拖动调节视频区和简介区大小')
      .position({ x: this.referenceLandscapeHandleX(),
        y: this.referenceLandscapeAreaTop() + (this.referenceLandscapeAreaHeight() - 72) / 2 })
      .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => { this.referenceLandscapeBeginResize(); })
        .onActionUpdate((event: GestureEvent) => { this.referenceLandscapeResize(event.offsetX); })
        .onActionEnd((event: GestureEvent) => { this.referenceLandscapeFinishResize(event.offsetX); })
        .onActionCancel(() => { this.referenceLandscapeFinishResize(0, true); }))
  }

  @Builder
  ReferencePortrait() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column() { this.ReferencePanel() }.width('100%').height('100%')
          // 已有简介不随下一分P的首帧等待隐藏，切集期间只更新选中状态。
          .visibility(this.waitingForFirstFrame && !this.vd ? Visibility.Hidden : Visibility.Visible)
      }.width(this.isLs ? this.referenceLandscapePanelWidth() : this.cw)
        .onAreaChange((_old: Area, area: Area) => {
          if (this.referenceLandscapeResizeActive) {
            const now = Date.now();
            this.resizeLayoutCount++;
            this.resizeLayoutMaxGap = Math.max(this.resizeLayoutMaxGap, now - this.resizeLayoutLastAt);
            this.resizeLayoutLastAt = now;
          }
        })
        .backgroundColor(this.isDarkMode ? '#17181A' : '#FFFFFF')
        // Clip the wallpaper, native header and body together at the panel's outer edge.
        // A square backing behind a separately rounded body leaves exposed top corners.
        .borderRadius({ topLeft: this.isLs ? this.cardBorderRadius : 12,
          topRight: this.isLs ? this.cardBorderRadius : 12,
          bottomLeft: this.isLs ? this.cardBorderRadius : 0,
          bottomRight: this.isLs ? this.cardBorderRadius : 0 }).clip(true)
        .height(this.isLs ? Math.max(1, this.ch - this.referenceSafeTop() - this.safeCM()) :
          Math.max(120, this.ch - (this.referenceSafeTop() +
            (this.referenceFeedComments ? Math.max(100, this.ch * 0.34) : this.referenceDetailAreaHeight()))))
        .position({ x: this.isLs ? this.referenceLandscapePanelX() : 0,
          y: this.isLs ? this.referenceSafeTop() : this.referenceDetailPanelTop() })
        .visibility(!this.isLs && !this.referenceFeedComments && this.referenceFeedProgress >= 1 ? Visibility.Hidden : Visibility.Visible)
        .hitTestBehavior(this.referenceModeAnimating ? HitTestMode.None : HitTestMode.Default)
    }.width('100%').height('100%').backgroundColor('#000000').onAreaChange(this.onCA)
  }

  private referencePortraitFeedActive(): boolean {
    return this.referenceLayout && this.referenceFeed && !this.referenceModeAnimating && !this.fs && !this.isLs && !this.isAnimatingToFS && !this.fsEntering;
  }


  private referenceCleanViewing(): boolean {
    return this.referenceLayout && this.referenceFeed && !this.fs && !this.isLs && this.referenceInfoHidden;
  }

  private referenceToggleInfo(): void {
    if (this.fullscreenTransformTouch || Date.now() < this.fullscreenTransformClickUntil) return;
    if (this.referenceModeAnimating || this.referenceFeedComments || this.referenceVerticalSwipe || this.referenceFeedPanOwnsTouch || this.mp) return;
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 160, curve: Curve.EaseOut }, () => {
      this.referenceInfoHidden = !this.referenceInfoHidden;
    });
    // 目标系统栏状态变化才下发；单击显隐是高频操作，不该每次都重算一遍窗口 avoidArea。
    this.manageSB();
    logInfo(`[ReferencePortrait] information hidden=${this.referenceInfoHidden}`);
  }

  private referenceCancelFeedTap(): void {
    if (this.referenceFeedTapTimer !== -1) clearTimeout(this.referenceFeedTapTimer);
    this.referenceFeedTapTimer = -1;
  }

  private referenceHandleFeedClick(): void {
    if (Date.now() < this.referenceFeedDoubleTapUntil) return;
    if (!this.referencePortraitFeedActive() || this.referenceFeedComments || this.referenceFeedLoading ||
      this.referenceVerticalSwipe || this.referenceFeedPanOwnsTouch || this.mp || this.lk ||
      this.sliderDragging_ || this.seekBarTouch_ || this.fullscreenTransformTouch ||
      Date.now() < this.fullscreenTransformClickUntil) return;
    this.referenceCancelFeedTap();
    this.referenceFeedTapGeneration = this.referenceSwitchGeneration;
    this.referenceFeedTapTimer = setTimeout(() => {
      this.referenceFeedTapTimer = -1;
      if (this.referenceAlive && this.referenceFeedTapGeneration === this.referenceSwitchGeneration) this.referenceToggleInfo();
    }, 350);
  }

  private referenceHandleFeedDoubleTap(event: GestureEvent): void {
    this.referenceCancelFeedTap();
    if (!this.referencePortraitFeedActive() || this.referenceFeedComments || this.referenceFeedLoading ||
      this.referenceVerticalSwipe || this.referenceFeedPanOwnsTouch || this.mp || this.lk ||
      this.sliderDragging_ || this.seekBarTouch_ || this.fullscreenTransformTouch ||
      Date.now() < this.fullscreenTransformClickUntil) return;
    const finger = event.fingerList[0];
    if (!this.referenceInfoHidden && finger &&
      (finger.globalY < this.referenceSafeTop() || finger.globalY >= this.ch - 244 - this.navIndicatorHeight)) return;
    this.referenceFeedDoubleTapUntil = Date.now() + 350;
    logInfo(`[ReferenceFeed] double tap playing=${this.play}`);
    this.togglePP();
  }

  @Builder
  ReferenceFeedPlaybackOverlay() {
    if (this.referencePortraitFeedActive() && !this.referenceFeedComments && !this.mp &&
      !this.referenceFeedLoading && this.referencePlaybackCompleted) {
      Column({ space: 24 }) {
        // ⭐ 竖屏连刷的重播按钮与顶栏控件同一份材质（HeaderGlassControl）：原生沉浸光感 ULTRA_THIN
        //    + 按压白光，降级设备走顶栏同款 COMPONENT_ULTRA_THIN 模糊底，替换原来的平涂 #55777777。
        //    固定 108x44，内容（↻26 + 8 + 重播32）居中，不会挤字。
        Stack() {
          HeaderGlassControl({
            controlWidth: 108, controlHeight: 44, controlId: 'reference-feed-replay', label: '重播',
            onActivate: () => { this.referenceReplay(); }
          }) {
            Row({ space: 8 }) {
              Text('↻').fontSize(26).fontColor(Color.White).hitTestBehavior(HitTestMode.None)
              Text('重播').fontSize(16).fontColor(Color.White).hitTestBehavior(HitTestMode.None)
            }
          }
        }
        .onTouch((event: TouchEvent) => event.stopPropagation())
        Text('⌃ 上滑查看更多推荐视频').fontSize(14).fontColor('#BBFFFFFF')
          .hitTestBehavior(HitTestMode.None)
      }.position({ x: 0, y: this.ch * 0.42 }).width('100%').zIndex(9)
        .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
    }
  }

  private referenceOpenPortraitSettings(): void {
    this.referenceInfoHidden = false;
    // 目标系统栏状态没变就别再下发窗口指令，否则动画首帧要先等一轮 avoidArea 重算。
    this.manageSB();
    this.referenceAnimateMenu(true);
    logInfo('[ReferencePortrait] settings open');
  }

  private referenceClosePortraitSettings(): void {
    if (this.referenceLayout && this.fs && this.isLs) { this.referenceSetMoreDrawer(false); return; }
    this.referenceAnimateMenu(false);
    logInfo('[ReferencePortrait] settings close');
  }

  /**
   * 抽屉开合：只有 translate 在动，必须让它跑满屏幕刷新率。
   * 不声明 expectedFrameRateRange 时按 60Hz 出帧，120Hz 真机上这段位移只有十几帧，
   * 观感就是「一顿一顿」。这里按设备上限要帧，并把动画窗口收紧一点，少掉几帧也不显。
   */
  private referenceAnimateMenu(open: boolean): void {
    this.referencePortraitSettingsAnimating = true;
    const token = ++this.referencePortraitMotionToken;
    this.getUIContext().animateTo({ duration: open ? 260 : 220, curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        if (token !== this.referencePortraitMotionToken) return;
        this.referencePortraitSettingsAnimating = false;
        this.referenceRestoreProgressUi();
      }
    }, () => { this.mp = open; this.ip = open; });
  }

  /** 动画期间冻结了进度/字幕的 UI 写入，收尾时补一次真实进度。 */
  private referenceRestoreProgressUi(): void {
    if (!this.av || this.sk_ || this.sg_) return;
    // 播完时 currentTime 可能已经回到 0，别把进度条从片尾拉回去。
    if (this.av.state === 'completed') return;
    this.ct = Math.max(0, this.av.currentTime / 1000);
  }

  private referenceMenuVisibility(): Visibility {
    return this.mp || this.referencePortraitSettingsAnimating ? Visibility.Visible : Visibility.Hidden;
  }

  private async referenceSetSubtitles(enabled: boolean): Promise<void> {
    this.referenceSubtitleEnabled = enabled;
    this.referenceSubtitleText = '';
    this.referenceSubtitleCues = [];
    if (!enabled) return;
    const bvid = this.vi.bvid;
    const request = http.createHttp();
    try {
      const result = await request.request(`https://api.bilibili.com/x/player/v2?bvid=${bvid}&cid=${this.vi.cid}`, {
        method: http.RequestMethod.GET,
        header: { 'Cookie': AppStorage.get<string>('biliCookie') || '', 'Referer': 'https://www.bilibili.com/' }
      });
      const info = JSON.parse(result.result as string) as ReferenceSubtitleInfo;
      const tracks = info.data?.subtitle?.subtitles || [];
      if (bvid !== this.vi.bvid || !this.referenceAlive) return;
      if (!tracks.length) {
        this.referenceSubtitleEnabled = false;
        this.getUIContext().getPromptAction().showToast({ message: '当前视频暂无可用字幕' });
        return;
      }
      const response = await request.request(tracks[0].subtitle_url.startsWith('//') ? `https:${tracks[0].subtitle_url}` : tracks[0].subtitle_url);
      if (bvid !== this.vi.bvid || !this.referenceAlive) return;
      this.referenceSubtitleCues = (JSON.parse(response.result as string) as ReferenceSubtitleBody).body || [];
      this.referenceSubtitleEnabled = this.referenceSubtitleCues.length > 0;
    } catch (error) {
      this.referenceSubtitleEnabled = false;
      logWarn('加载字幕失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '字幕加载失败，请重试' });
    } finally { request.destroy(); }
  }

  private async referenceOpenLandscapeSubtitles(asMenu: boolean = false): Promise<void> {
    if (!asMenu) {
      this.cv = false;
      this.ip = true;
      this.referenceSubtitlePanelOpen = true;
    }
    const token = ++this.referenceSubtitleMenuRequest;
    this.referenceSubtitleMenuLoading = true;
    this.referenceSubtitleMenuFailed = false;
    this.referenceSubtitleOptions = [];
    this.referenceSubtitleTrackUrls = [];
    const bvid = this.vi.bvid;
    const cid = this.vi.cid;
    const request = http.createHttp();
    try {
      const result = await request.request(`https://api.bilibili.com/x/player/v2?bvid=${bvid}&cid=${this.vi.cid}`, {
        method: http.RequestMethod.GET,
        header: { 'Cookie': AppStorage.get<string>('biliCookie') || '', 'Referer': 'https://www.bilibili.com/' }
      });
      const info = JSON.parse(result.result as string) as ReferenceSubtitleInfo;
      const tracks = info.data?.subtitle?.subtitles || [];
      if (token !== this.referenceSubtitleMenuRequest || bvid !== this.vi.bvid || cid !== this.vi.cid || !this.referenceAlive) return;
      this.referenceSubtitleOptions = tracks.map((track: ReferenceSubtitleTrack) => track.lan_doc || '字幕');
      this.referenceSubtitleTrackUrls = tracks.map((track: ReferenceSubtitleTrack) =>
        track.subtitle_url.startsWith('//') ? `https:${track.subtitle_url}` : track.subtitle_url);
    } catch (error) {
      if (token !== this.referenceSubtitleMenuRequest || bvid !== this.vi.bvid || cid !== this.vi.cid || !this.referenceAlive) return;
      this.referenceSubtitleMenuFailed = true;
      logWarn('读取字幕列表失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '字幕列表加载失败' });
    } finally {
      request.destroy();
      if (token === this.referenceSubtitleMenuRequest && bvid === this.vi.bvid && cid === this.vi.cid && this.referenceAlive) this.referenceSubtitleMenuLoading = false;
    }
  }

  private closeLandscapeSubtitlePanel(): void {
    this.referenceSubtitlePanelOpen = false;
    this.ip = false;
    this.cv = true;
    this.resetCT();
  }

  private async referenceSelectSubtitle(index: number, closePanel: boolean = true): Promise<void> {
    const token = ++this.referenceSubtitleSelectionRequest;
    if (index < 0) {
      this.referenceSelectedSubtitleIndex = -1;
      this.referenceSubtitleEnabled = false;
      this.referenceSubtitleText = '';
      this.referenceSubtitleCues = [];
      if (closePanel) this.closeLandscapeSubtitlePanel();
      return;
    }
    const subtitleUrl = this.referenceSubtitleTrackUrls[index];
    if (!subtitleUrl) return;
    const bvid = this.vi.bvid;
    const cid = this.vi.cid;
    const request = http.createHttp();
    this.referenceSubtitleText = '';
    try {
      const response = await request.request(subtitleUrl, {
        method: http.RequestMethod.GET, connectTimeout: 8000, readTimeout: 8000,
        header: { 'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
      });
      if (token !== this.referenceSubtitleSelectionRequest || bvid !== this.vi.bvid || cid !== this.vi.cid || !this.referenceAlive) return;
      if (response.responseCode !== 200) throw new Error(`字幕 HTTP ${response.responseCode}`);
      const body = JSON.parse(response.result as string) as ReferenceSubtitleBody;
      this.referenceSubtitleCues = body.body || [];
      if (this.referenceSubtitleCues.length === 0) {
        logWarn(`[Subtitle] empty track status=${response.responseCode} keys=${Object.keys(body).join(',')}`);
      }
      this.referenceSubtitleEnabled = this.referenceSubtitleCues.length > 0;
      this.referenceSelectedSubtitleIndex = this.referenceSubtitleEnabled ? index : -1;
      if (!this.referenceSubtitleEnabled) this.getUIContext().getPromptAction().showToast({ message: '字幕轨道没有可显示内容' });
      if (closePanel) this.closeLandscapeSubtitlePanel();
    } catch (error) {
      if (token !== this.referenceSubtitleSelectionRequest || bvid !== this.vi.bvid || cid !== this.vi.cid || !this.referenceAlive) return;
      logWarn('加载字幕失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '字幕加载失败，请重试' });
    } finally { request.destroy(); }
  }

  @Builder
  ReferenceLandscapeSubtitlePanel() {
    Stack() {
      Column().width('58%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => this.closeLandscapeSubtitlePanel())
      Stack() { PlaybackControlSurface() {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Text('字幕').fontSize(16).fontColor(this.isDarkMode ? '#FFFFFF' : '#18191C')
                .fontWeight(FontWeight.Medium).layoutWeight(1)
              Stack() { PlaybackGlassAction({ actionHeight: 36, radius: 18, actionId: 'player-bottom-subtitle-done',
                onActivate: () => this.closeLandscapeSubtitlePanel() }) {
                Text('完成').fontSize(14).fontColor('#D34E7E')
              } }.width(72)
            }.width('100%').height(48)
            Column({ space: 8 }) {
              PlaybackGlassAction({ actionHeight: 48, actionId: 'player-bottom-subtitle-off',
                onActivate: () => this.referenceSelectSubtitle(-1) }) {
                Text('关闭字幕').fontSize(14).width('100%').padding({ left: 14, right: 14 })
                  .fontColor(!this.referenceSubtitleEnabled ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
              }
              ForEach(this.referenceSubtitleOptions, (label: string, index: number) => {
                PlaybackGlassAction({ actionHeight: 48, actionId: `player-bottom-subtitle-${index}`,
                  onActivate: () => this.referenceSelectSubtitle(index) }) {
                  Row() {
                    Text(label).fontSize(14).layoutWeight(1)
                      .fontColor(this.referenceSelectedSubtitleIndex === index ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
                    if (this.referenceSelectedSubtitleIndex === index) Image($r('app.media.ref_check')).width(18).height(18)
                  }.width('100%').padding({ left: 14, right: 14 })
                }
              }, (label: string, index: number) => `${index}:${label}`)
              if (this.referenceSubtitleOptions.length === 0) {
                Text('当前视频暂无可用字幕轨道').fontSize(12).fontColor(this.isDarkMode ? '#96999F' : '#61666D')
                  .width('100%').padding({ left: 14, top: 12, bottom: 12 })
              }
            }.width('100%')
            PlaybackMenuRow({ rowWidth: Math.max(0, this.cw * 0.42 - 36), rowId: 'player-bottom-subtitle-large',
              icon: $r('app.media.ref_ps_subtitle'), title: '字幕大字号', isToggle: true, checked: this.referenceSubtitleLarge,
              onToggle: (value: boolean) => { this.referenceSubtitleLarge = value; } })
          }.width('100%').padding({ left: 18, right: 18, top: 24, bottom: 24 })
        }.width('100%').height('100%').scrollBar(BarState.Off)
      } }.width('42%').height('100%').position({ right: 0, top: 0 })
    }.width('100%').height('100%').zIndex(30)
  }

  @Builder
  ReferenceLandscapeDanmakuPanel() {
    Stack() {
      Column().width('56%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => {
          this.referenceLandscapeDanmakuOpen = false;
          this.ip = false;
          this.cv = true;
          this.resetCT();
          this.saveDanmakuDisplaySettings();
        })
      Column() {
        ReferenceDanmakuSettings({
          config: $danmakuConfig,
          onChanged: () => { this.notifyDanmakuSettingsChanged(); },
        })
      }
      .width('44%').height(Math.max(1, this.ch - this.playbackPanelTopInset))
        .position({ right: 0, top: this.playbackPanelTopInset }).id('player-danmaku-panel')
    }.width('100%').height('100%').zIndex(30)
  }

  private async referencePortraitAction(action: string): Promise<void> {
    logInfo(`[ReferencePortrait] action ${action}`);
    if (action === 'close') { this.referenceClosePortraitSettings(); return; }
    if (action === 'feedScope:standard' || action === 'feedScope:all') {
      this.referenceFeedPortraitScaleScope = action === 'feedScope:all' ? 'all' : 'standard';
      this.onPlaybackViewportChanged();
      await this.saveFeedPortraitScaleMode();
      return;
    }
    if (action === 'feedScale:auto' || action === 'feedScale:fill') {
      this.referenceFeedPortraitScaleMode = action === 'feedScale:auto' ? 'auto' : 'fill';
      this.onPlaybackViewportChanged();
      await this.saveFeedPortraitScaleMode();
      return;
    }
    if (action.startsWith('scale:')) {
      const item = this.sl_.find((item: SO) => item.label === action.substring(6));
      if (item) {
        this.sm = item.mode;
        if (this.av) this.av.videoScaleType = this.getVideoScaleType();
        this.updateVideoSize();
        this.saveSM();
        logInfo(`[ReferencePortrait] scale=${this.sm} viewport=${this.referenceMediaWidth()}x${this.referenceMediaHeight()} surface=${this.ovVideoW()}x${this.ovVideoH()}`);
      }
      return;
    }
    if (action === 'copy') { this.referenceCopyLink(); return; }
    if (action.startsWith('share:')) {
      const data = new systemShare.SharedData({ utd: 'general.hyperlink', content: this.referenceVideoLink(), title: this.vi.title });
      this.referenceShareController = new systemShare.ShareController(data);
      try { await this.referenceShareController.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {}); }
      catch (error) { logWarn('打开分享面板失败', error); }
      return;
    }
    if (action === 'cache') { this.referenceClosePortraitSettings(); this.startCacheCurrentVideo(); return; }
    if (action === 'pip') { this.referenceClosePortraitSettings(); this.minimizeToFloating(); return; }
    if (action === 'danmaku') { this.referenceClosePortraitSettings(); this.openDanmakuSettingSheet(); return; }
    if (action === 'dislike') { this.referenceClosePortraitSettings(); this.referenceDislike(); return; }
    if (action === 'watchlater') {
      const cookie = AppStorage.get<string>('biliCookie') || '';
      const csrf = cookie.match(/bili_jct=([^;]+)/)?.[1] || '';
      if (!csrf) { this.getUIContext().getPromptAction().showToast({ message: '请先登录' }); return; }
      const request = http.createHttp();
      try {
        const response = await request.request('https://api.bilibili.com/x/v2/history/toview/add', {
          method: http.RequestMethod.POST,
          header: { 'Cookie': cookie, 'Referer': 'https://www.bilibili.com/', 'Content-Type': 'application/x-www-form-urlencoded' },
          extraData: `bvid=${encodeURIComponent(this.vi.bvid)}&csrf=${encodeURIComponent(csrf)}`
        });
        const result = JSON.parse(response.result as string) as ReferenceActionResult;
        this.getUIContext().getPromptAction().showToast({ message: result.code === 0 ? '已添加到稍后再看' : result.message || '添加失败，请重试' });
      } catch (error) { logWarn('添加稍后再看失败', error); }
      finally { request.destroy(); }
      return;
    }
    if (action === 'report' || action === 'feedback') {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      try { await context.startAbility({ action: 'ohos.want.action.viewData', uri: action === 'report'
        ? `https://www.bilibili.com/appeal/?avid=${this.vd?.aid || 0}` : 'https://www.bilibili.com/blackboard/help.html' }); }
      catch (error) { logWarn('打开反馈页面失败', error); }
    }
  }

  private portraitSettingsHeight(): number {
    return this.isLs || this.fs ? Math.max(1, this.ch - this.playbackPanelTopInset) : this.ch * 0.61;
  }

  @Builder
  ReferencePortraitDrawer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%')
        .hitTestBehavior(this.mp ? HitTestMode.Default : HitTestMode.None)
        .onClick(() => this.referenceClosePortraitSettings())
      ReferencePortraitSettings({ rate: $rt, mode: $referencePlaybackMode, scaleMode: $sm, backgroundEnabled: $bgp,
        open: this.mp,
        bottomQualityAvailable: this.isLs || this.fs,
        bottomPlaybackSettingsAvailable: this.isLs,
        hdrUiRatio: this.hdrUiRatio(),
        feedPortraitScaleMode: $referenceFeedPortraitScaleMode,
        feedPortraitScaleScope: $referenceFeedPortraitScaleScope,
        mirror: $referenceMirrorVideo, subtitle: $referenceSubtitleEnabled,
        subtitleTracks: this.referenceSubtitleOptions, subtitleIndex: this.referenceSelectedSubtitleIndex,
        subtitleLarge: this.referenceSubtitleLarge, subtitleLoading: this.referenceSubtitleMenuLoading,
        subtitleFailed: this.referenceSubtitleMenuFailed,
        onSubtitlePrepare: () => { this.referenceOpenLandscapeSubtitles(true); },
        onSubtitle: (index: number) => { this.referenceSelectSubtitle(index, false); },
        onSubtitleLarge: (large: boolean) => { this.referenceSubtitleLarge = large; },
        quality: this.getQlLabel(this.qn),
        qualitySwitching: this.qs, qualities: this.getQlList(), sleepMinutes: $referenceSleepMinutes,
        stopAtEnd: $referenceStopAtEnd, bottomInset: this.navIndicatorHeight, feedMode: this.referenceFeed,
        onAction: (action: string) => { this.referencePortraitAction(action); },
        onRate: (rate: number) => { logInfo(`[ReferencePortrait] rate ${rate} state=${this.av?.state}`); this.setRate(rate, false); },
        onMode: (mode: string) => { this.referencePlaybackMode = mode; },
        onSleep: (minutes: number) => { logInfo(`[ReferencePortrait] sleep ${minutes}`); this.referenceSetSleep(minutes); },
        onQuality: (quality: number) => { this.switchQ(quality); },
        onToggle: (key: string, enabled: boolean) => {
          logInfo(`[ReferencePortrait] toggle ${key}=${enabled}`);
          if (key === 'background' && this.bgp !== enabled) this.toggleBackgroundPlayback();
          else if (key === 'mirror') this.referenceMirrorVideo = enabled;
          else if (key === 'stopAtEnd') this.referenceStopAtEnd = enabled;
        }
      }).width(this.isLs || this.fs ? this.cw * 0.43 : this.cw).height(this.portraitSettingsHeight())
        .position({ x: this.isLs || this.fs ? this.cw * 0.57 : 0, y: this.ch - this.portraitSettingsHeight() })
        .translate({ x: this.mp ? 0 : (this.isLs || this.fs ? this.cw * 0.43 + 32 : 0),
          y: this.mp ? 0 : (this.isLs || this.fs ? 0 : this.portraitSettingsHeight() + 32) })
    }.width('100%').height('100%')
      .visibility(this.referenceMenuVisibility())
      .hitTestBehavior(this.mp ? HitTestMode.Default : HitTestMode.None)
  }

  @Builder
  ReferenceTopBar() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 16 }) {
        HeaderBackButton({ hdrUiRatio: this.hdrUiRatio(), iconColor: '#FFFFFF', onBack: () => {
          if (this.commentThread) this.closeCommentThread();
          else if (!this.isLs && this.referenceFeedComments) this.referenceSetFeedComments(false);
          else if (!this.isLs && this.referenceFeed) this.referenceSetFeed(false);
          else this.goBack();
        } })
        if (this.isLs || !this.referenceFeed) {
          Column() {
            HeaderGlassControl({ label: '回首页', controlId: 'video-header-home', onActivate: (): void => { this.goHome(); } }) {
              Image($r('app.media.ref_home')).width(22).height(22).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
            }
          }.width(40).height(40)
        }
        Blank()
        if (!this.isLs && this.referenceFeed) {
          Column() {
            HeaderGlassControl({ label: '分享', controlId: 'reference-feed-top-share',
              onActivate: () => { this.referencePortraitAction('share:feed-top'); } }) {
              Image($r('app.media.ref_share')).width(22).height(22).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
            }
          }.width(40).height(40)
        } else if (!this.isLs) {
          Column() {
            HeaderGlassControl({ label: '投屏', controlId: 'video-header-cast' }) {
              Stack() {
                Image($r('app.media.ref_ps_cast')).width(22).height(22).hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
                // Keep the system picker as the actual full-size touch target.
                AVCastPicker({ sessionType: 'video' }).width(40).height(40).opacity(0)
              }.width(40).height(40)
            }
          }.width(40).height(40)
        }
        if (!this.isLs) {
          Column() {
            HeaderGlassControl({ label: '系统小窗', controlId: 'video-header-pip',
              onActivate: () => { this.referencePortraitAction('pip'); } }) {
              Image($r('app.media.ref_pip')).width(22).height(22).hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
            }
          }.width(40).height(40)
        }
        Column() {
          HeaderGlassControl({ label: '更多', controlId: 'video-header-more', onActivate: () => this.referenceOpenPortraitSettings() }) {
            Image($r('app.media.ref_more')).width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio()))
          }
        }.width(40).height(40)
      }.width(this.isLs ? this.ovRectW() : this.cw).height(44).padding({ left: 8, right: 8 })
    }.width(this.isLs ? this.ovRectW() : this.cw).height(44)
      .id('reference-half-screen-top-bar')
      .position({ x: this.isLs ? this.ovRectX() : 0, y: this.referenceSafeTop() }).zIndex(8)
      .visibility((!this.isLs && this.referenceFeed ? !this.referenceInfoHidden : this.cv) && !this.mp ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior((!this.isLs && this.referenceFeed ? !this.referenceInfoHidden : this.cv) && !this.mp ? HitTestMode.Default : HitTestMode.None)
  }

  private referenceFeedChromeHitTest(): HitTestMode {
    // None 只让容器自身透传，子节点仍会命中并截住评论的第二次拖动。
    // 保留信息栏的淡出动画，但让整棵隐藏子树退出触摸测试。
    return this.referenceFeed && !this.referenceFeedComments ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS;
  }

  @Builder
  ReferenceChrome() {
    if (this.referenceFeed) {
      if (this.ar >= 1) {
        Row() {
          Row({ space: 4 }) {
            Image($r('app.media.ref_fullscreen')).width(12).height(12).fillColor('#FFFFFF')
            Text('全屏播放').fontSize(12).fontColor('#FFFFFF')
          }.padding(8).borderRadius(18).backgroundColor('#AA17181A').onClick(() => this.toggleFS())
        }.width('100%').justifyContent(FlexAlign.Center)
          .position({ x: 0, y: this.referenceFullscreenButtonTop() }).zIndex(8)
          .opacity(this.referenceFeedProgress * (1 - this.referenceFeedCommentAmount()))
          .hitTestBehavior(this.referenceFeedChromeHitTest())
      }
      Column({ space: 6 }) {
        if (this.referenceInfoHidden) {
          Row({ space: 10 }) {
          }.width('100%').height(98).alignItems(VerticalAlign.Bottom).padding({ left: 16, bottom: 8 })
        } else {
        this.ReferenceUpRow(true)
        Row() {
          Text(this.vi.title).fontSize(14).fontColor('#FFFFFF').maxLines(2).layoutWeight(1)
          Stack() { Image($r('app.media.ref_chevron_up')).width(16).height(16).fillColor('#FFFFFF') }
            .width(30).height(30).borderRadius(15).backgroundColor('#CC252525')
        }.width('100%').onClick(() => this.referenceSetFeed(false))
        }
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Image(this.play ? $r('app.media.ref_pause') : $r('app.media.ref_play_triangle'))
              .width(22).height(22).fillColor('#FFFFFF')
          }.width(40).height(40).id('feed-play-pause')
            .accessibilityText(this.play ? '暂停' : '播放')
            .onTouch((event: TouchEvent) => event.stopPropagation())
            .onClick(() => this.togglePP())
          Text(`${this.formatDuration(this.ct)} / ${this.formatDuration(this.dur)}`)
            .fontSize(12).fontColor('#EEEEEE').maxLines(1).id('feed-playback-time')
        }.width('100%').height(40)
        Slider({ value: this.ct, min: 0, max: Math.max(1, this.dur), style: SliderStyle.OutSet })
          .trackThickness(2).blockSize({ width: 5, height: 5 }).selectedColor('#D34E7E').blockColor('#D34E7E')
          .trackColor(bufferedTrack(this.bufferedUntil, this.dur, '#45494F'))
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.referenceVerticalSwipe || this.referenceFeedPanOwnsTouch) return;
            this.onSeekBarInteract_(mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving, value);
          }).width('100%').height(20).id('feed-seek-bar')
        Row() {
          Row() {
            // 连刷浮层弹幕输入入口：与评论页输入胶囊同款 capsule 材质、全圆角。
            NativeGlassInput({ inputHeight: 34 }) {
              Row({ space: 10 }) {
                Image($r('app.media.ref_danmaku_checked')).width(23).height(23)
                Rect().width(0.5).height(13).fill('#888888')
                Text('发弹幕').fontSize(13).fontColor('#E7E9EB')
              }.width('100%').height('100%').padding({ left: 12, right: 12 })
                .onClick(() => { this.showDanmakuSheet = true; })
            }
          }.layoutWeight(1).constraintSize({ maxWidth: FEED_DANMAKU_MAX_W })
          // 按钮组固定宽度靠右：输入框吃掉剩余宽度，四个按钮间距不随屏宽变化。
          // 四个图标统一走同族单色 SVG（选中态由 fillColor 染成 #D34E7E），不再混用 APK 的
          // story 位图（那套只有 PNG，墨迹留白 26%，和矢量的 15% 放一起必然一大一小）。
          Row() {
            ReferencePlayerAction({ icon: $r('app.media.ref_like'), label: this.fmtN(this.likeCount), selected: this.isLiked, light: this.referenceFeed, onAction: () => this.toggleLike() })
            ReferencePlayerAction({ icon: $r('app.media.ref_coin'), label: this.fmtN(this.coinCount), selected: this.isCoined, light: this.referenceFeed, onAction: () => this.toggleCoin(1) })
            ReferencePlayerAction({ icon: $r('app.media.ref_favorite'), label: this.fmtN(this.favoriteCount), selected: this.isFavorited, light: this.referenceFeed, onAction: () => this.toggleFavorite() })
            ReferencePlayerAction({ icon: $r('app.media.ref_comment_fill'), label: this.fmtN(this.vd?.stat.reply || 0), selected: false, light: this.referenceFeed, onAction: () => {
              this.referenceSetFeedComments(true);
            } })
          }.width(FEED_ACTION_ITEM_W * 4)
        }.width('100%').justifyContent(FlexAlign.SpaceBetween)
      }.width('100%').height(244 + this.referenceChromeInset()).justifyContent(FlexAlign.End)
        .padding({ left: 8, right: 8, bottom: this.referenceChromeInset() })
        // 与滑入页信息层共用同一套位置计算：提交瞬间两层交接不会错位/跳一下。
        .position({ x: 0, y: this.feedChromeTop() }).zIndex(8)
        .opacity(this.referenceFeedProgress * (1 - this.referenceFeedCommentAmount()))
        .hitTestBehavior(this.referenceFeedChromeHitTest())
        .translate({ y: (1 - this.referenceFeedProgress) * 28 })
        .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 0.5], ['#FF000000', 1]] })
    }
  }
}

// 独立组件的 @Prop 随详情异步返回和连刷切片更新，避免 Builder 值参数保留初始值。
@Component
struct ReferenceIntroStat {
  @Prop icon: Resource = $r('app.media.ref_play');
  @Prop value: string = '—';

  build() {
    Row({ space: 3 }) {
      Image(this.icon).width(13).height(13).fillColor('#757A81')
      Text(this.value).fontSize(10).fontColor('#757A81').maxLines(1)
    }
  }
}

@Component
struct ReferencePlayerAction {
  @Prop icon: Resource = $r('app.media.ref_like');
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop light: boolean = false;
  @Prop intro: boolean = false;
  onAction: () => void = () => {};

  /**
   * 图标光学尺寸。四个按钮的图标都来自同族单色 SVG（墨迹占视图框 85%~91%），同框即可等大；
   * 之前混用 APK 的 story 位图（PNG 墨迹只占 74%，且点赞走 23vp 分支），才会一大一小、
   * 还因 Column 内容高度不同把四个数字基线错开约 5vp。
   * 简介统计行（intro，5 个入口）保持 22vp。
   */
  private actionIconSize(): number {
    return this.intro ? 22 : 32;
  }

  build() {
    Column({ space: this.intro ? 8 : 6 }) {
      // Contain：评论气泡是 38×37 的非正方形视图框，Cover 会裁掉一条边。
      Image(this.icon).width(this.actionIconSize()).height(this.actionIconSize())
        .objectFit(ImageFit.Contain)
        .fillColor(this.selected ? '#D34E7E' : (this.light ? '#FFFFFF' : '#A2A7AE'))
      Text(this.label).fontSize(10).fontColor(this.selected ? '#D34E7E' : (this.light ? '#FFFFFF' : '#A2A7AE')).maxLines(1)
    }.layoutWeight(1).height(this.intro ? 54 : 58).justifyContent(FlexAlign.Center).onClick(this.onAction)
  }
}
