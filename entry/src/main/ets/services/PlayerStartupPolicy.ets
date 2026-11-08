import type { media } from '@kit.MediaKit';

/**
 * Keep the native DASH startup and rebuffering policy. Forcing a 0.5s
 * startup waterline can render one frame then stall both tracks on 4K60.
 * A complete prefetched segment does not imply native playback readiness.
 */
export function startupPlaybackStrategy(): media.PlaybackStrategy {
  return {};
}
