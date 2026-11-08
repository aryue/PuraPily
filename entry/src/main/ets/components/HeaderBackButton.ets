import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';

/** Top-bar navigation uses native interactive glass independently of content-card settings. */
@Component
export struct HeaderBackButton {
  @Prop hdrUiRatio: number = 1;
  @Prop iconColor: ResourceColor | undefined = undefined;
  onBack: () => void = () => {};
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
  }

  @Builder
  private arrow() {
    Image($r('app.media.ref_back')).width(22).height(22)
      .fillColor(this.iconColor ?? (this.dark ? '#F2F4F8' : '#18191C'))
      .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private nativeButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack() { this.arrow() }
        .width(40).height(40).position({ x: 16, y: 16 }).borderRadius(20)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: this.dark ? '#301C2022' : '#30FFFFFF',
          applyShadow: false, interactive: true, lightEffect: { color: Color.White }
        }))
        .onTouch((_event: TouchEvent) => {})
        .onClick(() => this.onBack())
    }.width(72).height(72)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported) {
        Navigation() { Column().height(0) }
          .width(72).height(72).position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
          .title({ builder: this.nativeButton, height: 72 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
      } else {
        Stack() { this.arrow() }.width(40).height(40).borderRadius(20)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN)
          .backgroundColor(this.dark ? '#80202528' : '#80FFFFFF')
          .onClick(() => this.onBack())
      }
    }.width(40).height(40).clip(false).id('header-back-glass')
      .accessibilityText('返回').accessibilityLevel('yes')
  }
}
