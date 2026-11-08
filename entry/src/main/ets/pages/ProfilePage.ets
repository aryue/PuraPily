import { FavoritesDataService } from '../services/FavoritesDataService';
import { extractMidFromCookie } from '../api/FeedbackService';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageSurface } from '../components/PageSurface';
import { NativeGlassCapsule } from '../components/NativeGlassCapsule';
import { PageWallpaperService } from '../services/PageWallpaperService';
// ProfilePage.ets - 个人中心与当前设置页。
import { deviceInfo } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { applyThemeMode } from '../utils/ReferenceAppearance';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { preferences } from '@kit.ArkData';
import { window, uiMaterial, LengthMetrics } from '@kit.ArkUI';
import { getUserInfo } from '../api/BilibiliApi';
import { logoutSession } from '../services/LoginSession';
import { getLoginAccessKey } from '../utils/CredentialStore';
import { HighRefreshService } from '../services/HighRefreshService';

interface QualityItem { qn: number; label: string; }
const QUALITY_LIST: QualityItem[] = [
  { qn: 16, label: '360P' }, { qn: 32, label: '480P' },
  { qn: 64, label: '720P' }, { qn: 80, label: '1080P' },
  { qn: 112, label: '1080P+' }, { qn: 116, label: '1080P60' }, { qn: 120, label: '4K' }
];
const DEFAULT_QN: number = 116;
const ROTATION_OPTIONS: string[] = ['跟随系统', '自动旋转', '锁定竖屏', '锁定横屏'];
function labelByQn(qn: number): string {
  return QUALITY_LIST.find(q => q.qn === qn)?.label ?? '1080P60';
}

@Component({ freezeWhenInactive: true })
export struct ProfilePage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('pageWallpaperSource') pageWallpaperSource: string = 'none';
  @StorageLink('pageWallpaperBusy') pageWallpaperBusy: boolean = false;
  @StorageLink('pageWallpaperOpacity') pageWallpaperOpacity: number = 0.7;
  @StorageLink('isLandscape') wallpaperLandscape: boolean = false;
  @StorageLink('playbackKernel') playbackKernel: string = 'system';
  @State cacheSizeText: string = '计算中…';
  @Prop settingsOnly: boolean = false;
  @StorageLink('highRefreshRate') highRefreshRate: number = 0;
  @StorageLink('highRefreshSupportedRates') highRefreshSupportedRates: number[] = [];
  @StorageLink('highRefreshAvailable') highRefreshAvailable: boolean = true;
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
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('bgp') referenceBackgroundPlay: boolean = false;
  @StorageLink('cellularPrefetch') cellularPrefetch: boolean = false;
  @StorageLink('vibrateEnabled') referenceVibrate: boolean = true;
  @StorageLink('landscapePlaybackSide') landscapePlaybackSide: string = 'left';
  @StorageLink('screenOrientationLock') screenOrientationLock: string = '跟随系统';
  @StorageLink('defaultVideoQn') defaultVideoQn: number = DEFAULT_QN;
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
    if (this.settingsOnly) await this.calcCacheSize();
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

  private async saveDefaultQn(qn: number): Promise<void> {
    try {
      const pref = await preferences.getPreferences(this.getUIContext().getHostContext() as common.UIAbilityContext, 'my_app_settings');
      await pref.put('defaultVideoQn', qn);
      await pref.flush();
      this.defaultVideoQn = qn;
    } catch (error) { logError('保存默认画质失败', error); }
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
  MenuRowPlain(label: string, action: () => void) {
    Row({ space: 14 }) {
      Text(label).fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
      Text('›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
    }.width('100%').height(56).padding({ left: 16, right: 16 }).onClick(action)
  }

  private openSettings(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SettingsPage' })
      .catch((error: Error) => { logError('打开设置失败', error); });
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

  private settingLabels(kind: string): string[] {
    if (kind === 'kernel') return ['系统 AVPlayer', 'IJK 双轨直连（实验）'];
    if (kind === 'theme') return ['跟随系统', '浅色', '深色'];
    if (kind === 'wallpaper') return ['Pipw 二次元', 'Lorem Picsum 摄影', '设备本地图片', '关闭壁纸'];
    if (kind === 'rotation') return ROTATION_OPTIONS;
    if (kind === 'side') return ['左侧', '右侧'];
    if (kind === 'refresh') return ['跟随系统', ...this.highRefreshSupportedRates.map((rate: number) => `${rate} Hz`)];
    if (kind === 'quality') return QUALITY_LIST.map((item: QualityItem) => item.label);
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
    if (kind === 'quality') return QUALITY_LIST.findIndex((item: QualityItem) => item.qn === this.defaultVideoQn);
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
    else if (kind === 'quality') await this.saveDefaultQn(QUALITY_LIST[index].qn);
    else if (kind === 'recommend') await this.saveApiSource('recommendApiSource', index === 0 ? 'App' : 'Web');
    else if (kind === 'danmaku') await this.saveApiSource('danmakuApiSource', index === 0 ? 'grpc' : 'xml');
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
      systemMaterial: deviceInfo.apiAvailable('26.0.0') ? new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.REGULAR,
        materialColor: this.isDarkMode ? '#66242628' : '#88F7F8FA',
        interactive: true, applyShadow: true, lightEffect: { color: Color.White }
      }) : undefined
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

  @Builder
  ReferenceSettings() {
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
              Column() {
                Text('壁纸透明度 ' + Math.round(this.pageWallpaperOpacity * 100) + '%')
                .fontSize(13).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').width('100%')
                Slider({ value: this.pageWallpaperOpacity * 100, min: 20, max: 100, step: 5 })
                .selectedColor('#D34E7E').onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                    PageWallpaperService.getInstance().setOpacity(value / 100).catch(() => {});
                  }
                })
              }.width('100%').padding({ left: 16, right: 16 })
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('显示与方向')
        PageSurface() {
          Column() {
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
        }.width('100%').margin({ bottom: 18 })
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
            Row() {
              Text('默认播放画质').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(labelByQn(this.defaultVideoQn) + ' ›').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81')
            }.width('100%').height(56).padding({ left: 16, right: 16 }).bindMenu(this.SettingsOptions('quality'), this.settingsMenuOptions())
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
        }.width('100%').margin({ bottom: 18 })
        Column({ space: 6 }) {
        this.SectionTitle('其它')
        PageSurface() {
          Column() {
            Row() {
              Text('清除缓存').fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C').layoutWeight(1)
              Text(this.cacheSizeText + ' ›').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
            }.width('100%').constraintSize({ minHeight: 56 }).padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .id('setting-clear-cache').onClick(() => this.clearCache())
            this.MenuRowPlain('关于PuraPily', () => this.goToAbout())
            if (this.isLoggedIn) { this.MenuRowPlain('退出登录', () => this.showLogoutConfirm()) }
          }.width('100%').padding({ top: 4, bottom: 4 })
        }
        }.width('100%')
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 16, right: 16, top: this.statusBarHeight + 60, bottom: 32 + this.navIndicatorHeight })
    }.width('100%').height('100%').scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))

  }

  build() {
    if (this.settingsOnly) {
      this.ReferenceSettings()
    } else {
      this.ReferenceProfile()
    }
  }
}
