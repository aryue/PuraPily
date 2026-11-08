export class JellyMesh {
  // Exact barrel expression recovered from libgraphics_effect.z.so at 0x53ee5.
  // It maps destination UV to source UV, after InvBilinear in the shader.
  static barrel(frame: number[], u: number, v: number): number[] {
    const dx: number = frame[8] + (frame[9] - frame[8]) * u;
    const dy: number = frame[10] + (frame[11] - frame[10]) * v;
    const x: number = u - 0.5;
    const y: number = v - 0.5;
    const radius2: number = x * x + y * y;
    return [0.5 + x * (1 + dx * radius2) / (1 + dx * 0.5),
      0.5 + y * (1 + dy * radius2) / (1 + dy * 0.5)];
  }

  static point(frame: number[], u: number, v: number): number[] {
    // drawPixelMapMesh needs the opposite mapping: source UV -> destination.
    // Solve barrel(q)=source, then apply the forward bilinear quadrilateral.
    let qx: number = u;
    let qy: number = v;
    for (let i: number = 0; i < 12; i++) {
      const sample: number[] = JellyMesh.barrel(frame, qx, qy);
      const ex: number = sample[0] - u;
      const ey: number = sample[1] - v;
      if (Math.max(Math.abs(ex), Math.abs(ey)) < 1e-10) { break; }
      const step: number = 1e-5;
      const sx: number[] = JellyMesh.barrel(frame, qx + step, qy);
      const sy: number[] = JellyMesh.barrel(frame, qx, qy + step);
      const a: number = (sx[0] - sample[0]) / step;
      const b: number = (sy[0] - sample[0]) / step;
      const c: number = (sx[1] - sample[1]) / step;
      const d: number = (sy[1] - sample[1]) / step;
      const determinant: number = a * d - b * c;
      if (Math.abs(determinant) < 1e-10) { break; }
      qx -= (d * ex - b * ey) / determinant;
      qy -= (a * ey - c * ex) / determinant;
    }
    return [frame[0] * (1 - qx) * (1 - qy) + frame[2] * qx * (1 - qy) +
      frame[4] * qx * qy + frame[6] * (1 - qx) * qy,
    frame[1] * (1 - qx) * (1 - qy) + frame[3] * qx * (1 - qy) +
      frame[5] * qx * qy + frame[7] * (1 - qx) * qy];
  }
  static vertices(frame: number[], width: number, height: number, padding: number,
    columns: number = 16, rows: number = 32): number[] {
    const vertices: number[] = [];
    for (let row: number = 0; row <= rows; row++) {
      const v: number = row / rows;
      for (let column: number = 0; column <= columns; column++) {
        const u: number = column / columns;
        // Mesh triangles still approximate the continuous recovered shader.
        const point: number[] = JellyMesh.point(frame, u, v);
        vertices.push(padding + point[0] * width, padding + point[1] * height);
      }
    }
    return vertices;
  }
}
