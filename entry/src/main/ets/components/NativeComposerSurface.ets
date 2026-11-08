import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Same static material recipe as the comment action menu; input behavior stays in the content. */
@Component
export struct NativeComposerSurface {
  @Prop allCorners: boolean = false;
  @Prop active: boolean = true;
  @Prop rounding: number = 12;
  @Prop lowerRounding: number = 0;
  @BuilderParam content: () => void;
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private supported: boolean = false;
  @State private surfaceWidth: number = 0;
  @State private surfaceHeight: number = 0;

  aboutToAppear(): void {
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) { this.supported = false; }
  }

  @Builder
  private materialSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width(this.surfaceWidth).height(this.surfaceHeight)
        .position({ x: 16, y: 16 }).borderRadius(this.allCorners ? this.rounding : {
          topLeft: this.rounding, topRight: this.rounding, bottomLeft: this.lowerRounding, bottomRight: this.lowerRounding })
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK,
          materialColor: this.dark ? '#661C2022' : '#88F2F3F5',
          applyShadow: false, interactive: false, lightEffect: null
        }))
    }.width(this.surfaceWidth + 32).height(this.surfaceHeight + 32)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.active && this.supported && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        // The oversized title scope paints outside this measured frame; it must not enlarge FIT_CONTENT sheets.
        Stack({ alignContent: Alignment.TopStart }) {
        Navigation() { Column().height(0) }
          .id('composer-menu-material')
          .width(this.surfaceWidth + 32).height(this.surfaceHeight + 32)
          .position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
          .title({ builder: this.materialSurface, height: this.surfaceHeight + 32 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false).focusable(false)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        }.width(this.surfaceWidth).height(this.surfaceHeight).position({ x: 0, y: 0 }).clip(false)
          .hitTestBehavior(HitTestMode.None).id('composer-material-frame')
      }
      Column() { this.content() }
        .width('100%').height(LayoutPolicy.fixAtIdealSize)
        .backgroundColor(!this.active || this.supported ? Color.Transparent : (this.dark ? '#171A1D' : '#FFFFFF'))
        .borderRadius(this.allCorners ? this.rounding : {
          topLeft: this.rounding, topRight: this.rounding, bottomLeft: this.lowerRounding, bottomRight: this.lowerRounding })
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width);
          const height = Number(size.height);
          if (width > 0 && Math.abs(width - this.surfaceWidth) > 0.5) this.surfaceWidth = width;
          if (height > 0 && Math.abs(height - this.surfaceHeight) > 0.5) this.surfaceHeight = height;
        })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize)
  }
}
