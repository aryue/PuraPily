import displaySync from '@ohos.graphics.displaySync';
import { ExperimentalLevelBarParticleField } from '../utils/ExperimentalLevelBarParticleField';

/** 仅供独立效果页使用；复现参考视频的玻璃、液面和粒子；不修改系统音量或屏幕亮度。 */
@Component
export struct ExperimentalLevelBar {
  @Prop initialValue: number = 0.5;
  @Prop kind: string = 'volume';
  @Prop @Watch('resize') length: number = 162;
  @Prop thickness: number = 72;
  @Prop @Watch('activeChanged') active: boolean = true;
  onValueChange: (value: number) => void = () => {};
  @State private pressed: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private iconContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private iconReady: boolean = false;
  private iconValue: number = 0.5;
  private field: ExperimentalLevelBarParticleField = new ExperimentalLevelBarParticleField(72, 162, 0.5);
  private sync: displaySync.DisplaySync | null = null;
  private ready: boolean = false;
  private running: boolean = false;
  private lastTime: number = 0;
  private settleUntil: number = 0;
  private dragPosition: number = 0;
  private pointerId: number = -1;
  private initialDragValue: number = 0;
  @State private percent: number = 50;
  private dragValue: number = 0;
  private lastMove: number = 0;

  aboutToAppear(): void {
    this.field = new ExperimentalLevelBarParticleField(this.thickness, this.length, this.initialValue, this.kind === 'volume' ? 7429 : 19427);
    this.percent = Math.round(this.initialValue * 100);
    this.iconValue = this.field.value;
    this.sync = displaySync.create();
    this.sync.setExpectedFrameRateRange({ min: 30, max: 120, expected: 60 });
    this.sync.on('frame', this.onFrame);
  }

  aboutToDisappear(): void {
    this.ready = false;
    this.iconReady = false;
    this.stop();
    this.sync?.off('frame', this.onFrame);
    this.sync = null;
  }

  private resize(): void {
    // 旋转只调整画布坐标；保留数值、粒子和同一组件。
    const previousLength: number = this.field.height;
    for (const p of this.field.particles) p.y *= this.length / previousLength;
    this.field.height = this.length;
    if (this.pressed) this.release(true);
    this.redraw();
  }

  private redraw(): void { if (this.ready) this.draw(); }

  private activeChanged(): void {
    if (!this.active) { this.pressed = false; this.pointerId = -1; this.field.end(); this.stop(); }
    else if (this.ready) {
      this.draw();
      if (this.field.particles.length > 0) { this.settleUntil = Date.now() + 700; this.start(); }
    }
  }

  private onFrame = (_frame: displaySync.IntervalInfo): void => {
    const now: number = Date.now();
    const dt: number = Math.min(0.034, Math.max(0.001, (now - this.lastTime) / 1000));
    this.lastTime = now;
    this.field.step(dt);
    this.iconValue += (this.field.value - this.iconValue) * (1 - Math.exp(-dt * 28));
    if (Math.abs(this.iconValue - this.field.value) < 0.0001) this.iconValue = this.field.value;
    this.draw();
    if (!this.pressed && now >= this.settleUntil && this.field.particles.length === 0) this.stop();
  };

  private start(): void {
    if (!this.running && this.ready && this.active) {
      this.lastTime = Date.now(); this.running = true; this.sync?.start();
    }
  }

  private stop(): void { this.sync?.stop(); this.running = false; }

  private updateValue(value: number, seconds: number): void {
    this.field.setValue(value, seconds);
    this.percent = Math.round(this.field.value * 100);
    this.onValueChange(this.field.value);
    this.draw();
  }

  private release(cancel: boolean): void {
    if (cancel) this.updateValue(this.initialDragValue, 0.016);
    this.pressed = false;
    this.pointerId = -1;
    this.field.end();
    this.settleUntil = Date.now() + 700;
    this.start();
  }

  private touch(event: TouchEvent): void {
    event.stopPropagation();
    if (!this.active) return;
    if (event.type === TouchType.Down && !this.pressed && event.changedTouches.length > 0) {
      const point = event.changedTouches[0];
      this.pointerId = point.id;
      this.initialDragValue = this.field.value;
      this.dragPosition = point.windowY;
      this.lastMove = Date.now();
      this.pressed = true;
      // 抓取时保留原数值，亮度和音量都从当前值相对拖动。
      this.dragValue = this.field.value;
      this.field.begin();
      this.start();
    } else if (event.type === TouchType.Move && this.pressed) {
      const point = event.touches.find((item: TouchObject) => item.id === this.pointerId);
      if (!point) return;
      const now: number = Date.now();
      const distance: number = this.dragPosition - point.windowY;
      this.updateValue(this.dragValue + distance / this.length, (now - this.lastMove) / 1000);
      this.lastMove = now;
    } else if (event.type === TouchType.Cancel && this.pressed) {
      this.release(true);
    } else if (event.type === TouchType.Up && this.pressed &&
      event.changedTouches.some((item: TouchObject) => item.id === this.pointerId)) {
      this.release(false);
    }
  }

  private pill(inset: number = 0): void {
    const c = this.context;
    const left: number = inset; const top: number = inset;
    const right: number = this.thickness - inset; const bottom: number = this.length - inset;
    const r: number = (right - left) / 2;
    c.beginPath(); c.moveTo(left, top + r);
    c.arc(left + r, top + r, r, Math.PI, Math.PI * 2);
    c.lineTo(right, bottom - r);
    c.arc(left + r, bottom - r, r, 0, Math.PI);
    c.closePath();
  }

  private dot(x: number, y: number, radius: number, opacity: number): void {
    const c = this.context;
    c.globalAlpha = opacity;
    c.fillStyle = '#FFFFFF'; c.beginPath(); c.arc(x, y, radius, 0, Math.PI * 2); c.fill();
  }

  private draw(): void {
    if (!this.ready) return;
    const c = this.context;
    const w: number = this.thickness;
    const h: number = this.length;
    const surface: number = (1 - this.field.value) * h;
    const glow: number = this.field.illumination;
    c.clearRect(0, 0, w, h);
    c.save();
    c.save(); this.pill(); c.clip();
    // 完整调节底色与图标转暗同步，黑背景、低值或零值仍能看清深色图标。
    const iconContrast: number = Math.min(1, glow * 2.8);
    c.fillStyle = `rgba(218,224,236,${iconContrast * 0.43})`;
    c.fillRect(0, 0, w, h);
    const glass = c.createLinearGradient(0, 0, w, h);
    glass.addColorStop(0, 'rgba(178,187,210,0.22)');
    glass.addColorStop(0.5, 'rgba(96,108,132,0.15)');
    glass.addColorStop(1, 'rgba(189,199,218,0.24)');
    c.fillStyle = glass; c.fillRect(0, 0, w, h);
    if (surface < h) {
      // 静止时为内缩的暗淡填充；调节时扩展到外壳并点亮边界。
      const inset: number = 8 * (1 - glow);
      c.save();
      c.translate(inset, inset);
      c.scale((w - inset * 2) / w, (h - inset * 2) / h);
      this.pill(); c.clip();
      const fill = c.createLinearGradient(0, surface, 0, Math.min(h, surface + 100));
      fill.addColorStop(0, `rgba(255,255,255,${0.12 + glow * 0.84})`);
      fill.addColorStop(0.12, `rgba(242,245,250,${0.12 + glow * 0.60})`);
      fill.addColorStop(0.55, `rgba(191,201,219,${0.12 + glow * 0.32})`);
      fill.addColorStop(1, `rgba(174,184,206,${0.12 + glow * 0.22})`);
      c.fillStyle = fill;
      c.beginPath(); c.moveTo(0, surface);
      c.bezierCurveTo(w / 3, surface - this.field.wave, w * 2 / 3, surface + this.field.wave, w, surface);
      c.lineTo(w, h); c.lineTo(0, h); c.closePath(); c.fill();
      c.restore();
    }
    for (const p of this.field.particles) {
      this.dot(p.x, p.y, p.radius, p.opacity * (p.y < surface ? 0.72 : 0.9) * Math.sqrt(glow));
    }
    c.globalAlpha = 1; c.restore();
    c.globalAlpha = 0.25 + glow * 0.75;
    const rim = c.createLinearGradient(0, 0, w, h);
    rim.addColorStop(0, 'rgba(255,255,255,0.60)');
    rim.addColorStop(0.42, 'rgba(235,243,255,0.12)');
    rim.addColorStop(1, 'rgba(255,255,255,0.38)');
    c.strokeStyle = rim; c.lineWidth = 0.8; this.pill(0.5); c.stroke(); c.restore();
    this.drawIcon();
  }

  private volumeLevel(): number {
    if (this.field.value <= 0) return 0;
    // 四态分界为 0 / 33% / 66%，边界值进入后一档。
    return this.field.value < 0.33 ? 1 : (this.field.value < 0.66 ? 2 : 3);
  }

  private drawIcon(): void {
    if (!this.iconReady) return;
    const c = this.iconContext;
    c.clearRect(0, 0, 26, 26);
    c.save();
    const lit: number = Math.min(1, this.field.illumination * 2.8);
    const tone: number = Math.round(245 - lit * 219);
    const color: string = `rgb(${tone},${tone},${tone})`;
    c.fillStyle = color; c.strokeStyle = color;
    c.lineCap = 'round'; c.lineJoin = 'round';
    if (this.kind === 'brightness') {
      // 圆心及 A 保持朝上，八根光芒才随亮度旋转。低亮度为圆点，连续伸长为圆头线。
      c.beginPath(); c.arc(13, 13, 6.1, 0, Math.PI * 2); c.fill();
      c.globalCompositeOperation = 'destination-out';
      c.lineWidth = 1.35;
      c.beginPath(); c.moveTo(10.5, 16.2); c.lineTo(13, 9.7); c.lineTo(15.5, 16.2);
      c.moveTo(11.4, 14.1); c.lineTo(14.6, 14.1); c.stroke();
      c.globalCompositeOperation = 'source-over';
      const rotation: number = Math.PI * this.iconValue;
      const rayLength: number = this.iconValue * 2.8;
      c.lineWidth = 1.8;
      for (let i: number = 0; i < 8; i++) {
        const angle: number = rotation + i * Math.PI / 4;
        const x: number = Math.cos(angle); const y: number = Math.sin(angle);
        if (rayLength < 0.015) {
          c.beginPath(); c.arc(13 + x * 9.1, 13 + y * 9.1, 0.9, 0, Math.PI * 2); c.fill();
        } else {
          c.beginPath(); c.moveTo(13 + x * 9.1, 13 + y * 9.1);
          c.lineTo(13 + x * (9.1 + rayLength), 13 + y * (9.1 + rayLength)); c.stroke();
        }
      }
    } else {
      const level: number = this.volumeLevel();
      c.save();
      if (level === 0) c.translate(3, 0);
      c.beginPath(); c.moveTo(3, 9); c.lineTo(7, 9); c.lineTo(11.6, 5.3);
      c.quadraticCurveTo(13, 4.3, 13, 6); c.lineTo(13, 20);
      c.quadraticCurveTo(13, 21.5, 11.6, 20.5); c.lineTo(7, 17); c.lineTo(3, 17);
      c.quadraticCurveTo(1.8, 17, 1.8, 15.8); c.lineTo(1.8, 10.2);
      c.quadraticCurveTo(1.8, 9, 3, 9); c.closePath(); c.fill();
      c.restore();
      c.lineWidth = 1.9;
      if (level === 0) {
        // 斜杠周围留细缝，与参考图的静音轮廓一致。
        c.globalCompositeOperation = 'destination-out'; c.lineWidth = 3.5;
        c.beginPath(); c.moveTo(3, 3); c.lineTo(23, 23); c.stroke();
        c.globalCompositeOperation = 'source-over'; c.lineWidth = 1.9;
        c.beginPath(); c.moveTo(3, 3); c.lineTo(23, 23); c.stroke();
      } else {
        for (let i: number = 0; i < level; i++) {
          c.beginPath(); c.arc(10.8, 13, 5 + i * 3, -0.68, 0.68); c.stroke();
        }
      }
    }
    c.restore();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Canvas(this.context).width(this.thickness).height(this.length)
        .hitTestBehavior(HitTestMode.None)
        .onReady(() => { this.ready = true; this.draw(); })
      Canvas(this.iconContext).width(26).height(26).margin({ bottom: 24 })
        .id(`lab-${this.kind}-icon`).hitTestBehavior(HitTestMode.None)
        .onReady(() => { this.iconReady = true; this.drawIcon(); })
    }
    .id(`lab-${this.kind}-bar`)
    .width(this.thickness).height(this.length)
    .borderRadius(this.thickness / 2).clip(true)
    // 两种背景都使用同一深色材质，背景选择只改变实验页壁纸遮罩。
    .backgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THIN, { colorMode: ThemeColorMode.DARK })
    .backgroundColor('#202D3344')
    .shadow({ radius: 14, color: '#22000000', offsetY: 6 })
    .scale({ x: this.pressed ? 1.035 : 1, y: this.pressed ? 1.015 : 1 })
    .animation({ duration: 180, curve: Curve.EaseOut })
    .accessibilityText(`${this.kind === 'brightness' ? '亮度' : '音量'} ${this.percent}%`)
    .onTouch((event: TouchEvent) => this.touch(event))
  }
}
