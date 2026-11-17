import { media } from '@kit.MediaKit';
import type { PlaybackPlayer } from './PlaybackPlayer';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';
import { errMsg, logInfo, logWarn } from '../utils/Logger';

export interface PlaybackPreparationRequest {
  player: PlaybackPlayer;
  surfaceId: string;
  resumeMs: number;
  isCurrent: () => boolean;
  mark: (name: string, value?: number) => void;
  onEarlyResume: (ms: number) => void;
  onPrepare: () => void;
  onError: (error: Error) => void;
}

/** The player and Surface callbacks share one native prepare operation. */
export class PlaybackPreparation {
  private player: PlaybackPlayer | null = null;
  private task: Promise<void> | null = null;

  async bind(request: PlaybackPreparationRequest): Promise<void> {
    const player = request.player;
    if (this.player === player && this.task) return this.task;
    try {
      logInfo(`[VideoPlayer] Binding surface: ${request.surfaceId}, player state: ${player.state}`);
      player.surfaceId = request.surfaceId;
      if (player.state !== 'initialized') return;
      this.player = player;
      this.task = this.prepare(request);
      await this.task;
      if (!request.isCurrent()) return;
      request.mark('prepare-return');
      logInfo('[VideoPlayer] Player prepared successfully');
    } catch (error) {
      if (request.isCurrent()) request.onError(error as Error);
    } finally {
      if (this.player === player) {
        this.player = null;
        this.task = null;
      }
    }
  }

  private async prepare(request: PlaybackPreparationRequest): Promise<void> {
    const deadline = new PlaybackDeadline();
    const player = request.player;
    if (request.resumeMs > 0) {
      try {
        request.mark('range-call', request.resumeMs);
        await deadline.wait(player.setPlaybackRange(request.resumeMs, -1, media.SeekMode.SEEK_CLOSEST), '恢复播放位置');
        if (!request.isCurrent()) return;
        request.onEarlyResume(request.resumeMs);
        request.mark('range-return', request.resumeMs);
      } catch (error) {
        if (deadline.isExpired()) throw error as Error;
        logWarn('[VideoPlayer] early resume unavailable:', errMsg(error));
        request.mark('range-fallback');
      }
    }
    if (!request.isCurrent()) return;
    request.mark('prepare-call');
    request.onPrepare();
    await deadline.wait(player.prepare(), '准备播放器');
  }
}
