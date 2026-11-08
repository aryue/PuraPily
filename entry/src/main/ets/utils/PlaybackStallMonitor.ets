/** Distinguish a native refill receiving media from a stalled pipeline. */
export class PlaybackStallMonitor {
  private position: number = 0;
  private bufferedEnd: number = 0;
  private progressedAt: number = 0;
  private suppliedAt: number = 0;

  reset(position: number, bufferedEnd: number, now: number): void {
    this.position = position;
    this.bufferedEnd = bufferedEnd;
    this.progressedAt = now;
    this.suppliedAt = now;
  }

  stalled(position: number, bufferedEnd: number, buffering: boolean, now: number): boolean {
    if (position < this.position || position - this.position >= 250) {
      this.reset(position, bufferedEnd, now);
      return false;
    }
    if (buffering && bufferedEnd - this.bufferedEnd >= 250) {
      this.bufferedEnd = bufferedEnd;
      this.suppliedAt = now;
    }
    // Healthy refill gets time to reach the native watermark, with a hard
    // deadline for a decoder that never resumes even while bytes arrive.
    return now - this.progressedAt >= 30000 ||
      (now - this.progressedAt >= 8000 && now - this.suppliedAt >= 8000);
  }
}
