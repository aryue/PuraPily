import { audio } from '@kit.AudioKit';

export class PlaybackSystemVolume {
  private maxVolume: number = 15;

  read(): number | null {
    try {
      const manager = audio.getAudioManager().getVolumeManager();
      const usage = audio.StreamUsage.STREAM_USAGE_MUSIC;
      const maximum = manager.getMaxVolumeByStream(usage);
      this.maxVolume = maximum > 0 ? maximum : 15;
      const volume = manager.getVolumeByStream(usage);
      return maximum > 0 ? Math.min(1, Math.max(0, volume / maximum)) : 0.7;
    } catch (_) {
      return null;
    }
  }

  set(volume: number): void {
    try {
      audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, Math.round(volume * this.maxVolume));
    } catch (_) {}
  }
}
