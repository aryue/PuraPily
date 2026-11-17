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
const context = { exports: {}, MIN_HEARTBEAT_PROGRESS_SEC: 15, logInfo() {}, logError() {}, errMsg: String,
  setTimeout: (fn) => { fn(); return 1; }, ScrollAlign: { START: 0, CENTER: 1, END: 2, AUTO: 3 } };
const pgcApi = {};
context.require = () => pgcApi;
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/PgcPlaybackEpisodes.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${between(page, '  private pagesForCurrentVideo(', '  // ⭐ 格式化时长')}
}
export class Strip {
  ${between(strip, '  private syncPages():', '  build() {')}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);

async function main() {
  const portrait = between(page, '  ReferencePortrait() {', '  private referencePortraitFeedActive():');
  assert.ok(portrait.includes('this.waitingForFirstFrame && !this.vd'), 'buffering must not hide an existing introduction');
  const pgcEpisodes_ = new context.exports.PgcPlaybackEpisodes();
  const episodes = Array.from({ length: 4 }, (_, i) => ({
    id: 100 + i, aid: 50 + i, bvid: `BVpart${i}`, cid: i + 10, title: `Part ${i}`, duration: 12345
  }));
  const season = { title: 'Stable title', desc: 'Stable description', upInfo: {}, stat: {}, episodes };
  const { resolvePgcEpisodeEntry } = context.exports;
  pgcApi.getPgcEpisodeInfo = () => new Promise(() => {});
  pgcApi.getPgcSeasonInfoByEpId = async () => season;
  const preferred = await Promise.race([
    resolvePgcEpisodeEntry(103),
    new Promise(resolve => setImmediate(() => resolve(null)))
  ]);
  assert.equal(preferred?.cid, 13, 'a usable season CID does not wait for the episode endpoint');
  pgcApi.getPgcEpisodeInfo = async () => ({ cid: 99 });
  pgcApi.getPgcSeasonInfoByEpId = async () => null;
  assert.equal((await resolvePgcEpisodeEntry(103)).cid, 99);
  let seasonRequests = 0;
  pgcApi.getPgcSeasonInfoByEpId = async () => { seasonRequests++; return season; };
  assert.deepEqual(await Promise.all([pgcEpisodes_.seasonForEpisode(103), pgcEpisodes_.seasonForEpisode(103)]),
    [season, season]);
  assert.equal(await pgcEpisodes_.seasonForEpisode(100), season);
  assert.equal(seasonRequests, 1, 'all entry consumers and episodes of the same season reuse the lookup');
  const vd = pgcEpisodes_.load(season, episodes[0], 10);
  const pages = vd.pages;
  assert.equal(pgcEpisodes_.bvidForCid(13), 'BVpart3');
  assert.equal(pgcEpisodes_.aidAt(3), 53);
  assert.equal(pgcEpisodes_.episodeAt(3), 103);
  assert.equal(pgcEpisodes_.indexOf(103), 3);
  assert.equal(pgcEpisodes_.bvidForCid(999), '');
  assert.equal(pages[3].duration, 12);
  const related = [{ id: 'BVstable' }];
  const scroller = { savedOffset: 135 };
  const p = new context.exports.Page();
  const heartbeat = [], started = [], comments = [];
  let unlock;
  let releases = 0;
  Object.assign(p, { vd, vi: { cid: 10 }, relatedVideos: related, detailScroller: scroller, referenceDescriptionExpanded: true,
    referencePanelOffset: -120, at: 0, referenceAlive: true, isPgc_: true, currentPageIndex: 0,
    episodeSwitchJob_: null, pendingEpisodeIndex_: -1, referenceEpisodeSelection: -1,
    epId_: 100, ct: 30, pgcEpisodes_,
    playbackProgressReporter_: { resetHeartbeat() {} },
    resetFullscreenVideo() {}, reportPgcHeartbeat: async () => { heartbeat.push(p.epId_); },
    release: () => ++releases === 1 ? new Promise(r => { unlock = r; }) : Promise.resolve(),
    setPlaybackCid: (cid, bvid, aid, epId) => {
      p.cid = cid; p.vi.cid = cid; p.vi.bvid = bvid; p.aidFromParams_ = aid;
      if (epId !== undefined) p.epId_ = epId;
    }, commentDataSource: { clear() {} },
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
  s.scroller = { calls: [], scrollToIndex(index, smooth, align) { this.calls.push([index, smooth, align]); } };
  s.pages = Array.from({ length: 150 }, (_, i) => ({ cid: i, page: i + 1, part: `Song ${i}` }));
  s.syncPages();
  assert.equal(s.scroller.calls.length, 0, 'first layout keeps the initialIndex position');
  s.selectedIndex = 1;
  s.pages = s.pages.map(p => ({ ...p }));
  s.syncPages();
  assert.equal(reloads, 1, 'selection and equal incoming pages retain the lazy list');
  assert.equal(s.scroller.calls.length, 0, 'equal pages do not re-scroll');
  // 自动连播/选集面板跳转：选中项变化必须把列表滚到该集，否则选中项留在屏外
  s.selectedIndex = 42;
  s.followSelection();
  assert.deepEqual(s.scroller.calls, [[42, true, 3]], 'selection change scrolls the new episode into view (AUTO keeps visible rows still)');
  s.scroller.calls = [];
  s.laidOut = true;
  s.pages = [{ cid: 500, page: 1, part: 'New video' }];
  s.selectedIndex = 0;
  s.syncPages();
  assert.equal(reloads, 2, 'a different video replaces the data');
  assert.deepEqual(s.scroller.calls, [[0, false, 3]], 'a replaced episode list re-aligns without animation');
  console.log('PASS: immediate selection, latest queued episode, outgoing history, stable intro identity and lazy list reuse');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
