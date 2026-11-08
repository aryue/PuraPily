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
function fixture() {
  let now = 0, interval, refreshes = 0;
  const timeouts = [];
  const events = [], context = { exports: {}, console,
    Date: { now: () => now }, setTimeout(callback) { timeouts.push(callback); return timeouts.length; }, clearTimeout() {},
    invalidatePlayUrlCache() { refreshes++; },
    setInterval(callback) { interval = callback; return 1; }, clearInterval() {},
    deviceInfo: { sdkApiVersion: 26 },
    PlaybackDeadline: class { async wait(task) { return task; } }, errMsg: e => e.message };
  const body = method('    private setupL()', '    private preparingPlayer_') +
    method('    private applyServerResumePoint(', '    private saveWatchHistory()') +
    method('    private async captureStalledPlaybackInfo(', '    private retry()');
  vm.runInNewContext(ts.transpileModule('export class Page {' + body + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const player = () => ({ currentTime: 0, duration: 60000, state: 'playing', on() {}, off() {} });
  const page = new context.exports.Page();
  Object.assign(page, { av: player(), referenceAlive: true, referenceSwitchGeneration: 1,
    vi: { bvid: 'test', cid: 1 }, playerPageVisible: true, waitingForFirstFrame: false,
    stallRecoveryKey_: '', stallResumeMs_: -1, releases: 0, starts: 0,
    playbackProfile: { mark(...args) { events.push(args); } },
    async release() { this.releases++; this.av = null; },
    async initP() { this.starts++; this.resumedAt = this.stallResumeMs_; this.av = player(); } });
  page.setupL();
  return { page, events, refreshes: () => refreshes, timeout() { timeouts.at(-1)(); }, tick(ms) { now = ms; interval(); } };
}
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  {
    const f = fixture(); f.page.waitingForFirstFrame = true; f.page.initialProgress_ = 42;
    f.page.av.currentTime = -1; f.timeout(); await flush();
    assert.equal(f.page.starts, 1); assert.equal(f.page.resumedAt, 42000, 'first-frame retry preserves intended resume point');
    assert.equal(f.refreshes(), 1, 'first-frame failure discards old playurl cache');
    f.page.waitingForFirstFrame = true; f.page.setupL(); f.timeout(); await flush();
    assert.equal(f.page.starts, 1, 'startup recovery shares the existing one-attempt budget');
    assert.match(f.page.err, /重试/);
  }
  {
    const f = fixture(); f.page.av = null; f.page.waitingForFirstFrame = true; f.page.initialProgress_ = 12;
    await f.page.recoverPlaybackStall(null);
    assert.equal(f.page.starts, 1); assert.equal(f.page.resumedAt, 12000, 'initialization failure before player adoption can recover');
  }
  {
    const f = fixture();
    f.page.av.getPlaybackInfo = async () => ({ download_rate: 500, buffer_duration: 0,
      server_ip_address: 'secret-ip', unexpected: 'secret-payload' });
    await f.page.captureStalledPlaybackInfo(f.page.av);
    assert.ok(f.events.some(e => e[0] === 'native-download_rate' && e[1] === 500));
    assert.ok(!JSON.stringify(f.events).includes('secret'), 'native fields use a numeric allowlist');
    f.page.av.getPlaybackInfo = async () => { throw Error('unavailable'); };
    await f.page.captureStalledPlaybackInfo(f.page.av);
    assert.ok(f.events.some(e => e[0] === 'native-statistics-unavailable'));
    assert.equal(f.page.playbackInfoPending_, false, 'statistics failure unlocks future capture');
  }
  {
    const f = fixture();
    f.tick(3000); f.page.av.currentTime = 13; f.tick(5000);
    f.page.av.currentTime = 133; f.tick(8000); await flush();
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
    const f = fixture(); f.page.av.currentTime = 59500; f.tick(20000);
    assert.equal(f.page.releases, 0, 'end of stream is not a stall');
  }
  {
    const f = fixture();
    for (let i = 1; i <= 20; i++) { f.page.av.currentTime = i * 250; f.tick(i * 1000); }
    assert.equal(f.page.releases, 0, 'slow continuous playback remains valid');
  }
  {
    const f = fixture(); let finish;
    f.page.release = () => { f.page.av = null; return new Promise(resolve => { finish = resolve; }); };
    f.tick(8000); f.page.referenceSwitchGeneration++; finish(); await flush();
    assert.equal(f.page.starts, 0, 'a late release cannot restart the previous video');
    assert.equal(f.page.ry_, false, 'cancelled recovery must unlock later manual retry');
  }
  console.log('Compiled playback stall recovery tests passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
