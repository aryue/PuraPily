export interface ExperimentalLevelBarParticle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  age: number;
  life: number;
  phase: number;
  side: number;
  speed: number;
  opacity: number;
  absorbAge: number;
  origin: string;
}

/** 两端保持原有涌现，上下两部分中段持续补充，向液面逐渐汇密。 */
export class ExperimentalLevelBarParticleField {
  value: number = 0.5;
  wave: number = 0;
  energy: number = 0;
  illumination: number = 0;
  particles: ExperimentalLevelBarParticle[] = [];
  private seed: number = 7429;
  private endCredit: number = 0;
  private interiorCredit: number = 0;
  private speed: number = 0;
  private waveVelocity: number = 0;
  private pressed: boolean = false;
  private readonly flowSpeedScale: number = 2;
  width: number;
  height: number;

  constructor(width: number, height: number, value: number, seed: number = 7429) {
    this.width = width; this.height = height; this.seed = seed >>> 0;
    this.value = Math.max(0, Math.min(1, value));
  }

  private random(): number {
    this.seed = (this.seed * 1664525 + 1013904223) >>> 0;
    return this.seed / 4294967296;
  }

  begin(): void {
    this.pressed = true;
    this.energy = 0.55;
    this.endCredit = 0; this.interiorCredit = 0;
    this.emitEnds(6);
    this.emitInterior(5);
  }

  setValue(value: number, seconds: number): void {
    const next: number = Math.max(0, Math.min(1, value));
    const oldSurface: number = (1 - this.value) * this.height;
    const surface: number = (1 - next) * this.height;
    const displacement: number = surface - oldSurface;
    const velocity: number = displacement / Math.max(0.008, seconds);
    this.speed = this.speed * 0.35 + Math.max(-600, Math.min(600, velocity)) * 0.65;
    this.waveVelocity += Math.max(-8, Math.min(8, (next - this.value) * 32));
    this.energy = Math.min(1, Math.max(this.energy, Math.abs(this.speed) / 200));
    this.value = next;
    for (const p of this.particles) {
      if (p.absorbAge >= 0) continue;
      const distance: number = Math.abs(p.y - oldSurface);
      // 移动的液面对两侧粒子产生同方向拖曳：前侧被推、后侧被拉；不把整个场硬绑到手指。
      p.y += displacement * (0.12 + 0.30 * Math.exp(-distance / 60));
      p.vy += Math.max(-35, Math.min(35, velocity * 0.06));
      if ((p.y - surface) * p.side <= 2) this.absorb(p, surface);
    }
  }

  end(): void { this.pressed = false; }

  private addParticle(side: number, y: number, origin: string): void {
    if (this.particles.length >= 160) return;
    // 端部的出生位置落在胶囊真实圆帽内，不从裁剪区突然跳入。
    const radius: number = this.width / 2;
    const capDepth: number = Math.min(y, this.height - y);
    const halfWidth: number = capDepth < radius ?
      Math.sqrt(Math.max(0, radius * radius - (radius - capDepth) * (radius - capDepth))) : radius;
    const speed: number = 13 + this.random() * 14;
    this.particles.push({
      x: radius + (this.random() * 2 - 1) * Math.max(0, halfWidth - 3), y: y,
      vx: (this.random() - 0.5) * 3, vy: -side * speed * this.flowSpeedScale,
      radius: 0.28 + Math.pow(this.random(), 2) * 0.95,
      age: 0, life: 10, phase: this.random() * Math.PI * 2,
      side: side, speed: speed, opacity: 0, absorbAge: -1, origin: origin
    });
  }

  private emitEnds(count: number): void {
    const surface: number = (1 - this.value) * this.height;
    for (let i: number = 0; i < count; i++) {
      for (const side of [-1, 1]) {
        const space: number = side < 0 ? surface : this.height - surface;
        if (space < 9) continue;
        const depth: number = 3 + this.random() * Math.min(12, space * 0.2);
        this.addParticle(side, side < 0 ? depth : this.height - depth, 'end');
      }
    }
  }

  private emitInterior(count: number): void {
    const surface: number = (1 - this.value) * this.height;
    for (let i: number = 0; i < count; i++) {
      // 两侧分别产生，避免随机挑边导致某一侧长时间缺少中段涌现。
      for (const side of [-1, 1]) {
        const space: number = side < 0 ? surface : this.height - surface;
        if (space < 14) continue;
        const distance: number = space * (0.32 + this.random() * 0.32);
        this.addParticle(side, surface + side * distance, 'interior');
      }
    }
  }

  private absorb(p: ExperimentalLevelBarParticle, surface: number): void {
    p.absorbAge = 0;
    p.y = surface + p.side * 2;
  }

  step(seconds: number): void {
    const dt: number = Math.max(0, Math.min(0.034, seconds));
    const target: number = this.pressed ? 1 : 0;
    this.illumination += (target - this.illumination) * (1 - Math.exp(-dt * (this.pressed ? 24 : 11)));
    if (!this.pressed && this.illumination < 0.002) this.illumination = 0;
    this.energy *= Math.exp(-dt * (this.pressed ? 1.4 : 4));
    this.speed *= Math.exp(-dt * 5);
    this.waveVelocity += (-this.wave * 100 - this.waveVelocity * 13) * dt;
    this.wave += this.waveVelocity * dt;
    if (!this.pressed && this.illumination === 0) {
      this.particles = [];
      return;
    }
    if (this.pressed) {
      this.endCredit += dt * (16 + this.energy * 10);
      const pairs: number = Math.floor(this.endCredit);
      this.endCredit -= pairs;
      this.emitEnds(pairs);
      this.interiorCredit += dt * (18 + this.energy * 8 + Math.abs(this.speed) * 0.025);
      const interior: number = Math.floor(this.interiorCredit);
      this.interiorCredit -= interior;
      this.emitInterior(interior);
    }
    const surface: number = (1 - this.value) * this.height;
    for (let i: number = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.age += dt;
      if (p.absorbAge >= 0) {
        p.absorbAge += dt;
        p.opacity *= Math.exp(-dt * 28);
        p.y = surface + p.side * Math.max(0, 2 - p.absorbAge * 14);
        if (p.absorbAge >= 0.14) this.particles.splice(i, 1);
        continue;
      }
      const distance: number = (p.y - surface) * p.side;
      if (distance <= 2) { this.absorb(p, surface); continue; }
      const inward: number = -p.side * (p.speed + Math.sqrt(distance) * 2.8) * this.flowSpeedScale;
      const drag: number = this.speed * (0.14 + 0.18 * Math.exp(-distance / 60));
      p.vy += (inward + drag - p.vy) * (1 - Math.exp(-dt * 7));
      p.x += (p.vx + Math.sin(p.age * 2.5 + p.phase) * 1.5) * dt;
      p.x = Math.max(2, Math.min(this.width - 2, p.x));
      p.y += p.vy * dt;
      const remaining: number = (p.y - surface) * p.side;
      // 保留液面附近汇密的可见粒子，仅在最后 5vp 淡出并由边界吸收。
      p.opacity = Math.min(1, p.age / 0.22) * Math.min(1, Math.max(0, remaining) / 5);
      if (remaining <= 2) this.absorb(p, surface);
      else if (p.age >= p.life || p.y < -3 || p.y > this.height + 3) this.particles.splice(i, 1);
    }
  }
}
