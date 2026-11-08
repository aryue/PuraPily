import { HeaderBackButton } from '../components/HeaderBackButton';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct SettingsPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;



  build() {
    Stack() {
      PageWallpaper()
    Stack({ alignContent: Alignment.TopStart }) {
      ProfilePage({ settingsOnly: true })
      PageHeader({ withTabs: false }) {
        Row({ space: 10 }) {
          HeaderBackButton({ onBack: () => this.getUIContext().getRouter().back() })
          Text('设置').fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
        }.height(44).width('100%').padding({ left: 8, top: this.statusBarHeight })
          .height(44 + this.statusBarHeight)
      }

    }
    .width('100%').height('100%').backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
