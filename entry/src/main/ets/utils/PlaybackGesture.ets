export type PlaybackDragAxis = 'seek' | 'level' | '';

export function playbackDragAxis(dx: number, dy: number): PlaybackDragAxis {
  const x = Math.abs(dx);
  const y = Math.abs(dy);
  if (x >= 24 && x >= y * 1.5) return 'seek';
  if (y >= 12 && y >= x * 1.2) return 'level';
  return '';
}

/** Seconds traversed by a horizontal drag across one playback window. */
export function playbackSeekSpan(duration: number): number {
  if (duration <= 600) return duration * 0.5;
  if (duration <= 3600) return duration * 0.3;
  return Math.max(duration * 0.12, 600);
}
