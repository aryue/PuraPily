import { supportsIjkPlayback, createPlaybackPlayer } from './PlaybackFactory';
import { IjkPlaybackPlayer } from './IjkPlaybackPlayer';
import type { PlaybackPlayer } from './PlaybackPlayer';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlayUrlResult } from '../api/BilibiliApi';
import { DashPlayerBridge } from './DashPlayerBridge';
import { startupPlaybackStrategy } from './PlayerStartupPolicy';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';

export interface FeedPlaybackHandles {
  video: PlaybackPlayer;
  audioPlayer: PlaybackPlayer | null;
  bridge: DashPlayerBridge | null;
}

/** Owns the inactive slot until take() transfers all resources to the page. */
export class FeedPlaybackSession {
  readonly id: string;
  readonly surfaceId: string;
  readonly source: PlayUrlResult;
  private readonly startTimeMs: number;
  aspectRatio: number = 1;
  onSizeChanged: ((aspectRatio: number) => void) | null = null;
  ready: boolean = false;
  reserved: boolean = false;
  private video: PlaybackPlayer | null = null;
  private audioPlayer: PlaybackPlayer | null = null;
  private bridge: DashPlayerBridge | null = null;
  private cancelled: boolean = false;
  private taken: boolean = false;
  private settle: ((ready: boolean) => void) | null = null;
  private job: Promise<boolean> | null = null;
  private cleanup: Promise<void> | null = null;
  private deadline: PlaybackDeadline = new PlaybackDeadline();

  constructor(id: string, surfaceId: string, source: PlayUrlResult, startTimeMs: number = 0) {
    this.id = id;
    this.surfaceId = surfaceId;
    this.source = source;
    this.startTimeMs = startTimeMs;
  }

  prepare(scaleType: media.VideoScaleType, cookie: string): Promise<boolean> {
    if (!this.job) this.job = this.prepareOwned(scaleType, cookie);
    return this.job;
  }

  reserve(): void {
    this.reserved = true;
    this.onSizeChanged = null;
  }

  private async prepareOwned(scaleType: media.VideoScaleType, cookie: string): Promise<boolean> {
    this.deadline = new PlaybackDeadline();
    const headers: Record<string, string> = {
      'User-Agent': this.source.mediaUserAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    };
    const referer = this.source.mediaReferer ?? 'https://www.bilibili.com/';
    if (referer) headers['Referer'] = referer;
    let timer: number = -1;
    try {
      if (this.cancelled || !this.surfaceId) return false;
      let url = this.source.url;
      if (!supportsIjkPlayback(this.source) && this.source.audioUrl && this.source.dash) {
        this.bridge = new DashPlayerBridge();
        url = await this.deadline.wait(this.bridge.buildAndStart(this.source.dash, this.source.mediaReferer ?? 'https://www.bilibili.com/', headers['User-Agent'], cookie, this.startTimeMs), '准备媒体索引') || '';
      }
      if (this.cancelled || !url) return false;
      this.video = await this.createOwnedPlayer(true);
      if (this.cancelled) return false;
      const video = this.video;
      let rendered = false;
      let playing = false;
      let audioPrepared = video instanceof IjkPlaybackPlayer || !this.source.audioUrl || this.bridge !== null;
      let seekReady: (() => void) | null = null;
      video.on('seekDone', () => { seekReady?.(); seekReady = null; });
      const readiness = new Promise<boolean>((resolve) => { this.settle = resolve; });
      const check = (): void => {
        if (rendered && playing && audioPrepared) this.settle?.(true);
      };
      timer = setTimeout(() => { this.settle?.(false); }, 15000);
      video.on('stateChange', async (state: string) => {
        if (this.cancelled) return;
        try {
          if (state === 'initialized') {
            video.surfaceId = this.surfaceId;
            if (video instanceof IjkPlaybackPlayer && this.startTimeMs > 0)
              await video.setPlaybackRange(this.startTimeMs, -1);
            await video.prepare();
          } else if (state === 'prepared') {
            video.setVolume(0);
            video.videoScaleType = scaleType;
            if (this.startTimeMs > 0 && !(video instanceof IjkPlaybackPlayer)) {
              const seek = new Promise<void>((resolve) => { seekReady = resolve; });
              video.seek(this.startTimeMs, media.SeekMode.SEEK_CLOSEST);
              await this.deadline.wait(seek, '定位备用画质');
              if (this.cancelled) return;
            }
            await video.play();
          } else if (state === 'playing') {
            playing = true;
            check();
          }
        } catch (_) { this.ready = false; this.settle?.(false); }
      });
      video.on('startRenderFrame', () => { rendered = true; check(); });
      video.on('videoSizeChange', (width: number, height: number) => {
        if (width > 0 && height > 0 && !this.cancelled) {
          this.aspectRatio = width / height;
          this.onSizeChanged?.(this.aspectRatio);
        }
      });
      video.on('error', (_error: BusinessError) => { this.ready = false; this.settle?.(false); });
      if (!(video instanceof IjkPlaybackPlayer) && this.source.audioUrl && !this.bridge) {
        this.audioPlayer = await this.createOwnedPlayer();
        if (this.cancelled) return false;
        const audioPlayer = this.audioPlayer;
        audioPlayer.on('stateChange', async (state: string) => {
          if (this.cancelled) return;
          try {
            if (state === 'initialized') await audioPlayer.prepare();
            else if (state === 'prepared') {
              audioPlayer.setVolume(0);
              audioPrepared = true;
              check();
            }
          } catch (_) { this.ready = false; this.settle?.(false); }
        });
        audioPlayer.on('error', (_error: BusinessError) => { this.ready = false; this.settle?.(false); });
        await this.deadline.wait(audioPlayer.setMediaSource(media.createMediaSourceWithUrl(this.source.audioUrl, headers)), '设置音频源');
      }
      if (this.cancelled) return false;
      if (video instanceof IjkPlaybackPlayer) video.load(this.source);
      else await this.deadline.wait(video.setMediaSource(media.createMediaSourceWithUrl(url, headers), this.bridge ? startupPlaybackStrategy() : {}), '设置播放源');
      if (!await this.deadline.wait(readiness, '等待视频首帧') || this.cancelled || video.state !== 'playing') return false;
      await this.deadline.wait(video.pause(), '暂停预加载播放器');
      const pauseDeadline = Date.now() + 1000;
      while (!this.isPaused() && !this.cancelled && Date.now() < pauseDeadline) {
        await new Promise<void>((resolve) => setTimeout(resolve, 16));
      }
      this.ready = !this.cancelled && this.isPaused();
      return this.ready;
    } catch (_) {
      this.cancelled = true;
      this.ready = false;
      return false;
    } finally {
      if (timer !== -1) clearTimeout(timer);
      this.settle = null;
      if (!this.ready) await this.dispose();
    }
  }

  private async createOwnedPlayer(video: boolean = false): Promise<PlaybackPlayer> {
    const task = (video ? createPlaybackPlayer(this.source) : media.createAVPlayer()).then((player: PlaybackPlayer) => {
      if (this.cancelled) {
        player.release().catch(() => {});
        throw new Error('播放准备已取消');
      }
      return player;
    });
    return this.deadline.wait(task, '创建播放器');
  }

  private isPaused(): boolean {
    return this.video?.state === 'paused';
  }

  take(): FeedPlaybackHandles | null {
    if (!this.ready || this.cancelled || this.taken || !this.video || this.video.state !== 'paused') return null;
    this.taken = true;
    this.ready = false;
    this.detachListeners();
    const handles: FeedPlaybackHandles = { video: this.video, audioPlayer: this.audioPlayer, bridge: this.bridge };
    this.video = null;
    this.audioPlayer = null;
    this.bridge = null;
    return handles;
  }

  async release(): Promise<void> {
    if (this.taken) return;
    this.cancelled = true;
    this.deadline.cancel();
    this.ready = false;
    this.settle?.(false);
    if (this.job) await this.job;
    await this.dispose();
  }

  private detachListeners(): void {
    this.onSizeChanged = null;
    this.video?.off('stateChange');
    this.video?.off('startRenderFrame');
    this.video?.off('videoSizeChange');
    this.video?.off('error');
    this.video?.off('seekDone');
    this.audioPlayer?.off('stateChange');
    this.audioPlayer?.off('error');
  }

  private dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.detachListeners();
    const pending: Promise<void>[] = [];
    if (this.video) pending.push(this.video.release().catch(() => {}));
    if (this.audioPlayer) pending.push(this.audioPlayer.release().catch(() => {}));
    if (this.bridge) pending.push(this.bridge.stopIfRunning().catch(() => {}));
    this.video = null;
    this.audioPlayer = null;
    this.bridge = null;
    this.cleanup = Promise.all(pending).then(() => {});
    return this.cleanup;
  }
}
