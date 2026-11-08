const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

// Exercise CompileArkTS output, including the actual conditional native-node creation.
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/VideoControls.ts', 'utf8');
const methods = source.slice(source.indexOf('    private hasSeekDuration('), source.indexOf('    ReferenceReplayButton('));
const rendered = [], events = {}, interactions = [];
const node = new Proxy({}, { get: () => () => {} });
const slider = new Proxy({}, { get: (_, name) => name === 'create' ? options => rendered.push(options)
  : name === 'onChange' || name === 'onTouch' ? callback => { events[name] = callback; } : () => {} });
const context = { exports: {}, Stack: node, If: node, Row: node, Slider: slider,
  Alignment: { Start: 0 }, SliderStyle: { OutSet: 0 }, HitTestMode: { None: 0 },
  SliderChangeMode: { Begin: 0, Moving: 1, End: 2 }, TouchType: { Cancel: 3 }, bufferedTrack: () => ({}) };
vm.runInNewContext(ts.transpileModule(`class Controls { ${methods} } exports.Controls = Controls;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const controls = new context.exports.Controls();
Object.assign(controls, { currentTime: 26.043, duration: 0, bufferedUntil: 0,
  observeComponentCreation2(callback) { callback(1, true); },
  ifElseBranchUpdateFunction(_branch, callback) { callback(); },
  onSeekBarInteract(active, value) { interactions.push([active, value]); } });
function render() {
  rendered.length = 0;
  controls.ReferenceSeekBar(44, 9, '#D34E7E');
  return rendered[0];
}
for (const duration of [0, -1, NaN, Infinity]) {
  controls.duration = duration;
  assert.equal(render(), undefined, 'an early resume position must not create a full temporary slider');
  assert.equal(controls.seekDisplayTime(), 0);
}
controls.duration = 75.007;
assert.equal(render().value, 26.043);
assert.equal(render().max, 75.007, 'first native slider must have the real range');
assert.ok(render().value / render().max < 0.35);
events.onChange(12, 0);
assert.deepEqual(interactions.at(-1), [true, 12]);
assert.equal(controls.currentTime, 12);
events.onChange(15, 2);
assert.deepEqual(interactions.at(-1), [false, 15]);
events.onTouch({ type: 3 });
assert.deepEqual(interactions.at(-1), [false, 15]);
for (const [time, expected] of [[0, 0], [-1, 0], [NaN, 0], [Infinity, 0], [100, 75.007], [75.007, 75.007]]) {
  controls.currentTime = time;
  assert.equal(render().value, expected);
}
// A replacement source can deliver its new position before its duration too.
controls.duration = 0;
controls.currentTime = 150;
assert.equal(render(), undefined);
controls.duration = 600;
assert.equal(render().value / render().max, 0.25);
console.log('PASS: compiled resume rendering, unknown duration, valid range, replay/completion, source replacement, drag/end/cancel');
