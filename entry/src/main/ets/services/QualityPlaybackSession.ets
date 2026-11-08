import type { PlaybackPlayer } from './PlaybackPlayer';
import { media } from '@kit.MediaKit';
import { PlayUrlResult } from '../api/BilibiliApi';
import { FeedPlaybackSession, FeedPlaybackHandles } from './FeedPlaybackSession';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';
import { PlaybackStartup } from '../utils/PlaybackStartup';
import type { DashServerHandle } from './PlayerService';

export interface RetiredPlayback {
  video: PlaybackPlayer;
  audioPlayer: PlaybackPlayer | null;
  bridge: DashServerHandle | null;
}

/** Retire only these captured resources; never touch the page's new owner. */
export async function retirePlayback(handles: RetiredPlayback): Promise<void> {
  const players: PlaybackPlayer[] = [handles.video];
  if (handles.audioPlayer) players.push(handles.audioPlayer);
  const tasks: Promise<void>[] = [];
  players.forEach((player: PlaybackPlayer) => {
    player.off('stateChange');
    player.off('error');
    player.off('startRenderFrame');
    player.off('seekDone');
    player.off('videoSizeChange');
    tasks.push(player.release().catch(() => {}));
  });
  if (handles.bridge) tasks.push(handles.bridge.stop().catch(() => {}));
  await Promise.all(tasks);
}

/** Decode and align a muted replacement while the original remains visible/audible. */
export class QualityPlaybackSession {
  private warm: FeedPlaybackSession;
  private handles: FeedPlaybackHandles | null = null;
  private deadline: PlaybackDeadline = new PlaybackDeadline();
  private cancelled: boolean = false;
  private taken: boolean = false;
  private cleanup: Promise<void> | null = null;
  driftMs: number = 0;

  constructor(id: string, surfaceId: string, source: PlayUrlResult, targetMs: number) {
    this.warm = new FeedPlaybackSession(id, surfaceId, source, targetMs);
  }

  async prepare(scale: media.VideoScaleType, cookie: string): Promise<boolean> {
    if (!await this.warm.prepare(scale, cookie) || this.cancelled) return false;
    this.handles = this.warm.take();
    this.handles?.video.on('error', () => this.deadline.cancel());
    this.handles?.audioPlayer?.on('error', () => this.deadline.cancel());
    return this.handles !== null;
  }

  async align(reference: PlaybackPlayer, speed: media.PlaybackSpeed, rate: number): Promise<boolean> {
    const handles = this.handles;
    if (!handles || this.cancelled) return false;
    const video = handles.video;
    const audio = handles.audioPlayer;
    let leadMs = 5000;
    video.setSpeed(speed);
    audio?.setSpeed(speed);
    for (let attempt = 0; attempt < 4 && !this.cancelled; attempt++) {
      const profile = PlaybackStartup.span('quality-align');
      profile?.mark('attempt', attempt);
      const playing = reference.state === 'playing';
      if (video.state === 'playing') await this.deadline.wait(video.pause(), '定位备用画质');
      const target = Math.max(0, Math.min(video.duration - 100, reference.currentTime + (playing ? leadMs : 0)));
      const reuseFrame = attempt === 0 && video.currentTime >= reference.currentTime - 200 &&
        (playing ? video.currentTime - reference.currentTime <= 10000 : Math.abs(video.currentTime - reference.currentTime) <= 350);
      let resolveSeek: (() => void) | null = null;
      let resolveAudioSeek: (() => void) | null = null;
      let resolvePresent: (() => void) | null = null;
      const seek = new Promise<void>((resolve) => { resolveSeek = resolve; });
      const audioSeek = audio ? new Promise<void>((resolve) => { resolveAudioSeek = resolve; }) : Promise.resolve();
      const present = new Promise<void>((resolve) => { resolvePresent = resolve; });
      video.on('seekDone', (position: number) => { profile?.mark('seek-done', position); if (!this.taken && !this.cancelled) resolveSeek?.(); });
      audio?.on('seekDone', () => { if (!this.taken && !this.cancelled) resolveAudioSeek?.(); });
      video.on('timeUpdate', (time: number) => { profile?.once('present', time); if (!this.taken && !this.cancelled) resolvePresent?.(); });
      const started = Date.now();
      try {
        if (reuseFrame) {
          profile?.mark('reuse-decoded-frame', video.currentTime);
          if (audio) {
            audio.seek(video.currentTime, media.SeekMode.SEEK_CLOSEST);
            await this.deadline.wait(audioSeek, '对齐备用音频进度');
          }
        } else {
          profile?.mark('seek-call', target);
          video.seek(target, media.SeekMode.SEEK_CLOSEST);
          audio?.seek(target, media.SeekMode.SEEK_CLOSEST);
          await this.deadline.wait(Promise.all([seek, audioSeek]), '对齐备用画质进度');
        }
        const seekMs = Date.now() - started;
        profile?.mark('seek-ready', seekMs);
        if (this.cancelled) return false;
        if (playing) {
          // Decode a future frame, then let the visible original catch up. Seeking
          // repeatedly to its moving current time chases a target we can never hit
          // when precise native seek takes 1-2 seconds.
          if (video.currentTime < reference.currentTime - 200) {
            leadMs = Math.min(10000, seekMs * rate + 1000);
            continue;
          }
          while (!this.cancelled && reference.state === 'playing' && video.currentTime - reference.currentTime > 150) {
            await this.deadline.wait(new Promise<void>((resolve) => setTimeout(resolve, 16)), '等待原画面对齐');
          }
          if (this.cancelled) return false;
          if (reference.state !== 'playing') continue;
          await this.deadline.wait(video.play(), '准备备用画质画面');
          profile?.mark('play-return');
          if (audio) await this.deadline.wait(audio.play(), '准备备用音频');
          if (!reuseFrame) await this.deadline.wait(present, '等待备用画质画面');
        }
        this.driftMs = video.currentTime - reference.currentTime;
        profile?.mark('drift', Math.round(this.driftMs));
        if (playing === (reference.state === 'playing') && Math.abs(this.driftMs) <= 350) return true;
        leadMs = Math.max(0, Math.min(10000, seekMs * rate + 1000));
      } finally { profile?.end(); resolveSeek = null; resolveAudioSeek = null; resolvePresent = null; }
    }
    return false;
  }

  take(): FeedPlaybackHandles | null {
    if (this.cancelled || this.taken || !this.handles) return null;
    const handles = this.handles;
    handles.video.off('seekDone');
    handles.video.off('error');
    handles.audioPlayer?.off('seekDone');
    handles.audioPlayer?.off('error');
    this.handles = null;
    this.taken = true;
    return handles;
  }

  release(): Promise<void> {
    if (this.taken) return Promise.resolve();
    if (this.cleanup) return this.cleanup;
    this.cancelled = true;
    this.deadline.cancel();
    const handles = this.handles;
    this.handles = null;
    const retirement: RetiredPlayback | null = handles ? {
      video: handles.video, audioPlayer: handles.audioPlayer, bridge: handles.bridge } : null;
    this.cleanup = Promise.all([this.warm.release(), retirement ? retirePlayback(retirement) : Promise.resolve()]).then(() => {});
    return this.cleanup;
  }
}
