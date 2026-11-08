import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

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
    try {
      this.supported = deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) {}
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
      Row() { this.label() }.width(this.measuredWidth).height(this.buttonHeight)
        .position({ x: 16, y: 16 }).borderRadius(this.buttonHeight / 2)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN, materialColor: this.materialTint(),
          applyShadow: false, interactive: true, lightEffect: { color: this.accent }
        }))
        .onTouch((_event: TouchEvent) => {})
        .onClick(() => this.onActivate())
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
