import { SdfKeyframes } from './SdfKeyframes';

export interface JellyHost {
  now: () => number;
  schedule: (callback: () => void, delay: number) => number;
  cancel: (id: number) => void;
  activate: () => boolean;
  frame: (values: number[]) => void;
  finish: () => void;
}

// Original delays and k=140,c=20,m=1. The public mesh renderer is separate.
export class JellyMotion {
  private host: JellyHost;
  private pending: number[] = [];
  private tick: number = -1;
  private generation: number = 0;
  private active: boolean = false;
  private from: number[] = SdfKeyframes.identity.slice();
  private target: number[] = SdfKeyframes.identity.slice();
  private startedAt: number = 0;

  constructor(host: JellyHost) { this.host = host; }

  private sample(): number[] {
    const t: number = Math.max(0, (this.host.now() - this.startedAt) / 1000);
    const frequency: number = Math.sqrt(140 - 10 * 10);
    const remaining: number = Math.exp(-10 * t) *
      (Math.cos(frequency * t) + 10 / frequency * Math.sin(frequency * t));
    return this.target.map((value: number, index: number): number =>
      value + (this.from[index] - value) * remaining);
  }

  private clearTasks(): void {
    this.pending.forEach((id: number) => { this.host.cancel(id); });
    this.pending = [];
    if (this.tick !== -1) { this.host.cancel(this.tick); this.tick = -1; }
  }

  private later(callback: () => void, delay: number): void {
    const generation: number = this.generation;
    this.pending.push(this.host.schedule(() => {
      if (generation === this.generation) { callback(); }
    }, delay));
  }

  private retarget(frame: number[]): void {
    this.from = this.sample();
    this.target = frame.slice();
    this.startedAt = this.host.now();
  }

  private render(): void {
    if (!this.active) { return; }
    this.host.frame(this.sample());
    if (this.active) { this.tick = this.host.schedule(() => { this.render(); }, 16); }
  }

  down(): void {
    const previous: number[] = this.active ? this.sample() : SdfKeyframes.enter[2].slice();
    this.generation++;
    this.clearTasks();
    this.from = previous;
    this.target = previous;
    this.startedAt = this.host.now();
    // A re-press preserves the current shape while waiting for the original delay.
    if (this.active) { this.render(); }
    this.later(() => {
      if (!this.active && !this.host.activate()) { return; }
      this.active = true;
      this.retarget(SdfKeyframes.enter[0]);
      if (this.tick === -1) { this.render(); }
      this.later(() => { this.retarget(SdfKeyframes.enter[1]); }, 233);
      this.later(() => { this.retarget(SdfKeyframes.enter[2]); }, 367);
    }, 300);
  }

  up(): void {
    const previous: number[] = this.active ? this.sample() : this.target;
    this.generation++;
    this.clearTasks();
    if (!this.active) { return; }
    this.from = previous;
    this.target = previous;
    this.startedAt = this.host.now();
    this.retarget(SdfKeyframes.exit[0]);
    this.render();
    this.later(() => { this.retarget(SdfKeyframes.exit[1]); }, 167);
    this.later(() => { this.retarget(SdfKeyframes.exit[2]); }, 333);
    // Numerical spring settles below 0.001 by this point. Native onFinish is private.
    this.later(() => { this.stop(); }, 1333);
  }

  stop(): void {
    this.generation++;
    this.clearTasks();
    this.active = false;
    this.from = SdfKeyframes.identity.slice();
    this.target = SdfKeyframes.identity.slice();
    this.host.finish();
  }
}
