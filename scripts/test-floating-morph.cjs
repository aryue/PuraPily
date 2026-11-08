const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(compiled + 'pages/VideoPlayerPage.ts', 'utf8');
function method(name) {
  const match = new RegExp('(?:private )?' + name + '\\(').exec(source);
  const start = match ? match.index : -1;
  assert(start >= 0, name + ' survives CompileArkTS');
  const open = source.indexOf('{', start);
  let depth = 1, end = open + 1;
  while (depth && end < source.length) {
    const c = source[end++];
    if (c === '{') depth++;
    if (c === '}') depth--;
  }
  return source.slice(start, end);
}
const service = fs.readFileSync(compiled + 'services/FloatingVideoTransition.ts', 'utf8').replace(/^import .*;\s*$/gm, '');
const storage = new Map();
const context = { exports: {}, AppStorage: { get: k => storage.get(k), setOrCreate: (k,v) => storage.set(k,v) } };
vm.runInNewContext(ts.transpileModule(service, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
context.FloatingVideoTransition = context.exports.FloatingVideoTransition;
vm.runInNewContext(ts.transpileModule('exports.Page = class Page {' +
  ['floatingRect', 'prepareFloatingGeometry'].map(method).join('\n') + '};', {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
const T = context.FloatingVideoTransition;
const p = new context.exports.Page();
Object.assign(p, { floatingMorph: false, ar: 9/16, cw: 440, ch: 744, navIndicatorHeight: 28,
  ovRectX: () => 0, ovRectY: () => 39, ovRectW: () => 440, ovRectH: () => 387,
  ovVideoW: () => 217.6875, ovVideoH: () => 387 });
p.prepareFloatingGeometry();
const from = p.floatingSource, to = p.floatingTarget;
for (const t of [0, .1, .3, .5, .7, .9, 1]) {
  p.floatingCompact = t;
  const r = p.floatingRect();
  assert.equal(r.width, from.width + (to.width-from.width)*t);
  assert.equal(r.x, from.x + (to.x-from.x)*t);
  assert(Math.abs(r.width/r.height-9/16)<1e-9, 'video preserves aspect throughout transition');
}
const moved = { x: 42, y: 140, width: 144, height: 256 };
T.remember(moved);p.floatingMorph = true;p.prepareFloatingGeometry();
assert.equal(p.floatingMorph, true, 'sampling layout retains transition state');
p.floatingCompact = 1;
assert.deepEqual(JSON.parse(JSON.stringify(p.floatingRect())), moved, 'restore begins at dragged and resized bounds');
p.floatingCompact = 0;
assert.deepEqual(JSON.parse(JSON.stringify(p.floatingRect())), JSON.parse(JSON.stringify(from)));
p.ar = 16/9;p.prepareFloatingGeometry();
assert(Math.abs(p.floatingTarget.width/p.floatingTarget.height-16/9)<1e-9, 'a different video updates the target ratio');
assert(p.floatingTarget.x>=8 && p.floatingTarget.y>=48, 'target stays inside safe bounds');
T.begin('minimize');assert.equal(storage.get('floatingMorphBusy'),true);
T.finish();assert.equal(storage.get('floatingMorphBusy'),false);assert.equal(T.active(),false);
console.log('PASS compiled floating geometry: portrait ratio, intermediate bounds, dragged/resized origin, handoff guard');

// Local overlay motion was retired; the system now owns PiP window geometry.
let released = 0;
T.pausedFrame = { release: () => { released++; return Promise.resolve(); } };
T.clearPausedFrame();T.clearPausedFrame();
assert.equal(released,1);assert.equal(T.pausedFrame,undefined);
console.log('PASS paused snapshot cleanup is idempotent');
