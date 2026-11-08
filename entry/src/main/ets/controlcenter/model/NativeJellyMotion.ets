import { JellyHost } from './JellyMotion';
import { SdfKeyframes } from './SdfKeyframes';

export type NativeJellyAnimate = (frame: number[], delay: number, onFinish?: () => void) => void;

// With the actual visualEffect property available, let ArkUI interpolate it.
// Delays and last-stage onFinish match BrightnessButtonViewModel.
export class NativeJellyMotion {
  private host: JellyHost;
  private animate: NativeJellyAnimate;
  private pending: number = -1;
  private stages: number[] = [];
  private generation: number = 0;
  private active: boolean = false;

  constructor(host: JellyHost, animate: NativeJellyAnimate) {
    this.host = host;
    this.animate = animate;
  }

  private cancelPending(): void {
    if (this.pending !== -1) { this.host.cancel(this.pending); this.pending = -1; }
    this.stages.forEach((id: number) => { this.host.cancel(id); });
    this.stages = [];
  }

  private stage(frame: number[], delay: number, generation: number, finish: boolean = false): void {
    const run = (): void => {
      if (generation !== this.generation || !this.active) { return; }
      this.animate(frame, 0, finish ? (): void => {
        if (generation === this.generation) { this.stop(); }
      } : undefined);
    };
    if (delay === 0) { run(); } else { this.stages.push(this.host.schedule(run, delay)); }
  }

  down(): void {
    this.cancelPending();
    const generation: number = ++this.generation;
    this.pending = this.host.schedule(() => {
      this.pending = -1;
      if (generation !== this.generation) { return; }
      if (!this.active && !this.host.activate()) { return; }
      this.active = true;
      this.stage(SdfKeyframes.enter[0], 0, generation);
      this.stage(SdfKeyframes.enter[1], 233, generation);
      this.stage(SdfKeyframes.enter[2], 367, generation);
    }, 300);
  }

  up(): void {
    this.cancelPending();
    const generation: number = ++this.generation;
    if (!this.active) { return; }
    this.stage(SdfKeyframes.exit[0], 0, generation);
    this.stage(SdfKeyframes.exit[1], 167, generation);
    this.stage(SdfKeyframes.exit[2], 333, generation, true);
  }

  stop(): void {
    this.generation++;
    this.cancelPending();
    this.active = false;
    this.host.finish();
  }
}
