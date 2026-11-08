// Exercise the actual CompileArkTS method: HDR must never receive super-white
// filter output, and the glyph's alpha (including antialiasing) must survive.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/PlaybackMenuIcon.ts';
const source = fs.readFileSync(path, 'utf8');
const method = source.match(/private iconFilter\(\): ColorFilter\s*\{([\s\S]*?)\n    \}/);
assert.ok(method, 'compiled tint method exists');
const context = { ColorFilter: class { constructor(matrix) { this.matrix = matrix; } } };
vm.runInNewContext('globalThis.tint = function() {' + method[1] + '}', context);
for (const dark of [true, false]) {
  const matrix = context.tint.call({ dark }).matrix;
  const expected = dark ? [238, 239, 241] : [24, 25, 28];
  assert.equal(matrix.length, 20);
  for (const rgb of [[0,0,0], [1,1,1], [.2,.6,.9]]) {
    for (const alpha of [0, .1, .5, 1]) {
      const input = [...rgb, alpha, 1];
      const output = Array.from({ length: 4 }, (_, row) =>
        input.reduce((sum, value, column) => sum + matrix[row*5+column]*value, 0));
      output.forEach(value => assert.ok(value >= 0 && value <= 1, 'output stays in SDR range before tone mapping'));
      expected.forEach((value, channel) => assert.ok(Math.abs(output[channel]*255-value) < 1e-10, 'matches label tint'));
      assert.equal(output[3], alpha, 'preserves transparent and antialiased pixels');
    }
  }
}
console.log('PASS: compiled playback icon tint stays within SDR range in both themes and preserves alpha');
