import { FavoritesDataService } from '../services/FavoritesDataService';
import { extractMidFromCookie } from '../api/FeedbackService';
import { pageBackgroundColor, secondaryTextColor, tertiaryTextColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageSurface } from '../components/PageSurface';
import { NativeGlassCapsule } from '../components/NativeGlassCapsule';
import { PageWallpaperService, clampWallpaperOpacity, clampWallpaperScrim } from '../services/PageWallpaperService';
// ProfilePage.ets - 个人中心与当前设置页。
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { applyThemeMode } from '../utils/ReferenceAppearance';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { preferences } from '@kit.ArkData';
import { window, LengthMetrics } from '@kit.ArkUI';
import { GlassMaterial } from '../utils/GlassMaterial';
import { getUserInfo } from '../api/BilibiliApi';
import { logoutSession } from '../services/LoginSession';
import { getLoginAccessKey } from '../utils/CredentialStore';
import { HighRefreshService } from '../services/HighRefreshService';
import { AppScaleService, FONT_SCALE_MIN, FONT_SCALE_MAX, FONT_SCALE_STEP, FONT_SCALE_DEFAULT } from '../services/AppScaleService';
import { QualityPreferenceService, QualityBucket } from '../services/QualityPreferenceService';
import {
  QUALITY_OPTIONS, QualityOption, DEFAULT_QUALITY_QN, DEFAULT_CELLULAR_QUALITY_QN, qualityLabel
} from '../utils/QualityCatalog';

const ROTATION_OPTIONS: string[] = ['跟随系统', '自动旋转', '锁定竖屏', '锁定横屏'];
/** 字号拖动预览的最小下发间隔：setFontSizeScale 会重排整页，太密会明显掉帧。 */
const FONT_PREVIEW_INTERVAL_MS: number = 80;

@Component({ freezeWhenInactive: true })
export struct ProfilePage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('pageWallpaperSource') pageWallpaperSource: string = 'none';
  @StorageLink('pageWallpaperBusy') pageWallpaperBusy: boolean = false;
  @StorageLink('pageWallpaperOpacity') pageWallpaperOpacity: number = 0.7;
  @StorageLink('pageWallpaperScrim') pageWallpaperScrim: number = 0;
  /** 壁纸滑条草稿（百分比）：拖动中即时生效（只改 AppStorage），松手才落盘。 */
  @State wallpaperOpacityDraft: number = 70;
  @State wallpaperScrimDraft: number = 0;
  @StorageLink('isLandscape') wallpaperLandscape: boolean = false;
  @StorageLink('playbackKernel') playbackKernel: string = 'system';
  @State cacheSizeText: string = '计算中…';
  @Prop settingsOnly: boolean = false;
  /** 设置页层级：root=一级入口卡，appearance=外观与交互，playback=播放设置。 */
  @Prop settingsSection: string = 'root';
  @StorageLink('highRefreshRate') highRefreshRate: number = 0;
  @StorageLink('highRefreshSupportedRates') highRefreshSupportedRates: number[] = [];
  @StorageLink('highRefreshAvailable') highRefreshAvailable: boolean = true;
  /** 字体大小：system=跟随系统 / custom=按滑条倍率（appFontScale 为已生效倍率）。 */
  @StorageLink('fontSizeMode') fontSizeMode: string = 'system';
  @StorageLink('appFontScale') appFontScale: number = 1;
  /** 滑条拖动中的草稿值：立即反映到行右侧百分比，同时作为实时下发的目标值。 */
  @State fontScaleDraft: number = FONT_SCALE_DEFAULT;
  /** 拖动预览的节流时间戳（ms）。 */
  private lastFontPreviewAt: number = 0;
  @StorageLink('videoCardGlassThickness') videoCardGlassThickness: string = 'thin';
  @StorageLink('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @StorageLink('videoCardGlassTint') videoCardGlassTint: boolean = true;
  @StorageLink('videoCardGlassInvert') videoCardGlassInvert: boolean = false;
  @StorageLink('otherCardGlassEnabled') otherCardGlassEnabled: boolean = true;
  @StorageLink('otherCardGlassTint') otherCardGlassTint: boolean = true;
  @StorageLink('otherCardGlassInvert') otherCardGlassInvert: boolean = false;
  @StorageLink('otherCardGlassThickness') otherCardGlassThickness: string = 'thick';
  @StorageLink('hideNavigationIndicator') hideNavigationIndicator: boolean = false;
  @StorageLink('floatingBottomBar') floatingBottomBar: boolean = true;
  @StorageLink('bottomBarSmartGrip') bottomBarSmartGrip: boolean = false;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  /** 启动静默更新检查结果（UpdateChecker 写入），关于入口红点。 */
  @StorageLink('hasNewVersion') hasNewVersion: boolean = false;
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('bgp') referenceBackgroundPlay: boolean = false;
  @StorageLink('cellularPrefetch') cellularPrefetch: boolean = false;
  @StorageLink('vibrateEnabled') referenceVibrate: boolean = true;
  @StorageLink('landscapePlaybackSide') landscapePlaybackSide: string = 'left';
  @StorageLink('screenOrientationLock') screenOrientationLock: string = '跟随系统';
  /** 画质偏好分两档：Wi-Fi（含以太网/不计费）与移动网络（蜂窝、计费 Wi-Fi、手机热点）。 */
  @StorageLink('videoQnWifi') videoQnWifi: number = DEFAULT_QUALITY_QN;
  @StorageLink('videoQnCellular') videoQnCellular: number = DEFAULT_CELLULAR_QUALITY_QN;
  /** 当前链路类别/计费判定，由 QualityPreferenceService 每次换网后写回。 */
  @StorageLink('networkClass') networkClass: string = 'unknown';
  @StorageLink('networkMetered') networkMetered: boolean = true;
  @StorageLink('recommendApiSource') recommendApiSource: string = 'App';
  @StorageLink('danmakuApiSource') danmakuApiSource: string = 'grpc';
  @StorageProp('refreshHomeFlag') @Watch('onLoginStateChanged') refreshHomeFlag: number = 0;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @State isLoggedIn: boolean = (AppStorage.get<string>('biliCookie') ?? '').includes('SESSDATA');
  @State hasClientCredential: boolean = false;
  @StorageLink('biliTvAuthorizationStatus') tvAuthorizationStatus: string = 'idle';
  @State userDisplayName: string = AppStorage.get<string>('userProfileName') || '已登录用户';
  @StorageLink('userProfileFace') userAvatarUrl: string = '';
  @State userMid: number = Number(extractMidFromCookie(AppStorage.get<string>('biliCookie') ?? ''));
  private dataPreferences: preferences.Preferences | null = null;

  async aboutToAppear(): Promise<void> {
    if (!this.settingsOnly) FavoritesDataService.getInstance().warm(Number(extractMidFromCookie(AppStorage.get<string>('biliCookie') ?? '')));
    HighRefreshService.getInstance().supportedRates();
    this.dataPreferences = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, 'my_app_settings');
    this.recommendApiSource = await this.dataPreferences.get('recommendApiSource', 'App') as string;
    this.danmakuApiSource = await this.dataPreferences.get('danmakuApiSource', 'grpc') as string;
    const side = await this.dataPreferences.get('landscapePlaybackSide', 'left');
    this.landscapePlaybackSide = side === 'right' ? 'right' : 'left';
    // 系统字号可能在应用进后台期间被改过，进设置页时先对齐（只有原生跟随态才读得回系统值）
    AppScaleService.refreshSystemScale(this.getUIContext().getHostContext() as common.UIAbilityContext);
    const fontSetting = await AppScaleService.loadFontSetting(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.fontSizeMode = fontSetting.followSystem ? 'system' : 'custom';
    this.appFontScale = fontSetting.scale;
    // 滑条草稿与「当前真实生效的字号」对齐：跟随系统时是系统倍率，不是上次自定义值
    this.fontScaleDraft = AppScaleService.entryCustomScale(fontSetting.followSystem, fontSetting.scale);
    // 壁纸两条滑条的草稿对齐已生效值（服务写入 AppStorage 前已夹过区间）
    this.wallpaperOpacityDraft = Math.round(clampWallpaperOpacity(this.pageWallpaperOpacity) * 100);
    this.wallpaperScrimDraft = clampWallpaperScrim(this.pageWallpaperScrim);
    // 进设置页时重算一次「当前链路 → 生效画质」：后台期间换过网、事件没送到时靠这一次兜底，
    // 顺带刷新「当前网络」那一行的判定文案。
    QualityPreferenceService.getInstance().refresh('settings-page');
    if (this.settingsOnly && this.settingsSection === 'root') await this.calcCacheSize();
    await this.restoreCachedProfile();
    this.onLoginStateChanged();
  }

  private async selectPlaybackKernel(kernel: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const settings = await preferences.getPreferences(context, 'my_app_settings');
      await settings.put('playbackKernel', kernel);
      await settings.flush();
      this.playbackKernel = kernel;
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '保存播放内核失败，请重试' });
    }
  }

  /** 格式化字节数 */
  private formatSize(bytes: number): string {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1048576).toFixed(1) + ' MB';
  }

  /** 递归计算目录大小 */
  private getDirSize(dirPath: string): number {
    let total = 0;
    try {
      const names: string[] = fileIo.listFileSync(dirPath);
      for (const name of names) {
        const fullPath: string = dirPath + '/' + name;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isDirectory()) {
            total += this.getDirSize(fullPath);
          } else {
            total += stat.size;
          }
        } catch (_) {}
      }
    } catch (_) {}
    return total;
  }

  /** 计算缓存总大小 */
  private async calcCacheSize(): Promise<void> {
    try {
      const context: common.Context = this.getUIContext().getHostContext() as common.Context;
      let total = 0;
      total += this.getDirSize(context.cacheDir);
      this.cacheSizeText = this.formatSize(total);
    } catch (_) {
      this.cacheSizeText = '获取失败';
    }
  }

  /** 递归清空目录 */
  private clearDir(dirPath: string): void {
    try {
      const names: string[] = fileIo.listFileSync(dirPath);
      for (const name of names) {
        const fullPath: string = dirPath + '/' + name;
        try {
          const stat = fileIo.statSync(fullPath);
          if (stat.isDirectory()) {
            this.clearDir(fullPath);
            fileIo.rmdirSync(fullPath);
          } else {
            fileIo.unlinkSync(fullPath);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /** 清除缓存 */
  private async clearCache(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '清除缓存',
      message: '确定要清除缓存数据吗？\n（仅清除临时缓存）',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确定', color: '#007DFF' }
      ]
    });
    if (result.index === 1) {
      try {
        const context: common.Context = this.getUIContext().getHostContext() as common.Context;
        this.clearDir(context.cacheDir);
        await this.calcCacheSize();
        this.getUIContext().getPromptAction().showToast({ message: '缓存已清除' });
      } catch (_) {
        this.getUIContext().getPromptAction().showToast({ message: '清除失败' });
      }
    }
  }



  private wallpaperLabel(): string {
    if (this.pageWallpaperSource === 'pipw') return 'Pipw 二次元';
    if (this.pageWallpaperSource === 'picsum') return 'Lorem Picsum 摄影';
    if (this.pageWallpaperSource === 'local') return '本地图片';
    return '关闭';
  }
  private async applyPageWallpaper(source: string, refresh: boolean = false, local: string = ''): Promise<void> {
    const service = PageWallpaperService.getInstance();
    try {
      await service.open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      await service.select(source, !this.wallpaperLandscape, refresh, local);
    } catch (error) {
      logError('壁纸设置失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '壁纸加载失败，请重试；已保留原壁纸' });
    }
  }

  private glassThicknessLabel(otherCards: boolean = false): string {
    const value = otherCards ? this.otherCardGlassThickness : this.videoCardGlassThickness;
    return value === 'ultra-thin' ? '超薄' : value === 'regular' ? '常规' : value === 'thick' ? '厚' : value === 'ultra-thick' ? '超厚' : '薄';
  }

  private async saveThemeMode(mode: string): Promise<void> {
    if (!['system', 'light', 'dark'].includes(mode)) return;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('themeMode', mode);
      await pref.flush();
      const dark = applyThemeMode(context, mode);
      await StatusBarUtils.updateStatusBarColor(context, dark);
    } catch (error) {
      logError('保存主题失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  private async onDarkModeChange(isOn: boolean): Promise<void> {
    await this.saveThemeMode(isOn ? 'dark' : 'light');
  }

  /** 画质偏好按链路分档落盘；当前链路正好是这一档时立刻生效（写 AppStorage）。 */
  private saveQuality(bucket: QualityBucket, qn: number): void {
    try {
      QualityPreferenceService.getInstance().setQn(bucket, qn);
    } catch (error) {
      logError('保存画质偏好失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  /** 「当前网络」行右侧：链路类别（Wi-Fi / 移动热点 / 移动网络 / 以太网）。 */
  private networkClassText(): string {
    return QualityPreferenceService.classLabel(this.networkClass);
  }

  /** 「当前网络」行副标题：这条链路按哪一档取流。 */
  private networkDetailText(): string {
    return QualityPreferenceService.networkDetail(this.networkClass, this.networkMetered);
  }

  private async saveApiSource(key: string, source: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put(key, source);
      await pref.flush();
      AppStorage.setOrCreate(key, source);
      this.getUIContext().getPromptAction().showToast({ message: '已保存，下次加载时生效' });
    } catch (error) {
      logError('保存数据源失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  private async onLoginStateChanged(): Promise<void> {
    const cookie = AppStorage.get<string>('biliCookie') ?? '';
    const loggedIn = cookie.includes('SESSDATA');
    logInfo(`[ProfilePage] refreshHomeFlag=${this.refreshHomeFlag}, Cookie长度=${cookie.length}, 有SESSDATA=${loggedIn}`);
    this.isLoggedIn = loggedIn;
    this.hasClientCredential = !!AppStorage.get<string>('biliAccessKey');

    if (loggedIn) {
      try {
        const accessKey = await getLoginAccessKey(cookie);
        if (cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
        this.hasClientCredential = !!accessKey;
      } catch (error) { logWarn('客户端登录凭据暂不可读取'); }
      // 调用API获取用户信息
      const userInfo = await getUserInfo();
      if (cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      if (userInfo && userInfo.isLogin) {
        this.userDisplayName = userInfo.uname;
        AppStorage.setOrCreate('userProfileName', userInfo.uname);
        this.userAvatarUrl = userInfo.face;
        this.userMid = userInfo.mid;
        if (!this.settingsOnly) FavoritesDataService.getInstance().warm(userInfo.mid);
        // ⭐ 缓存成功获取的资料：冷启动先显示缓存再后台刷新
        this.persistCachedProfile(userInfo.uname, userInfo.face, userInfo.mid);
        logInfo(`[ProfilePage] 获取用户信息成功: ${userInfo.uname}`);
      } else {
        // API失败时使用备用方案：缓存优先（头像/名称立即可用），无缓存才退回 cookie DedeUserID
        let cachedName: string = '';
        let cachedFace: string = '';
        if (this.dataPreferences) {
          try {
            cachedName = await this.dataPreferences.get('userProfileName', '') as string;
            cachedFace = await this.dataPreferences.get('userProfileFace', '') as string;
          } catch (_e) { /* 读取失败不阻断 */ }
        }
        const match = cookie.match(/DedeUserID=(\d+)/);
        if (cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
        this.userDisplayName = cachedName || (match ? `B站用户: ${match[1]}` : '已登录用户');
        this.userAvatarUrl = cachedFace;
        this.userMid = match ? parseInt(match[1], 10) : 0;
      }
    } else {
      this.userDisplayName = '未登录用户';
      AppStorage.setOrCreate('userProfileName', '');
      this.userAvatarUrl = '';
      this.userMid = 0;
      // ⭐ 登出：清缓存，避免下次冷启动闪现旧资料
      this.clearCachedProfile();
    }
  }

  private async restoreCachedProfile(): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      const cookie = AppStorage.get<string>('biliCookie') ?? '';
      if (!cookie.includes('SESSDATA')) return; // 未登录无缓存可显（登出时已清）
      const name = await this.dataPreferences.get('userProfileName', '') as string;
      const face = await this.dataPreferences.get('userProfileFace', '') as string;
      const mid = await this.dataPreferences.get('userProfileMid', 0) as number;
      if (cookie !== (AppStorage.get<string>('biliCookie') ?? '')) return;
      if (name || face) {
        this.isLoggedIn = true;
        if (name) this.userDisplayName = name;
        if (face) this.userAvatarUrl = face;
        if (mid) this.userMid = mid;
      }
    } catch (_e) { /* 读取失败不阻断 */ }
  }

  private async persistCachedProfile(name: string, face: string, mid: number): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.put('userProfileName', name);
      await this.dataPreferences.put('userProfileFace', face);
      await this.dataPreferences.put('userProfileMid', mid);
      await this.dataPreferences.flush();
    } catch (_e) { /* 写入失败不阻断 */ }
  }

  private async clearCachedProfile(): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.delete('userProfileName');
      await this.dataPreferences.delete('userProfileFace');
      await this.dataPreferences.delete('userProfileMid');
      await this.dataPreferences.flush();
    } catch (_e) { /* 清除失败不阻断 */ }
  }

  private goToWatchHistory(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/WatchHistoryPage' }).catch((err: Error) => {
      logError('跳转观看历史失败', err);
    });
  }

  private goToLogin(tvMode: boolean = false): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage', params: { tvMode: tvMode } }).catch((err: Error) => {
      logError('跳转扫码登录页失败', err);
      this.getUIContext().getPromptAction().showToast({ message: '登录功能暂不可用' });
    });
  }

  private async doLogout(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await logoutSession(context);
      await this.clearCachedProfile();
    } catch (err) {
      logError('清除登录会话失败');
      this.getUIContext().getPromptAction().showToast({ message: '清理登录信息失败，请重试' });
      return;
    }
    const flag = AppStorage.get<number>('refreshHomeFlag') ?? 0;
    AppStorage.set('refreshHomeFlag', flag + 1);
    this.getUIContext().getPromptAction().showToast({ message: '已退出B站登录' });
  }

  private goToFavorites(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/FavoritesPage' }).catch((err: Error) => {
      logError('跳转收藏页面失败', err);
      this.getUIContext().getPromptAction().showToast({ message: '收藏页面暂不可用' });
    });
  }

  private goToOfflineCache(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/OfflineCachePage' }).catch((err: Error) => {
      logError('跳转离线缓存页面失败', err);
      this.getUIContext().getPromptAction().showToast({ message: '离线缓存页面暂不可用' });
    });
  }

  private showLogoutConfirm(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认退出登录',
      message: '退出后将无法使用个性化推荐功能',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '确认退出', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.doLogout();
      }
    }).catch((err: Error) => {
      logError('显示对话框失败', err);
    });
  }

  private goToAbout(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/AboutPage' }).catch((err: Error) => {
      logError('跳转关于页面失败', err);
    });
  }

  private goToLevelBarLab(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/LevelBarLab' }).catch((err: Error) => {
      logError('打开音量与亮度测试失败', err);
    });
  }

  private openProfile(): void {
    if (!this.isLoggedIn) { this.goToLogin(); return; }
    this.getUIContext().getRouter().pushUrl({ url: 'pages/UpSpacePage', params: {
      mid: this.userMid, upName: this.userDisplayName, upFace: this.userAvatarUrl
    } }).catch((error: Error) => { logError('打开空间失败', error); });
  }

  @Builder
  QuickEntry(icon: Resource, label: string, action: () => void) {
    Column({ space: 10 }) {
      Image(icon).width(28).height(28)
        .fillColor(label === '历史记录' ? (this.isDarkMode ? '#76C8FA' : '#237CBD')
          : label === '我的收藏' ? (this.isDarkMode ? '#FFCD70' : '#BD780E') : (this.isDarkMode ? '#78D8BE' : '#18846A'))
      Text(label).fontSize(13).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
    }.layoutWeight(1).height(90).justifyContent(FlexAlign.Center).onClick(action)
  }

  private profileIconColor(): string {
    return this.isDarkMode ? '#D0D4DA' : '#454B54';
  }

  @Builder
  MenuRow(icon: Resource, label: string, action: () => void) {
    Row({ space: 14 }) {
      Image(icon).width(22).height(22).fillColor(this.profileIconColor())
      Text(label).fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
      Image($r('app.media.ref_chevron_right')).width(16).height(16).fillColor(this.profileIconColor())
    }.width('100%').height(56).padding({ left: 16, right: 16 }).onClick(action)
  }

  // 设置页「其它」分组使用：无前置图标，右侧沿用设置页统一的「›」文字箭头
  @Builder
  MenuRowPlain(label: string, action: () => void, showUpdateDot: boolean) {
    Row({ space: 14 }) {
      Text(label).fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
      if (showUpdateDot) {
        Circle({ width: 8, height: 8 }).fill('#E64545')
      }
      Text('›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
    }.width('100%').height(56).padding({ left: 16, right: 16 }).onClick(action)
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' })
      .catch((error: Error) => { logError('打开设置失败', error); });
  }

  /** 设置页二级分区：外观与交互 / 播放设置，共用同一个分区页。 */
  private openSettingsSection(section: string): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsSectionPage', params: { section: section } })
      .catch((error: Error) => { logError('打开设置分区失败', error); });
  }

  @Builder
  SectionTitle(title: string) {
    Text(title).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(this.isDarkMode ? '#C9CDD3' : '#606773').width('100%')
      .padding({ left: 8, top: this.settingsOnly ? 0 : 8, bottom: this.settingsOnly ? 0 : 10 })
  }

  @Builder
  ReferenceProfile() {
    Stack({ alignContent: Alignment.TopStart }) {

      Scroll() {
        Column({ space: 16 }) {
          PageSurface() {
            Row({ space: 16 }) {
              if (this.userAvatarUrl) {
                Image(this.userAvatarUrl).width(72).height(72).borderRadius(36).objectFit(ImageFit.Cover)
              } else {
                Image($r('app.media.ref_profile')).width(72).height(72).padding(16).borderRadius(36)
                  .backgroundColor(this.isDarkMode ? '#35303A' : '#FCEAF0').fillColor('#D34E7E')
              }
              Column({ space: 10 }) {
                Text(this.isLoggedIn ? this.userDisplayName : '点击登录').fontSize(22).fontWeight(FontWeight.Bold)
                  .fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.isLoggedIn ? (!this.hasClientCredential && this.tvAuthorizationStatus === 'pending' ? 'TV 授权确认中' : '查看个人资料与投稿') : '登录后同步你的观看记录').fontSize(12)
                  .fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Image($r('app.media.ref_chevron_right')).width(18).height(18).fillColor(this.profileIconColor())
            }.width('100%').padding(22).onClick(() => this.openProfile())
          }
          PageSurface() {
            Column() {
              this.SectionTitle('常用功能')
              Row() {
                this.QuickEntry($r('app.media.ref_history'), '历史记录', () => this.goToWatchHistory())
                this.QuickEntry($r('app.media.ref_favorites_folder'), '我的收藏', () => this.goToFavorites())
                this.QuickEntry($r('app.media.ref_cache'), '离线缓存', () => this.goToOfflineCache())
              }.width('100%')
            }.width('100%').padding({ left: 10, right: 10, top: 10, bottom: 8 })
          }
          PageSurface() {
            Column() {
              this.SectionTitle('个人服务')
              this.MenuRow($r('app.media.ref_profile'), '个人空间', () => this.openProfile())
              if (this.isLoggedIn && !this.hasClientCredential) {
                this.MenuRow($r('app.media.ref_profile'), '补充 TV 授权', () => this.goToLogin(true))
              }
              this.MenuRow($r('app.media.ref_message'), '消息中心', () => {
                this.getUIContext().getRouter().pushUrl({ url: 'pages/MessagesPage' })
                  .catch((error: Error) => { logError('打开消息失败', error); });
              })
            }.width('100%').padding({ left: 8, right: 8, top: 10, bottom: 8 })
          }
          // 实验室分区暂时隐藏，保留整块代码便于恢复
          // PageSurface() {
          //   Column() {
          //     this.SectionTitle('实验室')
          //     this.MenuRow($r('app.media.ic_public_volume_down'), '音量与亮度测试', () => this.goToLevelBarLab())
          //     this.MenuRow($r('app.media.headphones_fill'), '音频输出测试', () => {
          //       this.getUIContext().getRouter().pushUrl({ url: 'pages/AudioOutputLab' })
          //         .catch((error: Error) => { logError('打开音频输出测试失败', error); });
          //     })
          //   }.width('100%').padding({ left: 8, right: 8, top: 10, bottom: 8 })
          // }
        }.width('100%').constraintSize({ maxWidth: 760 })
          .padding({ left: 16, right: 16, top: this.statusBarHeight + 60,
            bottom: this.floatingBottomBar ? 100 + this.navIndicatorHeight : 32 })
      }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Column() {
      PageHeader({ withTabs: false }) {
        Row() {
          Text('我的').fontSize(22).fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C').layoutWeight(1)
          NativeGlassCapsule({ capsuleWidth: 88, capsuleHeight: 36 }) {
            Row() {
              Image($r('app.media.ic_settings_darkmode')).width(40).height(36).padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .fillColor(this.profileIconColor()).borderRadius(18)
                .id('profile-dark-mode').accessibilityText('切换深色模式')
                .onClick(() => this.onDarkModeChange(!this.isDarkMode))
              Image($r('app.media.ref_settings')).width(40).height(36).padding({ left: 10, right: 10, top: 8, bottom: 8 })
                .fillColor(this.profileIconColor()).borderRadius(18)
                .id('profile-settings').accessibilityText('设置').onClick(() => this.openSettings())
            }.padding({ left: 4, right: 4 })
          }
        }.width('100%').height(44 + this.statusBarHeight).constraintSize({ maxWidth: 760 })
          .padding({ left: 16, right: 16, top: this.statusBarHeight })
          .id('profile-fixed-header')
      }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }.width('100%').height('100%')
      .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
  }

  private async referenceSaveBoolean(key: string, value: boolean): Promise<void> {
    AppStorage.setOrCreate(key, value);
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.put(key, value);
      await this.dataPreferences.flush();
    } catch (error) { logError('保存设置失败', error); }
  }

  /** 设置项：写 AppStorage 立即生效（NetworkGate 每次判定都实时读取），同时落盘保证重启后 UI 与策略一致。 */
  private async saveCellularPrefetch(value: boolean): Promise<void> {
    await this.referenceSaveBoolean('cellularPrefetch', value);
    if (value) {
      this.getUIContext().getPromptAction().showToast({ message: '已放行蜂窝预热取流，注意移动数据流量' });
    }
  }

  private async referenceSaveRotation(mode: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow = await window.getLastWindow(context);
      const orientation = mode === '锁定竖屏' ? window.Orientation.PORTRAIT
        : mode === '锁定横屏' ? window.Orientation.AUTO_ROTATION_LANDSCAPE
        : mode === '自动旋转' ? window.Orientation.AUTO_ROTATION : window.Orientation.AUTO_ROTATION_RESTRICTED;
      await mainWindow.setPreferredOrientation(orientation);
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('screenOrientationLock', mode);
      await pref.flush();
      this.screenOrientationLock = mode;
    } catch (error) {
      logError('保存屏幕旋转设置失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '设置旋转失败，请重试' });
    }
  }

  private async saveLandscapePlaybackSide(side: string): Promise<void> {
    if (side !== 'left' && side !== 'right') return;
    try {
      const pref = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, 'my_app_settings');
      await pref.put('landscapePlaybackSide', side);
      await pref.flush();
      this.landscapePlaybackSide = side;
    } catch (error) {
      logError('保存横屏默认播放区域失败', error);
      this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
    }
  }

  /** 字体大小当前值文案（跟随系统时不显示滑条倍率）。 */
  private fontSizeValueLabel(): string {
    if (this.fontSizeMode !== 'custom') return '跟随系统';
    return AppScaleService.formatFontScale(this.fontScaleDraft);
  }

  /**
   * 菜单切模式。
   * 切到自定义：从**当前真实生效的字号**起步——跟随系统时生效的是系统倍率，
   *   用上次的自定义值会让滑条和画面字号对不上（且此时不会重新下发，画面不变）。
   * 切到跟随系统：立刻拉回系统倍率（setFontSizeScale 撤不回来，只能下发系统值）。
   */
  private async selectFontSizeMode(custom: boolean): Promise<void> {
    if (!custom) {
      this.fontScaleDraft = this.appFontScale;
      await this.saveFontSize(true, this.appFontScale);
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    AppScaleService.refreshSystemScale(context);
    const seed = AppScaleService.entryCustomScale(this.fontSizeMode !== 'custom', this.appFontScale);
    this.fontScaleDraft = seed;
    await this.saveFontSize(false, seed);
  }

  /**
   * 拖动中的实时预览：节流下发（不落盘），松手才落盘。
   * 节流是为了拖动时整树重排不至于每帧一次——setFontSizeScale 会重排整页，高频调用会明显掉帧。
   */
  private previewFontScale(scale: number): void {
    if (Math.abs(scale - this.appFontScale) < 1e-6) return;
    const now = Date.now();
    if (now - this.lastFontPreviewAt < FONT_PREVIEW_INTERVAL_MS) return;
    this.lastFontPreviewAt = now;
    this.fontSizeMode = 'custom';
    this.appFontScale = scale;
    AppScaleService.applyFontScale(this.getUIContext().getHostContext() as common.UIAbilityContext, scale);
  }

  /**
   * 字体大小：落盘 + 立即下发。
   * 跟随系统下发的是系统倍率（setFontSizeScale 撤不回来），下次冷启动才回到引擎原生跟随。
   */
  private async saveFontSize(followSystem: boolean, scale: number): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const prevMode = this.fontSizeMode;
    const prevScale = this.appFontScale;
    const next = followSystem ? this.appFontScale : scale;
    // 拖动预览已经下发过同一个值就不再下发（重复下发等于整树重排两遍，会闪一下）
    const needApply = followSystem || Math.abs(next - this.appFontScale) > 1e-6;
    this.fontSizeMode = followSystem ? 'system' : 'custom';
    this.appFontScale = next;
    this.fontScaleDraft = next;
    const saved = await AppScaleService.saveFontSetting(context, followSystem, next);
    if (!saved) {
      this.fontSizeMode = prevMode;
      this.appFontScale = prevScale;
      this.fontScaleDraft = prevScale;
      this.getUIContext().getPromptAction().showToast({ message: '保存字体大小失败，请重试' });
      return;
    }
    if (needApply && !AppScaleService.applyFontSetting(context, followSystem, next)) {
      this.getUIContext().getPromptAction().showToast({ message: '字体大小设置失败，请重试' });
    }
  }

  private settingLabels(kind: string): string[] {
    if (kind === 'kernel') return ['系统 AVPlayer', 'IJK 双轨直连（实验）'];
    if (kind === 'theme') return ['跟随系统', '浅色', '深色'];
    if (kind === 'wallpaper') return ['Pipw 二次元', 'Lorem Picsum 摄影', '设备本地图片', '关闭壁纸'];
    if (kind === 'rotation') return ROTATION_OPTIONS;
    if (kind === 'side') return ['左侧', '右侧'];
    if (kind === 'refresh') return ['跟随系统', ...this.highRefreshSupportedRates.map((rate: number) => `${rate} Hz`)];
    if (kind === 'fontSize') return ['跟随系统', '自定义'];
    if (kind === 'qualityWifi' || kind === 'qualityCellular') {
      return QUALITY_OPTIONS.map((item: QualityOption) => item.label);
    }
    if (kind === 'recommend') return ['App', 'Web'];
    if (kind === 'danmaku') return ['gRPC Protobuf', 'XML'];
    return ['超薄', '薄', '常规', '厚', '超厚'];
  }

  private settingSelection(kind: string): number {
    if (kind === 'kernel') return this.playbackKernel === 'ijk' ? 1 : 0;
    if (kind === 'theme') return ['system', 'light', 'dark'].indexOf(this.themeMode);
    if (kind === 'wallpaper') return ['pipw', 'picsum', 'local', 'none'].indexOf(this.pageWallpaperSource);
    if (kind === 'rotation') return ROTATION_OPTIONS.indexOf(this.screenOrientationLock);
    if (kind === 'side') return this.landscapePlaybackSide === 'right' ? 1 : 0;
    if (kind === 'refresh') return [0, ...this.highRefreshSupportedRates].indexOf(this.highRefreshRate);
    if (kind === 'fontSize') return this.fontSizeMode === 'custom' ? 1 : 0;
    if (kind === 'qualityWifi') return QUALITY_OPTIONS.findIndex((item: QualityOption) => item.qn === this.videoQnWifi);
    if (kind === 'qualityCellular') return QUALITY_OPTIONS.findIndex((item: QualityOption) => item.qn === this.videoQnCellular);
    if (kind === 'recommend') return this.recommendApiSource === 'Web' ? 1 : 0;
    if (kind === 'danmaku') return this.danmakuApiSource === 'xml' ? 1 : 0;
    return ['ultra-thin', 'thin', 'regular', 'thick', 'ultra-thick'].indexOf(
      kind === 'otherGlass' ? this.otherCardGlassThickness : this.videoCardGlassThickness);
  }

  private async selectSetting(kind: string, index: number): Promise<void> {
    if (index < 0 || index >= this.settingLabels(kind).length) return;
    if (kind === 'kernel') await this.selectPlaybackKernel(index === 1 ? 'ijk' : 'system');
    else if (kind === 'theme') await this.saveThemeMode(['system', 'light', 'dark'][index]);
    else if (kind === 'wallpaper') {
      if (this.pageWallpaperBusy) return;
      if (index === 2) await this.getUIContext().getRouter().pushUrl({ url: 'pages/LocalWallpaperPage' });
      else await this.applyPageWallpaper(['pipw', 'picsum', 'local', 'none'][index]);
    } else if (kind === 'rotation') await this.referenceSaveRotation(ROTATION_OPTIONS[index]);
    else if (kind === 'side') await this.saveLandscapePlaybackSide(index === 1 ? 'right' : 'left');
    else if (kind === 'qualityWifi') this.saveQuality('wifi', QUALITY_OPTIONS[index].qn);
    else if (kind === 'qualityCellular') this.saveQuality('cellular', QUALITY_OPTIONS[index].qn);
    else if (kind === 'recommend') await this.saveApiSource('recommendApiSource', index === 0 ? 'App' : 'Web');
    else if (kind === 'danmaku') await this.saveApiSource('danmakuApiSource', index === 0 ? 'grpc' : 'xml');
    else if (kind === 'fontSize') await this.selectFontSizeMode(index === 1);
    else if (kind === 'refresh') {
      try { HighRefreshService.getInstance().choose([0, ...this.highRefreshSupportedRates][index]); }
      catch (error) {
        logError('保存高刷设置失败', error);
        this.getUIContext().getPromptAction().showToast({ message: '设置失败，请重试' });
      }
    } else {
      const value = ['ultra-thin', 'thin', 'regular', 'thick', 'ultra-thick'][index];
      try {
        const pref = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, 'my_app_settings');
        await pref.put(kind === 'otherGlass' ? 'otherCardGlassThickness' : 'videoCardGlassThickness', value);
        await pref.flush();
        if (kind === 'otherGlass') this.otherCardGlassThickness = value;
        else this.videoCardGlassThickness = value;
      } catch (error) { logError('保存玻璃厚度失败', error); }
    }
  }

  private settingsMenuOptions(): MenuOptions {
    return {
      placement: Placement.BottomRight, enableArrow: false, borderRadius: 24,
      systemMaterial: deviceInfo.apiAvailable('26.0.0') ? GlassMaterial.create('menu', this.isDarkMode) : undefined
    };
  }

  @Builder
  SettingsOptions(kind: string) {
    Menu() {
      ForEach(this.settingLabels(kind), (label: string, index: number) => {
        MenuItem({ content: label,
          endIcon: this.settingSelection(kind) === index ? (this.isDarkMode ?
            $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          .height(52).id('setting-option-' + kind + '-' + index)
          .onClick(() => { this.selectSetting(kind, index); })
      }, (label: string) => label)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: this.isDarkMode ? '#24FFFFFF' : '#18000000', startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  /** 二级页：外观与交互（主题与壁纸 / 显示与方向 / 底栏与手势 / 视频卡片 / 其它内容卡片）。 */
  @Builder
  SettingsAppearanceLevel() {
    Scroll() {
      Column() {
        Column({ space: 6 }) {
        this.SectionTitle('主题与壁纸')
        PageSurface() {
          Column() {
            Row() {
              Text('主题').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.settingLabels('theme')[this.settingSelection('theme')] + ' ›').fontSize(13)
                .fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            }.width('100%').height(56).padding({ left: 16, right: 16 })
              .id('setting-theme').bindMenu(this.SettingsOptions('theme'), this.settingsMenuOptions())
            Row() {
              Column({ space: 4 }) {
                Text('页面壁纸').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                Text('仅非播放页生效').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text(this.pageWallpaperBusy ? '加载中…' : this.wallpaperLabel() + ' ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(72).padding({ left: 16, right: 16 })
            .id('setting-page-wallpaper').enabled(!this.pageWallpaperBusy).bindMenu(this.SettingsOptions('wallpaper'), this.settingsMenuOptions())
            if (this.pageWallpaperSource === 'pipw' || this.pageWallpaperSource === 'picsum') {
              Row() {
                Text('换一张壁纸').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
                Text('当前屏幕方向 ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.width('100%').height(50).padding({ left: 16, right: 16 }).enabled(!this.pageWallpaperBusy)
              .id('setting-wallpaper-refresh').onClick(() => this.applyPageWallpaper(this.pageWallpaperSource, true))
            }
            if (this.pageWallpaperEnabled) {
              // 两条滑条都实时生效：Moving 只改 AppStorage（PageWallpaper 立即重绘背景），
              // End/Click 才落盘。滑条值绑草稿而不是 StorageLink，避免「写回 0.55 → 读回 55.0000001」
              // 让滑块在拖动中自己抖一档。
              Column() {
                Text('壁纸透明度 ' + Math.round(this.wallpaperOpacityDraft) + '%')
                .fontSize(13).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').width('100%')
                Slider({ value: this.wallpaperOpacityDraft, min: 20, max: 100, step: 5 })
                .selectedColor('#D34E7E').id('setting-wallpaper-opacity')
                .onChange((value: number, mode: SliderChangeMode) => {
                  this.wallpaperOpacityDraft = Math.round(value);
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    PageWallpaperService.getInstance().setOpacity(this.wallpaperOpacityDraft / 100).catch(() => {});
                  } else {
                    PageWallpaperService.getInstance().previewOpacity(this.wallpaperOpacityDraft / 100);
                  }
                })
              }.width('100%').padding({ left: 16, right: 16 })
              Column() {
                Text('壁纸遮罩 ' + Math.round(this.wallpaperScrimDraft) + '%')
                  .fontSize(13).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').width('100%')
                Slider({ value: this.wallpaperScrimDraft, min: 0, max: 60, step: 1 })
                  .selectedColor('#D34E7E').id('setting-wallpaper-scrim')
                  .onChange((value: number, mode: SliderChangeMode) => {
                    this.wallpaperScrimDraft = Math.round(value);
                    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                      PageWallpaperService.getInstance().setScrim(this.wallpaperScrimDraft).catch(() => {});
                    } else {
                      PageWallpaperService.getInstance().previewScrim(this.wallpaperScrimDraft);
                    }
                  })
              }.width('100%').padding({ left: 16, right: 16, bottom: 10 })
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('显示与方向')
        PageSurface() {
          Column() {
            // 字体大小：菜单选「跟随系统 / 自定义」，选自定义才展开滑条（拖动中实时生效）。
            // ⚠️ 行高必须写死 height：拖动时字号变化会重排整页，minHeight 会让本行跟着长高，
            // 滑条被顶离手指（拖动到小字号时反向收缩、拖动中断）。固定后滑条位置不动。
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('字体大小').fontSize(15).maxFontScale(1.2)
                  .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text(this.fontSizeValueLabel() + ' ›').fontSize(13).maxFontScale(1.2)
                .fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            }.width('100%').height(72).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .id('setting-font-size').bindMenu(this.SettingsOptions('fontSize'), this.settingsMenuOptions())
            if (this.fontSizeMode === 'custom') {
              Column() {
                Slider({
                  value: this.fontScaleDraft,
                  min: FONT_SCALE_MIN,
                  max: FONT_SCALE_MAX,
                  step: FONT_SCALE_STEP
                })
                  .selectedColor('#D34E7E')
                  .blockColor(this.isDarkMode ? '#E7E9EB' : '#FFFFFF')
                  .id('setting-font-scale-slider')
                  .onChange((value: number, mode: SliderChangeMode) => {
                    const scale = Math.round(value * 100) / 100;
                    this.fontScaleDraft = scale;
                    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                      this.saveFontSize(false, scale);
                    } else {
                      this.previewFontScale(scale);
                    }
                  })
              }.width('100%').padding({ left: 16, right: 16, bottom: 10 })
            }
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('高刷模式').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                Text(this.highRefreshSupportedRates.length > 0
                ? '实际刷新率由系统调度'
                : '当前屏幕未提供可用高刷档位')
                .fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text((this.highRefreshRate === 0 ? '跟随系统' : `${this.highRefreshRate} Hz` +
              (this.highRefreshAvailable ? '' : '（当前不可用）')) + ' ›')
              .fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').constraintSize({ minHeight: 72 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .id('setting-high-refresh-rate').bindMenu(this.SettingsOptions('refresh'), this.settingsMenuOptions())
            Row() {
              Text('屏幕旋转').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.screenOrientationLock + ' ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(56).padding({ left: 16, right: 16 })
            .bindMenu(this.SettingsOptions('rotation'), this.settingsMenuOptions())
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('底栏与手势')
        PageSurface() {
          Column() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('隐藏底部小白条').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                // Text('在应用内隐藏系统手势导航提示条').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.hideNavigationIndicator }).selectedColor('#D34E7E')
              .id('setting-hide-navigation-indicator').accessibilityText('隐藏底部小白条')
              .onChange((value: boolean) => {
                this.referenceSaveBoolean('hideNavigationIndicator', value);
                StatusBarUtils.updateNavigationInset();
                window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((win: window.Window) => {
                  StatusBarUtils.setSystemBars(win, !(AppStorage.get<boolean>('isLandscape') ?? false) &&
                    !(AppStorage.get<boolean>('hideStatusBar') ?? false), true);
                });
              })
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('悬浮底栏').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                // Text('光感玻璃 · 首页上滑隐藏，下滑显示').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.floatingBottomBar }).selectedColor('#D34E7E')
              .accessibilityText('悬浮底栏')
              .onChange((value: boolean) => this.referenceSaveBoolean('floatingBottomBar', value))
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('底栏智感握姿').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                // Text(this.floatingBottomBar ? '底栏跟随左右手握持位置，双手握持时居中' : '开启悬浮底栏后可用')
                // .fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.bottomBarSmartGrip }).selectedColor('#D34E7E')
              .enabled(this.floatingBottomBar)
              .accessibilityText('底栏智感握姿')
              .onChange((value: boolean) => this.referenceSaveBoolean('bottomBarSmartGrip', value))
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .opacity(this.floatingBottomBar ? 1 : 0.5)
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('视频卡片')
        PageSurface() {
          Column() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('沉浸光感').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                // Text('原生玻璃 · 仅边缘光感').fontSize(12).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.videoCardEdgeLight }).selectedColor('#D34E7E')
              .id('setting-video-card-edge-light').accessibilityText('视频卡片原生玻璃')
              .onChange((value: boolean) => this.referenceSaveBoolean('videoCardEdgeLight', value))
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            if (this.videoCardEdgeLight) {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('卡片染色').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                  // Text('关闭后更通透，折射更明显').fontSize(12)
                  // .fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.videoCardGlassTint }).selectedColor('#D34E7E')
                .id('setting-video-card-glass-tint').accessibilityText('卡片玻璃染色')
                .onChange((value: boolean) => this.referenceSaveBoolean('videoCardGlassTint', value))
              }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('材质反色').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.videoCardGlassInvert }).selectedColor('#D34E7E')
                  .id('setting-video-card-glass-invert').accessibilityText('视频卡片材质反色')
                  .onChange((value: boolean) => this.referenceSaveBoolean('videoCardGlassInvert', value))
              }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              Row() {
                Text('材质厚度').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
                Text(this.glassThicknessLabel() + ' ›').fontSize(13)
                .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.width('100%').height(56).padding({ left: 16, right: 16 })
              .id('setting-glass-thickness').bindMenu(this.SettingsOptions('videoGlass'), this.settingsMenuOptions())
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('其它内容卡片')
        PageSurface() {
          Column() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('沉浸光感').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                // Text('资料、设置、动态等内容卡片').fontSize(12)
                //   .fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.otherCardGlassEnabled }).selectedColor('#D34E7E')
                .id('setting-other-card-glass').accessibilityText('其它卡片原生玻璃')
                .onChange((value: boolean) => this.referenceSaveBoolean('otherCardGlassEnabled', value))
            }.width('100%').constraintSize({ minHeight: 72 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            if (this.otherCardGlassEnabled) {
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('卡片染色').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                  // Text('关闭后使用无染色原生玻璃').fontSize(12).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.otherCardGlassTint }).selectedColor('#D34E7E')
                  .id('setting-other-card-glass-tint').accessibilityText('其它卡片玻璃染色')
                  .onChange((value: boolean) => this.referenceSaveBoolean('otherCardGlassTint', value))
              }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('材质反色').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.otherCardGlassInvert }).selectedColor('#D34E7E')
                  .id('setting-other-card-glass-invert').accessibilityText('其它卡片材质反色')
                  .onChange((value: boolean) => this.referenceSaveBoolean('otherCardGlassInvert', value))
              }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              Row() {
                Text('材质厚度').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
                Text(this.glassThicknessLabel(true) + ' ›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
              }.width('100%').height(56).padding({ left: 16, right: 16 })
                .id('setting-other-card-glass-thickness').bindMenu(this.SettingsOptions('otherGlass'), this.settingsMenuOptions())
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%')
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 16, right: 16, top: this.statusBarHeight + 60, bottom: 32 + this.navIndicatorHeight })
    }.width('100%').height('100%').scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
  }

  /** 二级页：播放设置（播放 / 内容来源 / 网络与流量）。 */
  @Builder
  SettingsPlaybackLevel() {
    Scroll() {
      Column() {
        Column({ space: 6 }) {
        this.SectionTitle('播放')
        PageSurface() {
          Column() {
            Row() {
              Text('播放内核').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.settingLabels('kernel')[this.settingSelection('kernel')] + ' ›').fontSize(13)
                .fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .id('setting-playback-kernel').bindMenu(this.SettingsOptions('kernel'), this.settingsMenuOptions())
            Row() {
              Text('横屏默认播放区域').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text((this.landscapePlaybackSide === 'right' ? '右侧' : '左侧') + ' ›').fontSize(13)
                .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(56).padding({ left: 16, right: 16 })
            .id('setting-landscape-playback-side').bindMenu(this.SettingsOptions('side'), this.settingsMenuOptions())
            Row() {
              Text('后台播放').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.referenceBackgroundPlay }).selectedColor('#D34E7E')
              .onChange((value: boolean) => this.referenceSaveBoolean('bgp', value))
            }.width('100%').height(56).padding({ left: 16, right: 16 })
            // 画质偏好按链路分两档：Wi-Fi（含以太网/不计费）与移动网络（蜂窝、计费 Wi-Fi、手机热点）。
            // 热点走 Wi-Fi 承载却记在蜂窝套餐上，判定为计费后自动切到「移动网络」档。
            Row() {
              Text('Wi-Fi 画质').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(qualityLabel(this.videoQnWifi) + ' ›').fontSize(13).fontColor(secondaryTextColor(this.isDarkMode))
            }.width('100%').height(56).padding({ left: 16, right: 16 })
              .id('setting-quality-wifi').bindMenu(this.SettingsOptions('qualityWifi'), this.settingsMenuOptions())
            Row() {
              Text('移动网络画质').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(qualityLabel(this.videoQnCellular) + ' ›').fontSize(13).fontColor(secondaryTextColor(this.isDarkMode))
            }.width('100%').height(56).padding({ left: 16, right: 16 })
              .id('setting-quality-cellular').bindMenu(this.SettingsOptions('qualityCellular'), this.settingsMenuOptions())
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('当前网络').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Text(this.networkClassText()).fontSize(13).fontColor(secondaryTextColor(this.isDarkMode))
            }.width('100%').constraintSize({ minHeight: 72 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .id('setting-quality-network')
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('内容来源')
        PageSurface() {
          Column() {
            Row() {
              Text('推荐源').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.recommendApiSource + ' ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(56).padding({ left: 16, right: 16 }).bindMenu(this.SettingsOptions('recommend'), this.settingsMenuOptions())
            Row() {
              Text('弹幕数据源').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text((this.danmakuApiSource === 'xml' ? 'XML' : 'gRPC Protobuf') + ' ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(56).padding({ left: 16, right: 16 }).bindMenu(this.SettingsOptions('danmaku'), this.settingsMenuOptions())
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('网络与流量')
        PageSurface() {
          Column() {
            Row({ space: 12 }) {
              Column({ space: 4 }) {
                Text('蜂窝网络预热取流').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                Text('测试用 · 允许蜂窝/计费网络后台预取，消耗更多流量').fontSize(12)
                  .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Toggle({ type: ToggleType.Switch, isOn: this.cellularPrefetch }).selectedColor('#D34E7E')
                .id('setting-cellular-prefetch').accessibilityText('蜂窝网络预热取流')
                .onChange((value: boolean) => { this.saveCellularPrefetch(value); })
            }.width('100%').constraintSize({ minHeight: 72 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
            // Text('仅放开网络门控；当前 512 KiB 单任务、1152 KiB/30s 的预热字节预算不变，未知网络与切网瞬间仍拒绝。')
            //   .fontSize(12).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            //   .width('100%').padding({ left: 16, right: 16, bottom: 12 })
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%')
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 16, right: 16, top: this.statusBarHeight + 60, bottom: 32 + this.navIndicatorHeight })
    }.width('100%').height('100%').scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
  }

  /** 一级入口行：右侧沿用设置页统一的「›」文字箭头。 */
  @Builder
  SettingsEntryRow(label: string, entryId: string, action: () => void) {
    Row({ space: 14 }) {
      Text(label).fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
      Text('›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
    }.width('100%').height(56).padding({ left: 16, right: 16 }).id(entryId).onClick(action)
  }

  /** 设置一级：不带标题的单张卡片，只留两个分区入口与清理/关于/退出。 */
  @Builder
  SettingsRoot() {
    Scroll() {
      Column() {
        PageSurface() {
          Column() {
            this.SettingsEntryRow('外观与交互', 'setting-entry-appearance', () => this.openSettingsSection('appearance'))
            this.SettingsEntryRow('播放设置', 'setting-entry-playback', () => this.openSettingsSection('playback'))
            Row() {
              Text('清除缓存').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.cacheSizeText + ' ›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .id('setting-clear-cache').onClick(() => this.clearCache())
            this.MenuRowPlain('关于PuraPily', () => this.goToAbout(), this.hasNewVersion)
            if (this.isLoggedIn) { this.MenuRowPlain('退出登录', () => this.showLogoutConfirm(), false) }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 16, right: 16, top: this.statusBarHeight + 60, bottom: 32 + this.navIndicatorHeight })
    }.width('100%').height('100%').scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
  }

  build() {
    if (this.settingsOnly) {
      if (this.settingsSection === 'appearance') {
        this.SettingsAppearanceLevel()
      } else if (this.settingsSection === 'playback') {
        this.SettingsPlaybackLevel()
      } else {
        this.SettingsRoot()
      }
    } else {
      this.ReferenceProfile()
    }
  }
}
