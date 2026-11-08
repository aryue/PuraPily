// Visual reconstruction of the fill boundary's optical response. These tuning
// values are not recovered HDS constants. Coordinates are the unscaled track's.
export class LiquidSurfaceLight {
  static paint(c: CanvasRenderingContext2D, width: number, height: number,
    filled: number, contactX: number, intensity: number): void {
    const amount: number = Math.max(0, Math.min(height, filled));
    const fade: number = Math.min(1, amount / 5, (height - amount) / 5);
    const strength: number = Math.max(0, Math.min(1, intensity)) * fade;
    if (strength < 0.001) { return; }
    const surface: number = height - amount;
    const center: number = Math.max(width * 0.25, Math.min(width * 0.75, contactX));
    c.save();
    // The weaker dry-side halo and broader liquid-side glow share one boundary.
    c.save();
    c.beginPath(); c.rect(0, 0, width, surface); c.clip();
    LiquidSurfaceLight.halo(c, center, surface + 0.6, width * 0.78, 8, 0.12 * strength);
    c.restore();
    c.save();
    c.beginPath(); c.rect(0, surface, width, height - surface); c.clip();
    LiquidSurfaceLight.halo(c, center, surface + 0.6, width * 0.78, 14, 0.28 * strength);
    c.restore();

    const rim: CanvasGradient = c.createLinearGradient(center - width * 0.7, 0,
      center + width * 0.7, 0);
    rim.addColorStop(0, 'rgba(255,255,255,0)');
    rim.addColorStop(0.25, `rgba(255,255,255,${0.18 * strength})`);
    rim.addColorStop(0.5, `rgba(255,255,255,${0.68 * strength})`);
    rim.addColorStop(0.75, `rgba(255,255,255,${0.18 * strength})`);
    rim.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = rim;
    c.fillRect(0, surface - 0.375, width, 0.75);
    c.restore();
  }

  private static halo(c: CanvasRenderingContext2D, x: number, y: number,
    radiusX: number, radiusY: number, alpha: number): void {
    c.save();
    c.translate(x, y); c.scale(radiusX, radiusY);
    const gradient: CanvasGradient = c.createRadialGradient(0, 0, 0, 0, 0, 1);
    gradient.addColorStop(0, `rgba(255,255,255,${alpha})`);
    gradient.addColorStop(0.3, `rgba(255,255,255,${alpha * 0.65})`);
    gradient.addColorStop(1, 'rgba(255,255,255,0)');
    c.fillStyle = gradient;
    c.fillRect(-1, -1, 2, 2);
    c.restore();
  }
}
