import { FollowGlassButton } from '../components/FollowGlassButton';
import { GlassMaterial } from '../utils/GlassMaterial';
import { HistoryDustChip } from '../components/HistoryDustChip';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageSurface } from '../components/PageSurface';
import { ChannelCardSurface } from '../components/ChannelCardSurface';
import { cardItemBg } from '../utils/CardStyle';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { FloatingVideoTransition } from '../services/FloatingVideoTransition';
import { VideoListItem, videoListPublished } from '../components/VideoListItem';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
﻿import { router, curves, display } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { searchByType, searchLive, SearchType, SearchOrder, SEARCH_ORDER_KEYS, getSearchOrderLabel, getSearchTypeLabel, SearchTypeLabelMap, getFollowStatus, modifyFollow, prefetchVideoPlayback, prefetchPlayUrlsOnly } from '../api/BilibiliApi';
import { fetchRecommendedLiveRooms, LiveFeedRoom } from '../api/LiveFeedApi';
import { fetchHotSearch, fetchSearchDiscovery, fetchSearchSuggestions, HotSearchItem } from '../api/HotSearchService';
import { RecommendItem } from '../model/RecommendItem';
import { common } from '@kit.AbilityKit';
import { formatPlayCountText, getPlayCountDisplayColor } from '../utils/PlayCountStyle';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { VibrateUtils } from '../utils/VibrateUtils';
import { motion } from '@kit.MultimodalAwarenessKit';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { HdsMiniBarButton } from '../components/infra/HdsMiniBarButton';
import { HdsTabs } from '@kit.UIDesignKit';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { HomeBarScrollTracker } from '../utils/HomeBarScrollTracker';

// ── Tab 类型 ──
const TAB_KEYS: string[] = ['video', 'media_bangumi', 'live_user', 'bili_user', 'media_ft', 'article'];
const RESULT_ORDER_KEYS: string[] = ['totalrank', 'pubdate', 'click', 'dm'];

@Entry
@Component({ freezeWhenInactive: true })
struct SearchPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @State searchText: string = '';
  @State isLoading: boolean = false;
  @State showClearButton: boolean = false;
  @State searchBarFocused: boolean = false;
  @State showSkeleton: boolean = false;
  @State showAllHistory: boolean = false;
  @State searchHistory: string[] = [];
  @State dissolvingHistory: string[] = [];
  private completedHistoryDust: string[] = [];
  private visibleHistoryDust: string[] = [];
  // ⭐ 路由传入的待搜索关键词（搜索历史加载完成后执行，防止覆盖历史）
  private pendingKeyword_: string = '';
  // ⭐ 路由传入的待搜索 Tab（如 'all' 综合搜索）
  private pendingTab_: string = '';
  @State showHistory: boolean = false;
  @State isLandscape: boolean = false;
  @State hotSearchItems: HotSearchItem[] = [];
  @State searchDiscoveryWords: string[] = [];
  @State suggestionWords: string[] = [];
  @State showSuggestions: boolean = false;
  // 搜索类型 Tab — UI 直接绑定的当前 Tab 数据
  @State activeTab: string = 'video';
  @State searchError: string = '';
  private searchRequestVersion: number = 0;
  private resultsKeyword: string = '';
  private sceneVersion: number = 0;
  @State hasActiveSearch: boolean = false;  // 用户是否主动搜索过（0结果时留在搜索结果页，不回到初始页以避开ImmersiveLightWrapper崩溃）
  @State activeOrder: string = 'totalrank';
  @State activeResults: RecommendItem[] = [];
  @StorageLink('cardFeedbackRevision') @Watch('onCardFeedbackChange') feedbackRevision: number = 0;

  private onCardFeedbackChange(): void {
    this.activeResults = this.activeResults.filter(item => !VideoCardFeedback.isDismissed(item.id, item.ownerMid));
    this.cachedResults.forEach((items, key) => {
      this.cachedResults.set(key, items.filter(item => !VideoCardFeedback.isDismissed(item.id, item.ownerMid)));
    });
  }
  @State activePage: number = 1;
  @State activeHasMore: boolean = true;
  @State searchTabBarW: number = 320;
  @State searchOrderBarW: number = 280;
  @State searchInputBarW: number = 200;
  @State searchCapsuleExpanded: boolean = false;
  @State resultOptionsHidden: boolean = false;
  @State resultOptionsHeight: number = 88;
  private resultScrollTracker: HomeBarScrollTracker = new HomeBarScrollTracker();
  @State searchOrderTranslateX: number = 0;
  @State searchOrderOpacity: number = 1;
  @State currentWindowW: number = 360;
  @State liveStreamers: RecommendItem[] = [];   // 直播搜索结果中的主播列表
  @State showAllStreamers: boolean = false;     // 主播折叠展开
  // 私有缓存（非 @State，切换 Tab 时保存/恢复）
  private cachedResults: Map<string, RecommendItem[]> = new Map();
  private cachedPages: Map<string, number> = new Map();
  private cachedHasMore: Map<string, boolean> = new Map();
  private cachedOrders: Map<string, string> = new Map();
  // 搜索结果区动画状态
  @State contentOpacity: number = 1;
  @State contentTranslateY: number = 0;
  // 搜索历史动画状态
  @State historyOpacity: number = 0;
  @State historyTranslateY: number = -20;

  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('statusBarHeight') globalStatusBarHeight: number = 0;
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
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
  @StorageLink('cardBorderFollowPlayCount') cardBorderFollowPlayCount: boolean = false;
  @StorageLink('cardCapsuleFollowTheme') cardCapsuleFollowTheme: boolean = false;
  @StorageLink('cardCapsuleShow') cardCapsuleShow: boolean = true;
  @StorageLink('cardCapsuleSize') cardCapsuleSize: number = 12;
  @StorageLink('cardCapsuleRadius') cardCapsuleRadius: number = 7;
  @StorageLink('cardCapsuleColor') cardCapsuleColor: string = '';
  @StorageLink('cardPlayCountShow') cardPlayCountShow: boolean = true;
  @StorageLink('cardPlayCountUnit') cardPlayCountUnit: string = 'wanYi';
  @StorageLink('cardPlayCountSize') cardPlayCountSize: number = 12;
  @StorageLink('cardPlayCountColorMode') cardPlayCountColorMode: string = 'level';
@StorageLink('cardPlayCountIcon') cardPlayCountIcon: boolean = true;
  @StorageLink('cardPlayCountColor') cardPlayCountColor: string = '';
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardListBorderRadius') cardListBorderRadius: number = 12;
  @StorageLink('cardListMargin') cardListMargin: number = 0;
  @StorageLink('cardStyleSearchSuggest') cardStyleSearchSuggest: boolean = true;
  @StorageLink('showSearchDiscovery') showSearchDiscovery: boolean = true;
  @StorageLink('showHotSearch') showHotSearch: boolean = true;
  @StorageLink('showSearchHistory') showSearchHistory: boolean = true;
  @StorageLink('searchHistoryRows') searchHistoryRows: number = 3;
  @State showEditPanel: boolean = false;
  private returnToCaller: boolean = false;
  private fromHotRanking: boolean = false;
  @State discoveryHidden: boolean = false;
  @State imageLoadFailed: boolean = false;
  @State followedUserIds: string[] = [];
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
  @StorageLink('searchFloatBtnSide') searchFloatBtnSide: string = 'right';
  @StorageLink('searchFloatBtnY') searchFloatBtnY: number = 120;
  @State private dragStartY: number = 0;
  @State private dragOffsetX: number = 0;
  private touchStartWX: number = 0;
  private touchStartWY: number = 0;
  private touchMoved: boolean = false;
  @State private dragDeltaY: number = 0;
  @State private isDragging: boolean = false;
  @State private btnScale: number = 1;
  @State private maxFloatBtnBottom: number = 592; // 按钮顶部距屏幕顶部至少80vp
  // 是否已监听握持事件
  private gripListenersInitialized: boolean = false;
  @State showBackToTop: boolean = false;
  // ⭐ 初始数据加载状态
  @State isInitialLoading: boolean = false;  // 初始数据是否加载完成
  // 搜索栏单行高度，输入框与两侧操作垂直居中。
  private readonly SEARCH_BAR_STACK_HEIGHT: number = 56;
  // ⭐ 状态栏下方固定间隔
  private readonly SEARCH_BAR_SPACER: number = 8;
  // ⭐ 搜索栏总高度（供 onAreaChange 回调使用，模板中直接用计算值）
  @State actualSearchBarHeight: number = 0;

  /** 计算固定搜索栏的精确高度：状态栏 + 8vp间隔 + Stack(84vp) */
  private getSearchBarHeight(): number {
    const sb = this.hideStatusBar ? 0 : this.globalStatusBarHeight;
    return sb + this.SEARCH_BAR_SPACER + this.SEARCH_BAR_STACK_HEIGHT;
  }

  private hideHistoryTimeout: number = 0;
  private suggestTimer: number = 0;
  private suppressSuggestDebounce: boolean = false;
  private scroller: Scroller = new Scroller();
  private windowClass: window.Window | null = null;
  private windowSizeChangeCallback: ((size: window.Size) => void) | null = null;
  // 保存进入搜索页前的状态栏属性，退出时恢复
  private previousStatusBarColor: string = '';
  private previousStatusBarContentColor: string = '';
  // 保存进入搜索页前的状态栏显隐状态
  private previousHideStatusBar: boolean = false;
  // 输入框控制器，用于自动聚焦和关闭键盘
  private inputController: TextInputController = new TextInputController();

  aboutToAppear() {
    this.saveAndSetStatusBarTransparent();
    this.initOrientationAndListen();
    this.initSmartGrip();
    this.recalcSearchTabBarW();
    // ⭐ 长按文本选取「搜索」直达：接收路由 keyword，待搜索历史加载完成后再自动搜索
    //   （立即 performSearch 会用未加载的空历史数组 addToSearchHistory，覆盖掉旧搜索历史）
    try {
      const p = this.getUIContext().getRouter().getParams() as Record<string, Object>;
      this.fromHotRanking = p ? (p['fromHotRanking'] as boolean) === true : false;
      const kw = p ? ((p['keyword'] as string) || '') : '';
      // 外部关键词直达没有搜索首页这一层，返回应退出当前路由。
      this.returnToCaller = this.fromHotRanking || kw.trim().length > 0;
      if (kw) {
        this.pendingKeyword_ = kw;
        // 路由直达结果页从首帧显示加载态，推入时不展示搜索首页。
        this.searchText = kw;
        this.hasActiveSearch = true;
        this.showSkeleton = true;
        const tab = (p['tab'] as string) || '';
        if (tab) {
          this.pendingTab_ = tab;
        }
      }
    } catch (e) {
      logWarn(`[SearchPage] 路由参数解析失败: ${e}`);
    }
    // ⭐ 统一加载所有初始数据，完成后一起淡入
    this.loadInitialData();
  }

  /** 统一加载初始数据，完成后触发淡入动画 */
  private async loadInitialData(): Promise<void> {
    const request = this.searchRequestVersion;
    this.isInitialLoading = false;
    // Remote suggestions must not delay local history or a keyword search.
    this.loadHotSearch().catch((error: Error) => logWarn('热搜加载失败', error));
    this.loadSearchDiscovery().catch((error: Error) => logWarn('搜索发现加载失败', error));
    this.loadSearchEditSettings().catch((error: Error) => logWarn('搜索设置加载失败', error));
    try { await this.loadSearchHistory(); } catch (error) { logWarn('搜索历史加载失败', error); }
    if (request !== this.searchRequestVersion) return;
    if (this.pendingKeyword_ !== '') {
      this.searchText = this.pendingKeyword_;
      this.pendingKeyword_ = '';
      if (this.pendingTab_ !== '') { this.activeTab = this.pendingTab_; this.pendingTab_ = ''; }
      void this.performSearch(true);
    }
  }

  /** ⭐ 动态计算搜索标签行和输入框宽度：标签行根据文字自适应 */
  private recalcSearchTabBarW(windowW?: number): void {
    try {
      let screenW: number;
      if (windowW !== undefined) {
        screenW = windowW;
      } else {
        const d = display.getDefaultDisplaySync();
        screenW = this.getUIContext().px2vp(d.width);
      }
      const maxTabBarW = Math.max(200, screenW - 28 - 16);
      // 标签行：根据 TAB_KEYS 文字内容估算总宽度
      const tabLabels: string[] = TAB_KEYS.map((k: string) => getSearchTypeLabel(k));
      this.searchTabBarW = this.estimateBarWidth(tabLabels, 14, 24, 8, 8, maxTabBarW);
      // 排序行：参数和实际渲染一致（fontSize=14, itemPadding=24, itemSpace=8）
      const orderLabels: string[] = SEARCH_ORDER_KEYS.map((k: string) => getSearchOrderLabel(k));
      const orderMaxW = Math.max(160, screenW - this.getCollapsedTabBarW() - 68);
      this.searchOrderBarW = this.estimateBarWidth(orderLabels, 14, 16, 4, 8, orderMaxW);
      // 扣除两侧按钮、页边距和输入框间隔，填满可用宽度。
      this.searchInputBarW = Math.max(120, screenW - 124);
    } catch (_) {
      this.searchTabBarW = 340;
      this.searchInputBarW = 200;
    }
  }

  /** 估算胶囊宽度：根据文字内容自适应 */
  private estimateBarWidth(labels: string[], fontSize: number, itemPadding: number,
    itemSpace: number, rowPadding: number, maxW: number): number {
    if (labels.length === 0) {
      return maxW;
    }
    let totalW = rowPadding;
    for (const label of labels) {
      let textW = 0;
      for (const ch of label) {
        textW += (ch.charCodeAt(0) > 0x4e00 && ch.charCodeAt(0) < 0x9fff) ? fontSize : fontSize * 0.55;
      }
      totalW += textW + itemPadding + itemSpace;
    }
    totalW -= itemSpace;
    return Math.min(totalW, maxW);
  }

  /** 收起态胶囊宽度：当前标签文字 + 右侧展开图标 */
  private getCollapsedTabBarW(): number {
    const label = getSearchTypeLabel(this.activeTab);
    let textW = 0;
    for (const ch of label) {
      textW += (ch.charCodeAt(0) > 0x4e00 && ch.charCodeAt(0) < 0x9fff) ? 14 : 14 * 0.55;
    }
    return textW + 24 + 20 + 8;
  }

  /** 展开态胶囊宽度：显示所有标签，考虑 contentPadding*4 和外层 padding */
  private getExpandedTabBarW(windowW?: number): number {
    try {
      let screenW: number;
      if (windowW !== undefined) {
        screenW = windowW;
      } else {
        const d = display.getDefaultDisplaySync();
        screenW = this.getUIContext().px2vp(d.width);
      }
      return Math.max(280, screenW - 28 - 16);
    } catch (_) {
      return 320;
    }
  }

  /** 展开/收起搜索标签胶囊 */
  private setSearchCapsuleExpanded(expanded: boolean): void {
    if (this.searchCapsuleExpanded === expanded) return;
    this.triggerHaptic();
    if (expanded) {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 450,
        curve: curves.springMotion(0.4, 0.8)
      }, () => {
        this.searchCapsuleExpanded = true;
        this.searchOrderTranslateX = 300;
        this.searchOrderOpacity = 0;
      });
    } else {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
        duration: 280,
        curve: curves.springMotion(0.5, 0.85)
      }, () => {
        this.searchCapsuleExpanded = false;
        this.searchOrderTranslateX = 0;
        this.searchOrderOpacity = 1;
      });
    }
  }

  private async initOrientationAndListen() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.windowClass = await window.getLastWindow(context);
      const props = this.windowClass.getWindowProperties();
      this.isLandscape = props.windowRect.width > props.windowRect.height;
      this.currentWindowW = this.getUIContext().px2vp(props.windowRect.width);
      this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;

      // ★ 从窗口避让区读取实际状态栏高度，更新 AppStorage
      const avoidArea = this.windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const realSbHeight = this.getUIContext().px2vp(avoidArea.topRect.height);
      if (realSbHeight > 0) {
        AppStorage.set('statusBarHeight', realSbHeight);
      }

      // 保存回调引用，以便精确移除，避免误删其他页面的监听器
      this.windowSizeChangeCallback = (size: window.Size): void => {
        this.isLandscape = size.width > size.height;
        this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;
        const windowW = this.getUIContext().px2vp(size.width);
        this.currentWindowW = windowW;
        this.recalcSearchTabBarW(windowW);
      };
      this.windowClass.on('windowSizeChange', this.windowSizeChangeCallback);
    } catch (err) {
      logError('初始化屏幕方向监听失败:', err);
    }
  }

  aboutToDisappear() {
    this.searchRequestVersion++;
    this.sceneVersion++;
    this.settleHistoryDisintegration();
    if (this.hideHistoryTimeout) {
      clearTimeout(this.hideHistoryTimeout);
      this.hideHistoryTimeout = 0;
    }
    // 精确移除自己的监听器，不影响首页等其他页面的 windowSizeChange 监听
    if (this.windowClass && this.windowSizeChangeCallback) {
      this.windowClass.off('windowSizeChange', this.windowSizeChangeCallback);
      this.windowSizeChangeCallback = null;
    }
    // 恢复进入搜索页前的状态栏属性
    this.restoreStatusBar();
  }

  async saveAndSetStatusBarTransparent() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const windowClass: window.Window = await window.getLastWindow(context);
      const props = windowClass.getWindowSystemBarProperties();
      this.previousStatusBarColor = props.statusBarColor ?? '';
      this.previousStatusBarContentColor = props.statusBarContentColor ?? '';
      // 保存当前状态栏显隐状态
      this.previousHideStatusBar = AppStorage.get<boolean>('hideStatusBar') ?? false;
      await windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF'
      });
      // 横屏时强制隐藏状态栏
      const isLandscape = AppStorage.get<boolean>('isLandscape') ?? false;
      if (isLandscape) {
        windowClass.setSpecificSystemBarEnabled('status', false);
      }
    } catch (error) {
      logError('设置状态栏透明失败', error);
    }
  }

  private async restoreStatusBar() {
    try {
      if (!this.windowClass) return;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const isDark = AppStorage.get<boolean>('isDarkMode') ?? false;
      // 根据当前深色模式恢复状态栏颜色
      await this.windowClass.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
      // 横屏时保持状态栏隐藏，不恢复
      const isLandscape = AppStorage.get<boolean>('isLandscape') ?? false;
      if (!isLandscape) {
        // 重新应用用户的状态栏隐藏设置
        await StatusBarUtils.setStatusBarHidden(context, this.previousHideStatusBar);
      }
    } catch (err) {
      logError('恢复状态栏失败', err);
    }
  }

  private getSolidBackground(): string {
    switch (this.wallpaper) {
      case 'dark': return '#0A0E1A';
      case 'light': return '#FFFFFF';
      case 'mint': return '#E0F7F0';
      case 'blue': return '#1E2A4F';
      case 'custom_color': return this.wallpaperColor;
      default: return this.isDarkMode ? '#171A1C' : '#FFFFFF';
    }
  }

  async loadSearchHistory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      const savedHistory = await pref.get('searchHistory', '[]') as string;
      const historyArray: string[] = JSON.parse(savedHistory);
      if (Array.isArray(historyArray)) {
        this.searchHistory = historyArray;
      }
    } catch (error) {
      logError('加载搜索历史失败:', error);
    }
  }

  async saveSearchHistory() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('searchHistory', JSON.stringify(this.searchHistory.filter(word => !this.dissolvingHistory.includes(word))));
      await pref.flush();
    } catch (error) {
      logError('保存搜索历史失败:', error);
    }
  }

  async loadSearchEditSettings(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      this.showHotSearch = await pref.get('showHotSearch', true) as boolean;
      this.showSearchHistory = await pref.get('showSearchHistory', true) as boolean;
      this.searchHistoryRows = await pref.get('searchHistoryRows', 3) as number;
      this.showSearchDiscovery = await pref.get('showSearchDiscovery', true) as boolean;
    } catch (error) {
      logError('加载搜索编辑设置失败:', error);
    }
  }

  async saveSearchEditSettings(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('showHotSearch', this.showHotSearch);
      await pref.put('showSearchHistory', this.showSearchHistory);
      await pref.put('searchHistoryRows', this.searchHistoryRows);
      await pref.put('showSearchDiscovery', this.showSearchDiscovery);
      await pref.flush();
    } catch (error) {
      logError('保存搜索编辑设置失败:', error);
    }
  }

  async performSearch(reset: boolean = true): Promise<void> {
    const keyword = this.searchText.trim();
    if (!keyword) {
      this.suppressSuggestDebounce = false;
      this.getUIContext().getPromptAction().showToast({ message: '请输入搜索关键词' });
      return;
    }
    if (!reset && this.isLoading) return;
    const request = ++this.searchRequestVersion;
    const tab = this.activeTab;
    const order = this.activeOrder;
    const firstSearch = !this.hasActiveSearch;
    const newKeyword = keyword !== this.resultsKeyword;
    this.sceneVersion++;
    this.resultsKeyword = keyword;
    this.searchError = '';
    this.isLoading = true;
    if (this.suggestTimer > 0) { clearTimeout(this.suggestTimer); this.suggestTimer = 0; }
    this.showSuggestions = false;
    this.suggestionWords = [];
    this.suppressSuggestDebounce = false;
    this.addToSearchHistory(keyword);
    if (reset) {
      this.setResultOptionsHidden(false);
      this.activePage = 1;
      this.activeHasMore = true;
      if (newKeyword) {
        this.cachedResults.clear(); this.cachedPages.clear();
        this.cachedHasMore.clear(); this.cachedOrders.clear();
        this.activeResults = [];
        this.liveStreamers = [];
      }
      this.showSkeleton = firstSearch || newKeyword || this.activeResults.length === 0;
    }
    this.contentOpacity = 1;
    this.contentTranslateY = 0;
    // Native insert/remove transitions move the landing and loading scenes together.
    if (firstSearch) {
      this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 300, curve: Curve.FastOutSlowIn }, () => {
        this.hasActiveSearch = true;
      });
    } else {
      this.hasActiveSearch = true;
    }
    try {
      let page = this.activePage;
      const items = tab === 'live_user'
        ? await this.searchLiveFeedRooms(keyword, page, request)
        : await searchByType(keyword, tab, page, 20, order);
      if (request !== this.searchRequestVersion) return;
      let collected = items;
      if (tab === 'live_user' && reset) {
        let hasMore = items.length >= 20;
        let searched = 1;
        while (collected.length < 10 && hasMore && searched < 10) {
          const more = await this.searchLiveFeedRooms(keyword, ++page, request);
          if (request !== this.searchRequestVersion) return;
          collected = collected.concat(more);
          hasMore = more.length >= 20;
          searched++;
        }
      }
      this.activePage = page;
      this.activeHasMore = tab === 'live_user' ? collected.length >= 20 : items.length > 0;
      this.activeResults = reset ? collected : this.activeResults.concat(collected);
      // 搜索结果没有首页那种列表阶段预取：点击瞬间才发取流请求，实测要多等 ~200ms。
      // 结果一回来就把前几条的地址备好（只取地址，不下媒体、不建播放器）。
      if (tab === 'video') {
        prefetchPlayUrlsOnly(this.activeResults, AppStorage.get<number>('defaultVideoQn') ?? 116);
      }
      this.showSkeleton = false;
      this.isLoading = false;
      this.cachedResults.set(tab, this.activeResults);
      this.cachedPages.set(tab, this.activePage);
      this.cachedHasMore.set(tab, this.activeHasMore);
      this.hideHistoryWithAnimation();
      if (tab === 'bili_user') await this.initFollowedUsers();
    } catch (error) {
      if (request !== this.searchRequestVersion) return;
      this.searchError = '搜索失败，请重试';
      logError('[SearchPage] 搜索请求失败', error);
    } finally {
      if (request === this.searchRequestVersion) {
        this.isLoading = false;
        this.showSkeleton = false;
      }
    }
  }

  /**
   * 切换到指定 Tab：保存当前 Tab 状态，恢复目标 Tab 状态
   */
  switchToTab(tabKey: string): void {
    const cacheCurrent = !this.isLoading;
    this.searchRequestVersion++;
    this.isLoading = false;
    this.showSkeleton = false;
    this.searchError = "";
    // Loading an uncached tab must not cache the previous category's rows under its key.
    if (cacheCurrent) {
      this.cachedResults.set(this.activeTab, this.activeResults);
      this.cachedPages.set(this.activeTab, this.activePage);
      this.cachedHasMore.set(this.activeTab, this.activeHasMore);
      this.cachedOrders.set(this.activeTab, this.activeOrder);
    }

    // 切换到新 Tab
    this.activeTab = tabKey;
    this.setResultOptionsHidden(false);

    // 从缓存恢复目标 Tab 状态（直接替换，不淡入淡出）
    const cached = this.cachedResults.get(tabKey);
    if (cached && cached.length > 0) {
      this.hasActiveSearch = true;
      this.activeResults = cached;
      this.activePage = this.cachedPages.get(tabKey) || 1;
      this.activeHasMore = this.cachedHasMore.get(tabKey) ?? true;
      this.activeOrder = this.cachedOrders.get(tabKey) || 'totalrank';
    } else {
      // Uncached categories show their own loading scene immediately.
      this.activeResults = [];
      this.performSearch(true);
    }
  }

  /** 直播 Tab：搜索直播间（live_room），主播存入 liveStreamers */
  private async searchLiveFeedRooms(keyword: string, page: number, request: number): Promise<RecommendItem[]> {
    const rooms: RecommendItem[] = [];
    const existingIds = new Set<string>();

    // 1) 搜索直播间（live_room）
    try {
      const roomResults = await searchLive(keyword, page, 20);
      if (request !== this.searchRequestVersion) return [];
      for (const item of roomResults) {
        if (item.id && !existingIds.has(item.id)) {
          rooms.push(item);
          if (item.id) existingIds.add(item.id);
        }
      }
      logInfo(`[SearchPage] searchLive(room) → ${roomResults.length} 条`);
    } catch (err) {
      logWarn(`[SearchPage] searchLive(room) 失败: ${err}`);
    }

    // 2) 搜索正在直播的主播（live_user），只取第一页
    if (page === 1) {
      try {
        const userResults = await searchByType(keyword, 'live_user', 1, 20);
        if (request !== this.searchRequestVersion) return [];
        const newStreamers: RecommendItem[] = [];
        const streamerIds = new Set<string>();
        for (const item of userResults) {
          if (item.id && !streamerIds.has(item.id)) {
            newStreamers.push(item);
            streamerIds.add(item.id);
            // 也标记到已有 ID 集，避免与直播间重复
            if (item.id) existingIds.add(item.id);
          }
        }
        this.liveStreamers = newStreamers.sort((a, b) => (b.pubdate || 0) - (a.pubdate || 0));
        this.showAllStreamers = false;
        logInfo(`[SearchPage] searchByType(live_user) → ${newStreamers.length} 条主播`);
      } catch (err) {
        logWarn(`[SearchPage] searchByType(live_user) 失败: ${err}`);
      }
    }

    // 3) 如果房间不足 20 条，从推荐流补全（不包含主播列表中的房间）
    if (rooms.length < 20) {
      try {
        const lowerKw = keyword.toLowerCase();
        const feedRooms = await fetchRecommendedLiveRooms(page, 50);
        if (request !== this.searchRequestVersion) return [];
        const matched = feedRooms.filter((r: LiveFeedRoom) =>
        r.title.toLowerCase().includes(lowerKw) ||
          r.uname.toLowerCase().includes(lowerKw)
        );
        const feedItems = matched.map((r: LiveFeedRoom): RecommendItem => {
          const item = new RecommendItem();
          item.id = r.roomId ? `live_${r.roomId}` : '';
          item.title = r.title;
          item.ownerName = r.uname;
          item.ownerFace = r.face ? (r.face.startsWith('//') ? `https:${r.face}` : r.face) : '';
          item.coverUrl = r.cover ? (r.cover.startsWith('//') ? `https:${r.cover}` : r.cover.startsWith('http') ? r.cover : `https:${r.cover}`) : '';
          item.pubdate = 1;
          item.ownerMid = String(r.uid);
          return item;
        });
        for (const fi of feedItems) {
          if (!existingIds.has(fi.id)) {
            rooms.push(fi);
            existingIds.add(fi.id);
          }
        }
        logInfo(`[SearchPage] 推荐流补全 ${feedItems.length} 条，去重后共 ${rooms.length} 条`);
      } catch (err) {
        logWarn(`[SearchPage] 推荐流补全失败: ${err}`);
      }
    }

    return rooms;
  }

  /** 格式化观看人数（如 1.2万） */
  formatShortCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万';
    }
    return String(count);
  }

  addToSearchHistory(keyword: string) {
    this.settleHistoryDisintegration();
    const index = this.searchHistory.indexOf(keyword);
    if (index !== -1) {
      this.searchHistory.splice(index, 1);
    }
    this.searchHistory.unshift(keyword);
    if (this.searchHistory.length > 30) {
      this.searchHistory = this.searchHistory.slice(0, 30);
    }
    this.saveSearchHistory();
  }

  private beginHistoryDisintegration(words: string[]): void {
    if (this.dissolvingHistory.length > 0 || words.length === 0) return;
    this.completedHistoryDust = [];
    this.visibleHistoryDust = (this.showAllHistory ? this.searchHistory :
      this.searchHistory.slice(0, this.searchHistoryRows * (this.isLandscape ? 8 : 5)))
      .filter(word => words.includes(word));
    this.dissolvingHistory = words.slice();
    // Persist intent now; navigation or snapshot failure must not undo a confirmed deletion.
    this.saveSearchHistory();
    if (this.visibleHistoryDust.length === 0) this.settleHistoryDisintegration();
  }

  private settleHistoryDisintegration(): void {
    if (this.dissolvingHistory.length === 0) return;
    this.searchHistory = this.searchHistory.filter(word => !this.dissolvingHistory.includes(word));
    this.dissolvingHistory = [];
    this.completedHistoryDust = [];
    this.visibleHistoryDust = [];
  }

  private finishHistoryDisintegration(word: string): void {
    if (!this.visibleHistoryDust.includes(word) || this.completedHistoryDust.includes(word)) return;
    this.completedHistoryDust.push(word);
    if (this.completedHistoryDust.length !== this.visibleHistoryDust.length) return;
    const removed = this.dissolvingHistory.slice();
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 220, curve: Curve.EaseOut }, () => {
      this.searchHistory = this.searchHistory.filter(item => !removed.includes(item));
      this.dissolvingHistory = [];
      this.completedHistoryDust = [];
      this.visibleHistoryDust = [];
    });
  }

  removeFromSearchHistory(index: number): void {
    if (index >= 0 && index < this.searchHistory.length) {
      this.beginHistoryDisintegration([this.searchHistory[index]]);
    }
  }

  clearSearchHistory() {
      this.getUIContext().getPromptAction().showDialog({
        title: '确认清空',
        message: '确定要清空所有搜索历史吗？',
        buttons: [
          { text: '取消', color: '#666666' },
          { text: '清空', color: '#FB7299' }
        ]
      }).then((result) => {
        if (result.index === 1) {
          this.beginHistoryDisintegration(this.searchHistory);
        }
      }).catch(() => {});
    }

  loadMore() {
    if (!this.activeHasMore || this.isLoading) return;
    this.activePage++;
    this.performSearch(false);
  }

  // ═══════════════════════════════════════════
  // 智感握持 —— 回到顶部按钮定位
  // ═══════════════════════════════════════════

  private recalcSmartGripPosition(): void {
    const screenH: number = this.isLandscape ? 520 : 720; // 兜底值
    const bottomSafe: number = 24;
    if (this.isLandscape) {
      this.smartGripBottom = Math.max(bottomSafe + 24, screenH * 0.20);
    } else {
      this.smartGripBottom = Math.max(bottomSafe + 12, screenH * 0.15);
    }
    const LEFT_HAND = 1; // motion.HoldingHandStatus.LEFT_HAND_HELD
    // 两边始终保持有效值，避免 position 跳变触发平移动画
    this.smartGripLeft = this.gripSafeAreaLeft + 16;
    this.smartGripRight = this.gripSafeAreaRight + 8;
  }

  private initSmartGrip(): void {
    if (this.gripListenersInitialized) return;
    if (!this.smartGripEnabled) return;
    try {
      motion.on('holdingHandChanged', (data: number) => {
        if (data !== this.hand && (data === 1 || data === 2)) {
          this.hand = data;
          this.recalcSmartGripPosition();
        }
      });
      this.gripListenersInitialized = true;
    } catch (_e) { }
  }

  // 统一触觉反馈（短震动）
  private triggerHaptic(): void {
    VibrateUtils.vibrateTime(15);
  }

  private async saveFloatBtnPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('searchFloatBtnSide', this.searchFloatBtnSide);
      await pref.put('searchFloatBtnY', this.searchFloatBtnY);
      await pref.flush();
    } catch (e) {
      logError('保存悬浮按钮位置失败', e);
    }
  }

  /** 回到顶部按钮点击（覆盖层 Up 未拖动时调用，替代 TabBar onTabBarClick） */
  private handleBackToTopClick(): void {
    this.triggerHaptic();
    animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
      this.btnScale = 0.8;
    });
    setTimeout(() => {
      animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
        this.btnScale = 1;
      });
    }, 100);
    this.setResultOptionsHidden(false);
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
  }

  private returnToSearchLanding(): void {
    this.searchRequestVersion++;
    const scene = ++this.sceneVersion;
    this.searchText = '';
    this.showClearButton = false;
    this.suppressSuggestDebounce = false;
    this.showSuggestions = false;
    this.suggestionWords = [];
    this.showBackToTop = false;
    if (this.suggestTimer > 0) { clearTimeout(this.suggestTimer); this.suggestTimer = 0; }
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 300, curve: Curve.FastOutSlowIn,
      onFinish: () => {
        if (scene !== this.sceneVersion || this.hasActiveSearch) return;
        this.activeResults = [];
        this.isLoading = false;
        this.showSkeleton = false;
        this.activePage = 1;
        this.activeHasMore = true;
        this.contentOpacity = 1;
        this.contentTranslateY = 0;
        this.searchError = '';
      } }, () => { this.hasActiveSearch = false; });
  }

  goBack(): void {
    this.triggerHaptic();
    if (this.returnToCaller) { this.getUIContext().getRouter().back(); return; }
    if (this.hasActiveSearch || this.searchText.trim().length > 0) {
      this.returnToSearchLanding();
      return;
    }
    router.back();
  }

  onBackPress(): boolean | void {
    if (this.returnToCaller) return false;
    if (this.hasActiveSearch || this.searchText.trim().length > 0) {
      this.returnToSearchLanding();
      return true;
    }
    return false;
  }

  // 向下渐隐清空搜索结果
  private animateClearResults(): void {
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 300, curve: Curve.EaseIn }, () => {
      this.contentOpacity = 0;
      this.contentTranslateY = 50; // 向下位移
      this.historyOpacity = 0;
      this.historyTranslateY = -20; // 历史同步向上淡出
    });

    setTimeout(() => {
      this.searchText = '';
      this.showClearButton = false;
      this.activeResults = [];
      this.activePage = 1;
      this.activeHasMore = true;
      this.showSkeleton = false;
      this.showBackToTop = false;
      this.isLoading = false;
      this.showHistory = this.searchHistory.length > 0;
      this.contentOpacity = 1;
      this.contentTranslateY = 0;
      this.historyOpacity = 0;
      this.historyTranslateY = -20;

      // 回到初始态后若有历史记录，渐显
      if (this.showHistory) {
        setTimeout(() => {
          animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 250, curve: Curve.EaseOut }, () => {
            this.historyOpacity = 1;
            this.historyTranslateY = 0;
          });
        }, 16);
      }
    }, 300);
  }

  // 带动画显示搜索历史
  private showHistoryWithAnimation(): void {
    this.showHistory = true;
    this.historyOpacity = 0;
    this.historyTranslateY = -20;
    setTimeout(() => {
      animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 250, curve: Curve.EaseOut }, () => {
        this.historyOpacity = 1;
        this.historyTranslateY = 0;
      });
    }, 16);
  }

  // 带动画隐藏搜索历史
  private hideHistoryWithAnimation(): void {
    if (!this.showHistory) return;
    animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 200, curve: Curve.EaseIn }, () => {
      this.historyOpacity = 0;
      this.historyTranslateY = -20;
    });
    if (this.hideHistoryTimeout) {
      clearTimeout(this.hideHistoryTimeout);
    }
    this.hideHistoryTimeout = setTimeout(() => {
      this.showHistory = false;
      this.historyOpacity = 0;
      this.historyTranslateY = -20;
      this.hideHistoryTimeout = 0;
    }, 200);
  }

  async playVideo(item: RecommendItem) {
    if (!item.id) {
      this.getUIContext().getPromptAction().showToast({ message: '视频ID无效' });
      return;
    }

    // 番剧/影视（PGC）：id 形如 media_12345，跳转播放页并传 mediaId
    if (item.id.startsWith('media_')) {
      const mediaIdStr = item.id.substring(6);
      const mediaId = parseInt(mediaIdStr);
      if (isNaN(mediaId) || mediaId <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '番剧ID无效' });
        return;
      }
      this.getUIContext().getRouter().pushUrl({
        url: 'pages/VideoPlayerPage',
        params: {
          mediaId: mediaId,
          title: item.title,
          coverUrl: item.coverUrl,
          score: item.pgcScore ? item.pgcScore.toString() : '',
          indexShow: item.pgcEpSize ? `全${item.pgcEpSize}话` : '',
        }
      });
      return;
    }

    // 点击即进入播放器；缺 CID 时由共享详情请求补齐，页面转场不等待网络。
    prefetchVideoPlayback(item.id, item.cid || 0, AppStorage.get<number>('defaultVideoQn') ?? 116);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/VideoPlayerPage',
      params: { bvid: item.id, aid: item.aid, cid: item.cid || 0,
        title: item.title, coverUrl: item.coverUrl }
    }).catch((error: Error) => { logError('跳转播放页失败', error.message); });
  }

  clearSearchText() {
    this.returnToSearchLanding();
  }

  onSearchTextChange(value: string) {
    this.searchText = value;
    this.showClearButton = value.length > 0;

    // 防抖：清除之前的定时器
    if (this.suggestTimer > 0) {
      clearTimeout(this.suggestTimer);
      this.suggestTimer = 0;
    }
    // 隐藏搜索建议面板
    if (this.showSuggestions) {
      this.showSuggestions = false;
      this.suggestionWords = [];
    }

    // 程序化设置文本（如点击建议词）时不触发防抖
    if (this.suppressSuggestDebounce) {
      return;
    }

    // 加载中或首次搜索过渡中不触发搜索建议
    if (this.showSkeleton || (this.isLoading && !this.hasActiveSearch)) {
      return;
    }

    // 输入不为空时，延迟 300ms 请求搜索建议
    if (value.trim().length > 0) {
      this.suggestTimer = setTimeout(async () => {
        this.suggestTimer = 0;
        const words = await fetchSearchSuggestions(value.trim());
        if (words.length > 0 && this.searchText.trim().length > 0) {
          this.suggestionWords = words;
          this.showSuggestions = true;
        }
      }, 300);
    }
  }

  /** 热搜标签文字颜色 */
  private getTagTextColor(tag: string): string {
    switch (tag) {
      case '新': return '#FFFFFF';
      case '热': return '#FFFFFF';
      case '梗': return '#FFFFFF';
      case '话题': return '#FFFFFF';
      case '活动': return '#FFFFFF';
      case '推荐': return '#FFFFFF';
      case '上升': return '#FFFFFF';
      default: return '#FFFFFF';
    }
  }

  /** 热搜标签背景色 */
  private getTagBgColor(tag: string): string {
    switch (tag) {
      case '新': return '#FFB526';  // 天蓝
      case '热': return '#FF5158';  // 粉红
      case '梗': return '#CE93D8';  // 浅紫
      case '话题': return '#4FC3F7'; // 浅蓝
      case '独家': return '#FFD54F'; // 琥珀
      case '直播': return '#FF7043'; // 橙红
      case '活动': return '#FFB74D'; // 橙色
      case '推荐': return '#4DB6AC'; // 青绿
      case '上升': return '#FF8A65'; // 珊瑚
      default: return '#90A4AE';    // 灰蓝
    }
  }

  private async loadHotSearch(): Promise<void> {
    const items = await fetchHotSearch();
    if (items.length > 0) {
      this.hotSearchItems = items;
    }
  }

  private async loadSearchDiscovery(): Promise<void> {
    const words = await fetchSearchDiscovery();
    // 如果已有搜索结果，不再更新搜索发现（防止搜索完成后弹出）
    if (this.activeResults.length > 0) return;
    if (words.length > 0) {
      this.searchDiscoveryWords = words;
    }
  }

  private resultTabLabel(key: string): string {
    if (key === 'video') return '综合';
    if (key === 'article') return '图文';
    return getSearchTypeLabel(key);
  }

  private resultOrderLabel(key: string): string {
    switch (key) {
      case 'totalrank': return '默认排序';
      case 'pubdate': return '新发布';
      case 'click': return '播放多';
      case 'dm': return '弹幕多';
      default: return getSearchOrderLabel(key);
    }
  }

  private setResultOptionsHidden(hidden: boolean): void {
    const height = hidden ? 0 : (this.activeTab === 'video' ? 88 : 44);
    if (this.resultOptionsHidden === hidden && this.resultOptionsHeight === height) return;
    this.resultOptionsHidden = hidden;
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: this.da ? 0 : 280, curve: Curve.FastOutSlowIn }, () => {
      this.resultOptionsHeight = height;
    });
  }

  @Builder
  ResultOptions() {
    Column() {
      Row() {
        ForEach(TAB_KEYS, (key: string) => {
          Column() {
            Text(this.resultTabLabel(key))
              .fontSize(15)
              .fontWeight(key === this.activeTab ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(key === this.activeTab ? '#FB7299' : (this.isDarkMode ? '#B6BAC0' : '#61666D'))
              .height(38)
              .textAlign(TextAlign.Center)
            Row().width(28).height(2)
              .backgroundColor(key === this.activeTab ? '#FB7299' : Color.Transparent)
          }
          .layoutWeight(1).height(44)
          .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.inputController.stopEditing();
            if (key !== this.activeTab) {
              this.triggerHaptic();
              this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
              this.switchToTab(key);
            }
          })
        }, (key: string) => key)
      }
      .width('100%').height(44)
      if (this.activeTab === 'video') {
        Row() {
          ForEach(RESULT_ORDER_KEYS, (key: string) => {
            Text(this.resultOrderLabel(key))
              .fontSize(14)
              .fontColor(key === this.activeOrder ? '#FB7299' : (this.isDarkMode ? '#B6BAC0' : '#61666D'))
              .height(44).padding({ left: 14, right: 14 })
              .onClick(() => {
                this.inputController.stopEditing();
                if (key !== this.activeOrder) {
                  this.triggerHaptic();
                  this.activeOrder = key;
                  this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
                  this.performSearch(true);
                }
              })
          }, (key: string) => key)
        }
        .width('100%').height(44).justifyContent(FlexAlign.Start)
      }
    }
    .width('100%').height(this.activeTab === 'video' ? 88 : 44)
    .translate({ y: this.resultOptionsHeight - (this.activeTab === 'video' ? 88 : 44) })
  }

  private searchLandingWord(word: string): void {
    this.triggerHaptic();
    this.searchText = word;
    this.inputController.stopEditing();
    this.performSearch(true);
  }

  @Builder
  HotWord(item: HotSearchItem) {
    Row({ space: 4 }) {
      Text(item.showName || item.keyword)
        .fontSize(14)
        .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      if (item.iconUrl) {
        Image(item.iconUrl).width(16).height(16).objectFit(ImageFit.Contain).flexShrink(0)
      } else if (item.tagLabel) {
        Text(item.tagLabel)
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 3, right: 3 })
          .height(16)
          .borderRadius(2)
          .backgroundColor(this.getTagBgColor(item.tagLabel))
          .flexShrink(0)
      }
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  SearchLanding() {
    Column() {
      if (this.showHotSearch && this.hotSearchItems.length > 0) {
        Column() {
          Row() {
            Text('bilibili 热搜')
              .gesture(LongPressGesture().onAction(() => { this.showEditPanel = true; }))
              .fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
            Blank()
            Row({ space: 4 }) {
              Text('完整榜单').fontSize(13)
                .fontColor(this.isDarkMode ? '#85898E' : '#9499A0')
              Image($r('app.media.chevron_right')).width(12).height(12)
                .fillColor(this.isDarkMode ? '#85898E' : '#9499A0')
            }
            .height(32)
            .onClick(() => {
              this.inputController.stopEditing();
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/HotRankingPage', params: { items: this.hotSearchItems }
              }).catch((error: Error) => logError('[SearchPage] 打开完整榜单失败', error));
            })
          }
          .width('100%').margin({ bottom: 4 })
          Grid() {
            ForEach(this.hotSearchItems.slice(0, 10), (item: HotSearchItem) => {
              GridItem() {
                Row() { this.HotWord(item) }
                  .width('100%').height(36)
                  .onClick(() => this.searchLandingWord(item.keyword))
              }
            }, (item: HotSearchItem) => item.keyword)
          }
          .columnsTemplate(this.isLandscape ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
          .columnsGap(24).rowsGap(2)
        }
        .width('100%').margin({ bottom: 12 })
      }
      if (this.showSearchHistory && this.searchHistory.length > 0) {
        Column() {
        PageSurface({ radius: 20, forceGlass: true }) {
        Column() {
          Row() {
            Text('搜索历史').fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
            Blank()
            Row() {
              Image($r('app.media.trash')).width(18).height(18)
                .fillColor(this.isDarkMode ? '#85898E' : '#9499A0')
            }
            .width(32).height(32).justifyContent(FlexAlign.End)
            .onClick(() => this.clearSearchHistory())
          }
          .width('100%').margin({ bottom: 4 })
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.showAllHistory ? this.searchHistory :
              this.searchHistory.slice(0, this.searchHistoryRows * (this.isLandscape ? 8 : 5)),
              (word: string, index: number) => {
                HistoryDustChip({ word: word, dark: this.isDarkMode,
                  dissolving: this.dissolvingHistory.includes(word), staggerMs: (index % 7) * 22,
                  onActivate: () => { if (this.dissolvingHistory.length === 0) this.searchLandingWord(word); },
                  onDelete: () => this.removeFromSearchHistory(index),
                  onGone: () => this.finishHistoryDisintegration(word) })
                  .margin({ right: 6, bottom: 6 })
              }, (word: string) => word)
            if (this.searchHistory.length > this.searchHistoryRows * (this.isLandscape ? 8 : 5)) {
              Text(this.showAllHistory ? '收起' : '展开')
                .fontSize(13).fontColor('#9499A0').height(30)
                .padding({ left: 12, right: 12 })
                .onClick(() => { this.showAllHistory = !this.showAllHistory; })
            }
          }
          .width('100%')
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 4 })
        }
        }.width('100%').id('search-history-surface').margin({ bottom: 10 })
      }
      if (this.showSearchDiscovery && this.searchDiscoveryWords.length > 0) {
        Column() {
        PageSurface({ radius: 20, forceGlass: true }) {
        Column() {
          Row() {
            Text('搜索发现').fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
            Blank()
            Row() {
              Image(this.discoveryHidden ? $r('app.media.search_eye_hidden') : $r('app.media.search_eye'))
                .width(18).height(18)
            }
            .width(32).height(32).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.End)
            .id('search-discovery-toggle')
            .accessibilityText(this.discoveryHidden ? '显示搜索发现' : '隐藏搜索发现')
            .onClick(() => { this.discoveryHidden = !this.discoveryHidden; })
          }
          .width('100%').height(32).alignItems(VerticalAlign.Center)
          .margin({ bottom: this.discoveryHidden ? 0 : 4 })
          if (!this.discoveryHidden) {
            Grid() {
              ForEach(this.searchDiscoveryWords.slice(0, 12), (word: string) => {
                GridItem() {
                  Text(word)
                    .fontSize(14)
                    .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .padding({ left: 4, right: 4 })
                    .width('100%').height(36).borderRadius(10)
                    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
                    .onClick(() => this.searchLandingWord(word))
                }
              }, (word: string) => word)
            }
            .columnsTemplate(this.isLandscape ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
            .columnsGap(12).rowsGap(2)
          }
        }
        .width('100%').padding({ left: 12, right: 12, top: 8, bottom: this.discoveryHidden ? 8 : 10 })
        }
        }.width('100%').id('search-discovery-surface')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 8, bottom: 16 })
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
    Stack() {
      // PageWallpaper owns image and neutral backgrounds.
      // 搜索首页和结果页各自保留滚动视口，转场时结果页不会因首页高度变化而跳动。
      if (!this.hasActiveSearch) {
        Scroll() {
          Column() {
            Column()
              .width('100%')
              .height((this.hideStatusBar ? 0 : this.globalStatusBarHeight) + this.SEARCH_BAR_SPACER + this.SEARCH_BAR_STACK_HEIGHT)
            if (this.isInitialLoading) {
              Column() {
                LoadingProgress().width(40).height(40).color('#FF6699').margin({ top: 100 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
            } else {
              this.SearchLanding()
            }
          }
          .width('100%')
        }
        .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .id('search-landing-scene')
        .transition(TransitionEffect.translate({ x: -this.currentWindowW }))
      } else {
        Scroll(this.scroller) {
          Column() {
            Column()
              .width('100%')
              .height((this.hideStatusBar ? 0 : this.globalStatusBarHeight) + this.SEARCH_BAR_SPACER + this.SEARCH_BAR_STACK_HEIGHT + (this.activeTab === 'video' ? 88 : 44))
            Column() {
              if (this.showSkeleton) {
              // 骨架屏
              WaterFlow() {
                ForEach([0, 1, 2, 3, 4], (idx: number) => {
                  FlowItem() { this.SkeletonCard(idx) }
                })
              }
              .columnsTemplate(this.activeTab === 'live_user'
                ? (this.isLandscape ? '1fr 1fr 1fr' : '1fr 1fr')
                : (this.isLandscape ? '1fr 1fr' : '1fr'))
              .columnsGap(this.cardListMargin)
              .rowsGap(this.activeTab === 'video' || this.activeTab === 'media_bangumi' || this.activeTab === 'media_ft' ? 0 : (this.activeTab === 'bili_user' || this.activeTab === 'article' ? Math.max(8, this.cardListMargin) : this.cardListMargin))
              .padding({ left: 14, right: 14, top: 4 })
              .backgroundColor('transparent')

            } else {
              // ────────── 直播搜索结果 — 主播区（折叠/展开） ──────────
              if (this.activeTab === 'live_user' && this.liveStreamers.length > 0) {
                Column() {
                  // 区头
                  Row() {
                    Text('主播').fontSize(16).fontWeight(FontWeight.Bold)
                      .fontColor(this.isDarkMode ? Color.White : Color.Black)
                    Text(`(${this.liveStreamers.length})`)
                      .fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999').margin({ left: 4 })
                    Blank()
                    if (this.liveStreamers.length > 8) {
                      Text(this.showAllStreamers ? '收起' : '展开全部')
                        .fontSize(12).fontColor('#FB7299')
                        .onClick(() => {
                          this.showAllStreamers = !this.showAllStreamers;
                        })
                    }
                  }
                  .width('100%').padding({ left: 14, right: 14, bottom: 8 })
                  // 主播胶囊行（Flex 支持换行，默认显示 2 排约 6 个）
                  Flex({ wrap: FlexWrap.Wrap }) {
                    ForEach(this.liveStreamers.slice(0,
                      this.showAllStreamers ? this.liveStreamers.length : 8
                    ), (streamer: RecommendItem) => {
                      Row() {
                        ImmersiveLightWrapper({ radius: 18, materialStyle: 0, lightIntensity: 2.0 }) {
                          Row() {
                            if (streamer.ownerFace) {
                              Image(streamer.ownerFace)
                                .width(28).height(28)
                                .borderRadius(14)
                                .objectFit(ImageFit.Cover)
                                .margin({ right: 6 })
                            }
                            Text(streamer.ownerName || '')
                              .fontSize(13)
                              .fontColor(this.isDarkMode ? Color.White : Color.Black)
                              .maxLines(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                            // 粉色直播状态指示图标（仅正在直播的显示）
                            if (streamer.pubdate > 0) {
                              Image($r('app.media.ic_public_brightness_filled'))
                                .width(12).height(12)
                                .fillColor('#FB7299')
                                .margin({ left: 4 })
                            }
                          }
                          .height(36)
                          .padding({ left: 4, right: 12 })
                          .alignItems(VerticalAlign.Center)
                          .onClick(() => {
                            if (streamer.id) {
                              this.enterLiveRoom(streamer.id);
                            }
                          })
                        }
                      }
                      .margin({ right: 8, bottom: 8 })
                    })
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, bottom: 12 })
                }
              }

              // ────────── 直播搜索结果 — 直播间区头 ──────────
              if (this.activeTab === 'live_user' && this.activeResults.length > 0) {
                Row() {
                  Text('直播间').fontSize(16).fontWeight(FontWeight.Bold)
                    .fontColor(this.isDarkMode ? Color.White : Color.Black)
                  Text(`(${this.activeResults.length})`)
                    .fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999').margin({ left: 4 })
                  Blank()
                }
                .width('100%')
                .padding({ left: 14, right: 14, bottom: 8 })
              }

              // 搜索结果——竖屏单列 / 横屏双列
              WaterFlow() {
                ForEach(this.activeResults, (item: RecommendItem, index: number) => {
                  FlowItem() {
                    if (this.activeTab === 'video') {
                      this.VideoCard(item, index)
                    } else if (this.activeTab === 'bili_user') {
                      this.UserCard(item)
                    } else if (this.activeTab === 'article') {
                      this.ArticleSearchCard(item)
                    } else if (this.activeTab === 'live_user') {
                      this.LiveSearchCard(item)
                    } else if (this.activeTab === 'media_bangumi' || this.activeTab === 'media_ft') {
                      this.VideoCard(item, index)
                    } else {
                      this.LiveSearchCard(item)
                    }
                  }
                }, (item: RecommendItem) => item.id)
              }
              .columnsTemplate(this.activeTab === 'live_user'
                ? (this.isLandscape ? '1fr 1fr 1fr' : '1fr 1fr')
                : (this.isLandscape ? '1fr 1fr' : '1fr'))
              .columnsGap(this.cardListMargin)
              .rowsGap(this.activeTab === 'video' || this.activeTab === 'media_bangumi' || this.activeTab === 'media_ft' ? 0 : (this.activeTab === 'bili_user' || this.activeTab === 'article' ? Math.max(8, this.cardListMargin) : this.cardListMargin))
              .padding({ left: 14, right: 14, top: 4 })
              .backgroundColor('transparent')

              // ⭐ 空结果提示：搜索无结果时显示
              if (this.activeResults.length === 0 && !this.isLoading) {
                Column() {
                  Text(this.searchError || '未找到相关内容')
                    .fontSize(16)
                    .fontColor(this.isDarkMode ? '#888888' : '#999999')
                    .margin({ top: 80 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Center)
              }

              // 加载更多指示器
              if (this.isLoading) {
                Column() {
                  LoadingProgress()
                    .width(32).height(32)
                    .color('#FF6699')
                  Text('正在加载更多...')
                    .fontSize(14)
                    .fontColor(this.isDarkMode ? '#888888' : '#999999')
                    .margin({ top: 12 })
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .padding(24)
                .width('100%')
              } else if (!this.activeHasMore && this.activeResults.length > 0) {
                Row() {
                  Divider().strokeWidth(1)
                    .color(this.isDarkMode ? '#444444' : '#E0E0E0')
                    .layoutWeight(1)
                  Text('已经到底了')
                    .fontSize(12)
                    .fontColor(this.isDarkMode ? '#666666' : '#BBBBBB')
                    .margin({ left: 12, right: 12 })
                  Divider().strokeWidth(1)
                    .color(this.isDarkMode ? '#444444' : '#E0E0E0')
                    .layoutWeight(1)
                }
                .padding(16)
                .width('100%')
              }
            }
            }
          .opacity(this.contentOpacity)
          .translate({ y: this.contentTranslateY })
        }
        .width('100%')
      }
      .scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
      // 内容始终从搜索栏下方开始，避免短列表整体居中。
      .align(Alignment.Top)
      .onReachEnd(() => {
        if (this.hasActiveSearch && this.activeResults.length > 0 && !this.isLoading && this.activeHasMore) {
          this.loadMore();
        }
      })
      .onWillScroll((_xOffset: number, yOffset: number, _state: ScrollState, source: ScrollSource) => {
        if (this.hasActiveSearch) {
          const hidden = this.resultScrollTracker.update(yOffset, source);
          if (hidden !== undefined) this.setResultOptionsHidden(hidden);
        }

        // 滚动时检测是否超出阈值 → 显示/隐藏回到顶部按钮
        // 只有有搜索结果时才显示，回到初始页时无条件隐藏
        if (this.activeResults.length > 0) {
          const offset = this.scroller.currentOffset().yOffset;
          this.showBackToTop = Math.abs(offset) > 300;
        } else {
          this.showBackToTop = false;
        }
      })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .id('search-results-scene')
      .transition(TransitionEffect.translate({ x: this.currentWindowW }))
      }

      // ── 固定顶部的搜索栏 ──
      Stack({ alignContent: Alignment.TopStart }) {
        PageHeader({ withTabs: this.hasActiveSearch,
          scopeId: 'search-header-native-scope',
          materialHeight: (this.hideStatusBar ? 0 : this.globalStatusBarHeight) + this.SEARCH_BAR_SPACER +
            this.SEARCH_BAR_STACK_HEIGHT + (this.activeTab === 'video' ? 88 : 44) }) {
          Column() {
            // 状态栏占位
            Row()
              .height(this.hideStatusBar ? 0 : this.globalStatusBarHeight)
              .width('100%')
              .backgroundColor(Color.Transparent)

            Row()
              .height(8)
              .width('100%')
              .backgroundColor(Color.Transparent)

            // 搜索栏主体——改用 Row Flex 布局，避免绝对定位导致触摸测试 miss
            Row() {
              // 返回按钮与输入框同一基线
              Row() {
                HeaderBackButton({ onBack: () => this.goBack() })
              }
              .width(40)
              .height(40)


              // 中间搜索输入框（占据剩余宽度）
              Row() {
                HdsTabs() {
                  TabContent()
                    .tabBar(this.searchInputBar())
                    .backgroundColor(Color.Transparent)
                }
                .barWidth(this.searchInputBarW)
                .barHeight(40)
                .barOverlap(true)
                .barPosition(BarPosition.End)
                .barFloatingStyle({
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
                .width(this.searchInputBarW)
                .height(40)
                .clip(false)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .margin({ left: 8, right: 8 })

              Column() {
                HeaderGlassControl({ label: '搜索', controlId: 'search-header-submit', onActivate: () => {
                  this.triggerHaptic();
                  this.inputController.stopEditing();
                  this.performSearch(true);
                } }) {
                  Image($r('app.media.ic_public_search_filled')).width(22).height(22)
                    .fillColor(this.isDarkMode ? '#F2F4F8' : '#18191C').hitTestBehavior(HitTestMode.None)
                }
              }.width(40).height(40)
            }
            .width('100%')
            .height(this.SEARCH_BAR_STACK_HEIGHT)
            .alignItems(VerticalAlign.Center)
            .justifyContent(FlexAlign.SpaceBetween)
            .padding({ left: 14, right: 14 })
            if (this.hasActiveSearch) {
              Column() {
                this.ResultOptions()
              }
              .width('100%')
              .height(this.resultOptionsHeight)
              .clip(true)
              .hitTestBehavior(this.resultOptionsHidden ? HitTestMode.None : HitTestMode.Default)
              .accessibilityLevel(this.resultOptionsHidden ? 'no-hide-descendants' : 'auto')
            }
          }
          .width('100%')
        }
      }.width('100%')
      .clip(this.hasActiveSearch)
      .position({ x: 0, y: 0 })
      .zIndex(1)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newHeight: number = newValue.height as number;
        logInfo(`[SearchPage] onAreaChange: actualSearchBarHeight old=${this.actualSearchBarHeight} new=${newHeight} calculated=${this.getSearchBarHeight()} sb=${this.globalStatusBarHeight} hideSb=${this.hideStatusBar}`);
        if (Math.abs(this.actualSearchBarHeight - newHeight) > 1) {
          this.actualSearchBarHeight = newHeight;
        }
      })

      // ── 搜索建议面板 ──
      if (this.showSuggestions && this.suggestionWords.length > 0) {
        Column() {
          // 占位：将面板推到搜索栏下方
          Column() {}.height((this.hideStatusBar ? 0 : this.globalStatusBarHeight) + this.SEARCH_BAR_SPACER + this.SEARCH_BAR_STACK_HEIGHT)
          Column() {
            ForEach(this.suggestionWords.slice(0, 10), (word: string) => {
              Row() {
                Image($r('app.media.ic_public_search_filled'))
                  .width(14).height(14)
                  .fillColor(this.isDarkMode ? '#999999' : '#888888')
                  .margin({ right: 10 })
                Text(word)
                  .fontSize(14)
                  .fontColor(this.isDarkMode ? '#E0E0E0' : '#000000')
              }
              .width('100%')
              .height(40)
              .justifyContent(FlexAlign.Center)
              .hitTestBehavior(HitTestMode.Default)
              .onClick(() => {
                this.triggerHaptic();
                this.suppressSuggestDebounce = true;
                this.searchText = word;
                this.inputController.stopEditing();
                this.showSuggestions = false;
                this.suggestionWords = [];
                this.performSearch(true);
              })
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          // 与直播页分类面板一致：系统磨砂毛玻璃 + clip 裁切成型
          .backgroundBlurStyle(GlassMaterial.fallbackBlur('panel'))
          .clip(true)
        }
        .width('100%')
        .margin({ top: 8 })
        .padding({ left: 62, right: 62 })
        .position({ x: 0, y: 0 })
        .zIndex(2)
        .hitTestBehavior(HitTestMode.Transparent)
        .transition(this.da ? TransitionEffect.OPACITY : TransitionEffect.asymmetric(
            TransitionEffect.translate({ y: -12 }).combine(TransitionEffect.opacity(0))
              .animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 200, curve: Curve.FastOutSlowIn }),
            TransitionEffect.translate({ y: -12 }).combine(TransitionEffect.opacity(0))
              .animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 150, curve: Curve.FastOutSlowIn })
          )
        )

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
          // 触摸接管层：HdsTabs TabBar 原生消费事件导致外层 onTouch 收不到，
          // 用 Block 模式透明层强制接管，拖动+点击都由本层实现
          // 跟手优化：拖动中只更新 translate（GPU 变换不重排），Up 时才写回 position
          Column()
            .width(48).height(48)
            .hitTestBehavior(HitTestMode.Block)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.touchStartWX = event.touches[0].windowX;
                this.touchStartWY = event.touches[0].windowY;
                this.dragStartY = this.searchFloatBtnY;
                this.touchMoved = false;
                this.isDragging = true;
                logInfo('[searchFloatBtn] overlay touch down');
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                if (Math.abs(offYpx) > 5) {
                  this.touchMoved = true;
                }
                this.searchFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  AppStorage.set('searchFloatBtnY', this.searchFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else if (event.type === TouchType.Up) {
                  this.handleBackToTopClick();
                }
              }
            })
        }
        .width(48).height(48)
        .position({ bottom: this.searchFloatBtnY, left: this.smartGripLeft })
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
          // 触摸接管层：同左侧按钮
          Column()
            .width(48).height(48)
            .hitTestBehavior(HitTestMode.Block)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.touchStartWX = event.touches[0].windowX;
                this.touchStartWY = event.touches[0].windowY;
                this.dragStartY = this.searchFloatBtnY;
                this.touchMoved = false;
                this.isDragging = true;
                logInfo('[searchFloatBtn] overlay touch down');
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                if (Math.abs(offYpx) > 5) {
                  this.touchMoved = true;
                }
                this.searchFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  AppStorage.set('searchFloatBtnY', this.searchFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else if (event.type === TouchType.Up) {
                  this.handleBackToTopClick();
                }
              }
            })
        }
        .width(48).height(48)
        .position({ bottom: this.searchFloatBtnY, right: this.smartGripRight })
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
          // 触摸接管层：拖动+吸附+点击全由本层实现
          Column()
            .width(48).height(48)
            .hitTestBehavior(HitTestMode.Block)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.touchStartWX = event.touches[0].windowX;
                this.touchStartWY = event.touches[0].windowY;
                this.dragStartY = this.searchFloatBtnY;
                this.dragOffsetX = 0;
                this.touchMoved = false;
                this.isDragging = true;
                logInfo('[searchFloatBtn] overlay touch down');
              } else if (event.type === TouchType.Move) {
                const offYpx = event.touches[0].windowY - this.touchStartWY;
                const offXpx = event.touches[0].windowX - this.touchStartWX;
                if (Math.abs(offYpx) > 5 || Math.abs(offXpx) > 5) {
                  this.touchMoved = true;
                }
                this.searchFloatBtnY = Math.max(20, Math.min(this.maxFloatBtnBottom, this.dragStartY - Math.round(this.getUIContext().px2vp(offYpx))));
                this.dragOffsetX = Math.round(this.getUIContext().px2vp(offXpx));
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.isDragging = false;
                if (this.touchMoved) {
                  const totalOffsetX: number = this.dragOffsetX;
                  let newSide: string = this.searchFloatBtnSide;
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
                        this.searchFloatBtnSide = newSide;
                      }
                    });
                  } else {
                    this.dragOffsetX = 0;
                  }
                  AppStorage.set('searchFloatBtnSide', this.searchFloatBtnSide);
                  AppStorage.set('searchFloatBtnY', this.searchFloatBtnY);
                  this.saveFloatBtnPrefs();
                } else {
                  this.dragOffsetX = 0;
                  if (event.type === TouchType.Up) {
                    this.handleBackToTopClick();
                  }
                }
              }
            })
        }
        .width(48).height(48)
        .position(this.searchFloatBtnSide === 'left'
          ? { bottom: this.searchFloatBtnY, left: 32 }
          : { bottom: this.searchFloatBtnY, right: 32 })
        .opacity(this.showBackToTop ? 1 : 0)
        .scale({ x: this.showBackToTop ? this.btnScale : 0, y: this.showBackToTop ? this.btnScale : 0 })
        .hitTestBehavior(this.showBackToTop ? HitTestMode.Default : HitTestMode.None)
        .animation(this.da || this.isDragging ? { duration: 0 } : {
          duration: 300,
          curve: Curve.Ease
        })
        .translate({ x: this.dragOffsetX })
      }

    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .bindSheet(this.showEditPanel, this.searchEditPanel(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: this.isDarkMode ? '#1A1A1A' : '#FFFFFF',
      onDisappear: () => {
        this.showEditPanel = false;
      }
    })
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // ────────── Builder：搜索页编辑面板 ──────────
  @Builder
  searchEditPanel() {
    Column() {
      // 标题
      Row() {
        Text('编辑')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // 热搜开关
      Row() {
        Text('热搜')
          .fontSize(16)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showHotSearch })
          .onChange((isOn: boolean) => {
            this.triggerHaptic();
            this.showHotSearch = isOn;
            this.saveSearchEditSettings();
          })
          .selectedColor('#FB7299')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      Divider().color(this.isDarkMode ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)').margin({ left: 20, right: 20 })

      // 搜索历史开关
      Row() {
        Text('搜索历史')
          .fontSize(16)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showSearchHistory })
          .onChange((isOn: boolean) => {
            this.triggerHaptic();
            this.showSearchHistory = isOn;
            this.saveSearchEditSettings();
          })
          .selectedColor('#FB7299')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })

      // 搜索历史行数选择
      if (this.showSearchHistory) {
        Row() {
          Text('显示行数')
            .fontSize(14)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#666666')
          Blank()
          Row({ space: 8 }) {
            ForEach([1, 2, 3], (rows: number) => {
              Text(rows === 1 ? '少' : rows === 2 ? '中' : '多')
                .fontSize(13)
                .fontColor(this.searchHistoryRows === rows ? '#FB7299' : (this.isDarkMode ? '#FFFFFF' : '#666666'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .borderRadius(12)
                .backgroundColor(this.searchHistoryRows === rows ? 'rgba(251,114,153,0.15)' : 'rgba(255,255,255,0.08)')
                .onClick(() => {
                  this.triggerHaptic();
                  this.searchHistoryRows = rows;
                  this.saveSearchEditSettings();
                })
            })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 8, bottom: 12 })
      }

      Divider().color(this.isDarkMode ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)').margin({ left: 20, right: 20 })

      // 搜索发现开关
      Row() {
        Text('搜索发现')
          .fontSize(16)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showSearchDiscovery })
          .onChange((isOn: boolean) => {
            this.triggerHaptic();
            this.showSearchDiscovery = isOn;
            this.saveSearchEditSettings();
          })
          .selectedColor('#FB7299')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    }
    .width('100%')
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .borderRadius({ topLeft: 16, topRight: 16 })
  }

  // ────────── Builder：搜索输入栏（HdsTabs 承载沉浸光感）──────────
  @Builder
  searchInputBar() {
    Row() {
      Image($r('app.media.ic_public_search_filled'))
        .width(18).height(18)
        .margin({ left: 14 })
        .fillColor(this.isDarkMode ? '#8B8E93' : '#9499A0')

      TextInput({
        placeholder: '搜索 B 站视频',
        text: this.searchText,
        controller: this.inputController
      })
        .id('search-text-input')
        .defaultFocus(!this.fromHotRanking)
        .layoutWeight(1)
        .height('100%')

        .backgroundColor(Color.Transparent)
        .margin({ left: 8, right: 8 })
        .placeholderColor(this.isDarkMode ? '#8B8E93' : '#9499A0')
        .placeholderFont({ size: 15 })
        .caretColor('#FF6699')
        .fontColor($r('app.color.color_primary_text'))
        .fontSize(15)
        .textAlign(TextAlign.Start)
        .padding({ left: 0, right: 0, top: 0, bottom: 0 })
        .enterKeyType(EnterKeyType.Search)
        .onChange((value) => {
          this.onSearchTextChange(value);
        })
        .onSubmit(() => {
          this.showSuggestions = false;
          this.suggestionWords = [];
          this.performSearch(true);
        })
        .onEditChange((isEditing) => {
          this.searchBarFocused = isEditing;
          if (isEditing) {
            this.setResultOptionsHidden(false);
            if (this.searchHistory.length > 0) {
              this.showHistoryWithAnimation();
            }
          } else {
            this.hideHistoryWithAnimation();
          }
        })

      if (this.showClearButton) {
        Image($r('app.media.ic_public_cancel_filled'))
          .width(18).height(18)
          .margin({ right: 14 })
          .fillColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.85 })
          .onClick(() => {
            this.triggerHaptic();
            this.clearSearchText();
          })
      }
    }
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
  }

  // ────────── Builder：搜索结果卡片（对齐发现页风格）──────────
  @Builder
  ArticleSearchCard(item: RecommendItem) {
    PageSurface({ radius: 12 }) {

    Row({ space: 12 }) {
      if (item.coverUrl) {
        Image(item.coverUrl).width(120).height(80).objectFit(ImageFit.Cover).borderRadius(6)
      }
      Column({ space: 8 }) {
        Text(item.title).fontSize(14)
          .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
          .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.ownerName + ' · ' + this.formatNumber(item.playCount) + '阅读')
          .fontSize(12).fontColor('#9499A0')
      }
      .layoutWeight(1).alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(12)
    .onClick(() => {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility({
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: 'https://www.bilibili.com/read/cv' + item.id.replace('article_', '')
      }).catch((error: Error) => {
        logError('[SearchPage] 打开图文失败', error);
        this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开图文' });
      });
    })

    }
  }

  @Builder
  VideoCard(item: RecommendItem, index: number) {
    VideoListItem({
      title: item.title, cover: item.coverUrl, duration: item.duration,
      videoId: this.activeTab === 'video' ? item.id : '', ownerMid: item.ownerMid,
      owner: item.ownerName,
      playCount: this.activeTab === 'media_bangumi' || this.activeTab === 'media_ft' ? -1 : item.playCount,
      dateText: videoListPublished(item.pubdate),
      detailText: this.activeTab === 'media_bangumi' || this.activeTab === 'media_ft'
        ? (item.pgcEpSize > 0 ? `共${item.pgcEpSize}集` : '') +
          (item.pgcScore > 0 ? `  ${item.pgcScore.toFixed(1)}分` : '') : '',
      onActivate: () => { this.triggerHaptic(); this.playVideo(item); }
    })
  }

  @Builder
  SkeletonCard(index: number) {
    VideoListItem({ loading: true })
  }

  // ────────── 直播搜索卡片（仿 LivePage 垂直卡片风格） ──────────
  @Builder
  LiveSearchCard(item: RecommendItem) {
    ChannelCardSurface({ radius: 12 }) {

    Column() {
      // ---- 封面区 ----
      Stack() {
        Image(item.coverUrl)
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
        if (item.online > 0) {
          Row() {
            Image($r('app.media.ic_public_screencap'))
              .width(12).height(12)
              .fillColor(Color.White)
            Text(this.formatShortCount(item.online))
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ left: 3 })
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('rgba(0,0,0,0.55)')
          .borderRadius(4)
          .position({ bottom: 6, right: 6 })
        }
      }
      .width('100%')
      .borderRadius(12)
      .clip(true)
      .backgroundColor(this.isDarkMode ? '#333333' : '#F0F0F0')

      // ---- 标题 ----
      Text(item.title || '未命名直播')
        .fontSize(14)
        .fontColor(this.isDarkMode ? Color.White : Color.Black)
        .maxLines(2)
        .lineHeight(20)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, left: 2, right: 2 })
        .width('100%')

      // ---- 主播信息行 ----
      Row() {
        if (item.ownerFace) {
          Image(item.ownerFace)
            .width(20).height(20)
            .borderRadius(10)
            .margin({ right: 5 })
            .backgroundColor(this.isDarkMode ? '#444444' : '#E0E0E0')
        }
        Text(item.ownerName || '未知主播')
          .fontSize(13)
          .fontColor(this.isDarkMode ? '#AAAAAA' : '#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (item.online > 0) {
          Text(this.formatShortCount(item.online) + '观看')
            .fontSize(11)
            .fontColor(this.isDarkMode ? '#888888' : '#999999')
            .flexShrink(0)
        }
      }
    }
    .backgroundColor(this.videoCardEdgeLight ? Color.Transparent : (this.cardCustomColor && this.cardCustomColor !== '#007DFF'
      ? (this.cardTransparentStyle
        ? '#' + this.opacityToHexAlpha(this.cardBgOpacity) + this.cardCustomColor.slice(1)
        : this.cardCustomColor)
      : cardItemBg(this.isDarkMode, this.cardTransparentStyle, this.cardBgOpacity, this.pageWallpaperEnabled)))
    .border({ width: !this.videoCardEdgeLight && this.cardTransparentStyle ? this.cardBorderWidth : 0,
      color: this.cardTransparentStyle
        ? (this.cardBorderFollowTheme
          ? ('#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1))
          : (this.isDarkMode ? `rgba(255,255,255,${this.cardBorderOpacity / 100})` : 'rgba(255,255,255,0.25)'))
        : Color.Transparent })
    .borderRadius(12)
    .clip(true)
    .padding(12)
    .shadow({ radius: 4, color: '#10000000', offsetY: 2 })
    .clickEffect({ level: 0, scale: 0.95 })
    .onClick(() => {
      if (item.id && item.id.startsWith('live_')) {
        const roomId = item.id.replace('live_', '');
        this.openLiveRoom(roomId, item.ownerName);
      }
    })

    }
  }

  // ────────── 用户搜索结果卡片 ──────────
  @Builder
  UserCard(item: RecommendItem) {
    PageSurface({ radius: 999 }) {

    Row() {
      // 头像（圆形）
      Image(item.ownerFace)
        .width(48).height(48)
        .borderRadius(24)
        .margin({ right: 12 })
        .objectFit(ImageFit.Cover)
        .backgroundColor(this.isDarkMode ? '#444444' : '#E0E0E0')

      Column() {
        // 用户名
        Text(item.ownerName)
          .fontSize(16)
          .fontColor(this.isDarkMode ? '#E0E0E0' : '#000000')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 签名
        if (item.title) {
          Text(item.title)
            .fontSize(12)
            .fontColor(this.isDarkMode ? '#888888' : '#999999')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }

        // 粉丝数 + 视频数
        Row() {
          if (item.playCount > 0) {
            Text(`${this.formatFansCount(item.playCount)} 粉丝`)
              .fontSize(11)
              .fontColor(this.isDarkMode ? '#666666' : '#AAAAAA')
          }
          if (item.danmakuCount > 0) {
            Text(`${item.danmakuCount} 视频`)
              .fontSize(11)
              .fontColor(this.isDarkMode ? '#666666' : '#AAAAAA')
              .margin({ left: 12 })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      FollowGlassButton({ followed: this.followedUserIds.indexOf(item.id) >= 0,
        buttonWidth: 76, buttonHeight: 32, accent: this.followedUserIds.indexOf(item.id) >= 0 ? '#FB7299' : '#545452',
        textColor: this.followedUserIds.indexOf(item.id) >= 0 ? '#FB7299' : '#545452', fill: Color.Transparent,
        onActivate: () => { this.triggerHaptic(); this.toggleFollowUser(item); }
      }).margin({ left: 8 }).flexShrink(0)
    }
    .width('100%')
    .padding(12)
    .borderRadius(999)
    .onClick(() => {
      this.triggerHaptic();
      const mid = parseInt(item.ownerMid, 10);
      if (mid && !isNaN(mid)) {
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/UpSpacePage',
          params: {
            mid: mid,
            upName: item.ownerName,
            upFace: item.ownerFace
          }
        });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: `用户: ${item.ownerName}` });
      }
    })

    }
  }

  private formatFansCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万';
    }
    return count.toString();
  }

  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  // ⭐ 真实关注/取关用户
  private toggleFollowUser(item: RecommendItem): void {
    const midStr = item.ownerMid;
    const mid = parseInt(midStr, 10);
    if (!mid || isNaN(mid)) {
      this.getUIContext().getPromptAction().showToast({ message: '无法获取用户ID' });
      return;
    }

    const isCurrentlyFollowed = this.followedUserIds.indexOf(item.id) >= 0;

    // 先乐观更新 UI
    if (isCurrentlyFollowed) {
      // 当前已关注 → 移除（变为未关注）
      this.followedUserIds = this.followedUserIds.filter(id => id !== item.id);
    } else {
      // 当前未关注 → 加入（变为已关注）
      this.followedUserIds = [...this.followedUserIds, item.id];
    }

    // 调用 API：act=1 关注, act=2 取关
    modifyFollow(mid, isCurrentlyFollowed ? 2 : 1).then((success: boolean) => {
      if (success) {
        this.getUIContext().getPromptAction().showToast({ message: isCurrentlyFollowed ? '取消关注' : '关注成功', duration: 1500 });
      } else {
        // 失败则回滚
        if (isCurrentlyFollowed) {
          this.followedUserIds = [...this.followedUserIds, item.id];
        } else {
          this.followedUserIds = this.followedUserIds.filter(id => id !== item.id);
        }
        this.getUIContext().getPromptAction().showToast({ message: '操作失败，请重试', duration: 1500 });
      }
    });
  }

  // 标记已关注的用户：先用搜索结果的 isFollowed（快速通道），再通过 getFollowStatus 逐个查询
  private async initFollowedUsers(): Promise<void> {
    logInfo(`[initFollowedUsers] 开始，结果数=${this.activeResults.length}`);
    // 第一遍：利用搜索 API 自带的 is_followed 字段（零开销）
    for (const item of this.activeResults) {
      if (item.ownerMid.length === 0) continue;
      if (item.isFollowed && this.followedUserIds.indexOf(item.id) < 0) {
        this.followedUserIds = [...this.followedUserIds, item.id];
      }
    }
    logInfo(`[initFollowedUsers] 第一遍完成，followedUserIds=${this.followedUserIds.length}`);
    // 第二遍：通过 x/web-interface/card 接口逐个查询
    for (const item of this.activeResults) {
      if (item.ownerMid.length === 0) continue;
      if (this.followedUserIds.indexOf(item.id) >= 0) continue; // 已标记则跳过
      try {
        const mid = parseInt(item.ownerMid, 10);
        if (!mid || isNaN(mid)) continue;
        const isFollowed = await getFollowStatus(mid);
        if (isFollowed && this.followedUserIds.indexOf(item.id) < 0) {
          this.followedUserIds = [...this.followedUserIds, item.id];
        }
      } catch (e) {
        logWarn(`[initFollowedUsers] 查询 mid=${item.ownerMid} 失败: ${e}`);
      }
    }
    logInfo(`[initFollowedUsers] 全部完成，共 ${this.followedUserIds.length} 个`);
  }

  // ────────── 根据类型导航 ──────────
  private navigateToDetail(item: RecommendItem, tabType: string): void {
    if (tabType === 'live_user' && item.id.startsWith('live_')) {
      const roomId = item.id.replace('live_', '');
      this.openLiveRoom(roomId, item.ownerName);
    } else {
      this.getUIContext().getPromptAction().showToast({ message: `${getSearchTypeLabel(tabType) || tabType}: ${item.title}` });
    }
  }

  private openLiveRoom(roomId: string, ownerName: string): void {
    logInfo(`[SearchPage] 进入直播间 roomId=${roomId}`);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/LivePlayerPage',
      params: { roomId: parseInt(roomId) }
    });
  }

  /** 从主播头像进入直播间 */
  private enterLiveRoom(id: string): void {
    if (id.startsWith('live_')) {
      const roomId = id.substring(5);
      this.openLiveRoom(roomId, '');
    }
  }

  // ────────── 工具函数 ──────────
  private formatNumber(num: number): string {
    if (num >= 100000000) return (num / 100000000).toFixed(1) + '亿';
    if (num >= 10000) return (num / 10000).toFixed(1) + '万';
    return num.toString();
  }

  private getPlayCountColor(count: number): string {
    if (count >= 10000000) return '#FF0000';
    if (count >= 3000000) return '#C2185B';
    if (count >= 1000000) return '#FF8C00';
    if (count >= 100000) return '#FFB800';
    if (count >= 50000) return '#4A90D9';
    return '#999999';
  }

  private formatTimeAgo(timestamp: number): string {
    if (!timestamp) return '';
    const now = Math.floor(Date.now() / 1000);
    const diff = now - timestamp;

    if (diff < 60) {
      return '刚刚';
    } else if (diff < 3600) {
      return `${Math.floor(diff / 60)}分钟前`;
    } else if (diff < 86400) {
      return `${Math.floor(diff / 3600)}小时前`;
    } else if (diff < 2592000) {
      return `${Math.floor(diff / 86400)}天前`;
    } else if (diff < 31536000) {
      return `${Math.floor(diff / 2592000)}个月前`;
    } else {
      return `${Math.floor(diff / 31536000)}年前`;
    }
  }
}
