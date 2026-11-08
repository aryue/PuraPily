import { FollowGlassButton } from '../components/FollowGlassButton';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { NativeGlassInput } from '../components/NativeGlassInput';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { ChannelCardSurface } from '../components/ChannelCardSurface';
import { ordinaryCardColor } from '../utils/SurfaceColors';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { cardItemBg } from '../utils/CardStyle';
import { PageHeader } from '../components/PageHeader';
import { PageSurface } from '../components/PageSurface';
import { PageWallpaper } from '../components/PageWallpaper';
import { FloatingVideoTransition } from '../services/FloatingVideoTransition';
import { VideoListItem } from '../components/VideoListItem';
// UpSpacePage.ets — UP主个人空间页
import { router, mediaquery, window } from '@kit.ArkUI';
import { GlassMaterial } from '../utils/GlassMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { VideoCardMoreButton } from '../components/VideoCardMoreButton';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { FullImagePreview } from '../components/FullImagePreview';
import { getUserSpaceVideos, UpSpaceInfo, UpRelationStat, UpSpaceVideoItem, modifyFollow, clearFollowedMidsCache, getUpSpaceInitData, UpSpaceImages, resolveSpaceHeaderImage, blacklistUploader, unblacklistUploader, getUpSpaceDynamics, SpaceDynamicItem, DynVideoInfo, DynImageInfo, DynCommonInfo, DynTextSegment, prefetchVideoPlayback } from '../api/BilibiliApi';

/** 图片网格四角圆角参数（与动态页同款） */
interface DynCornerRadius {
  topLeft?: number;
  topRight?: number;
  bottomLeft?: number;
  bottomRight?: number;
}

/** 动态类型常量 */
const DYN_TYPE_AV: string = 'DYNAMIC_TYPE_AV';
const DYN_TYPE_DRAW: string = 'DYNAMIC_TYPE_DRAW';
const DYN_TYPE_FORWARD: string = 'DYNAMIC_TYPE_FORWARD';
const DYN_TYPE_WORD: string = 'DYNAMIC_TYPE_WORD';

/** 排序选项 */
interface OrderOption {
  key: string;
  label: string;
}

const ORDER_OPTIONS: OrderOption[] = [
  { key: 'pubdate', label: '最新发布' },
  { key: 'click', label: '最多播放' },
  { key: 'stow', label: '最多收藏' }
];

/**
 * 图片 URL 追加压缩参数（hdslb 图床）：列表加载缩略图，避免直接解码原图导致内存峰值过高闪退
 * （与 CommentContentRenderer.resizeImageUrl 一致；原图仅全屏预览时使用）
 */
function resizeImageUrl(url: string, width: number): string {
  if (!url || !url.includes('hdslb.com')) {
    return url;
  }
  // ⚠️ 原实现 `!url.includes('@')`：URL 已带后缀（动态/OPUS 图常见）时**整段跳过压缩** → 原图整张解码
  const at: number = url.indexOf('@');
  const base: string = (at > url.lastIndexOf('/') && url.indexOf('?') < 0) ? url.substring(0, at) : url;
  return base + `@${width}w`;
}

/** 格式化播放数：万单位 */
function fmtN(n: number): string {
  // ⭐ 兜底：接口个别投稿缺 play/danmaku 等字段（undefined 会直接崩）
  const v: number = n || 0;
  if (v >= 10000) return (v / 10000).toFixed(1) + '万';
  return v.toString();
}

/** 格式化时长：秒 → mm:ss / h:mm:ss */
function fmtDuration(sec: number): string {
  if (!Number.isFinite(sec) || sec <= 0) return '';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  if (m >= 60) {
    const h = Math.floor(m / 60);
    return `${h}:${String(m % 60).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
  }
  return `${m}:${String(s).padStart(2, '0')}`;
}

/** 格式化发布时间戳 → 相对时间 */
function fmtPubdate(ts: number): string {
  const t: number = ts || 0;
  const now = Math.floor(Date.now() / 1000);
  const diff = now - t;
  if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
  if (diff < 2592000) return `${Math.floor(diff / 86400)}天前`;
  if (diff < 31536000) return `${Math.floor(diff / 2592000)}个月前`;
  return `${Math.floor(diff / 31536000)}年前`;
}

@Entry
@Component({ freezeWhenInactive: true })
struct UpSpacePage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  // 路由参数
  @State mid: number = 0;
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.videos = this.videos.filter(item => !VideoCardFeedback.isDismissed(item.bvid, String(this.mid)));
    this.videoPairs = this.buildVideoGroups(this.videos, 2);
    this.videoTriples = this.buildVideoGroups(this.videos, 3);
  }
  @State upName: string = '';
  @State upFace: string = '';

  // 加载状态
  @State isInfoLoaded: boolean = false;
  @State initialSpaceReady: boolean = false;
  @State isListLoaded: boolean = false;
  @State loadError: string = '';

  // UP主信息
  @State spaceInfo: UpSpaceInfo | null = null;
  @State spaceImages: UpSpaceImages | null = null;
  @State loadedSpaceHeaderImage: string = '';
  @State relationStat: UpRelationStat | null = null;

  // 视频列表
  @State videos: UpSpaceVideoItem[] = [];
  @State videoPairs: UpSpaceVideoItem[][] = []; // A1 竖屏 2 列网格：两两分组
  @State videoTriples: UpSpaceVideoItem[][] = []; // A1 横屏 3 列网格：三三分组
  @State currentPage: number = 1;
  @State totalCount: number = -1; // -1 表示尚未取得统计，不能冒充真实的零投稿
  @State hasMore: boolean = true;
  @State isLoadingMore: boolean = false;
  @State order: string = 'pubdate'; // 排序：pubdate最新/click播放/stow收藏

  // 动态列表
  @State dynamics: SpaceDynamicItem[] = [];
  @State dynOffset: string = '';
  @State dynHasMore: boolean = false;
  @State dynLoading: boolean = false;
  @State isDynLoaded: boolean = false;

  // Tab：home=主页 / dynamic=动态 / video=投稿
  @State activeTab: string = 'video';
  @State spaceSearchOpen: boolean = false;
  @State spaceSearchText: string = '';
  @State spaceSearchKeyword: string = '';
  @State spaceSearchVideos: UpSpaceVideoItem[] = [];
  @State spaceSearchDynamics: SpaceDynamicItem[] = [];
  @State spaceSearchLoading: boolean = false;
  @State spaceSearchHasMore: boolean = false;
  @State spaceSearchError: string = '';
  @State spaceViewportWidth: number = 400;
  @StorageLink('da') spaceDisableAnimations: boolean = false;
  private spaceSearchVersion: number = 0;
  private spaceSearchPage: number = 0;
  private spaceSearchDynamicPage: number = 0;
  private spaceSearchVideoHasMore: boolean = false;
  private spaceSearchDynamicHasMore: boolean = false;
  private spaceSearchOffset: string = '';
  private spaceSearchScroller: Scroller = new Scroller();
  private spaceSearchInputController: TextInputController = new TextInputController();
  @State spaceTabIndex: number = 2;
  @State spaceTabProgress: number = 2;
  @State spaceTabBarWidth: number = 0;
  @State spaceViewportHeight: number = 800;
  private spacePager: SwiperController = new SwiperController();
  private spaceHeaderScroller: Scroller = new Scroller();
  private submissionScroller: Scroller = new Scroller();
  @State receivedLikes: number | null = null;
  @State detailsExpanded: boolean = false;

  // 样式状态
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @StorageProp('otherCardGlassEnabled') otherCardGlassEnabled: boolean = true;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('wallpaper') wallpaper: string = 'default';
  @StorageLink('customWallpaper') customWallpaper: string = '';
  @StorageLink('wallpaperBlur') wallpaperBlur: number = 0;
  @StorageLink('wallpaperDarkness') wallpaperDarkness: number = 50;
  // ⭐ 卡片样式（与动态页/首页一致）
  @StorageLink('cardListBorderRadius') cardListBorderRadius: number = 12;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 15;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = true;
  // ⭐ 首页同款卡片间距（个性化页"首页样式 → 卡片间距"滑块；页面级左右边距/卡片间隔统一走它）
  @StorageLink('cardListMargin') cardListMargin: number = 12;
  // ⭐ 图片全屏预览状态（动态图文同款 FullImagePreview）
  @State showPreview: boolean = false;
  @State previewImageUrls: string[] = [];
  @State previewThumbIds: string[] = [];
  @State previewIndex: number = 0;
  @State previewOriginX: number = 0;
  @State previewOriginY: number = 0;
  @State previewOriginW: number = 0;
  @State previewOriginH: number = 0;
  @State isLandscape: boolean = false;
  // ⭐ 状态栏高度走 EntryAbility 维护的全局值（vp，0=隐藏/横屏；本页自测 getWindowAvoidArea 实测会拿到 0）
  @StorageLink('statusBarHeight') statusBarHeight: number = 40;
  // ⭐ 关注状态
  @State isFollowed: boolean = false;
  // 下拉刷新
  @State isRefreshing: boolean = false;
  // 黑名单状态（简化：本地记录，菜单文案切换）
  @State isBlacklisted: boolean = false;
  // 媒体查询监听器（方向变化，与 HomePage 相同方案）
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  private isPageActive: boolean = false;
  // ⭐ A1 页眉吸顶：列表滚动器 + 页眉实测高度（onAreaChange）+ 吸顶开关（仅竖屏用）
  private videoScroller: Scroller = new Scroller();
  private dynScroller: Scroller = new Scroller();
  @State headerH: number = 0;
  @State videoSticky: boolean = false;
  @State dynSticky: boolean = false;
  // 节标题行实测高度（onAreaChange）：吸顶期间列表内本行用同高占位隐藏，防布局跳动
  @State secRowH: number = 0;
  // 沉浸光感分段胶囊的玻璃条高（官方 SegmentButton 内在高 ~40.5，回归官方比例）；
  // 内容 34 居中、上下各 3vp 对称余量——系统内缩（~3vp，在哪侧未知）最多造成 1vp 视觉偏差
  @State segBarH: number = 40;

  async aboutToAppear(): Promise<void> {
    this.isPageActive = true;
    // 获取路由参数
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      this.mid = (params['mid'] as number) || 0;
      this.upName = (params['upName'] as string) || '';
      this.upFace = (params['upFace'] as string) || '';
    }
    // 状态栏高度由 @StorageLink('statusBarHeight') 提供（EntryAbility 维护）；
    // 但全局值可能被"全屏播放退出 / 上次横屏持久化"等路径留成 0（状态栏其实可见）⇒ 竖屏进页时按 SearchPage 同口径自愈一次
    this.refreshStatusBarHeight();
    this.listenOrientationChange();
    // 加载数据
    await this.loadAllData();
  }

  aboutToDisappear(): void {
    this.isPageActive = false;
    this.spaceSearchVersion++;
    this.spaceSearchLoading = false;
    // 移除媒体查询监听
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  /** 注册媒体查询监听（方向变化，与 HomePage 相同方案） */
  private listenOrientationChange(): void {
    const mediaQuery = this.getUIContext().getMediaQuery();
    this.landscapeListener = mediaQuery.matchMediaSync('(orientation: landscape)');
    // 初始方向
    this.isLandscape = this.landscapeListener.matches;
    this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      if (!this.isPageActive) return;
      const newIsLandscape = result.matches;
      if (this.isLandscape !== newIsLandscape) {
        logInfo(`[UpSpacePage] 方向变化: ${newIsLandscape ? '横屏' : '竖屏'}`);
        this.isLandscape = newIsLandscape;
            if (!newIsLandscape) {
          // 横转竖：全局状态栏高度在横屏期间为 0，转回竖屏后自愈一次
          this.refreshStatusBarHeight();
        }
      }
    });
  }

  /**
   * 竖屏时刷新全局状态栏高度（与 SearchPage 同口径：getLastWindow + TYPE_SYSTEM 避让区）。
   * 仅测得 >0 才写 AppStorage——横屏/隐藏态测到 0 不写，避免把好值冲掉。
   */
  private async refreshStatusBarHeight(): Promise<void> {
    if (this.isLandscape) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      const avoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const realHeight = this.getUIContext().px2vp(avoidArea.topRect.height);
      if (realHeight > 0 && realHeight !== this.statusBarHeight) {
        AppStorage.set('statusBarHeight', realHeight);
      }
    } catch (_) {}
  }

  private async loadAllData(): Promise<void> {
    if (!this.mid) {
      this.loadError = '用户ID无效';
      return;
    }
    this.loadError = '';
    // 并行加载：UP主信息 + 视频列表 同时发起（无节流延迟）
    await Promise.all([
      this.loadProfileData(),
      this.loadVideos(1)
    ]);
    if (!this.isPageActive || this.initialSpaceReady) return;
    if (!this.spaceInfo) {
      this.loadError = '资料加载失败，点击重试';
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      this.initialSpaceReady = true;
    });
  }

  private async loadProfileData(): Promise<void> {
    try {
      const result = await getUpSpaceInitData(this.mid);
      if (result.info) {
        this.spaceInfo = result.info;
        this.upName = result.info.name;
        this.upFace = result.info.face;
      }
      this.spaceImages = result.images;
      this.relationStat = result.relation;
      this.receivedLikes = result.likes;
      this.isFollowed = result.isFollowed;
      logInfo(`[UpSpacePage] 统计 fans=${result.relation?.follower}, following=${result.relation?.following}, likes=${result.likes}, location=${!!result.info?.ip_location}`);
      logInfo(`[UpSpacePage] 并行加载完成: info=${result.info !== null}, relation=${result.relation !== null}, isFollowed=${result.isFollowed}`);
    } catch (err) {
      logError(`[UpSpacePage] 加载UP主信息失败: ${err}`);
    } finally {
      this.isInfoLoaded = true;
    }
  }

  private async loadVideos(page: number): Promise<void> {
    if (this.isLoadingMore) return;
    this.isLoadingMore = true;
    try {
      const result = await getUserSpaceVideos(this.mid, page, 30, this.order);
      if (result) {
        if (page === 1) {
          this.videos = result.list.vlist || [];
          this.videoPairs = this.buildVideoGroups(this.videos, 2);
          this.videoTriples = this.buildVideoGroups(this.videos, 3);
          logInfo(`[UpSpacePage] loadVideos page=1: videos.length=${this.videos.length}, totalCount=${result.page.count}`);
          // 打印第一个视频信息确认
          if (this.videos.length > 0) {
            logInfo(`[UpSpacePage] 第一个视频: bvid=${this.videos[0].bvid}, title=${this.videos[0].title}`);
          }
        } else {
          this.videos = [...this.videos, ...(result.list.vlist || [])];
          this.videoPairs = this.buildVideoGroups(this.videos, 2);
          this.videoTriples = this.buildVideoGroups(this.videos, 3);
        }
        this.totalCount = Math.max(result.page.count || 0, this.videos.length);
        this.currentPage = page;
        this.hasMore = this.videos.length < this.totalCount;
      } else {
        if (page === 1) {
          this.loadError = '加载视频列表失败';
        }
      }
    } catch (err) {
      logError(`[UpSpacePage] 加载视频列表失败: ${err}`);
      if (page === 1) {
        this.loadError = '网络错误，请稍后重试';
      }
    } finally {
      this.isListLoaded = true;
      this.isLoadingMore = false;
    }
  }

  private loadMore(): void {
    if (this.hasMore && !this.isLoadingMore) {
      this.loadVideos(this.currentPage + 1);
    }
  }

  /** 切换排序：重置视频列表并重新加载 */
  private switchOrder(newOrder: string): void {
    if (newOrder === this.order) return;
    this.order = newOrder;
    this.videos = [];
    this.videoPairs = [];
    this.videoTriples = [];
    this.currentPage = 1;
    this.hasMore = true;
    this.isListLoaded = false;
    this.loadError = '';
    this.loadVideos(1);
  }

  /** 加载动态列表（offset 游标分页） */
  private async loadDynamics(offset: string): Promise<void> {
    if (this.dynLoading) return;
    this.dynLoading = true;
    try {
      const result = await getUpSpaceDynamics(this.mid, offset);
      if (result) {
        if (!offset) {
          this.dynamics = result.items;
        } else {
          this.dynamics = [...this.dynamics, ...result.items];
        }
        this.dynOffset = result.offset;
        this.dynHasMore = result.hasMore;
        logInfo(`[UpSpacePage] 动态加载: items=${result.items.length}, hasMore=${result.hasMore}`);
      }
    } catch (err) {
      logError(`[UpSpacePage] 加载动态失败: ${err}`);
    } finally {
      this.dynLoading = false;
      this.isDynLoaded = true;
    }
  }

  /** 动态触底加载更多 */
  private loadMoreDynamics(): void {
    if (this.dynHasMore && !this.dynLoading) {
      this.loadDynamics(this.dynOffset);
    }
  }

  /** 点击与拖动共用原生分页器，保留推出页和推进页的连续运动。 */
  private switchTab(tab: string): void {
    const index = ['home', 'dynamic', 'video'].indexOf(tab);
    if (index < 0 || index === this.spaceTabIndex) return;
    if (index === 1 && !this.isDynLoaded && !this.dynLoading) this.loadDynamics('');
    this.spacePager.changeIndex(index, true);
  }

  private settleSpaceTab(index: number): void {
    this.spaceTabIndex = index;
    this.activeTab = ['home', 'dynamic', 'video'][index];
    if (index === 1 && !this.isDynLoaded && !this.dynLoading) this.loadDynamics('');
  }

  private spaceTabColor(index: number): string {
    const weight = Math.max(0, 1 - Math.abs(this.spaceTabProgress - index));
    const base = this.isDarkMode ? [201, 204, 208] : [97, 102, 109];
    const accent = [251, 114, 153];
    return '#' + base.map((value: number, channel: number) =>
      Math.round(value + (accent[channel] - value) * weight).toString(16).padStart(2, '0')).join('');
  }

  /** 从动态视频卡片跳转播放 */
  private playDynVideo(video: DynVideoInfo | null): void {
    if (!video || !video.bvid) {
      this.getUIContext().getPromptAction().showToast({ message: '无法播放该动态视频', duration: 1500 });
      return;
    }
    // ⭐ 预热详情（fire-and-forget）：把加载 cid 的 RTT 藏进转场+播放器初始化
    prefetchVideoPlayback(video.bvid, 0, AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: video.bvid,
        title: video.title,
        coverUrl: video.cover,
        cid: 0
      }
    });
  }

  /** 将视频列表按每行 size 个分组（A1 网格：竖屏 2 列 / 横屏 3 列） */
  private buildVideoGroups(videos: UpSpaceVideoItem[], size: number): UpSpaceVideoItem[][] {
    const groups: UpSpaceVideoItem[][] = [];
    for (let i: number = 0; i < videos.length; i += size) {
      groups.push(videos.slice(i, Math.min(i + size, videos.length)));
    }
    return groups;
  }

  private goBack(): void {
    if (this.spaceSearchOpen) { this.closeSpaceSearch(); return; }
    router.back();
  }

  onBackPress(): boolean {
    if (this.showPreview) { this.showPreview = false; return true; }
    if (this.spaceSearchOpen) { this.closeSpaceSearch(); return true; }
    return false;
  }

  private openSpaceSearch(): void {
    this.resetSpaceSearch();
    this.spaceSearchText = '';
    this.getUIContext().animateTo({ duration: this.spaceDisableAnimations ? 0 : 300,
      curve: Curve.FastOutSlowIn }, () => { this.spaceSearchOpen = true; });
  }

  private closeSpaceSearch(): void {
    this.spaceSearchInputController.stopEditing();
    this.spaceSearchVersion++;
    this.spaceSearchLoading = false;
    this.getUIContext().animateTo({ duration: this.spaceDisableAnimations ? 0 : 300,
      curve: Curve.FastOutSlowIn }, () => { this.spaceSearchOpen = false; });
  }

  private resetSpaceSearch(): void {
    this.spaceSearchVersion++;
    this.spaceSearchKeyword = '';
    this.spaceSearchVideos = [];
    this.spaceSearchDynamics = [];
    this.spaceSearchPage = 0;
    this.spaceSearchDynamicPage = 0;
    this.spaceSearchVideoHasMore = false;
    this.spaceSearchDynamicHasMore = false;
    this.spaceSearchOffset = '';
    this.spaceSearchHasMore = false;
    this.spaceSearchLoading = false;
    this.spaceSearchError = '';
  }

  private submitSpaceSearch(): void {
    this.spaceSearchInputController.stopEditing();
    const keyword = this.spaceSearchText.trim();
    this.resetSpaceSearch();
    this.spaceSearchKeyword = keyword;
    this.spaceSearchScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    if (keyword) {
      this.spaceSearchHasMore = true;
      this.spaceSearchVideoHasMore = true;
      this.spaceSearchDynamicHasMore = true;
      void this.loadSpaceSearch();
    }
  }

  private async loadSpaceSearch(): Promise<void> {
    if (!this.spaceSearchOpen || this.spaceSearchLoading || !this.spaceSearchHasMore || !this.spaceSearchKeyword) return;
    const version = this.spaceSearchVersion;
    const keyword = this.spaceSearchKeyword;
    this.spaceSearchLoading = true;
    this.spaceSearchError = '';
    try {
      const errors = await Promise.all([
        this.loadSpaceSearchVideos(version, keyword),
        this.loadSpaceSearchDynamics(version, keyword)
      ]);
      if (version !== this.spaceSearchVersion) return;
      this.spaceSearchError = errors.filter((message: string) => message.length > 0).join('\n');
      this.spaceSearchHasMore = this.spaceSearchVideoHasMore || this.spaceSearchDynamicHasMore;
    } finally {
      if (version === this.spaceSearchVersion) this.spaceSearchLoading = false;
    }
  }

  private async loadSpaceSearchVideos(version: number, keyword: string): Promise<string> {
    if (!this.spaceSearchVideoHasMore) return '';
    try {
        const page = this.spaceSearchPage + 1;
        const result = await getUserSpaceVideos(this.mid, page, 30, 'pubdate', keyword);
        if (version !== this.spaceSearchVersion) return '';
        if (!result) throw new Error('视频搜索失败，请重试');
        const seen = new Set<string>(this.spaceSearchVideos.map((item: UpSpaceVideoItem) => item.bvid));
        this.spaceSearchVideos = [...this.spaceSearchVideos, ...result.list.vlist.filter((item: UpSpaceVideoItem) => !seen.has(item.bvid))];
        this.spaceSearchPage = page;
        this.spaceSearchVideoHasMore = result.list.vlist.length > 0 && page * 30 < result.page.count;
        return '';
    } catch (error) {
      return errMsg(error);
    }
  }

  private async loadSpaceSearchDynamics(version: number, keyword: string): Promise<string> {
    if (!this.spaceSearchDynamicHasMore) return '';
    try {
      const offset = this.spaceSearchOffset;
      const page = this.spaceSearchDynamicPage + 1;
      const result = await getUpSpaceDynamics(this.mid, offset, keyword, page);
      if (version !== this.spaceSearchVersion) return '';
      if (!result) throw new Error('动态搜索失败，请重试');
      const seen = new Set<string>(this.spaceSearchDynamics.map((item: SpaceDynamicItem) => item.idStr));
      this.spaceSearchDynamics = [...this.spaceSearchDynamics,
        ...result.items.filter((item: SpaceDynamicItem) => !seen.has(item.idStr))];
      this.spaceSearchDynamicPage = page;
      this.spaceSearchOffset = result.offset;
      this.spaceSearchDynamicHasMore = result.hasMore && result.offset.length > 0 && result.offset !== offset;
      return '';
    } catch (error) {
      return errMsg(error);
    }
  }

  private playVideo(item: UpSpaceVideoItem): void {
    // ⭐ 预热详情（fire-and-forget）：把加载 cid 的 RTT 藏进转场+播放器初始化
    prefetchVideoPlayback(item.bvid, 0, AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: item.bvid,
        title: item.title,
        coverUrl: item.pic,
        cid: 0
      }
    });
  }

  // ⭐ 切换关注状态
  private async toggleFollow(): Promise<void> {
    if (!this.spaceInfo) return;
    const newIsFollowed = !this.isFollowed;
    const success = await modifyFollow(this.mid, newIsFollowed ? 1 : 2);
    if (success) {
      this.isFollowed = newIsFollowed;
      clearFollowedMidsCache();
      this.getUIContext().getPromptAction().showToast({ message: newIsFollowed ? '关注成功' : '取消关注', duration: 1500 });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 1500 });
    }
  }

  /** 打开私信（跟UP主聊天） */
  private openWhisper(): void {
    try {
      const cookie = AppStorage.get<string>('biliCookie') || '';
      if (!cookie.includes('SESSDATA')) {
        this.getUIContext().getPromptAction().showToast({ message: '请先登录', duration: 1500 });
        return;
      }
      router.pushUrl({
        url: 'pages/WhisperDetailPage',
        params: {
          'talkerId': this.mid,
          'name': this.spaceInfo?.name ?? this.upName,
          'face': this.spaceInfo?.face ?? this.upFace
        }
      });
    } catch (err) {
      logError(`[UpSpacePage] openWhisper 失败: ${errMsg(err)}`);
    }
  }

  /** 下拉刷新：按当前 Tab 刷新 */
  private async onRefresh(): Promise<void> {
    try {
      if (this.activeTab !== 'dynamic') {
        this.order = 'pubdate';
        this.videos = [];
        this.videoPairs = [];
        this.videoTriples = [];
        this.currentPage = 1;
        this.hasMore = true;
        this.isListLoaded = false;
        this.loadError = '';
        await Promise.all([
          this.loadProfileData(),
          this.loadVideos(1)
        ]);
      } else {
        this.dynamics = [];
        this.dynOffset = '';
        this.dynHasMore = false;
        this.isDynLoaded = false;
        await this.loadDynamics('');
      }
    } finally {
      this.isRefreshing = false;
    }
  }

  /** 加入/移除黑名单 */
  private async toggleBlacklist(): Promise<void> {
    try {
      const ok = this.isBlacklisted ? await unblacklistUploader(this.mid) : await blacklistUploader(this.mid);
      if (ok) {
        this.isBlacklisted = !this.isBlacklisted;
        this.getUIContext().getPromptAction().showToast({ message: this.isBlacklisted ? '已加入黑名单' : '已移除黑名单', duration: 1500 });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 1500 });
      }
    } catch (err) {
      logError(`[UpSpacePage] 黑名单操作失败: ${err}`);
      this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 1500 });
    }
  }

  /** 复制用户名 */
  private async copyUpName(): Promise<void> {
    const name = this.spaceInfo?.name ?? this.upName;
    if (!name) return;
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, name);
      await pasteboard.getSystemPasteboard().setData(data);
      this.getUIContext().getPromptAction().showToast({ message: '已复制用户名', duration: 1500 });
    } catch (err) {
      logError(`[UpSpacePage] 复制失败: ${err}`);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1500 });
    }
  }

  /** 更多操作菜单 */
  private showMoreMenu(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: '更多操作',
      buttons: [
        { text: '复制用户名', color: this.isDarkMode ? '#E5E5E5' : '#333333' },
        { text: this.isBlacklisted ? '移除黑名单' : '加入黑名单', color: '#FF4444' }
      ]
    }).then((result) => {
      const idx = result.index;
      if (idx === 0) {
        this.copyUpName();
      } else if (idx === 1) {
        this.toggleBlacklist();
      }
    }).catch((_err: Error) => {
      // 用户取消菜单，忽略
    });
  }

  /** 明暗效果层（全局壁纸暗化/亮化：wallpaperDarkness <50 压黑，>50 提白） */
  @Builder
  wallpaperDarknessLayer() {
    if (this.wallpaperDarkness < 50) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(`rgba(0, 0, 0, ${(50 - this.wallpaperDarkness) / 50})`)
    } else if (this.wallpaperDarkness > 50) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(`rgba(255, 255, 255, ${(this.wallpaperDarkness - 50) / 50})`)
    }
  }

  /** 下拉刷新指示器（非刷新态显示静态箭头，仅刷新时转圈，避免 LoadingProgress 常驻动画） */
  @Builder
  customRefreshComponent() {
    Stack() {
      Column() {
        if (this.isRefreshing) {
          LoadingProgress()
            .width(26).height(26)
            .color(this.customThemeColor)
        } else {
          Text('↓')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.customThemeColor)
        }
        Text('下拉刷新')
          .fontSize(12)
          .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
          .margin({ top: 6 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 12, bottom: 12 })
    }
    .width('100%')
  }

  pageTransition() {
    if (FloatingVideoTransition.active()) {
      PageTransitionEnter({ duration: FloatingVideoTransition.direction === 'minimize' ? 0 : FloatingVideoTransition.DURATION }).opacity(1)
      PageTransitionExit({ duration: FloatingVideoTransition.DURATION }).opacity(1)
    }
  }

  build() {
    Stack() {
      PageWallpaper()
    Stack({ alignContent: Alignment.TopStart }) {
      // ── 背景层：全局壁纸（默认壁纸分深/浅模式；与搜索页等其余页面同款三分支）──
      if (this.pageWallpaperEnabled) {
      // Shared non-player wallpaper is rendered beneath the page.
    } else if (this.wallpaper === 'builtin') {
        Stack() {
          Image(this.isDarkMode ? $r('app.media.wallpaper_shen') : $r('app.media.wallpaper_qian'))
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      } else if (this.wallpaper === 'custom' && this.customWallpaper) {
        Stack() {
          Image('file://' + this.customWallpaper)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
            .blur(this.wallpaperBlur)
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      } else {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor(this.paperBg())
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      }

      Stack({ alignContent: Alignment.TopStart }) {
        if (this.initialSpaceReady) {
          Stack({ alignContent: Alignment.TopStart }) {
      if (this.isLandscape) {
        Row() {
          this.railSection()
          Column() {
            this.sectionRow(0, 0)
            this.spaceTabPager()
          }.layoutWeight(1).height('100%')
        }.width('100%').height('100%')
          .padding({ top: this.statusBarHeight })
      } else {
        // 共用可折叠资料区，三页只横向推拉内容；列表通过嵌套滚动收起/展开资料区。
        Scroll(this.spaceHeaderScroller) {
          Column() {
            this.spaceHeader()
            this.sectionRow(0, 0)
            this.spaceTabPager()
          }.width('100%')
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onDidScroll(() => {
            this.videoSticky = this.spaceHeaderScroller.currentOffset().yOffset >=
              Math.max(0, this.headerH - this.statusBarHeight - 44) - 1;
          })
        Column() { this.spaceToolbar() }.width('100%')
      }

          }.width('100%').height('100%')
            .transition(TransitionEffect.OPACITY)
        } else {
          Column({ space: 12 }) {
            if (!this.loadError) {
              LoadingProgress().width(28).height(28).color(this.customThemeColor)
            }
            Text(this.loadError || '加载中…').fontSize(13).fontColor(this.muted())
              .onClick(() => { if (this.loadError) this.loadAllData(); })
          }.width('100%').height('100%').justifyContent(FlexAlign.Center)
            .transition(TransitionEffect.OPACITY)
            .id('space-initial-loading')
          Column() { this.spaceToolbar() }.width('100%')
        }
      }.width('100%').height('100%')
        .translate({ x: this.spaceSearchOpen ? -this.spaceViewportWidth : 0 })
        .hitTestBehavior(this.spaceSearchOpen ? HitTestMode.None : HitTestMode.Default)

    if (this.spaceSearchOpen) {
      this.spaceSearchPanel()
    }

    // ⭐ 图片全屏预览（与动态页同款：一镜到底飞入、左右滑动切图）
    FullImagePreview({
      isShow: $showPreview,
      previewUrls: this.previewImageUrls,
      thumbIds: this.previewThumbIds,
      initialIndex: this.previewIndex,
      originX: $previewOriginX,
      originY: $previewOriginY,
      originW: $previewOriginW,
      originH: $previewOriginH,
      immersiveMode: this.isLandscape
    })
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
  .width('100%').height('100%')
  .backgroundColor(Color.Transparent)
  .alignContent(Alignment.TopStart)
  .onAreaChange((_old: Area, area: Area) => {
    this.spaceViewportHeight = Number(area.height);
    this.spaceViewportWidth = Number(area.width);
  });
}

  private spaceHeaderImage(): string {
    return resolveSpaceHeaderImage(this.spaceImages, this.isDarkMode, this.spaceInfo?.top_photo || '');
  }

  private hasLoadedSpaceHeaderImage(): boolean {
    const imageUrl = this.spaceHeaderImage();
    return imageUrl.length > 0 && this.loadedSpaceHeaderImage === imageUrl;
  }

  @Builder
  spaceSearchPanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 共用空间已显示的壁纸，避免搜索推入时重新加载图片而闪出纯色背景。
      List({ space: 8, scroller: this.spaceSearchScroller }) {
        ListItem() { Column().height(this.statusBarHeight + 96).width('100%') }
        if (!this.spaceSearchKeyword) {
          ListItem() { Text('搜索此 UP 的视频和动态').fontSize(14).fontColor(this.muted()).padding(24) }
        } else {
          if (this.spaceSearchVideos.length > 0) {
            ListItem() { Text('视频').fontSize(15).fontColor(this.ink()).padding({ left: 14, top: 8, bottom: 4 }) }
            ForEach(this.spaceSearchVideos, (item: UpSpaceVideoItem) => {
              ListItem() { this.submissionVideoRow(item) }
            }, (item: UpSpaceVideoItem) => 'space-search-' + item.bvid)
          }
          if (this.spaceSearchDynamics.length > 0) {
            ListItem() { Text('动态').fontSize(15).fontColor(this.ink()).padding({ left: 14, top: 8, bottom: 4 }) }
            ForEach(this.spaceSearchDynamics, (item: SpaceDynamicItem) => {
              ListItem() {
                Row() { this.dynamicCard(item) }.width('100%').padding({ left: 14, right: 14 })
              }
            }, (item: SpaceDynamicItem) => 'space-search-' + item.idStr)
          }
          ListItem() {
            Column({ space: 12 }) {
              if (this.spaceSearchLoading) {
                LoadingProgress().width(28).height(28).color(this.customThemeColor)
                Text('正在搜索视频和动态…')
                  .fontSize(13).fontColor(this.muted())
              } else if (this.spaceSearchError) {
                Text(this.spaceSearchError).fontSize(13).fontColor(this.muted())
                Button('重试').onClick(() => { void this.loadSpaceSearch(); })
              } else if (this.spaceSearchHasMore) {
                Button('加载更多')
                  .onClick(() => { void this.loadSpaceSearch(); })
              } else {
                Text(this.spaceSearchVideos.length + this.spaceSearchDynamics.length === 0
                  ? '没有找到相关内容' : '已显示全部结果').fontSize(13).fontColor(this.muted())
              }
            }.width('100%').padding(24)
          }
        }
        ListItem() { Column().height(32) }
      }.width('100%').height('100%').scrollBar(BarState.Off)
        .id('space-search-results')
      PageHeader({ withTabs: false, scopeId: 'space-search-header' }) {
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            HeaderBackButton({ onBack: () => this.closeSpaceSearch() })
            Column() {
              NativeGlassInput({ inputHeight: 40 }) {
                TextInput({ text: this.spaceSearchText, placeholder: '搜索此 UP 的内容', controller: this.spaceSearchInputController })
                  .id('space-search-input').height('100%').width('100%')
                  .padding({ left: 14, right: 14, top: 0, bottom: 0 })
                  .backgroundColor(Color.Transparent).fontColor(this.ink()).fontSize(15)
                  .enterKeyType(EnterKeyType.Search)
                  .onAppear(() => { this.getUIContext().getFocusController().requestFocus('space-search-input'); })
                  .onChange((value: string) => { this.spaceSearchText = value; })
                  .onSubmit(() => this.submitSpaceSearch())
              }
            }.layoutWeight(1)
            HeaderGlassControl({ label: '搜索', controlId: 'space-search-submit', onActivate: () => this.submitSpaceSearch() }) {
              Image($r('app.media.ref_search')).width(22).height(22).fillColor(this.ink()).hitTestBehavior(HitTestMode.None)
            }
          }.width('100%').height(48).padding({ left: 12, right: 12 })
          Text('仅搜索 ' + (this.spaceInfo?.name || this.upName || '此 UP') + ' 的视频与动态')
            .fontSize(12).fontColor(this.muted()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%').padding({ left: 16, right: 16 })
        }.padding({ top: this.statusBarHeight + 8, bottom: 8 })
      }
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .id('space-search-panel')
      .transition(TransitionEffect.translate({ x: this.spaceViewportWidth, y: 0 }))
  }

  /** 竖屏空间页：头图与头像重叠，统计和关注按钮排在头像右侧。 */
  @Builder
  spaceHeaderBackground(imageUrl: string) {
    Stack() {
      if (imageUrl) {
        Image(imageUrl).width('100%').height('100%').objectFit(ImageFit.Cover)
          .opacity(this.loadedSpaceHeaderImage === imageUrl ? 1 : 0)
          .onComplete((event) => {
            if (event?.loadingStatus === 1) this.loadedSpaceHeaderImage = imageUrl;
          })
          .onError(() => {
            if (this.loadedSpaceHeaderImage === imageUrl) this.loadedSpaceHeaderImage = '';
          })
        if (this.loadedSpaceHeaderImage === imageUrl) {
          Column().width('100%').height('100%').backgroundColor('#45000000')
        }
      }
    }.width('100%').height(160).backgroundColor(Color.Transparent)
  }

  @Builder
  spaceHeader() {
    Column() {
      this.spaceHeaderBackground(this.spaceHeaderImage())
      Row({ space: 42 }) {
        Image(this.upFace).width(84).height(84).borderRadius(42)
          .objectFit(ImageFit.Cover).border({ width: 2, color: '#FFFFFF' })
          .margin({ top: -22, left: 30 })
        Column({ space: 6 }) {
          Row() {
            this.statCell('粉丝')
            Column().width(1).height(15).backgroundColor(this.hairline())
            this.statCell('关注')
            Column().width(1).height(15).backgroundColor(this.hairline())
            this.statCell('获赞')
          }.width('100%').height(38)
          FollowGlassButton({ followed: this.isFollowed, buttonWidth: '100%', fontSize: 14,
            accent: this.isFollowed ? this.muted() : '#FB7299',
            textColor: this.isFollowed ? this.muted() : '#FFFFFF',
            fill: this.isFollowed ? this.skeletonBg() : '#FB7299', onActivate: () => this.toggleFollow() })
        }.layoutWeight(1).padding({ top: 6, right: 12 })
      }.width('100%').alignItems(VerticalAlign.Top)
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.spaceInfo?.name || this.upName || '用户空间').fontSize(18)
            .fontColor(this.ink()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '82%' })
          this.lvBadge()
          this.verifyBadge()
        }.width('100%')
        Row({ space: 12 }) {
          Text(this.spaceInfo?.sign || '这个人很神秘，什么都没有写')
            .fontSize(12).fontColor(this.muted()).maxLines(this.detailsExpanded ? 1000 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .onClick(() => { this.detailsExpanded = true; })
          Text(this.detailsExpanded ? '收起' : '详情').fontSize(12).fontColor('#5AAACB')
            .onClick(() => { this.detailsExpanded = !this.detailsExpanded; })
        }.width('100%')
        Text(this.spaceInfo?.ip_location ?
          (this.spaceInfo.ip_location.includes('IP') ? this.spaceInfo.ip_location : 'IP属地：' + this.spaceInfo.ip_location) :
          (this.isInfoLoaded ? 'IP属地：暂未获取' : 'IP属地：加载中'))
          .fontSize(10).fontColor(this.muted())
        if (this.detailsExpanded) {
          Column({ space: 8 }) {
            Text(`UID：${this.mid}`).fontSize(12).fontColor(this.muted())
            if (this.spaceInfo?.sex && this.spaceInfo.sex !== '保密') {
              Text(`性别：${this.spaceInfo.sex}`).fontSize(12).fontColor(this.muted())
            }
            if (this.spaceInfo?.birthday && !this.spaceInfo.birthday.startsWith('0000')) {
              Text(`生日：${this.spaceInfo.birthday}`).fontSize(12).fontColor(this.muted())
            }
            if (this.spaceInfo?.official_verify?.desc) {
              Text(this.spaceInfo.official_verify.desc).fontSize(12).fontColor(this.muted())
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 20, bottom: 18 })
    }.width('100%').backgroundColor(this.paperBg())
      .onAreaChange((_old: Area, area: Area) => { this.headerH = Number(area.height); })
  }

  @Builder
  spaceToolbar() {
    PageHeader({ withTabs: false, scopeId: 'up-toolbar-native-scope' }) {
      Row({ space: 8 }) {
        HeaderBackButton({ iconColor: this.videoSticky || !this.hasLoadedSpaceHeaderImage() ? this.ink() : '#FFFFFF', onBack: () => this.goBack() })
        Blank()
        Column() {
          HeaderGlassControl({ label: '私信', controlId: 'space-header-message', onActivate: () => { this.openWhisper(); } }) {
            Image($r('app.media.ref_message')).width(22).height(22)
              .fillColor(this.videoSticky || !this.hasLoadedSpaceHeaderImage() ? this.ink() : '#FFFFFF').hitTestBehavior(HitTestMode.None)
          }
        }.width(40).height(40)
        Column() {
          HeaderGlassControl({ label: '搜索', controlId: 'space-header-search', onActivate: () => this.openSpaceSearch() }) {
            Image($r('app.media.ref_search')).width(22).height(22)
              .fillColor(this.videoSticky || !this.hasLoadedSpaceHeaderImage() ? this.ink() : '#FFFFFF').hitTestBehavior(HitTestMode.None)
          }
        }.width(40).height(40)
        Column() {
          HeaderGlassControl({ label: '更多', controlId: 'space-header-more', onActivate: () => { this.showMoreMenu(); } }) {
            Image($r('app.media.comment_more')).width(22).height(22)
              .fillColor(this.videoSticky || !this.hasLoadedSpaceHeaderImage() ? this.ink() : '#FFFFFF').hitTestBehavior(HitTestMode.None)
          }
        }.width(40).height(40)
      }.width('100%').height(this.statusBarHeight + 44)
        .padding({ top: this.statusBarHeight, left: 8, right: 8 })
      }


  }

  /** A1 数据条单元：衬线数字 + letterspacing 小标签 */
  @Builder
  statCell(label: string) {
    Column() {
      Text(label === '粉丝' ? (this.relationStat ? fmtN(this.relationStat.follower) : '—') :
        (label === '关注' ? (this.relationStat ? fmtN(this.relationStat.following) : '—') :
          (this.receivedLikes === null ? '—' : fmtN(this.receivedLikes))))
        .fontSize(12)
        .fontWeight(FontWeight.Normal)
        .fontColor(this.ink())
      Text(label)
        .fontSize(11)
        .fontColor(this.muted())
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  /** LV 胶囊（主题色底白字） */
  @Builder
  lvBadge() {
    if (this.spaceInfo?.level && this.spaceInfo.level > 0) {
      Text(`LV${this.spaceInfo.level}`)
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .letterSpacing(0.6)
        .fontColor('#FFFFFF')
        .backgroundColor('#65C8E4')
        .padding({ left: 3, right: 6, top: 1.5, bottom: 1.5 })
        .borderRadius(4)
    }
  }

  /** 认证徽章（0=个人蓝 / 1=机构粉；无认证省略） */
  @Builder
  verifyBadge() {
    if (this.spaceInfo?.official_verify?.type === 0 || this.spaceInfo?.official_verify?.type === 1) {
      Text('✓')
        .fontSize(11)
        .fontColor('#FFFFFF')
        .width(17).height(17)
        .borderRadius(8.5)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.spaceInfo?.official_verify?.type === 0 ? '#56B7FF' : '#FB7299')
        .margin({ left: 7 })
    }
  }

  /** 主页、动态、投稿三页签。 */
  @Builder
  sectionRow(vPadTop: number, vPadBottom: number) {
    PageHeader({ withTabs: true, scopeId: 'up-tabs-native-scope' }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Row() {
          ForEach([0, 1, 2], (index: number) => {
            Text(['主页', '动态', '投稿'][index])
              .fontSize(15).fontColor(this.spaceTabColor(index))
              .layoutWeight(1).height(40).textAlign(TextAlign.Center)
              .padding({ bottom: 4 })
              .onClick(() => this.switchTab(['home', 'dynamic', 'video'][index]))
          }, (index: number) => index.toString())
        }.width('100%').height(40)
        Column().width(14).height(2).borderRadius(1).backgroundColor('#FB7299')
          .translate({ x: this.spaceTabBarWidth * (this.spaceTabProgress + 0.5) / 3 - 7, y: -4 })
          .hitTestBehavior(HitTestMode.None)
      }.width('100%').height(40)

        .onAreaChange((_old: Area, area: Area) => { this.spaceTabBarWidth = Number(area.width); })
      }


  }

  @Builder
  submissionOrderMenu() {
    Menu() {
      ForEach(ORDER_OPTIONS, (option: OrderOption) => {
        MenuItem({ content: option.label, endIcon: this.order === option.key ?
          (this.isDarkMode ? $r('app.media.settings_menu_check_dark') :
            $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.ink()).height(52).id('space-order-' + option.key)
          .onClick(() => this.switchOrder(option.key))
      }, (option: OrderOption) => option.key)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: this.isDarkMode ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  private submissionOrderMenuOptions(): MenuOptions {
    return {
      placement: Placement.BottomRight, enableArrow: false, borderRadius: 24,
      systemMaterial: deviceInfo.apiAvailable('26.0.0') ? GlassMaterial.create('menu', this.isDarkMode) : undefined
    };
  }

  @Builder
  spaceTabPager() {
    Swiper(this.spacePager) {
      ForEach([0, 1, 2], (index: number) => {
        Column() { this.spaceTabList(index) }.width('100%').height('100%')
      }, (index: number) => index.toString())
    }.index(this.spaceTabIndex).loop(false).indicator(false).cachedCount(1)
      .duration(300).curve(Curve.FastOutSlowIn)
      .width('100%')
      .height(this.isLandscape ? Math.max(120, this.spaceViewportHeight - this.statusBarHeight - 40) :
        Math.max(120, this.spaceViewportHeight - this.statusBarHeight - 44 - 40))
      .onContentDidScroll((_selected: number, index: number, position: number, _length: number) => {
        this.spaceTabProgress = Math.max(0, Math.min(2, index - position));
        if (this.spaceTabProgress > 0 && this.spaceTabProgress < 2 && !this.isDynLoaded && !this.dynLoading) {
          this.loadDynamics('');
        }
      })
      .onChange((index: number) => this.settleSpaceTab(index))
      .onAnimationEnd((index: number) => { this.spaceTabProgress = index; })
  }

  /**
   * A1 横屏左侧个人信息（圆角矩形卡片，与竖屏页眉同款、受全局卡片样式控制）：
   * mono 标签 + 更多（卡内右上）、头像/名/LV、纵列数据、关注条、衬线斜体签名引文；超高时 Scroll 兜底
   */
  @Builder
  railSection() {
    Column() {
      Scroll() {
        PageSurface({ radius: this.cardListBorderRadius }) {
        Column() {
          // mono 标签 + 更多（卡片内右上）
          Row() {
            Text(`UP-SPACE · UID ${this.mid}`)
              .fontFamily('monospace')
              .fontSize(9)
              .letterSpacing(2)
              .fontColor(this.muted())
            Blank()
            Stack() {
              Image($r('app.media.comment_more'))
                .width(16).height(16)
                .fillColor(this.inkSoft())
            }
            .width(30).height(30)
            .borderRadius(15)
            .backgroundColor(this.iconBtnBg())
            .onClick(() => { this.showMoreMenu(); })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Image(this.upFace)
            .width(72).height(72).borderRadius(36)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.isDarkMode ? '#2A2723' : '#E8E4DC')
            .border({ width: 3, color: this.isDarkMode ? '#26221D' : '#FFFFFF' })
            .margin({ top: 14 })

          Text(this.spaceInfo?.name ?? this.upName)
            .fontFamily('serif')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.ink())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 9 })

          Row() {
            this.lvBadge()
            this.verifyBadge()
          }
          .margin({ top: 4 })

          // 纵列数据（每行：衬线数字 + 小标签，行间 hairline）
          Column() {
            this.railStat('投稿')
            this.railStat('粉丝')
            this.railStat('关注')
          }
          .width('100%')
          .margin({ top: 12 })

          // 关注条 + 私信
          Row() {
            FollowGlassButton({ followed: this.isFollowed, buttonWidth: '100%', buttonHeight: 40,
              accent: this.isFollowed ? this.muted() : this.customThemeColor,
              textColor: this.isFollowed ? this.muted() : '#FFFFFF',
              fill: this.isFollowed ? Color.Transparent : this.customThemeColor,
              onActivate: () => this.toggleFollow() }).layoutWeight(1)

            Stack() {
              Image($r('app.media.message'))
                .width(16).height(16)
                .fillColor(this.inkSoft())
            }
            .width(40).height(40)
            .borderRadius(12)
            .backgroundColor(this.iconBtnBg())
            .margin({ left: 7 })
            .onClick(() => this.openWhisper())
          }
          .width('100%')
          .margin({ top: 12 })

          // 签名引文（衬线斜体 + 左侧 3px 主题色线；无签名省略）
          // Blank 把它钉到卡片底部：卡片高度自适应可用区域时，底部不留死白
          if (this.spaceInfo?.sign) {
            Blank().layoutWeight(1)
            Text(this.spaceInfo.sign)
              .fontFamily('serif')
              .fontStyle(FontStyle.Italic)
              .fontSize(13)
              .fontColor(this.warmGray())
              .lineHeight(20)
              .maxLines(4)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 12 })
              .border({ width: { left: 3 }, color: this.customThemeColor })
              .margin({ top: 12 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(16)
        .borderRadius(this.cardListBorderRadius)
        .border({ width: this.otherCardGlassEnabled ? this.cardBorderWidth : 0, color: this.getCardItemBorder() })
        .shadow({ radius: this.otherCardGlassEnabled ? 4 : 0, color: '#10000000', offsetX: 0, offsetY: 2 })
        // ⭐ 上下自适应：至少撑满 rail 可用高度（内容超出时随内容增长、Scroll 兜底滚动）
        .constraintSize({ minHeight: '100%' })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width(296)
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    // 右侧 padding 给 0：与内容区间的缝由内容列自己的左 padding（= cardListMargin）提供，避免双倍间距
    .padding({ left: this.cardListMargin, right: 0, top: 0, bottom: this.cardListMargin })
  }

  /** A1 横屏 rail 纵列数据行 */
  @Builder
  railStat(label: string) {
    Row() {
      // 在文本更新闭包内读取状态；不要把异步统计预先求值后作为 Builder 的普通参数传入。
      Text(this.spaceStatText(label))
        .fontFamily('serif')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink())
      Text(label)
        .fontSize(11)
        .fontColor(this.muted())
        .margin({ left: 8 })
      Blank()
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .border({ width: { bottom: 1 }, color: this.hairlineSoft() })
  }

  private spaceStatText(label: string): string {
    const value = label === '投稿' ? this.totalCount :
      (label === '粉丝' ? this.relationStat?.follower : this.relationStat?.following);
    return value !== undefined && Number.isFinite(value) && value >= 0 ? fmtN(value) : '—';
  }

  /**
   * A1 网格视频卡（圆角矩形卡片，受全局卡片样式控制）：
   * 16:10 封面（右下时长角标）+ 2 行标题 + meta（播放 · 相对时间）；封面按显示尺寸压缩解码（@400w）
   */
  @Builder
  gridVideoCard(item: UpSpaceVideoItem) {
    ChannelCardSurface({ radius: 6 }) {

    Column() {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(resizeImageUrl(item.pic, 400)).width('100%').aspectRatio(16 / 10).objectFit(ImageFit.Cover)
        Row({ space: 8 }) {
          this.videoMetric($r('app.media.ref_play'), item.play, '#FFFFFF')
          Blank()
          Text(fmtDuration(item.duration)).fontSize(10).fontColor('#FFFFFF')
        }.width('100%').padding(6).linearGradient({ angle: 0, colors: [['#80000000', 0], ['#00000000', 1]] })
      }.width('100%')
      Row({ space: 4 }) {
        Text(item.title).fontSize(13).fontColor(this.ink()).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        VideoCardMoreButton({ title: item.title, videoId: item.bvid, ownerMid: String(this.mid), onActivate: () => this.playVideo(item) })
      }.width('100%').height(46).alignItems(VerticalAlign.Bottom)
        .padding({ left: 10, right: 6, top: 6, bottom: 6 })
    }.width('100%').backgroundColor(this.videoCardEdgeLight ? Color.Transparent : ordinaryCardColor(this.isDarkMode))
      .visibility(this.feedbackRevision >= 0 && VideoCardFeedback.isDismissed(item.bvid, String(this.mid)) ? Visibility.None : Visibility.Visible)
      .borderRadius(6).clip(true).onClick(() => this.playVideo(item))

    }
  }

  /** 网格骨架单元（A1：灰圆角块，不转圈） */
  @Builder
  skeletonCell() {
    Column() {
      Column()
        .width('100%')
        .aspectRatio(1.6)
        .borderRadius(Math.max(4, this.cardListBorderRadius - 4))
        .backgroundColor(this.skeletonBg())
      Column()
        .width('70%')
        .height(11)
        .borderRadius(5.5)
        .backgroundColor(this.skeletonBg())
        .margin({ top: 8 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 投稿空态（A1：衬线空态；加载失败给下拉重试提示） */
  @Builder
  emptyVideos() {
    Column() {
      Text(this.loadError ? '加载失败' : 'TA 还没有投稿')
        .fontFamily('serif')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.warmGray())
      Text(this.loadError ? '下拉重试' : 'NO VIDEOS YET')
        .fontFamily('monospace')
        .fontSize(9)
        .letterSpacing(2)
        .fontColor(this.muted())
        .margin({ top: 6 })
    }
    .width('100%')
    .padding({ top: 60, bottom: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  spaceTabList(index: number) {
    Refresh({ refreshing: $$this.isRefreshing, builder: this.customRefreshComponent() }) {
      List({ space: index === 1 ? 8 : 0, scroller: index === 0 ? this.videoScroller : (index === 1 ? this.dynScroller : this.submissionScroller) }) {
        if (index === 1) {
          if (!this.isDynLoaded) {
            ListItem() { LoadingProgress().width(28).height(28).margin(30).color('#FB7299') }
          } else if (this.dynamics.length === 0) {
            ListItem() {
              Text('暂无动态，或登录后可查看完整动态').fontSize(13).fontColor(this.muted())
                .width('100%').textAlign(TextAlign.Center).padding(40)
            }
          } else {
            ForEach(this.dynamics, (item: SpaceDynamicItem) => {
              ListItem() {
                Row() { this.dynamicCard(item) }.width('100%').padding({ left: 14, right: 14 })
              }
            }, (item: SpaceDynamicItem) => item.idStr)
          }
        } else {
          ListItem() {
            Row({ space: 8 }) {
              if (index === 0) {
                Text('视频').fontSize(14).fontColor(this.ink())
                Text(this.spaceStatText('投稿')).fontSize(11).fontColor(this.muted())
                Blank()
                Text('更多  ›').fontSize(12).fontColor(this.muted()).onClick(() => this.switchTab('video'))
              } else {
                Image($r('app.media.ref_play')).width(20).height(20).fillColor('#FB7299')
                Text('播放全部').fontSize(14).fontColor(this.ink())
                  .onClick(() => { if (this.videos.length > 0) this.playVideo(this.videos[0]); })
                Blank()
                Text(this.order === 'pubdate' ? '☰ 最新发布' : (this.order === 'click' ? '☰ 最多播放' : '☰ 最多收藏'))
                  .fontSize(12).fontColor(this.muted())
                  .id('space-submission-order')
                  .bindMenu(this.submissionOrderMenu(), this.submissionOrderMenuOptions())
              }
            }.width('100%').height(44).padding({ left: 12, right: 12 })
          }
          if (!this.isListLoaded) {
            ListItem() {
              Row({ space: 10 }) { this.skeletonCell(); this.skeletonCell() }.padding(12)
            }
          } else if (this.videos.length === 0) {
            ListItem() { this.emptyVideos() }
          } else if (index === 0) {
            ForEach(this.isLandscape ? this.videoTriples : this.videoPairs, (pair: UpSpaceVideoItem[]) => {
              ListItem() {
                Row({ space: 10 }) {
                  Column() { this.gridVideoCard(pair[0]) }.layoutWeight(1)
                  if (pair.length > 1) {
                    Column() { this.gridVideoCard(pair[1]) }.layoutWeight(1)
                  } else { Column().layoutWeight(1) }
                  if (this.isLandscape) {
                    if (pair.length > 2) { Column() { this.gridVideoCard(pair[2]) }.layoutWeight(1) }
                    else { Column().layoutWeight(1) }
                  }
                }.width('100%').alignItems(VerticalAlign.Top).padding({ left: 12, right: 12, bottom: 16 })
              }
            }, (pair: UpSpaceVideoItem[]) => 'home-' + pair[0].bvid)
          } else {
            ForEach(this.videos, (item: UpSpaceVideoItem) => {
              ListItem() { this.submissionVideoRow(item) }
            }, (item: UpSpaceVideoItem) => 'submission-' + item.bvid)
          }
        }
        ListItem() { Column().height(32).width('100%') }
      }.width('100%').height('100%').padding({ top: index === 1 ? 8 : 0 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).cachedCount(4)
        .onReachEnd(() => {
          if (index === 1) this.loadMoreDynamics();
          else this.loadMore();
        })
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
    }.width('100%').height('100%').onRefreshing(() => { this.onRefresh(); })
  }

  @Builder
  videoMetric(icon: Resource, value: number, color: string) {
    Row({ space: 3 }) {
      Image(icon).width(14).height(14).fillColor(color)
      Text(fmtN(value)).fontSize(10).fontColor(color)
    }
  }

  @Builder
  submissionVideoRow(item: UpSpaceVideoItem) {
    VideoListItem({
      title: item.title, cover: resizeImageUrl(item.pic, 400), duration: item.duration,
      videoId: item.bvid, ownerMid: String(this.mid),
      playCount: item.play, dateText: this.spaceDate(item.pubdate),
      onActivate: () => this.playVideo(item)
    }).padding({ left: 12, right: 12 })
  }

  private spaceDate(ts: number): string {
    if (!ts) return '';
    const date = new Date(ts * 1000);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  /** A1 横屏投稿列表：右侧 3 列网格（节标题在右侧固定，列表自身不带头） */


  // ── 动态卡片渲染 ──

  /** 动态：视频类型（上图下文全宽封面：封面占满整行、2:1 比例 + 标题与统计在下方） */
  @Builder
  dynVideoCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, true, 12)
      }
      if (item.video) {
        Column() {
          Stack({ alignContent: Alignment.BottomStart }) {
            Image(item.video.cover)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(4)
              .backgroundColor('#E8E8E8')
            Row({ space: 8 }) {
              if (item.video.durationText) {
                Text(item.video.durationText)
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .backgroundColor('#B0000000')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
              }
              Text(`${fmtN(item.video.play)}播放`)
                .fontSize(12).fontColor('#FFFFFF')
                .fontWeight(FontWeight.Bold)
                .textShadow({ radius: 2, color: '#99000000', offsetX: 0, offsetY: 1 })
                .padding({ bottom: 2 })
              Blank()
              Image($r('app.media.tvdasd'))
                .width(54).height(54)
                .fillColor('#FFFFFF')
                .opacity(0.7)
                .margin({ right: 8 })
            }
            .width('100%')
            .align(Alignment.BottomStart)
            .padding({ left: 14, right: 8, bottom: 4 })
            .alignItems(VerticalAlign.Bottom)
          }
          .width('100%')
          .aspectRatio(16 / 9)
          // 标题（最多 2 行）
          Row({ space: 4 }) {
          Text(item.video.title)
            .fontSize(13)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(18)
            .layoutWeight(1)
            .textAlign(TextAlign.Start)
          VideoCardMoreButton({ title: item.video.title, videoId: item.video.bvid, ownerMid: String(item.authorMid), onActivate: () => this.playDynVideo(item.video) })
          }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 12 })
          this.spaceDynamicActions(item)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .onClick(() => { this.playDynVideo(item.video); })
      }
    }
    .width('100%')
  }

  /** 动态：图文类型（单图原比例完整显示/超长图 3:4；多图 2/4 张两列、其余三列九宫格） */
  @Builder
  dynDrawCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, true, 12)
      }
      if (item.images.length === 1) {
        // ⭐ 单图：普通图原比例完整显示；超长图（高/宽 > 16:9）用 3:4 竖版 + 顶部对齐 + 底部「长图」胶囊
        Stack() {
          Image(resizeImageUrl(item.images[0].src, 800))
            .width('100%')
            .aspectRatio(this.originalImageAspectRatio(item.images[0]))
            .objectFit(ImageFit.Cover)
            .backgroundColor('#E8E8E8')
          if (this.isTallImage(item.images[0])) {
            Column() {
              Blank()
              this.tallImageBadge()
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
            .hitTestBehavior(HitTestMode.None)
          }
        }
        .width('100%')
        .aspectRatio(this.singleImageAspectRatio(item.images[0]))
        .alignContent(Alignment.Top)
        .borderRadius(this.cardListBorderRadius)
        .clip(true)
        .id(`dyn_thumb_${item.images[0].src}`)
        .onClick(() => { this.openImagePreview(item.images, item.images[0].src, `dyn_thumb_${item.images[0].src}`); })
      } else if (item.images.length > 1) {
        // ⭐ 多图：2/4 张每行 2 个；其余每行 3 个（最多 9 张）；四角单圆角 + 右下 +N 胶囊
        Column() {
          ForEach(this.chunkImages(item.images), (row: DynImageInfo[], rowIndex: number) => {
            Row({ space: 6 }) {
              ForEach(row, (img: DynImageInfo, colIndex: number) => {
                Image(resizeImageUrl(img.src, 400))
                  .layoutWeight(1)
                  .aspectRatio(1)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(this.gridCornerRadius(this.chunkImages(item.images), rowIndex, colIndex))
                  .backgroundColor('#E8E8E8')
                  .overlay(this.overflowBadgeIfNeeded(item.images.length, this.chunkImages(item.images), rowIndex, colIndex), { align: Alignment.Bottom })
                  .id(`dyn_thumb_${img.src}`)
                  .onClick(() => { this.openImagePreview(item.images, img.src, `dyn_thumb_${img.src}`); })
              }, (img: DynImageInfo, colIndex: number) => `img_${img.src}_${colIndex}`)
            }
            .width('100%')
            .margin({ bottom: rowIndex < this.chunkImages(item.images).length - 1 ? 6 : 0 })
          }, (row: DynImageInfo[]) => row[0].src)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /** 动态：纯文本类型 */
  @Builder
  dynTextCard(item: SpaceDynamicItem) {
    Column() {
      this.dynTextSegmentsBuilder(item, false, 0)
    }
    .width('100%')
  }

  /** 动态：转发类型（显示转发源摘要） */
  @Builder
  dynForwardCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, false, 8)
      }
      if (item.orig) {
        Row() {
          if (item.orig.video) {
            Image(item.orig.video.cover)
              .width(64).height(40)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .backgroundColor('#E8E8E8')
          }
          Column() {
            if (item.orig.video) {
              Text(item.orig.video.title)
                .fontSize(12)
                .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .lineHeight(17)
                .width('100%')
            } else {
              Text(item.orig.text)
                .fontSize(12)
                .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .lineHeight(17)
                .width('100%')
            }
            Text(`@${item.orig.authorName || '原动态'}`)
              .fontSize(10)
              .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 8 })
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
        .onClick(() => { this.playDynVideo(item.orig?.video ?? null); })
      }
    }
    .width('100%')
  }

  /** 动态：不支持的类型占位 */
  @Builder
  dynUnsupportedCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, false, 8)
      }
      Text('暂不支持此动态类型')
        .fontSize(12)
        .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
        .padding({ top: 8, bottom: 8 })
    }
    .width('100%')
  }

  /** 动态卡片（按类型分发渲染，与动态页同款） */
  @Builder
  dynamicCard(item: SpaceDynamicItem) {
    // Match the feed's measured native card material; spacing stays outside the surface.
    Column() {
    PageSurface({ radius: 20 }) {
    Column() {
      // ⭐ 内部包裹 Column：承载 padding，保证内容在卡片内
      Column() {
        Row({ space: 8 }) {
          Image(item.authorFace).width(40).height(40).borderRadius(20).objectFit(ImageFit.Cover)
            .onClick(() => this.openUpSpace(item))
          Column({ space: 5 }) {
            Text(item.authorName || this.upName).fontSize(14).fontColor(this.ink()).maxLines(1)
              .onClick(() => this.openUpSpace(item))
            Text(`${this.spaceDate(item.pubTs)}${item.video ? ' · 投稿了视频' : ''}`)
              .fontSize(11).fontColor(this.muted())
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Image($r('app.media.comment_more')).width(18).height(24).fillColor(this.muted())
            .onClick(() => this.openDynDetail(item))
        }.width('100%').margin({ bottom: 16 }).onClick(() => this.openDynDetail(item))

        // ⭐ 按已解析字段分发（优先字段而非 type 字符串）：PGC 走竖版海报卡，视频/图文/专栏/文字/转发依次兜底
        if (item.type.startsWith('DYNAMIC_TYPE_PGC')) {
          this.dynPgcCard(item)
        } else if (item.video) {
          this.dynVideoCard(item)
        } else if (item.images.length > 0) {
          this.dynDrawCard(item)
        } else if (item.common) {
          this.dynCommonCard(item)
        } else if (item.type === DYN_TYPE_WORD) {
          this.dynTextCard(item)
        } else if (item.type === DYN_TYPE_FORWARD) {
          this.dynForwardCard(item)
        } else if (item.text) {
          this.dynTextCard(item)
        } else {
          this.dynUnsupportedCard(item)
        }

        if (!item.video) { this.spaceDynamicActions(item) }
      }.width('100%').padding(12)
    }.width('100%')
      .onClick(() => this.openDynDetail(item))
    }
    }.width('100%')
  }

  @Builder
  spaceDynamicActions(item: SpaceDynamicItem) {
    Row() {
      Row({ space: 5 }) {
        Image($r('app.media.ref_share')).width(20).height(20).fillColor(this.muted())
        Text(item.forwardCount ? fmtN(item.forwardCount) : '转发').fontSize(12).fontColor(this.muted())
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Row({ space: 5 }) {
        Image($r('app.media.comment_reply')).width(20).height(20).fillColor(this.muted())
        Text(fmtN(item.commentCount)).fontSize(12).fontColor(this.muted())
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
      Row({ space: 5 }) {
        Image($r('app.media.ref_like')).width(20).height(20).fillColor(this.muted())
        Text(fmtN(item.likeCount)).fontSize(12).fontColor(this.muted())
      }.layoutWeight(1).justifyContent(FlexAlign.Center)
    }.width('100%').height(40).margin({ top: 10 }).onClick(() => this.openDynDetail(item))
  }

  /** ⭐ 动态正文分段渲染：普通文字 / B 站表情图 / #话题# 胶囊 / @某人 高亮（动态页同款，后两者可点击） */
  @Builder
  dynTextSegmentsBuilder(item: SpaceDynamicItem, isCenter: boolean, bottomMargin: number) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: isCenter ? FlexAlign.Center : FlexAlign.Start }) {
      ForEach(item.textSegments, (seg: DynTextSegment, index: number) => {
        if (seg.emoteUrl) {
          Image(seg.emoteUrl)
            .width(20)
            .height(20)
            .margin({ left: 2, right: 2 })
            .objectFit(ImageFit.Contain)
        } else if (seg.kind === 'topic') {
          // ⭐ #话题# → 胶囊（主题色文字 + 主题色 16% 底）：点击进搜索
          // ⭐ 与 DynamicTextContent 同步收紧（12 号字 + 行高 16 + 上下 padding 1 = 胶囊仅 18vp）：
          //    胶囊过高时换行行距不够、相邻两行互相压住；上下 margin 2 让行间留出 4vp 间隙
          Text(seg.text)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.customThemeColor)
            .lineHeight(16)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .margin({ left: 2, right: 2, top: 2, bottom: 2 })
            .borderRadius(5)
            .backgroundColor('#' + this.opacityToHexAlpha(16) + this.customThemeColor.slice(1))
            .clickEffect({ level: 0, scale: 0.95 })
            .onClick(() => { this.openTopicTag(seg.text); })
        } else if (seg.kind === 'at') {
          // ⭐ @某人 → 主题色 + Medium（不加底色，与话题胶囊区分）：点击进 TA 的空间
          Text(seg.text)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.customThemeColor)
            .lineHeight(20)
            .textAlign(isCenter ? TextAlign.Center : TextAlign.Start)
            .clickEffect({ level: 0, scale: 0.95 })
            .onClick(() => { this.openMentionedUp(seg); })
        } else {
          Text(seg.text)
            .fontSize(14)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .lineHeight(20)
            .textAlign(isCenter ? TextAlign.Center : TextAlign.Start)
        }
      }, (seg: DynTextSegment, index: number) => `dseg_${index}`)
    }
    .width('100%')
    .margin({ bottom: bottomMargin })
  }

  /** ⭐ 点击正文 #话题#：本工程无话题详情页，带关键词进搜索页（与动态页同一入口，两页各留一份） */
  private openTopicTag(topicText: string): void {
    let kw: string = topicText;
    if (kw.startsWith('#')) kw = kw.substring(1);
    if (kw.endsWith('#')) kw = kw.substring(0, kw.length - 1);
    kw = kw.trim();
    if (!kw) return;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage', params: { keyword: kw } }).catch(() => {});
  }

  /** ⭐ 点击正文 @某人：进 TA 的空间（mid 来自富文本节点 rid） */
  private openMentionedUp(seg: DynTextSegment): void {
    const mid: number = seg.mid ?? 0;
    if (mid <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开该用户主页', duration: 1500 });
      return;
    }
    let name: string = seg.text ?? '';
    if (name.startsWith('@')) name = name.substring(1);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/UpSpacePage',
      params: { mid: mid, upName: name, upFace: '' }
    }).catch(() => {});
  }

  /** 动态：专栏/通用卡片类型（majorType=COMMON，如专栏文章；点击打开跳转链接） */
  @Builder
  dynCommonCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, false, 8)
      }
      if (item.common) {
        Row() {
          if (item.common.cover) {
            Image(item.common.cover)
              .width(84).height(56)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .backgroundColor('#E8E8E8')
          }
          Column() {
            Text(item.common.title)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(18)
              .width('100%')
            if (item.common.desc) {
              Text(item.common.desc)
                .fontSize(11)
                .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .lineHeight(15)
                .width('100%')
                .margin({ top: 3 })
            }
          }
          .layoutWeight(1)
          .margin({ left: 8 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
        .borderRadius(8)
        .padding({ left: 10, right: 10 })
        // ⭐ 仅展示卡片（jumpUrl 为外部 http 链接，pushUrl 仅接受应用内路由，暂不跳转）
      }
    }
    .width('100%')
  }

  /** 番剧卡封面（数据源兼容：番剧 majorType=ARCHIVE 时只有 video，common 为 null 时用 video 兜底） */
  private pgcCoverOf(item: SpaceDynamicItem): string {
    return (item.common?.cover ?? item.video?.cover) ?? '';
  }

  /** 番剧卡标题（video 兜底） */
  private pgcTitleOf(item: SpaceDynamicItem): string {
    return (item.common?.title ?? item.video?.title) ?? '';
  }

  /** 番剧卡描述（video 兜底） */
  private pgcDescOf(item: SpaceDynamicItem): string {
    return (item.common?.desc ?? item.video?.desc) ?? '';
  }

  /** 动态：番剧/影视卡片（DYNAMIC_TYPE_PGC，竖版海报适配番剧封面） */
  @Builder
  dynPgcCard(item: SpaceDynamicItem) {
    Column() {
      if (item.text) {
        this.dynTextSegmentsBuilder(item, true, 8)
      }
      if (this.pgcCoverOf(item) || this.pgcTitleOf(item)) {
        // ---- 横版封面（16:9，动态页卡片统一横版比例）----
        Stack({ alignContent: Alignment.BottomStart }) {
          Image(this.pgcCoverOf(item))
            .width('100%')
            .aspectRatio(16 / 9)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.isDarkMode ? '#333333' : '#E8E8E8')
            .borderRadius(this.cardListBorderRadius)

          // 底部渐变遮罩
          Row()
            .width('100%')
            .height(30)
            .position({ bottom: 0 })
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [['#00000000', 0], ['#66000000', 1]]
            })

          // ⭐ 播放图标：tvdasd（与视频投稿卡同款），封面右下角，70% 不透明
          Image($r('app.media.tvdasd'))
            .width(54)
            .height(54)
            .fillColor(Color.White)
            .opacity(0.7)
            .position({ bottom: 8, right: 8 })
        }
        .width('100%')
        .borderRadius(this.cardListBorderRadius)
        .clip(true)

        // ---- 标题 ----
        Text(this.pgcTitleOf(item))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 8, left: 2, right: 2 })

        // ---- 描述 ----
        if (this.pgcDescOf(item)) {
          Text(this.pgcDescOf(item))
            .fontSize(12)
            .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .lineHeight(17)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 4, left: 2, right: 2 })
        }
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.otherCardGlassEnabled ? Color.Transparent : this.getCardItemBg())
    .borderRadius(this.cardListBorderRadius)
    .border({ width: this.cardBorderWidth, color: this.getCardItemBorder() })
    .clip(true)
    .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
    .onClick(() => { this.openPgcLink(item); })
  }

  /** 提取字符串开头的连续数字（用于解析 jumpUrl 中的 id），无数字返回 0 */
  private parseLeadingNumber(s: string): number {
    let num: number = 0;
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c >= 48 && c <= 57) {
        num = num * 10 + (c - 48);
      } else {
        break;
      }
    }
    return num;
  }

  /** 点击番剧卡：优先用解析保留的 seasonId/epId，其次从 jumpUrl 解析，应用内跳转 VideoPlayerPage 播放 */
  private openPgcLink(item: SpaceDynamicItem): void {
    let seasonId: number = item.common?.seasonId ?? 0;
    let epId: number = item.common?.epId ?? 0;
    const url = item.common?.jumpUrl ?? '';
    if (seasonId <= 0) {
      const ssIdx = url.indexOf('/ss');
      if (ssIdx >= 0) {
        seasonId = this.parseLeadingNumber(url.substring(ssIdx + 3));
      }
    }
    if (epId <= 0) {
      const epIdx = url.indexOf('/ep');
      if (epIdx >= 0) {
        epId = this.parseLeadingNumber(url.substring(epIdx + 3));
      }
    }
    if (seasonId <= 0 && epId <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无详情链接', duration: 1500 });
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        mediaId: seasonId > 0 ? seasonId : 0,
        epId: epId,
        title: item.common?.title ?? '',
      }
    }).catch((err: Error) => {
      logWarn(`[UpSpacePage] 跳转番剧失败: ${err}`);
    });
  }

  /**
   * ⭐ 打开动态详情页（正文不截断 + 看评论），与动态页 openDynDetail 同款。
   * 把整条 item 当 preload 传过去：详情页先渲染，再后台拉 `feed/detail` 校正数据（避免白屏）。
   * ⚠️ 本页原先**根本没有**这个入口 —— UP 空间页的动态卡片点哪儿都进不去详情页
   *    （内部各分支既没挂 onTapSelf，也没有跳转方法），用户报"有些卡片点击后打不开"就包括这里。
   */
  private openDynDetail(item: SpaceDynamicItem): void {
    if (item.type === DYN_TYPE_AV && item.video) {
      this.playDynVideo(item.video);
      return;
    }
    if (!item.idStr) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开该动态', duration: 1500 });
      return;
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/DynamicDetailPage',
      params: { dynIdStr: item.idStr, preload: item }
    }).catch(() => {});
  }

  /** 点击作者行 → 打开该作者的空间 */
  private openUpSpace(item: SpaceDynamicItem): void {
    if (!item.authorName) return;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/UpSpacePage',
      params: {
        mid: item.authorMid,
        upName: item.authorName,
        upFace: item.authorFace
      }
    });
  }

  // ── 图片网格辅助（与动态页同款）──

  /** 最大显示数量：5 张显示 4；7/8 张显示 6；其余按 9 张（3×3） */
  private maxDisplayCount(count: number): number {
    let maxCount: number = count;
    if (count === 5) {
      maxCount = 4;
    } else if (count === 7 || count === 8) {
      maxCount = 6;
    }
    return maxCount;
  }

  /** 将图片列表按行分组：2/4 张 → 每行 2 个（4 张为 2×2）；其余 → 每行 3 个（最多 9 张 = 3×3） */
  private chunkImages(images: DynImageInfo[]): DynImageInfo[][] {
    const rows: DynImageInfo[][] = [];
    const maxCount: number = this.maxDisplayCount(images.length);
    const cols: number = (maxCount === 2 || maxCount === 4) ? 2 : 3;
    for (let i: number = 0; i < maxCount; i += cols) {
      const row: DynImageInfo[] = [];
      for (let j: number = i; j < Math.min(i + cols, maxCount); j++) {
        row.push(images[j]);
      }
      rows.push(row);
    }
    return rows;
  }

  /** 多图网格四角单圆角：左上/右上/左下/右下用卡片圆角，内部小圆角 4 */
  private gridCornerRadius(rows: DynImageInfo[][], rowIndex: number, colIndex: number): DynCornerRadius {
    const r: number = this.cardListBorderRadius;
    const rowCount: number = rows.length;
    const rowLen: number = rows[rowIndex].length;
    const corner: DynCornerRadius = {};
    const isRowLast: boolean = colIndex === rowLen - 1;
    const isLastRow: boolean = rowIndex === rowCount - 1;
    const nextRowHasCol: boolean = rowIndex + 1 < rowCount && rows[rowIndex + 1].length > colIndex;
    const isBottomRight: boolean = isRowLast && (isLastRow || !nextRowHasCol);
    const isCornerCell: boolean = (rowIndex === 0 && colIndex === 0) ||
      (rowIndex === 0 && colIndex === rowLen - 1) ||
      (rowIndex === rowCount - 1 && colIndex === 0) || isBottomRight;
    if (isCornerCell) {
      corner.topLeft = (rowIndex === 0 && colIndex === 0) ? r : 4;
      corner.topRight = (rowIndex === 0 && colIndex === rowLen - 1) ? r : 4;
      corner.bottomLeft = (rowIndex === rowCount - 1 && colIndex === 0) ? r : 4;
      corner.bottomRight = isBottomRight ? r : 4;
    } else {
      const small: number = 4;
      corner.topLeft = small;
      corner.topRight = small;
      corner.bottomLeft = small;
      corner.bottomRight = small;
    }
    return corner;
  }

  /** 是否为超长图（高/宽 > 16:9）：单图时用 3:4 竖版展示并显示「长图」标识 */
  private isTallImage(img: DynImageInfo): boolean {
    return img.width > 0 && img.height > 0 && img.height / img.width > 16 / 9;
  }

  /** 原图宽高比（宽/高）：超长图按原比例撑高后，由外层容器裁剪出顶部区域 */
  private originalImageAspectRatio(img: DynImageInfo): number {
    if (img.width > 0 && img.height > 0) {
      return img.width / img.height;
    }
    return 1;
  }

  /** 单图宽高比：普通图按原比例完整显示；超长图（高/宽 > 16:9）用 3:4 竖版展示 */
  private singleImageAspectRatio(img: DynImageInfo): number {
    if (this.isTallImage(img)) {
      return 3 / 4;
    }
    if (img.width > 0 && img.height > 0) {
      return img.width / img.height;
    }
    return 16 / 9;
  }

  /** 超长图「长图」标识：底部居中半透明胶囊（点击穿透到图片，避免拦截展开预览） */
  @Builder
  tallImageBadge() {
    Text('长图')
      .fontSize(13)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Medium)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor('rgba(0,0,0,0.45)')
      .margin({ bottom: 10 })
      .align(Alignment.Bottom)
      .hitTestBehavior(HitTestMode.None)
  }

  /** 超出数量 +N 胶囊：最右下角图片叠加显示（与「长图」胶囊同尺寸，白字） */
  @Builder
  overflowBadge(count: number) {
    Text('+' + count.toString())
      .fontSize(13)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Medium)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor('rgba(0,0,0,0.45)')
      .margin({ bottom: 10 })
  }

  /** 图片超出显示数量（原图数 - 显示数），>0 时需要在最右下角叠加 +N */
  private overflowCount(total: number): number {
    return total - this.maxDisplayCount(total);
  }

  /** 是否应在该图叠加 +N 胶囊：图片超出显示数量，且该图是网格最右下角 */
  private shouldShowOverflowBadge(total: number, rows: DynImageInfo[][], rowIndex: number, colIndex: number): boolean {
    if (this.overflowCount(total) <= 0) return false;
    return rowIndex === rows.length - 1 && colIndex === rows[rowIndex].length - 1;
  }

  /** 仅当图片超出显示数量时，在最右下角图片上叠加 +N 胶囊 */
  @Builder
  overflowBadgeIfNeeded(total: number, rows: DynImageInfo[][], rowIndex: number, colIndex: number) {
    if (this.shouldShowOverflowBadge(total, rows, rowIndex, colIndex)) {
      this.overflowBadge(this.overflowCount(total))
    }
  }

  /** 点击图文图片：打开全屏预览（压缩图，左右滑动切换；预览 UI 由通用 FullImagePreview 组件渲染） */
  private openImagePreview(images: DynImageInfo[], src: string, thumbId: string): void {
    if (images.length === 0) return;
    let idx = -1;
    for (let i = 0; i < images.length; i++) {
      if (images[i].src === src) {
        idx = i;
        break;
      }
    }
    const urls: string[] = [];
    const thumbIds: string[] = [];
    for (const img of images) {
      urls.push(resizeImageUrl(img.src, 1600));
      thumbIds.push(`dyn_thumb_${img.src}`);
    }
    this.previewImageUrls = urls;
    this.previewThumbIds = thumbIds;
    this.previewIndex = idx >= 0 ? idx : 0;
    this.captureThumbRect(thumbId);
    this.showPreview = true;
  }

  /** 通过组件 id 获取缩略图相对窗口矩形并转 vp；失败时置 0（退回中心缩放） */
  private captureThumbRect(thumbId: string): void {
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById(thumbId);
      this.previewOriginX = this.getUIContext().px2vp(info.windowOffset.x);
      this.previewOriginY = this.getUIContext().px2vp(info.windowOffset.y);
      this.previewOriginW = this.getUIContext().px2vp(info.size.width);
      this.previewOriginH = this.getUIContext().px2vp(info.size.height);
    } catch (e) {
      this.previewOriginX = 0;
      this.previewOriginY = 0;
      this.previewOriginW = 0;
      this.previewOriginH = 0;
    }
  }

  /** ⭐ 动态卡片背景（与动态页/首页卡片样式一致） */
  private getCardItemBg(): string {
    return cardItemBg(this.isDarkMode, this.cardTransparentStyle, this.cardBgOpacity, this.pageWallpaperEnabled);
  }

  /** ⭐ 动态卡片边框色（与动态页/首页卡片样式一致） */
  private getCardItemBorder(): string {
    if (!this.cardTransparentStyle) {
      return 'rgba(0,0,0,0)';
    }
    if (this.cardBorderFollowTheme) {
      return '#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1);
    }
    return this.isDarkMode
      ? `rgba(255,255,255,${this.cardBorderOpacity / 100})`
      : 'rgba(255,255,255,0.25)';
  }

  /** 透明度(0-100) → 两位十六进制 */
  private opacityToHexAlpha(opacity: number): string {
    const val = Math.round(opacity / 100 * 255);
    return val.toString(16).padStart(2, '0');
  }

  // ── A1 色彩 token（纸面编辑风；明暗双模式）──
  /** 纸面底（默认壁纸分支） */
  private paperBg(): string { if (this.pageWallpaperEnabled) return 'transparent'; return pageBackgroundColor(this.isDarkMode); }
  /** 主墨色 */
  private ink(): string { return this.isDarkMode ? '#E3E5E7' : '#18191C'; }
  /** 次墨色（卡片标题/图标） */
  private inkSoft(): string { return this.isDarkMode ? '#C9CCD0' : '#61666D'; }
  /** 暖灰正文（签名） */
  private warmGray(): string { return this.isDarkMode ? '#A8A298' : '#5C574E'; }
  /** 弱提示（mono 标签/数据标签） */
  private muted(): string { return this.isDarkMode ? '#85898F' : '#9499A0'; }
  /** 标准 hairline */
  private hairline(): string { return this.isDarkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.07)'; }
  /** 更弱 hairline（数据条分隔/rail 数据行） */
  private hairlineSoft(): string { return this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'; }
  /** 图标钮/胶囊槽底 */
  private iconBtnBg(): string { return this.isDarkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)'; }
  /** 骨架灰块 */
  private skeletonBg(): string { return this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'; }

  /**
   * 动态列表（含加载态、下拉刷新、触底加载）
   * A1：竖屏 = 浮丸留白 + 页眉（随列表滚走）+ 02 节标题（dynScroller 驱动吸顶替身）；
   *     横屏 = 纯列表（页眉在左 rail，节标题在右侧固定行）
   */

}

