import { HomeInitialLoading } from '../components/HomeInitialLoading';
import { HOME_SEARCH_ROW_HEIGHT, homeHeaderTopInset } from '../utils/HomeHeaderLayout';
import { HomeBarScrollTracker } from '../utils/HomeBarScrollTracker';
import { HomeRefreshIndicator } from '../components/HomeRefreshIndicator';
import { VideoListItem, videoListPublished } from '../components/VideoListItem';
import { fetchRegionContent, REGION_TABS, RegionTab } from '../api/RegionApi';
import { RecommendItem } from '../model/RecommendItem';
import { prefetchVideoPlayback } from '../api/BilibiliApi';
import { GenericDataSource } from '../model/GenericDataSource';
import { logError } from '../utils/Logger';
import { VideoCardFeedback } from '../services/VideoCardFeedback';

class RegionContentState {
  items: RecommendItem[] = [];
  page: number = 0;
  hasMore: boolean = false;
  offset: number = 0;
  loaded: boolean = false;
  failed: boolean = false;
  pending: Promise<void> | null = null;
  revision: number = 0;
}

/** 首页分区：完整左侧列表，右侧展示对应的视频或节目索引。 */
@Component
export struct RegionChannelPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('cardListMargin') cardListMargin: number = 12;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('homeSearchRowHeight') homeSearchRowHeight: number = HOME_SEARCH_ROW_HEIGHT;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('refreshHomeFlag') @Watch('onRefreshFlagChange') refreshFlag: number = 0;
  @StorageLink('scrollToTopFlag') @Watch('onScrollToTop') scrollToTopFlag: number = 0;
  @State selectedRid: number = 0;
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State itemCount: number = 0;
  @State hasMore: boolean = false;
  @State contentOffset: number = 0;
  @State transitionActive: boolean = false;
  @State activePane: number = 0;
  @State paneRids: number[] = [0, 0];
  @State paneCounts: number[] = [0, 0];
  @State paneLoaded: boolean[] = [false, false];
  @State transitionDirection: number = 1;
  @State incomingItems: RecommendItem[] = [];
  @State incomingLoaded: boolean = false;
  private queuedRid: number | null = null;
  private paneScrollers: Scroller[] = [new Scroller(), new Scroller()];
  private paneDataSources: GenericDataSource<RecommendItem>[] = [new GenericDataSource(), new GenericDataSource()];
  private paneItemSets: RecommendItem[][] = [[], []];
  @State refreshReady: boolean = false;
  @State private contentWidth: number = 300;
  private generation: number = 0;
  private disposed: boolean = false;
  private page: number = 1;
  private ids: Set<string> = new Set();
  private regionStates: Map<number, RegionContentState> = new Map();
  private currentDataSource(): GenericDataSource<RecommendItem> { return this.paneDataSources[this.activePane]; }
  private currentScroller(): Scroller { return this.paneScrollers[this.activePane]; }
  private incomingDataSource(): GenericDataSource<RecommendItem> { return this.paneDataSources[1 - this.activePane]; }
  private incomingScroller(): Scroller { return this.paneScrollers[1 - this.activePane]; }
  private sidebarScroller: Scroller = new Scroller();
  private barScrollTracker: HomeBarScrollTracker = new HomeBarScrollTracker(20);

  aboutToAppear(): void { this.disposed = false; void this.loadRanking(true, true); }
  aboutToDisappear(): void { this.disposed = true; this.generation++; }
  private isActive(): boolean {
    return (AppStorage.get<boolean>('homeFeedActive') ?? false) && AppStorage.get<number>('homeChannelIndex') === 0;
  }

  private onCardFeedbackChange(): void {
    this.regionStates.forEach(state => {
      const items = state.items.filter(item => !VideoCardFeedback.isDismissed(item.id, item.ownerMid));
      if (items.length !== state.items.length) state.items = items;
    });
    if (!this.transitionActive) this.restoreRegion(this.regionState(this.selectedRid));
  }
  private onRefreshFlagChange(): void { if (this.isActive()) void this.loadRanking(true); }
  private onScrollToTop(): void {
    if (this.isActive()) this.currentScroller().scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: 260 } });
  }

  private regionState(rid: number): RegionContentState {
    let state = this.regionStates.get(rid);
    if (!state) {
      state = new RegionContentState();
      this.regionStates.set(rid, state);
    }
    return state;
  }

  private restoreRegion(state: RegionContentState, updateItems: boolean = true): void {
    if (updateItems && this.paneItemSets[this.activePane] !== state.items) {
      this.currentDataSource().reloadItems(state.items);
      this.paneItemSets[this.activePane] = state.items;
    }
    this.paneRids[this.activePane] = this.selectedRid;
    this.paneCounts[this.activePane] = state.items.length;
    this.paneLoaded[this.activePane] = state.loaded || state.failed;
    this.ids = new Set(state.items.map(item => item.id));
    this.itemCount = state.items.length;
    this.page = state.page;
    this.hasMore = state.hasMore;
    this.isLoading = !state.loaded && !state.failed;
    this.isRefreshing = false;
    this.loadingMore = false;
  }

  private prepareIncoming(state: RegionContentState): void {
    const pane = 1 - this.activePane;
    this.paneRids[pane] = this.selectedRid;
    this.paneCounts[pane] = state.items.length;
    this.paneLoaded[pane] = state.loaded || state.failed;
    this.incomingItems = state.items.slice();
    if (this.paneItemSets[pane] !== state.items) {
      this.incomingDataSource().reloadItems(state.items);
      this.paneItemSets[pane] = state.items;
    }
    this.incomingLoaded = state.loaded;
  }

  private async fetchRegionPage(rid: number, state: RegionContentState, page: number,
    refresh: boolean, revision: number): Promise<void> {
    try {
      const items = await fetchRegionContent(rid, page);
      if (this.disposed || revision !== state.revision) return;
      const all = refresh ? [] : state.items.slice();
      const ids = new Set(all.map(item => item.id));
      items.forEach(item => {
        if (item.id && !ids.has(item.id) && !VideoCardFeedback.isDismissed(item.id, item.ownerMid)) { ids.add(item.id); all.push(item); }
      });
      state.items = all;
      state.page = page;
      state.loaded = true;
      state.failed = false;
      state.hasMore = !!REGION_TABS.find(tab => tab.rid === rid)?.seasonType && items.length === 30;
      if (refresh) state.offset = 0;
    } catch (error) {
      if (!this.disposed && revision === state.revision) state.failed = true;
      throw new Error(String(error));
    } finally { if (revision === state.revision) state.pending = null; }
  }

  private async loadRanking(refresh: boolean, initial: boolean = false): Promise<void> {
    if (!refresh && (!this.hasMore || this.isLoading || this.loadingMore)) return;
    const state = this.regionState(this.selectedRid);
    if (initial && state.loaded) { this.restoreRegion(state); return; }
    const generation = refresh ? ++this.generation : this.generation;
    const rid = this.selectedRid;
    const page = refresh ? 1 : state.page + 1;
    if (refresh) this.isRefreshing = !initial;
    else this.loadingMore = true;
    try {
      if (!initial || !state.pending) {
        state.pending = this.fetchRegionPage(rid, state, page, refresh, ++state.revision);
      }
      await state.pending;
      if (this.disposed || generation !== this.generation || rid !== this.selectedRid) return;
      if (this.transitionActive) {
        this.prepareIncoming(state);
      } else this.restoreRegion(state);
    } catch (error) {
      logError('[RegionChannelPage] 获取分区失败', error);
      if (!this.disposed && generation === this.generation && rid === this.selectedRid) {
        if (this.transitionActive) this.prepareIncoming(state);
        else this.restoreRegion(state);
      }
    }
    finally {
      if (generation === this.generation && !this.transitionActive) {
        this.isLoading = false;
        this.isRefreshing = false;
        this.loadingMore = false;
      }
    }
  }

  private slideContent(offset: number): Promise<void> {
    return new Promise<void>(resolve => {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 260, curve: Curve.EaseOut, onFinish: resolve }, () => {
        this.contentOffset = offset;
      });
    });
  }

  private waitForPaneLayout(): Promise<void> {
    return new Promise<void>(resolve => { setTimeout(resolve, 32); });
  }

  private outgoingTranslation(progress: number): number {
    return -this.transitionDirection * this.contentWidth * progress;
  }

  private incomingTranslation(progress: number): number {
    return this.transitionDirection * this.contentWidth * (1 - progress);
  }

  private paneTranslation(pane: number): number {
    if (this.transitionActive) return pane === this.activePane
      ? this.outgoingTranslation(this.contentOffset) : this.incomingTranslation(this.contentOffset);
    return pane === this.activePane ? 0 : this.contentWidth;
  }

  private async onRegionSelect(rid: number): Promise<void> {
    if (this.transitionActive) { this.queuedRid = rid; return; }
    if (rid === this.selectedRid) return;
    const from = REGION_TABS.findIndex(tab => tab.rid === this.selectedRid);
    const to = REGION_TABS.findIndex(tab => tab.rid === rid);
    if (to < 0) return;
    const direction: number = to > from ? 1 : -1;
    const outgoing = this.regionState(this.selectedRid);
    if (outgoing.loaded) outgoing.offset = this.currentScroller().currentOffset().yOffset;
    ++this.generation;
    this.transitionDirection = direction;
    this.contentOffset = 0;
    this.transitionActive = true;
    this.selectedRid = rid;
    const state = this.regionState(rid);
    this.prepareIncoming(state);
    if (!state.loaded) void this.loadRanking(true, true);
    await this.waitForPaneLayout();
    if (this.disposed) return;
    this.incomingScroller().scrollTo({ xOffset: 0, yOffset: state.offset });
    await this.slideContent(1);
    if (this.disposed) return;
    // Promote the already rendered list, preserving its Image nodes and scroll position.
    this.activePane = 1 - this.activePane;
    this.restoreRegion(state, false);
    this.transitionActive = false;
    this.contentOffset = 0;
    this.incomingItems = [];
    const queued = this.queuedRid;
    this.queuedRid = null;
    if (queued !== null && queued !== rid) void this.onRegionSelect(queued);
  }

  private onCardClick(item: RecommendItem): void {
    const params: Record<string, Object> = {};
    params['title'] = item.title;
    params['coverUrl'] = item.coverUrl;
    if (item.pgcSeasonId > 0) {
      params['mediaId'] = item.pgcSeasonId;
      params['indexShow'] = item.ownerName;
    } else {
      params['bvid'] = item.id;
      params['aid'] = item.aid;
      params['ownerName'] = item.ownerName;
      params['cid'] = item.cid || 0;
      prefetchVideoPlayback(item.id || String(item.aid), item.cid || 0,
        AppStorage.get<number>('defaultVideoQn') ?? 116);
    }
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params
    }).catch((error: Error) => logError('[RegionChannelPage] 跳转失败', error));
  }

  @Builder
  private Sidebar() {
    Scroll(this.sidebarScroller) {
      Column() {
        ForEach(REGION_TABS, (tab: RegionTab) => {
          Stack({ alignContent: Alignment.Start }) {
            if (tab.rid === this.selectedRid) {
              Row().width(3).height(24).backgroundColor(this.customThemeColor).borderRadius(1)
            }
            Text(tab.name).fontSize(14).maxLines(1).width('100%').textAlign(TextAlign.Center)
              .fontWeight(tab.rid === this.selectedRid ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(tab.rid === this.selectedRid ? this.customThemeColor : (this.isDarkMode ? '#F2F3F5' : '#30343B'))
          }.width('100%').height(36).id(`region-tab-${tab.rid}`)
          .accessibilityText(`分区：${tab.name}`).onClick(() => { void this.onRegionSelect(tab.rid); })
        }, (tab: RegionTab) => tab.rid.toString())
      }.width('100%').padding({
        top: homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight),
        bottom: 100 + this.navIndicatorHeight
      })
    }.width(60).height('100%').align(Alignment.TopStart)
      .scrollable(ScrollDirection.Vertical).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  private RefreshIndicator() {
    HomeRefreshIndicator({ refreshing: this.isRefreshing, ready: this.refreshReady, color: this.customThemeColor })
  }

  private contentColumns(): number {
    return this.contentWidth >= 560 ? 2 : 1;
  }

  private contentItemWidth(): number {
    const columns = this.contentColumns();
    return Math.max(0, (this.contentWidth - 16 - (columns - 1) * this.cardListMargin) / columns);
  }

  @Builder
  private Content(pane: number) {
      List({ scroller: this.paneScrollers[pane], space: 0 }) {
        if (!this.paneLoaded[pane] && this.paneCounts[pane] === 0) {
          ListItem() {
            HomeInitialLoading({ color: this.customThemeColor, refreshing: this.isRefreshing || this.refreshReady })
          }
        } else if (this.paneCounts[pane] === 0) {
          ListItem() {
            Column({ space: 12 }) {
              Text('暂未获取到内容').fontSize(14).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
              Text('点击重试').fontSize(13).fontColor(this.customThemeColor).onClick(() => { void this.loadRanking(true); })
            }.width('100%').height(220).justifyContent(FlexAlign.Center)
          }
        }
        LazyForEach(this.paneDataSources[pane], (item: RecommendItem) => {
          ListItem() {
            VideoListItem({ title: item.title, cover: item.coverUrl, duration: item.duration, owner: item.ownerName,
              showDivider: false,
              videoId: item.pgcSeasonId > 0 ? '' : item.id, ownerMid: item.ownerMid,
              playCount: item.pgcSeasonId > 0 ? -1 : item.playCount,
              dateText: videoListPublished(item.pubdate), detailText: item.rcmdReason,
              onActivate: () => this.onCardClick(item) })
              .clickEffect({ level: 0, scale: 0.9 })
          }.width(this.contentItemWidth())
        }, (item: RecommendItem) => `${this.paneRids[pane]}:${item.id}`)
        if (pane === this.activePane && this.loadingMore) { ListItem() { LoadingProgress().width(24).height(32).color(this.customThemeColor) } }
      }.width('100%').height('100%').scrollBar(BarState.Off).cachedCount(8)
      .lanes(this.paneCounts[pane] > 0 ? this.contentColumns() : 1, this.cardListMargin)
      .padding({ left: 8, right: 8 })
      .contentStartOffset(homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight))
      .contentEndOffset(100 + this.navIndicatorHeight)
      .onReachEnd(() => { if (pane === this.activePane && this.isActive() && !this.transitionActive) void this.loadRanking(false); })
      .onDidScroll(() => {
        if (pane !== this.activePane || !this.isActive() || this.transitionActive) return;
        const offset = Math.max(0, this.currentScroller().currentOffset().yOffset);
        this.regionState(this.selectedRid).offset = offset;
        AppStorage.setOrCreate('homeScrollOffset', offset);
      })
      .onWillScroll((yOffset: number, _state: ScrollState, source: ScrollSource) => {
        if (pane !== this.activePane || !this.isActive() || yOffset === 0) return;
        if (this.transitionActive) return;
        const hidden = this.barScrollTracker.update(yOffset, source);
        if (hidden !== undefined) {
          AppStorage.setOrCreate('homeBarsHidden', hidden);
          AppStorage.setOrCreate('tabBarHidden', hidden);
        }
      })
  }

  build() {
    Row() {
      this.Sidebar()
      // One native refresh controller owns the active region; panes retain their lists only.
      Refresh({ refreshing: $$this.isRefreshing, builder: this.RefreshIndicator() }) {
      Stack() {
        Column() { this.Content(0) }.width('100%').height('100%')
          .translate({ x: this.paneTranslation(0) })
          .hitTestBehavior(this.activePane === 0 && !this.transitionActive ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.activePane === 0 && !this.transitionActive ? 'auto' : 'no-hide-descendants')
        Column() { this.Content(1) }.width('100%').height('100%')
          .translate({ x: this.paneTranslation(1) })
          .hitTestBehavior(this.activePane === 1 && !this.transitionActive ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.activePane === 1 && !this.transitionActive ? 'auto' : 'no-hide-descendants')
      }.width('100%').height('100%').clip(true)
      .onAreaChange((_old, area) => { this.contentWidth = Number(area.width); })
      }.layoutWeight(1).height('100%')
      .onStateChange((state: RefreshStatus) => { this.refreshReady = state === RefreshStatus.OverDrag; })
      .onRefreshing(() => {
        if (!this.transitionActive) void this.loadRanking(true);
        else this.isRefreshing = false;
      })
    }.width('100%').height('100%').alignItems(VerticalAlign.Top)
    .padding({ right: 12 })
  }
}
