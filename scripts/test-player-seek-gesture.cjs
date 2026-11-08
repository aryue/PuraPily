const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const source = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const cls = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
const names = ['onTD', 'onTM', 'onTU', 'onTC'];
const methods = cls.members.filter(n => names.includes(n.name?.getText(source))).map(n => n.getText(source));
assert.equal(methods.length, names.length);
let timerId = 0;
const timers = new Map();
const ctx = { setTimeout: fn => { timers.set(++timerId, fn); return timerId; }, clearTimeout: id => timers.delete(id),
  AppStorage: { setOrCreate() {} } };
vm.runInNewContext(ts.transpileModule('class Page {' + methods.join('\n') + '} globalThis.Page = Page;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const touch = (dx = 0, dy = 0, id = 7) => ({ touches: [{ id, windowX: 200 + dx, windowY: 300 - dy }] });
function page() {
  const p = new ctx.Page();
  Object.assign(p, { playerTouchId_: -1, dt_: -1, lt_: -1, gt_: -1, ct_: -1,
    ct: 120, dur: 600, cw: 400, screenH_: 800, vol: .5, bri: .5, rt: 1,
    cv: true, sk_: false, gm_: '', av: { state: 'playing', setVolume() {} },
    seeks: [], haptics: 0, hints: [], rates: [],
    triggerHaptic() { this.haptics++; }, fireHaptic() {},
    sGH(...args) { this.hints.push(args); }, formatDuration: String,
    updateSeekThumb_() {}, sampleLevelInput() {}, setSystemVolume() {},
    finishLevelGesture_() {}, cancelDelayHide() {}, clearGestureHint_() { this.hints = []; },
    seek(value) { this.seeks.push(value); }, togglePP() {},
    setRate(value) { this.rates.push(value); }
  });
  p.onTD(touch());
  return p;
}
for (const [dx, dy] of [[11, 0], [-23, 0], [20, 20], [30, 24], [-30, -24]]) {
  const p = page(); p.onTM(touch(dx, dy)); p.onTU(touch(dx, dy));
  assert.equal(p.seeks.length, 0, `accidental motion ${dx},${dy}`);
  assert.equal(p.haptics, 0);
}
for (const direction of [-1, 1]) {
  const p = page();
  p.onTM(touch(direction * 24));
  assert.equal(p.ct, 120, 'recognition threshold must not jump progress');
  p.onTM(touch(direction * 64, 4));
  assert.equal(p.ct, 120 + direction * 30);
  assert.equal(p.seeks.length, 0, 'drag previews until release');
  p.onTM(touch(direction * 44));
  assert.equal(p.ct, 120 + direction * 15, 'reverse motion stays continuous');
  p.onTU(touch()); assert.deepEqual(p.seeks, [p.ct]);
}
for (const cancel of [p => p.onTC(), p => p.onTM({ touches: [...touch(64).touches, ...touch(0, 0, 8).touches] }),
  p => p.onTM(touch(64, 0, 9))]) {
  const p = page(); p.onTM(touch(64)); cancel(p); p.onTU(touch());
  assert.equal(p.ct, 120); assert.equal(p.sk_, false); assert.equal(p.seeks.length, 0);
  p.onTM(touch(100)); assert.equal(p.seeks.length, 0); assert.equal(p.gm_, '');
}
for (const [dx, expected] of [[-10, 'brightness'], [10, 'volume']]) {
  const p = page(); p.onTM(touch(dx, 30)); assert.equal(p.gm_, expected);
  p.onTM(touch(100, 40)); assert.equal(p.gm_, expected, 'vertical direction remains locked');
  p.onTU(touch()); assert.equal(p.seeks.length, 0);
}
const unknown = page(); unknown.dur = 0; unknown.onTM(touch(100));
assert.equal(unknown.gm_, ''); assert.equal(unknown.haptics, 0);
const longPress = page(); timers.get(longPress.lt_)(); longPress.onTM(touch(100)); longPress.onTU(touch());
assert.equal(longPress.seeks.length, 0); assert.deepEqual(longPress.rates, [2, 1]);
const doubleTap = page(); doubleTap.dt_ = 999; doubleTap.onTD(touch()); doubleTap.onTM(touch(100)); doubleTap.onTU(touch());
assert.equal(doubleTap.seeks.length, 0);
console.log('PASS: compiled player gestures — jitter, diagonal intent, both seek directions, reversal, cancellation, pointer changes, volume/brightness, long press and double tap.');
