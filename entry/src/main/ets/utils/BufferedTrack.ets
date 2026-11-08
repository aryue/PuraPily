// A hard color stop keeps the cached section distinct from the unbuffered track.
export function bufferedTrack(end: number, duration: number, base: string = '#4DFFFFFF'): LinearGradient {
  const fraction = Math.max(0, Math.min(1, end / Math.max(1, duration)));
  return {
    direction: GradientDirection.Right,
    colors: [['#B3FFFFFF', 0], ['#B3FFFFFF', fraction], [base, fraction], [base, 1]]
  };
}
