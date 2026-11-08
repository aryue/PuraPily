import { HeaderBackButton } from '../components/HeaderBackButton';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { WhisperPage } from './WhisperPage';

@Entry
@Component
struct MessagesPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;



  build() {
    Stack() {
      PageWallpaper()
    Stack({ alignContent: Alignment.TopStart }) {

      WhisperPage({ contentTopInset: this.statusBarHeight + 48 }).height('100%')

      Column() {
      PageHeader({ withTabs: false }) {
        Row() {
          HeaderBackButton({ onBack: () => this.getUIContext().getRouter().back() }).margin({ left: 4 })
          Text('消息').fontSize(18).fontWeight(FontWeight.Medium).layoutWeight(1).textAlign(TextAlign.Center)
            .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          Blank().width(44)
        }.height(48 + this.statusBarHeight).width('100%').padding({ top: this.statusBarHeight })
      }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }
    .width('100%').height('100%').backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
