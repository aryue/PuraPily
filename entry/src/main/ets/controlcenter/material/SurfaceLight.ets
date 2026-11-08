@Component
export struct SurfaceLight {
  @Prop @Watch('paint') surfaceWidth: number = 144;
  @Prop @Watch('paint') lightX: number = 72;
  @Prop @Watch('paint') lightY: number = 32;
  @Prop @Watch('paint') intensity: number = 0;
  @Prop @Watch('paint') vertical: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ready: boolean = false;

  private capsulePath(): void {
    const c = this.context;
    const right: number = this.surfaceWidth - 32;
    c.beginPath();
    c.moveTo(32, 0.5);
    c.lineTo(right, 0.5);
    c.arc(right, 32, 31.5, -Math.PI / 2, Math.PI / 2);
    c.lineTo(32, 63.5);
    c.arc(32, 32, 31.5, Math.PI / 2, 3 * Math.PI / 2);
    c.closePath();
  }

  private paint(): void {
    if (!this.ready) { return; }
    const c = this.context;
    c.clearRect(0, 0, this.vertical ? 64 : this.surfaceWidth, this.vertical ? this.surfaceWidth : 64);
    // Paint the same capsule in a local axis; vertical maps its start to the bottom.
    const axisLight: number = this.vertical ? this.surfaceWidth - this.lightY : this.lightX;
    const crossLight: number = this.vertical ? this.lightX : this.lightY;
    c.save();
    if (this.vertical) {
      c.translate(0, this.surfaceWidth);
      c.rotate(-Math.PI / 2);
    }
    c.save();
    this.capsulePath();
    c.clip();
    // Fallback only: an optical approximation, not the private HDS shader.
    const body: CanvasGradient = c.createLinearGradient(0, 0, 0, 64);
    body.addColorStop(0, 'rgba(255,255,255,0.12)');
    body.addColorStop(0.35, 'rgba(255,255,255,0)');
    body.addColorStop(0.8, 'rgba(0,0,0,0.018)');
    body.addColorStop(1, 'rgba(0,0,0,0.055)');
    c.fillStyle = body;
    c.fillRect(0, 0, this.surfaceWidth, 64);
    const strength: number = Math.max(0, Math.min(1, this.intensity));
    if (strength > 0.001) {
      // The original point source uses Z=110. Use that reach for the SDR substitute.
      const halo: CanvasGradient = c.createRadialGradient(axisLight, crossLight, 0, axisLight, crossLight, 110);
      halo.addColorStop(0, `rgba(255,255,255,${0.34 * strength})`);
      halo.addColorStop(0.35, `rgba(255,255,255,${0.17 * strength})`);
      halo.addColorStop(1, 'rgba(255,255,255,0)');
      c.fillStyle = halo;
      c.fillRect(0, 0, this.surfaceWidth, 64);
    }
    c.restore();

    // A thin edge response, sampled over the real capsule contour.
    // Intensity depends on the contact position and remains lit for a stationary finger.
    const straight: number = this.surfaceWidth - 64;
    const perimeter: number = 2 * straight + 2 * Math.PI * 31.5;
    const samples: number = Math.ceil(perimeter / 3);
    for (let index: number = 0; index < samples; index++) {
      const distance: number = perimeter * index / samples;
      const nextDistance: number = perimeter * (index + 1) / samples;
      const point: number[] = this.contour(distance, straight);
      const next: number[] = this.contour(nextDistance, straight);
      const dx: number = point[0] - axisLight;
      const dy: number = point[1] - crossLight;
      const falloff: number = Math.pow(110 / Math.sqrt(dx * dx + dy * dy + 110 * 110), 3);
      const edgeBase: number = 0.12 + 0.12 * (1 - point[1] / 64);
      const alpha: number = Math.min(0.85, edgeBase + 0.48 * strength * falloff);
      c.strokeStyle = `rgba(255,255,255,${alpha})`;
      c.lineWidth = 0.8;
      c.beginPath();
      c.moveTo(point[0], point[1]);
      c.lineTo(next[0], next[1]);
      c.stroke();
    }
    c.restore();
  }

  private contour(distance: number, straight: number): number[] {
    const radius: number = 31.5;
    const arc: number = Math.PI * radius;
    if (distance <= straight) { return [32 + distance, 0.5]; }
    distance -= straight;
    if (distance <= arc) {
      const angle: number = distance / radius - Math.PI / 2;
      return [this.surfaceWidth - 32 + radius * Math.cos(angle), 32 + radius * Math.sin(angle)];
    }
    distance -= arc;
    if (distance <= straight) { return [this.surfaceWidth - 32 - distance, 63.5]; }
    distance -= straight;
    const angle: number = distance / radius + Math.PI / 2;
    return [32 + radius * Math.cos(angle), 32 + radius * Math.sin(angle)];
  }

  build() {
    Canvas(this.context).width(this.vertical ? 64 : this.surfaceWidth)
      .height(this.vertical ? this.surfaceWidth : 64)
      .hitTestBehavior(HitTestMode.None)
      .onReady(() => { this.ready = true; this.paint(); })
      .onDisAppear(() => { this.ready = false; })
  }
}
