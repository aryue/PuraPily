const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function load(file, requireFn, extra = {}) {
  const context = { exports: {}, require: requireFn, ...extra };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root + file + '.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
require('./test-controlcenter-player.cjs');
require('./test-controlcenter-press.cjs');

// Exercise the compiled page methods with a deterministic timer queue.
for (const [file, className, finish, active, visible] of [
  ['pages/VideoPlayerPage', 'VideoPlayerPage', 'finishLevelGesture_', 'ghActive', 'gh'],
  ['pages/LivePlayerPage', 'LivePlayerPage', 'finishLevelGesture', 'gestureHintActive', 'showGestureHint']
]) {
  const source = ts.createSourceFile(file + '.ts', fs.readFileSync(root + file + '.ts', 'utf8'), ts.ScriptTarget.Latest, true);
  const cls = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === className);
  const names = ['sGH', finish, 'sampleLevelInput'];
  const methods = cls.members.filter(n => names.includes(n.name?.getText(source))).map(n => n.getText(source));
  assert.equal(methods.length, 3);
  const timers = new Map(); let id = 0;
  const ctx = { Page: null, setTimeout: (fn) => { timers.set(++id, fn); return id; }, clearTimeout: (key) => timers.delete(key) };
  vm.runInNewContext(ts.transpileModule('class Page { ' + methods.join('\n') + ' } globalThis.Page = Page;', {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, ctx);
  const page = new ctx.Page(); page.gt_ = -1;
  const motionKey = file.includes('VideoPlayer') ? 'ghMotion' : 'gestureHintMotion';
  page[motionKey] = { sequence: 0, delta: 0, velocity: 0 };
  page.sampleLevelInput(.2);
  assert.equal(page[motionKey].delta, .2);
  page.sGH('50%', .5, 'volume');
  assert.equal(page[active], true); assert.equal(page[visible], true);
  assert.equal(timers.size, 0, 'holding without moves must not schedule hide');
  page.sampleLevelInput(.3);
  assert.ok(Math.abs(page[motionKey].delta - .1) < 1e-9);
  page.sampleLevelInput(.5);
  assert.equal(page[motionKey].sequence, 3, 'Motion continues even when displayed level is clamped');
  page[finish](); assert.equal(page[active], false); assert.equal(page[visible], true);
  assert.equal(timers.size, 1);
  page.sampleLevelInput(-.1);
  assert.equal(page[motionKey].delta, -.1, 'New gesture resets the normalized origin');
  page.sGH('60%', .6, 'brightness'); assert.equal(timers.size, 0, 'next drag cancels old release timeout');
  page[finish](); for (const fn of timers.values()) fn();
  assert.equal(page[visible], false);
}
console.log('PASS: compiled video/live page methods — hold has no timeout, release tail, interrupted tail cancellation.');

const { IconFrames } = load('controlcenter/model/IconFrames');
for (const [value, expected] of [[0, 0], [.00001, 1], [.32999, 1], [.33, 2], [.65999, 2], [.66, 3], [1, 3]]) {
  assert.equal(IconFrames.volumeLevel(value), expected);
}
assert.equal(IconFrames.sun(0, 128), 61);
assert.equal(IconFrames.sun(1, 128), 301);
console.log('PASS: compiled firmware icon frames use exact 0/33%/66% thresholds and full brightness range.');
