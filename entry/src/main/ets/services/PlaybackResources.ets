import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import type { PlaybackPlayer } from './PlaybackPlayer';
import type { DashPlayerBridge } from './DashPlayerBridge';
import type { DashServerHandle, PlayerService } from './PlayerService';
import type { FeedPlaybackHandles } from './FeedPlaybackSession';
import { logInfo, logWarn } from '../utils/Logger';

export interface RetiredPlayback {
  video: PlaybackPlayer;
  audioPlayer: PlaybackPlayer | null;
  bridge: DashServerHandle | null;
}

/** Detach page listeners and start releasing an already-disowned player. */
async function retirePlaybackPlayer(player: PlaybackPlayer, video: boolean): Promise<void> {
  try {
    player.off('stateChange');
    // Release removes timeUpdate asynchronously, avoiding synchronous media IPC on exit.
    player.off('error');
    if (video) {
      player.off('videoSizeChange');
      player.off('startRenderFrame');
    }
    player.off('seekDone');
  } catch (error) {
    logWarn('移除播放器监听失败', error);
  }
  try {
    await player.release();
  } catch (error) {
    logWarn(video ? '释放视频播放器失败' : '释放音频播放器失败', error);
  }
}

async function stopPlaybackBridge(bridge: DashServerHandle): Promise<void> {
  try {
    await bridge.stop();
  } catch (error) {
    logWarn('停止播放转播站失败', error);
  }
}

/** Retire only the handles from the completed handoff. */
export async function retirePlayback(handles: RetiredPlayback): Promise<void> {
  const pending = [retirePlaybackPlayer(handles.video, true)];
  if (handles.audioPlayer) pending.push(retirePlaybackPlayer(handles.audioPlayer, false));
  if (handles.bridge) pending.push(stopPlaybackBridge(handles.bridge));
  await Promise.all(pending);
}

/** The old decoded buffer remains available until the new Surface has been installed. */
export function retireAfterSurfaceSwap(handles: RetiredPlayback): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => { retirePlayback(handles).finally(resolve); }, 100);
  });
}

/** Prevents a decoder from binding the spare Surface before prior owners retire. */
export class PlaybackSurfaceRetirement {
  private pending: Promise<void> = Promise.resolve();

  track(retirement: Promise<void>): Promise<void> {
    this.pending = Promise.all([this.pending, retirement]).then(() => {});
    return retirement;
  }

  wait(): Promise<void> {
    return this.pending;
  }
}

/** Resources owned by the current page, excluding players already transferred to PiP. */
export class PlaybackResources {
  video: PlaybackPlayer | null = null;
  audio: PlaybackPlayer | null = null;
  bridge: DashPlayerBridge | null = null;
  restoredBridge: DashServerHandle | null = null;
  private videoFile: fs.File | null = null;
  private audioFile: fs.File | null = null;

  private fadeToken: number = 0;
  private gain: number = 1;

  get audioGain(): number { return this.gain; }

  set audioGain(value: number) {
    this.fadeToken++;
    this.gain = value;
  }

  /** Soften discontinuities when seek pauses and restarts audio. */
  rampAudio(to: number, durationMs: number): void {
    const video = this.video;
    const audio = this.audio;
    const player = audio ?? video;
    if (!player) return;
    const token = ++this.fadeToken;
    const from = this.gain;
    if (durationMs <= 0 || Math.abs(to - from) < 0.02) {
      try { player.setVolume(to); } catch (_error) {}
      this.gain = to;
      return;
    }
    const stepMs = Math.max(1, Math.round(durationMs / 6));
    const steps = Math.max(2, Math.round(durationMs / stepMs));
    let step = 0;
    const tick = (): void => {
      if (token !== this.fadeToken || this.video !== video || this.audio !== audio) return;
      step++;
      const gain = from + (to - from) * (step / steps);
      try { player.setVolume(gain); } catch (_error) {}
      this.gain = gain;
      if (step < steps) setTimeout(tick, stepMs);
      else logInfo(`[VideoPlayer] audio ramp → ${to.toFixed(2)} done`);
    };
    setTimeout(tick, stepMs);
  }

  async setPlaying(video: PlaybackPlayer, playing: boolean, currentIntent: () => boolean): Promise<boolean> {
    const audio = this.audio;
    if (this.video !== video || !currentIntent()) return false;
    if (playing) await video.play();
    else await video.pause();
    if (this.video !== video || this.audio !== audio || !currentIntent()) return false;
    if (playing) await audio?.play();
    else await audio?.pause();
    return this.video === video && this.audio === audio && currentIntent();
  }

  async setSpeed(speed: media.PlaybackSpeed, currentIntent: () => boolean): Promise<boolean> {
    const video = this.video;
    const audio = this.audio;
    if (!video || !currentIntent()) return false;
    await video.setSpeed(speed);
    if (this.video !== video || this.audio !== audio || !currentIntent()) return false;
    await audio?.setSpeed(speed);
    return this.video === video && this.audio === audio && currentIntent();
  }

  bindOfflineSource(player: PlaybackPlayer, path: string, video: boolean): void {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    // Record ownership before assigning fdSrc, which can fail synchronously.
    if (video) this.videoFile = file;
    else this.audioFile = file;
    const source: media.AVFileDescriptor = { fd: file.fd, offset: 0 };
    player.fdSrc = source;
  }

  adoptPrepared(handles: FeedPlaybackHandles): void {
    this.video = handles.video;
    this.audio = handles.audioPlayer;
    this.bridge = handles.bridge;
    this.restoredBridge = null;
  }

  replaceForQuality(handles: FeedPlaybackHandles, previous: PlaybackPlayer): RetiredPlayback {
    const outgoing: RetiredPlayback = {
      video: previous, audioPlayer: this.audio, bridge: this.bridge ?? this.restoredBridge
    };
    previous.setVolume(0);
    this.audio?.setVolume(0);
    this.adoptPrepared(handles);
    return outgoing;
  }

  /** PiP has started with these same players. Remove the old page listeners before it takes over. */
  handOffToFloating(service: PlayerService, takeOver: () => void): void {
    if (!this.video && !this.audio) return;
    if (this.video) {
      this.video.off('stateChange');
      this.video.off('timeUpdate');
      this.video.off('error');
      this.video.off('videoSizeChange');
    }
    if (this.audio) {
      this.audio.off('stateChange');
      this.audio.off('seekDone');
      this.audio.off('error');
    }
    const bridge = this.bridge ?? this.restoredBridge;
    if (bridge) {
      service.setDashServer(bridge);
      this.bridge = null;
      this.restoredBridge = null;
    }
    takeOver();
    this.video = null;
    this.audio = null;
  }

  restoreFromFloating(service: PlayerService): boolean {
    this.video = service.videoPlayer;
    this.audio = service.audioPlayer;
    this.restoredBridge = service.takeDashServer();
    service.hasActivePlayer = false;
    service.videoPlayer = null;
    service.audioPlayer = null;
    service.playerState = null;
    return this.restoredBridge !== null;
  }

  release(): Promise<void>[] {
    const video = this.video;
    const audio = this.audio;
    const bridge = this.bridge;
    const restored = this.restoredBridge;
    const videoFile = this.videoFile;
    const audioFile = this.audioFile;
    // Native release and listener removal may reenter callbacks.
    this.video = null;
    this.audio = null;
    this.bridge = null;
    this.restoredBridge = null;
    this.videoFile = null;
    this.audioFile = null;
    const pending: Promise<void>[] = [];
    if (video) pending.push(retirePlaybackPlayer(video, true));
    if (audio) pending.push(retirePlaybackPlayer(audio, false));
    if (bridge) stopPlaybackBridge(bridge);
    if (restored && restored !== bridge) stopPlaybackBridge(restored);
    if (videoFile) {
      try { fs.closeSync(videoFile); } catch (_error) {}
    }
    if (audioFile) {
      try { fs.closeSync(audioFile); } catch (_error) {}
    }
    return pending;
  }
}
