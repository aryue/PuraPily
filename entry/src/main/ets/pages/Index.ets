import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { GlassMaterial } from '../utils/GlassMaterial';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageWallpaper } from '../components/PageWallpaper';
import { NativeHeaderGlass } from '../components/NativeHeaderGlass';
import { FloatingVideoTransition } from '../services/FloatingVideoTransition';
import { HOME_SEARCH_ROW_HEIGHT, HOME_CHANNEL_ROW_HEIGHT } from '../utils/HomeHeaderLayout';
import { common } from '@kit.AbilityKit';
import { window, uiMaterial } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';
import deviceInfo from '@ohos.deviceInfo';
import { drawing } from '@kit.ArkGraphics2D';
import { preferences } from '@kit.ArkData';
import { HomeChannelContainer, CHANNEL_TABS, ChannelTabDef, channelPagerIndex } from '../components/HomeChannelContainer';
import { FloatingBottomBar } from '../components/FloatingBottomBar';
import { DynamicsPage } from './DynamicsPage';
import { ProfilePage } from './ProfilePage';
import { initializeReferenceAppearance } from '../utils/ReferenceAppearance';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { logError } from '../utils/Logger';
import { tabIndicatorCenter } from '../utils/TabIndicatorGeometry';
import { WarmSurfaceHost } from '../services/WarmSurfaceHost';

@Entry
@Component({ freezeWhenInactive: true })
struct Index {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  private tabs: TabsController = new TabsController();
  @State private homeHeaderSearchWidth: number = 200;
  private lastExitBackTime: number = 0;
  private mainWindow: window.Window | null = null;
  private warmHostCtl: XComponentController = new XComponentController();
  private sizeListener: ((size: window.Size) => void) | null = null;
  private avoidListener: ((data: window.AvoidAreaOptions) => void) | null = null;
  @State @Watch('updateHomeActivity') private pageVisible: boolean = true;
  private darkHeaderMaterial: uiMaterial.Material | undefined = undefined;
  private lightHeaderMaterial: uiMaterial.Material | undefined = undefined;
  private darkMenuFilter: drawing.ColorFilter = drawing.ColorFilter.createBlendModeColorFilter(
    { alpha: 255, red: 216, green: 220, blue: 225 }, drawing.BlendMode.SRC_IN);
  private lightMenuFilter: drawing.ColorFilter = drawing.ColorFilter.createBlendModeColorFilter(
    { alpha: 255, red: 69, green: 74, blue: 80 }, drawing.BlendMode.SRC_IN);
  @State immersiveHeader: boolean = false;
  @State ready: boolean = false;
  @StorageLink('continuationMainTab') @Watch('updateHomeActivity') activeTab: number = 0;
  @StorageLink('floatingBottomBar') @Watch('updateSearchVisibility') floatingBottomBar: boolean = true;
  @StorageLink('homeBarsHidden') @Watch('updateSearchVisibility') bottomBarHidden: boolean = false;
  @StorageLink('homeSearchRowHeight') searchRowHeight: number = HOME_SEARCH_ROW_HEIGHT;
  @State titleContentHeight: number = HOME_SEARCH_ROW_HEIGHT + HOME_CHANNEL_ROW_HEIGHT;
  @State private headerMaterialWidth: number = 0;
  private searchAnimationGeneration: number = 0;
  private searchAnimationRunning: boolean = false;
  @StorageLink('userProfileFace') avatar: string = '';
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('homeChannelIndex') @Watch('onChannelChange') channel: number = 2;
  @StorageLink('homeChannelPosition') channelPosition: number = 2;
  @State homeTabCenters: number[] = [32, 88, 144, 200, 256, 312];
  @StorageLink('homeScrollOffset') homeScrollOffset: number = 0;

  async aboutToAppear(): Promise<void> {
    this.updateHomeActivity();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await initializeReferenceAppearance(context);
      this.initializeHeaderMaterial();
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      const cookie = AppStorage.get<string>('biliCookie') ?? '';
      const cachedFace = await pref.get('userProfileFace', '') as string;
      const cachedName = await pref.get('userProfileName', '') as string;
      const cachedMid = await pref.get('userProfileMid', 0) as number;
      const currentMid = Number(cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/)?.[1] ?? 0);
      if (cookie === (AppStorage.get<string>('biliCookie') ?? '')) {
        AppStorage.setOrCreate('userProfileName', cookie.includes('SESSDATA') && currentMid > 0 && cachedMid === currentMid ? cachedName : '');
        this.avatar = cookie.includes('SESSDATA') ? cachedFace : '';
      }
      this.mainWindow = await window.getLastWindow(context);
      const rect = this.mainWindow.getWindowProperties().windowRect;
      this.updateOrientation(rect.width, rect.height);
      this.sizeListener = (size: window.Size): void => this.updateOrientation(size.width, size.height);
      this.mainWindow.on('windowSizeChange', this.sizeListener);
      this.avoidListener = (_data: window.AvoidAreaOptions): void => {
        if (this.mainWindow) {
          this.statusBarHeight = StatusBarUtils.statusBarInset(this.mainWindow);
          const area = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          const bottom = this.getUIContext().px2vp(area.bottomRect.height);
          StatusBarUtils.updateNavigationInset(bottom);
        }
      };
      this.mainWindow.on('avoidAreaChange', this.avoidListener);
      StatusBarUtils.updateStatusBarColor(context, this.isDarkMode);
    } catch (error) {
      logError('[Index] initialize failed', error);
    }
    this.ready = true;
  }

  private initializeHeaderMaterial(): void {
    try {
      this.immersiveHeader = deviceInfo.apiAvailable('26.0.0') && hdsMaterial.getSystemMaterialTypes().length > 0;
      if (this.immersiveHeader) {
        this.darkHeaderMaterial = GlassMaterial.createWithStyle({
          style: uiMaterial.ImmersiveStyle.THIN, interactive: true,
          light: { color: undefined }, tint: '#18000000', shadow: false
        });
        this.lightHeaderMaterial = GlassMaterial.createWithStyle({
          style: uiMaterial.ImmersiveStyle.THIN, interactive: true,
          light: { color: undefined }, tint: '#18FFFFFF', shadow: false
        });
      }
    } catch (error) {
      this.immersiveHeader = false;
      logError('[Index] header material unavailable', error);
    }
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    if (this.mainWindow && this.sizeListener) {
      this.mainWindow.off('windowSizeChange', this.sizeListener);
    }
    if (this.mainWindow && this.avoidListener) this.mainWindow.off('avoidAreaChange', this.avoidListener);
  }

  private updateOrientation(width: number, height: number): void {
    AppStorage.setOrCreate('isLandscape', width > height);
    if (this.mainWindow) {
      const bottom = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.statusBarHeight = StatusBarUtils.statusBarInset(this.mainWindow);
      const inset = this.getUIContext().px2vp(bottom.bottomRect.height);
      StatusBarUtils.updateNavigationInset(inset);
      if (this.pageVisible) this.restoreSystemBars();
    }
  }

  onChannelChange(): void {
    this.homeScrollOffset = 0;
  }

  private updateHomeActivity(): void {
    AppStorage.setOrCreate('homeFeedActive', this.pageVisible && this.activeTab === 0);
    this.updateSearchVisibility();
  }

  private updateSearchVisibility(): void {
    const hidden = this.floatingBottomBar && this.activeTab === 0 && this.bottomBarHidden;
    const height = hidden ? 0 : HOME_SEARCH_ROW_HEIGHT;
    if (this.searchRowHeight === height) {
      if (!this.searchAnimationRunning) this.titleContentHeight = height + HOME_CHANNEL_ROW_HEIGHT;
      return;
    }
    const generation = ++this.searchAnimationGeneration;
    this.searchAnimationRunning = true;
    // Keep the native title large enough for the exiting surface until it has slid out.
    // On entry restore that scope first, then animate the visible glass and content.
    if (!hidden) this.titleContentHeight = HOME_SEARCH_ROW_HEIGHT + HOME_CHANNEL_ROW_HEIGHT;
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      duration: 280, curve: Curve.FastOutSlowIn,
      onFinish: (): void => {
        if (generation !== this.searchAnimationGeneration) return;
        this.searchAnimationRunning = false;
        this.titleContentHeight = height + HOME_CHANNEL_ROW_HEIGHT;
      }
    }, () => {
      this.searchRowHeight = height;
    });
  }

  onPageShow(): void {
    this.lastExitBackTime = 0;
    this.pageVisible = true;
    this.updateHomeActivity();
    this.restoreSystemBars();
    if (AppStorage.get<boolean>('goHome')) {
      AppStorage.set('goHome', false);
      this.activeTab = 0;
      this.tabs.changeIndex(0);
    }
  }

  onPageHide(): void {
    AppStorage.setOrCreate('nativeCardLightActive', false);
    this.lastExitBackTime = 0;
    this.pageVisible = false;
    // Frozen child components may defer @Watch delivery; stop list prefetch synchronously.
    this.updateHomeActivity();
  }

  private restoreSystemBars(): void {
    if (!this.mainWindow) return;
    StatusBarUtils.setSystemBars(this.mainWindow,
      !(AppStorage.get<boolean>('hideStatusBar') ?? false), true);
  }

  onBackPress(): boolean {
    const now = Date.now();
    if (this.lastExitBackTime > 0 && now >= this.lastExitBackTime && now - this.lastExitBackTime < 2000) {
      this.lastExitBackTime = 0;
      return false;
    }
    this.lastExitBackTime = now;
    this.getUIContext().getPromptAction().showToast({ message: '再按一次返回退出应用', duration: 2000 });
    return true;
  }

  private selectTab(index: number): void {
    this.lastExitBackTime = 0;
    if (index === this.activeTab) {
      if (index === 0 || index === 1) {
        const offset = index === 0 ? this.homeScrollOffset : (AppStorage.get<number>('dynScrollOffset') ?? 0);
        if (Math.abs(offset) > 5) {
          AppStorage.setOrCreate('scrollToTopFlag', Date.now());
        } else {
          const key = index === 0 ? 'refreshHomeFlag' : 'refreshDynamicsFlag';
          AppStorage.setOrCreate(key, (AppStorage.get<number>(key) ?? 0) + 1);
        }
      }
      return;
    }
    this.tabs.changeIndex(index);
    this.activeTab = index;
  }

  private navigate(page: string): void {
    this.getUIContext().getRouter().pushUrl({ url: page }).catch((error: Error) => {
      logError('[Index] navigation failed', error);
    });
  }

  @Builder
  HomeSearchRow() {
    Row({ space: 12 }) {
      Column() {
        HeaderGlassControl({ label: '个人主页', controlId: 'home-header-profile', onActivate: () => this.selectTab(2) }) {
          if (this.avatar) {
            Image(this.avatar).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover)
              .hitTestBehavior(HitTestMode.None)
          } else {
            Image($r('app.media.ref_profile')).width(26).height(26)
              .fillColor(this.isDarkMode ? '#A2A7AE' : '#757A81').hitTestBehavior(HitTestMode.None)
          }
        }
      }.width(40).height(40)
      Row() {
        HeaderGlassControl({ controlWidth: this.homeHeaderSearchWidth, label: '搜索视频、UP主',
          controlId: 'home-header-search', onActivate: () => this.navigate('pages/SearchPage') }) {
          Row({ space: 8 }) {
            Image($r('app.media.ref_search')).width(20).height(20)
              .fillColor(this.isDarkMode ? '#E7E9EB' : '#454A50')
            Text('搜索视频、UP主').fontSize(14)
              .fontColor(this.isDarkMode ? '#CFD3D8' : '#61666D').maxLines(1)
          }.width('100%').padding({ left: 14, right: 14 }).hitTestBehavior(HitTestMode.None)
        }
      }.layoutWeight(1).height(40)
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width);
          if (width > 0 && Math.abs(width - this.homeHeaderSearchWidth) > 0.5) this.homeHeaderSearchWidth = width;
        })
      Column() {
        HeaderGlassControl({ label: '消息中心', controlId: 'home-header-message',
          onActivate: () => this.navigate('pages/MessagesPage') }) {
          Image($r('app.media.ref_message')).width(23).height(23)
            .fillColor(this.isDarkMode ? '#E7E9EB' : '#454A50').hitTestBehavior(HitTestMode.None)
        }
      }.width(40).height(40)
    }.width('100%').height(HOME_SEARCH_ROW_HEIGHT).padding({ left: 14, right: 14 })
  }

  @Builder
  HomeChannelTitle(item: ChannelTabDef) {
    Column() {
      Text(item.name).fontSize(16).maxLines(1).flexShrink(0)
        .fontWeight(Math.round(this.channelPosition) === channelPagerIndex(item.index) + 1 ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(Math.round(this.channelPosition) === channelPagerIndex(item.index) + 1 ? '#FB7299' : (this.isDarkMode ? '#A2A7AE' : '#757A81'))
    }.layoutWeight(1)
      .height(HOME_CHANNEL_ROW_HEIGHT).justifyContent(FlexAlign.End).padding({ bottom: 8 })
      .onAreaChange((_oldArea: Area, area: Area) => {
        const center = Number(area.position.x) + Number(area.width) / 2;
        if (Math.abs(this.homeTabCenters[channelPagerIndex(item.index)] - center) < 0.1) return;
        const centers = [...this.homeTabCenters];
        centers[channelPagerIndex(item.index)] = center;
        this.homeTabCenters = centers;
      })
      .onClick(() => { this.channel = item.index; })
  }

  @Builder
  HomeChannelTabs() {
    Row() {
      Scroll() {
        Stack({ alignContent: Alignment.BottomStart }) {
          Row() {
            ForEach(CHANNEL_TABS, (item: ChannelTabDef) => {
              this.HomeChannelTitle(item)
            }, (item: ChannelTabDef) => item.index.toString())
          }.width('100%').padding({ left: 8, right: 8 })
          Row().width(16).height(3).borderRadius(2)
            .backgroundColor('#FB7299')
            .translate({ x: tabIndicatorCenter(this.homeTabCenters, this.channelPosition - 1) - 8, y: -3 })
            .hitTestBehavior(HitTestMode.None)
        }.width('100%').height(HOME_CHANNEL_ROW_HEIGHT)
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
    }.width('100%').height(HOME_CHANNEL_ROW_HEIGHT)
  }

  @Builder
  HomeTitle() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        // Keep the native title scope fixed; glass and controls inherit one translation.
        NativeHeaderGlass({ surfaceWidth: this.headerMaterialWidth,
          materialStyle: uiMaterial.ImmersiveStyle.REGULAR,
          surfaceHeight: this.headerTopInset() + HOME_SEARCH_ROW_HEIGHT + HOME_CHANNEL_ROW_HEIGHT,
          scopeId: 'home-header-native-scope' })
        Stack({ alignContent: Alignment.TopStart }) {
          Column() { this.HomeSearchRow() }
            .width('100%').height(HOME_SEARCH_ROW_HEIGHT)
            .translate({ y: this.searchRowHeight - HOME_SEARCH_ROW_HEIGHT })
        }
        // Keep the top slide mask, with space below the row for capsule shadows.
        // Keep 32vp below the row so the capsule shadow blends into the tabs.
        .width('100%').height(80).clip(true)
        .position({ x: 0, y: this.headerTopInset() })
        // Keep the mask below the status bar while the shared group slides upward.
        .translate({ y: HOME_SEARCH_ROW_HEIGHT - this.searchRowHeight })
        .hitTestBehavior(this.searchRowHeight === 0 ? HitTestMode.None : HitTestMode.Default)
        .accessibilityLevel(this.searchRowHeight === 0 ? 'no-hide-descendants' : 'auto')
        Row() { this.HomeChannelTabs() }
          .width('100%').height(HOME_CHANNEL_ROW_HEIGHT)
          .position({ x: 0, y: this.headerTopInset() + HOME_SEARCH_ROW_HEIGHT })
          .id('home-channel-strip')
      }
      .width('100%').height(this.headerTopInset() + HOME_SEARCH_ROW_HEIGHT + HOME_CHANNEL_ROW_HEIGHT)
      .translate({ y: this.searchRowHeight - HOME_SEARCH_ROW_HEIGHT })
      .clip(true)
      .id('home-title-moving-group')
    }
    .width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.Transparent)
      .id('home-title-viewport')
      .onSizeChange((_previous: SizeOptions, size: SizeOptions) => {
        const width = Number(size.width);
        if (width > 0 && Math.abs(width - this.headerMaterialWidth) > 0.5) this.headerMaterialWidth = width;
      })
  }

  private headerTopInset(): number {
    // Keep interactive controls below the full system camera/status safe area.
    return Math.max(0, this.statusBarHeight);
  }

  @Builder
  NavItem(label: string, icon: Resource, selectedIcon: Resource, index: number) {
    Column({ space: 4 }) {
      Image(this.activeTab === index ? selectedIcon : icon).width(25).height(25)
        .fillColor(this.activeTab === index ? '#FB7299' : '#757A81')
      Text(label).fontSize(11).fontColor(this.activeTab === index ? '#FB7299' : '#757A81')
    }
    .layoutWeight(1).height(54).justifyContent(FlexAlign.Center)
    .onClick(() => this.selectTab(index))
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
      // 全局预热 surface 宿主：1x1 隐藏，随首页常驻；只给预热播放器做 prepare 的落点。
      XComponent({ id: 'warm_host_xc', type: XComponentType.SURFACE, controller: this.warmHostCtl })
        .onLoad(() => { WarmSurfaceHost.set(this.warmHostCtl.getXComponentSurfaceId()); })
        .width(2)
        .height(2)
        .opacity(0.01)
        .hitTestBehavior(HitTestMode.None)
        .position({ x: 0, y: 0 })
    Stack() {
      if (this.ready) {
        Navigation() {
          Column() {
            Stack({ alignContent: Alignment.Top }) {
              Tabs({ controller: this.tabs, index: this.activeTab }) {
                TabContent() { HomeChannelContainer() }
                TabContent() { DynamicsPage() }
                TabContent() { ProfilePage() }
              }
              .barHeight(0).scrollable(false).animationDuration(150)
              .onChange((index: number) => { this.activeTab = index; })
              .width('100%').height('100%')
            }.width('100%').layoutWeight(1).clip(true)
            if (!this.floatingBottomBar) {
              Row() {
                this.NavItem('首页', $r('app.media.ref_home'), $r('app.media.ref_home_selected'), 0)
                this.NavItem('动态', $r('app.media.ref_dynamic'), $r('app.media.ref_dynamic_selected'), 1)
                this.NavItem('我的', $r('app.media.ref_profile'), $r('app.media.ref_profile_selected'), 2)
              }
              .width('100%').padding({ bottom: this.navIndicatorHeight })
              .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
              .border({ width: { top: 0.5 }, color: this.isDarkMode ? '#242628' : '#E3E5E7' })
            }
          }.width('100%').height('100%')
        }
        .backgroundColor(Color.Transparent)
        .titleMode(NavigationTitleMode.Mini).hideBackButton(true).mode(NavigationMode.Stack)
        .hideTitleBar(this.activeTab !== 0)
        .title({ builder: (): void => { this.HomeTitle(); }, height: this.headerTopInset() + this.titleContentHeight }, {
          barStyle: BarStyle.STACK,
          backgroundColor: Color.Transparent
        })
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
        .width('100%').height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        if (this.floatingBottomBar) {
          Stack({ alignContent: Alignment.Bottom }) {
            FloatingBottomBar({
              activeIndex: this.activeTab,
              pageActive: this.pageVisible,
              hidden: this.activeTab === 0 && this.bottomBarHidden,
              onSelect: (index: number) => this.selectTab(index)
            })
          }.width('100%').height('100%').hitTestBehavior(HitTestMode.Transparent).zIndex(10)
        }

      } else {
        LoadingProgress().width(28).height(28).color('#D34E7E')
      }
    }
    .width('100%').height('100%').backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
