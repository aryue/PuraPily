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

@Entry
@Component
struct AboutPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  /** 版本不在页面里写死：运行时读取 AppScope/app.json5 打包后的 versionName。 */
  @State appVersion: string = '';
  // TODO: 替换为实际项目地址和 Issues 地址。
  private readonly projectUrl: string = 'https://github.com/aryue/PuraPily';
  private readonly feedbackUrl: string = 'https://github.com/aryue/PuraPily/issues/';

  aboutToAppear(): void {
    this.loadAppVersion();
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
