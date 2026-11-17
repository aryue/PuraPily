import { PlaybackStallMonitor } from '../utils/PlaybackStallMonitor';

export interface PlaybackObservationSample {
  position: number;
  bufferedEnd: number;
  checkStall: boolean;
}

/** Owns the existing first-frame timeout and one-second playback sample. */
export class PlaybackObservation {
  private firstFrameTimer: number = -1;
  private sampleTimer: number = -1;
  private stall: PlaybackStallMonitor = new PlaybackStallMonitor();
  private buffering: boolean = false;

  start(position: number, onFrameTimeout: () => void,
    sample: () => PlaybackObservationSample | null, onStall: () => void): void {
    this.cancelFirstFrame();
    this.stopSampling();
    this.buffering = false;
    this.stall.reset(position, 0, Date.now());
    this.firstFrameTimer = setTimeout(onFrameTimeout, 15000);
    this.sampleTimer = setInterval(() => {
      const now = Date.now();
      const current = sample();
      if (!current) return;
      if (!current.checkStall) {
        this.stall.reset(current.position, current.bufferedEnd, now);
      } else if (this.stall.stalled(current.position, current.bufferedEnd, this.buffering, now)) {
        onStall();
      }
    }, 1000);
  }

  setBuffering(value: boolean): void {
    this.buffering = value;
  }

  cancelFirstFrame(): void {
    clearTimeout(this.firstFrameTimer);
    this.firstFrameTimer = -1;
  }

  stopSampling(): void {
    clearInterval(this.sampleTimer);
    this.sampleTimer = -1;
  }
}
