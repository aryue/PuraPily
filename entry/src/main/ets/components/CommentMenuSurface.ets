import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

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
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
    if (this.supported && this.followTouchLight) this.touchMaterial = new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN, applyShadow: false,
      interactive: false, lightEffect: { color: Color.White }
    });
  }

  @Builder
  private nativeSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: this.interactive ? Alignment.Center : Alignment.TopStart }) { this.content() }
        .width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension)
        .position({ x: 16, y: 16 }).borderRadius(this.radius)
        .id(this.interactive ? 'comment-menu-button-material' : 'comment-menu-panel-material')
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: this.interactive ? uiMaterial.ImmersiveStyle.ULTRA_THIN : uiMaterial.ImmersiveStyle.THICK,
          materialColor: this.interactive ? (this.dark ? '#301C2022' : '#30FFFFFF') :
            (this.dark ? '#661C2022' : '#88F2F3F5'),
          applyShadow: false, interactive: this.interactive,
          lightEffect: this.interactive ? { color: Color.White } : null
        }))
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
          .backgroundBlurStyle(this.interactive ? BlurStyle.COMPONENT_ULTRA_THIN : BlurStyle.COMPONENT_THICK)
          .backgroundColor(this.interactive ? (this.dark ? '#80202528' : '#80FFFFFF') : (this.dark ? '#E6202528' : '#E6F2F3F5'))
      }
    }.width(this.surfaceWidth).height(this.surfaceHeight + this.bottomExtension).clip(false)
  }
}
