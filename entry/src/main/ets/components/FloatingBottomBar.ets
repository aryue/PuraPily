import deviceInfo from '@ohos.deviceInfo';
import { motion } from '@kit.MultimodalAwarenessKit';
import { curves, CommonModifier } from '@kit.ArkUI';
import { GlassMaterial } from '../utils/GlassMaterial';

/** Keep the material and its contents on the same animated surface. */
@Component
export struct FloatingBottomBar {
  @Prop activeIndex: number = 0;
  @Prop hidden: boolean = false;
  @Prop @Watch('updateGripSubscription') pageActive: boolean = true;
  @StorageLink('bottomBarSmartGrip') @Watch('updateGripSubscription') smartGrip: boolean = false;
  @StorageLink('isLandscape') @Watch('updateGripSubscription') isLandscape: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @State immersive: boolean = false;
  @State barWidth: number = 264;
  @State gripOffset: number = 0;
  private viewportWidth: number = 0;
  private hand: motion.HoldingHandStatus = motion.HoldingHandStatus.UNKNOWN_STATUS;
  private gripCallback: ((data: motion.HoldingHandStatus) => void) | null = null;
  private touching: boolean = false;
  private mounted: boolean = false;
  onSelect: (index: number) => void = () => {};

  aboutToAppear(): void {
    this.immersive = GlassMaterial.supported();
    this.mounted = true;
    this.updateGripSubscription();
  }

  aboutToDisappear(): void {
    AppStorage.setOrCreate('nativeCardLightActive', false);
    this.mounted = false;
    this.stopGripSubscription();
  }

  private stopGripSubscription(): void {
    if (!this.gripCallback) return;
    try {
      motion.off('holdingHandChanged', this.gripCallback);
    } catch (_) { }
    this.gripCallback = null;
    this.hand = motion.HoldingHandStatus.UNKNOWN_STATUS;
  }

  private updateGripSubscription(): void {
    if (!this.mounted) return;
    if (!this.smartGrip || !this.pageActive || this.isLandscape) {
      this.stopGripSubscription();
      this.updateGripPosition();
      return;
    }
    if (this.gripCallback) return;
    const callback = (hand: motion.HoldingHandStatus): void => {
      if (!this.mounted || !this.smartGrip || !this.pageActive || this.isLandscape || this.hand === hand) return;
      this.hand = hand;
      this.updateGripPosition();
    };
    try {
      motion.on('holdingHandChanged', callback);
      this.gripCallback = callback;
    } catch (_) {
      // Unsupported devices keep the centered navigation bar.
      this.hand = motion.HoldingHandStatus.UNKNOWN_STATUS;
      this.updateGripPosition();
    }
  }

  private updateGripPosition(): void {
    if (this.touching) return;
    const travel = Math.max(0, (this.viewportWidth - this.barWidth - 16) / 2 - 12);
    let offset = 0;
    if (this.smartGrip && this.pageActive && !this.isLandscape) {
      if (this.hand === motion.HoldingHandStatus.LEFT_HAND_HELD) offset = -travel;
      else if (this.hand === motion.HoldingHandStatus.RIGHT_HAND_HELD) offset = travel;
    }
    if (this.gripOffset !== offset) this.gripOffset = offset;
  }

  private barMaterial(): CommonModifier {
    const modifier = new CommonModifier().borderRadius(28).clip(false).backgroundColor(Color.Transparent);
    if (this.immersive && deviceInfo.apiAvailable('26.0.0')) {
      return modifier.systemMaterial(GlassMaterial.create('capsule', true));
    }
    return modifier.backgroundBlurStyle(BlurStyle.COMPONENT_THICK);
  }

  private itemColor(index: number): ResourceColor {
    if (this.activeIndex === index) {
      return this.isDarkMode ? $r('app.color.floating_nav_selected_dark') : $r('app.color.floating_nav_selected_light');
    }
    // Keep the special system resource intact for native material color inversion.
    // Selected pink remains an app resource and keeps its original color.
    if (this.immersive) return $r('sys.color.font_primary');
    return this.isDarkMode ? $r('app.color.floating_nav_foreground_dark') : $r('app.color.floating_nav_foreground_light');
  }

  @Builder
  Item(label: string, icon: Resource, selectedIcon: Resource, index: number) {
    Column({ space: 2 }) {
      Image(this.activeIndex === index ? selectedIcon : icon).width(24).height(24)
        .fillColor(this.itemColor(index))
      Text(label).fontSize(12).fontWeight(this.activeIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.itemColor(index))
    }.width('100%').height(56).justifyContent(FlexAlign.Center)
      .accessibilityText(label).accessibilitySelected(this.activeIndex === index)
  }

  build() {
    Row() {
    Row() {
    Tabs({ index: this.activeIndex, barPosition: BarPosition.End, barModifier: this.barMaterial() }) {
      TabContent() { Column().height(0) }.tabBar(this.Item('首页', $r('app.media.ref_home'), $r('app.media.ref_home_selected'), 0))
      TabContent() { Column().height(0) }.tabBar(this.Item('动态', $r('app.media.ref_dynamic'), $r('app.media.ref_dynamic_selected'), 1))
      TabContent() { Column().height(0) }.tabBar(this.Item('我的', $r('app.media.ref_profile'), $r('app.media.ref_profile_selected'), 2))
    }
    .scrollable(false)
    // Keep tab children interactive while excluding the content below this bar.
    .hitTestBehavior(this.hidden ? HitTestMode.None : HitTestMode.BLOCK_HIERARCHY)
    .barWidth(this.barWidth).barHeight(56).width(this.barWidth).height(56)
    .barFloatingStyle({
      barWidth: { smallBarWidth: this.barWidth, mediumBarWidth: this.barWidth, largeBarWidth: this.barWidth },
      barSideMargin: 0, barBottomMargin: 0, maskColor: Color.Transparent, maskHeight: 0
    })
    // Observe the actual native tab surface; child tabs can consume the host Row touch.
    .onTouch((event: TouchEvent) => {
      AppStorage.setOrCreate('nativeCardLightActive', event.type === TouchType.Down || event.type === TouchType.Move);
      if (event.type === TouchType.Down) this.touching = true;
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touching = false;
        this.updateGripPosition();
      }
    })
    .onTabBarClick((index: number) => this.onSelect(index))
    .clip(false)
    // Shrink the complete glass surface inside a separately translated host.
    // Ease-in preserves its size and contrast during the initial downward motion.
    .scale({ x: this.hidden ? 0 : 1, y: this.hidden ? 0 : 1, centerX: '50%', centerY: '50%' })
    .opacity(this.hidden ? 0 : 1)
    .animation({ duration: 280, curve: this.hidden ? Curve.EaseIn : Curve.EaseOut })
    }
    .width('64%').height(72).constraintSize({ maxWidth: 280 })
    .padding(8).justifyContent(FlexAlign.Center)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.barWidth = Math.max(0, Number(size.width) - 16);
      this.updateGripPosition();
    })
    .margin({ bottom: Math.max(0, this.navIndicatorHeight - 8) })
    .translate({ y: this.hidden ? 64 : 0 })
    .animation({ duration: 280, curve: Curve.FastOutSlowIn })
    .hitTestBehavior(this.hidden ? HitTestMode.None : HitTestMode.Default)
    }
    .width('100%').justifyContent(FlexAlign.Center)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      this.viewportWidth = Number(size.width);
      this.updateGripPosition();
    })
    .translate({ x: this.gripOffset })
    .animation({ curve: curves.interpolatingSpring(0, 1, 200, 17) })
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
