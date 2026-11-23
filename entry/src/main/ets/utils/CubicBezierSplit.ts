export interface CubicBezierControlPoints {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export interface CubicBezierSplit {
  timeFraction: number;
  first: CubicBezierControlPoints;
  second: CubicBezierControlPoints;
}

interface Point {
  x: number;
  y: number;
}

function interpolate(a: Point, b: Point, t: number): Point {
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
}

/** Split a curve with monotonic progress at a progress strictly between 0 and 1. */
export function splitCubicBezierAtProgress(curve: CubicBezierControlPoints, progress: number): CubicBezierSplit {
  let low = 0;
  let high = 1;
  for (let i = 0; i < 32; i++) {
    const t = (low + high) / 2;
    const inv = 1 - t;
    const y = 3 * inv * inv * t * curve.y1 + 3 * inv * t * t * curve.y2 + t * t * t;
    if (y < progress) low = t;
    else high = t;
  }

  // De Casteljau subdivision, followed by normalization to each animation's local axes.
  const t = (low + high) / 2;
  const start: Point = { x: 0, y: 0 };
  const end: Point = { x: 1, y: 1 };
  const c1: Point = { x: curve.x1, y: curve.y1 };
  const c2: Point = { x: curve.x2, y: curve.y2 };
  const a = interpolate(start, c1, t);
  const b = interpolate(c1, c2, t);
  const c = interpolate(c2, end, t);
  const d = interpolate(a, b, t);
  const e = interpolate(b, c, t);
  const split = interpolate(d, e, t);
  return {
    timeFraction: split.x,
    first: { x1: a.x / split.x, y1: a.y / split.y, x2: d.x / split.x, y2: d.y / split.y },
    second: {
      x1: (e.x - split.x) / (1 - split.x), y1: (e.y - split.y) / (1 - split.y),
      x2: (c.x - split.x) / (1 - split.x), y2: (c.y - split.y) / (1 - split.y)
    }
  };
}
