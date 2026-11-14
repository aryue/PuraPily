import { audio } from '@kit.AudioKit';
import { logWarn } from './Logger';

// 音频会话是应用级的，视频、直播和预览共用同一策略。
export class PlaybackAudioSession {
  private static appliedMode: audio.AudioConcurrencyMode | undefined;
  private static pending: Promise<void> = Promise.resolve();

  static activate(): Promise<void> {
    PlaybackAudioSession.pending = PlaybackAudioSession.pending.then(async () => {
      const mode = AppStorage.get<boolean>('mixAudioWithOtherApps') === true
        ? audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
        : audio.AudioConcurrencyMode.CONCURRENCY_DEFAULT;
      try {
        const session = audio.getAudioManager().getSessionManager();
        if (session.isAudioSessionActivated()) {
          if (PlaybackAudioSession.appliedMode === mode) return;
          await session.deactivateAudioSession();
        }
        await session.activateAudioSession({ concurrencyMode: mode });
        PlaybackAudioSession.appliedMode = mode;
      } catch (error) {
        logWarn(`应用播放音频策略失败: ${error}`);
      }
    });
    return PlaybackAudioSession.pending;
  }
}
