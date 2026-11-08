import { LiquidSurfaceLight } from './LiquidSurfaceLight';

@Component
export struct ProgressFill {
  @Prop @Watch('paint') fillWidth: number = 0;
  @Prop @Watch('paint') trackWidth: number = 128;
  @Prop @Watch('paint') shellWidth: number = 144;
  @Prop @Watch('paint') chosen: boolean = false;
  @Prop @Watch('paint') lightX: number = 72;
  @Prop @Watch('paint') lightY: number = 32;
  @Prop @Watch('paint') intensity: number = 0;
  @Prop @Watch('paint') vertical: boolean = false;
  @Prop @Watch('paint') surfaceHighlight: boolean = false;
  @Prop @Watch('paint') differentiatedFill: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  private paint(): void {
    if (!this.ready) { return; }
    const c = this.context;
    // Draw in the fixed track's coordinates. Percentage is a rectangular mask,
    // never a separate rounded white capsule.
    const canvasWidth: number = this.vertical ? 48 : this.trackWidth;
    const canvasHeight: number = this.vertical ? this.trackWidth : 48;
    c.clearRect(0, 0, canvasWidth, canvasHeight);
    const width: number = Math.max(0, Math.min(this.trackWidth, this.fillWidth));
    if (width <= 0) { return; }
    c.save();
    c.beginPath();
    c.rect(0, this.vertical ? canvasHeight - width : 0,
      this.vertical ? canvasWidth : width, this.vertical ? width : canvasHeight);
    c.clip();

    // Native getProgressColor() returns undefined in the sliderLight + isSysColor
    // branch: an opaque #FFFFFFFF rectangle is the wrong rendering path.
    // These alpha values approximate that material; they are not firmware constants.
    const base: CanvasGradient = c.createLinearGradient(0, 0, canvasWidth, canvasHeight);
    const separate: boolean = this.vertical && this.chosen && this.differentiatedFill;
    base.addColorStop(0, separate ? 'rgba(255,255,255,0.30)' :
      (this.chosen ? 'rgba(255,255,255,0.14)' : 'rgba(255,255,255,0.10)'));
    base.addColorStop(1, separate ? 'rgba(255,255,255,0.38)' :
      (this.chosen ? 'rgba(255,255,255,0.22)' : 'rgba(255,255,255,0.13)'));
    c.fillStyle = base;
    c.fillRect(0, 0, canvasWidth, canvasHeight);

    const strength: number = this.chosen ? Math.max(0, Math.min(1, this.intensity)) : 0;
    if (strength > 0.001) {
      // Invert the inner track's actual center-origin scale for the contact point.
      const scaleX: number = this.shellWidth / this.trackWidth;
      const localX: number = this.vertical ? this.lightX * 48 / 64 : this.lightX / scaleX;
      const localY: number = this.vertical ? this.lightY / scaleX : this.lightY * 48 / 64;
      const glow: CanvasGradient = c.createRadialGradient(localX, localY, 0, localX, localY, 60);
      glow.addColorStop(0, `rgba(255,255,255,${(separate ? 0.20 : 0.54) * strength})`);
      glow.addColorStop(0.32, `rgba(255,255,255,${(separate ? 0.10 : 0.28) * strength})`);
      glow.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = glow;
      c.fillRect(0, 0, canvasWidth, canvasHeight);
    }
    c.restore();
    if (this.surfaceHighlight && this.vertical) {
      // Same canvas and same parent scale as the fill: the highlight cannot lag
      // behind the liquid boundary or require a separate shell-space transform.
      LiquidSurfaceLight.paint(c, canvasWidth, canvasHeight, width,
        this.lightX * canvasWidth / 64, strength);
    }
  }

  build() {
    Canvas(this.context).width(this.vertical ? 48 : this.trackWidth)
      .height(this.vertical ? this.trackWidth : 48)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => { this.ready = true; this.paint(); })
      .onDisAppear(() => { this.ready = false; })
  }
}
