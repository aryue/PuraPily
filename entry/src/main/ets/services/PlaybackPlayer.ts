import { media } from '@kit.MediaKit';

/**
 * Playback operations consumed by the page, media session and PiP ownership
 * code. The native AVPlayer satisfies this contract without a wrapper.
 * Keeping SDK method signatures preserves the existing callback overloads.
 */
export interface PlaybackPlayer {
  readonly state: media.AVPlayerState;
  readonly currentTime: number;
  readonly duration: number;
  readonly width: number;
  readonly height: number;
  surfaceId?: string;
  fdSrc?: media.AVFileDescriptor;
  audioRendererInfo?: media.AVPlayer['audioRendererInfo'];
  videoScaleType?: media.VideoScaleType;
  on: media.AVPlayer['on'];
  off: media.AVPlayer['off'];
  play(): Promise<void>;
  pause(): Promise<void>;
  prepare(): Promise<void>;
  reset(): Promise<void>;
  release(): Promise<void>;
  seek: media.AVPlayer['seek'];
  setSpeed: media.AVPlayer['setSpeed'];
  setVolume: media.AVPlayer['setVolume'];
  setMediaSource: media.AVPlayer['setMediaSource'];
  setPlaybackRange: media.AVPlayer['setPlaybackRange'];
  getTrackDescription(): Promise<media.MediaDescription[]>;
}
