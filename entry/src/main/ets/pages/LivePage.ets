import { HomeInitialLoading } from '../components/HomeInitialLoading';
import { cardItemBg } from '../utils/CardStyle';
import { ChannelCardSurface } from '../components/ChannelCardSurface';
import { HOME_SEARCH_ROW_HEIGHT, homeHeaderTopInset } from '../utils/HomeHeaderLayout';
import { VideoCardMoreButton } from '../components/VideoCardMoreButton';
import { HomeBarScrollTracker } from '../utils/HomeBarScrollTracker';
import { HomeRefreshIndicator } from '../components/HomeRefreshIndicator';
import { VibrateUtils } from '../utils/VibrateUtils';
/**
 * LivePage.ets — 直播信息流页面（B站风格）
 *
 * 功能：
 * - 顶部悬浮毛玻璃分区 Tab 栏（在历史/搜索按钮下方）
 * - 信息流穿透效果：内容在 Tab 栏下方滚动
 * - 2列直播卡片网格
 * - 下拉刷新 + 上拉加载更多
 */
import { mediaquery, display } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  LiveFeedRoom,
  LiveArea,
  fetchRecommendedLiveRooms,
  fetchLiveRoomsByArea,
  fetchLiveAreas,
  fetchFollowedLiveRooms,
  formatOnlineCount
} from '../api/LiveFeedApi';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { HdsMiniBarButton } from '../components/infra/HdsMiniBarButton';

/** 数据源封装，供 LazyForEach 使用 */
class LiveDataSource implements IDataSource {
  private items: LiveFeedRoom[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): LiveFeedRoom {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener);
    if (pos >= 0) this.listeners.splice(pos, 1);
  }

  notifyDataReload(): void {
    this.listeners.forEach(listener => listener.onDataReloaded());
  }

  notifyDataAdd(startIndex: number): void {
    this.listeners.forEach(listener => listener.onDataAdd(startIndex));
  }

  addItems(newItems: LiveFeedRoom[]): void {
    const startIdx = this.items.length;
    this.items.push(...newItems);
    this.notifyDataAdd(startIdx);
  }

  reloadItems(allItems: LiveFeedRoom[]): void {
    this.items = allItems;
    this.notifyDataReload();
  }

  getRawItems(): LiveFeedRoom[] {
    return this.items;
  }
}

interface AreaTab {
  id: number;
  name: string;
  isSelected: boolean;
  pinned: boolean;
}

@Component({ freezeWhenInactive: true })
export struct LivePage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('floatingBottomBar') floatingBottomBar: boolean = true;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#00A1D6';
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('homeSearchRowHeight') homeSearchRowHeight: number = HOME_SEARCH_ROW_HEIGHT;
  @StorageLink('scrollToTopFlag') @Watch('onScrollToTop') scrollToTopFlag: number = 0;
  @StorageLink('tabBarHidden') tabBarHidden: boolean = false;
  @StorageLink('refreshLiveFlag') @Watch('onRefreshFlagChange') refreshFlag: number = 0;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardListBorderRadius') cardListBorderRadius: number = 12;
  @StorageLink('cardListMargin') cardListMargin: number = 0;
  @StorageLink('cardStyleLiveCategory') cardStyleLiveCategory: boolean = true;
  @StorageLink('livePanelCollapseSignal') @Watch('onCollapseSignal') livePanelCollapseSignal: number = 0;
  @StorageLink('da') da: boolean = false;

  // 数据
  @State dataSource: LiveDataSource = new LiveDataSource();
  @State areas: AreaTab[] = [{ id: 0, name: '全部', isSelected: true, pinned: true }];
  @State selectedAreaId: number = 0;

  // ⭐ 关注的UP主正在直播列表（信息流上方横向区块）
  @State followedLiveRooms: LiveFeedRoom[] = [];
  @State showAllFollowed: boolean = false;   // 关注主播折叠展开
  private followedLoading: boolean = false;  // 防止重复请求

  // 加载状态
  private barScrollTracker: HomeBarScrollTracker = new HomeBarScrollTracker(20);
  // ⭐ 滚动方向阈值：与分类页一致，delta 为自上次触发以来的累积位移，慢速滑动也能触发显隐
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = true;

  // 分页
  private pageNum: number = 1;
  private readonly PAGE_SIZE: number = 30;

  // 已显示的 roomId 集合（去重）
  private roomIdSet: Set<number> = new Set();

  // 滚动控制器
  private scroller: Scroller = new Scroller();
  private tabScroller: Scroller = new Scroller();

  // 折叠展开
  @State isCategoriesExpanded: boolean = false;
  @State isEditing: boolean = false;
  private readonly MAX_VISIBLE_TABS: number = 4;
  /** ⭐ 长条胶囊宽度（动态计算） */
  @State liveBarW: number = 200;

  // 下拉刷新状态


  // 横竖屏检测
  @State isLandscape: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  private readonly TAB_BAR_HEIGHT: number = 56;
  private headerTopInset(): number {
    // Match the visible popular card edge, including VideoListItem's top spacing.
    return homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight) + this.cardListMargin / 2;
  }

  private visibleFilterHeight(): number {
    return 0;
  }

  aboutToAppear() {
    this.loadLiveRooms(true);
    this.loadFollowedLiveRooms();
    this.setupMediaQuery();
  }

  /** ⭐ 动态计算长条胶囊宽度：根据标签文字内容自适应，不占满屏幕 */
  private recalcLiveBarW(): void {
    try {
      const d = display.getDefaultDisplaySync();
      const screenW = this.getUIContext().px2vp(d.width);
      const maxBarW = Math.max(200, screenW - 24 - 16);
      const pinnedTabs = this.areas.filter((t: AreaTab) => t.pinned);
      if (pinnedTabs.length === 0) {
        this.liveBarW = maxBarW;
        return;
      }
      const fontSize = 14;
      const itemPadding = 24;
      const itemSpace = 8;
      const rowPadding = 8;
      let totalW = rowPadding;
      for (const tab of pinnedTabs) {
        let textW = 0;
        for (const ch of tab.name) {
          textW += (ch.charCodeAt(0) > 0x4e00 && ch.charCodeAt(0) < 0x9fff) ? fontSize : fontSize * 0.55;
        }
        totalW += textW + itemPadding + itemSpace;
      }
      totalW -= itemSpace;
      this.liveBarW = Math.min(totalW, maxBarW);
    } catch (_) {
      this.liveBarW = 340;
    }
  }

  aboutToDisappear() {
    this.landscapeListener?.off('change');
  }

  private setupMediaQuery(): void {
    this.landscapeListener = this.getUIContext().getMediaQuery().matchMediaSync('(min-aspect-ratio: 1.4)');
    this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isLandscape = result.matches;
    });
    this.isLandscape = this.landscapeListener.matches;
  }

  // ==================== 数据加载 ====================

  private async loadAreas(): Promise<void> {
    try {
      const areas = await fetchLiveAreas();
      if (areas.length > 0) {
        // 先按默认方式创建
        let tabList: AreaTab[] = areas.map((a: LiveArea, idx: number) => ({
          id: a.id,
          name: a.name,
          isSelected: a.id === this.selectedAreaId,
          pinned: idx < this.MAX_VISIBLE_TABS
        }) as AreaTab);
        // 从 Preferences 恢复保存的 pinned 状态
        const savedIds: number[] = await this.loadPinnedAreaIds();
        if (savedIds.length > 0) {
          tabList = tabList.map((tab: AreaTab) => ({
            id: tab.id,
            name: tab.name,
            isSelected: tab.isSelected,
            pinned: savedIds.indexOf(tab.id) >= 0
          }) as AreaTab);
        }
        this.areas = tabList;
      }
      this.recalcLiveBarW();
    } catch (err) {
      logError(`[LivePage] 加载分区失败: ${err}`);
    }
  }

  // 持久化：保存已固定的分区ID列表
  private async savePinnedAreas(): Promise<void> {
    try {
      const pinnedIds: number[] = this.areas
        .filter((a: AreaTab) => a.pinned)
        .map((a: AreaTab) => a.id);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('livePinnedAreas', JSON.stringify(pinnedIds));
      await pref.flush();
    } catch (_e) {}
  }

  // 持久化：读取之前保存的固定分区ID列表
  private async loadPinnedAreaIds(): Promise<number[]> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref: preferences.Preferences = await preferences.getPreferences(context, 'my_app_settings');
      const raw: string = await pref.get('livePinnedAreas', '') as string;
      if (raw) {
        return JSON.parse(raw) as number[];
      }
    } catch (_e) {}
    return [];
  }

  private async loadLiveRooms(isRefresh: boolean): Promise<void> {
    try {
      if (isRefresh) {
        this.isLoading = true;
        this.pageNum = 1;
        this.roomIdSet.clear();
      } else {
        this.isLoadingMore = true;
      }

      let rooms: LiveFeedRoom[];
      if (this.selectedAreaId === 0) {
        rooms = await fetchRecommendedLiveRooms(this.pageNum, this.PAGE_SIZE);
      } else {
        rooms = await fetchLiveRoomsByArea(this.selectedAreaId, this.pageNum, this.PAGE_SIZE);
      }

      const uniqueRooms: LiveFeedRoom[] = [];
      for (const room of rooms) {
        if (!this.roomIdSet.has(room.roomId)) {
          this.roomIdSet.add(room.roomId);
          uniqueRooms.push(room);
        }
      }

      if (isRefresh) {
        this.dataSource.reloadItems(uniqueRooms);
      } else {
        this.dataSource.addItems(uniqueRooms);
      }

      this.hasMore = uniqueRooms.length >= this.PAGE_SIZE;
      this.pageNum++;
    } catch (err) {
      logError(`[LivePage] 加载直播列表失败: ${err}`);
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
      this.isLoadingMore = false;
    }
  }

  /**
   * ⭐ 加载关注的UP主中正在直播的房间（信息流上方区块）
   * 需要登录 Cookie；失败时静默清空区块
   */
  private async loadFollowedLiveRooms(): Promise<void> {
    if (this.followedLoading) return;
    this.followedLoading = true;
    try {
      const rooms: LiveFeedRoom[] = await fetchFollowedLiveRooms(1, 50);
      this.followedLiveRooms = rooms;
      this.showAllFollowed = false;
    } catch (err) {
      logError(`[LivePage] 加载关注直播失败: ${err}`);
      this.followedLiveRooms = [];
    } finally {
      this.followedLoading = false;
    }
  }



  private onScrollToTop(): void {
    if (this.scroller) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300 } });
    }
  }

  private onRefreshFlagChange(): void {
    this.loadLiveRooms(true);
    this.loadFollowedLiveRooms();
  }

  private onRefresh(): void {
    this.isRefreshing = true;
    this.loadLiveRooms(true);
    this.loadFollowedLiveRooms();
  }

  private loadMore(): void {
    if (this.isLoadingMore || !this.hasMore || this.isRefreshing) return;
    this.loadLiveRooms(false);
  }

  private onAreaSelect(areaId: number): void {
    if (areaId === this.selectedAreaId) return;
    this.selectedAreaId = areaId;
    this.areas = this.areas.map(a => ({
      id: a.id,
      name: a.name,
      isSelected: a.id === areaId,
      pinned: a.pinned
    }) as AreaTab);
    this.loadLiveRooms(true);
  }

  // ==================== 页面跳转 ====================

  private enterRoom(room: LiveFeedRoom): void {
    if (room.roomId <= 0) return;
    this.collapsePanel();
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LivePlayerPage',
      params: { roomId: room.roomId, rooms: [room, ...this.dataSource.getRawItems().filter(item => item.roomId !== room.roomId)],
        roomIds: this.dataSource.getRawItems().map(item => item.roomId),
        areaId: this.selectedAreaId, roomPage: this.pageNum }
    });
  }

  // ==================== 工具方法 ====================

  getThemeColor(): string {
    return this.customThemeColor || '#00A1D6';
  }

  private expandPanel(): void {
    this.isCategoriesExpanded = true;
    this.recalcLiveBarW();
  }

  private collapsePanel(): void {
    this.isCategoriesExpanded = false;
    this.recalcLiveBarW();
    if (this.isEditing) {
      this.isEditing = false;
      this.savePinnedAreas();
    }
  }

  private onCollapseSignal(): void {
    this.collapsePanel();
  }

  private formatShortCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万';
    }
    return String(count);
  }

  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  private get cardBg(): string {
    // 使用稍微不同的颜色以区分页面背景
    return this.isDarkMode ? '#1E1E1E' : '#FAFAFA';
  }

  // ⭐ 面板展开时悬浮 Tab 栏向左滑出屏幕的距离（需大于屏宽，确保完全滑出）
  private panelSlideOutX(): number {
    return 1200;
  }

  // ⭐ 页面显示/隐藏时重置下拉状态
  onPageShow(): void {
    this.isRefreshing = false;
    this.refreshReady = false;
  }

  // ==================== 构建UI ====================

  @State refreshReady: boolean = false;

  @Builder
  customRefreshComponent() {
    HomeRefreshIndicator({ refreshing: this.isRefreshing, ready: this.refreshReady, color: this.getThemeColor() })
  }

  /**
   * ⭐ 直播卡片
   */
  @Builder
  LiveCard(room: LiveFeedRoom) {
    Stack() {
      ChannelCardSurface({ radius: this.cardListBorderRadius }) {
        Column() {
          // ---- 封面区 ----
          Stack() {
            Image(room.cover ? room.cover : '')
              .width('100%')
              .aspectRatio(16 / 9)
              .objectFit(ImageFit.Cover)
              .backgroundColor(this.isDarkMode ? '#333333' : '#E8E8E8')
              .draggable(false)

            // 底部渐变遮罩
            Row()
              .width('100%')
              .height(40)
              .position({ bottom: 0 })
              .linearGradient({
                direction: GradientDirection.Bottom,
                colors: [['#00000000', 0], ['#CC000000', 1]]
              })

            // 左上角"直播"角标
            Row() {
              Circle().width(7).height(7).fill('#FF4D4D')
              Text('直播')
                .fontSize(11)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
                .margin({ left: 4 })
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .backgroundColor('rgba(255,77,77,0.85)')
            .borderRadius(4)
            .position({ top: 6, left: 6 })

            // 右上角观看人数
            Row() {
              Image($r('app.media.ic_public_screencap'))
                .width(12).height(12)
                .fillColor(Color.White)
              Text(formatOnlineCount(room.online))
                .fontSize(11)
                .fontColor(Color.White)
                .margin({ left: 3 })
            }
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('rgba(0,0,0,0.55)')
            .borderRadius(4)
            .position({ bottom: 6, right: 6 })

            // 分区标签
            if (room.areaName) {
              Text(room.areaName)
                .fontSize(10)
                .fontColor('rgba(255,255,255,0.9)')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('rgba(0,0,0,0.4)')
                .borderRadius(3)
                .position({ bottom: 6, left: 6 })
            }
          }
          .width('100%')
          .borderRadius(this.cardListBorderRadius)
          .clip(true)
          .backgroundColor(this.isDarkMode ? '#333333' : '#F0F0F0') // 封面容器背景

          // ---- 标题 ----
          Text(room.title || '未命名直播')
            .fontSize(14)
            .fontColor(this.isDarkMode ? Color.White : Color.Black)
            .maxLines(2)
            .height(40)
            .lineHeight(20)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 8, left: 2, right: 2 })
            .width('100%')

          // ---- 主播信息行 ----
          Row() {
            if (room.face) {
              Image(room.face)
                .width(20).height(20)
                .borderRadius(10)
                .margin({ right: 5 })
                .backgroundColor(this.isDarkMode ? '#444444' : '#E0E0E0') // 头像占位背景
            }
            Text(room.uname || '未知主播')
              .fontSize(13)
              .fontColor(this.isDarkMode ? '#AAAAAA' : '#666666')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(this.formatShortCount(room.online) + '观看')
              .fontSize(11)
              .fontColor(this.isDarkMode ? '#888888' : '#999999')
              .flexShrink(0)
            VideoCardMoreButton({ title: room.title, actionText: '进入直播间', onActivate: () => this.enterRoom(room) })
          }
          .width('100%')
          .margin({ top: 4, left: 2, right: 2 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding(8).height(LayoutPolicy.fixAtIdealSize)
      }
    }
    .width('100%')
    .backgroundColor(this.videoCardEdgeLight ? Color.Transparent : (this.cardCustomColor && this.cardCustomColor !== '#007DFF'
      ? (this.cardTransparentStyle
        ? '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1)
        : this.cardCustomColor)
      : cardItemBg(this.isDarkMode, this.cardTransparentStyle, this.cardBgOpacity, this.pageWallpaperEnabled))) // 动态背景色，深色/浅色模式都有对比
    .border({ width: !this.videoCardEdgeLight && this.cardTransparentStyle ? this.cardBorderWidth : 0,
      color: this.cardTransparentStyle
        ? (this.cardBorderFollowTheme
          ? ('#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1))
          : (this.isDarkMode ? `rgba(255,255,255,${this.cardBorderOpacity / 100})` : 'rgba(255,255,255,0.25)'))
        : Color.Transparent })
    .borderRadius(this.cardListBorderRadius)
    .clip(true)
    .shadow({ radius: 8, color: this.isDarkMode ? '#40000000' : '#20000000', offsetY: 4 })
    .clickEffect({ level: 0, scale: 0.9 })
    .onClick(() => this.enterRoom(room))
  }

  // ==================== 主构建 ====================

  build() {
    Stack() {
      // ═══ Layer 1: 内容层（填满屏幕，穿透 Tab 栏下方） ═══
      Column() {
        Refresh({ refreshing: $$this.isRefreshing, builder: this.customRefreshComponent() }) {
          Scroll(this.scroller) {
            Column() {
              // ⭐ 关注的UP主正在直播区块（信息流上方，需要登录）
              if (this.followedLiveRooms.length > 0 && !(this.isLoading && this.dataSource.totalCount() === 0)) {
                Column() {
                  // 区头
                  Row() {
                    Text('关注的主播').fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(this.isDarkMode ? Color.White : Color.Black)
                    Text(`(${this.followedLiveRooms.length})`)
                      .fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999').margin({ left: 4 })
                    Blank()
                    if (this.followedLiveRooms.length > 8) {
                      Text(this.showAllFollowed ? '收起' : '展开全部')
                        .fontSize(12).fontColor('#FB7299')
                        .onClick(() => {
                          this.showAllFollowed = !this.showAllFollowed;
                        })
                    }
                  }
                  .width('100%').padding({ left: 24, right: 20, bottom: 8 })
                  // 主播胶囊行（Flex 支持换行，默认显示 8 个，可展开全部）
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.followedLiveRooms.slice(0,
                      this.showAllFollowed ? this.followedLiveRooms.length : 8
                    ), (room: LiveFeedRoom) => {
                      Row() {
                        ImmersiveLightWrapper({ radius: 18, materialStyle: 0, lightIntensity: 2.0 }) {
                          Row() {
                            if (room.face) {
                              Image(room.face)
                                .width(28).height(28)
                                .borderRadius(14)
                                .objectFit(ImageFit.Cover)
                                .margin({ right: 6 })
                            }
                            Text(room.uname || '')
                              .fontSize(13)
                              .fontColor(this.isDarkMode ? Color.White : Color.Black)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            // 粉色直播状态指示图标（该列表均为直播中）
                            Image($r('app.media.ic_public_brightness_filled'))
                              .width(12).height(12)
                              .fillColor('#FB7299')
                              .margin({ left: 4 })
                          }
                          .height(36)
                          .padding({ left: 4, right: 12 })
                          .alignItems(VerticalAlign.Center)
                          .onClick(() => {
                            this.enterRoom(room);
                          })
                        }
                      }
                      .margin({ right: 8, bottom: 8 })
                    }, (room: LiveFeedRoom) => String(room.roomId))
                  }
                  .width('100%')
                  .padding({ left: 20, right: 20, bottom: 12 })
                }
              }

              if (this.isLoading && this.dataSource.totalCount() === 0) {
                HomeInitialLoading({ color: this.getThemeColor(), refreshing: this.isRefreshing || this.refreshReady })
              } else if (!this.isLoading && this.dataSource.totalCount() === 0) {
                Column() {
                  Image($r('app.media.ic_public_screencap'))
                    .width(64).height(64)
                    .fillColor(this.isDarkMode ? '#555555' : '#CCCCCC')
                    .margin({ bottom: 12 })
                  Text('暂无直播')
                    .fontSize(14).fontColor(this.isDarkMode ? '#888888' : '#999999')
                  Text('下拉刷新试试')
                    .fontSize(12).fontColor(this.isDarkMode ? '#666666' : '#BBBBBB')
                    .margin({ top: 4 })
                }
                .width('100%')
                .height(300)
                .justifyContent(FlexAlign.Center)
              } else {
                WaterFlow({ layoutMode: WaterFlowLayoutMode.SLIDING_WINDOW }) {
                  LazyForEach(this.dataSource, (room: LiveFeedRoom, index: number) => {
                    FlowItem() {
                      this.LiveCard(room)
                    }
                    .backgroundColor('transparent')
                  }, (room: LiveFeedRoom, index: number) => `${room.roomId}_${index}`)
                }
                .columnsTemplate({ fillType: PresetFillType.BREAKPOINT_DEFAULT })
                .columnsGap(this.cardListMargin).rowsGap(this.cardListMargin)
                .padding({
                  left: 12,
                  right: 12,
                  bottom: 4
                })
                .backgroundColor('transparent')
                .cachedCount(20)
                .clip(false)

                // 底部加载提示
                if (this.isLoadingMore) {
                  Row() {
                    LoadingProgress().width(20).height(20).color(this.getThemeColor())
                    Text(' 加载更多...')
                      .fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
                  }
                  .width('100%')
                  .height(44)
                  .justifyContent(FlexAlign.Center)
                } else if (!this.hasMore && this.dataSource.totalCount() > 0) {
                  Text('已经到底了~')
                    .fontSize(12).fontColor(this.isDarkMode ? '#666666' : '#CCCCCC')
                    .width('100%')
                    .height(44)
                    .textAlign(TextAlign.Center)
                }
              }
            }
            .width('100%')
            // Share the current home header and filter heights when entering this channel.
            .padding({
              top: this.isLoading && this.dataSource.totalCount() === 0 ? homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight) : this.headerTopInset() + this.visibleFilterHeight(),
              bottom: this.floatingBottomBar ? 84 + this.navIndicatorHeight : 0
            })
          }
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onWillScroll((_, yOffset: number, _state: ScrollState, source: ScrollSource) => {
            if (!AppStorage.get<boolean>('homeFeedActive') || yOffset === 0 || AppStorage.get<number>('homeChannelIndex') !== 1) return;
            const absoluteOffset = this.scroller.currentOffset().yOffset;
            AppStorage.set('homeScrollOffset', Math.max(0, absoluteOffset));
            const hidden = this.barScrollTracker.update(yOffset, source);
            if (hidden !== undefined) {
              AppStorage.set('homeBarsHidden', hidden);
              AppStorage.set('tabBarHidden', hidden);
            }
          })
          .onReachEnd(() => {
            this.loadMore();
          })
        }
        .onRefreshing(() => this.onRefresh())
        .onStateChange((refreshStatus: RefreshStatus) => {
          this.refreshReady = refreshStatus === RefreshStatus.OverDrag;
        })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('transparent')
      }
      .width('100%')
      .height('100%')

    }
  .align(Alignment.Top)
  .width('100%')
  .height('100%')
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
}
}
