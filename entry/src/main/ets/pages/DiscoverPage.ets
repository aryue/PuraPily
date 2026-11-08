import { HomeInitialLoading } from '../components/HomeInitialLoading';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { HOME_SEARCH_ROW_HEIGHT, homeHeaderTopInset } from '../utils/HomeHeaderLayout';
import { VideoCardMenu } from '../services/VideoCardMenu';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { VideoListItem, videoListPublished } from '../components/VideoListItem';
import { HomeBarScrollTracker } from '../utils/HomeBarScrollTracker';
import { HomeRefreshIndicator } from '../components/HomeRefreshIndicator';
// DiscoverPage.ets - 热门横向列表：四成宽封面、双行标题、UP与播放时间。
// 使用媒体查询监听横竖屏变化，响应式更新列表列数。
import { common } from '@kit.AbilityKit';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { window, mediaquery } from '@kit.ArkUI';
import { getPopularVideos, blacklistUploader, prefetchVideoPlayback } from '../api/BilibiliApi';
import { RecommendItem } from '../model/RecommendItem';
import { sendDislikeFeedback, sendDislikeUpFeedback } from '../api/FeedbackService';
import { UserBehaviorService } from '../services/UserBehaviorService';
import { GenericDataSource } from '../model/GenericDataSource';

@Component({ freezeWhenInactive: true })
export struct DiscoverPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  // ★ 由父组件传入，供 Scroll 组件和 HdsNavigation.bindToScrollable 使用
  externalScroller: Scroller = new Scroller();
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('cardListMargin') cardListMargin: number = 12;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('floatingBottomBar') floatingBottomBar: boolean = true;
  @StorageLink('homeSearchRowHeight') homeSearchRowHeight: number = HOME_SEARCH_ROW_HEIGHT;
  @StorageLink('scrollToTopFlag') @Watch('onScrollToTop') scrollToTopFlag: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('pageShowCounter') @Watch('onPageShowReset') pageShowCounter: number = 0;
  @StorageLink('refreshDiscoverFlag') @Watch('onRefreshDiscoverFlagChange') refreshDiscoverFlag: number = 0;
  @StorageLink('homeScrollOffset') homeScrollOffset: number = 0;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('da') da: boolean = false;
  // 滚动隐藏底栏相关
  private barScrollTracker: HomeBarScrollTracker = new HomeBarScrollTracker();
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  private dataSource: GenericDataSource<RecommendItem> = new GenericDataSource();
  @State isLoading: boolean = true;
  @State isLoadingMore: boolean = false;
  @State isRefreshing: boolean = false;
  @State pageNum: number = 1;
  @State isLandscape: boolean = false;      // 当前是否横屏
  @State columnCount: number = 1;           // 600vp 以上双列，窄窗口单列
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.dataSource.removeItems(item => VideoCardFeedback.isDismissed(item.id, item.ownerMid));
  }
  @State private contentWidth: number = 360;
  private pageSize: number = 20;
  private hasMore: boolean = true;
  private isPageActive: boolean = true;

  // 底部弹窗相关状态

  // 媒体查询监听器
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  // 入场动画相关

  async aboutToAppear() {
    if (AppStorage.get('scrollToTopFlag') === undefined) {
      AppStorage.setOrCreate('scrollToTopFlag', 0);
    }
    this.getStatusBarHeight();
    await this.initOrientationAndMediaQuery();
    this.loadData(true);
  }

  aboutToDisappear() {
    // 移除媒体查询监听
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  onPageShow() {
    this.isPageActive = true;
    // 重新检查方向，确保从播放器返回后方向正确
    this.updateOrientationFromWindow();
  }

  onPageHide() {
    this.isPageActive = false;
  }

  onPageShowReset() {
    this.isRefreshing = false;
    this.refreshReady = false;
  }

  @Watch('onHideStatusBarChange')
  @StorageLink('hideStatusBar') watchHideStatusBarLink: boolean = false;

  private onHideStatusBarChange() {
    if (this.hideStatusBar) {
      this.statusBarHeight = 0;
    } else {
      const cached = AppStorage.get<number>('realStatusBarHeight');
      if (cached && cached > 0) {
        this.statusBarHeight = cached;
      } else {
        this.getStatusBarHeight();
      }
    }
  }

  private onScrollToTop() {
    if (this.externalScroller) {
      this.externalScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300 } });
    }
  }

  private onRefreshDiscoverFlagChange() {
    this.loadData(true);
    // ⭐ 程序化刷新不触发 Refresh 下拉头部
    this.isRefreshing = false;
  }

  // 通过窗口属性更新方向（用于手动触发）
  private updateOrientationFromWindow() {
    const mainWindow = AppStorage.get<window.Window>('mainWindow');
    if (mainWindow) {
      try {
        const props = mainWindow.getWindowProperties();
        const newIsLandscape = props.windowRect.width > props.windowRect.height;
        if (this.isLandscape !== newIsLandscape) {
          this.isLandscape = newIsLandscape;
          this.updateColumnCount();
        }
      } catch (err) {
        logWarn(`updateOrientationFromWindow 异常: ${errMsg(err)}`);
      }
    }
  }

  // 初始化方向并注册媒体查询监听
  private async initOrientationAndMediaQuery() {
    // 获取当前方向（优先从 AppStorage，取不到则直接从 context 获取）
    let mainWindow = AppStorage.get<window.Window>('mainWindow');
    if (!mainWindow) {
      try {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        mainWindow = await window.getLastWindow(context);
      } catch (e) {
        logWarn('[DiscoverPage] 无法获取窗口对象:', e);
      }
    }
    if (mainWindow) {
      try {
        const props = mainWindow.getWindowProperties();
        this.isLandscape = props.windowRect.width > props.windowRect.height;
        this.updateColumnCount();
        logInfo(`[DiscoverPage] 初始方向: ${this.isLandscape ? '横屏' : '竖屏'}, 列数=${this.columnCount}`);
      } catch (err) {
        logWarn(`initOrientationAndMediaQuery 异常: ${errMsg(err)}`);
      }
    }

    // 注册媒体查询监听横竖屏变化（官方推荐方式）
    const mediaQuery = this.getUIContext().getMediaQuery();
    this.landscapeListener = mediaQuery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      if (!this.isPageActive) return;
      const newIsLandscape = result.matches;
      if (this.isLandscape !== newIsLandscape) {
        this.isLandscape = newIsLandscape;
        this.updateColumnCount();
        logInfo(`[DiscoverPage] 方向变化，横屏=${this.isLandscape}, 列数=${this.columnCount}`);
      }
    });
  }

  private updateColumnCount() {
    this.columnCount = this.contentWidth >= 600 ? 2 : 1;
  }

  private async loadData(refresh: boolean = false) {
    if (refresh) {
      this.pageNum = 1;
      this.hasMore = true;
      this.isLoading = true;
      this.isRefreshing = this.dataSource.totalCount() > 0;
    } else {
      if (this.isLoadingMore || !this.hasMore) return;
      this.isLoadingMore = true;
    }
    const newItems = await getPopularVideos(this.pageNum, this.pageSize);
    // ⭐ 只过滤已屏蔽的UP主，不过滤已看视频
    const filteredItems = UserBehaviorService.filterBlockedUploadersOnly(newItems);
    if (filteredItems.length > 0) {
      if (refresh) {
        this.dataSource.reloadItems(filteredItems);
      } else {
        this.dataSource.addItems(filteredItems);
      }
      this.pageNum++;
    } else {
      this.hasMore = false;
    }
    this.isLoading = false;
    this.isRefreshing = false;
    this.isLoadingMore = false;
  }


  private onRefresh() {
    this.loadData(true);
  }

  private loadMore() {
    if (!this.isLoadingMore && this.hasMore && !this.isRefreshing) {
      this.loadData(false);
    }
  }

  private onCardClick(item: RecommendItem) {
    // ⭐ 预热详情（fire-and-forget）：把加载详情的 RTT 藏在转场+播放器初始化期间
    prefetchVideoPlayback(item.id.startsWith('BV') ? item.id : (item.aid > 0 ? String(item.aid) : item.id), item.cid || 0,
      AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: item.id,
        aid: item.aid,  // ⭐ App API 的项只有 aid，没有 bvid
        title: item.title,
        ownerName: item.ownerName,
        coverUrl: item.coverUrl,
        cid: item.cid || 0
      }
    }).catch((err: Error) => {
      logError(`跳转播放页失败: ${err.message}`);
    });
  }

  /**
   * ⭐ 显示视频菜单（底部弹窗）
   */
  private showVideoMenu(item: RecommendItem): void {
    void VideoCardMenu.show(this.getUIContext(), item.title, item.pgcSeasonId > 0 ? '' : item.id, item.ownerMid, this.isDarkMode);
  }

  /**
   * ⭐ 处理不感兴趣
   */
  private async handleDislike(item: RecommendItem): Promise<void> {
    try {
      const result = await sendDislikeFeedback(item.id, 1);
      this.removeVideoFromList(item.id);
      if (result.success) {
        this.getUIContext().getPromptAction().showToast({ message: '已减少此类推荐', duration: 1500 });
        logInfo(`[不感兴趣] ✅ ${item.id} - ${item.title}`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '已移除（服务器反馈暂不可用）', duration: 1500 });
        logInfo(`[不感兴趣] ⚠️ 本地移除 ${item.id}（${result.message}）`);
      }
    } catch (err) {
      logError(`[不感兴趣] 异常: ${err}`);
      try { this.removeVideoFromList(item.id); } catch (_) { }
      this.getUIContext().getPromptAction().showToast({ message: '已移除', duration: 1500 });
    }
  }

  /**
   * ⭐ 屏蔽UP主
   */
  private async handleBlockUploader(item: RecommendItem): Promise<void> {
    try {
      const result = await sendDislikeUpFeedback(item.id, item.ownerMid);
      UserBehaviorService.addBlockedUploader(item.ownerMid);
      this.removeVideosByUploader(item.ownerMid);
      if (result.success) {
        this.getUIContext().getPromptAction().showToast({ message: `已屏蔽 ${item.ownerName}`, duration: 1500 });
        logInfo(`[屏蔽UP主] ✅ ${item.ownerMid} - ${item.ownerName}`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: `已本地屏蔽 ${item.ownerName}`, duration: 1500 });
        logInfo(`[屏蔽UP主] ⚠️ 本地屏蔽 ${item.ownerMid}（${result.message}）`);
      }
    } catch (err) {
      logError(`[屏蔽UP主] 异常: ${err}`);
      try {
        UserBehaviorService.addBlockedUploader(item.ownerMid);
        this.removeVideosByUploader(item.ownerMid);
      } catch (_) { }
      this.getUIContext().getPromptAction().showToast({ message: `已本地屏蔽 ${item.ownerName}`, duration: 1500 });
    }
  }

  /**
   * ⭐ 拉黑UP主（API拉黑）
   */
  private async handleBlacklistUploader(item: RecommendItem): Promise<void> {
    try {
      const result = await blacklistUploader(Number(item.ownerMid));
      if (result) {
        // 拉黑成功，也加入本地屏蔽列表
        UserBehaviorService.addBlockedUploader(item.ownerMid);
        this.removeVideosByUploader(item.ownerMid);
        this.getUIContext().getPromptAction().showToast({ message: `已拉黑 ${item.ownerName}`, duration: 1500 });
        logInfo(`[拉黑UP主] ${item.ownerMid} - ${item.ownerName}`);
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '拉黑失败，请检查登录状态', duration: 2000 });
      }
    } catch (err) {
      this.getUIContext().getPromptAction().showToast({ message: '操作失败', duration: 1500 });
    }
  }

  /**
   * ⭐ 标记为看过类似视频
   */
  private async handleSeenBefore(item: RecommendItem): Promise<void> {
    this.removeVideoFromList(item.id);
    try {
      this.getUIContext().getPromptAction().showToast({ message: '已标记为看过', duration: 1500 });
    } catch (err) {
      logWarn(`showToast 异常: ${errMsg(err)}`);
    }
  }

  /**
   * ⭐ 从列表中移除单个视频
   */
  private removeVideoFromList(bvid: string) {
    this.dataSource.removeItem((item: RecommendItem) => item.id === bvid);
  }

  /**
   * ⭐ 移除某UP主的所有视频
   */
  private removeVideosByUploader(mid: string) {
    this.dataSource.removeItems((item: RecommendItem) => item.ownerMid === mid);
  }

  @State refreshReady: boolean = false;

  @Builder
  customRefreshComponent() {
    HomeRefreshIndicator({ refreshing: this.isRefreshing, ready: this.refreshReady, color: this.customThemeColor })
  }

  /**
   * ⭐ 底部菜单弹窗内容
   */


  /**
   * ⭐ 菜单项按钮
   */
  @Builder
  MenuItemButton(text: string, onClick: () => void, isCancelButton: boolean = false) {
    Text(text)
      .fontSize(15)
      .fontColor(isCancelButton ? '#FFFFFF' : (this.isDarkMode ? '#FFFFFF' : '#000000'))
      .width('100%')
      .height(50)
      .textAlign(TextAlign.Center)
      .backgroundColor(isCancelButton ? this.customThemeColor : (this.isDarkMode ? '#2A2A2A' : '#F5F5F5'))
      .borderRadius(20)
      .onClick(() => onClick())
  }

  @Builder
  VideoCard(item: RecommendItem) {
    VideoListItem({
      showDivider: false,
      title: item.title, cover: item.coverUrl, duration: item.duration,
      videoId: item.pgcSeasonId > 0 ? '' : item.id, ownerMid: item.ownerMid,
      owner: item.ownerName, playCount: item.playCount,
      dateText: videoListPublished(item.pubdate), tag: item.rcmdReason,
      onActivate: (): void => { this.onCardClick(item); },
      onMore: () => this.showVideoMenu(item), onHold: () => this.showVideoMenu(item)
    })
    .clickEffect({ level: 0, scale: 0.9 })
  }

  async getStatusBarHeight() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const windowClass: window.Window = await window.getLastWindow(context);
      const avoidArea = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const h = this.getUIContext().px2vp(avoidArea.topRect.height);
      if (h > 0) {
        this.statusBarHeight = h;
        AppStorage.setOrCreate('realStatusBarHeight', h);
      }
    } catch (error) {
      // 保留已有值
    }
  }

  @Builder
  listFooter() {
    Column() {
      if (this.isLoading && this.dataSource.totalCount() === 0) {
        HomeInitialLoading({ color: this.customThemeColor, refreshing: this.isRefreshing || this.refreshReady })
      } else if (this.isLoadingMore) {
        Row({ space: 8 }) {
          LoadingProgress().width(24).height(24).color(this.customThemeColor)
          Text('加载更多...').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
        }.width('100%').height(40).justifyContent(FlexAlign.Center)
      } else if (!this.hasMore && this.dataSource.totalCount() > 0) {
        Text('没有更多了').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
          .width('100%').height(40).textAlign(TextAlign.Center)
      }
    }.width('100%').padding({ bottom: this.floatingBottomBar ? 100 + this.navIndicatorHeight : 16 })
  }

  build() {
    Refresh({ refreshing: $$this.isRefreshing, builder: this.customRefreshComponent() }) {
      // Keep the viewport full-height; the header clearance scrolls with the items.
      List({ scroller: this.externalScroller, space: 0 }) {
        ListItemGroup({ footer: this.listFooter }) {
          LazyForEach(this.dataSource, (item: RecommendItem) => {
            ListItem() { this.VideoCard(item) }
              .width(Math.max(0, (this.contentWidth - 24 - (this.columnCount - 1) * this.cardListMargin) / this.columnCount))
          }, (item: RecommendItem) => item.id)
        }
      }
      .lanes(this.columnCount, this.cardListMargin)
      .contentStartOffset(homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight))
      .padding({ left: 12, right: 12 })
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      .onWillScroll((yOffset: number, _state: ScrollState, source: ScrollSource) => {
        if (!AppStorage.get<boolean>('homeFeedActive') || yOffset === 0 || AppStorage.get<number>('homeChannelIndex') !== 3) return;
        const absoluteOffset = this.externalScroller.currentOffset().yOffset;
        this.homeScrollOffset = absoluteOffset;
        AppStorage.set('homeScrollOffset', absoluteOffset);
        const hidden = this.barScrollTracker.update(yOffset, source);
        if (hidden !== undefined) AppStorage.set('homeBarsHidden', hidden);
      })
      .onReachEnd(() => {
        if (!this.isLoadingMore && !this.isLoading && !this.isRefreshing && this.hasMore) this.loadMore();
      })
    }
    .onStateChange((refreshStatus: RefreshStatus) => {
      this.refreshReady = refreshStatus === RefreshStatus.OverDrag;
    })
    .onRefreshing(() => this.onRefresh())
    .width('100%')
    .height('100%')
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.contentWidth = Number(size.width);
      this.columnCount = this.contentWidth >= 600 ? 2 : 1;
    })
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
