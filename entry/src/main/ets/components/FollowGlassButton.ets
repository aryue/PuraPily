import { GlassMaterial } from '../utils/GlassMaterial';
import { NativeGlassSurface } from './NativeGlassSurface';

/** Independent interactive material. The native pressed light follows the current button color. */
@Component
export struct FollowGlassButton {
  @Prop followed: boolean = false;
  @Prop buttonWidth: Length = 76;
  @Prop buttonHeight: number = 30;
  @Prop accent: ResourceColor = '#D34E7E';
  @Prop textColor: ResourceColor = '#FFFFFF';
  @Prop fill: ResourceColor = '#D34E7E';
  @Prop fontSize: number = 13;
  onActivate: () => void = () => {};
  @State private measuredWidth: number = 76;
  @State private supported: boolean = false;

  aboutToAppear(): void {
    if (typeof this.buttonWidth === 'number') this.measuredWidth = this.buttonWidth;
    this.supported = GlassMaterial.supported();
  }

  private materialTint(): ResourceColor {
    // Keep the existing hue while allowing the native material and its pressed light to show through.
    if (typeof this.fill === 'string' && /^#[0-9a-fA-F]{6}$/.test(this.fill)) return '#66' + this.fill.slice(1);
    return this.fill;
  }

  @Builder
  private label() {
    Text(this.followed ? '已关注' : '＋ 关注').fontSize(this.fontSize).fontColor(this.textColor)
      .maxLines(1).textAlign(TextAlign.Center).width('100%')
  }

  @Builder
  private materialButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      NativeGlassSurface({
        surfaceWidth: this.measuredWidth, surfaceHeight: this.buttonHeight,
        radius: this.buttonHeight / 2, kind: 'accent', dark: true,
        supported: true, attachPress: true, insetX: 16, insetY: 16,
        useTint: true, tintColor: this.materialTint(),
        useLight: true, lightColor: this.accent,
        onActivate: () => this.onActivate()
      }) { this.label() }
    }.width(this.measuredWidth + 32).height(this.buttonHeight + 32)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.supported) {
        Navigation() { Column().height(0) }
          .width(this.measuredWidth + 32).height(this.buttonHeight + 32).position({ x: -16, y: -16 })
          .mode(NavigationMode.Stack)
          .title({ builder: this.materialButton, height: this.buttonHeight + 32 }, {
            barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
          })
          .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
      } else {
        Row() { this.label() }.width('100%').height(this.buttonHeight)
          .borderRadius(this.buttonHeight / 2).backgroundColor(this.fill)
          .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN).onClick(() => this.onActivate())
      }
    }.width(this.buttonWidth).height(this.buttonHeight).clip(false)
      .id('follow-glass-button').accessibilityText(this.followed ? '已关注' : '关注')
      .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
        if (Number(size.width) > 0) this.measuredWidth = Number(size.width);
      })
  }
}
