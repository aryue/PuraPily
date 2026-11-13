export const SPLIT_DEFAULT_RATIO: number = 2 / 3;
export const SPLIT_PRIMARY_MIN: number = 280;
export const SPLIT_SECONDARY_MIN: number = 220;
export const SPLIT_EXPAND_THRESHOLD: number = 0.62;
export const SPLIT_HANDLE_WIDTH: number = 32;
export const SPLIT_HANDLE_HEIGHT: number = 72;

export function clampSplitWidth(windowWidth: number, proposed: number,
  primaryMin: number = SPLIT_PRIMARY_MIN, secondaryMin: number = SPLIT_SECONDARY_MIN): number {
  const minimum = Math.min(primaryMin, windowWidth * 0.4);
  const maximum = windowWidth - Math.min(secondaryMin, windowWidth * 0.3);
  return Math.max(1, Math.max(minimum, Math.min(maximum, proposed)));
}

export function splitPrimaryWidth(windowWidth: number, ratio: number, expand: number,
  primaryMin: number = SPLIT_PRIMARY_MIN, secondaryMin: number = SPLIT_SECONDARY_MIN): number {
  const resting = clampSplitWidth(windowWidth, windowWidth * ratio, primaryMin, secondaryMin);
  return resting + (windowWidth - resting) * expand;
}

export function splitSecondaryWidth(windowWidth: number, ratio: number, inset: number,
  primaryMin: number = SPLIT_PRIMARY_MIN, secondaryMin: number = SPLIT_SECONDARY_MIN): number {
  return windowWidth - clampSplitWidth(windowWidth, windowWidth * ratio, primaryMin, secondaryMin) - 2 * inset;
}

export function splitSecondaryX(primaryWidth: number, secondaryWidth: number, inset: number,
  expand: number, swapped: boolean): number {
  return (swapped ? -(secondaryWidth + 2 * inset) * expand : primaryWidth) + inset;
}

export function splitHandleX(secondaryX: number, secondaryWidth: number, swapped: boolean,
  handleWidth: number = SPLIT_HANDLE_WIDTH): number {
  return secondaryX + (swapped ? secondaryWidth : 0) - handleWidth / 2;
}

export interface SplitResize {
  ratio: number;
  expand: number;
}

/** Keep the resting ratio clamped while reporting excess drag as a 0–1 expansion. */
export function splitResize(windowWidth: number, proposed: number,
  primaryMin: number = SPLIT_PRIMARY_MIN, secondaryMin: number = SPLIT_SECONDARY_MIN): SplitResize {
  const maximum = clampSplitWidth(windowWidth, windowWidth, primaryMin, secondaryMin);
  const expansionWidth = windowWidth - maximum;
  return {
    ratio: clampSplitWidth(windowWidth, proposed, primaryMin, secondaryMin) / windowWidth,
    expand: expansionWidth > 0 ? Math.max(0, Math.min(1, (proposed - maximum) / expansionWidth)) : 0
  };
}
