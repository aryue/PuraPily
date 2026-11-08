export interface VideoTransformPoint {
  id: number;
  x: number;
  y: number;
}

/** Incremental similarity transform: keep the picture under the two fingers anchored. */
export class FullscreenVideoTransform {
  scale: number = 1;
  angle: number = 0;
  x: number = 0;
  y: number = 0;
  private previous: VideoTransformPoint[] = [];

  reset(): void {
    this.scale = 1;
    this.angle = 0;
    this.x = 0;
    this.y = 0;
    this.end();
  }

  end(): void {
    this.previous = [];
  }

  update(points: VideoTransformPoint[], centerX: number, centerY: number): void {
    if (points.length !== 2) { this.end(); return; }
    const first = points[0];
    const second = points[1];
    const a = this.previous.find(point => point.id === first.id);
    const b = this.previous.find(point => point.id === second.id);
    if (a && b) {
      const oldDX = b.x - a.x;
      const oldDY = b.y - a.y;
      const dx = second.x - first.x;
      const dy = second.y - first.y;
      const oldDistance = Math.sqrt(oldDX * oldDX + oldDY * oldDY);
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (oldDistance >= 8 && distance >= 8) {
        const nextScale = Math.max(0.25, Math.min(5, this.scale * distance / oldDistance));
        const ratio = nextScale / this.scale;
        let radians = Math.atan2(dy, dx) - Math.atan2(oldDY, oldDX);
        if (radians > Math.PI) radians -= 2 * Math.PI;
        if (radians < -Math.PI) radians += 2 * Math.PI;
        const oldX = (a.x + b.x) / 2 - centerX;
        const oldY = (a.y + b.y) / 2 - centerY;
        const offsetX = this.x - oldX;
        const offsetY = this.y - oldY;
        this.x = (first.x + second.x) / 2 - centerX +
          ratio * (Math.cos(radians) * offsetX - Math.sin(radians) * offsetY);
        this.y = (first.y + second.y) / 2 - centerY +
          ratio * (Math.sin(radians) * offsetX + Math.cos(radians) * offsetY);
        this.scale = nextScale;
        this.angle = (this.angle + radians * 180 / Math.PI) % 360;
      }
    }
    this.previous = points.map((point: VideoTransformPoint): VideoTransformPoint => ({ id: point.id, x: point.x, y: point.y }));
  }
}
