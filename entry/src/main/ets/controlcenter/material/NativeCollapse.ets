import { uiEffect } from '@kit.ArkGraphics2D';

interface CollapsePoint { x: number; y: number; }
interface CollapseBarrel { x: number; y: number; z: number; w: number; }
interface CollapseParameters {
  topLeft: CollapsePoint;
  topRight: CollapsePoint;
  bottomRight: CollapsePoint;
  bottomLeft: CollapsePoint;
  barrelDistortion: CollapseBarrel;
}

// Runtime extension found in the supplied firmware, absent from public SDK
// declarations. Never assume availability or bypass a runtime rejection.
interface CollapseEffect extends uiEffect.VisualEffect {
  distortionCollapse(parameters: CollapseParameters | undefined): uiEffect.VisualEffect;
}

export class NativeCollapse {
  static clear(): uiEffect.VisualEffect {
    const effect: CollapseEffect = uiEffect.createEffect() as CollapseEffect;
    return effect.distortionCollapse(undefined);
  }
  static create(frame: number[], outerScale: number = 1): uiEffect.VisualEffect {
    const effect: CollapseEffect = uiEffect.createEffect() as CollapseEffect;
    if (typeof effect.distortionCollapse !== 'function') {
      throw new Error('distortionCollapse is not exposed by this runtime');
    }
    // Keep the outer press scale continuous. Compensate the four destination
    // corners so the combined transform still reaches the original keyframe.
    const point = (x: number, y: number): CollapsePoint => {
      if (outerScale === 1) { return { x: x, y: y }; }
      return { x: 0.5 + (x - 0.5) / outerScale, y: 0.5 + (y - 0.5) / outerScale };
    };
    const result: uiEffect.VisualEffect = effect.distortionCollapse({
      topLeft: point(frame[0], frame[1]), topRight: point(frame[2], frame[3]),
      bottomRight: point(frame[4], frame[5]), bottomLeft: point(frame[6], frame[7]),
      barrelDistortion: { x: frame[8], y: frame[9], z: frame[10], w: frame[11] }
    });
    if (result === undefined || result === null) { throw new Error('distortionCollapse returned no effect'); }
    return result;
  }
}
