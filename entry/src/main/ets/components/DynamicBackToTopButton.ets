import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** A fixed native touch frame preserves incident light while the visual button follows the gesture. */
@Component
export struct DynamicBackToTopButton {
  @Prop @Watch('refreshMaterial') color: ResourceColor = Color.White;
  @Prop hostWidth: number = 0;
  @Prop hostHeight: number = 0;
  @Prop buttonX: number = 0;
  @Prop buttonY: number = 0;
  @Prop shown: boolean = false;
  @Prop buttonScale: number = 1;
  @StorageLink('isDarkMode') @Watch('refreshMaterial') dark: boolean = true;
  onButtonTouch: (event: TouchEvent) => void = () => {};
  @State private supported: boolean = false;
  @State private material: uiMaterial.ImmersiveMaterial | null = null;
  @State private touchMaterial: uiMaterial.ImmersiveMaterial | null = null;
  @State private pressed: boolean = false;

  aboutToAppear(): void {
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) {}
    this.refreshMaterial();
  }

  @Builder
  private icon() {
    Image($r('app.media.chevron_down')).width(20).height(20)
      .fillColor(this.color).rotate({ angle: 180 }).hitTestBehavior(HitTestMode.None)
  }

  private touchRegion(event: TouchEvent): HitTestMode {
    if (!this.shown || event.touches.length === 0) return HitTestMode.None;
    const point = event.touches[0];
    // The scope fills the viewport, but only the real 48vp button owns a touch stream.
    return point.x >= this.buttonX && point.x <= this.buttonX + 48 &&
      point.y >= this.buttonY && point.y <= this.buttonY + 48
      ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None;
  }

  private refreshMaterial(): void {
    if (!this.supported) { this.material = null; this.touchMaterial = null; return; }
    // Keep the source object alive throughout drag frames; replacing it loses its native touch light.
    this.material = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: this.dark ? '#301C2022' : '#30FFFFFF',
      applyShadow: false, interactive: false, lightEffect: { color: this.color }
    });
    this.touchMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false, interactive: false, lightEffect: { color: this.color }
    });
  }

  @Builder
  private nativeButton() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {
      // Ordinary layout offsets also move the native light's layout origin.
      Row().width(1).height(this.buttonY).flexShrink(0)
      Row() {
        Row().width(this.buttonX).height(1).flexShrink(0)
      Button({ type: ButtonType.Normal, stateEffect: false }) { this.icon() }.width(48).height(48)
        .padding(0).backgroundColor(Color.Transparent).borderRadius(24)
        .systemMaterial(this.material)
        .backgroundBlurStyle(this.supported ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
        .scale({ x: this.shown ? this.buttonScale * (this.pressed ? 0.96 : 1) : 0,
          y: this.shown ? this.buttonScale * (this.pressed ? 0.96 : 1) : 0 })
        .opacity(this.shown ? 1 : 0)
        .animation({ duration: 160, curve: Curve.EaseOut })
        .hitTestBehavior(HitTestMode.None)
        .id('dynamic-backtop-light-source').accessibilityText('回到顶部')
      }.width(this.hostWidth).height(48).flexShrink(0)
    }.width(this.hostWidth).height(this.hostHeight).alignItems(HorizontalAlign.Start)
      .hitTestBehavior(HitTestMode.None)
      // A stationary native touch frame keeps the light's coordinates stable as the visual button moves.
      Row().width(this.hostWidth).height(this.hostHeight)
        .systemMaterial(this.touchMaterial).opacity(this.shown && this.pressed ? 0.001 : 0)
        .hitTestBehavior(this.shown ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
        .onTouchIntercept((event: TouchEvent) => this.touchRegion(event))
        .onTouch((event: TouchEvent) => {
          this.pressed = event.type === TouchType.Down || event.type === TouchType.Move;
          this.onButtonTouch(event);
        })
    }.width(this.hostWidth).height(this.hostHeight)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported) {
        Navigation() { Column().height(0) }
          // Keep the native light's coordinate scope stationary. Only the material target moves.
          .width(this.hostWidth).height(this.hostHeight).position({ x: 0, y: 0 }).mode(NavigationMode.Stack)
          .title({ builder: this.nativeButton, height: this.hostHeight }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
          .hitTestBehavior(this.shown ? HitTestMode.Transparent : HitTestMode.None)
          .onTouchIntercept((event: TouchEvent) => this.touchRegion(event))
      } else {
        this.nativeButton()
      }
    }.width(this.hostWidth).height(this.hostHeight).clip(false)
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
