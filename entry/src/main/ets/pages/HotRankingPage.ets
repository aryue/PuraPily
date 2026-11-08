import { HeaderBackButton } from '../components/HeaderBackButton';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { HotSearchItem, fetchHotSearch } from '../api/HotSearchService';
import { logError } from '../utils/Logger';

@Entry
@Component
struct HotRankingPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('statusBarHeight') globalStatusBarHeight: number = 0;
  @State hotSearchItems: HotSearchItem[] = [];

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    const items = params ? params['items'] as HotSearchItem[] : [];
    if (items && items.length > 0) {
      this.hotSearchItems = items;
    } else {
      fetchHotSearch().then((items: HotSearchItem[]) => { this.hotSearchItems = items; });
    }
  }

  private openResults(keyword: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/SearchPage',
      params: { keyword: keyword, fromHotRanking: true }
    }).catch((error: Error) => logError('[HotRankingPage] 打开搜索结果失败', error));
  }

  /** 热搜标签文字颜色 */
  private getTagTextColor(tag: string): string {
    switch (tag) {
      case '新': return '#FFFFFF';
      case '热': return '#FFFFFF';
      case '梗': return '#FFFFFF';
      case '话题': return '#FFFFFF';
      case '活动': return '#FFFFFF';
      case '推荐': return '#FFFFFF';
      case '上升': return '#FFFFFF';
      default: return '#FFFFFF';
    }
  }

  /** 热搜标签背景色 */
  private getTagBgColor(tag: string): string {
    switch (tag) {
      case '新': return '#FFB526';  // 天蓝
      case '热': return '#FF5158';  // 粉红
      case '梗': return '#CE93D8';  // 浅紫
      case '话题': return '#4FC3F7'; // 浅蓝
      case '独家': return '#FFD54F'; // 琥珀
      case '直播': return '#FF7043'; // 橙红
      case '活动': return '#FFB74D'; // 橙色
      case '推荐': return '#4DB6AC'; // 青绿
      case '上升': return '#FF8A65'; // 珊瑚
      default: return '#90A4AE';    // 灰蓝
    }
  }

  @Builder
  HotWord(item: HotSearchItem) {
    Row({ space: 4 }) {
      Text(item.showName || item.keyword)
        .fontSize(14)
        .fontColor(this.isDarkMode ? '#E6E7E8' : '#18191C')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .flexShrink(1)
      if (item.iconUrl) {
        Image(item.iconUrl).width(16).height(16).objectFit(ImageFit.Contain).flexShrink(0)
      } else if (item.tagLabel) {
        Text(item.tagLabel)
          .fontSize(10)
          .fontColor(Color.White)
          .padding({ left: 3, right: 3 })
          .height(16)
          .borderRadius(2)
          .backgroundColor(this.getTagBgColor(item.tagLabel))
          .flexShrink(0)
      }
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Start)
  }



  build() {
    Stack() {
      PageWallpaper()
    Scroll() {
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          Image($r('app.media.search_ranking_header'))
            .width('100%').height(192).objectFit(ImageFit.Cover)
          Column() {
            Column().height(48 + (this.hideStatusBar ? 0 : this.globalStatusBarHeight))
            Text('bilibili 热搜').fontSize(42).fontWeight(FontWeight.Bold)
              .fontColor(Color.White).margin({ top: 12 })
          }
          .width('100%')
        }
        .width('100%').height(192)
        Column() {
          ForEach(this.hotSearchItems, (item: HotSearchItem, index: number) => {
            Row({ space: 10 }) {
              Text(`${index + 1}`)
                .fontSize(16).fontStyle(FontStyle.Italic).fontWeight(FontWeight.Bold)
                .fontColor(index === 0 ? '#FFB526' : index === 1 ? '#86A8FF' :
                  index === 2 ? '#E4A47A' : (this.isDarkMode ? '#C4C8CB' : '#9499A0'))
                .width(24)
              this.HotWord(item)
              Image($r('app.media.chevron_right')).width(14).height(14)
                .fillColor('#85898E')
            }
            .width('100%').height(58)
            .border({ width: { bottom: 0.5 }, color: this.isDarkMode ? '#2A2D30' : '#EEEEEE' })
            .onClick(() => this.openResults(item.keyword))
          }, (item: HotSearchItem) => item.keyword)
        }
        .width('100%').padding({ left: 20, right: 20, bottom: 32 })
        .borderRadius({ topLeft: 16, topRight: 16 })
        .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
        .margin({ top: -16 })
      }
      .width('100%')
    }
    .width('100%').height('100%')
    .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Column() {
            PageHeader() {
            Row() {
              HeaderBackButton({ iconColor: Color.White, onBack: () => this.getUIContext().getRouter().back() })
              Blank()
            }
            .width('100%').height(48 + (this.hideStatusBar ? 0 : this.globalStatusBarHeight))
            .padding({ left: 20, right: 20, top: this.hideStatusBar ? 0 : this.globalStatusBarHeight })
            }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

}
