import { HOME_SEARCH_ROW_HEIGHT, homeHeaderTopInset } from '../utils/HomeHeaderLayout';

/** 首页与动态共用的刷新提示，避让各自的悬浮顶栏。 */
@Component
export struct HomeRefreshIndicator {
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('homeSearchRowHeight') homeSearchRowHeight: number = HOME_SEARCH_ROW_HEIGHT;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @Prop refreshing: boolean = false;
  @Prop ready: boolean = false;
  @Prop color: string = '#FB7299';
  @Prop topInset: number = -1;

  private headerHeight(): number {
    return this.topInset >= 0 ? this.topInset :
      homeHeaderTopInset(this.statusBarHeight, this.hideStatusBar, this.homeSearchRowHeight);
  }

  build() {
    Column({ space: 4 }) {
      LoadingProgress()
        .width(28)
        .height(28)
        .color(this.color)
      Text(this.refreshing ? '刷新中' : '松开刷新')
        .fontSize(12)
        .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
    }
    .width('100%')
    .height(60)
    .id('feed-refresh-indicator')
    .justifyContent(FlexAlign.Center)
    .translate({ y: this.headerHeight() })
    // 达到刷新距离后再显示，回弹结束前也不会露到顶栏内。
    .opacity(this.ready || this.refreshing ? 1 : 0)
    .accessibilityLevel(this.ready || this.refreshing ? 'auto' : 'no-hide-descendants')
    .hitTestBehavior(HitTestMode.None)
  }
}
