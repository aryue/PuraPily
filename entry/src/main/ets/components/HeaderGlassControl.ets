import { GlassMaterial } from '../utils/GlassMaterial';
import { NativeGlassSurface } from './NativeGlassSurface';

/** Header actions share the unified glass surface without reading content-card preferences. */
@Component
export struct HeaderGlassControl {
  @Prop controlWidth: number = 40;
  @Prop controlHeight: number = 40;
  @Prop controlId: string = 'header-action-glass';
  @Prop label: string = '';
  @Prop actionEnabled: boolean = true;
  @BuilderParam content: () => void;
  onActivate: () => void = () => {};
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    this.supported = GlassMaterial.supported();
  }

  @Builder
  private glassButton(insideScope: boolean) {
    NativeGlassSurface({
      surfaceWidth: this.controlWidth, surfaceHeight: this.controlHeight,
      radius: this.controlHeight / 2, kind: 'control', dark: this.dark,
      supported: insideScope, attachPress: true,
      insetX: insideScope ? 16 : 0, insetY: insideScope ? 16 : 0,
      onActivate: () => { if (this.actionEnabled) this.onActivate(); }
    }) { this.content() }
  }

  @Builder
  private nativeButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.glassButton(true)
    }.width(this.controlWidth + 32).height(this.controlHeight + 32)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported) {
        Navigation() { Column().height(0) }
          .width(this.controlWidth + 32).height(this.controlHeight + 32).position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
          .title({ builder: this.nativeButton, height: this.controlHeight + 32 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
      } else {
        this.glassButton(false)
      }
    }.width(this.controlWidth).height(this.controlHeight).clip(false).id(this.controlId)
      .opacity(this.actionEnabled ? 1 : 0.4)
      .accessibilityText(this.label).accessibilityLevel('yes')
  }
}
