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

interface BezierPoint {
  x: number;
  y: number;
}

function interpolate(start: BezierPoint, end: BezierPoint, fraction: number): BezierPoint {
  return {
    x: start.x + (end.x - start.x) * fraction,
    y: start.y + (end.y - start.y) * fraction
  };
}

export function splitCubicBezierAtProgress(curve: CubicBezierControlPoints,
  progress: number): CubicBezierSplit {
  let low = 0;
  let high = 1;
  for (let index = 0; index < 32; index++) {
    const fraction = (low + high) / 2;
    const inverse = 1 - fraction;
    const value = 3 * inverse * inverse * fraction * curve.y1 +
      3 * inverse * fraction * fraction * curve.y2 + fraction * fraction * fraction;
    if (value < progress) low = fraction;
    else high = fraction;
  }

  const fraction = (low + high) / 2;
  const start: BezierPoint = { x: 0, y: 0 };
  const end: BezierPoint = { x: 1, y: 1 };
  const control1: BezierPoint = { x: curve.x1, y: curve.y1 };
  const control2: BezierPoint = { x: curve.x2, y: curve.y2 };
  const firstControl = interpolate(start, control1, fraction);
  const middleControl = interpolate(control1, control2, fraction);
  const lastControl = interpolate(control2, end, fraction);
  const firstInner = interpolate(firstControl, middleControl, fraction);
  const secondInner = interpolate(middleControl, lastControl, fraction);
  const split = interpolate(firstInner, secondInner, fraction);
  return {
    timeFraction: split.x,
    first: {
      x1: firstControl.x / split.x, y1: firstControl.y / split.y,
      x2: firstInner.x / split.x, y2: firstInner.y / split.y
    },
    second: {
      x1: (secondInner.x - split.x) / (1 - split.x),
      y1: (secondInner.y - split.y) / (1 - split.y),
      x2: (lastControl.x - split.x) / (1 - split.x),
      y2: (lastControl.y - split.y) / (1 - split.y)
    }
  };
}
