// Ported from SliderIconViewData and VolumeButtonViewModel in the verified firmware.
export class IconFrames {
  static sun(value: number, sliderLength: number): number {
    return 61 + Math.ceil(Math.max(0, Math.min(1, value)) * sliderLength) * 240 / sliderLength;
  }

  static volumeLevel(value: number): number {
    return value >= 0.66 ? 3 : value >= 0.33 ? 2 : value > 0 ? 1 : 0;
  }

  static volumeRestFrame(level: number): number {
    return [0, 29, 140, 214][level];
  }

  static volumeSegment(previous: number, next: number): number[] {
    const ranges: number[][] = [[0, 29], [104, 140], [179, 214]];
    if (previous === next) { return []; }
    return next > previous ? ranges[next - 1].slice() : ranges[next].slice().reverse();
  }
}
