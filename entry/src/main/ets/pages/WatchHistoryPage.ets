import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { GlassMaterial } from '../utils/GlassMaterial';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { gradientTitleBarStyle } from '../utils/HeaderStyle';
import { PageWallpaper } from '../components/PageWallpaper';
import { FloatingVideoTransition } from '../services/FloatingVideoTransition';
import { VideoListItem } from '../components/VideoListItem';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
// WatchHistoryPage.ets - 观看历史页面
import { router, mediaquery, window, LengthMetrics, curves } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { WatchHistoryItem } from '../model/WatchHistoryItem';
import { WatchHistoryHelper } from '../model/WatchHistoryHelper';
import { getVideoInfo, getPgcEpIdByBvid, prefetchVideoPlayback } from '../api/BilibiliApi';
import { VibrateUtils } from '../utils/VibrateUtils';
import { HdsNavigation, TitleSize, DividerShowType, HdsNavigationTitleMode, ScrollEffectType, HdsTabs } from '@kit.UIDesignKit';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
import { deviceInfo } from '@kit.BasicServicesKit';
import { motion } from '@kit.MultimodalAwarenessKit';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { HdsMiniBarButton } from '../components/infra/HdsMiniBarButton';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { FrameCallback } from '@ohos.arkui.UIContext';

class HistoryFirstFrameCallback extends FrameCallback {
  private done: boolean = false;
  private start: () => void;
  constructor(start: () => void) { super(); this.start = start; }
  onFrame(_frameTimeInNano: number): void {}
  onIdle(_timeLeftInNano: number): void {
    if (this.done) return;
    this.done = true;
    this.start();
  }
}

class HistoryDataSource implements IDataSource {
  private items: WatchHistoryItem[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): WatchHistoryItem { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }
  reload(items: WatchHistoryItem[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

@Entry
@Component({ freezeWhenInactive: true })
struct WatchHistoryPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @State historyList: WatchHistoryItem[] = [];
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.historyList = this.historyList.filter(item => !VideoCardFeedback.isDismissed(item.bvid, String(item.ownerMid)));
    this.isEmpty = this.historyList.length === 0;
  }
  @State isLoading: boolean = true;
  @State isEmpty: boolean = false;
  @State isEditMode: boolean = false;  // 编辑模式
  @State selectedIds: Set<number> = new Set<number>();  // 选中的视频id
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('wallpaper') wallpaper: string = 'default';
  @StorageLink('customWallpaper') customWallpaper: string = '';
  @StorageLink('wallpaperBlur') wallpaperBlur: number = 0;
  @StorageLink('wallpaperDarkness') wallpaperDarkness: number = 50;
  @StorageLink('wallpaperColor') wallpaperColor: string = '#007DFF';
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('da') da: boolean = false;
  @StorageLink('statusBarHeight') globalStatusBarHeight: number = 0;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @State imageLoadFailed: boolean = false;
  @State isLandscape: boolean = false;
  @State columnCount: number = 1;
  @State bottomSafeHeight: number = 0; // 底部安全区域高度

  // ⭐ 智感握持 - 边距
  @State private gripSafeAreaRight: number = 24;
  @State private gripSafeAreaLeft: number = 24;
  // ⭐ 智感握持 - 最终计算出的按钮定位
  @State private smartGripBottom: number = 120;
  @State private smartGripRight: number = 32;
  @State private smartGripLeft: number = -1;
  // ⭐ 智感握持 - 当前握持状态
  @State private hand: number = 16; // motion.HoldingHandStatus.UNKNOWN_STATUS
  // ⭐ 智感握姿开关
  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  @StorageLink('floatBtnFollowTheme') floatBtnFollowTheme: boolean = true;
  // ⭐ 拖拽自定义按钮位置（智感握姿关闭时生效）
  @StorageLink('watchHistoryFloatBtnSide') watchHistoryFloatBtnSide: string = 'right';
  @StorageLink('watchHistoryFloatBtnY') watchHistoryFloatBtnY: number = 120;
  @State private dragStartY: number = 0;
  @State private dragOffsetX: number = 0;
  @State private isDragging: boolean = false;
  @State private dragDeltaY: number = 0;
  private touchStartWX: number = 0;
  private touchStartWY: number = 0;
  private touchMoved: boolean = false;
  @State private btnScale: number = 1;
  @State private maxFloatBtnBottom: number = 592; // 按钮顶部距屏幕顶部至少80vp
  // 是否已监听握持事件
  private gripListenersInitialized: boolean = false;
  @State showBackToTop: boolean = false;

  // 搜索相关状态
  @State showSearchBar: boolean = false;  // 是否显示搜索栏
  @State searchText: string = '';
  @State @Watch('onFilteredItemsChanged') filteredItems: WatchHistoryItem[] = [];
  private historyDataSource: HistoryDataSource = new HistoryDataSource();
  private onFilteredItemsChanged(): void { this.historyDataSource.reload(this.filteredItems); }
  @State showClearButton: boolean = false; // 是否显示清除按钮
  @State searchBarOpacity: number = 0;  // 搜索栏透明度（动画）
  @State searchBarTranslateY: number = -20;  // 搜索栏垂直位移（动画）
  @State searchBarW: number = 200;  // 搜索栏宽度（对齐 SearchPage：屏宽 60% - 左右 margin，barWidth 需要具体数值）
  // 内容就绪标志（代替逐项 cardVisibleSet 动画）
  // 搜索输入框控制器，用于设置光标位置
  private searchInputController: TextInputController = new TextInputController();
  // 搜索输入框的组件id，用于 focusControl 自动聚焦
  private readonly SEARCH_INPUT_ID: string = 'watchHistorySearchInput';

  // 系统级沉浸光感配置
  @State customMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  @State customMaterialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;
  @State supportImmersive: boolean = false; // 设备是否支持沉浸光感

  // 下拉刷新相关状态
  @State isRefreshing: boolean = false;
  @State refreshBuilderText: string = '下拉刷新';
  @State showSearchIcon: boolean = false;
  private longPullTimer: number = -1;
  private longPullTriggered: boolean = false;

  private waterFlowScroller: Scroller = new Scroller();

  // 媒体查询监听器
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  private historyRequestVersion: number = 0;
  private historyPageActive: boolean = false;
  private historyStarted: boolean = false;
  private loadedHistoryCookie: string = '';
  @StorageProp('biliCookie') @Watch('onHistorySessionChanged') historySession: string = '';
  private helper: WatchHistoryHelper = WatchHistoryHelper.getInstance();
  private searchDebounceTimer: number = -1;

  aboutToAppear() {
    this.historyPageActive = true;
    this.getUIContext().postFrameCallback(new HistoryFirstFrameCallback(() => {
      if (!this.historyPageActive || this.historyStarted) return;
      this.historyStarted = true;
      this.loadHistory();
    }));
    this.initBottomSafeHeight();
    this.initSmartGrip();
    // 检测设备是否支持系统级沉浸光感
    this.checkImmersiveSupport();
    // 横竖屏媒体查询
    try {
      const mq = this.getUIContext().getMediaQuery();
      this.landscapeListener = mq.matchMediaSync('(orientation: landscape)');
      this.isLandscape = this.landscapeListener.matches;
      this.columnCount = this.isLandscape ? 2 : 1;
      this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;
      this.updateSearchBarWidth();
      this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.isLandscape = result.matches;
        this.columnCount = this.isLandscape ? 2 : 1;
        this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;
        this.updateSearchBarWidth();
      });
    } catch (e) {
      // 静默
    }
  }

  // 计算搜索栏宽度（与 SearchPage 的 searchInputBarW 保持同一算法）
  private updateSearchBarWidth(): void {
    try {
      const mainWindow = AppStorage.get<window.Window>('mainWindow');
      const screenW = mainWindow ? this.getUIContext().px2vp(mainWindow.getWindowProperties().windowRect.width) : 360;
      this.searchBarW = Math.max(120, Math.min(Math.round(screenW * 0.6) - 16, screenW - 100));
    } catch (e) {
      this.searchBarW = 200;
    }
  }

  // 检测设备是否支持系统级沉浸光感
  private checkImmersiveSupport() {
    try {
      const apiVersion = deviceInfo.sdkApiVersion ?? 0;
      this.supportImmersive = apiVersion >= 23;

      if (this.supportImmersive) {
        // 查询设备支持的材质类型
        const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
        if (types && types.includes(hdsMaterial.MaterialType.IMMERSIVE)) {
          this.customMaterialType = hdsMaterial.MaterialType.IMMERSIVE;
        } else {
          // 降级到 ADAPTIVE
          this.customMaterialType = hdsMaterial.MaterialType.ADAPTIVE;
        }
        logInfo(`[WatchHistory] 支持沉浸光感: ${this.customMaterialType}`);
      } else {
        logInfo(`[WatchHistory] API版本 ${apiVersion} 不支持沉浸光感`);
      }
    } catch (e) {
      this.supportImmersive = false;
      logError(`[WatchHistory] 检测沉浸光感支持失败: ${e}`);
    }
  }

  onPageShow(): void {
    AppStorage.setOrCreate('historyStatusBarVisible', true);
    void this.setStatusBarTransparent();
  }

  onPageHide(): void {
    AppStorage.setOrCreate('historyStatusBarVisible', false);
  }

  // 历史记录始终显示透明状态栏，返回本页时也恢复。
  private async setStatusBarTransparent() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const windowClass: window.Window = await window.getLastWindow(context);
      await windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: this.isDarkMode ? '#FFFFFF' : '#000000'
      });
      if (!(AppStorage.get<boolean>('historyStatusBarVisible') ?? false)) return;
      await StatusBarUtils.setStatusBarHidden(context, false);
    } catch (error) {
      logError('设置状态栏透明失败', error);
    }
  }

  // 获取底部安全区域高度
  async initBottomSafeHeight() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const win = await window.getLastWindow(context);
      // 获取导航条区域高度
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomSafeHeight = this.getUIContext().px2vp(navArea.bottomRect.height);
    } catch (e) {
      logError('获取底部安全区域高度失败:', e);
    }
  }

  aboutToDisappear() {
    this.historyPageActive = false;
    this.historyRequestVersion++;
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  async loadHistory() {
    const request = ++this.historyRequestVersion;
    const cookie = AppStorage.get<string>('biliCookie') ?? '';
    if (cookie !== this.loadedHistoryCookie) {
      this.historyList = []; this.filteredItems = []; this.isEmpty = false;
      this.loadedHistoryCookie = cookie;
    }
    this.helper.setCookie(cookie);
    if (!cookie) {
      this.historyList = []; this.filteredItems = []; this.isEmpty = true; this.isLoading = false;
      return;
    }
    if (this.historyList.length === 0) {
      const cached = this.helper.peekHistory(200);
      if (cached !== undefined) { this.historyList = cached; this.filterHistory(); this.isEmpty = cached.length === 0; }
    }
    this.isLoading = true;
    try {
      const list = await this.helper.queryAllHistory(200, true);
      if (request !== this.historyRequestVersion || cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      this.historyList = list;
      this.filterHistory();
      this.isEmpty = list.length === 0;
    } catch (err) {
      if (request !== this.historyRequestVersion || cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      logError('加载观看历史失败:', err);
      this.isEmpty = this.historyList.length === 0;
    } finally {
      if (request === this.historyRequestVersion) this.isLoading = false;
    }
  }

  private onHistorySessionChanged(): void {
    if (this.historyStarted && this.loadedHistoryCookie !== (AppStorage.get<string>('biliCookie') ?? '')) this.loadHistory();
  }

  private triggerHaptic(): void {
    VibrateUtils.vibrateTime(15);
  }

  // ═══════════════════════════════════════════
  // 智感握持 —— 回到顶部按钮定位
  // ═══════════════════════════════════════════

  private recalcSmartGripPosition(): void {
    const screenH: number = this.isLandscape ? 520 : 720;
    const bottomSafe: number = 24;
    if (this.isLandscape) {
      this.smartGripBottom = Math.max(bottomSafe + 24, screenH * 0.20);
    } else {
      this.smartGripBottom = Math.max(bottomSafe + 12, screenH * 0.15);
    }
    const LEFT_HAND = 1;
    // 两边始终保持有效值，避免 position 跳变触发平移动画
    this.smartGripLeft = this.gripSafeAreaLeft + 16;
    this.smartGripRight = this.gripSafeAreaRight + 8;
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
      logWarn('[WatchHistory] 初始化智感握持失败:', err);
    }
  }

  async deleteItem(item: WatchHistoryItem, index: number) {
    this.triggerHaptic();
    // 使用aid而不是本地id
    const success = await this.helper.deleteRecord(item.aid);
    if (success) {
      this.historyList.splice(index, 1);
      this.filterHistory(); // 更新过滤列表
      if (this.historyList.length === 0) {
        this.isEmpty = true;
      }
      this.getUIContext().getPromptAction().showToast({ message: '已删除' });
    }
  }

  async clearAll() {
    this.triggerHaptic();
    const success = await this.helper.clearAll();
    if (success) {
      this.historyList = [];
      this.filteredItems = []; // 清空过滤列表
      this.isEmpty = true;
      this.getUIContext().getPromptAction().showToast({ message: '已清空观看历史' });
    }
  }

  // 进入/退出编辑模式
  toggleEditMode() {
    this.isEditMode = !this.isEditMode;
    if (!this.isEditMode) {
      this.selectedIds.clear();
    }
  }

  // 切换选中状态
  toggleSelect(id: number) {
    if (this.selectedIds.has(id)) {
      this.selectedIds.delete(id);
    } else {
      this.selectedIds.add(id);
    }
    // 通过创建新 Set 引用来触发状态刷新（比全量重设快，因为 WaterFlow 只有少量 FlowItem 需要重布）
    this.selectedIds = new Set(this.selectedIds);
  }

  // 全选/取消全选
  toggleSelectAll() {
    if (this.selectedIds.size === this.historyList.length) {
      this.selectedIds.clear();
    } else {
      this.selectedIds = new Set(this.historyList.map(item => item.id));
    }
  }

  // 删除选中的视频
  async deleteSelected() {
    if (this.selectedIds.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先选择视频' });
      return;
    }
    this.triggerHaptic();

    // 收集选中视频的aid
    const aidsToDelete: number[] = [];
    this.selectedIds.forEach(id => {
      const item = this.historyList.find(h => h.id === id);
      if (item && item.aid) {
        aidsToDelete.push(item.aid);
      }
    });

    // 批量删除
    const success = await this.helper.deleteRecords(aidsToDelete);
    if (success) {
      const deleteCount = aidsToDelete.length;
      this.historyList = this.historyList.filter(item => !this.selectedIds.has(item.id));
      this.filterHistory(); // 更新过滤列表
      this.selectedIds.clear();
      this.isEditMode = false;
      if (this.historyList.length === 0) {
        this.isEmpty = true;
      }
      this.getUIContext().getPromptAction().showToast({ message: `已删除 ${deleteCount} 条记录` });
    }
  }

  async playVideo(item: WatchHistoryItem) {
    this.triggerHaptic();

    // 检查是否有有效的视频标识
    if (!item.bvid && !item.aid) {
      this.getUIContext().getPromptAction().showToast({ message: '视频ID无效' });
      return;
    }

    // ⭐ PGC（番剧）记录反查 epId：v2 历史接口的 PGC 记录无 epId，但可凭 bvid 调 view 接口
    //   拿 redirect_url（"//www.bilibili.com/bangumi/play/ep4723795"）反查分集 id，
    //   否则被当 UGC 播放（bvid+cid 无效组合 → playurl -404），不依赖先播放过番剧
    // ⚠️ 这个 await 在 pushUrl **之前**：每点一次卡片都要先等一个网络往返才发生转场。
    //   原来对所有记录都做（含 UGC 记录，而 UGC 反查必然返回 0 = 纯浪费），
    //   现在用记录自身的 isPgc 门控 —— 只有"确实是番剧且还没拿到 epId"才反查。
    let epIdToPlay: number = item.epId || 0;
    if (epIdToPlay <= 0 && item.isPgc && item.bvid) {
      try {
        const lookedUpEpId: number = await getPgcEpIdByBvid(item.bvid);
        if (lookedUpEpId > 0) {
          epIdToPlay = lookedUpEpId;
          logInfo(`[WatchHistory] bvid 反查 PGC epId: ${item.bvid} → ${lookedUpEpId}`);
        }
      } catch (e) {
        // 反查失败（非 PGC 或网络异常），按原逻辑播放
      }
    }

    // ⭐ 预热详情（fire-and-forget）：非 PGC 记录播放页要用详情里的 cid 才能起播，
    //   把这次 RTT 藏在转场+播放器初始化里；PGC 记录已直接传 cid，命中缓存也是 0 开销。
    if (!item.isPgc && epIdToPlay <= 0) {
      prefetchVideoPlayback(item.bvid || (item.aid > 0 ? String(item.aid) : ''), item.cid || 0,
        AppStorage.get<number>('defaultVideoQn') ?? 116);
    }

    // ⭐ 调试日志
    logInfo(`[WatchHistory] 播放视频: bvid=${item.bvid}, aid=${item.aid}, playProgress=${item.playProgress}, totalDuration=${item.totalDuration}`);

    // 注：优先使用bvid，如果没有bvid但有aid，VideoPlayerPage会通过aid获取视频信息
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: {
        bvid: item.bvid || '',  // 可能为空，但aid会有值
        aid: item.aid,          // 传入aid作为备选
        // ⭐ cid 必须传：历史接口顶层就有真实 cid（item.cid）。
        //   以前写死 0 → 播放页 PGC 分支判定 cid 无效，于是串行打两次反查
        //   （getPgcEpisodeInfo 实测对剧集 epId 恒返回 data 空 = 白等 ~190ms，
        //     再 getPgcSeasonInfoByEpId ~300ms）→ 这 ~490ms 是"历史页进播放页慢"的主因；
        //   而且 cid 不到手 playurl 就不能发起，首帧还要再往后顺延。
        cid: item.cid || 0,
        title: item.title,
        coverUrl: item.coverUrl,
        initialProgress: item.playProgress || 0,  // 传入已观看进度（秒）
        // ⭐ PGC（番剧）历史记录：传 epId/seasonId，VideoPlayerPage 走 PGC 路径（bvid 为空时）
        //   epIdToPlay 为上方 bvid 反查结果（item.epId 为 0 时用反查的 epId，否则 PGC 记录被当 UGC -404）
        epId: epIdToPlay,
        seasonId: item.seasonId || 0
      }
    });
  }

  goBack(): void {
    this.triggerHaptic();
    router.back();
  }

  // 搜索文本变化处理（带防抖，避免每次按键都触发 WaterFlow 重排）
  onSearchTextChange(value: string) {
    this.searchText = value;
    this.showClearButton = value.length > 0;
    if (this.searchDebounceTimer !== -1) {
      clearTimeout(this.searchDebounceTimer);
    }
    this.searchDebounceTimer = setTimeout(() => {
      this.searchDebounceTimer = -1;
      this.filterHistory();
    }, 200);
  }

  // 清空搜索文本
  clearSearchText() {
    this.searchText = '';
    this.showClearButton = false;
    this.filteredItems = [...this.historyList];
  }

  // 过滤历史记录
  filterHistory() {
    const keyword = this.searchText.trim().toLowerCase();
    if (!keyword) {
      this.filteredItems = [...this.historyList];
      return;
    }

    this.filteredItems = this.historyList.filter(item => {
      // 搜索标题
      if (item.title && item.title.toLowerCase().includes(keyword)) {
        return true;
      }
      // 搜索UP主名称
      if (item.ownerName && item.ownerName.toLowerCase().includes(keyword)) {
        return true;
      }
      return false;
    });
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

  private getSearchBarTopOffset(): number {
    return this.globalStatusBarHeight;
  }

  // Keep the compact content layout; the native blur ends at the title.
  private getHistoryContentTop(): number {
    return this.getSearchBarTopOffset() + (this.isEditMode ? 94 : (this.showSearchBar ? 120 : 56));
  }

  // 获取顶部区域的总高度（包括状态栏、间距、按钮栏）
  private getTopAreaTotalHeight(): number {
    return this.getSearchBarTopOffset() + 8 + 56 + 16;
  }

  // 下拉刷新方法
  private onRefresh() {
    this.loadHistory().finally(() => {
      this.isRefreshing = false;
    });
  }

  // 显示搜索栏（带动画），结束后自动弹出输入法
  private showSearchBarWithAnimation() {
    if (this.showSearchBar) return;
    this.showSearchBar = true;
    animateTo({ duration: this.da ? 0 : 250, curve: Curve.FastOutSlowIn }, () => {
      this.searchBarOpacity = 1;
      this.searchBarTranslateY = 0;
    });
    // 动画结束后自动聚焦输入框（弹出输入法）
    setTimeout(() => {
      focusControl.requestFocus(this.SEARCH_INPUT_ID);
    }, 280);
  }

  // ────────── Builder：搜索输入栏（HdsTabs 承载沉浸光感，对齐 SearchPage）──────────
  @Builder
  historySearchBar() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([this.isDarkMode ? '#FFFFFF' : '#000000'])
        .margin({ left: 14 })

      TextInput({ placeholder: '搜索历史记录', text: this.searchText, controller: this.searchInputController })
        .id(this.SEARCH_INPUT_ID)
        .focusable(true)
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .placeholderColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        .placeholderFont({ size: 15 })
        .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        .caretColor('#FB7299')
        .textAlign(TextAlign.Center)
        .margin({ left: 8, right: 8 })
        .onChange((value) => {
          this.onSearchTextChange(value);
        })

      if (this.showClearButton) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(18)
          .fontColor([this.isDarkMode ? '#FFFFFF' : '#000000'])
          .margin({ right: 14 })
          .onClick(() => {
            this.clearSearchText();
          })
      } else {
        Row().width(32)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
  }

  // 自定义刷新组件
  @Builder
  customRefreshComponent() {
    Stack() {
      Column() {
        if (this.showSearchIcon) {
          Image($r('app.media.ic_public_search_filled'))
            .width(32)
            .height(32)
            .fillColor(this.customThemeColor)
        } else {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.customThemeColor)
        }
        Text(this.refreshBuilderText)
          .fontSize(12)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height(80)
  }

  // 骨架屏卡片 - 加载时显示


  // 历史记录卡片 - 使用普通卡片样式（系统级沉浸光感由 HdsNavigation 提供）
  @Builder
  HistoryItemBuilder(item: WatchHistoryItem, index: number) {
    VideoListItem({
      title: item.title, cover: item.coverUrl, duration: item.totalDuration,
      videoId: item.isPgc ? '' : item.bvid, ownerMid: String(item.ownerMid),
      owner: item.ownerName, dateText: item.watchedAtText,
      progress: item.totalDuration > 0 ? item.playProgress / item.totalDuration * 100 : -1,
      selectable: this.isEditMode, selected: this.selectedIds.has(item.id),
      primaryActionText: this.isEditMode ? '选择记录' : '播放视频',
      onActivate: () => {
        this.triggerHaptic();
        if (this.isEditMode) this.toggleSelect(item.id);
        else this.playVideo(item);
      },
      onHold: () => {
        if (!this.isEditMode) { this.isEditMode = true; this.toggleSelect(item.id); }
      }
    })
  }

  pageTransition() {
    if (FloatingVideoTransition.active()) {
      PageTransitionEnter({ duration: FloatingVideoTransition.direction === 'minimize' ? 0 : FloatingVideoTransition.DURATION }).opacity(1)
      PageTransitionExit({ duration: FloatingVideoTransition.DURATION }).opacity(1)
    }
  }

  private toggleHeaderSearch(): void {
    if (!this.isEditMode) {
      this.triggerHaptic();
      if (!this.showSearchBar) {
        // 显示搜索栏：先设置显示，再执行入场动画
        this.showSearchBar = true;
        animateTo({ duration: this.da ? 0 : 250, curve: Curve.FastOutSlowIn }, () => {
          this.searchBarOpacity = 1;
          this.searchBarTranslateY = 0;
        });
        // 动画结束后自动聚焦输入框（弹出输入法）
        setTimeout(() => {
          focusControl.requestFocus(this.SEARCH_INPUT_ID);
        }, 280);
      } else {
        // 隐藏搜索栏：先执行退场动画，再设置隐藏
        animateTo({ duration: this.da ? 0 : 200, curve: Curve.FastOutSlowIn }, () => {
          this.searchBarOpacity = 0;
          this.searchBarTranslateY = -20;
        });
        setTimeout(() => {
          this.showSearchBar = false;
          this.clearSearchText();
        }, 200);
      }
    }

  }

  @Builder
  HeaderBackControl() {
    Row() {
      HeaderBackButton({ onBack: () => this.goBack() })
      Blank()
      Column() {
        HeaderGlassControl({ label: '搜索', controlId: 'history-header-search', actionEnabled: !this.isEditMode,
          onActivate: () => this.toggleHeaderSearch() }) {
          Image($r('app.media.ic_public_search_filled')).width(22).height(22)
            .fillColor(this.isDarkMode ? '#F2F4F8' : '#18191C').hitTestBehavior(HitTestMode.None)
        }
      }.width(40).height(40)
    }.width('100%').height('100%').padding({ left: 16, right: 16 })
      .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      PageWallpaper()
    Stack() {
      // PageWallpaper owns image and neutral backgrounds.
      // ── 使用 HdsNavigation 包裹内容 ──
      HdsNavigation() {
        Column() {
          // ── 列表内容 ──
          if (this.isLoading && this.historyList.length === 0) {
            Column({ space: 10 }) {
              LoadingProgress().width(28).height(28).color('#D34E7E')
              Text('加载中…').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
            }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
              .id('history-initial-loading')
          } else if (this.isEmpty) {
            Column() {
              Image($r('app.media.ic_settings_history'))
                .width(64).height(64)
                .fillColor(this.isDarkMode ? '#444444' : '#CCCCCC')
                .opacity(0.5)
              Text('暂无观看历史')
                .fontSize(16)
                .fontColor(this.isDarkMode ? '#666666' : '#AAAAAA')
                .margin({ top: 16 })
              Text('去首页发现感兴趣的视频吧')
                .fontSize(13)
                .fontColor(this.isDarkMode ? '#555555' : '#BBBBBB')
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            // 下拉刷新组件
            Refresh({ refreshing: $$this.isRefreshing, builder: this.customRefreshComponent() }) {
              WaterFlow({ scroller: this.waterFlowScroller }) {
                LazyForEach(this.historyDataSource, (item: WatchHistoryItem, index: number) => {
                  FlowItem() {
                    this.HistoryItemBuilder(item, index)
                  }
                  .width('100%')
                  .margin({ top: index < this.columnCount ? this.getHistoryContentTop() : 0 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.95 })
                }, (item: WatchHistoryItem, source: number) => `${item.id}_${item.bvid}_${source}`)
              }
              .columnsTemplate(this.columnCount === 3 ? '1fr 1fr 1fr' : (this.columnCount === 2 ? '1fr 1fr' : '1fr'))
              .columnsGap(20)
              .rowsGap(0)
              .width('100%')
              .layoutWeight(1)
              .scrollBar(BarState.Off)
              .cachedCount(0)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }) // 触底反弹效果
              .padding({
                left: 12,
                right: 12,
                bottom: 0
              })
              .backgroundColor('transparent')
              .onScrollIndex((firstIndex: number) => {
                // 滚动时检测是否超出阈值 → 显示/隐藏回到顶部按钮
                const scrollOffset: number = this.waterFlowScroller.currentOffset().yOffset;
                this.showBackToTop = Math.abs(scrollOffset) > 300;
              })
            }
            .onStateChange((refreshStatus: RefreshStatus) => {
              if (refreshStatus === RefreshStatus.OverDrag) {
                // 过度拖拽时启动定时器
                if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
                this.longPullTimer = setTimeout(() => {
                  this.showSearchIcon = true;
                  this.refreshBuilderText = '释放打开搜索';
                  this.longPullTriggered = true;
                  // 触发震动反馈
                  try {
                    VibrateUtils.vibrateTime(25);
                  } catch (err) { }
                }, 800);
              } else if (refreshStatus === RefreshStatus.Drag) {
                // 正常拖拽时重置状态
                if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
                if (this.longPullTriggered) {
                  try {
                    VibrateUtils.vibrateTime(15);
                  } catch (err) { }
                }
                this.showSearchIcon = false;
                this.refreshBuilderText = '下拉刷新';
                this.longPullTriggered = false;
              } else if (refreshStatus === RefreshStatus.Refresh) {
                if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
              } else {
                if (this.longPullTimer !== -1) clearTimeout(this.longPullTimer);
                this.showSearchIcon = false;
                this.refreshBuilderText = '下拉刷新';
                this.longPullTriggered = false;
              }
            })
            .onRefreshing(() => {
              if (this.longPullTriggered) {
                // 长按触发：弹出搜索框
                this.isRefreshing = false;
                this.showSearchIcon = false;
                this.refreshBuilderText = '下拉刷新';
                this.longPullTriggered = false;
                setTimeout(() => {
                  this.showSearchBarWithAnimation();
                }, 100);
                return;
              }
              // 正常刷新
              this.onRefresh();
            })
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('transparent')
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
      }
      // ── HdsNavigation 配置：系统级沉浸光感 ──
      .titleBar({
        avoidLayoutSafeArea: true,
        padding: { start: LengthMetrics.vp(64), end: LengthMetrics.vp(64) },
        style: gradientTitleBarStyle(this.isDarkMode),
        content: {
          stackBuilder: () => { this.HeaderBackControl(); },
          divider: { showType: DividerShowType.OFF },
          title: {
            mainTitle: '观看历史',
            mainTitleSize: TitleSize.TITLE_S
          },

        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .mode(NavigationMode.Stack) // ★★★ 强制单栏模式，避免横屏分栏 ★★★
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // ── 编辑模式操作栏 ──
      if (this.isEditMode && !this.isEmpty) {
        Row() {
          Text('取消')
            .fontSize(16)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .onClick(() => this.toggleEditMode())

          Blank()

          Text('删除')
            .fontSize(16)
            .fontColor(this.selectedIds.size > 0 ? '#FB7299' : (this.isDarkMode ? '#666666' : '#999999'))
            .onClick(() => {
              if (this.selectedIds.size > 0) {
                this.deleteSelected();
              }
            })
        }
        .width('100%')
        .height(40)
        .position({ x: 0, y: this.getSearchBarTopOffset() + 56 })
        .padding({ left: 16, right: 16 })
      }

      // ── 搜索栏（固定在标题栏正下方，HdsTabs 承载沉浸光感，结构对齐 SearchPage）──
      if (this.showSearchBar && !this.isEditMode && !this.isEmpty) {
        Row() {
          HdsTabs() {
            TabContent()
              .tabBar(this.historySearchBar())
              .backgroundColor(Color.Transparent)
          }
          .barWidth(this.searchBarW)
          .barHeight(40)
          .barOverlap(true)
          .barPosition(BarPosition.End)
          .barFloatingStyle({
            // ★ 必须显式关闭渐变遮罩，否则 bar 会渲染成一条渐变黑色矩形（SearchPage 同款写法）
            gradientMask: {
              maskColor: Color.Transparent
            },
            barBottomMargin: 0,
            systemMaterialEffect: {
              materialType: GlassMaterial.hdsType(),
              materialLevel: GlassMaterial.hdsLevel()
            }
          })
          .scrollable(false)
          .animationDuration(0)
          .backgroundColor(Color.Transparent)
          .width(this.searchBarW)
          .height(40)
          .clip(false)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        // Stack 子组件默认垂直居中，用 position 钉到标题栏正下方（与内容首行 top 预留 120+offset 对齐）
        .position({ x: 0, y: this.getSearchBarTopOffset() + 60 })
        .hitTestBehavior(HitTestMode.Transparent)
        .opacity(this.searchBarOpacity)
        .translate({ y: this.searchBarTranslateY })
      }
      // ⭐ 回到顶部悬浮按钮
      if (this.smartGripEnabled && !this.isLandscape) {
        // ⭐ 左侧按钮（左手握持时显示）
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
                this.dragStartY = this.watchHistoryFloatBtnY;
                this.touchMoved = false;
                this.isDragging = true;
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                if (Math.abs(offYpx) > 5) {
                  this.touchMoved = true;
                }
                this.watchHistoryFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  AppStorage.set('watchHistoryFloatBtnY', this.watchHistoryFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else if (event.type === TouchType.Up) {
                  this.triggerHaptic();
                  animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                    this.btnScale = 0.8;
                  });
                  setTimeout(() => {
                    animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                      this.btnScale = 1;
                    });
                  }, 100);
                  this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                }
              }
            })
        }
        .width(48).height(48)
        .position({ bottom: this.watchHistoryFloatBtnY, left: this.smartGripLeft })
        .opacity(this.hand === 1 && this.showBackToTop ? 1 : 0)
        .translate({ x: this.hand === 1 && this.showBackToTop ? 0 : -20 })
        .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
        .hitTestBehavior(this.hand === 1 && this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
        .animation(this.da || this.isDragging ? { duration: 0 } : {
          duration: 300,
          curve: curves.springMotion(0.3, 0.4)
        })
        // ⭐ 右侧按钮（右手/默认握持时显示）
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
                this.dragStartY = this.watchHistoryFloatBtnY;
                this.touchMoved = false;
                this.isDragging = true;
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                if (Math.abs(offYpx) > 5) {
                  this.touchMoved = true;
                }
                this.watchHistoryFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  AppStorage.set('watchHistoryFloatBtnY', this.watchHistoryFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else if (event.type === TouchType.Up) {
                  this.triggerHaptic();
                  animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
                    this.btnScale = 0.8;
                  });
                  setTimeout(() => {
                    animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
                      this.btnScale = 1;
                    });
                  }, 100);
                  this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                }
              }
            })
        }
        .width(48).height(48)
        .position({ bottom: this.watchHistoryFloatBtnY, right: this.smartGripRight })
        .opacity(this.hand !== 1 && this.showBackToTop ? 1 : 0)
        .translate({ x: this.hand !== 1 && this.showBackToTop ? 0 : 20 })
        .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
        .hitTestBehavior(this.hand !== 1 && this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
        .animation(this.da || this.isDragging ? { duration: 0 } : {
          duration: 300,
          curve: curves.springMotion(0.3, 0.4)
        })
      } else {
        // ⭐ 智感握姿关闭：单个可拖拽按钮
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
                this.dragStartY = this.watchHistoryFloatBtnY;
                this.dragOffsetX = 0;
                this.touchMoved = false;
                this.isDragging = true;
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                const offXpx = event.touches[0].windowX - this.touchStartWX;
                if (Math.abs(offYpx) > 5 || Math.abs(offXpx) > 5) {
                  this.touchMoved = true;
                }
                this.watchHistoryFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
                this.dragOffsetX = Math.round(this.getUIContext().px2vp(offXpx));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  const totalOffsetX: number = this.dragOffsetX;
                  let newSide: string = this.watchHistoryFloatBtnSide;
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
                        this.watchHistoryFloatBtnSide = newSide;
                      }
                    });
                  } else {
                    this.dragOffsetX = 0;
                  }
                  AppStorage.set('watchHistoryFloatBtnSide', this.watchHistoryFloatBtnSide);
                  AppStorage.set('watchHistoryFloatBtnY', this.watchHistoryFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else {
                  this.dragOffsetX = 0;
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
                    this.waterFlowScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
                  }
                }
              }
            })
        }
        .width(48).height(48)
        .position(this.watchHistoryFloatBtnSide === 'left'
          ? { bottom: this.watchHistoryFloatBtnY, left: 32 }
          : { bottom: this.watchHistoryFloatBtnY, right: 32 })
        .opacity(this.showBackToTop ? 1 : 0)
        .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
        .hitTestBehavior(this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
        .animation(this.da || this.isDragging ? { duration: 0 } : { duration: 300, curve: Curve.Ease })
        .translate({ x: this.dragOffsetX })
      }

    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)  // 设置顶部对齐，让搜索栏从顶部定位
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private async saveFloatBtnPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('watchHistoryFloatBtnSide', this.watchHistoryFloatBtnSide);
      await pref.put('watchHistoryFloatBtnY', this.watchHistoryFloatBtnY);
      await pref.flush();
    } catch (e) {
      logError('保存历史页悬浮按钮位置失败', e);
    }
  }
}
