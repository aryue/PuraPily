import { ProgressFill } from './ProgressFill';
import { curves } from '@kit.ArkUI';
import { OriginalProgressBlend } from './OriginalFillMaterial';

// Original progress clips a full-track gradient; it has no system material.
@Component
export struct OriginalProgress {
  @Prop fill: number = 0;
  @Prop track: number = 128;
  @Prop lightX: number = 32;
  @Prop lightY: number = 72;
  @Prop intensity: number = 0;
  @State private nativeBlend: boolean = false;
  aboutToAppear(): void { this.nativeBlend = OriginalProgressBlend.available(); }
  private curve: ICurve = curves.cubicBezierCurve(0.67, 0, 0.7, 1.04);

  private stops(): Array<[ResourceColor, number]> {
    const colors: Array<[ResourceColor, number]> = [['rgba(0,0,0,0.2)', 0], ['rgba(0,0,0,0.2)', 0.6]];
    for (let i: number = 1; i <= 20; i++) {
      const alpha: number = 0.2 + 0.8 * this.curve.interpolate(i / 20);
      colors.push([`rgba(0,0,0,${alpha})`, 0.6 + i * 0.02]);
    }
    return colors;
  }

  build() {
    if (this.nativeBlend) {
    Stack({ alignContent: Alignment.Top }) {
      Column().width(48).height(this.track)
        .linearGradient({ direction: GradientDirection.Top, colors: this.stops() })
        .attributeModifier(new OriginalProgressBlend())
        .hitTestBehavior(HitTestMode.None)
      Column().width(48).height(1.2)
        .linearGradient({ direction: GradientDirection.Top, colors: [[Color.Transparent, 0], [Color.Black, 1]] })
        .attributeModifier(new OriginalProgressBlend())
        .hitTestBehavior(HitTestMode.None)
    }.width(48).height(Math.max(0, Math.min(this.track, this.fill))).clip(true)
      .hitTestBehavior(HitTestMode.None)
    } else {
      ProgressFill({ fillWidth: this.fill, trackWidth: this.track, shellWidth: 144,
        chosen: true, vertical: true, surfaceHighlight: false, differentiatedFill: true,
        lightX: this.lightX, lightY: this.lightY, intensity: this.intensity })
    }
  }
}
