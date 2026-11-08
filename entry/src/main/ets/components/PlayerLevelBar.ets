import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { NativeSlider } from '../controlcenter/components/NativeSlider';
import { AdjustmentMotion } from '../controlcenter/model/AdjustmentMotion';

/** ControlCenterLab 1.0.28 display-only adapter. Playback owns all input and system writes. */
@Component
export struct PlayerLevelBar {
  @Prop @Watch('syncValue') progress: number = 0;
  @Prop kind: string = 'volume';
  @Prop headphones: boolean = false;
  @Prop headphoneIcon: string = 'headphones_fill';
  @Prop barWidth: number = 64;
  @Prop barHeight: number = 144;
  @Prop adjusting: boolean = false;
  @Prop adjustmentMotion: AdjustmentMotion | undefined = undefined;
  @State private value: number = 0;
  @State private emulatorPreview: boolean = false;

  aboutToAppear(): void {
    this.value = Math.max(0, Math.min(1, this.progress));
    this.emulatorPreview = deviceInfo.productModel.toLowerCase().includes('emulator');
  }

  private syncValue(): void { this.value = Math.max(0, Math.min(1, this.progress)); }

  @Builder
  private slider(kind: string) {
    NativeSlider({ value: $value, kind: kind, vertical: true, wide: false,
      brightnessMotion: true, touchEnabled: false, jellyEnabled: true,
      particlesEnabled: true, lightEnabled: true, immersiveEnabled: true,
      immersiveStyle: 0, originalLight: true, levelLight: true, upperLightGain: 0.4,
      emulatorLightPreview: this.emulatorPreview, pressing: this.adjusting, adjusting: this.adjusting,
      adjustmentMotion: this.adjustmentMotion, headphones: this.headphones,
      headphoneIcon: this.headphoneIcon })
  }

  @Builder
  private status() {
    Row() {
      if (this.kind === 'volume') { this.slider('volume'); }
      else { this.slider('sun'); }
    }.width(136).height(216).justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      Stack() {
      WithTheme({ colorMode: ThemeColorMode.DARK }) {
        Navigation() { Column().height(0) }
          .title({ builder: this.status, height: 216 },
            { backgroundColor: Color.Transparent, systemMaterial: uiMaterial.Material.empty })
          .titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true)
          .mode(NavigationMode.Stack)
          .width(136).height(216).backgroundColor(Color.Transparent)
          .hitTestBehavior(HitTestMode.None)
      }
      }.width(136).height(216).position({ x: (this.barWidth - 136) / 2, y: (this.barHeight - 216) / 2 })
    }.width(this.barWidth).height(this.barHeight)
      .id(`player-${this.kind}-bar`).hitTestBehavior(HitTestMode.None)
      .accessibilityText(`${this.kind === 'volume' ? '音量' : '亮度'} ${Math.round(this.value * 100)}%`)
  }
}
