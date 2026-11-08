import { SunVectorData as D } from './SunVectorData';
import { IconFrames } from './IconFrames';

// Evaluates the original sun asset's ellipse and eight animated rounded rects.
// This deliberately supports the verified asset, not arbitrary Lottie documents.
export class SunVector {
  private static sample(keys: number[][], frame: number): number[] {
    for (let i: number = 0; i < keys.length - 1; i++) {
      if (frame <= keys[i + 1][0]) {
        const t: number = Math.max(0, (frame - keys[i][0]) / (keys[i + 1][0] - keys[i][0]));
        return keys[i].slice(1).map((value: number, index: number): number =>
          value + (keys[i + 1][index + 1] - value) * t);
      }
    }
    return keys[keys.length - 1].slice(1);
  }

  static contours(value: number, sliderLength: number): number[][] {
    const frame: number = IconFrames.sun(value, sliderLength);
    const size: number[] = SunVector.sample(D.raySizeKeys, frame);
    const position: number[] = SunVector.sample(D.rayPositionKeys, frame);
    const rotation: number = SunVector.sample(D.rotationKeys, frame)[0] * Math.PI / 180;
    const contours: number[][] = [];
    for (let ray: number = 0; ray < D.rays.length; ray++) {
      const transform: number[] = D.rays[ray];
      const angle: number = transform[0] * Math.PI / 180;
      const points: number[] = [];
      const radius: number = Math.min(D.rayRadius, size[0] / 2, size[1] / 2);
      for (let corner: number = 0; corner < 4; corner++) {
        const cx: number = (corner === 0 || corner === 3 ? 1 : -1) * (size[0] / 2 - radius);
        const cy: number = (corner < 2 ? 1 : -1) * (size[1] / 2 - radius);
        for (let step: number = 0; step <= 16; step++) {
          const a: number = (corner * Math.PI / 2) + step * Math.PI / 32;
          const x: number = cx + radius * Math.cos(a) + position[0] + transform[5] - transform[3];
          const y: number = cy + radius * Math.sin(a) + position[1] + transform[6] - transform[4];
          const lx: number = (x * Math.cos(angle) - y * Math.sin(angle) + transform[1]) * D.parentScale[0] / 100;
          const ly: number = (x * Math.sin(angle) + y * Math.cos(angle) + transform[2]) * D.parentScale[1] / 100;
          points.push(lx * Math.cos(rotation) - ly * Math.sin(rotation) + D.parentPosition[0],
            lx * Math.sin(rotation) + ly * Math.cos(rotation) + D.parentPosition[1]);
        }
      }
      contours.push(points);
    }
    const scale: number[] = SunVector.sample(D.circleScaleKeys, frame);
    const circle: number[] = [];
    for (let i: number = 0; i < 192; i++) {
      const angle: number = i * Math.PI * 2 / 192;
      circle.push(D.circlePosition[0] + D.circleSize[0] * scale[0] / 200 * Math.cos(angle),
        D.circlePosition[1] + D.circleSize[1] * scale[1] / 200 * Math.sin(angle));
    }
    contours.push(circle);
    return contours;
  }
}
