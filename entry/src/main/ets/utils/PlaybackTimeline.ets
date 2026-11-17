import { media } from '@kit.MediaKit';

export function shouldResumeAfterSeek(state: media.AVPlayerState, duration: number, target: number,
  wasPlaying: boolean, userPaused: boolean, hasSeparateAudio: boolean, wasCompleted: boolean): boolean {
  const endedAtEof = state === 'completed' || (duration > 0 && target >= duration - 1.5);
  return wasPlaying && !userPaused && !endedAtEof &&
    (hasSeparateAudio || wasCompleted || state !== 'playing');
}

export function seekEndedAtCompletion(state: media.AVPlayerState, duration: number,
  target: number, completionReported: boolean): boolean {
  return state === 'completed' && (completionReported || target >= duration - 1.5);
}
