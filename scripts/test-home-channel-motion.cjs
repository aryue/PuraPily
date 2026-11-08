const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/HomeChannelMotion.ts';
const context = { exports: {}, require: () => ({ default: { customCurve: fn => fn } }) };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { homeChannelProgress: p, HOME_CHANNEL_DURATION: duration, HOME_CHANNEL_CURVE: curve } = context.exports;
assert.equal(duration, 380);
assert.equal(curve, p, 'native curve must use the verified interpolation');
assert.equal(p(-1), 0);
assert.equal(p(0), 0);
assert.equal(p(1), 1);
assert.equal(p(2), 1);
for (const [ms, position] of [[66,.25],[116,.5],[167,.75],[249,.9],[315,.97]]) {
  assert.ok(Math.abs(p(ms / duration) - position) < 1e-10, `reference landmark ${ms}ms`);
  const t = ms / duration, h = 1e-6;
  const incoming = (p(t) - p(t - h)) / h;
  const outgoing = (p(t + h) - p(t)) / h;
  assert.ok(Math.abs(incoming - outgoing) < .001, `velocity continuity at ${ms}ms`);
}
let previous = 0;
for (let i = 0; i <= 10000; i++) {
  const value = p(i / 10000);
  assert.ok(Number.isFinite(value) && value >= 0 && value <= 1, 'no out-of-bounds page travel');
  assert.ok(value >= previous, 'no reversal during completion');
  previous = value;
}
const h = 1e-6;
assert.ok(p(h) / h < .001, 'smooth launch');
assert.ok((1 - p(1 - h)) / h < .001, 'zero terminal velocity');
console.log('PASS compiled homepage curve: reference landmarks, continuous velocity, monotonic travel, no overshoot, smooth endpoints.');
