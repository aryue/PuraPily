import { HeaderBackButton } from '../components/HeaderBackButton';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { ProfilePage } from './ProfilePage';
import { AppNavigation, SettingsSectionRouteParams } from '../services/AppNavigation';
import { ContentFilterPage } from './ContentFilterPage';

/** 设置页二级分区（外观与交互 / 播放设置），卡片实现复用 ProfilePage 的 settingsOnly 分支。 */
@Component
export struct SettingsSectionPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  /** 分区标识，由一级页 pushUrl 的 params.section 决定。 */
  @State section: string = 'appearance';
  @State sectionTitle: string = '外观与交互';
  @Prop navParams: SettingsSectionRouteParams | null = null;

  aboutToAppear(): void {
    const params = this.navParams;
    if (params !== null && params.section === 'playback') {
      this.section = 'playback';
      this.sectionTitle = '播放设置';
    } else if (params !== null && params.section === 'filter') {
      this.section = 'filter';
      this.sectionTitle = '内容过滤';
    }
  }

  build() {
    Stack() {
      PageWallpaper()
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.section === 'filter') {
          ContentFilterPage()
        } else {
          ProfilePage({ settingsOnly: true, settingsSection: this.section })
        }
        PageHeader({ withTabs: false }) {
          Row({ space: 10 }) {
            HeaderBackButton({ onBack: () => { AppNavigation.back(); } })
            Text(this.sectionTitle).fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          }.height(44).width('100%').padding({ left: 8, top: this.statusBarHeight })
            .height(44 + this.statusBarHeight)
        }
      }
      .width('100%').height('100%')
      .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
