import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
// BilibiliLoginPage.ets
import { webview } from '@kit.ArkWeb';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { saveLoginCredentials } from '../utils/CredentialStore';
import { isBilibiliHttpsUrl } from '../utils/LoginUrlPolicy';
import { common } from '@kit.AbilityKit';
import { verifyLoginSession } from '../api/BilibiliApi';
import { hasLoginSession } from '../utils/LoginCookie';

@Entry
@Component
struct BilibiliLoginPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 40;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  private webController: webview.WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State errorMsg: string = '';
  @State progress: number = 0;
  // 防止重复提取 Cookie
  private cookieExtracted: boolean = false;

  aboutToAppear() {
    webview.WebviewController.setWebDebuggingAccess(false);
  }

  private async saveCookie(cookie: string): Promise<boolean> {
    try {
      const verification = await verifyLoginSession(cookie);
      if (verification.state === 'rejected') return false;
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await saveLoginCredentials(context, cookie, '');

      const flag: number = AppStorage.get<number>('refreshHomeFlag') ?? 0;
      AppStorage.setOrCreate('refreshHomeFlag', flag + 1);
      this.getUIContext().getPromptAction().showToast({ message: '登录成功！即将刷新个性化推荐' });
      return true;
    } catch (err) {
      logError(`保存Cookie失败: ${err}`);
      return false;
    }
  }

  /**
   * 带重试的 Cookie 提取：WebView 登录后 Cookie 写入 WebCookieManager 存在延迟
   * 重试 3 次，每次间隔 800ms，直到获取到有效 Cookie 或达到最大重试次数
   */
  private async extractCookie(retryCount: number = 3): Promise<void> {
    if (this.cookieExtracted) return;
    const domains: string[] = [
      'https://passport.bilibili.com',
      'https://www.bilibili.com',
      'https://api.bilibili.com',
      'https://space.bilibili.com',
      'https://live.bilibili.com'
    ];

    for (let attempt = 0; attempt < retryCount; attempt++) {
      if (this.cookieExtracted) return;
      try {
        // 合并所有域名的 Cookie，而不仅取最长的一个
        const cookieMap = new Map<string, string>();
        for (const domain of domains) {
          const cookie: string = await webview.WebCookieManager.fetchCookie(domain);
          if (cookie) {
            // 解析 cookie 字符串，按 key 去重合并
            const pairs = cookie.split(';');
            for (const pair of pairs) {
              const eqIdx = pair.indexOf('=');
              if (eqIdx > 0) {
                const key = pair.substring(0, eqIdx).trim();
                const value = pair.substring(eqIdx + 1).trim();
                if (key && value && value !== 'undefined') {
                  cookieMap.set(key, value);
                }
              }
            }
          }
        }
        // 重建合并后的 cookie 字符串
        const mergedParts: string[] = [];
        cookieMap.forEach((value, key) => mergedParts.push(`${key}=${value}`));
        const bestCookie = mergedParts.join('; ');
        const len = bestCookie.length;
        const hasSESSDATA: boolean = bestCookie.includes('SESSDATA');
        const hasJct: boolean = bestCookie.includes('bili_jct');
        const hasMid: boolean = bestCookie.includes('DedeUserID');
        logInfo(`Cookie提取[${attempt + 1}/${retryCount}]: 长度=${len}, SESSDATA=${hasSESSDATA}, bili_jct=${hasJct}, DedeUserID=${hasMid}`);

        if (hasLoginSession(bestCookie)) {
          this.cookieExtracted = true;
          if (await this.saveCookie(bestCookie)) {
            setTimeout(() => this.getUIContext().getRouter().back(), 800);
            return;
          }
          this.cookieExtracted = false;
        }
        // 等待后重试
        if (attempt < retryCount - 1) {
          await new Promise<void>(resolve => setTimeout(resolve, 800));
        }
      } catch (err) {
        logError(`提取Cookie失败[${attempt + 1}]: ${err}`);
      }
    }
    // 所有重试均失败，提示用户
    logWarn('Cookie提取失败：所有重试均未获取到有效Cookie');
    this.getUIContext().getPromptAction().showToast({ message: '登录检测超时，请确认已成功登录后手动返回', duration: 3000 });
  }

  private refreshPage(): void {
    this.errorMsg = '';
    this.isLoading = true;
    this.cookieExtracted = false;
    this.webController.refresh();
  }

  private goBack(): void {
    if (this.webController.accessBackward()) {
      this.webController.backward();
    } else {
      this.getUIContext().getRouter().back();
    }
  }



  build() {
    Stack() {
      PageWallpaper()
    Column() {
      // 顶部导航栏预留系统状态栏安全区
      PageHeader({ withTabs: false }) {
        Column() {
          Row() {
            Text('B站登录')
            .fontSize(18).fontColor(Color.White).fontWeight(FontWeight.Medium)
            .width('100%').textAlign(TextAlign.Start).margin({ left: 20 })
        }
        .width('100%')
        .height(56)
        .padding({ left: 8, right: 8 })
        }.width('100%').padding({ top: this.statusBarHeight })

      }

      // ── WebView / 错误内容 ──
      Stack() {
        if (this.errorMsg) {
          Column() {
            Text('⚠️').fontSize(48).fontColor('#FF6600')
            Text(this.errorMsg).fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
            Button('重试').width(100).height(36).margin({ top: 20 })
              .backgroundColor('#007DFF').onClick(() => this.refreshPage())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#000000')
        } else {
          Web({ src: 'https://passport.bilibili.com/login', controller: this.webController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .onLoadIntercept((event) => event.data.isMainFrame() && !isBilibiliHttpsUrl(event.data.getRequestUrl()))
            .userAgent('Mozilla/5.0 (Linux; HarmonyOS 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36')
            .onPageBegin((event) => {
              this.isLoading = true;
              const url: string = event?.url || '';
              if (isBilibiliHttpsUrl(url) && url.startsWith('https://www.bilibili.com/')) {
                logInfo(`检测到登录后跳转: ${url.substring(0, 80)}`);
                setTimeout(() => this.extractCookie(), 1000);
              }
            })
            .onProgressChange((event) => { this.progress = event.newProgress; })
            .onPageEnd(() => {
              this.isLoading = false;
              setTimeout(() => this.extractCookie(), 1500);
            })
            .onErrorReceive((event) => {
              const errorCode: number | undefined = event.error?.getErrorCode();
              logError(`WebView错误: code=${errorCode}, info=${event.error?.getErrorInfo()}`);
              if (errorCode === -3) {
                logWarn('页面跳转中止，正常现象');
                if (this.isLoading) this.isLoading = false;
              } else if (errorCode === -106) {
                this.errorMsg = '网络连接异常，请检查网络后重试';
                this.isLoading = false;
              } else {
                this.errorMsg = `加载失败: ${event.error?.getErrorInfo()}`;
                this.isLoading = false;
              }
            })
            .onHttpErrorReceive((event) => {
              logWarn(`HTTP错误: status=${event.response?.getResponseCode()}, url=${event.request?.getRequestUrl()}`);
            })
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('#FFFFFF')
        }

        if (this.isLoading && !this.errorMsg) {
          Column() {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
              .width('100%')
              .height(2)
              .color('#FF6600')
          }
          .width('100%')
          .position({ x: 0, y: 0 })
          .zIndex(2)
        }

        if (this.isLoading && !this.errorMsg && this.progress < 100) {
          Column() {
            LoadingProgress().width(48).height(48).color('#007DFF')
            Text('加载登录页...').fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0,0,0,0.7)')
          .position({ x: 0, y: 0 })
          .zIndex(3)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ bottom: this.navIndicatorHeight })
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : '#000000')
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
