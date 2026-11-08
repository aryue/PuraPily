// Direct translation of HarmoniumSliderParticle, verified firmware disassembly.
// Keep emitter-local coordinates separate from layout offset and render translation.
export interface ParticlePoint { x: number; y: number; }

export class ParticleGeometry {
  static emitter(u: number, w: number, h: number, reverse: boolean,
    horizontal: boolean = true, expanded: boolean = false): ParticlePoint {
    if (expanded) { return { x: u + (reverse ? -138 : 138), y: -h / 2 }; }
    if (horizontal) { return { x: u - (reverse ? 96 : -96 * 2 / 3), y: -h / 2 }; }
    return { x: -w / 2, y: h - u - (reverse ? 96 : -96 / 2) };
  }

  static velocityPosition(w: number, h: number, horizontal: boolean = true): ParticlePoint {
    return horizontal ? { x: 1.5 * w, y: 0 } : { x: 0, y: 1.5 * h };
  }

  static offset(u: number, w: number, h: number, horizontal: boolean = true): ParticlePoint {
    return horizontal ? { x: w + u + 5, y: 0 } : { x: 0, y: 2 * h - u };
  }

  static velocity(v: number): number { return Math.abs(v) <= 10 ? 0 : Math.sign(v) * 150; }
}
