import { HdsNavigation, HdsNavigationTitleMode, DividerShowType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { gradientTitleBarStyle } from '../utils/HeaderStyle';

/** The same HDS title renderer and style used by WatchHistoryPage. */
@Component
export struct HistoryHeaderBlur {
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 0;
  @StorageLink('isDarkMode') dark: boolean = true;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      HdsNavigation() { Column().height(0) }
        .id('history-header-blur')
        .titleBar({
          avoidLayoutSafeArea: true,
          padding: { start: LengthMetrics.vp(0), end: LengthMetrics.vp(0) },
          style: gradientTitleBarStyle(this.dark),
          content: { title: { mainTitle: '' }, divider: { showType: DividerShowType.OFF } }
        })
        .titleMode(HdsNavigationTitleMode.MINI).hideBackButton(true)
        .mode(NavigationMode.Stack)
        // Keep rendering space for the native fade; HeaderStyle controls its visible range.
        .width(this.surfaceWidth).height(this.surfaceHeight + 64).clip(false)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
    }.width(this.surfaceWidth).height(this.surfaceHeight).clip(false)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}
