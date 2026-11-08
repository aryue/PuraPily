const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const page = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8').replace(/\r\n/g, '\n');
const strip = fs.readFileSync('entry/src/main/ets/components/ReferenceEpisodeStrip.ets', 'utf8').replace(/\r\n/g, '\n');
function between(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a);
  return source.slice(a, b);
}
const context = { exports: {}, MIN_HEARTBEAT_PROGRESS_SEC: 15, logInfo() {}, logError() {}, errMsg: String };
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${between(page, '  private switchEpisode(', '  // ⭐ 格式化时长')}
}
export class Strip {
  ${between(strip, '  private syncPages():', '  build() {')}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);

async function main() {
  const portrait = between(page, '  ReferencePortrait() {', '  private referencePortraitFeedActive():');
  assert.ok(portrait.includes('this.waitingForFirstFrame && !this.vd'), 'buffering must not hide an existing introduction');
  const pages = Array.from({ length: 4 }, (_, i) => ({ cid: i + 10, page: i + 1, part: `Part ${i}` }));
  const vd = { aid: 50, cid: 10, title: 'Stable title', desc: 'Stable description', pages };
  const related = [{ id: 'BVstable' }];
  const scroller = { savedOffset: 135 };
  const p = new context.exports.Page();
  const heartbeat = [], started = [], comments = [];
  let unlock;
  let releases = 0;
  Object.assign(p, { vd, vi: { cid: 10 }, relatedVideos: related, detailScroller: scroller, referenceDescriptionExpanded: true,
    referencePanelOffset: -120, at: 0, referenceAlive: true, isPgc_: true, currentPageIndex: 0,
    episodeSwitchJob_: null, pendingEpisodeIndex_: -1, referenceEpisodeSelection: -1,
    epId_: 100, ct: 30, pgcEpIds_: [100, 101, 102, 103], pgcAids_: [50, 51, 52, 53],
    resetFullscreenVideo() {}, reportPgcHeartbeat: async () => { heartbeat.push(p.epId_); },
    release: () => ++releases === 1 ? new Promise(r => { unlock = r; }) : Promise.resolve(),
    setPlaybackCid: cid => { p.cid = cid; p.vi.cid = cid; }, commentDataSource: { clear() {} },
    loadC: aid => comments.push(aid), initP: async () => { started.push(p.cid); } });
  const first = p.switchEpisode(1);
  await new Promise(setImmediate);
  assert.equal(p.referenceEpisodeSelection, 1, 'inline highlight updates before release/network completes');
  const second = p.switchEpisode(2);
  const last = p.switchEpisode(3);
  assert.equal(p.referenceEpisodeSelection, 3);
  assert.equal(first, second);
  assert.equal(first, last);
  unlock();
  await last;
  assert.deepEqual(heartbeat, [100], 'progress is reported with the outgoing episode identity');
  assert.deepEqual(started, [11, 13], 'intermediate queued requests are superseded');
  assert.deepEqual(comments, [51, 53]);
  assert.equal(p.currentPageIndex, 3);
  assert.equal(p.epId_, 103);
  assert.equal(vd.aid, 53);
  assert.equal(p.vd, vd);
  assert.equal(p.vd.pages, pages);
  assert.equal(p.relatedVideos, related);
  assert.equal(p.detailScroller, scroller);
  assert.equal(p.referenceDescriptionExpanded, true);
  assert.equal(p.referencePanelOffset, -120);
  assert.equal(p.at, 0);
  assert.equal(p.referenceEpisodeSelection, -1);
  const before = releases;
  await p.switchEpisode(3);
  await p.switchEpisode(99);
  assert.equal(releases, before, 'current and invalid rows cannot restart playback');

  const s = new context.exports.Strip();
  let items = [], reloads = 0;
  s.items = { getRawItems: () => items, reloadItems: x => { items = x; reloads++; } };
  s.pages = Array.from({ length: 150 }, (_, i) => ({ cid: i, page: i + 1, part: `Song ${i}` }));
  s.syncPages();
  s.selectedIndex = 1;
  s.pages = s.pages.map(p => ({ ...p }));
  s.syncPages();
  assert.equal(reloads, 1, 'selection and equal incoming pages retain the lazy list');
  s.pages = [{ cid: 500, page: 1, part: 'New video' }];
  s.syncPages();
  assert.equal(reloads, 2, 'a different video replaces the data');
  console.log('PASS: immediate selection, latest queued episode, outgoing history, stable intro identity and lazy list reuse');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
