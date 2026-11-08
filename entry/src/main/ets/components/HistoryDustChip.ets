import { image } from '@kit.ImageKit';
import { errMsg, logWarn } from '../utils/Logger';

/** ComponentSnapshot requests share a renderer; serialize capture, then animate independently. */
export class HistoryDustSnapshotQueue {
  private static pending: Promise<void> = Promise.resolve();

  static async capture(capture: () => Promise<image.PixelMap>): Promise<image.PixelMap> {
    const previous = HistoryDustSnapshotQueue.pending;
    let release: () => void = () => {};
    HistoryDustSnapshotQueue.pending = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    try { return await capture(); } finally { release(); }
  }
}

interface HistoryDustTile {
  x: number;
  y: number;
  width: number;
  height: number;
  delay: number;
  driftX: number;
  driftY: number;
  turn: number;
}

/** Dissolve the actual rendered label, keeping its layout slot until every chip has finished. */
@Component
export struct HistoryDustChip {
  @Prop word: string = '';
  @Prop dark: boolean = true;
  @Prop @Watch('onDissolvingChanged') dissolving: boolean = false;
  @Prop staggerMs: number = 0;
  onActivate: () => void = () => {};
  onDelete: () => void = () => {};
  onGone: () => void = () => {};
  @State private captured: boolean = false;
  private snapshotId: string = `history-dust-${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @State private chipWidth: number = 0;
  private chipHeight: number = 30;
  private canvasReady: boolean = false;
  private running: boolean = false;
  private disposed: boolean = false;
  private timer: number = -1;
  private bitmap: image.PixelMap | null = null;
  private sourceWidth: number = 0;
  private sourceHeight: number = 0;
  private tiles: HistoryDustTile[] = [];

  private onDissolvingChanged(): void {
    if (this.dissolving) this.startDust();
  }

  private async startDust(): Promise<void> {
    if (!this.canvasReady || !this.dissolving || this.running || this.disposed || this.chipWidth <= 0) return;
    this.running = true;
    try {
      const bitmap = await HistoryDustSnapshotQueue.capture(() =>
        this.getUIContext().getComponentSnapshot().get(this.snapshotId,
          { scale: 1, waitUntilRenderFinished: true }));
      if (this.disposed) { bitmap.release().catch(() => {}); return; }
      this.bitmap = bitmap;
      const info = await bitmap.getImageInfo();
      if (this.disposed) return;
      // PixelMap source rectangles use vp from API 18 onward, like the destination canvas.
      this.sourceWidth = this.getUIContext().px2vp(info.size.width);
      this.sourceHeight = this.getUIContext().px2vp(info.size.height);
      this.tiles = [];
      const grain = Math.max(2.5, Math.sqrt(this.chipWidth * this.chipHeight / 360));
      for (let y = 0; y < this.chipHeight; y += grain) {
        for (let x = 0; x < this.chipWidth; x += grain) {
          this.tiles.push({ x: x, y: y, width: Math.min(grain, this.chipWidth - x),
            height: Math.min(grain, this.chipHeight - y),
            delay: (1 - x / this.chipWidth) * 0.34 + Math.random() * 0.1,
            driftX: 28 + Math.random() * 62, driftY: -12 - Math.random() * 42,
            turn: (Math.random() - 0.5) * 3 });
        }
      }
      this.drawDust(0);
      this.captured = true;
      const started = Date.now();
      this.timer = setInterval(() => {
        const progress = Math.max(0, (Date.now() - started - this.staggerMs) / 1120);
        this.drawDust(Math.min(1, progress));
        if (progress >= 1) {
          this.stopDust();
          this.onGone();
        }
      }, 16);
    } catch (error) {
      if (!this.disposed) logWarn('历史碎化快照失败', errMsg(error));
      this.stopDust();
      if (!this.disposed) this.onGone();
    }
  }

  private drawDust(progress: number): void {
    this.context.clearRect(0, 0, this.chipWidth + 128, this.chipHeight + 128);
    if (!this.bitmap) return;
    const scaleX = this.sourceWidth / this.chipWidth;
    const scaleY = this.sourceHeight / this.chipHeight;
    for (const tile of this.tiles) {
      const age = Math.max(0, Math.min(1, (progress - tile.delay) / 0.54));
      if (age >= 1) continue;
      const movement = age * age;
      const size = 1 - age * 0.65;
      this.context.save();
      this.context.globalAlpha = 1 - age;
      this.context.translate(24 + tile.x + tile.width / 2 + tile.driftX * movement,
        76 + tile.y + tile.height / 2 + tile.driftY * movement);
      this.context.rotate(tile.turn * age);
      this.context.drawImage(this.bitmap, tile.x * scaleX, tile.y * scaleY,
        tile.width * scaleX, tile.height * scaleY, -tile.width * size / 2, -tile.height * size / 2,
        tile.width * size, tile.height * size);
      this.context.restore();
    }
  }

  private stopDust(): void {
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    const bitmap = this.bitmap;
    this.bitmap = null;
    if (bitmap) bitmap.release().catch(() => {});
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stopDust();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Text(this.word)
        .id(this.snapshotId).fontSize(14).fontColor(this.dark ? '#E6E7E8' : '#18191C')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 168 })
        .padding({ left: 12, right: 12 }).height(30).borderRadius(15)
        .backgroundColor(this.dark ? '#14FFFFFF' : '#0A000000')
        .opacity(this.captured ? 0 : 1)
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          this.chipWidth = Number(size.width); this.chipHeight = Number(size.height);
        })
      if (this.dissolving) {
        Canvas(this.context).width(this.chipWidth + 128).height(this.chipHeight + 128)
          .position({ x: -24, y: -76 }).hitTestBehavior(HitTestMode.None)
          .onReady(() => { this.canvasReady = true; this.startDust(); })
      }
    }.width(this.chipWidth > 0 ? this.chipWidth : LayoutPolicy.fixAtIdealSize).height(30).clip(false)
      .id('search-history-chip').accessibilityText(this.word)
      .onClick(() => { if (!this.dissolving) this.onActivate(); })
      .gesture(LongPressGesture().onAction(() => { if (!this.dissolving) this.onDelete(); }))
  }
}
