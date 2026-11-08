const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/ExperimentalLevelBarParticleField.ts';
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const Field = context.exports.ExperimentalLevelBarParticleField;
const step = (field, frames) => { for (let i = 0; i < frames; i++) field.step(1 / 60); };
const field = new Field(72, 162, .5);
assert.equal(field.particles.length, 0, 'inactive has no persistent ambient dots');
field.begin();
const ends = field.particles.filter(p => p.origin === 'end');
assert.equal(ends.length, 12);
assert.ok(ends.every(p => p.side < 0 ? p.y < 16 && p.vy > 0 : p.y > 146 && p.vy < 0), 'both caps emit toward surface');
for (const side of [-1, 1]) {
  const middle = field.particles.filter(p => p.origin === 'interior' && p.side === side);
  assert.ok(middle.length > 0, 'each side has its own middle emergence');
  assert.ok(middle.every(p => Math.abs(p.y - 81) >= 81 * .32 && Math.abs(p.y - 81) <= 81 * .64));
}
const startDistances = ends.map(p => Math.abs(p.y - 81));
step(field, 40);
assert.ok(ends.every((p, i) => Math.abs(p.y - 81) < startDistances[i] - 10), 'both sides actually travel inward');
step(field, 260);
assert.ok(ends.every(p => !field.particles.includes(p) && p.age < p.life), 'cohort is absorbed before lifetime, not recycled across surface');
assert.ok(field.particles.every(p => p.absorbAge >= 0 || (p.y - 81) * p.side > 0), 'no particle crosses and flies out the other side');
assert.ok(field.particles.some(p => p.origin === 'interior'), 'interior particles also appear');
// Measure visible density over sustained holds, in equal-sized thirds of each
// section. This checks the requested gradient rather than merely total count.
for (const [width, height] of [[52,116], [72,162]]) for (const value of [.2,.5,.8]) {
  const held = new Field(width, height, value);
  held.begin(); step(held, 120);
  const density = { '-1': [0,0,0], '1': [0,0,0] };
  for (let frame = 0; frame < 600; frame++) {
    held.step(1 / 60);
    const surface = (1 - value) * height;
    for (const particle of held.particles) {
      if (particle.absorbAge >= 0) continue;
      const span = particle.side < 0 ? surface : height - surface;
      const fraction = Math.abs(particle.y - surface) / span;
      const band = Math.min(2, Math.floor(fraction * 3));
      density[particle.side][band] += particle.opacity;
      assert.ok(particle.vy * particle.side < 0, 'all active particles still flow into liquid surface');
    }
  }
  for (const side of [-1,1]) {
    const [near, middle, cap] = density[side];
    assert.ok(near > middle && middle > cap, `visible density must rise toward surface (${width}x${height}, ${value}, ${side}): ${near},${middle},${cap}`);
  }
}
for (const delta of [-.08, .08]) {
  const moved = new Field(72, 162, .5);
  moved.begin(); step(moved, 20);
  const before = moved.particles.map(p => ({ y: p.y, side: p.side }));
  moved.setValue(.5 + delta, 1 / 60);
  for (const side of [-1, 1]) {
    const tracked = moved.particles.map((p, i) => ({ p, old: before[i] })).filter(x => x.p.side === side && x.p.absorbAge < 0);
    assert.ok(tracked.length > 0);
    assert.ok(tracked.every(x => (x.p.y - x.old.y) * delta < 0), 'moving surface pushes front and pulls back in the same drag direction');
  }
}
for (let i = 0; i < 1200; i++) {
  field.setValue((Math.sin(i / 31) + 1) / 2, 1 / 60);
  field.step(1 / 60);
  assert.ok(field.particles.length <= 160);
  assert.ok(field.particles.every(p => Number.isFinite(p.x + p.y + p.vy + p.opacity)));
}
field.end(); step(field, 60);
assert.equal(field.illumination, 0);
assert.equal(field.particles.length, 0, 'release drains particles and leaves no idle animation');
console.log('PASS: CompileArkTS output — end inflow, boundary absorption, interior birth, bidirectional advection, bounds, release.');
