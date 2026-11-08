import { PageSurface } from '../components/PageSurface';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
// QrCodeLoginPage.ets — 扫码登录（纯API方案，不依赖WebView Cookie同步延迟）
import { router } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { saveLoginCredentials } from '../utils/CredentialStore';
import { common } from '@kit.AbilityKit';
import {
  generateLoginQrCode,
  pollQrCodeStatusApi,
  generateTvLoginQrCode,
  pollTvQrCodeStatusApi,
  verifyLoginSession,
  QrCodeStatus,
  QrCodePollResult
} from '../api/BilibiliApi';
import { mergeLoginCookies, hasLoginSession } from '../utils/LoginCookie';
import { TvQrAuthorization, TvAuthorizationState } from '../services/TvQrAuthorization';
import { authorizeCurrentAccount } from '../services/CurrentAccountAuthorization';

interface QrCodeLoginParams { tvMode?: boolean; }

@Entry
@Component
struct QrCodeLoginPage {
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @State qrContent: string = '';
  @State statusText: string = '正在生成二维码...';
  @State statusSubText: string = '';
  @State isPolling: boolean = false;
  @State isExpired: boolean = false;
  @State isSuccess: boolean = false;
  @State qrSecondsLeft: number = 0;
  // 开源版默认走 Web 扫码登录：该路径使用公开接口（passport-login/web/qrcode），
  // 无需额外凭据即可使用。
  @State isTvMode: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 40;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @State canAuthorizeCurrentAccount: boolean = false;
  private qrcodeKey: string = '';
  private initialCookies: string = '';  // generate 阶段返回的初始 Cookie，用于 poll 时保持会话
  private pollTimer: number = -1;
  private loginProcessing: boolean = false;
  private pollInFlight: boolean = false;
  private loginGeneration: number = 0;
  private qrExpiresAt: number = 0;
  private lastPollAt: number = 0;
  private tvAuthorizationSession: number = -1;
  private loginPageActive: boolean = true;

  async aboutToAppear(): Promise<void> {
    this.loginPageActive = true;
    this.canAuthorizeCurrentAccount = hasLoginSession(AppStorage.get<string>('biliCookie') || '');
    const params = this.getUIContext().getRouter().getParams() as QrCodeLoginParams;
    if (params?.tvMode === true) this.isTvMode = true;
    await this.generateQrCode();
  }

  aboutToDisappear(): void {
    this.loginPageActive = false;
    TvQrAuthorization.detach(this.tvAuthorizationSession);
    this.loginGeneration++;
    this.stopPolling();
  }

  private async confirmCurrentAccountAuthorization(): Promise<void> {
    if (this.loginProcessing) return;
    this.loginProcessing = true;
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const generation = this.loginGeneration;
    try {
      const choice = await this.getUIContext().getPromptAction().showDialog({
        title: '授权当前账号',
        message: '将使用当前已登录的 B 站账号新增一次客户端登录授权，并安全保存令牌，用于不喜欢、投币等操作。是否继续？',
        buttons: [{ text: '取消', color: '#999999' }, { text: '确认授权', color: '#007DFF' }]
      });
      if (choice.index !== 1 || !this.loginPageActive || generation !== this.loginGeneration) return;
      if (cookie !== AppStorage.get<string>('biliCookie')) throw new Error('账号已变化，请重新确认授权');
      TvQrAuthorization.cancel(this.tvAuthorizationSession);
      this.stopPolling();
      this.qrContent = '';
      this.statusText = '正在接收客户端授权...';
      this.statusSubText = '';
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await authorizeCurrentAccount(context, cookie);
      if (!this.loginPageActive || generation !== this.loginGeneration) return;
      this.isSuccess = true;
      this.isExpired = false;
      this.statusText = '客户端授权已保存';
      this.statusSubText = '可以返回重试不喜欢、投币等操作';
    } catch (error) {
      if (!this.loginPageActive || generation !== this.loginGeneration) return;
      this.isExpired = true;
      this.statusText = '客户端授权未完成';
      this.statusSubText = (error as Error).message || '请稍后重试';
    } finally { this.loginProcessing = false; }
  }

  /** 生成登录二维码 */
  private async generateQrCode(): Promise<void> {
    if (this.loginProcessing) return;
    TvQrAuthorization.cancel(this.tvAuthorizationSession);
    this.stopPolling();
    const generation = ++this.loginGeneration;
    this.isExpired = false;
    this.isSuccess = false;
    this.isPolling = false;
    this.statusText = '正在生成二维码...';
    this.statusSubText = '';
    this.qrContent = '';
    this.initialCookies = '';
    this.qrExpiresAt = 0;
    this.qrSecondsLeft = 0;
    this.lastPollAt = 0;

    if (this.isTvMode) {
      // ── TV端登录 ──
      const result = await generateTvLoginQrCode();
      if (generation !== this.loginGeneration) return;
      if (!result) {
        this.statusText = '生成二维码失败';
        this.statusSubText = '请检查网络后重试';
        return;
      }
      this.qrcodeKey = result.qrcode_key; // auth_code
      this.qrContent = result.url;
      this.statusText = '请使用B站客户端扫描二维码';
      this.statusSubText = '打开B站APP → 我的 → 扫一扫';
    } else {
      // ── Web端扫码登录 ──
      const result = await generateLoginQrCode();
      if (generation !== this.loginGeneration) return;
      if (!result) {
        this.statusText = '生成二维码失败';
        this.statusSubText = '请检查网络后重试';
        return;
      }
      this.qrcodeKey = result.qrcode_key;
      this.initialCookies = result._cookies || '';
      this.qrContent = result.url;
      this.statusText = '请使用B站客户端扫描二维码';
      this.statusSubText = '打开B站APP → 我的 → 扫一扫';
    }

    this.qrExpiresAt = Date.now() + 180000;
    this.qrSecondsLeft = 180;
    this.isPolling = true;
    if (this.isTvMode) {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.tvAuthorizationSession = TvQrAuthorization.begin(context, this.qrcodeKey, (state: TvAuthorizationState) => {
        if (!this.loginPageActive || generation !== this.loginGeneration) return;
        this.qrSecondsLeft = state.remainingSeconds;
        this.statusText = state.message;
        if (state.status === QrCodeStatus.SUCCESS) {
          this.isSuccess = true;
          this.isExpired = false;
          this.isPolling = false;
          this.statusSubText = '客户端授权已保存，即将返回';
          setTimeout(() => {
            if (this.loginPageActive && generation === this.loginGeneration) this.getUIContext().getRouter().back();
          }, 800);
        } else if (state.status === QrCodeStatus.ERROR || state.status === QrCodeStatus.EXPIRED) {
          this.isExpired = true;
          this.isPolling = false;
          this.statusSubText = '请重新获取二维码';
        } else {
          this.statusSubText = state.status === QrCodeStatus.SCANNED ? '请在手机上确认；返回上一页后仍会接收授权结果' : '打开B站APP → 我的 → 扫一扫';
        }
      });
      return;
    }
    this.startPolling();
  }

  /** 启动轮询（每2秒一次） */
  private startPolling(): void {
    this.stopPolling();
    this.isPolling = true;
    // 首次立即轮询
    this.doPoll();
    this.pollTimer = setInterval(() => {
      this.doPoll();
    }, 1000);
  }

  /** 停止轮询 */
  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
    this.isPolling = false;
  }

  /** 执行一次轮询 */
  private async doPoll(): Promise<void> {
    if (this.isSuccess || this.isExpired || this.loginProcessing) return;
    const now = Date.now();
    this.qrSecondsLeft = Math.max(0, Math.ceil((this.qrExpiresAt - now) / 1000));
    if (this.qrSecondsLeft === 0) { this.onQrCodeExpired(); return; }
    if (this.pollInFlight || now - this.lastPollAt < 2000) return;
    this.lastPollAt = now;
    const generation = this.loginGeneration;
    this.pollInFlight = true;

    let result: QrCodePollResult;
    try {
      if (this.isTvMode) {
        result = await pollTvQrCodeStatusApi(this.qrcodeKey);
      } else {
        result = await pollQrCodeStatusApi(this.qrcodeKey, this.initialCookies);
      }
    } finally {
      this.pollInFlight = false;
    }
    if (generation !== this.loginGeneration) return;
    if (this.isExpired && result.status !== QrCodeStatus.SUCCESS) return;

    switch (result.status) {
      case QrCodeStatus.SUCCESS:
        await this.onLoginSuccess(result.cookies, result.accessKey || '');
        break;
      case QrCodeStatus.SCANNED:
        if (this.statusText !== '已扫码，请在手机上确认登录') {
          this.statusText = '已扫码，请在手机上确认登录';
          this.statusSubText = '点击确认即可完成登录';
        }
        break;
      case QrCodeStatus.EXPIRED:
        this.onQrCodeExpired();
        break;
      case QrCodeStatus.NOT_SCANNED:
        // 保持等待状态
        break;
      case QrCodeStatus.ERROR:
        this.stopPolling();
        this.isExpired = true;
        this.statusText = 'TV 授权未完成';
        this.statusSubText = result.message || '授权响应异常，请重新获取二维码';
        break;
      default:
        logWarn(`未知轮询状态: ${result.status}`);
        break;
    }
  }

  /** 二维码过期处理 */
  private onQrCodeExpired(): void {
    this.stopPolling();
    this.isExpired = true;
    this.qrSecondsLeft = 0;
    this.statusText = '二维码已过期';
    this.statusSubText = '请点击下方按钮重新获取';
  }

  /** 登录成功处理 */
  private async onLoginSuccess(cookieStr: string, accessKey: string): Promise<void> {
    if (this.isSuccess || this.loginProcessing) return;
    this.stopPolling();
    this.loginProcessing = true;
    this.isExpired = false;
    this.statusText = '正在验证登录状态...';
    this.statusSubText = '';
    cookieStr = mergeLoginCookies([cookieStr]);
    let loginError = '登录信息保存失败，请重试';

    try {
      if (!hasLoginSession(cookieStr)) {
        loginError = '扫码已确认，但登录响应缺少 SESSDATA，请重新扫码或切换 TV 登录';
        throw new Error(loginError);
      }
      const verification = await verifyLoginSession(cookieStr);
      if (verification.state === 'rejected') {
        loginError = verification.reason;
        throw new Error(loginError);
      }
      // 保存 Cookie
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (this.isTvMode && !accessKey.trim()) {
        loginError = 'TV 登录响应缺少客户端令牌，请重新获取二维码';
        throw new Error(loginError);
      }
      await saveLoginCredentials(context, cookieStr, accessKey, this.isTvMode);
      this.isSuccess = true;
      this.loginProcessing = false;
      this.statusText = this.isTvMode ? 'TV 登录成功！' : '登录成功！';
      this.statusSubText = verification.state === 'unavailable' ? '账号资料暂不可用，已保存登录会话' : '即将返回...';

      // 触发首页刷新
      const flag: number = AppStorage.get<number>('refreshHomeFlag') ?? 0;
      AppStorage.setOrCreate('refreshHomeFlag', flag + 1);
      this.getUIContext().getPromptAction().showToast({ message: verification.state === 'unavailable'
        ? '扫码已确认，会话已保存；账号资料稍后刷新' : '登录成功！' });
    } catch (err) {
      logError(`保存Cookie失败: ${err}`);
      this.isSuccess = false;
      this.loginProcessing = false;
      this.isExpired = true;
      this.statusText = '登录验证失败';
      this.statusSubText = loginError;
      return;
    }

    // 延迟返回上一页
    setTimeout(() => this.getUIContext().getRouter().back(), 800);
  }

  /** 重新生成二维码 */
  private refreshQrCode(): void {
    this.generateQrCode();
  }

  /** 切换到 TV 登录 */
  private switchToTvLogin(): void {
    if (this.loginProcessing) return;
    this.stopPolling();
    this.isTvMode = true;
    this.statusText = '正在生成TV端二维码...';
    this.statusSubText = '';
    this.generateQrCode();
  }

  /** 切换到 Web 扫码登录 */
  private switchToWebQrLogin(): void {
    if (this.loginProcessing) return;
    this.stopPolling();
    this.isTvMode = false;
    this.statusText = '正在生成二维码...';
    this.statusSubText = '';
    this.generateQrCode();
  }

  /** 切换到 WebView 登录 */
  private switchToWebLogin(): void {
    router.replaceUrl({ url: 'pages/BilibiliLoginPage' }).catch((err: Error) => {
      logError('跳转Web登录失败', err);
    });
  }

  @Builder
  LoginModeOption(tvMode: boolean, label: string) {
    Button() {
      Column({ space: 4 }) {
        Text(label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White)
        Text(this.isTvMode === tvMode ? '当前方式' : '点击切换')
          .fontSize(12).fontColor(this.isTvMode === tvMode ? '#FFFFFF' : '#C4CAD4')
      }.padding({ top: 10, bottom: 10 })
    }
    .id(tvMode ? 'login-mode-tv' : 'login-mode-web')
    .layoutWeight(1)
    .borderRadius(12)
    .backgroundColor(this.isTvMode === tvMode ? '#006CDE' : '#303640')
    .border({ width: 1, color: this.isTvMode === tvMode ? '#75B8FF' : '#59616D' })
    .onClick(() => {
      if (this.isTvMode === tvMode || this.isSuccess) return;
      if (tvMode) this.switchToTvLogin();
      else this.switchToWebQrLogin();
    })
  }



  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageWallpaper()
      Scroll() {
        Column() {
        PageSurface({ radius: 24 }) {
        Column({ space: 20 }) {
          Column({ space: 12 }) {
            Text('选择扫码方式')
              .fontSize(16).fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C').fontWeight(FontWeight.Medium)
              .width('100%')
            Row({ space: 12 }) {
              this.LoginModeOption(true, 'TV 扫码')
              this.LoginModeOption(false, 'Web 扫码')
            }.width('100%')
            Text(this.isTvMode
              ? 'TV 扫码可补充客户端授权，用于 App 推荐源的个性化推荐及部分互动。'
              : 'Web 扫码用于网页登录。需要 App 推荐源的个性化推荐及客户端授权时，请选择 TV 扫码。')
              .fontSize(13).fontColor(this.isDarkMode ? '#D4D9E1' : '#50545A').lineHeight(20).width('100%')
          }.width('100%')

          Column({ space: 16 }) {
            if (this.qrContent && !this.isExpired && !this.isSuccess) {
              QRCode(this.qrContent)
                .width(220).height(220).color(Color.Black)
                .borderRadius(12).backgroundColor(Color.White).padding(8)
            } else {
              Column() {
                if (this.isSuccess) {
                  Text('✓').fontSize(48).fontColor('#65E3A0')
                } else if (this.isExpired) {
                  Text('二维码已失效').fontSize(16).fontColor('#FF9B9B')
                } else if (this.statusSubText) {
                  Text('二维码暂不可用').fontSize(16).fontColor(Color.White)
                } else {
                  LoadingProgress().width(48).height(48).color('#75B8FF')
                }
              }.width(220).height(220).justifyContent(FlexAlign.Center)
                .borderRadius(12).backgroundColor('#303640')
            }
            Column({ space: 8 }) {
              Text(this.statusText)
                .fontSize(18).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
                .fontColor(this.isSuccess ? '#65E3A0' : (this.isExpired ? (this.isDarkMode ? '#FF9B9B' : '#B32632') : (this.isDarkMode ? '#F2F4F8' : '#18191C')))
              if (this.statusSubText) {
                Text(this.statusSubText).fontSize(14).fontColor(this.isDarkMode ? '#D4D9E1' : '#50545A')
                  .lineHeight(21).textAlign(TextAlign.Center)
              }
              if (this.isPolling && !this.isExpired && !this.isSuccess) {
                Text(`二维码 ${this.qrSecondsLeft} 秒后过期`)
                  .fontSize(13).fontColor(this.isDarkMode ? '#D4D9E1' : '#50545A')
              }
            }.width('100%')
            if (!this.isSuccess) {
              Button(this.isExpired || !this.qrContent ? '重新获取二维码' : '刷新二维码')
                .width('100%').height(44).borderRadius(22)
                .backgroundColor('#303640').fontColor(Color.White)
                .border({ width: 1, color: '#707A89' })
                .onClick(() => this.refreshQrCode())
            }
            if (this.isTvMode && this.canAuthorizeCurrentAccount && !this.isSuccess) {
              Button('使用当前账号授权')
                .width('100%').height(44).backgroundColor('#006CDE').fontColor(Color.White)
                .onClick(() => this.confirmCurrentAccountAuthorization())
            }
          }.width('100%')

          Column({ space: 10 }) {
            Button('改用网页登录')
              .width('100%').height(44).borderRadius(22)
              .backgroundColor('#303640').fontColor(Color.White)
              .onClick(() => this.switchToWebLogin())
            Text('网页登录支持账号密码、短信及扫码')
              .fontSize(13).fontColor(this.isDarkMode ? '#D4D9E1' : '#50545A').textAlign(TextAlign.Center)
          }.width('100%')
        }
        .width('100%').constraintSize({ maxWidth: 440 })
        .padding(20).borderRadius(24)
        }
        }.width('100%').constraintSize({ maxWidth: 440 })
        .margin({ top: this.statusBarHeight + 76, bottom: 24 + this.navIndicatorHeight })
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
      .padding({ left: 16, right: 16 })

      Column() {
      PageHeader({ withTabs: false }) {
        Column() {
          Row() {
            Text('扫码登录').fontSize(20).fontColor(Color.White).fontWeight(FontWeight.Medium)
          }.width('100%').height(56).padding({ left: 24, right: 24 })
        }.width('100%').padding({ top: this.statusBarHeight })
      }
      }.width('100%').hitTestBehavior(HitTestMode.Block).zIndex(3)
    }
    .width('100%').height('100%')
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : '#111111')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
