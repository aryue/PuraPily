import { FavoritesDataService } from '../services/FavoritesDataService';
import { extractMidFromCookie } from '../api/FeedbackService';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageSurface } from '../components/PageSurface';
import { cardItemBg } from '../utils/CardStyle';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { FloatingVideoTransition } from '../services/FloatingVideoTransition';
import { VideoListItem } from '../components/VideoListItem';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
// FavoritesPage.ets - 我的收藏页面（同步B站官方收藏夹）
import { router, mediaquery, window, curves } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  FavFolderItem,
  FavResourceItem,
  getCreatedFavFolders,
  getCollectedFavFolders,
  getFavFolderResources,
  formatDuration,
  formatCount
} from '../api/FavoritesApi';
import { getUserInfo, prefetchVideoPlayback } from '../api/BilibiliApi';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { VibrateUtils } from '../utils/VibrateUtils';
import { HdsMiniBarButton } from '../components/infra/HdsMiniBarButton';

enum PageMode {
  FOLDER_LIST,
  FOLDER_DETAIL
}

@Observed
class FavoriteFolderState {
  folders: FavFolderItem[] = [];
  loading: boolean = false;
  loaded: boolean = false;
  error: string = '';
  refreshing: boolean = false;
  generation: number = 0;
}

@Entry
@Component({ freezeWhenInactive: true })
struct FavoritesPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageProp('otherCardGlassEnabled') otherCardGlassEnabled: boolean = true;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('wallpaper') wallpaper: string = 'default';
  @StorageLink('customWallpaper') customWallpaper: string = '';
  @StorageLink('wallpaperBlur') wallpaperBlur: number = 0;
  @StorageLink('wallpaperDarkness') wallpaperDarkness: number = 50;
  @StorageLink('wallpaperColor') wallpaperColor: string = '#007DFF';
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('da') da: boolean = false;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardCapsuleFollowTheme') cardCapsuleFollowTheme: boolean = false;
  @StorageLink('cardCapsuleShow') cardCapsuleShow: boolean = true;
  @StorageLink('cardCapsuleSize') cardCapsuleSize: number = 12;
  @StorageLink('cardCapsuleRadius') cardCapsuleRadius: number = 7;
  @StorageLink('cardCapsuleColor') cardCapsuleColor: string = '';
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardListBorderRadius') cardListBorderRadius: number = 12;
  @StorageLink('cardListMargin') cardListMargin: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('statusBarHeight') globalStatusBarHeight: number = 0;

  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  @StorageLink('floatBtnFollowTheme') floatBtnFollowTheme: boolean = true;
  @StorageLink('favoritesFloatBtnSide') favoritesFloatBtnSide: string = 'right';
  @StorageLink('favoritesFloatBtnY') favoritesFloatBtnY: number = 120;

  @State pageMode: PageMode = PageMode.FOLDER_LIST;
  @State activeTabIndex: number = 0;
  @State folderPages: FavoriteFolderState[] = [new FavoriteFolderState(), new FavoriteFolderState()];
  @State tabPosition: number = 0;
  @State tabStripWidth: number = 0;
  private folderTabs: TabsController = new TabsController();
  private detailPager: SwiperController = new SwiperController();
  private folderRequestVersion: number = 0;
  @State private folderAnimating: boolean = false;
  private pagerWidth: number = 0;
  @State currentFolderId: number = 0;
  @State currentFolderTitle: string = '';
  @State resourceList: FavResourceItem[] = [];
  @State resourceError: string = '';
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.resourceList = this.resourceList.filter(item =>
      !VideoCardFeedback.isDismissed(item.bvid, item.upper ? String(item.upper.mid) : ''));
  }
  @State isLoadingResources: boolean = false;
  @State resourcePage: number = 1;
  @State resourceHasMore: boolean = true;
  @State isLoadingMore: boolean = false;
  @State isLoggedIn: boolean = false;
  @State loginResolved: boolean = false;
  private sessionCookie: string = '';
  @StorageProp('biliCookie') @Watch('onSessionChanged') favoriteSession: string = '';
  @State userMid: number = 0;
  @State isLoadingCovers: boolean = false;
  @State isLandscape: boolean = false;
  @State columnCount: number = 1;

  @State customMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @State customMaterialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;
  @State supportImmersive: boolean = false;
  @State imageLoadFailed: boolean = false;

  @State isRefreshing: boolean = false;
  @State showBackToTop: boolean = false;
  @State btnScale: number = 1;
  @State hand: number = 0;
  @State dragOffsetX: number = 0;
  @State isDragging: boolean = false;

  @State tabExpandAnimated: boolean = false;

  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  private waterFlowScroller: Scroller = new Scroller();
  private folderScrollers: Scroller[] = [new Scroller(), new Scroller()];

  private folderScroller(index: number = this.activeTabIndex): Scroller {
    return this.folderScrollers[index];
  }
  private touchStartWX: number = 0;
  private touchStartWY: number = 0;
  private dragStartY: number = 0;
  private gripListenersInitialized: boolean = false;
  private gripSafeAreaLeft: number = 0;
  private gripSafeAreaRight: number = 0;
  private smartGripLeft: number = 0;
  private smartGripRight: number = 0;
  private smartGripBottom: number = 0;
  private maxFloatBtnBottom: number = 592;
  private bottomSafeHeight: number = 0;

  async aboutToAppear(): Promise<void> {
    this.initOrientation();
    this.checkImmersiveSupport();
    await this.checkLoginState();
    this.initSmartGrip();
    this.setStatusBarTransparent();
    this.initBottomSafeHeight();
  }

  aboutToDisappear(): void {
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  private initOrientation(): void {
    const mainWindow = AppStorage.get<window.Window>('mainWindow');
    if (mainWindow) {
      const props = mainWindow.getWindowProperties();
      this.isLandscape = props.windowRect.width > props.windowRect.height;
      this.columnCount = this.isLandscape ? 2 : 1;
    }
    const mediaQuery = this.getUIContext().getMediaQuery();
    this.landscapeListener = mediaQuery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      const newIsLandscape = result.matches;
      if (this.isLandscape !== newIsLandscape) {
        this.isLandscape = newIsLandscape;
        this.columnCount = this.isLandscape ? 2 : 1;
        this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;
      }
    });
  }

  private checkImmersiveSupport(): void {
    try {
      const apiVersion = deviceInfo.sdkApiVersion ?? 0;
      this.supportImmersive = apiVersion >= 23;
      if (this.supportImmersive) {
        const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
        if (types && types.includes(hdsMaterial.MaterialType.IMMERSIVE)) {
          this.customMaterialType = hdsMaterial.MaterialType.IMMERSIVE;
        } else {
          this.customMaterialType = hdsMaterial.MaterialType.ADAPTIVE;
        }
      }
    } catch (e) {
      this.supportImmersive = false;
    }
  }

  private async setStatusBarTransparent(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const windowClass: window.Window = await window.getLastWindow(context);
      await windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: this.isDarkMode ? '#FFFFFF' : '#000000'
      });
      const hideSb: boolean = AppStorage.get<boolean>('hideStatusBar') ?? false;
      await StatusBarUtils.setStatusBarHidden(context, hideSb);
    } catch (error) {
      logError('设置状态栏透明失败', error);
    }
  }

  private async initBottomSafeHeight(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomSafeHeight = this.getUIContext().px2vp(navArea.bottomRect.height);
    } catch (e) {
      logError('获取底部安全区域高度失败', e);
    }
  }

  private initSmartGrip(): void {
    if (this.gripListenersInitialized) return;
    try {
      motion.on('holdingHandChanged', (data: number) => {
        if (data !== this.hand && (data === 1 || data === 2)) {
          this.hand = data;
          this.recalcSmartGripPosition();
        }
      });
      this.gripListenersInitialized = true;
    } catch (err) {
      logWarn('[Favorites] 初始化智感握持失败:', err);
    }
  }

  private recalcSmartGripPosition(): void {
    const screenH: number = this.isLandscape ? 520 : 720;
    const bottomSafe: number = 24;
    if (this.isLandscape) {
      this.smartGripBottom = Math.max(bottomSafe + 24, screenH * 0.20);
    } else {
      this.smartGripBottom = Math.max(bottomSafe + 12, screenH * 0.15);
    }
    this.smartGripLeft = this.gripSafeAreaLeft + 16;
    this.smartGripRight = this.gripSafeAreaRight + 8;
  }

  private async checkLoginState(): Promise<void> {
    const cookie = AppStorage.get<string>('biliCookie') ?? '';
    this.sessionCookie = cookie;
    this.isLoggedIn = cookie.includes('SESSDATA');
    if (!this.isLoggedIn) { this.loginResolved = true; return; }
    this.userMid = Number(extractMidFromCookie(cookie));
    if (this.userMid <= 0) {
      const user = await getUserInfo();
      if (cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      if (!user?.isLogin) { this.isLoggedIn = false; this.loginResolved = true; return; }
      this.userMid = user.mid;
    }
    const cache = FavoritesDataService.getInstance();
    for (let index = 0; index < 2; index++) {
      const items = cache.peekFolders(this.userMid, index);
      if (items !== undefined) { this.folderPages[index].folders = items; this.folderPages[index].loaded = true; }
    }
    this.folderPages = [...this.folderPages];
    this.loginResolved = true;
    await Promise.all([this.loadFolders(0), this.loadFolders(1)]);
  }

  private onSessionChanged(): void {
    if (this.sessionCookie === (AppStorage.get<string>('biliCookie') ?? '')) return;
    this.folderRequestVersion++;
    this.folderPages = [new FavoriteFolderState(), new FavoriteFolderState()];
    this.resourceList = [];
    this.userMid = 0;
    this.pageMode = PageMode.FOLDER_LIST;
    this.loginResolved = false;
    this.detailPager.changeIndex(0, false);
    this.checkLoginState();
  }

  private async loadFolders(index: number = this.activeTabIndex, refresh: boolean = false): Promise<void> {
    const state = this.folderPages[index];
    if (state.loading) return;
    const generation = ++state.generation;
    state.loading = true;
    state.error = '';
    this.folderPages = [...this.folderPages];
    try {
      const folders = await FavoritesDataService.getInstance().loadFolders(this.userMid, index, refresh);
      if (state !== this.folderPages[index] || generation !== state.generation ||
        this.sessionCookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      if (folders) {
        state.folders = folders;
        state.loaded = true;
      } else {
        state.error = '获取收藏夹列表失败，请点击重试';
      }
    } catch (err) {
      logError('[FavoritesPage] 加载收藏夹失败', err);
      state.error = '加载失败，请稍后重试';
    } finally {
      if (state !== this.folderPages[index] || generation !== state.generation) return;
      state.loading = false;
      state.refreshing = false;
      this.folderPages = [...this.folderPages];
    }
    if (state.loaded) this.loadAllFolderCovers(index, generation);
  }

  private async loadAllFolderCovers(index: number, generation: number): Promise<void> {
    const state = this.folderPages[index];
    const folders = state.folders.slice(0, 6);
    for (const folder of folders) {
      if (generation !== state.generation || state !== this.folderPages[index]) return;
      if (folder.cover || (folder.covers && folder.covers.length >= 3)) continue;
      try {
        const result = await getFavFolderResources(folder.id, 1, 3);
        if (generation !== state.generation || state !== this.folderPages[index] ||
          this.sessionCookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
        if (result && result.medias) {
          const covers = result.medias.map(item => item.cover).filter(cover => cover.length > 0);
          while (covers.length > 0 && covers.length < 3) covers.push(covers[0]);
          if (covers.length > 0) {
            state.folders = state.folders.map(item => item.id === folder.id ? {
              id: item.id, title: item.title, cover: item.cover, covers: covers, media_count: item.media_count
            } : item);
            FavoritesDataService.getInstance().rememberFolders(this.userMid, index, state.folders);
            this.folderPages = [...this.folderPages];
          }
        }
      } catch (err) {
        logWarn('[FavoritesPage] 获取收藏夹封面失败', err);
      }
    }
  }

  private onTabChange(index: number): void {
    this.activeTabIndex = index;
    this.tabPosition = index;
    this.showBackToTop = Math.abs(this.folderScroller(index).currentOffset().yOffset) > 300;
    const state = this.folderPages[index];
    if (this.isLoggedIn && !state.loaded && !state.loading) this.loadFolders(index);
  }

  private async onFolderClick(folder: FavFolderItem): Promise<void> {
    if (this.folderAnimating) return;
    this.folderRequestVersion++;
    this.currentFolderId = folder.id;
    this.currentFolderTitle = folder.title;
    const cached = FavoritesDataService.getInstance().peekResources(this.userMid, folder.id);
    this.resourceList = cached?.items ?? [];
    this.resourcePage = 1;
    this.resourceHasMore = cached?.hasMore ?? true;
    this.resourceError = '';
    this.pageMode = PageMode.FOLDER_DETAIL;
    this.detailPager.changeIndex(1, true);
    await this.loadFolderResources(true);
  }

  private async loadFolderResources(isRefresh: boolean): Promise<void> {
    if (this.currentFolderId === 0) return;
    const version = this.folderRequestVersion;
    if (!isRefresh) {
      if (!this.resourceHasMore || this.isLoadingMore || this.isLoadingResources) return;
      this.isLoadingMore = true;
    } else {
      this.isLoadingResources = true;
      this.resourceError = '';
      this.resourcePage = 1;
    }
    try {
      const result = await getFavFolderResources(
        this.currentFolderId,
        this.resourcePage,
        20,
        'mtime',
        ''
      );
      if (version !== this.folderRequestVersion || this.pageMode !== PageMode.FOLDER_DETAIL ||
        this.sessionCookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      if (result) {
        const medias = result.medias || [];
        if (isRefresh) {
          this.resourceList = medias;
          FavoritesDataService.getInstance().rememberResources(this.userMid, this.currentFolderId, medias, result.has_more || false);
        } else {
          const merged: FavResourceItem[] = [];
          for (let i = 0; i < this.resourceList.length; i++) {
            merged.push(this.resourceList[i]);
          }
          for (let i = 0; i < medias.length; i++) {
            merged.push(medias[i]);
          }
          this.resourceList = merged;
        }
        this.resourceHasMore = result.has_more || false;
      } else {
        this.resourceError = '加载失败，点击重试';
        if (this.resourceList.length === 0) this.resourceHasMore = false;
      }
    } catch (err) {
      if (version !== this.folderRequestVersion || this.pageMode !== PageMode.FOLDER_DETAIL ||
        this.sessionCookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      let error = err as Error;
      this.resourceError = '加载失败，点击重试';
      logError(`[FavoritesPage] loadFolderResources异常: ${error.message}`);
    }
    if (version !== this.folderRequestVersion) return;
    this.isLoadingResources = false;
    this.isLoadingMore = false;
  }

  private async onLoadMore(): Promise<void> {
    if (this.isLoadingResources || this.isLoadingMore || !this.resourceHasMore ||
      this.pageMode !== PageMode.FOLDER_DETAIL) return;
    this.resourcePage++;
    await this.loadFolderResources(false);
  }

  private goBackToFolderList(): void {
    if (this.folderAnimating) return;
    this.folderRequestVersion++;
    this.detailPager.changeIndex(0, true);
  }

  private goToVideo(video: FavResourceItem): void {
    // ⭐ 预热详情（fire-and-forget）：收藏页只传 bvid，播放页要等详情里的 cid 才能起播，
    //   在转场这一刻先把这次 RTT 发出去，与转场/播放器初始化重叠
    prefetchVideoPlayback(video.bvid, 0, AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: video.bvid,
        title: video.title,
        coverUrl: video.cover,
        duration: video.duration
      }
    }).catch((err: Error) => {
      logError('跳转视频播放失败', err.message);
      this.getUIContext().getPromptAction().showToast({ message: '播放页面暂不可用' });
    });
  }

  onBackPress(): boolean {
    if (this.pageMode === PageMode.FOLDER_DETAIL) {
      this.goBackToFolderList();
      return true;
    }
    return false;
  }

  private getSolidBackground(): string {
    switch (this.wallpaper) {
      case 'dark': return '#0A0E1A';
      case 'light': return '#FFFFFF';
      case 'mint': return '#E0F7F0';
      case 'blue': return '#1E2A4F';
      case 'custom_color': return this.wallpaperColor;
      default: return this.isDarkMode ? '#121212' : '#FFFFFF';
    }
  }

  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  private getCardBgColor(): string {
    if (this.cardCustomColor && this.cardCustomColor !== '#007DFF') {
      if (this.cardTransparentStyle) {
        return '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1);
      }
      return this.cardCustomColor;
    }
    return cardItemBg(this.isDarkMode, this.cardTransparentStyle, this.cardBgOpacity, this.pageWallpaperEnabled);
  }

  private getCardBorderColor(): string {
    if (!this.cardTransparentStyle) return 'transparent';
    if (this.cardBorderFollowTheme) {
      return '#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1);
    }
    if (this.isDarkMode) {
      return `rgba(255,255,255,${this.cardBorderOpacity / 100})`;
    }
    return 'rgba(255,255,255,0.25)';
  }

  private getCoverByIndex(folder: FavFolderItem, idx: number): string {
    const fallback = folder.cover ?? '';
    if (folder.covers && folder.covers.length > idx) {
      return folder.covers[idx];
    }
    return fallback;
  }

  private triggerHaptic(): void {
    try {
      VibrateUtils.vibrateTime(15);
    } catch (err) {
    }
  }

  private async saveFloatBtnPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('favoritesFloatBtnSide', this.favoritesFloatBtnSide);
      await pref.put('favoritesFloatBtnY', this.favoritesFloatBtnY);
      await pref.flush();
    } catch (e) {
      logError('保存收藏页悬浮按钮位置失败', e);
    }
  }

  // ==================== Build ====================

  pageTransition() {
    if (FloatingVideoTransition.active()) {
      PageTransitionEnter({ duration: FloatingVideoTransition.direction === 'minimize' ? 0 : FloatingVideoTransition.DURATION }).opacity(1)
      PageTransitionExit({ duration: FloatingVideoTransition.DURATION }).opacity(1)
    }
  }

  build() {
    Stack() {
      Swiper(this.detailPager) {
        Column() { this.FolderScene(false) }.width('100%').height('100%')
        Column() { this.FolderScene(true) }.width('100%').height('100%')
      }.width('100%').height('100%').loop(false).indicator(false).cachedCount(1)
        .duration(300).curve(Curve.Friction).disableSwipe(this.pageMode === PageMode.FOLDER_LIST)
        .onAnimationStart(() => { this.folderAnimating = true; })
        .onAnimationEnd((index: number) => {
          this.folderAnimating = false;
          if (index === 0) {
            this.folderRequestVersion++;
            this.pageMode = PageMode.FOLDER_LIST;
            this.currentFolderId = 0;
            this.currentFolderTitle = '';
            this.resourceList = [];
            this.isLoadingResources = false;
            this.isLoadingMore = false;
          }
        })
      this.FloatButtonLayer()
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private FolderScene(detail: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      PageWallpaper()
      Column() {
        if (detail) {
          this.FolderDetailView()
        } else {
            Tabs({ controller: this.folderTabs, index: this.activeTabIndex }) {
              TabContent() { this.FolderPane(0) }
              TabContent() { this.FolderPane(1) }
            }.width('100%').height('100%').barHeight(0).barPosition(BarPosition.End)
              .animationDuration(this.da ? 0 : 200).animationCurve(Curve.Ease)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .onAreaChange((_old: Area, area: Area) => { this.pagerWidth = Number(area.width); })
              .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
                if (this.pagerWidth > 0) this.tabPosition = Math.max(0, Math.min(1, index - event.currentOffset / this.pagerWidth));
              })
              .onAnimationStart((_from: number, to: number) => {
                this.getUIContext().animateTo({ duration: this.da ? 0 : 200, curve: Curve.Ease }, () => { this.tabPosition = to; });
              })
              .onChange((index: number) => this.onTabChange(index))
              .onAnimationEnd((index: number) => this.onTabChange(index))
        }
      }.width('100%').height('100%')
      Column() {
        PageHeader({ withTabs: !detail, scopeId: 'favorites-header-native-scope' }) {
          Column() {
            Row({ space: 12 }) {
              HeaderBackButton({ onBack: () => {
                this.triggerHaptic();
                if (detail) this.goBackToFolderList();
                else this.getUIContext().getRouter().back();
              } })
              if (!detail) {
                this.TabBar()
              } else {
              Text(this.currentFolderTitle)
                .fontSize(20).fontWeight(FontWeight.Medium).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                .fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C')
              }
              Column() {
                HeaderGlassControl({ label: '搜索', controlId: 'favorites-header-search', onActivate: () => this.triggerHaptic() }) {
                  Image($r('app.media.ic_public_search_filled')).width(22).height(22)
                    .fillColor(this.isDarkMode ? '#F2F4F8' : '#18191C').hitTestBehavior(HitTestMode.None)
                }
              }.width(40).height(40)
            }.width('100%').height(48 + this.globalStatusBarHeight)
              .padding({ left: 16, right: 16, top: this.globalStatusBarHeight })
          }.width('100%')
        }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ==================== 背景层 ====================

  // ==================== 未登录 ====================

  @Builder
  NotLoggedInView() {
    Column() {
      Blank()
      Text('请先登录B站账号')
        .fontSize(16)
        .fontColor(this.isDarkMode ? '#999999' : '#666666')
      Button('去登录')
        .type(ButtonType.Capsule)
        .backgroundColor('#FB7299')
        .fontColor(Color.White)
        .margin({ top: 16 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
        })
      Blank()
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 首次加载 ====================

  @Builder
  InitialLoadingView() {
    Column({ space: 10 }) {
      LoadingProgress().width(28).height(28).color(this.customThemeColor)
      Text('加载中…').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .id('favorites-initial-loading')
  }

  // ==================== 错误状态 ====================

  @Builder
  ErrorView(index: number) {
    Column() {
      Blank()
      Text(this.folderPages[index].error)
        .fontSize(14)
        .fontColor('#FF4444')
        .margin({ bottom: 12 })
      Button('重试')
        .type(ButtonType.Capsule)
        .backgroundColor('#FB7299')
        .fontColor(Color.White)
        .onClick(() => this.loadFolders(index, true))
      Blank()
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 空状态 ====================

  @Builder
  EmptyView(index: number) {
    Column() {
      Blank()
      Text(index === 0 ? '还没有创建收藏夹' : '还没有订阅收藏夹')
        .fontSize(16)
        .fontColor(this.isDarkMode ? '#999999' : '#666666')
      Blank()
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 收藏夹列表内容 ====================

  @Builder
  FolderContent(index: number) {
    Column() {
      Refresh({ refreshing: $$this.folderPages[index].refreshing }) {
        WaterFlow({ scroller: this.folderScroller(index) }) {
          ForEach(this.folderPages[index].folders, (item: FavFolderItem, index: number) => {
            FlowItem() {
              this.FolderCard(item)
            }
            .width('100%')
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
          }, (item: FavFolderItem) => String(item.id))
        }
        .columnsTemplate(this.columnCount === 2 ? '1fr 1fr' : '1fr')
        .contentStartOffset(this.globalStatusBarHeight + 48)
        .columnsGap(this.cardListMargin)
        .rowsGap(this.cardListMargin + 8)
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .cachedCount(30)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ left: 12, right: 12, top: 12, bottom: 0 })
        .backgroundColor('transparent')
        .onScrollIndex((firstIndex: number) => {
          const scrollOffset: number = this.folderScroller(index).currentOffset().yOffset;
          this.showBackToTop = Math.abs(scrollOffset) > 300;
        })
      }
      .onRefreshing(() => {
        this.loadFolders(index, true).finally(() => {
          this.folderPages[index].refreshing = false;
        });
      })
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('transparent')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  FolderPane(index: number) {
    if (!this.loginResolved) {
      this.InitialLoadingView()
    } else if (!this.isLoggedIn) {
      this.NotLoggedInView()
    } else if (!this.folderPages[index].loaded && this.folderPages[index].folders.length === 0 && !this.folderPages[index].error) {
      this.InitialLoadingView()
    } else if (this.folderPages[index].error.length > 0 && this.folderPages[index].folders.length === 0) {
      this.ErrorView(index)
    } else if (this.folderPages[index].loaded && this.folderPages[index].folders.length === 0) {
      this.EmptyView(index)
    } else {
      this.FolderContent(index)
    }
  }

  @Builder
  TabBar() {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row() {
        ForEach(['收藏夹', '订阅'], (title: string, index: number) => {
          Column() {
            Text(title).fontSize(16).maxLines(1)
              .fontWeight(Math.round(this.tabPosition) === index ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(Math.round(this.tabPosition) === index ? '#FB7299' : (this.isDarkMode ? '#F2F3F5' : '#30343B'))
          }.layoutWeight(1).height(40).justifyContent(FlexAlign.End).padding({ bottom: 10 })
            .onClick(() => { this.triggerHaptic(); this.folderTabs.changeIndex(index); })
        }, (title: string) => title)
      }.width('100%')
      Row().width(16).height(3).borderRadius(2).backgroundColor('#FB7299')
        .translate({ x: this.tabStripWidth * (this.tabPosition + 0.5) / 2 - 8, y: -3 })
        .hitTestBehavior(HitTestMode.None)
    }.height(40).layoutWeight(1)
      .onSizeChange((_old: SizeOptions, size: SizeOptions) => { this.tabStripWidth = Number(size.width); })
  }

  // ==================== 收藏夹卡片 ====================

  @Builder
  FolderCard(folder: FavFolderItem) {
    PageSurface({ radius: this.cardListBorderRadius }) {

    Row() {
      Stack() {
        if (folder.cover) {
          Image(this.getCoverByIndex(folder, 2))
            .width(160)
            .height(120)
            .borderRadius(this.cardListBorderRadius)
            .objectFit(ImageFit.Cover)
            .border({ width: 1, color: this.isDarkMode ? '#33FFFFFF' : '#33000000' })
            .offset({ x: 24, y: 18 })
            .opacity(0.20)

          Image(this.getCoverByIndex(folder, 1))
            .width(160)
            .height(120)
            .borderRadius(this.cardListBorderRadius)
            .objectFit(ImageFit.Cover)
            .border({ width: 1, color: this.isDarkMode ? '#55FFFFFF' : '#55000000' })
            .offset({ x: 12, y: 9 })
            .opacity(0.50)

          Image(this.getCoverByIndex(folder, 0))
            .width(160)
            .height(120)
            .borderRadius(this.cardListBorderRadius)
            .objectFit(ImageFit.Cover)
        } else {
          Text('📁')
            .fontSize(36)
            .opacity(0.5)
        }
      }
      .width(160)
      .height(120)
      .margin({ right: 24 })

      Column() {
        Blank()
          .layoutWeight(1)
        Text(folder.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkMode ? '#E5E5E5' : '#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22)
          .width('100%')

        Row() {
          Text(String(folder.media_count) + ' 个内容')
            .fontSize(13)
            .fontColor(this.isDarkMode ? '#999999' : '#999999')
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 100 })
    }
    .width('100%')
    .height(168)
    .padding({ left: 18, right: 20, top: 15, bottom: 33 })
    .borderRadius(this.cardListBorderRadius)
    .clip(true)
    .shadow({
      radius: this.otherCardGlassEnabled ? 16 : 0,
      color: this.isDarkMode ? 'rgba(0, 0, 0, 0.3)' : 'rgba(0, 0, 0, 0.08)',
      offsetX: 0,
      offsetY: 2
    })
    .onClick(() => {
      this.triggerHaptic();
      this.onFolderClick(folder);
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })

    }
  }

  // ==================== 收藏夹详情（视频列表） ====================

  @Builder
  FolderDetailView() {
    Column() {
      if (this.isLoadingResources && this.resourceList.length === 0) {
        this.InitialLoadingView()
      } else if (this.resourceList.length === 0) {
        Text(this.resourceError || '收藏夹为空')
          .fontSize(16)
          .fontColor(this.isDarkMode ? '#999999' : '#666666')
          .margin({ top: this.globalStatusBarHeight + 56 })
          .onClick(() => { if (this.resourceError) this.loadFolderResources(true); })
      } else {
        Refresh({ refreshing: $$this.isRefreshing }) {
          WaterFlow({ scroller: this.waterFlowScroller }) {
            ForEach(this.resourceList, (item: FavResourceItem) => {
              FlowItem() {
                this.VideoCard(item)
              }
              .width('100%')
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
            }, (item: FavResourceItem) => String(item.id))

            if (this.resourceHasMore) {
              FlowItem() {
                if (this.isLoadingMore) {
                  Row() {
                    LoadingProgress()
                      .width(20)
                      .height(20)
                      .color('#FB7299')
                    Text('加载中...')
                      .fontSize(13)
                      .fontColor(this.isDarkMode ? '#999999' : '#666666')
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .height(48)
                  .justifyContent(FlexAlign.Center)
                } else {
                  Text('点击加载更多')
                    .fontSize(13)
                    .fontColor('#FB7299')
                    .width('100%')
                    .height(48)
                    .textAlign(TextAlign.Center)
                    .onClick(() => this.onLoadMore())
                }
              }
            }
          }
          .columnsTemplate(this.columnCount === 2 ? '1fr 1fr' : '1fr')
          .contentStartOffset(this.globalStatusBarHeight + 48)
        .columnsGap(20)
          .rowsGap(0)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .cachedCount(30)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .padding({ left: 12, right: 12, top: 8, bottom: 0 })
          .backgroundColor('transparent')
          .onScrollIndex((firstIndex: number) => {
            const scrollOffset: number = this.waterFlowScroller.currentOffset().yOffset;
            this.showBackToTop = Math.abs(scrollOffset) > 300;
          })
        }
        .onRefreshing(() => {
          this.loadFolderResources(true).finally(() => {
            this.isRefreshing = false;
          });
        })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('transparent')
      }
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 视频卡片 ====================

  @Builder
  VideoCard(video: FavResourceItem) {
    VideoListItem({
      title: video.title, cover: video.cover, duration: video.duration,
      videoId: video.bvid, ownerMid: video.upper ? String(video.upper.mid) : '',
      playCount: video.cnt_info ? video.cnt_info.play : -1,
      tag: video.title === '已失效视频' ? '已失效' : '',
      onActivate: () => { this.triggerHaptic(); this.goToVideo(video); }
    })
  }

  // ==================== 骨架屏视频卡片 ====================


  @Builder
  FloatButtonLayer() {
    if (this.smartGripEnabled && !this.isLandscape) {
      Stack() {
        HdsMiniBarButton({
          barWidth: 48,
          barHeight: 48,
          contentPadding: 0,
          containerSize: { width: 48, height: 48 },
          barBottomMargin: 0,
          barOverlap: true,
          barPosition: BarPosition.End
        }) {
          Image($r('app.media.chevron_down'))
            .width(20).height(20)
            .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : (this.isDarkMode ? Color.White : Color.Black))
            .rotate({ angle: 180 })
        }
        Column()
          .width(48).height(48)
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.touchStartWY = event.touches[0].windowY;
              this.dragStartY = this.favoritesFloatBtnY;
              this.isDragging = true;
            } else if (event.type === TouchType.Move) {
              const offYpx = event.touches[0].windowY - this.touchStartWY;
              this.favoritesFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isDragging = false;
              if (event.type === TouchType.Up) {
                this.triggerHaptic();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.btnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.btnScale = 1;
                  });
                }, 100);
                if (this.pageMode === PageMode.FOLDER_LIST) {
                  this.folderScroller().scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                } else {
                  this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                }
              }
            }
          })
      }
      .width(48).height(48)
      .position({ bottom: this.favoritesFloatBtnY, left: this.smartGripLeft })
      .opacity(this.hand === 1 && this.showBackToTop ? 1 : 0)
      .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
      .hitTestBehavior(this.hand === 1 && this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
      .animation(this.da || this.isDragging ? { duration: 0 } : { duration: 300, curve: curves.springMotion(0.3, 0.4) })

      Stack() {
        HdsMiniBarButton({
          barWidth: 48,
          barHeight: 48,
          contentPadding: 0,
          containerSize: { width: 48, height: 48 },
          barBottomMargin: 0,
          barOverlap: true,
          barPosition: BarPosition.End
        }) {
          Image($r('app.media.chevron_down'))
            .width(20).height(20)
            .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : (this.isDarkMode ? Color.White : Color.Black))
            .rotate({ angle: 180 })
        }
        Column()
          .width(48).height(48)
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.touchStartWY = event.touches[0].windowY;
              this.dragStartY = this.favoritesFloatBtnY;
              this.isDragging = true;
            } else if (event.type === TouchType.Move) {
              const offYpx = event.touches[0].windowY - this.touchStartWY;
              this.favoritesFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isDragging = false;
              if (event.type === TouchType.Up) {
                this.triggerHaptic();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.btnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.btnScale = 1;
                  });
                }, 100);
                if (this.pageMode === PageMode.FOLDER_LIST) {
                  this.folderScroller().scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                } else {
                  this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                }
              }
            }
          })
      }
      .width(48).height(48)
      .position({ bottom: this.favoritesFloatBtnY, right: this.smartGripRight })
      .opacity(this.hand !== 1 && this.showBackToTop ? 1 : 0)
      .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
      .hitTestBehavior(this.hand !== 1 && this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
      .animation(this.da || this.isDragging ? { duration: 0 } : { duration: 300, curve: curves.springMotion(0.3, 0.4) })
    } else {
      Stack() {
        HdsMiniBarButton({
          barWidth: 48,
          barHeight: 48,
          contentPadding: 0,
          containerSize: { width: 48, height: 48 },
          barBottomMargin: 0,
          barOverlap: true,
          barPosition: BarPosition.End
        }) {
          Image($r('app.media.chevron_down'))
            .width(20).height(20)
            .fillColor(this.floatBtnFollowTheme ? this.customThemeColor : (this.isDarkMode ? Color.White : Color.Black))
            .rotate({ angle: 180 })
        }
        Column()
          .width(48).height(48)
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.touchStartWX = event.touches[0].windowX;
              this.touchStartWY = event.touches[0].windowY;
              this.dragStartY = this.favoritesFloatBtnY;
              this.dragOffsetX = 0;
              this.isDragging = true;
            } else if (event.type === TouchType.Move) {
              const offYpx = event.touches[0].windowY - this.touchStartWY;
              const offXpx = event.touches[0].windowX - this.touchStartWX;
              this.favoritesFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
              this.dragOffsetX = Math.round(this.getUIContext().px2vp(offXpx));
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.isDragging = false;
              if (event.type === TouchType.Up) {
                const totalOffsetX: number = this.dragOffsetX;
                let newSide: string = this.favoritesFloatBtnSide;
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
                    this.dragOffsetX = 0;
                    if (sideChanged) {
                      this.favoritesFloatBtnSide = newSide;
                    }
                  });
                } else {
                  this.dragOffsetX = 0;
                }
                AppStorage.set('favoritesFloatBtnSide', this.favoritesFloatBtnSide);
                AppStorage.set('favoritesFloatBtnY', this.favoritesFloatBtnY);
                this.saveFloatBtnPrefs();
                this.triggerHaptic();
                animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                  this.btnScale = 0.8;
                });
                setTimeout(() => {
                  animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                    this.btnScale = 1;
                  });
                }, 100);
                if (this.pageMode === PageMode.FOLDER_LIST) {
                  this.folderScroller().scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                } else {
                  this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                }
              }
            }
          })
      }
      .width(48).height(48)
      .position(this.favoritesFloatBtnSide === 'left'
        ? { bottom: this.favoritesFloatBtnY, left: 32 }
        : { bottom: this.favoritesFloatBtnY, right: 32 })
      .opacity(this.showBackToTop ? 1 : 0)
      .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
      .hitTestBehavior(this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
      .animation(this.da || this.isDragging ? { duration: 0 } : { duration: 300, curve: Curve.Ease })
      .translate({ x: this.dragOffsetX })
    }
  }
}
