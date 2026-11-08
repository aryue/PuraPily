import { GlassMaterial } from '../utils/GlassMaterial';
import { NativeGlassSurface } from './NativeGlassSurface';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';

/** Top-bar navigation uses the unified glass surface independently of content-card settings. */
@Component
export struct HeaderBackButton {
  @Prop hdrUiRatio: number = 1;
  @Prop iconColor: ResourceColor | undefined = undefined;
  onBack: () => void = () => {};
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    this.supported = GlassMaterial.supported();
  }

  @Builder
  private arrow() {
    Image($r('app.media.ref_back')).width(22).height(22)
      .fillColor(this.iconColor ?? (this.dark ? '#F2F4F8' : '#18191C'))
      .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private glassButton(insideScope: boolean) {
    NativeGlassSurface({
      surfaceWidth: 40, surfaceHeight: 40, radius: 20, kind: 'control', dark: this.dark,
      supported: insideScope, attachPress: true,
      insetX: insideScope ? 16 : 0, insetY: insideScope ? 16 : 0,
      onActivate: () => this.onBack()
    }) { this.arrow() }
  }

  @Builder
  private nativeButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.glassButton(true)
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
        this.glassButton(false)
      }
    }.width(40).height(40).clip(false).id('header-back-glass')
      .accessibilityText('返回').accessibilityLevel('yes')
  }
}
