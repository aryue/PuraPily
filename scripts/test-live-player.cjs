const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/LivePlayerPage.ts', 'utf8');
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a);
  return source.slice(a, b);
}
const ctx = { exports: {}, clearTimeout, setTimeout, getLiveRoomInfo: async () => null, logInfo() {}, Curve: { EaseOut: 0 }, fetchLiveRoomsByArea: async () => [{ roomId: 3 }, { roomId: 2 }] };
const methods = section('  private portraitRoom()', '  private async setPortraitScale(') +
  section('  private async switchRoom(', '  private resetLive(') +
  section('  private applyStreamQuality(', '  private async startPlay(') +
  section('  private onTM(', '  private async applyRotationMode(');
vm.runInNewContext(ts.transpileModule(`export class Page { constructor() { this.startLiveChat = () => {}; this.finishLevelGesture = () => {}; this.previewRelease = Promise.resolve(); this.previewTask = Promise.resolve(); this.previewGeneration = 0; this.activeSlot = 0; this.previewRoomId = 0; this.touchActive = true; } ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
async function main() {
  const p = new ctx.exports.Page();
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800, sourceWidth: 1080, sourceHeight: 1920,
    portraitScale: 'auto', portraitScaleScope: 'standard', safeTop: 24,
    getUIContext: () => ({ animateTo: (options, action) => { action(); options.onFinish?.(); } }) });
  assert.equal(p.videoW(), 400);
  assert.equal(p.videoH(), 400 * 16 / 9);
  p.portraitScale = 'fill';
  assert.equal(p.videoW(), 450);
  assert.equal(p.videoH(), 800);
  p.sourceWidth = 600; p.sourceHeight = 800;
  assert.equal(p.videoW(), 400, 'standard scope must not crop a 3:4 stream');
  p.portraitScaleScope = 'all';
  assert.equal(p.videoW(), 600, 'all portrait scope crops other portrait ratios');
  p.portraitScaleScope = 'standard';
  p.sourceWidth = 1920; p.sourceHeight = 1080;
  assert.equal(p.videoW(), 400);
  assert.equal(p.videoH(), 225);
  const top = p.videoTop();
  p.informationVisible = false;
  assert.equal(p.videoTop(), top, 'clearing information must not move video');
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, sourceWidth: 1080, sourceHeight: 1920 });
  assert.equal(p.videoH(), 400, 'portrait crop preference only applies to portrait viewing');
  Object.assign(p, { roomIds: [1, 2], rooms: [], roomId: 1, roomPage: 1, playGeneration: 0, roomOffset: 0,
    releasePlayer() {}, initPlayback: async () => {}, showBottomHintTemporarily() {} });
  await p.switchRoom(-1); assert.equal(p.roomId, 1);
  await p.switchRoom(1); assert.equal(p.roomId, 2);
  await p.switchRoom(1); assert.equal(p.roomId, 3);
  assert.deepEqual(Array.from(p.roomIds), [1, 2, 3]);
  assert.equal(p.roomPage, 2);
  await p.switchRoom(-1); assert.equal(p.roomId, 2);
  let finish;
  const viewport = new ctx.exports.Page();
  Object.assign(viewport, { viewportHeight: 800, roomOffset: -120, roomIds: [1, 2], rooms: [], roomId: 1,
    playGeneration: 0, releasePlayer() {}, initPlayback: async () => {},
    getUIContext: () => ({ animateTo: (options, action) => { action(); finish = options.onFinish; } }) });
  const switching = viewport.switchRoom(1);
  assert.equal(viewport.roomId, 1, 'keep outgoing room until its slide completes');
  assert.equal(viewport.roomOffset, -800);
  assert.equal(viewport.roomAnimating, true);
  finish(); await switching;
  assert.equal(viewport.roomId, 2);
  assert.equal(viewport.roomOffset, 0);
  Object.assign(p, { availableQualities: [{ qn: 30000, label: '杜比' }, { qn: 250, label: '超清' }] });
  ctx.getLiveQualityLabel = qn => `画质${qn}`;
  p.applyStreamQuality({ currentQn: 250, acceptQuality: [250, 80, 250] });
  assert.equal(p.currentQn, 250, 'show actual returned quality after server downgrade');
  assert.deepEqual(Array.from(p.availableQualities, q => q.qn), [250, 80]);
  assert.equal(p.availableQualities[0].label, '超清');
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800, sx_: 200, sy_: 400,
    gm_: '', lt_: -1, la_: false, dtp_: false, informationVisible: true,
    informationProgress: 0, informationDragStart: 0 });
  p.onTM({ touches: [{ windowX: 300, windowY: 405 }] });
  assert.equal(p.gm_, 'horizontal');
  assert.equal(p.informationProgress, 0, 'horizontal drag must not move or hide information');
  p.touchActive = true; p.onTU({});
  assert.equal(p.informationVisible, true);
  p.gm_ = ''; p.ml_ = false; p.touchActive = true; p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, false, 'single tap hides the entire information layer');
  assert.equal(p.informationProgress, 1);
  p.gm_ = ''; p.ml_ = false; p.touchActive = true; p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, true, 'single tap restores information');
  assert.equal(p.informationProgress, 0);
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 280 }] });
  assert.equal(p.gm_, 'room');
  assert.equal(p.roomOffset, -120, 'room viewport follows the vertical drag');
  let direction;
  p.switchRoom = d => { direction = d; };
  p.touchActive = true; p.onTU({}); assert.equal(direction, 1);
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 435 }] });
  direction = undefined; p.touchActive = true; p.onTU({});
  assert.equal(direction, undefined, 'short motion must not change room');
  assert.equal(p.roomOffset, 0, 'short motion must spring back');
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 280 }] });
  assert.equal(p.roomOffset, -120);
  p.onTC();
  assert.equal(p.roomOffset, 0, 'cancelled room swipe must spring back');
  console.log('Live player geometry, directional gestures, boundaries and list pagination passed');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
// Exercise subscription order on the actual compiled mask predicate: the initial
// render has no player, but must still read the observed first-frame property.
const maskStart = source.indexOf('    private slotHasCurrentFrame(');
const maskEnd = source.indexOf('    private LiveVideoSlot(', maskStart);
assert.ok(maskStart >= 0 && maskEnd > maskStart);
const maskCtx = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Mask { ${source.slice(maskStart, maskEnd)} }`, {}).outputText, maskCtx);
const mask = new maskCtx.exports.Mask();
let readyReads = 0, ready = false;
Object.assign(mask, { activeSlot: 0, av: null, previewAV: null, previewRoomId: 2, roomId: 1, roomIds: [1,2], roomSlideDirection: 1 });
Object.defineProperty(mask, 'activeFrameReady', { get() { readyReads++; return ready; } });
Object.defineProperty(mask, 'previewReady', { get() { readyReads++; return ready; } });
assert.equal(mask.slotHasCurrentFrame(0), false);
assert.equal(mask.slotHasCurrentFrame(1), false);
assert.equal(readyReads, 2, 'both initial masks must subscribe before players exist');
ready = true; mask.av = {}; mask.previewAV = {};
assert.equal(mask.slotHasCurrentFrame(0), true);
assert.equal(mask.slotHasCurrentFrame(1), true);
mask.previewRoomId = 3;
assert.equal(mask.slotHasCurrentFrame(1), false, 'a stale adjacent frame stays masked');
console.log('PASS: compiled live masks subscribe on initial render and only reveal the matching room frame.');
