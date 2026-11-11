import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageSurface } from '../components/PageSurface';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
/**
 * 关于软件页面
 */
import { bundleManager, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  checkForUpdate, UpdateCheckResult, UpdateCheckStatus,
  GITHUB_PROJECT_URL, GITHUB_RELEASE_PAGE_URL
} from '../services/UpdateChecker';

/** 检查更新 UI 状态机。 */
enum UpdateUiState {
  IDLE = 0,
  CHECKING = 1,
  LATEST = 2,
  AVAILABLE = 3,
  ERROR = 4
}

@Entry
@Component
struct AboutPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  /** 版本不在页面里写死：运行时读取 AppScope/app.json5 打包后的 versionName。 */
  @State appVersion: string = '';
  @State updateState: number = UpdateUiState.IDLE;
  @State latestVersion: string = '';
  @State releaseNotes: string = '';
  @State releaseUrl: string = GITHUB_RELEASE_PAGE_URL;
  @State updateError: string = '';
  // TODO: 替换为实际项目地址和 Issues 地址。
  private readonly projectUrl: string = GITHUB_PROJECT_URL;
  private readonly feedbackUrl: string = 'https://github.com/aryue/PuraPily/issues/';

  aboutToAppear(): void {
    this.loadAppVersion();
    // 进入关于页即视为「已看过更新提示」，清掉「我的」页红点；随后静默复核（12h 缓存内不实发请求）。
    AppStorage.setOrCreate('hasNewVersion', false);
    this.runUpdateCheck(false);
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private async runUpdateCheck(force: boolean): Promise<void> {
    if (this.updateState === UpdateUiState.CHECKING) {
      return;
    }
    this.updateState = UpdateUiState.CHECKING;
    try {
      const result: UpdateCheckResult = await checkForUpdate(this.hostContext(), force);
      this.applyCheckResult(result);
    } catch (err) {
      this.updateState = UpdateUiState.ERROR;
      this.updateError = '检查失败，请检查网络后重试';
    }
  }

  private applyCheckResult(result: UpdateCheckResult): void {
    this.latestVersion = result.latestVersion;
    this.releaseNotes = result.releaseNotes;
    this.releaseUrl = result.releaseUrl;
    if (result.status === UpdateCheckStatus.UPDATE_AVAILABLE) {
      this.updateState = UpdateUiState.AVAILABLE;
    } else if (result.status === UpdateCheckStatus.UP_TO_DATE) {
      this.updateState = UpdateUiState.LATEST;
    } else {
      this.updateState = UpdateUiState.ERROR;
      this.updateError = '检查失败，请检查网络后重试';
    }
  }

  /** 可用状态下点行 = 前往下载；其余状态点行 = 重新检查。 */
  private handleUpdateRowTap(): void {
    if (this.updateState === UpdateUiState.AVAILABLE) {
      this.openExternalUrl(this.releaseUrl);
      return;
    }
    this.runUpdateCheck(true);
  }

  private updateSubtitle(): string {
    switch (this.updateState) {
      case UpdateUiState.CHECKING:
        return '检查中…';
      case UpdateUiState.LATEST:
        return '当前已是最新版本';
      case UpdateUiState.AVAILABLE:
        return `发现新版本 v${this.latestVersion}，点击前往下载`;
      case UpdateUiState.ERROR:
        return this.updateError;
      default:
        return '点击检查是否有新版本';
    }
  }

  private async loadAppVersion(): Promise<void> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = bundleInfo.versionName;
    } catch (err) {
      console.error(`[AboutPage] getBundleInfoForSelf failed: ${(err as BusinessError).message}`);
    }
  }

  private async openExternalUrl(url: string): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: url,
        entities: ['entity.system.browsable'] });
    } catch (_) {
      this.getUIContext().getPromptAction().showToast({ message: '打开浏览器失败，请重试' });
    }
  }

  @Builder
  ExternalLink(title: string, subtitle: string, url: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
        Text(subtitle).fontSize(12).fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(18).fontColor('#8E8E93')
    }.width('100%').constraintSize({ minHeight: 72 }).padding(16)
      .onClick(() => this.openExternalUrl(url))
  }

  @Builder
  UpdateCard() {
    Column() {
      PageSurface({ radius: 14 }) {
        Column() {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('检查更新')
                .fontSize(16)
                .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
              Text(this.updateSubtitle())
                .fontSize(12)
                .fontColor(this.updateState === UpdateUiState.AVAILABLE ? '#D34E7E'
                  : (this.isDarkMode ? '#C9CDD3' : '#606773'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            if (this.updateState === UpdateUiState.CHECKING) {
              LoadingProgress().width(20).height(20).color('#8E8E93')
            } else {
              Text('›').fontSize(18).fontColor('#8E8E93')
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 64 })
          .padding(16)
          .onClick(() => this.handleUpdateRowTap())

          if (this.updateState === UpdateUiState.AVAILABLE && this.releaseNotes.length > 0) {
            Divider().strokeWidth(1).color(this.isDarkMode ? '#2A2D31' : '#F0F1F2')
              .margin({ left: 16, right: 16 })
            // 更新说明过长时在卡片内滚动，不做截断。
            Scroll() {
              Text(this.releaseNotes)
                .fontSize(12)
                .fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
                .width('100%')
            }
            .constraintSize({ maxHeight: 220 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .align(Alignment.Top)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 4 })
          }
          if (this.updateState === UpdateUiState.AVAILABLE) {
            Row() {
              Text('重新检查')
                .fontSize(13)
                .fontColor(this.isDarkMode ? '#6FA8F5' : '#237CBD')
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            .padding({ left: 16, right: 16, top: 8, bottom: 14 })
            .onClick(() => this.runUpdateCheck(true))
          }
        }.width('100%')
      }
    }.width('100%').margin({ top: 20 })
  }

  build() {
    Stack() {
      PageWallpaper()
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column() {

      // 主体内容
      Column() {
        // 应用图标
        Image($r('app.media.icon'))
          .width(80)
          .height(80)
          .borderRadius(20)
          .margin({ bottom: 20 })

        // 应用名称
        Text('PuraPily')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#1C1C1E')
          .margin({ bottom: 8 })

        // 版本号（来自 app.json5；未就绪时用空格占位，保持下方内容不跳动）
        Text(this.appVersion.length > 0 ? 'v' + this.appVersion : ' ')
          .fontSize(14)
          .fontColor(this.isDarkMode ? '#8E8E93' : '#8E8E93')
          .margin({ bottom: 4 })

        // 检查更新（GitHub Release 比对）
        this.UpdateCard()

        Column() {
          PageSurface({ radius: 14 }) {
            Column() {
              this.ExternalLink('项目地址', this.projectUrl, this.projectUrl)
              this.ExternalLink('反馈与建议', 'Github Issues', this.feedbackUrl)
            }.width('100%')
          }
        }.width('100%').margin({ top: 24, bottom: 24 })

//         // ⭐ DASH PoC 验证入口（验证后可整体移除）
//         Column() {
//           PageSurface({ radius: 14 }) {
//             Row() {
//               Text('播放实验')
//                 .fontSize(16)
//                 .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
//               Blank()
//               Text('IJK 双轨播放')
//                 .fontSize(12)
//                 .fontColor('#8E8E93')
//             }
//             .width('100%')
//             .padding(16)
//             .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/IjkLab' }))
//           }
//         }
//         .width('100%')
//         .margin({ top: 12 })
//
//         Column() {
//         PageSurface({ radius: 14 }) {
//         Column() {
//           Row() {
//             Text('DASH PoC 验证')
//               .fontSize(16)
//               .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
//             Blank()
//             Text('单播放器 DASH 双流')
//               .fontSize(12)
//               .fontColor('#8E8E93')
//               .margin({ right: 8 })
//           }
//           .width('100%')
//           .padding(16)
//         }
//         .width('100%')
//         .borderRadius(14)
//         .onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/DashPocPage' }))
//
//         }
//         }.width('100%')
//         .margin({ top: 12 })
//

      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)


            }.width('100%').padding({ top: this.statusBarHeight + 72 })
      }.width('100%').height('100%').scrollBar(BarState.Off)
      Column() {
      PageHeader({ withTabs: false }) {
        Row() {
          HeaderBackButton({ onBack: () => this.getUIContext().getRouter().back() })

          Text('关于软件')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .margin({ left: 16 })

          Blank()
        }
        .width('100%')
        .padding({ top: 16 + this.statusBarHeight, left: 16, right: 16, bottom: 16 })
      }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .height('100%')
    .width('100%')
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
