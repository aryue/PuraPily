// Exercise CompileArkTS output: independent detail consumers and immediate entry navigation.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const tick = () => new Promise(resolve => setImmediate(resolve));
function gate() { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { promise, resolve, reject }; }
function load(file, start, end, mocks) {
  const source = fs.readFileSync(root + file + '.ts', 'utf8');
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, file);
  const context = { exports: {}, ...mocks };
  vm.runInNewContext(ts.transpileModule('export class Page {' + source.slice(a, b) + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return new context.exports.Page();
}
function interactions() {
  const follow = gate(), status = gate(), lookup = gate();
  const calls = [];
  let cookie = 'account-a';
  const page = load('pages/VideoPlayerPage', '    private loadInitialVideoInteractions(', '    private scheduleFloatBtnFadeIn(', {
    AppStorage: { get: () => cookie }, logInfo() {}, logWarn() {},
    getVideoDetail: () => lookup.promise,
    getFollowStatus() { calls.push('follow'); return follow.promise; },
    getVideoUserStatus() { calls.push('status'); return status.promise; }
  });
  Object.assign(page, { vi: { bvid: 'BVtest', cid: 1 }, referenceAlive: true, referenceSwitchGeneration: 1,
    interactionRevision: 1, expandedCommentIds: new Set(), savedScrollOffsetMap: new Map(), replyPageMap: new Map(),
    hasMoreRepliesMap: new Map(), loadingRepliesMap: new Map(), commentDataSource: { clear() {} },
    commentsInitialized: true, predecodeKeyImages() {}, applyDetailDimension() {},
    setPlaybackCid(cid) { this.vi.cid = cid; }, initP() { calls.push('init'); },
    loadC() { calls.push('comments'); }, fetchRelatedVideos() { calls.push('related'); } });
  const detail = { bvid: 'BVtest', aid: 2, owner: { mid: 3 }, stat: { like: 4, coin: 5, favorite: 6 }, pages: [] };
  return { page, detail, calls, follow, status, lookup, changeAccount() { cookie = 'account-b'; } };
}
async function main() {
  {
    const f = interactions();
    await f.page.loadD(f.detail);
    assert.deepEqual(f.calls, ['follow', 'status', 'comments', 'related']);
    assert.equal(f.page.ldd, false, 'detail finishes while both status requests remain pending');
    f.status.resolve({ like: true, coin: 1, favorite: true }); await tick();
    assert.equal(f.page.isLiked, true, 'status does not wait for follow');
    f.follow.resolve(true); await tick(); assert.equal(f.page.isFollowed, true);
  }
  for (const stale of [f => f.page.interactionRevision++, f => f.page.referenceSwitchGeneration++,
    f => { f.page.referenceAlive = false; }, f => { f.page.vi.bvid = 'BVnext'; }, f => f.changeAccount()]) {
    const f = interactions(); f.page.loadInitialVideoInteractions(f.detail, 'BVtest', 1, 1); stale(f);
    f.follow.resolve(true); f.status.resolve({ like: true, coin: 1, favorite: true }); await tick();
    assert.equal(f.page.isLiked, undefined); assert.equal(f.page.isFollowed, undefined);
  }
  for (const stale of [f => f.changeAccount(), f => { f.page.referenceAlive = false; }]) {
    const f = interactions(); const job = f.page.loadD(); stale(f);
    f.lookup.resolve(f.detail); await job;
    assert.equal(f.page.vd, undefined); assert.deepEqual(f.calls, []);
  }
  {
    const f = interactions(); f.page.vi.cid = 0; f.detail.cid = 77;
    await f.page.loadD(f.detail);
    assert.equal(f.page.vi.cid, 77, 'detail CID wakes startup even without a pages array');
    assert.ok(f.calls.includes('init'));
    f.follow.resolve(false); f.status.resolve(null); await tick();
  }
  {
    const lookup = gate();
    const page = load('pages/VideoPlayerPage', '    private async initFromAid(', '    private userPaused_', {
      AppStorage: { get: () => 'account-a' }, getVideoDetail: () => lookup.promise, logInfo() {}, logError() {}
    });
    Object.assign(page, { referenceAlive: true, referenceSwitchGeneration: 1, vi: { bvid: '' } });
    const job = page.initFromAid(123); page.referenceAlive = false;
    lookup.resolve({ bvid: 'BVlate', cid: 4 }); await job;
    assert.equal(page.vi.bvid, '', 'late aid lookup cannot restart an exited page');
    assert.equal(page.err, undefined);
  }
  {
    const f = interactions();
    f.detail.req_user = { like: true, dislike: false, coin: 1, favorite: true };
    await f.page.loadD(f.detail);
    assert.deepEqual(f.calls, ['follow', 'comments', 'related']);
    assert.equal(f.page.isLiked, true);
    f.follow.reject(new Error('offline')); await tick();
    assert.equal(f.page.ldd, false, 'follow failure leaves the loaded content available');
  }
  const routes = [], prefetches = [];
  const mocks = { AppStorage: { get: () => 116 }, logError() {},
    prefetchVideoPlayback(...args) { prefetches.push(args); return new Promise(() => {}); },
    router: { pushUrl(route) { routes.push(route); return Promise.resolve(); } } };
  {
    const page = load('pages/CommentDetailPage', '    private goToVideo(', '    private openReplySheet(', mocks);
    Object.assign(page, { aid: 123, bvid_: '', videoDetail: { cid: 4, title: 'title', pic: 'cover' } });
    page.goToVideo();
    assert.deepEqual(prefetches[0], ['123', 4, 116]);
    assert.equal(routes[0].params.coverUrl, 'cover'); assert.equal(routes[0].params.cid, 4);
  }
  {
    const page = load('components/WhisperChatView', '    private openVideo(', '    private ', mocks);
    page.getUIContext = () => ({ getRouter: () => mocks.router });
    page.openVideo('BVmessage', 'shared', 'message-cover');
    assert.equal(routes[1].params.coverUrl, 'message-cover');
    assert.deepEqual(prefetches[1], ['BVmessage', 0, 116]);
  }
  {
    const page = load('pages/RegionChannelPage', '    private onCardClick(', '    private ', mocks);
    page.getUIContext = () => ({ getRouter: () => mocks.router });
    page.onCardClick({ id: 'BVregion', aid: 123, cid: 8, coverUrl: 'region-cover', title: 'region' });
    assert.equal(routes[2].params.coverUrl, 'region-cover'); assert.equal(routes[2].params.cid, 8);
    assert.deepEqual(prefetches[2], ['BVregion', 8, 116]);
    page.onCardClick({ pgcSeasonId: 99, title: 'season', coverUrl: 'season-cover' });
    assert.equal(routes[3].params.mediaId, 99); assert.equal(prefetches.length, 3, 'PGC retains its own path');
  }
  console.log('PASS: compiled parallel interactions, independent content, stale responses, entry covers and immediate navigation');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
