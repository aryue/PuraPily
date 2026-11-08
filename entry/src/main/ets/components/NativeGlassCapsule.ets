import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Keep controls inside the material's title scope so native touch effects reach it. */
@Component
export struct NativeGlassCapsule {
  @Prop capsuleWidth: number = 104;
  @Prop capsuleHeight: number = 46;
  @Prop cornerRadius: number = -1;
  @Prop overlayContent: boolean = false;
  // Scrollable menus must keep their ancestor Scroll in the gesture chain.
  @Prop allowAncestorGestures: boolean = false;
  @Prop nativePressFeedback: boolean = false;
  // Menus share one stationary Navigation title instead of moving nested scopes.
  @Prop withinMaterialScope: boolean = false;
  onActivate?: () => void;
  @BuilderParam content: () => void;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
  }

  @Builder
  private interactiveTitle() {
    this.materialControl(true)
  }

  @Builder
  private materialControl(titleInset: boolean) {
    Stack({ alignContent: Alignment.TopStart }) {
      Button({ type: ButtonType.Normal, stateEffect: this.nativePressFeedback }) {
        if (!this.overlayContent) { this.content() }
      }
        .width(this.capsuleWidth).height(this.capsuleHeight)
        .padding(0).backgroundColor(Color.Transparent)
        .position({ x: titleInset ? 16 : 0, y: titleInset ? 16 : 0 })
        .borderRadius(this.cornerRadius >= 0 ? this.cornerRadius : this.capsuleHeight / 2)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          colorInvert: true, applyShadow: true, interactive: true,
          lightEffect: { color: Color.White }
        }))
        .hitTestBehavior(this.allowAncestorGestures ? HitTestMode.Default : HitTestMode.BLOCK_HIERARCHY)
        .onTouch((_event: TouchEvent) => {})
        .onClick(() => this.onActivate?.())
        .id('profile-header-actions-material')
    }.width(this.capsuleWidth + (titleInset ? 32 : 0)).height(this.capsuleHeight + (titleInset ? 32 : 0))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported) {
        if (this.withinMaterialScope) {
          this.materialControl(false)
        } else {
          Navigation() { Column().height(0) }
            .width(this.capsuleWidth + 32).height(this.capsuleHeight + 32)
            .position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
            .title({ builder: this.interactiveTitle, height: this.capsuleHeight + 32 }, {
              barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
            })
            .hideBackButton(true).hideToolBar(true)
            .backgroundColor(Color.Transparent).clip(false)
        }
        if (this.overlayContent) {
          // Keep glyphs out of the material title's resizing render cache. The
          // underlying native Button remains the material and touch receiver.
          Stack() { this.content() }
            .width(this.capsuleWidth).height(this.capsuleHeight)
            .hitTestBehavior(HitTestMode.Transparent)
        }
      } else {
        Row() { this.content() }
          .width(this.capsuleWidth).height(this.capsuleHeight)
          .borderRadius(this.cornerRadius >= 0 ? this.cornerRadius : this.capsuleHeight / 2)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)
          .onClick(() => this.onActivate?.())
      }
    }.width(this.capsuleWidth).height(this.capsuleHeight).clip(false)
  }
}
