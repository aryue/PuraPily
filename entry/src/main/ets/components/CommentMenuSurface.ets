import { uiMaterial } from '@kit.ArkUI';
import { GlassMaterial } from '../utils/GlassMaterial';

/** Each surface owns its material and keeps touch targets inside the native title scope. */
@Component
export struct CommentMenuSurface {
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 56;
  @Prop radius: number = 16;
  @Prop bottomExtension: number = 0;
  @Prop interactive: boolean = true;
  @Prop followTouchLight: boolean = false;
  @BuilderParam content: () => void;
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;
  private touchMaterial: uiMaterial.ImmersiveMaterial | null = null;

  aboutToAppear(): void {
    this.supported = GlassMaterial.supported();
    if (this.supported && this.followTouchLight) this.touchMaterial = GlassMaterial.create('touch', this.dark);
  }

  @Builder
  private nativeSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: this.interactive ? Alignment.Center : Alignment.TopStart }) { this.content() }
        .width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension)
        .position({ x: 16, y: 16 }).borderRadius(this.radius)
        .id(this.interactive ? 'comment-menu-button-material' : 'comment-menu-panel-material')
        .systemMaterial(GlassMaterial.create(this.interactive ? 'control' : 'panel', this.dark))
      if (this.followTouchLight) {
        // A fixed, native touch frame shares events with the scroll and controls.
        // Its optical output is hidden; the menu materials receive its light.
        Row().width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension)
          .position({ x: 16, y: 16 }).systemMaterial(this.touchMaterial).opacity(0.001)
          .hitTestBehavior(HitTestMode.Transparent)
          .onTouch((_event: TouchEvent) => {})
      }
    }.width(this.surfaceWidth + 32).height(this.surfaceHeight + this.bottomExtension + 32)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported && this.surfaceWidth > 0) {
        Navigation() { Column().height(0) }
          .width(this.surfaceWidth + 32).height(this.surfaceHeight + this.bottomExtension + 32)
          .position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
          .title({ builder: this.nativeSurface, height: this.surfaceHeight + this.bottomExtension + 32 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
      } else {
        Stack({ alignContent: this.interactive ? Alignment.Center : Alignment.TopStart }) { this.content() }
          .width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension).borderRadius(this.radius)
          .backgroundBlurStyle(GlassMaterial.fallbackBlur(this.interactive ? 'control' : 'panel'))
          .backgroundColor(GlassMaterial.fallbackColor(this.interactive ? 'control' : 'panel', this.dark))
      }
    }.width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension).clip(false)
  }
}
