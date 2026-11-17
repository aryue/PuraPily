import type { image } from '@kit.ImageKit';

const RETIRE_GRACE_MS: number = 300;
const RECHECK_MS: number = 800;

/** Retire only frames that have left the cache, the preview and the pinned surface. */
export class FeedStillFrameRetirement {
  private pending: Map<image.PixelMap, number> = new Map();
  private timer: number = -1;
  private nextSweepAt: number = Infinity;
  private inUse: ((frame: image.PixelMap) => boolean) | null;

  constructor(inUse: (frame: image.PixelMap) => boolean) {
    this.inUse = inUse;
  }

  retire(frame: image.PixelMap | undefined): void {
    if (!frame || this.pending.has(frame)) return;
    const readyAt = Date.now() + RETIRE_GRACE_MS;
    this.pending.set(frame, readyAt);
    this.schedule(readyAt);
  }

  /** After the UI drops its last references, the grace timer can drain without retaining the page. */
  close(): void {
    this.inUse = null;
  }

  private schedule(at: number): void {
    if (at >= this.nextSweepAt) return;
    clearTimeout(this.timer);
    this.nextSweepAt = at;
    this.timer = setTimeout(() => {
      this.timer = -1;
      this.nextSweepAt = Infinity;
      this.sweep();
    }, Math.max(1, at - Date.now()));
  }

  private sweep(): void {
    const now = Date.now();
    let next = Infinity;
    this.pending.forEach((readyAt: number, frame: image.PixelMap) => {
      if (readyAt > now) {
        next = Math.min(next, readyAt);
      } else if (this.inUse?.(frame)) {
        const recheckAt = now + RECHECK_MS;
        this.pending.set(frame, recheckAt);
        next = Math.min(next, recheckAt);
      } else {
        this.pending.delete(frame);
        try { frame.release().catch(() => {}); } catch (_error) {}
      }
    });
    if (next < Infinity) this.schedule(next);
  }
}
