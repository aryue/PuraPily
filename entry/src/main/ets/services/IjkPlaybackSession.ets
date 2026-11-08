import { IjkMediaPlayer, VideoCodecMode } from '@ohos/ijkplayer';
import { fileIo } from '@kit.CoreFileKit';
import { selectDashVideo } from '../utils/DashQuality';
import type { PlayUrlResult } from '../api/BilibiliApi';

export interface IjkPlaybackEvents {
  prepared: (duration: number) => void;
  time: (position: number) => void;
  rendered: () => void;
  completed: () => void;
  failed: (code: number) => void;
}

export interface IjkSourceFactory {
  create(video: string, audio: string): string;
}

/** Owns one IJK player and descriptor until the host explicitly releases it.
 * The XComponent host must outlive page-to-PiP handoffs.
 */
export class IjkPlaybackSession {
  private player: IjkMediaPlayer | null = null;
  private descriptor: string = '';
  private timer: number = -1;
  private generation: number = 0;
  private prepared: boolean = false;
  private autoplay: boolean = true;
  private speed: number = 1;
  private volume: number = 1;
  private resumeMs: number = 0;
  private rendered: boolean = false;
  private events: IjkPlaybackEvents;
  private sourceFactory: IjkSourceFactory;

  constructor(events: IjkPlaybackEvents, sourceFactory: IjkSourceFactory) {
    this.events = events;
    this.sourceFactory = sourceFactory;
  }

  getPosition(): number { return this.player?.getCurrentPosition() || 0; }
  getDuration(): number { return this.player?.getDuration() || 0; }

  open(context: object, componentId: string, result: PlayUrlResult,
    position: number = 0, autoplay: boolean = true): void {
    const dash = result.dash;
    if (!dash || !dash.audioStreams.length) throw new Error('IJK requires separate DASH tracks');
    const video = selectDashVideo(dash.videoStreams, dash.quality);
    if (!video || (video.codecid !== 7 && video.codecid !== 12)) {
      throw new Error('IJK rendition is unsupported');
    }
    const descriptor = this.sourceFactory.create(video.baseUrl, dash.audioStreams[0].baseUrl);
    if (!descriptor) throw new Error('Cannot create IJK source');
    this.release();
    this.descriptor = descriptor;
    const generation = this.generation;
    this.autoplay = autoplay;
    this.resumeMs = Math.max(0, Math.round(position));
    const player = new IjkMediaPlayer();
    this.player = player;
    try {
      player.setContext(context, componentId);
      player.native_setup(VideoCodecMode.SURFACE);
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'iformat', 'puradual');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-all-videos', '1');
      // 内核默认 max-fps=31，会把 60/120fps 源按「过高帧率」处理并在软解时丢非参考帧。
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'max-fps', '121');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'seek-at-start', String(this.resumeMs));
      player.setOnPreparedListener({ onPrepared: (): void => {
        if (generation !== this.generation) return;
        this.prepared = true;
        player.setSpeed(String(this.speed));
        player.setVolume(String(this.volume), String(this.volume));
        this.events.prepared(player.getDuration());
        // Event handlers may navigate away or replace this session.
        if (generation !== this.generation) return;
        if (this.autoplay) player.start();
        this.timer = setInterval(() => {
          if (generation === this.generation) this.events.time(player.getCurrentPosition());
        }, 250);
      } });
      player.setOnInfoListener({ onInfo: (what: number): void => {
        if (generation !== this.generation || what !== 3 || this.rendered) return;
        this.rendered = true;
        this.events.rendered();
      } });
      player.setOnCompletionListener({ onCompletion: (): void => {
        if (generation !== this.generation) return;
        this.autoplay = false;
        this.events.completed();
      } });
      player.setOnErrorListener({ onError: (code: number): void => {
        if (generation !== this.generation) return;
        this.release();
        this.events.failed(code);
      } });
      player.setMessageListener();
      player.setDataSource(descriptor);
      player.prepareAsync();
    } catch (error) {
      this.release();
      throw new Error(error instanceof Error ? error.message : 'IJK setup failed');
    }
  }

  play(): void {
    this.autoplay = true;
    if (this.prepared) this.player?.start();
  }

  pause(): void {
    this.autoplay = false;
    if (this.prepared) this.player?.pause();
  }

  seek(position: number): void {
    this.resumeMs = Math.max(0, Math.round(position));
    if (this.prepared) this.player?.seekTo(String(this.resumeMs));
    else this.player?.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'seek-at-start', String(this.resumeMs));
  }

  setSpeed(speed: number): void {
    this.speed = speed;
    if (this.prepared) this.player?.setSpeed(String(speed));
  }

  setVolume(volume: number): void {
    this.volume = Math.max(0, Math.min(1, volume));
    if (this.prepared) this.player?.setVolume(String(this.volume), String(this.volume));
  }

  release(): void {
    this.generation++;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.prepared = false;
    this.rendered = false;
    const player = this.player;
    this.player = null;
    const descriptor = this.descriptor;
    this.descriptor = '';
    try { player?.release(); } finally {
      if (descriptor) fileIo.unlink(descriptor).catch(() => {});
    }
  }
}
