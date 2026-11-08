import { uiMaterial } from '@kit.ArkUI';
import { GlassMaterial, GlassKind } from '../utils/GlassMaterial';

/** Independent thick header material, hosted in a real Navigation title scope. */
@Component
export struct NativeHeaderGlass {
  @Prop surfaceWidth: number = 0;
  @Prop materialStyle: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THICK;
  @Prop hideBottomEdge: boolean = false;
  @Prop surfaceHeight: number = 44;
  @Prop scopeId: string = 'header-native-scope';
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    this.supported = GlassMaterial.supported();
  }

  private kind(): GlassKind {
    return this.materialStyle === uiMaterial.ImmersiveStyle.REGULAR ? 'headerRegular' : 'header';
  }

  @Builder
  private surface() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Place native rims outside the visible header; seamless panels also extend the bottom rim.
      Column().width(this.surfaceWidth + 64).height(this.surfaceHeight + (this.hideBottomEdge ? 64 : 32))
        .position({ x: 16, y: 16 })
        .systemMaterial(GlassMaterial.create(this.kind(), this.dark))
    }.width(this.surfaceWidth + 96).height(this.surfaceHeight + 64)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported && this.surfaceWidth > 0) {
        Navigation() { Column().height(0) }
          .id(this.scopeId)
          .width(this.surfaceWidth + 96).height(this.surfaceHeight + 64)
          .position({ x: -48, y: -48 }).mode(NavigationMode.Stack)
          .title({ builder: this.surface, height: this.surfaceHeight + 64 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      } else if (!this.supported) {
        Column().width(this.surfaceWidth).height(this.surfaceHeight)
          .backgroundBlurStyle(GlassMaterial.fallbackBlur(this.kind()))
          .backgroundColor(GlassMaterial.fallbackColor(this.kind(), this.dark))
      }
    }.width(this.surfaceWidth).height(this.surfaceHeight).clip(true)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}
