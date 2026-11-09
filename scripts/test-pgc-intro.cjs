const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8').replace(/\r\n/g, '\n');
function between(start, end) {
  const from = source.indexOf(start), to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}
const context = { exports: {}, TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 },
  HitTestMode: { Default: 0 }, ScrollState: { Fling: 2 }, Curve: { EaseOut: 0 } };
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${between('  private referenceVideoLink():', '  private async referenceCopyLink()')}
  ${between('  private referenceIntroScrollOffset(', '  private referenceFeedNeighbor(')}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
const p = new context.exports.Page();
Object.assign(p, { vi: { bvid: 'BV1example' }, epId_: 123, isPgc_: true });
assert.equal(p.referenceVideoLink(), 'https://www.bilibili.com/bangumi/play/ep123');
p.epId_ = 456;
assert.equal(p.referenceVideoLink(), 'https://www.bilibili.com/bangumi/play/ep456', 'sharing follows episode switches');
p.isPgc_ = false;
assert.equal(p.referenceVideoLink(), 'https://www.bilibili.com/video/BV1example');
// Both content types must shrink the player before consuming intro scrolling,
// then hand a continuous reverse drag back to the panel when the list hits top.
for (const isPgc_ of [false, true]) {
  let yOffset = 60;
  Object.assign(p, { isPgc_, at: 0, isLs: false, referencePanelOffset: -20,
    detailScroller: { currentOffset: () => ({ xOffset: 0, yOffset }) },
    referenceMinimumPanelOffset: () => -100, referencePanelDragOffset: x => Math.max(-100, x),
    getUIContext: () => ({ animateTo: (_, f) => f() }) });
  const touch = (type, windowY) => ({ type, touches: [{ windowX: 50, windowY }],
    changedTouches: [{ windowX: 50, windowY }] });
  p.referencePanelBodyTouch(touch(context.TouchType.Down, 200));
  assert.equal(p.referencePanelBodyCanDrag, true);
  assert.equal(p.referenceIntroScrollOffset(40), 0);
  p.referencePanelBodyTouch(touch(context.TouchType.Move, 100));
  assert.equal(p.referencePanelOffset, -100);
  p.referencePanelBodyTouch(touch(context.TouchType.Move, 80));
  assert.equal(p.referencePanelBodyCanDrag, false);
  assert.equal(p.referenceIntroScrollOffset(40), 40);
  yOffset = 0;
  p.referencePanelBodyTouch(touch(context.TouchType.Move, 110));
  assert.equal(p.referencePanelBodyCanDrag, true);
  p.referencePanelBodyTouch(touch(context.TouchType.Move, 140));
  assert.equal(p.referencePanelOffset, -70);
}
const panel = between('  ReferencePanel() {', '  ReferenceLandscapeResizeHandle() {');
assert.ok(!panel.includes('this.bDetailCard()'), 'PGC must not fall back to the legacy intro');
assert.ok(panel.includes('this.ReferenceIntro()'));
const episodes = between('  episodeSheetContent() {', '  seasonSheetContent() {');
assert.ok(episodes.includes('this.pagesForCurrentVideo().length > 0'), 'single-episode movies need a real episode row');
console.log('PASS: unified PGC intro, episode links, and continuous list/panel scroll handoff');
