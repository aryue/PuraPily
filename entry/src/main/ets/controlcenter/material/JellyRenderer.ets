import { NodeController, FrameNode, RenderNode, DrawContext, UIContext } from '@kit.ArkUI';
import { drawing, common2D } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { SdfKeyframes } from '../model/SdfKeyframes';
import { JellyMesh } from '../model/JellyMesh';
import { SunVector } from '../model/SunVector';

class JellyRenderNode extends RenderNode {
  bitmap: image.PixelMap | null = null;
  backdrop: image.PixelMap | null = null;
  shape: number[] = SdfKeyframes.identity.slice();
  shellWidth: number = 64;
  shellHeight: number = 144;
  padding: number = 36;
  iconValue: number = 0;
  iconTrack: number = 128;
  iconInk: boolean = false;
  iconEnabled: boolean = false;
  private brush: drawing.Brush = new drawing.Brush();
  private iconBrush: drawing.Brush = new drawing.Brush();

  private drawIcon(canvas: drawing.Canvas, scale: number): void {
    if (!this.iconEnabled) { return; }
    this.iconBrush.setAntiAlias(true);
    this.iconBrush.setColor(this.iconInk ? 0xFF000000 : 0xFFFFFFFF);
    canvas.attachBrush(this.iconBrush);
    const top: number = this.shellHeight - (this.shellHeight - this.iconTrack) / 2 - 38;
    const contours: number[][] = SunVector.contours(this.iconValue, this.iconTrack);
    for (let c: number = 0; c < contours.length; c++) {
      const contour: number[] = contours[c];
      const path: drawing.Path = new drawing.Path();
      for (let i: number = 0; i < contour.length; i += 2) {
        const point: number[] = JellyMesh.point(this.shape,
          (18 + contour[i] / 10) / this.shellWidth,
          (top + contour[i + 1] / 10) / this.shellHeight);
        const x: number = (this.padding + point[0] * this.shellWidth) * scale;
        const y: number = (this.padding + point[1] * this.shellHeight) * scale;
        if (i === 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      path.close();
      canvas.drawPath(path);
    }
    canvas.detachBrush();
  }

  private drawTexture(canvas: drawing.Canvas, bitmap: image.PixelMap, vertices: number[]): void {
    if (deviceInfo.sdkApiVersion < 23) {
      canvas.drawPixelMapMesh(bitmap, 16, 32, vertices, 0, null, 0);
      return;
    }
    const size = bitmap.getImageInfoSync().size;
    const positions: common2D.Point[] = [];
    const texture: common2D.Point[] = [];
    const indices: number[] = [];
    for (let row: number = 0; row <= 32; row++) {
      for (let column: number = 0; column <= 16; column++) {
        const index: number = row * 17 + column;
        positions.push({ x: vertices[index * 2], y: vertices[index * 2 + 1] });
        texture.push({ x: column * size.width / 16, y: row * size.height / 32 });
        if (row < 32 && column < 16) {
          indices.push(index, index + 1, index + 17, index + 1, index + 18, index + 17);
        }
      }
    }
    this.brush.setShaderEffect(drawing.ShaderEffect.createImageShader(bitmap,
      drawing.TileMode.DECAL, drawing.TileMode.DECAL,
      new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR)));
    canvas.attachBrush(this.brush);
    canvas.drawVertices(drawing.VertexMode.TRIANGLES_VERTEXMODE, positions.length, positions,
      texture, null, indices.length, indices, drawing.BlendMode.MODULATE);
    canvas.detachBrush();
    this.brush.setShaderEffect(null);
    canvas.attachBrush(this.brush);
  }

  draw(context: DrawContext): void {
    // RenderNode records a fresh display list on invalidation. Clearing its canvas
    // can affect the full compositor surface beyond the warped capsule clip.
    // Visibility is controlled by node.opacity when the animation ends.
    if (this.bitmap === null) { return; }
    const scale: number = context.sizeInPixel.width / (this.shellWidth + 2 * this.padding);
    const vertices: number[] = JellyMesh.vertices(this.shape, this.shellWidth * scale,
      this.shellHeight * scale, this.padding * scale);
    this.brush.setAntiAlias(true);
    const contour: drawing.Path = new drawing.Path();
    const addPoint = (x: number, y: number, first: boolean = false): void => {
      const p: number[] = JellyMesh.point(this.shape, x / this.shellWidth, y / this.shellHeight);
      const px: number = (this.padding + p[0] * this.shellWidth) * scale;
      const py: number = (this.padding + p[1] * this.shellHeight) * scale;
      if (first) { contour.moveTo(px, py); } else { contour.lineTo(px, py); }
    };
    for (let i: number = 0; i <= 48; i++) {
      const angle: number = Math.PI + Math.PI * i / 48;
      addPoint(32 + 32 * Math.cos(angle), 32 + 32 * Math.sin(angle), i === 0);
    }
    for (let i: number = 1; i <= 48; i++) {
      addPoint(64, 32 + (this.shellHeight - 64) * i / 48);
    }
    for (let i: number = 0; i <= 48; i++) {
      const angle: number = Math.PI * i / 48;
      addPoint(32 + 32 * Math.cos(angle), this.shellHeight - 32 + 32 * Math.sin(angle));
    }
    for (let i: number = 1; i <= 48; i++) {
      addPoint(0, this.shellHeight - 32 - (this.shellHeight - 64) * i / 48);
    }
    contour.close();
    context.canvas.save();
    context.canvas.clipPath(contour, drawing.ClipOp.INTERSECT, true);
    context.canvas.attachBrush(this.brush);
    if (this.backdrop !== null) {
      this.drawTexture(context.canvas, this.backdrop, vertices);
    }
    this.drawTexture(context.canvas, this.bitmap, vertices);
    context.canvas.detachBrush();
    this.drawIcon(context.canvas, scale);
    context.canvas.restore();
  }
}

export class JellyRenderer extends NodeController {
  private root: FrameNode | null = null;
  private node: JellyRenderNode = new JellyRenderNode();
  private images: image.PixelMap[] = [];
  private captureAt: number = 0;
  private captureCount: number = 0;
  private captureMs: number = 0;

  setIcon(value: number, track: number, ink: boolean, enabled: boolean = true): void {
    this.node.iconValue = value;
    this.node.iconTrack = track;
    this.node.iconInk = ink;
    this.node.iconEnabled = enabled;
  }

  makeNode(context: UIContext): FrameNode {
    this.root = new FrameNode(context);
    this.root.getRenderNode()!.clipToFrame = false;
    this.node.clipToFrame = false;
    this.node.opacity = 0;
    this.root.getRenderNode()!.appendChild(this.node);
    this.resize(64, 144);
    return this.root;
  }

  resize(width: number, height: number): void {
    this.node.shellWidth = width;
    this.node.shellHeight = height;
    this.node.size = { width: width + 72, height: height + 72 };
    this.root?.setMeasuredSize({ width: width + 72, height: height + 72 });
  }

  capture(context: UIContext, id: string, force: boolean = false): boolean {
    const now: number = Date.now();
    if (!force && now - this.captureAt < 50) { return true; }
    if (force) {
      const source: FrameNode = context.getFrameNodeById(id)!;
      const wallpaper: FrameNode | null = context.getFrameNodeById('vertical_wallpaper');
      // Playback has a live video surface rather than the lab wallpaper node.
      // Capture only the slider there; never snapshot or replace the video.
      if (wallpaper !== null) {
        const size = source.getMeasuredSize();
        const position = source.getPositionToWindow();
        const origin = wallpaper.getPositionToWindow();
        const density: number = size.width / this.node.shellWidth;
        const left: number = Math.round((position.x - origin.x) * density);
        const top: number = Math.round((position.y - origin.y) * density);
        this.node.backdrop?.release().catch(() => {});
        this.node.backdrop = context.getComponentSnapshot().getSync('vertical_wallpaper', {
          waitUntilRenderFinished: true, region: { left: left, top: top,
            right: left + size.width, bottom: top + size.height }
        });
      }
    }
    const bitmap: image.PixelMap = context.getComponentSnapshot().getSync(id,
      { waitUntilRenderFinished: true });
    this.captureMs += Date.now() - now;
    this.captureCount++;
    this.captureAt = now;
    this.node.bitmap = bitmap;
    this.images.push(bitmap);
    if (this.images.length > 4) {
      this.images.shift()!.release().catch(() => {});
    }
    return true;
  }

  frame(shape: number[]): void {
    this.node.shape = shape;
    this.node.opacity = 1;
    this.node.invalidate();
  }

  clear(): void {
    this.node.opacity = 0;
    this.node.bitmap = null;
    this.node.invalidate();
    const retired: image.PixelMap[] = this.images;
    if (this.node.backdrop !== null) { retired.push(this.node.backdrop); this.node.backdrop = null; }
    this.images = [];
    setTimeout(() => { retired.forEach((bitmap: image.PixelMap) => { bitmap.release().catch(() => {}); }); }, 100);
    if (this.captureCount > 0) {
      console.info(`CCLab jelly snapshots=${this.captureCount}, averageMs=${this.captureMs / this.captureCount}`);
    }
    this.captureCount = 0;
    this.captureMs = 0;
  }

  dispose(): void {
    this.clear();
    this.root?.dispose();
    this.node.dispose();
    this.root = null;
  }
}
