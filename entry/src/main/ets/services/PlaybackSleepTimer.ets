/** A page-owned deadline that remains based on wall time while the app is suspended. */
export class PlaybackSleepTimer {
  private timer: number = -1;
  private generation: number = 0;
  private deadline: number = 0;
  private expired: (() => void) | null = null;

  start(minutes: number, expired: () => void): void {
    this.cancel();
    if (!(minutes > 0)) return;
    const generation = this.generation;
    this.deadline = Date.now() + minutes * 60000;
    this.expired = expired;
    this.timer = setInterval(() => {
      if (generation === this.generation) this.check();
    }, 1000);
  }

  check(): void {
    if (this.deadline === 0 || Date.now() < this.deadline) return;
    const expired = this.expired;
    this.cancel();
    expired?.();
  }

  cancel(): void {
    this.generation++;
    this.deadline = 0;
    this.expired = null;
    if (this.timer !== -1) clearInterval(this.timer);
    this.timer = -1;
  }
}
