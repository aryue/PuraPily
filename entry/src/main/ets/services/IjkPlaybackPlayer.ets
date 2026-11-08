import { hilog } from '@kit.PerformanceAnalysisKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { PlaybackPlayer } from './PlaybackPlayer';
import { PlaybackEventBus } from './PlaybackEventBus';
import { PlayUrlResult } from '../api/BilibiliApi';
import { selectDashVideo } from '../utils/DashQuality';
import { PlayerService } from './PlayerService';
import { HighRefreshService } from './HighRefreshService';
import { logInfo, logWarn } from '../utils/Logger';
import native from 'libpurapily_ijk.so';

/** One native player, independent of the lifetime of any page XComponent. */
export class IjkPlaybackPlayer implements PlaybackPlayer {
  private events: PlaybackEventBus = new PlaybackEventBus();
  readonly on = this.events.on;
  readonly off = this.events.off;
  state: media.AVPlayerState = 'idle';
  width: number = 0;
  height: number = 0;
  fdSrc?: media.AVFileDescriptor;
  audioRendererInfo: audio.AudioRendererInfo = { usage: audio.StreamUsage.STREAM_USAGE_MOVIE, rendererFlags: 0 };
  videoScaleType: media.VideoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
  private surface: string = '';
  private handle: number = 0;
  private source: string = '';
  private static instances: number = 0;
  private instanceNo: number = 0;
  private position: number = 0;
  private total: number = 0;
  /** playurl 的 timelength：puradual 解不出容器时长时的唯一权威兜底。 */
  private metadataDuration: number = 0;
  private timer: number = -1;
  private preparing: Promise<void> | null = null;
  private preparedResolve: (() => void) | null = null;
  private preparedReject: ((error: Error) => void) | null = null;
  private resume: number = 0;
  private rate: number = 1;
  private volume: number = 1;
  private generation: number = 0;
  private releaseTask: Promise<void> | null = null;
  private rendererId: number = -1;
  private rendererBaseline: number[] = [];
  private streamManager: audio.AudioStreamManager | null = null;
  private rendererChanged = (renderers: audio.AudioRendererChangeInfoArray): void => {
    if (this.state === 'released') return;
    if (this.rendererId < 0) {
      const added = renderers.filter(item => !this.rendererBaseline.includes(item.streamId));
      if (added.length === 1) this.rendererId = added[0].streamId;
    }
    const renderer = renderers.find(item => item.streamId === this.rendererId);
    if (!renderer) return;
    this.audioRendererInfo = renderer.rendererInfo;
    const route: audio.AudioStreamDeviceChangeInfo = {
      devices: renderer.deviceDescriptors,
      changeReason: audio.AudioStreamDeviceChangeReason.REASON_UNKNOWN
    };
    this.events.emit('audioOutputDeviceChangeWithInfo', route);
  };

  get currentTime(): number {
    if (this.handle && (this.state === 'playing' || this.state === 'paused' || this.state === 'prepared')) {
      const reported = Math.max(0, native.controlPlayer(this.handle, 6, 0));
      this.position = reported;
    }
    return this.position;
  }
  get duration(): number { return this.total; }
  get surfaceId(): string { return this.surface; }
  set surfaceId(value: string) {
    if (!value || value === this.surface) return;
    if (this.handle && native.bindPlayer(this.handle, value) !== 0) throw new Error('IJK Surface handoff failed');
    this.surface = value;
    logInfo('[IJK] surface=' + value + ' position=' + this.position);
  }

  private changeState(state: media.AVPlayerState): void {
    this.state = state;
    logInfo('[IJK] state=' + state + ' position=' + this.position);
    this.events.emit('stateChange', state, 1);
    this.syncRefresh();
  }

  /**
   * 播放/暂停时登记到 HighRefreshService：跟随系统时系统会在无触摸时把面板降回 60Hz，
   * 播放期间由播放器自己撑住最高可用档；用户手动选了档位时以用户设置为准。
   */
  private syncRefresh(): void {
    try {
      HighRefreshService.getInstance().setPlaybackActive(this.state === 'playing', this.instanceNo);
    } catch (error) {
      logWarn('[IJK] 申请播放高刷失败: ' + String(error));
    }
  }

  /** 取第一个可用的备用源；B站 backup_url 通常是同文件的其它 CDN 域名。 */
  private static firstBackup(urls: string[] | undefined, base: string): string {
    if (!urls) return '';
    const host = base.split('/')[2];
    let fallback = '';
    for (const url of urls) {
      if (!url || !url.startsWith('https://') || url === base) continue;
      if (url.split('/')[2] !== host) return url;
      if (!fallback) fallback = url;
    }
    return fallback;
  }

  load(result: PlayUrlResult): void {
    if (this.state !== 'idle') throw new Error('IJK source is already assigned');
    const context = PlayerService.getAppContext();
    IjkPlaybackPlayer.instances++;
    this.instanceNo = IjkPlaybackPlayer.instances;
    logInfo(`[IJK] instance #${this.instanceNo} qn=${result.dash?.quality ?? 0}`);
    const dash = result.dash;
    const video = dash ? selectDashVideo(dash.videoStreams, dash.quality) : null;
    if (!context || !dash || !video || !dash.audioStreams.length) throw new Error('IJK DASH source is incomplete');
    if (video.codecid !== 7 && video.codecid !== 12) throw new Error('IJK codec is unsupported');
    hilog.info(0, 'PlaybackTraffic', 'source qn=%{public}d video_bps=%{public}d audio_bps=%{public}d width=%{public}d height=%{public}d',
      dash.quality, video.bandwidth || 0, dash.audioStreams[0].bandwidth || 0, video.width || 0, video.height || 0);
    // 官方 base_url + backup_url 多源：备用源随 descriptor 带进 native，
    // 回源慢/失败时由 cache.c 切换，避免单点 CDN 拖住首帧。
    const videoBackup = IjkPlaybackPlayer.firstBackup(video.backupUrl, video.baseUrl);
    const audioBackup = IjkPlaybackPlayer.firstBackup(dash.audioStreams[0].backupUrl, dash.audioStreams[0].baseUrl);
    hilog.info(0, 'PlaybackTraffic', 'CDN base=%{public}s backup=%{public}s',
      video.baseUrl.split('/')[2] || '', videoBackup.split('/')[2] || '');
    this.source = native.source(context.cacheDir, video.baseUrl, dash.audioStreams[0].baseUrl,
      result.mediaUserAgent || 'Mozilla/5.0', result.mediaReferer ?? 'https://www.bilibili.com/',
      AppStorage.get<string>('biliCookie') || '',
      AppStorage.get<boolean>('playbackDiskCache') !== false ? 1 : 0,
      videoBackup, audioBackup, video.bandwidth || 0, dash.audioStreams[0].bandwidth || 0);
    if (!this.source) throw new Error('IJK input creation failed');
    this.width = video.width || 0;
    this.height = video.height || 0;
    // 4K fMP4 常见 mvhd 时长为 0，puradual 可能算不出 ic->duration。
    // 先把 playurl 的 timelength 存住，prepared 时若 native 报 0 就回退到这里。
    this.metadataDuration = dash.timelength || 0;
    this.total = this.metadataDuration;
    this.changeState('initialized');
  }

  prepare(): Promise<void> {
    if (!this.preparing) this.preparing = this.prepareNative();
    return this.preparing;
  }

  private prepareNative(): Promise<void> {
    if (this.state !== 'initialized' || !this.surface) return Promise.reject(new Error('IJK surface is not ready'));
    const generation = this.generation;
    try {
      this.streamManager = audio.getAudioManager().getStreamManager();
      this.rendererBaseline = this.streamManager.getCurrentAudioRendererInfoArraySync().map(item => item.streamId);
      this.streamManager.on('audioRendererChange', this.rendererChanged);
    } catch (_) {}
    const prepared = new Promise<void>((resolve, reject) => {
      this.preparedResolve = resolve;
      this.preparedReject = reject;
    });
    this.handle = native.createPlayer((type: number, first: number, second: number): void => {
      if (generation !== this.generation || this.state === 'released') return;
      switch (type) {
        case 100: {
          const error = new Error('IJK playback failed ' + first + '/' + second) as BusinessError;
          error.code = first || second;
          logWarn('[IJK] native error=' + first + '/' + second);
          this.preparedReject?.(error);
          this.preparedReject = null;
          this.preparedResolve = null;
          this.changeState('error');
          this.events.emit('error', error);
          break;
        }
        case 200: {
          const nativeDuration = native.controlPlayer(this.handle, 7, 0);
          // 0 或明显异常的小值不能覆盖 timelength：total 一旦为 0，UI 时长/进度条
          // 全废，seek() 又把每个目标夹到 0，表现就是「时间往回跑、画面像 PPT」。
          if (nativeDuration >= 1000) {
            this.total = nativeDuration;
          } else if (this.metadataDuration > 0) {
            this.total = this.metadataDuration;
            logWarn('[IJK] native duration=' + nativeDuration + 'ms, fallback to timelength=' +
              this.metadataDuration + 'ms');
          }
          native.controlPlayer(this.handle, 4, this.rate);
          native.controlPlayer(this.handle, 5, this.volume);
          this.events.emit('videoSizeChange', this.width, this.height);
          this.changeState('prepared');
          this.preparedResolve?.();
          this.preparedResolve = null;
          this.preparedReject = null;
          break;
        }
        case 300: this.position = this.total; this.changeState('completed'); break;
        case 400: this.width = first; this.height = second; this.events.emit('videoSizeChange', first, second); break;
        case 402: this.events.emit('startRenderFrame'); break;
        case 403:
        case 413:
          try { this.rendererChanged(this.streamManager?.getCurrentAudioRendererInfoArraySync() || []); } catch (_) {}
          break;
        case 412:
          if (second === audio.InterruptHint.INTERRUPT_HINT_PAUSE || second === audio.InterruptHint.INTERRUPT_HINT_STOP)
            this.pause().catch(() => {});
          break;
        case 500:
          hilog.info(0, 'PlaybackTraffic', 'buffering start position=%{public}d', this.currentTime);
          this.events.emit('bufferingUpdate', media.BufferingInfoType.BUFFERING_START, 0); break;
        case 501:
          hilog.info(0, 'PlaybackTraffic', 'buffering end position=%{public}d', this.currentTime);
          this.events.emit('bufferingUpdate', media.BufferingInfoType.BUFFERING_END, 0); break;
        case 600:
          this.position = first;
          this.events.emit('seekDone', first);
          break;
      }
    });
    if (!this.handle || native.preparePlayer(this.handle, this.source, this.surface, this.resume) !== 0) {
      this.preparedReject?.(new Error('IJK prepare failed'));
    }
    let lastStats = 0;
    this.timer = setInterval(() => {
      if (this.state === 'playing') {
        this.events.emit('timeUpdate', this.currentTime);
        const audioMs = Math.max(0, native.controlPlayer(this.handle, 10, 0));
        const videoMs = Math.max(0, native.controlPlayer(this.handle, 11, 0));
        this.events.emit('bufferingUpdate', media.BufferingInfoType.CACHED_DURATION, Math.min(audioMs, videoMs));
      }
      const now = Date.now();
      if (this.state === 'playing' && this.handle && now - lastStats >= 2000) {
        lastStats = now;
        hilog.info(0, 'PlaybackTraffic', 'playback position=%{public}d raw=%{public}d output_fps=%{public}s decode_fps=%{public}s drop_rate=%{public}s avdiff=%{public}s audio_ms=%{public}d video_ms=%{public}d',
          this.currentTime, native.controlPlayer(this.handle, 6, 0), native.controlPlayer(this.handle, 8, 0).toFixed(2),
          native.controlPlayer(this.handle, 13, 0).toFixed(2), native.controlPlayer(this.handle, 14, 0).toFixed(3),
          native.controlPlayer(this.handle, 9, 0).toFixed(3), native.controlPlayer(this.handle, 10, 0), native.controlPlayer(this.handle, 11, 0));
      }
    }, 200);
    return prepared;
  }

  play(): Promise<void> {
    const task = Promise.resolve().then(() => {
      if (!this.handle || native.controlPlayer(this.handle, 1, 0) !== 0) throw new Error('IJK play failed');
      this.changeState('playing');
    });
    return task;
  }

  pause(): Promise<void> {
    const task = Promise.resolve().then(() => {
      if (!this.handle || native.controlPlayer(this.handle, 2, 0) !== 0) throw new Error('IJK pause failed');
      this.changeState('paused');
    });
    return task;
  }

  seek(position: number, _mode?: media.SeekMode): void {
    // total 未知时不能再拿 total-1 当上界：那会把所有 seek 目标压成 0。
    const ceiling = this.total > 0 ? Math.max(0, this.total - 1) : Number.MAX_SAFE_INTEGER;
    const target = Math.max(0, Math.min(position, ceiling));
    if (!this.handle || native.controlPlayer(this.handle, 3, target) !== 0) throw new Error('IJK seek failed');
    this.position = target;
  }

  setSpeed(speed: media.PlaybackSpeed): void {
    const rates: number[] = [0.75, 1, 1.25, 1.75, 2, 0.5, 1.5, 3, 0.25];
    this.rate = rates[speed] || 1;
    if (this.handle) native.controlPlayer(this.handle, 4, this.rate);
    this.events.emit('speedDone', speed);
  }
  setVolume(volume: number): void {
    this.volume = Math.max(0, Math.min(1, volume));
    if (this.handle) native.controlPlayer(this.handle, 5, this.volume);
  }

  setPlaybackRange(start: number, end: number, _mode?: media.SeekMode): Promise<void> {
    if (end !== -1 || this.state !== 'initialized') return Promise.reject(new Error('IJK range is unsupported'));
    this.resume = Math.max(0, start);
    return Promise.resolve();
  }

  setMediaSource(_source: media.MediaSource, _strategy?: media.PlaybackStrategy): Promise<void> {
    return Promise.reject(new Error('IJK requires the original DASH track URLs'));
  }

  getTrackDescription(): Promise<media.MediaDescription[]> {
    return Promise.resolve([]);
  }

  reset(): Promise<void> {
    return this.releaseNative().then(() => {
      this.releaseTask = null;
      this.preparing = null;
      this.position = 0;
      this.resume = 0;
      this.changeState('idle');
    });
  }
  release(): Promise<void> {
    return this.releaseNative().then(() => {
      this.changeState('released');
      this.events.clear();
    });
  }
  private releaseNative(): Promise<void> {
    if (this.releaseTask) return this.releaseTask;
    this.generation++;
    try { this.streamManager?.off('audioRendererChange', this.rendererChanged); } catch (_) {}
    this.streamManager = null;
    this.rendererId = -1;
    if (this.timer >= 0) clearInterval(this.timer);
    this.timer = -1;
    this.preparedReject?.(new Error('IJK preparation cancelled'));
    this.preparedResolve = null;
    this.preparedReject = null;
    const handle = this.handle;
    this.handle = 0;
    const path = this.source;
    this.source = '';
    this.releaseTask = (handle ? native.releasePlayer(handle) : Promise.resolve())
      .finally(() => { if (path) fileIo.unlink(path).catch(() => {}); });
    return this.releaseTask;
  }
}
