const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8').replace(/\r\n/g, '\n');
const start = source.indexOf('  private openEpisodeSheet():');
const end = source.indexOf('  @Builder', start);
const a = source.indexOf('  private isCurrentSeasonEpisode('), b = source.indexOf('  /** 切换合集分集', a);
assert.ok(start >= 0 && end > start && a >= 0 && b > a);
const context = { exports: {} };
const heightStart = source.indexOf('  private selectionSheetHeight(');
vm.runInNewContext(ts.transpileModule(`export class Page { ${source.slice(heightStart, start)} ${source.slice(start, end)} ${source.slice(a, b)} }`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
const p = new context.exports.Page();
p.referenceSafeTop = () => 48;
p.ch = 744;
p.navIndicatorHeight = 0;
assert.equal(p.selectionSheetHeight(400), 400);
assert.equal(p.selectionSheetHeight(280), 280);
p.ch = 400;
p.navIndicatorHeight = 12;
assert.equal(p.selectionSheetHeight(400), 324, 'compact landscape must fit inside the actual safe viewport');
p.vd = { pages: Array.from({ length: 150 }, (_, i) => ({ cid: i + 1 })) };
p.referenceEpisodeSelection = -1;
for (const [index, segment, local] of [[0,0,0], [19,0,19], [20,1,0], [38,1,18], [149,7,9]]) {
  p.currentPageIndex = index;
  Object.defineProperty(p, 'showEpisodeSheet', { configurable: true, set(value) {
    assert.equal(value, true);
    assert.equal(p.episodeSegment, segment, 'segment is ready before showing the sheet');
    assert.equal(p.episodeSheetInitialIndex, local, 'initial index is local to the segment');
  } });
  p.openEpisodeSheet();
}
delete p.showEpisodeSheet;
p.referenceEpisodeSelection = 59;
p.openEpisodeSheet();
assert.equal(p.episodeSegment, 2);
assert.equal(p.episodeSheetInitialIndex, 19);
const sections = [
  { episodes: [{ cid: 8, bvid: 'BVsame' }, { cid: 9, bvid: 'BVother' }] },
  { episodes: [{ cid: 70, bvid: 'BVthird' }, { cid: 71, bvid: 'BVsame' }] }
];
p.vi = { cid: 71, bvid: 'BVsame' };
p.vd = { aid: 400, ugc_season: { sections } };
Object.defineProperty(p, 'showSeasonSheet', { configurable: true, set(value) {
  assert.equal(value, true);
  assert.equal(p.seasonSectionIndex, 1, 'exact cid wins across sections');
  assert.equal(p.seasonSheetInitialIndex, 1);
} });
p.openSeasonSheet();
delete p.showSeasonSheet;
p.vi = { cid: 0, bvid: 'BVother' };
p.openSeasonSheet();
assert.equal(p.seasonSectionIndex, 0);
assert.equal(p.seasonSheetInitialIndex, 1);
const bindSeason = source.slice(source.indexOf('.bindSheet($$this.showSeasonSheet'), source.indexOf('// 主要内容区域'));
const bindEpisode = source.slice(source.indexOf('.bindSheet($$this.showEpisodeSheet'), start);
for (const binding of [bindSeason, bindEpisode]) {
  assert.ok(!binding.includes('setTimeout') && !binding.includes('scrollToIndex'), 'opening must have no delayed scroll');
}
assert.ok(source.includes('initialIndex: this.episodeSheetInitialIndex'));
assert.ok(source.includes('initialIndex: this.seasonSheetInitialIndex'));
console.log('PASS: pre-open positions, segment-local indices, pending selection and exact cross-section collection matching');
