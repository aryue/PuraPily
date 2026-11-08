import { curves } from '@kit.ArkUI';

export const HOME_CHANNEL_DURATION: number = 380;

// Approximate visible travel landmarks from the supplied recording, in ms.
// Keep the last 3% for a smooth stop rather than snapping at the last sampled frame.
const TIMES: number[] = [0, 66, 116, 167, 249, 315, HOME_CHANNEL_DURATION];
const POSITIONS: number[] = [0, 0.25, 0.5, 0.75, 0.9, 0.97, 1];

function slope(index: number): number {
  if (index === 0 || index === TIMES.length - 1) return 0;
  const before = TIMES[index] - TIMES[index - 1];
  const after = TIMES[index + 1] - TIMES[index];
  const incoming = (POSITIONS[index] - POSITIONS[index - 1]) / before;
  const outgoing = (POSITIONS[index + 1] - POSITIONS[index]) / after;
  const firstWeight = 2 * after + before;
  const secondWeight = after + 2 * before;
  // Shape-preserving Hermite slopes: continuous velocity without overshoot.
  return (firstWeight + secondWeight) / (firstWeight / incoming + secondWeight / outgoing);
}

export function homeChannelProgress(fraction: number): number {
  if (fraction <= 0) return 0;
  if (fraction >= 1) return 1;
  const time = fraction * HOME_CHANNEL_DURATION;
  let index = 0;
  while (index < TIMES.length - 2 && time > TIMES[index + 1]) index++;
  const span = TIMES[index + 1] - TIMES[index];
  const t = (time - TIMES[index]) / span;
  const squared = t * t;
  const cubed = squared * t;
  return (2 * cubed - 3 * squared + 1) * POSITIONS[index]
    + (cubed - 2 * squared + t) * span * slope(index)
    + (-2 * cubed + 3 * squared) * POSITIONS[index + 1]
    + (cubed - squared) * span * slope(index + 1);
}

export const HOME_CHANNEL_CURVE = curves.customCurve(homeChannelProgress);
