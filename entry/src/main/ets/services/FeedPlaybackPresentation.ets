import type { PlaybackPlayer } from './PlaybackPlayer';

/** Readiness events belonging to a single committed feed switch. */
export class FeedPlaybackReadiness {
  private frame: (() => void) | null = null;
  private prepared: (() => void) | null = null;
  private advance: (() => void) | null = null;
  private advanceAfter: number = 0;
  private ready: Promise<void[]>;
  private cancelled: boolean = false;

  constructor() {
    const frame = new Promise<void>(resolve => { this.frame = resolve; });
    const prepared = new Promise<void>(resolve => { this.prepared = resolve; });
    this.ready = Promise.all([frame, prepared]);
  }

  get waitingForFrame(): boolean { return this.frame !== null; }
  get active(): boolean { return !this.cancelled; }

  frameRendered(): void {
    const done = this.frame;
    this.frame = null;
    done?.();
  }

  preparationCompleted(): void {
    const done = this.prepared;
    this.prepared = null;
    done?.();
  }

  async waitForPreparation(delay: (ms: number) => Promise<void>): Promise<boolean> {
    await Promise.race([this.ready, delay(6000)]);
    return this.active && !this.frame && !this.prepared;
  }

  expectAdvance(position: number, done: () => void): void {
    this.advanceAfter = position;
    this.advance = done;
  }

  positionChanged(position: number): void {
    if (!(position > this.advanceAfter)) return;
    const done = this.advance;
    this.advance = null;
    done?.();
  }

  cancel(): void {
    this.cancelled = true;
    this.frameRendered();
    this.preparationCompleted();
    const done = this.advance;
    this.advance = null;
    done?.();
  }
}

export interface FeedPresentation {
  surfacePrepared?: boolean;
  current: () => boolean;
  canStart: () => boolean;
  canReveal: () => boolean;
  waitForAdvance: (position: number, advanced: () => void) => void;
  alignAudio: () => Promise<void>;
  startVideo: () => Promise<void>;
  error: () => string;
  reveal: (visible: boolean) => void;
  delay: (ms: number) => Promise<void>;
}

/** Pause a decoder that began playing while the outgoing still covered it. */
export async function pauseFeedBehindStill(player: PlaybackPlayer, current: () => boolean,
  delay: (ms: number) => Promise<void>): Promise<boolean> {
  if (!current()) return false;
  if (player.state !== 'playing') return true;
  await player.pause();
  const deadline = Date.now() + 1500;
  while (player.state === 'playing' && Date.now() < deadline) {
    if (!current()) return false;
    await delay(16);
  }
  if (!current()) return false;
  if (player.state === 'playing') throw new Error('主播放器暂停超时');
  return true;
}

/** Keep the still visible until the active decoder advances and its Surface can be shown. */
export async function presentFeedPlayback(player: PlaybackPlayer, request: FeedPresentation): Promise<boolean> {
  while (request.current()) {
    while (!request.canStart()) {
      if (!request.current()) return false;
      await request.delay(16);
    }
    if (!request.current()) return false;
    // A warm decoder already has a frame. Move its Surface under the pinned
    // image before starting playback, so that resize/reposition and the first
    // visible video update happen while the image is still covering the slot.
    if (request.surfacePrepared) {
      request.reveal(true);
    }
    let advancing = false;
    const presented = new Promise<void>((resolve) => {
      request.waitForAdvance(player.currentTime, () => { advancing = true; resolve(); });
    });
    await request.alignAudio();
    if (!request.current()) return false;
    const state = String(player.state);
    if (state === 'completed') throw new Error('主播放器已播完，拒绝从头起播');
    if (state !== 'playing') await request.startVideo();
    await Promise.race([presented, request.delay(15000)]);
    if (!request.current()) return false;
    if (!advancing) {
      const error = request.error();
      if (error) throw new Error(error);
      if (request.canReveal()) throw new Error('主播放器起播后进度未推进');
      request.reveal(false);
      continue;
    }
    request.reveal(true);
    await request.delay(64);
    if (!request.current()) return false;
    if (!request.canReveal()) {
      request.reveal(false);
      if (String(player.state) === 'playing') await player.pause();
      continue;
    }
    return true;
  }
  return false;
}
