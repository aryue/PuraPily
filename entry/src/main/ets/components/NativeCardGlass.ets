import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** A measured, non-interactive title scope, matching ping's ImmersiveCard. */
@Component
export struct NativeCardGlass {
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 0;
  @Prop radius: number = 4;
  @Prop clearGlass: boolean = false;
  @Prop otherCards: boolean = false;
  @StorageLink('isDarkMode') dark: boolean = true;
  @StorageLink('videoCardGlassThickness') thickness: string = 'thin';
  @StorageLink('videoCardGlassTint') tintEnabled: boolean = true;
  @StorageLink('otherCardGlassThickness') otherThickness: string = 'thick';
  @StorageLink('otherCardGlassTint') otherTintEnabled: boolean = true;
  @StorageLink('nativeCardLightActive') externalLightActive: boolean = false;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    try {
      if (deviceInfo.apiAvailable('26.0.0')) this.supported = uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
  }

  private materialStyle(): uiMaterial.ImmersiveStyle {
    if (this.clearGlass) return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    const thickness = this.otherCards ? this.otherThickness : this.thickness;
    if (thickness === 'ultra-thick') return uiMaterial.ImmersiveStyle.ULTRA_THICK;
    if (thickness === 'thick') return uiMaterial.ImmersiveStyle.THICK;
    if (thickness === 'ultra-thin') return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    if (thickness === 'regular') return uiMaterial.ImmersiveStyle.REGULAR;
    return uiMaterial.ImmersiveStyle.THIN;
  }

  private edgePath(): string {
    const w = vp2px(this.surfaceWidth);
    const h = vp2px(this.surfaceHeight);
    const r = Math.min(vp2px(this.radius), w / 2, h / 2);
    const inset = Math.min(vp2px(2), w / 4, h / 4);
    const inner = Math.max(0, r - inset);
    return `M ${r} 0 H ${w-r} A ${r} ${r} 0 0 1 ${w} ${r} V ${h-r} A ${r} ${r} 0 0 1 ${w-r} ${h} H ${r} A ${r} ${r} 0 0 1 0 ${h-r} V ${r} A ${r} ${r} 0 0 1 ${r} 0 Z ` +
      `M ${r} ${inset} A ${inner} ${inner} 0 0 0 ${inset} ${r} V ${h-r} A ${inner} ${inner} 0 0 0 ${r} ${h-inset} H ${w-r} A ${inner} ${inner} 0 0 0 ${w-inset} ${h-r} V ${r} A ${inner} ${inner} 0 0 0 ${w-r} ${inset} H ${r} Z`;
  }

  @Builder
  private materialSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width(this.surfaceWidth).height(this.surfaceHeight)
        .position({ x: 16, y: 16 }).borderRadius(this.radius)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: this.materialStyle(),
          colorInvert: this.clearGlass,
          materialColor: !this.clearGlass && (this.otherCards ? this.otherTintEnabled : this.tintEnabled) ? (this.dark ? '#2017181A' : '#20FFFFFF') : Color.Transparent,
          applyShadow: false, interactive: false, lightEffect: null
        }))
      if (this.otherCards || this.externalLightActive) {
        // Other-card receivers must also exist on pages without the main tab bar.
        // Native controls supply incident light; the card never creates a touch source.
        // Same native rim-only layer as ping. The center never receives the light effect.
        Column().width(this.surfaceWidth).height(this.surfaceHeight)
          .position({ x: 16, y: 16 }).borderRadius(this.radius)
          .systemMaterial(new uiMaterial.ImmersiveMaterial({
            style: this.materialStyle(),
            colorInvert: this.clearGlass,
            materialColor: !this.clearGlass && (this.otherCards ? this.otherTintEnabled : this.tintEnabled) ? (this.dark ? '#2017181A' : '#20FFFFFF') : Color.Transparent,
            applyShadow: false, interactive: false, lightEffect: { color: Color.White }
          }))
          .clipShape(new Path().commands(this.edgePath())).opacity(0.45)
      }
    }.width(this.surfaceWidth + 32).height(this.surfaceHeight + 32)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        Navigation() { Column().height(0) }
          .id('native-card-material-scope')
          .width(this.surfaceWidth + 32).height(this.surfaceHeight + 32)
          .position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
          .title({ builder: this.materialSurface, height: this.surfaceHeight + 32 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true)
          .backgroundColor(Color.Transparent).clip(false)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      } else if (!this.supported) {
        Column().width(this.surfaceWidth).height(this.surfaceHeight).borderRadius(this.radius)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      }
    }.width(this.surfaceWidth).height(this.surfaceHeight).clip(false)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}
