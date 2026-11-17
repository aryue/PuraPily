import { media } from '@kit.MediaKit';
import type { PlaybackPlayer } from './PlaybackPlayer';

export interface PendingPlaybackSeek {
  target: number;
  fast: boolean;
  resetControls: boolean;
}

/** A seek in flight needs only the latest requested destination. */
export class PlaybackSeekQueue {
  private pending: PendingPlaybackSeek | null = null;

  replace(target: number, fast: boolean, resetControls: boolean): void {
    this.pending = { target, fast, resetControls };
  }

  hasPending(): boolean { return this.pending !== null; }

  differsFrom(target: number): boolean {
    return this.pending !== null && Math.abs(this.pending.target - target) > 0.05;
  }

  take(): PendingPlaybackSeek | null {
    const pending = this.pending;
    this.pending = null;
    return pending;
  }
}

export interface PlaybackSeekResult {
  landed: boolean;
  audioLanded: boolean;
}

export interface PlaybackSeekCallbacks {
  video: (callback: () => void) => void;
  audio: (callback: (position: number) => void) => void;
  delay: (ms: number) => Promise<void>;
}

/** Dispatch one seek after registering both acknowledgments, which may arrive synchronously. */
export async function seekPlaybackTracks(video: PlaybackPlayer, audio: PlaybackPlayer | null,
  targetMs: number, fast: boolean, retry: boolean, callbacks: PlaybackSeekCallbacks): Promise<PlaybackSeekResult> {
  let landed = false;
  let audioLanded = false;
  const videoDone = new Promise<void>((resolve) => {
    callbacks.video(() => { landed = true; resolve(); });
  });
  const audioDone = new Promise<void>((resolve) => {
    if (audio) callbacks.audio((position: number) => {
      audioLanded = Math.abs(position - targetMs) <= 120;
      resolve();
    });
    else resolve();
  });
  video.seek(targetMs, fast ? media.SeekMode.SEEK_CLOSEST : media.SeekMode.SEEK_PREV_SYNC);
  audio?.seek(targetMs, media.SeekMode.SEEK_CLOSEST);
  const videoWait = (fast ? 700 : 1500) + (retry ? 500 : 0);
  await Promise.all([
    Promise.race([videoDone, callbacks.delay(videoWait)]),
    audio ? Promise.race([audioDone, callbacks.delay(fast ? 250 : 500)]) : audioDone
  ]);
  return { landed, audioLanded };
}
