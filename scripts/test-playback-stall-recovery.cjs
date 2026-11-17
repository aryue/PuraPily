const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
function method(from, to) {
  const start = source.indexOf(from), end = source.indexOf(to, start);
  assert.ok(start >= 0 && end > start);
  return source.slice(start, end);
}
function loadMonitor() {
  const monitor = { exports: {} };
  const source = fs.readFileSync('entry/src/main/ets/utils/PlaybackStallMonitor.ets', 'utf8');
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, monitor);
  return monitor.exports.PlaybackStallMonitor;
}
function fixture() {
  let now = 0, interval, refreshes = 0;
  const timeouts = [];
  const events = [], context = { exports: {}, console,
    Date: { now: () => now }, setTimeout(callback) { timeouts.push(callback); return timeouts.length; }, clearTimeout() {},
    invalidatePlayUrlCache() { refreshes++; },
    setInterval(callback) { interval = callback; return 1; }, clearInterval() {},
    deviceInfo: { sdkApiVersion: 26 },
    PlaybackDeadline: class { async wait(task) { return task; } }, errMsg: e => e.message, logInfo() {},
    audio: { StreamUsage: { STREAM_USAGE_MUSIC: 1, STREAM_USAGE_MOVIE: 2 } },
    PlaybackStallMonitor: loadMonitor() };
  const body = method('    private setupL()', '    private playbackPreparation_') +
    method('    private applyServerResumePoint(', '    private saveWatchHistory(') +
    method('    private async recoverPlaybackStall(', '    private retry()');
  const observer = fs.readFileSync('entry/src/main/ets/services/PlaybackObservation.ets', 'utf8');
  const observerClass = observer.slice(observer.indexOf('export class PlaybackObservation'));
  vm.runInNewContext(ts.transpileModule(observerClass + '\nexport class Page {' +
    'playbackObservation_ = new PlaybackObservation();' + body + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const player = () => ({ currentTime: 0, duration: 60000, state: 'playing', on() {}, off() {} });
  const page = new context.exports.Page();
  Object.assign(page, { playbackResources_: { video: player() }, referenceAlive: true, referenceSwitchGeneration: 1,
    playbackStartupSlot_: { busy: false }, vi: { bvid: 'test', cid: 1 }, audioOutputMonitor: { bind() {} }, syncAspectFromPlayer() {}, playerPageVisible: true, waitingForFirstFrame: false,
    stallRecoveryKey_: '', stallResumeMs_: -1, releases: 0, starts: 0,
    playbackProfile: { mark(...args) { events.push(args); } },
    async release() { this.releases++; this.playbackResources_.video = null; },
    async initP() { this.starts++; this.resumedAt = this.stallResumeMs_; this.playbackResources_.video = player(); } });
  page.setupL();
  return { page, events, refreshes: () => refreshes, timeout() { timeouts.at(-1)(); }, tick(ms) { now = ms; interval(); } };
}
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  {
    const f = fixture(); f.page.waitingForFirstFrame = true; f.page.initialProgress_ = 42;
    f.page.playbackResources_.video.currentTime = -1; f.timeout(); await flush();
    assert.equal(f.page.starts, 1); assert.equal(f.page.resumedAt, 42000, 'first-frame retry preserves intended resume point');
    assert.equal(f.refreshes(), 1, 'first-frame failure discards old playurl cache');
    f.page.waitingForFirstFrame = true; f.page.setupL(); f.timeout(); await flush();
    assert.equal(f.page.starts, 1, 'startup recovery shares the existing one-attempt budget');
    assert.match(f.page.err, /重试/);
  }
  {
    const f = fixture(); f.page.playbackResources_.video = null; f.page.waitingForFirstFrame = true; f.page.initialProgress_ = 12;
    await f.page.recoverPlaybackStall(null);
    assert.equal(f.page.starts, 1); assert.equal(f.page.resumedAt, 12000, 'initialization failure before player adoption can recover');
  }
  {
    const f = fixture();
    f.tick(3000); f.page.playbackResources_.video.currentTime = 13; f.tick(5000);
    f.page.playbackResources_.video.currentTime = 133; f.tick(8000); await flush();
    assert.equal(f.page.starts, 1, 'tiny clock steps must not suppress stall recovery');
    assert.equal(f.page.resumedAt, 133, 'rebuild uses actual stalled position');
    f.page.stallResumeMs_ = 133;
    f.page.applyServerResumePoint({ lastPlayTimeMs: 50000 });
    assert.equal(f.page.initialProgress_, 0.133, 'stalled position takes precedence over history');
    assert.equal(f.page.stallResumeMs_, -1, 'position override is consumed once');
    assert.equal(f.events.some(e => e[0] === 'stall-recovered'), false);
    f.page.waitingForFirstFrame = false; f.page.setupL(); f.tick(16000); await flush();
    assert.equal(f.page.starts, 1, 'automatic rebuild is bounded per content session');
    assert.match(f.page.err, /重试/);
  }
  for (const flag of ['userPaused_', 'sg_', 'sk_', 'qs', 'ry_', 'waitingForFirstFrame', 'referenceFeedLoading']) {
    const f = fixture(); f.page[flag] = true; f.tick(20000); await flush();
    assert.equal(f.page.releases, 0, flag);
  }
  {
    const f = fixture(); f.page.playerPageVisible = false; f.tick(20000);
    assert.equal(f.page.releases, 0, 'hidden pages do not rebuild');
  }
  {
    const f = fixture(); f.page.playbackResources_.video.currentTime = 59500; f.tick(20000);
    assert.equal(f.page.releases, 0, 'end of stream is not a stall');
  }
  {
    const f = fixture();
    for (let i = 1; i <= 20; i++) { f.page.playbackResources_.video.currentTime = i * 250; f.tick(i * 1000); }
    assert.equal(f.page.releases, 0, 'slow continuous playback remains valid');
  }
  {
    const f = fixture(); let finish;
    f.page.release = () => { f.page.playbackResources_.video = null; return new Promise(resolve => { finish = resolve; }); };
    f.tick(8000); f.page.referenceSwitchGeneration++; finish(); await flush();
    assert.equal(f.page.starts, 0, 'a late release cannot restart the previous video');
    assert.equal(f.page.ry_, false, 'cancelled recovery must unlock later manual retry');
  }
  console.log('Compiled playback stall recovery tests passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
