// Explicit emulator preview. This is not the original HDS light shader.
@Component
export struct UpperLightPreview {
  @Prop @Watch('paint') surfaceWidth: number = 64;
  @Prop @Watch('paint') surfaceHeight: number = 144;
  @Prop @Watch('paint') liquidY: number = 72;
  @Prop @Watch('paint') intensity: number = 0;
  @Prop @Watch('paint') gain: number = 0.4;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  private paint(): void {
    if (!this.ready) { return; }
    const c = this.context;
    c.clearRect(0, 0, this.surfaceWidth, this.surfaceHeight);
    const cut: number = Math.max(0, Math.min(this.surfaceHeight, this.liquidY));
    const strength: number = Math.max(0, Math.min(1, this.intensity)) * Math.max(0, Math.min(1, this.gain));
    if (cut <= 0 || strength <= 0) { return; }
    c.save();
    c.beginPath();
    c.rect(0, 0, this.surfaceWidth, cut);
    c.clip();
    // Keep a broad, soft field. The percentage affects only the dry region;
    // the existing liquid diffuse field and its radius remain unchanged.
    const glow: CanvasGradient = c.createRadialGradient(this.surfaceWidth / 2, cut, 0,
      this.surfaceWidth / 2, cut, 110);
    glow.addColorStop(0, `rgba(255,255,255,${0.16 * strength})`);
    glow.addColorStop(0.35, `rgba(255,255,255,${0.10 * strength})`);
    glow.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = glow;
    c.fillRect(0, 0, this.surfaceWidth, cut);
    c.restore();
  }

  build() {
    Canvas(this.context).width(this.surfaceWidth).height(this.surfaceHeight)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => { this.ready = true; this.paint(); })
      .onDisAppear(() => { this.ready = false; })
  }
}
