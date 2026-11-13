const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const source = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const cls = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
const names = ['onTD', 'onTM', 'onTU', 'onTC', 'levelGestureCenterX',
  'scheduleHoldSpeed', 'referenceHandleFeedPlayerTouch', 'referenceCancelFeedPlayerTouch',
  'referenceFeedPlayerTouchAvailable'];
const methods = cls.members.filter(n => names.includes(n.name?.getText(source))).map(n => n.getText(source));
assert.equal(methods.length, names.length);
let timerId = 0;
const timers = new Map();
const ctx = { setTimeout: fn => { timers.set(++timerId, fn); return timerId; }, clearTimeout: id => timers.delete(id),
  AppStorage: { setOrCreate() {} }, TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 } };
vm.runInNewContext(ts.transpileModule('class Page {' + methods.join('\n') + '} globalThis.Page = Page;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const touch = (dx = 0, dy = 0, id = 7) => ({ touches: [{ id, windowX: 200 + dx, windowY: 300 - dy }] });
function page(start = true) {
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
  if (start) p.onTD(touch());
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
// 横屏分栏：分界线是播放视口中线，不是屏幕中线（播放区在左 0..300 时中线 = 150）
function splitPage(playerX, viewW) {
  const p = page();
  Object.assign(p, { cw: 400, isLs: true, referenceLayout: true, fs: false, isLandscapeVertical: false,
    referenceLandscapePlayerX: () => playerX, referenceLandscapeViewportWidth: () => viewW });
  return p;
}
const splitLeft = splitPage(0, 300);
splitLeft.onTM(touch(-20, 30)); // windowX 180：屏幕中线左侧，但在播放区右半
assert.equal(splitLeft.gm_, 'volume', 'split boundary follows playback viewport center');
const splitLeftBright = splitPage(0, 300);
splitLeftBright.onTM(touch(-90, 120)); // windowX 110
assert.equal(splitLeftBright.gm_, 'brightness');
const splitRight = splitPage(100, 300); // 播放区换到右侧：中线 250
splitRight.onTM(touch(20, 30)); // windowX 220：屏幕中线右侧，但仍在播放区左半
assert.equal(splitRight.gm_, 'brightness', 'split boundary must not fall back to the screen center');
const splitFull = splitPage(0, 300);
splitFull.fs = true;
splitFull.onTM(touch(20, 30)); // 全屏播放区占满窗口：中线回到 200
assert.equal(splitFull.gm_, 'volume', 'fullscreen keeps the screen center');
const unknown = page(); unknown.dur = 0; unknown.onTM(touch(100));
assert.equal(unknown.gm_, ''); assert.equal(unknown.haptics, 0);
const longPress = page(); timers.get(longPress.lt_)(); longPress.onTM(touch(100)); longPress.onTU(touch());
assert.equal(longPress.seeks.length, 0); assert.deepEqual(longPress.rates, [2, 1]);
const doubleTap = page(); doubleTap.dt_ = 999; doubleTap.onTD(touch()); doubleTap.onTM(touch(100)); doubleTap.onTU(touch());
assert.equal(doubleTap.seeks.length, 0);

function feedPage(overrides = {}) {
  const p = page(false);
  Object.assign(p, {
    referencePortraitFeedActive: () => true, referenceSafeTop: () => 40,
    feedChromeTop: () => 550, referenceFullscreenButtonTop: () => 400,
    referenceCancelFeedTap() {}, ...overrides
  });
  return p;
}
function feedTouch(p, phase, dx = 0, dy = 0, id = 7) {
  const { touches } = touch(dx, dy, id);
  p.referenceHandleFeedPlayerTouch({
    type: ctx.TouchType[phase], touches: phase === 'Up' ? [] : touches, changedTouches: touches
  });
}
for (const direction of [-1, 1]) {
  const p = feedPage({ referenceInfoHidden: direction < 0 });
  feedTouch(p, 'Down');
  feedTouch(p, 'Move', direction * 24);
  assert.equal(p.ct, 120);
  feedTouch(p, 'Move', direction * 64, 50);
  assert.equal(p.ct, 120 + direction * 30, 'recognized horizontal drag stays locked');
  assert.equal(p.referenceFeedPanOwnsTouch, true, 'drag suppresses information-layer tap');
  assert.deepEqual(p.seeks, []);
  feedTouch(p, 'Up');
  assert.deepEqual(p.seeks, [120 + direction * 30]);
}
for (const [dx, dy] of [[4, 3], [23, 0], [30, 24], [0, 32], [24, 0]]) {
  const p = feedPage();
  feedTouch(p, 'Down');
  feedTouch(p, 'Move', dx, dy);
  if (dx === 0) feedTouch(p, 'Move', 100, dy);
  feedTouch(p, 'Up');
  assert.equal(p.ct, 120);
  assert.deepEqual(p.seeks, [], `unintentional motion ${dx},${dy}`);
  assert.equal(p.hints.some(hint => hint[2] !== 'seek'), false);
}
for (const startY of [60, 410, 560]) {
  const p = feedPage({ ar: 16 / 9 });
  feedTouch(p, 'Down', 0, 300 - startY);
  feedTouch(p, 'Move', 100, 300 - startY);
  feedTouch(p, 'Up');
  assert.deepEqual(p.seeks, [], 'visible chrome is excluded');
  assert.equal(p.haptics, 0);
}
for (const overrides of [{ referenceFeedComments: true }, { lk: true }, { seekBarTouch_: true },
  { sliderDragging_: true }, { referenceFeedLoading: true }, { waitingForFirstFrame: true }, { dur: 0 }]) {
  const p = feedPage(overrides);
  feedTouch(p, 'Down');
  feedTouch(p, 'Move', 100);
  feedTouch(p, 'Up');
  assert.deepEqual(p.seeks, []);
  assert.equal(p.haptics, 0);
}
for (const cancel of [p => feedTouch(p, 'Cancel'), p => feedTouch(p, 'Up', 64, 0, 8),
  p => p.referenceHandleFeedPlayerTouch({ type: ctx.TouchType.Move, touches: [...touch(64).touches, ...touch(0, 0, 8).touches] }),
  p => { p.referenceFeedLoading = true; }, p => p.referenceCancelFeedPlayerTouch()]) {
  const p = feedPage();
  feedTouch(p, 'Down');
  feedTouch(p, 'Move', 64);
  assert.equal(p.ct, 150);
  cancel(p);
  feedTouch(p, 'Up');
  assert.equal(p.ct, 120);
  assert.equal(p.sk_, false);
  assert.deepEqual(p.seeks, []);
}
for (const finish of ['Up', 'Cancel', 'MultiTouch', 'Switch']) {
  const p = feedPage({ rt: 1.5 });
  feedTouch(p, 'Down');
  const timer = p.lt_;
  timers.get(timer)();
  assert.equal(p.gh, true);
  assert.equal(p.referenceFeedPanOwnsTouch, true);
  assert.deepEqual(p.rates, [2]);
  feedTouch(p, 'Move', 70);
  if (finish === 'Switch') p.referenceCancelFeedPlayerTouch();
  else if (finish === 'MultiTouch') {
    p.referenceHandleFeedPlayerTouch({ type: ctx.TouchType.Down, touches: [...touch().touches, ...touch(0, 0, 8).touches] });
  } else feedTouch(p, finish);
  assert.deepEqual(p.rates, [2, 1.5]);
  assert.equal(p.gh, false);
  assert.deepEqual(p.seeks, []);
}
for (const [phase, dx, dy] of [['Up', 0, 0], ['Move', 16, 0], ['Move', 0, 16], ['Cancel', 0, 0]]) {
  const p = feedPage();
  feedTouch(p, 'Down');
  const timer = p.lt_;
  assert.ok(timers.has(timer));
  feedTouch(p, phase, dx, dy);
  assert.equal(timers.has(timer), false);
  assert.deepEqual(p.rates, []);
}
const pausedFeed = feedPage({ av: { state: 'paused' } });
feedTouch(pausedFeed, 'Down');
assert.equal(pausedFeed.lt_, -1);
console.log('PASS: compiled player gestures — regular and feed seek, accidental motion, control exclusion, cancellation, volume/brightness, hold speed and double tap.');
