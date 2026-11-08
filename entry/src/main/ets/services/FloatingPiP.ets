import type { PlaybackPlayer } from './PlaybackPlayer';
import PiPWindow from '@ohos.PiPWindow';
import { UIContext } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { FloatingVideoSurface } from './FloatingVideoSurface';
import { FloatingVideoTransition } from './FloatingVideoTransition';
import { LiveViewHelper } from './LiveViewHelper';
import { PlayerService } from './PlayerService';
import { logInfo, logWarn } from '../utils/Logger';

/** One system PiP session owns the floating video, both inside and outside the app. */
export class FloatingPiP {
  private static instance_: FloatingPiP = new FloatingPiP();
  private controller_: PiPWindow.PiPController | null = null;
  private uiContext_: UIContext | null = null;
  private opening_: boolean = false;
  private active_: boolean = false;
  private restoring_: boolean = false;
  private closing_: boolean = false;
  private restoreFrame_: Promise<void> | null = null;
  private observedVideo_: PlaybackPlayer | null = null;
  private onPlaybackState_: (state: string) => void = (state: string): void => {
    const player = PlayerService.getInstance();
    if (player.videoPlayer !== this.observedVideo_) return;
    player.playbackState = state === 'playing' ? 'playing' : 'paused';
    if (player.playerState) player.playerState.isPlaying = state === 'playing';
    if (state === 'completed') {
      LiveViewHelper.updateProgress((this.observedVideo_?.duration || 0) / 1000);
    }
    if (state === 'playing' || state === 'paused' || state === 'completed') {
      LiveViewHelper.updatePlayState(state === 'playing');
    }
    this.syncPlayback();
  };
  private onPlaybackTime_: (time: number) => void = (time: number): void => {
    const player = PlayerService.getInstance();
    if (player.videoPlayer !== this.observedVideo_) return;
    if (player.playerState) player.playerState.currentTime = time / 1000;
    if (this.observedVideo_?.state === 'playing') {
      player.getDashServer?.()?.prefetchForPlayback?.(time, player.playerState?.playbackRate || 1);
    }
    AppStorage.setOrCreate('cardCurrentTime', time / 1000);
    LiveViewHelper.updateProgress(time / 1000);
  };
  private seekPlayer_: PlaybackPlayer | null = null;
  private pendingSeekMs_: number = -1;
  private lastSeekAt_: number = 0;
  private seekDelay_: number = -1;
  private seekInterval_: number = -1;
  private seekDirection_: number = 0;
  private seekHeld_: boolean = false;
  private seekWasPlaying_: boolean = false;

  static getInstance(): FloatingPiP { return FloatingPiP.instance_; }

  async open(uiContext: UIContext, width: number, height: number): Promise<boolean> {
    if (this.active_) return true;
    if (this.opening_ || AppStorage.get<boolean>('appInBackground') || !PiPWindow.isPiPEnabled()) return false;
    this.opening_ = true;
    this.uiContext_ = uiContext;
    try {
      await this.detach();
      if (!await FloatingVideoSurface.waitForLayout()) throw new Error('Source video layout is not ready');
      const controller = await PiPWindow.create({
        context: uiContext.getHostContext(), componentController: FloatingVideoSurface.controller,
        contentWidth: Math.max(1, Math.round(width)), contentHeight: Math.max(1, Math.round(height)),
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        controlGroups: [PiPWindow.VideoPlayControlGroup.FAST_FORWARD_BACKWARD]
      });
      this.controller_ = controller;
      this.restoring_ = false;
      this.closing_ = false;
      controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        if (this.controller_ !== controller) return;
        const video = PlayerService.getInstance().videoPlayer;
        logInfo(`[FloatingPiP] state=${state}, reason=${reason}, surface=${video?.surfaceId}, time=${video?.currentTime}, player=${video?.state}`);
        if (state === PiPWindow.PiPState.ABOUT_TO_START) {
          AppStorage.setOrCreate('floatingPiPActive', true);
        } else if (state === PiPWindow.PiPState.STARTED) {
          this.active_ = true;
          FloatingVideoSurface.bindPlayer();
          FloatingVideoSurface.park();
          this.syncPlayback();
        } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
          this.restoring_ = true;
          if (this.uiContext_ && FloatingVideoTransition.source) FloatingVideoSurface.prepare(this.uiContext_, FloatingVideoTransition.source);
          this.restoreFrame_ = this.preservePausedFrame();
          this.restorePlayer();
        } else if (state === PiPWindow.PiPState.STOPPED) {
          this.active_ = false;
          AppStorage.setOrCreate('floatingPiPActive', false);
          if (this.restoring_) {
            this.restoring_ = false;
            this.endPlaybackObservation();
            this.disposeController(controller);
          } else if (!this.closing_ && (reason === 'panelActionDelete' || reason === 'dragDelete' || reason === '0')) {
            this.endPlaybackObservation();
            this.disposeController(controller);
            FloatingVideoSurface.park();
            LiveViewHelper.end();
            AppStorage.set('videoMinimized', false);
            AppStorage.set('minimizedVideoState', '');
            FloatingVideoTransition.clearPausedFrame();
            PlayerService.getInstance().release();
          }
        } else if (state === PiPWindow.PiPState.ERROR) {
          this.active_ = false;
          AppStorage.setOrCreate('floatingPiPActive', false);
        }
      });
      controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
        if (event === 'fastForward') { this.seekBy(15); return; }
        if (event === 'fastBackward') { this.seekBy(-15); return; }
        if (event === 'playbackStateChanged') {
          const player = PlayerService.getInstance();
          if (status === PiPWindow.PiPControlStatus.PLAY) { FloatingVideoTransition.clearPausedFrame(); player.play(); }
          else player.pause();
          this.syncPlayback();
        }
      });
      // Already visible in the foreground: Home must not start a second session.
      controller.setAutoStartEnabled(false);
      await controller.startPiP();
      FloatingVideoSurface.bindPlayer();
      return true;
    } catch (error) {
      logWarn(`[FloatingPiP] open: ${error}`);
      await this.detach();
      return false;
    } finally { this.opening_ = false; }
  }

  /** Foregrounding the app leaves the same system window and Surface in place. */
  foreground(): void { this.syncPlayback(); }

  private disposeController(controller: PiPWindow.PiPController): void {
    controller.setAutoStartEnabled(false);
    controller.off('stateChange');
    controller.off('controlPanelActionEvent');
    if (this.controller_ === controller) this.controller_ = null;
  }

  private async preservePausedFrame(): Promise<void> {
    const video = PlayerService.getInstance().videoPlayer;
    if (!video || video.state !== 'paused') return;
    try {
      const frame = await image.createPixelMapFromSurfaceWithTransformation(FloatingVideoSurface.controller.getXComponentSurfaceId(), true);
      FloatingVideoTransition.clearPausedFrame();
      FloatingVideoTransition.pausedFrame = frame;
    } catch (_error) { logWarn('[FloatingPiP] paused restore frame unavailable'); }
  }

  private async restorePlayer(): Promise<void> {
    await this.restoreFrame_;
    this.restoreFrame_ = null;
    const state = PlayerService.getInstance().playerState;
    const uiContext = this.uiContext_;
    if (!state || !uiContext) return;
    this.endPlaybackObservation();
    await FloatingVideoSurface.waitForLayout();
    // Prepare the real source node during ABOUT_TO_RESTORE, before the system
    // locates its target rectangle and starts expanding the PiP window.
    FloatingVideoTransition.begin('restore');
    FloatingVideoTransition.restoreExpanded = true;
    try {
      await uiContext.getRouter().pushUrl({ url: 'pages/VideoPlayerPage', params: {
        bvid: state.bvid, cid: state.cid, title: state.title, coverUrl: state.cover,
        initialProgress: (PlayerService.getInstance().videoPlayer?.currentTime ?? state.currentTime * 1000) / 1000
      } });
    } catch (error) {
      FloatingVideoTransition.restoreExpanded = false;
      FloatingVideoTransition.finish();
      logWarn(`[FloatingPiP] restore: ${error}`);
      await this.open(uiContext, state.videoAspectRatio * 1000, 1000);
    }
  }

  takeoverPlayback(): void {
    this.endPlaybackObservation();
    const player = PlayerService.getInstance();
    this.observedVideo_ = player.videoPlayer;
    this.observedVideo_?.on('stateChange', this.onPlaybackState_);
    this.observedVideo_?.on('timeUpdate', this.onPlaybackTime_);
    LiveViewHelper.setControlHandlers({
      play: () => { FloatingVideoTransition.clearPausedFrame(); player.play(); this.syncPlayback(); },
      pause: () => { player.pause(); this.syncPlayback(); },
      seek: (time: number) => {
        const current = player.videoPlayer?.currentTime ?? 0;
        this.pendingSeekMs_ = -1;
        this.seekBy((time - current) / 1000);
      }
    });
  }

  private endPlaybackObservation(): void {
    if (!this.observedVideo_) return;
    this.observedVideo_.off('stateChange', this.onPlaybackState_);
    this.observedVideo_.off('timeUpdate', this.onPlaybackTime_);
    this.observedVideo_ = null;
    LiveViewHelper.setControlHandlers({});
  }

  beginSeek(direction: number): void {
    this.endSeek(true);
    this.seekDirection_ = direction;
    this.seekDelay_ = setTimeout(() => {
      this.seekDelay_ = -1;
      const player = PlayerService.getInstance();
      if (!player.hasActivePlayer) return;
      this.seekHeld_ = true;
      this.seekWasPlaying_ = player.playbackState === 'playing';
      if (this.seekWasPlaying_) player.pause();
      this.seekBy(this.seekDirection_ * 2);
      this.seekInterval_ = setInterval(() => this.seekBy(this.seekDirection_ * 2), 160);
    }, 380);
  }

  endSeek(cancelled: boolean = false): void {
    if (this.seekDelay_ !== -1) clearTimeout(this.seekDelay_);
    if (this.seekInterval_ !== -1) clearInterval(this.seekInterval_);
    this.seekDelay_ = -1;
    this.seekInterval_ = -1;
    if (this.seekHeld_) {
      if (this.seekWasPlaying_) PlayerService.getInstance().play();
    } else if (!cancelled && this.seekDirection_ !== 0) {
      this.seekBy(this.seekDirection_ * 15);
    }
    this.seekDirection_ = 0;
    this.seekHeld_ = false;
    this.seekWasPlaying_ = false;
    this.syncPlayback();
  }

  /** 应用内与系统画中画共用固定秒数跳转，音视频同步且保留播放/暂停状态。 */
  seekBy(seconds: number): void {
    const player = PlayerService.getInstance();
    const video = player.videoPlayer;
    if (!player.hasActivePlayer || !video) return;
    try {
      let current = player.audioPlayer ? player.audioPlayer.currentTime : video.currentTime;
      if (!Number.isFinite(current) || current < 0) current = video.currentTime;
      if (!Number.isFinite(current) || current < 0) current = 0;
      const now = Date.now();
      // seek 完成前的连续点击也应累计，不能反复从尚未更新的 currentTime 跳转。
      if (this.seekPlayer_ === video && this.pendingSeekMs_ >= 0 && now - this.lastSeekAt_ < 1200 &&
        Math.abs(current - this.pendingSeekMs_) > 750) current = this.pendingSeekMs_;
      const duration = video.duration > 0 ? video.duration : (player.playerState?.duration ?? 0) * 1000;
      let target = Math.max(0, Math.round(current + seconds * 1000));
      if (Number.isFinite(duration) && duration > 0) target = Math.min(duration, target);
      video.seek(target, media.SeekMode.SEEK_CLOSEST);
      FloatingVideoTransition.clearPausedFrame();
      player.audioPlayer?.seek(target, media.SeekMode.SEEK_CLOSEST);
      this.seekPlayer_ = video;
      this.pendingSeekMs_ = target;
      this.lastSeekAt_ = now;
      if (player.playerState) player.playerState.currentTime = target / 1000;
      AppStorage.setOrCreate('cardCurrentTime', target / 1000);
      LiveViewHelper.updateProgress(target / 1000);
      logInfo(`[FloatingPiP] seekBy(${seconds}): ${current} -> ${target}ms`);
    } catch (error) { logWarn(`[FloatingPiP] seek: ${error}`); }
  }

  syncPlayback(): void {
    try {
      this.controller_?.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
      PlayerService.getInstance().playbackState === 'playing' ?
        PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE);
    } catch (error) { logWarn(`[FloatingPiP] sync: ${error}`); }
  }

  async detach(): Promise<void> {
    this.endSeek(true);
    this.endPlaybackObservation();
    const controller = this.controller_;
    if (!controller) return;
    this.closing_ = true;
    controller.setAutoStartEnabled(false);
    if (this.active_) {
      try { await controller.stopPiP(); } catch (error) { logWarn(`[FloatingPiP] detach: ${error}`); }
    }
    this.disposeController(controller);
    this.active_ = false;
    AppStorage.setOrCreate('floatingPiPActive', false);
  }
}
