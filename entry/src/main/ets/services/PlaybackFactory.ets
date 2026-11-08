import { media } from '@kit.MediaKit';
import { PlayUrlResult } from '../api/BilibiliApi';
import { selectDashVideo } from '../utils/DashQuality';
import { PlaybackPlayer } from './PlaybackPlayer';
import { IjkPlaybackPlayer } from './IjkPlaybackPlayer';

export function ijkPlaybackRequested(): boolean {
  return AppStorage.get<string>('playbackKernel') === 'ijk';
}

export function supportsIjkPlayback(result: PlayUrlResult): boolean {
  if (!ijkPlaybackRequested() || !result.dash || !result.dash.audioStreams.length ||
    result.actualQn === 125 || result.actualQn === 126) return false;
  const video = selectDashVideo(result.dash.videoStreams, result.dash.quality);
  return video !== null && (video.codecid === 7 || video.codecid === 12);
}

export function createPlaybackPlayer(result: PlayUrlResult): Promise<PlaybackPlayer> {
  return supportsIjkPlayback(result) ? Promise.resolve(new IjkPlaybackPlayer()) : media.createAVPlayer();
}
