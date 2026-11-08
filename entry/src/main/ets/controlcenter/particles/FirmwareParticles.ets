import { uiEffect } from '@kit.ArkGraphics2D';
import { ParticleGeometry } from '../model/ParticleGeometry';

@Component
export struct FirmwareParticles {
  @Prop surfaceWidth: number = 144;
  @Prop surfaceHeight: number = 64;
  @Prop uiValue: number = 0;
  @Prop opacityValue: number = 1;
  @Prop vx: number = 0;
  @Prop vy: number = 0;
  @Prop fields: RippleFieldOptions[] = [];
  @Prop horizontal: boolean = true;
  @Prop expanded: boolean = false;
  // EnvVm falls back to NORMAL if its private transparency query is unavailable.
  // NORMAL uses 0.6. Do not map public computing-power levels to TransparencyLevel.
  @Prop sliderRate: number = 0.6;
  private filter: uiEffect.Filter = uiEffect.createFilter();

  aboutToAppear(): void {
    try {
      this.filter = uiEffect.createFilter().hdrBrightnessRatio(2);
      console.info('CCLab particle HDR ratio=2 accepted; effective luminance depends on display pipeline');
    } catch (error) {
      console.error(`CCLab particle HDR unavailable: ${error}; using ratio=1`);
      this.filter = uiEffect.createFilter();
    }
  }

  @Builder
  private stream(reverse: boolean) {
    Particle({ particles: [{
      emitter: { particle: { type: ParticleType.POINT, config: { radius: 1.2 }, count: -1,
        lifetime: 1000, lifetimeRange: reverse ? 200 : 150 },
        emitRate: 200 * this.sliderRate, size: this.expanded ? [96, 96] : [138, 138],
        shape: ParticleEmitterShape.CIRCLE },
      color: { range: ['#FFFFFFFF', '#FFFFFFFF'] },
      velocity: { speed: [100, 250], angle: this.horizontal ?
        (reverse ? [170, 190] : [350, 370]) : (reverse ? [260, 280] : [80, 100]) },
      opacity: { range: [0, 1], updater: { type: ParticleUpdater.CURVE, config: [
        { from: 0.3, to: 0.8, startMillis: 0, endMillis: 400, curve: Curve.EaseIn },
        { from: 0.8, to: 0.3, startMillis: 400, endMillis: 600, curve: Curve.Rhythm }
      ] } }, scale: { range: [0, 1] }
    }] })
      .rippleFields(this.fields)
      .emitter([
        { index: 0, position: ParticleGeometry.emitter(this.uiValue, this.surfaceWidth,
          this.surfaceHeight, reverse, this.horizontal, this.expanded) },
        { index: 1, position: ParticleGeometry.emitter(this.uiValue, this.surfaceWidth,
          this.surfaceHeight, reverse, this.horizontal, this.expanded) }
      ])
      .velocityFields([{ velocity: { x: this.vx, y: this.vy }, region: {
        shape: DisturbanceFieldShape.RECT,
        position: ParticleGeometry.velocityPosition(this.surfaceWidth, this.surfaceHeight, this.horizontal),
        size: { width: this.surfaceWidth + 50, height: this.surfaceHeight + 50 }
      } }])
      .opacity(this.opacityValue)
      .foregroundFilter(this.filter)
      .width(this.horizontal ? 3 * this.surfaceWidth : this.surfaceWidth)
      .height(this.horizontal ? this.surfaceHeight : 3 * this.surfaceHeight)
      .borderRadius(30)
      .clip(reverse ? undefined : new Rect({
        width: this.horizontal ? this.surfaceWidth + this.uiValue : this.surfaceWidth,
        height: this.horizontal ? this.surfaceHeight : 2 * this.surfaceHeight - this.uiValue - 8
      }))
      .offset(reverse ? ParticleGeometry.offset(this.uiValue, this.surfaceWidth,
        this.surfaceHeight, this.horizontal) : undefined)
      .translate(this.horizontal ? { x: -this.surfaceWidth } : { y: -this.surfaceHeight })
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: this.horizontal ? Alignment.Start : Alignment.Top }) {
      this.stream(false)
      this.stream(true)
    }.width(this.surfaceWidth).height(this.surfaceHeight).clip(true).borderRadius(30)
      .hitTestBehavior(HitTestMode.None)
  }
}
