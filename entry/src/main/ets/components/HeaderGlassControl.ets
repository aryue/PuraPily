import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Header actions share the back button material without reading content-card preferences. */
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
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
  }

  @Builder
  private nativeButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() { this.content() }
        .width(this.controlWidth).height(this.controlHeight).position({ x: 16, y: 16 }).borderRadius(this.controlHeight / 2)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: this.dark ? '#301C2022' : '#30FFFFFF',
          applyShadow: false, interactive: true, lightEffect: { color: Color.White }
        }))
        .onTouch((_event: TouchEvent) => {})
        .onClick(() => { if (this.actionEnabled) this.onActivate(); })
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
        Stack() { this.content() }.width(this.controlWidth).height(this.controlHeight).borderRadius(this.controlHeight / 2)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
          .backgroundColor(this.dark ? '#80202528' : '#80FFFFFF')
          .onClick(() => { if (this.actionEnabled) this.onActivate(); })
      }
    }.width(this.controlWidth).height(this.controlHeight).clip(false).id(this.controlId)
      .opacity(this.actionEnabled ? 1 : 0.4)
      .accessibilityText(this.label).accessibilityLevel('yes')
  }
}
