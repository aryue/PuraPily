// Run the actual CompileArkTS method with controlled native creation/network lifetimes.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const start = source.indexOf('    private setPlaybackCid(');
const end = source.indexOf('    private setupAudioL(', start);
assert.ok(start >= 0 && end > start);
const tick = () => new Promise(resolve => setImmediate(resolve));
function gate() { let resolve, reject; const promise = new Promise((r, j) => { resolve = r; reject = j; }); return { resolve, reject, promise }; }
function fixture() {
  const creation = gate(), url = gate(), probe = gate();
  const cidTimers = [];
  const sourceAgents = [], bridgeAgents = [], sourceHeaders = [], bridgeReferers = [];
  let creations = 0, requests = 0, probes = 0, stops = 0, recoveries = 0;
  const player = { releases: 0, sources: [], strategies: [], async release() { this.releases++; },
    async setMediaSource(src, strategy) { this.sources.push(src); this.strategies.push(strategy); } };
  const context = { exports: {}, setTimeout(callback, ms) { cidTimers.push({ callback, ms }); return setTimeout(callback, ms); }, clearTimeout, console,
    PlaybackDeadline: require('./playback-deadline-test-helper.cjs')(),
    selectDecodablePlayUrl: result => result,
    startupPlaybackStrategy: () => require('./test-player-startup-policy.cjs')(26),
    PlaybackStartup: { trace() {}, span() { return null; } }, logInfo() {}, logWarn() {}, logError() {}, errMsg: e => e.message,
    media: { createAVPlayer() { creations++; return creation.promise; },
      createMediaSourceWithUrl(url, headers) { sourceHeaders.push(headers); sourceAgents.push(headers?.['User-Agent']); return url; } },
    AppStorage: { get() { return ''; } },
    getVideoPlayUrl() { requests++; return url.promise; },
    DashPlayerBridge: class { buildAndStart(_dash, referer, ua) { bridgeReferers.push(referer); bridgeAgents.push(ua); probes++; return probe.promise; } async stopIfRunning() { stops++; } }
  };
  vm.runInNewContext(ts.transpileModule('export class Page {' + source.slice(start, end) + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const page = new context.exports.Page();
  Object.assign(page, { referenceAlive: true, referenceSwitchGeneration: 1, initPInProgress_: false,
    av: null, vi: { bvid: 'BVtest', cid: 2 }, qn: 116, initialProgress_: 0,
    async release() { const retired = this.av; this.av = null; if (retired) await retired.release(); },
    recoverPlaybackStall() { recoveries++; },
    applyServerResumePoint() {}, applyAcceptQuality() {}, getQlLabel() { return '1080p'; }, setupL() {} });
  return { page, player, creation, url, probe, cidTimers, sourceAgents, bridgeAgents, sourceHeaders, bridgeReferers, counts: () => ({ creations, requests, probes, stops, recoveries }) };
}
const dash = { url: 'video', audioUrl: 'audio', actualQn: 116, dash: {} };
(async () => {
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve({ ...dash, mediaUserAgent: 'App-media-UA', mediaReferer: '' });
    f.creation.resolve(f.player); f.probe.resolve('local-mpd'); await job;
    assert.deepEqual(f.bridgeAgents, ['App-media-UA'], 'App CDN headers reach DASH probing and proxy fetches');
    assert.deepEqual(f.bridgeReferers, ['']);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve({ url: 'app-direct', actualQn: 80, mediaUserAgent: 'App-media-UA', mediaReferer: '' });
    f.creation.resolve(f.player); await job;
    assert.deepEqual(f.sourceAgents, ['App-media-UA'], 'direct App sources keep their media headers');
    assert.equal('Referer' in f.sourceHeaders[0], false);
  }
  {
    const f = fixture(); f.page.vi.cid = 0;
    const job = f.page.initP();
    await tick();
    assert.equal(f.counts().creations, 1, 'native creation overlaps CID lookup');
    assert.equal(f.counts().requests, 0);
    assert.deepEqual(f.cidTimers.map(x => x.ms), [5000], 'CID wait uses one timeout and no polling');
    f.page.setPlaybackCid(12); await tick();
    assert.equal(f.counts().requests, 1, 'CID notification starts lookup immediately');
    f.url.resolve({ url: 'video', actualQn: 80 }); f.creation.resolve(f.player); await job;
    assert.equal(f.page.cidReady_, null); assert.equal(f.player.releases, 0);
  }
  {
    const f = fixture(); f.page.vi.cid = 0;
    const job = f.page.initP();
    f.cidTimers[0].callback(); f.creation.resolve(f.player); await job; await tick();
    assert.match(f.page.err, /CID/);
    assert.equal(f.counts().requests, 0); assert.equal(f.player.releases, 1);
    assert.equal(f.page.cidReady_, null);
    f.page.setPlaybackCid(12); await tick();
    assert.equal(f.counts().requests, 0, 'late CID cannot resurrect a timed out attempt');
  }
  {
    const f = fixture();
    const job = f.page.initP();
    await f.page.initP();
    assert.deepEqual(f.counts(), { creations: 1, requests: 1, probes: 0, stops: 0, recoveries: 0 });
    f.url.resolve(dash); await tick();
    assert.equal(f.counts().probes, 1, 'DASH probing starts while native creation is pending');
    f.probe.resolve('local-mpd'); f.creation.resolve(f.player); await job;
    assert.equal(f.page.av, f.player); assert.deepEqual(f.player.sources, ['local-mpd']);
    assert.deepEqual(Object.keys(f.player.strategies[0]), [], 'the actual compiled startup policy reaches the native DASH source without a forced waterline');
    assert.equal(f.player.releases, 0); assert.equal(f.counts().stops, 0);
    assert.equal(f.page.initPInProgress_, false);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve({ url: 'direct-remote', actualQn: 80 }); f.creation.resolve(f.player); await job;
    assert.equal(f.player.strategies[0], undefined, 'direct remote streams retain adaptive buffering');
    assert.equal(f.counts().probes, 0);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.page.referenceAlive = false;
    f.url.resolve(dash); f.creation.resolve(f.player); await job;
    assert.equal(f.page.av, null); assert.equal(f.player.releases, 1);
    assert.equal(f.counts().probes, 0, 'exit during URL lookup starts no bridge');
    assert.equal(f.page.err, undefined);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve(dash); f.creation.resolve(f.player); await tick();
    f.page.referenceSwitchGeneration++; f.probe.resolve('stale-mpd'); await job;
    assert.equal(f.page.av, null); assert.equal(f.player.releases, 1); assert.equal(f.counts().stops, 1);
    assert.equal(f.page.err, undefined);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve({ url: '' }); f.creation.resolve(f.player); await job;
    assert.equal(f.player.releases, 1); assert.equal(f.page.err, 'no url');
    assert.equal(f.page.initPInProgress_, false);
    await tick(); assert.equal(f.counts().recoveries, 1, 'initialization failure queues recovery after cleanup');
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.url.resolve(dash); f.creation.resolve(f.player); f.probe.resolve(null); await job;
    assert.equal(f.player.releases, 1); assert.equal(f.counts().stops, 1);
    assert.equal(f.page.err, 'DASH 转播站启动失败');
  }
  {
    const f = fixture(); f.page.vi.cid = 0;
    const job = f.page.initP(); f.page.referenceAlive = false;
    f.page.initializationDeadline_.cancel();
    f.creation.resolve(f.player); await job;
    assert.equal(f.counts().requests, 0); assert.equal(f.player.releases, 1);
    assert.equal(f.page.initPInProgress_, false);
  }
  {
    const f = fixture(); const job = f.page.initP();
    f.creation.reject(new Error('native creation failed'));
    f.url.resolve({ url: 'video', actualQn: 116 }); await job;
    assert.equal(f.page.err, 'no player'); assert.equal(f.page.initPInProgress_, false);
  }
  {
    const begin = source.indexOf('    private requestReferenceFeedPreview(');
    const finish = source.indexOf('    private async prepareReferenceFeedPreview(', begin);
    const context = { exports: {} };
    vm.runInNewContext(ts.transpileModule('export class Preview {' + source.slice(begin, finish) + '}', {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, context);
    const page = new context.exports.Preview();
    let decoded = 0;
    Object.assign(page, { referencePreviewSurfaceId: 'surface', referenceStillDetails: new Map(), referenceStillRatios: new Map(),
      referencePublishStill() { return false; }, referenceDecodeStill() { decoded++; return Promise.resolve(true); },
      waitingForFirstFrame: true, referenceVerticalSwipe: false, referenceFeedLoading: false });
    page.requestReferenceFeedPreview({ id: 'BVnext' });
    assert.equal(decoded, 0, 'background preview must wait for main first frame');
    page.referenceVerticalSwipe = true;
    page.requestReferenceFeedPreview({ id: 'BVnext' });
    assert.equal(decoded, 1, 'an actual swipe is never blocked by the background throttle');
    page.referenceVerticalSwipe = false; page.waitingForFirstFrame = false;
    page.requestReferenceFeedPreview({ id: 'BVnext' });
    assert.equal(decoded, 2);
  }
  // Exercise the compiled search click with a pending network request.
  {
    const search = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/SearchPage.ts', 'utf8');
    const begin = search.indexOf('    async playVideo(');
    const finish = search.indexOf('    clearSearchText(', begin);
    assert.ok(begin >= 0 && finish > begin);
    const routes = [], prefetched = [];
    const context = { exports: {}, AppStorage: { get() { return 116; } }, logError() {},
      prefetchVideoPlayback(...args) { prefetched.push(args); return new Promise(() => {}); } };
    vm.runInNewContext(ts.transpileModule('export class Search {' + search.slice(begin, finish) + '}', {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, context);
    const page = new context.exports.Search();
    page.getUIContext = () => ({ getRouter: () => ({ pushUrl(route) { routes.push(route); return Promise.resolve(); } }) });
    page.playVideo({ id: 'BVsearch', cid: 0, title: 'search result' });
    assert.equal(routes.length, 1, 'search click navigates immediately even without CID');
    assert.equal(routes[0].params.cid, 0); assert.equal(prefetched.length, 1);
    page.playVideo({ id: 'media_123', title: 'season' });
    assert.equal(routes[1].params.mediaId, 123); assert.equal(prefetched.length, 1, 'PGC keeps its own route');
  }
  console.log('PASS: compiled startup overlap, single allocation, cancellation during lookup/probe, failure cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
