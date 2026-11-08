const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(file, imports = {}, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, file + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => imports[name] || {}, ...globals });
  return exports;
}
async function main() {
  const { PlaybackProgress: p } = load('utils/PlaybackProgress');
  const key = p.key('1', 'BVtest', 11, 0);
  const entry = { key, position: 45.3, duration: 60, completed: false, updatedAt: 1 };
  let raw = p.write('[]', entry);
  assert.equal(p.resume(p.read(raw, key).position, 60), 45.3);
  raw = p.write(raw, { ...entry, position: 12 });
  assert.equal(p.read(raw, key).position, 12, 'backwards seeking must replace the old position');
  assert.equal(p.read(raw, p.key('1', 'BVtest', 12, 0)), undefined, 'parts must be isolated');
  assert.equal(p.read(raw, p.key('2', 'BVtest', 11, 0)), undefined, 'accounts must be isolated');
  raw = p.write(raw, { ...entry, position: 60, completed: true });
  const done = p.read(raw, key);
  assert.equal(p.resume(done.position, done.duration, done.completed), 0, 'completed playback restarts');
  assert.equal(p.resume(60, 60), 0, 'route positions at the end also restart');
  assert.equal(p.resume(-1, 60), 0);
  assert.equal(p.resume(NaN, 60), 0);
  raw = p.write(raw, { ...entry, position: 0 });
  assert.equal(p.read(raw, key).completed, false, 'replay clears completion');
  assert.equal(p.read('broken', key), undefined);
  assert.equal(p.read('{}', key), undefined);
  assert.equal(p.read(p.write('{}', entry), key).position, 45.3);
  const track = load('utils/BufferedTrack', {}, { GradientDirection: { Right: 1 } });
  assert.equal(track.bufferedTrack(30, 60).colors[1][1], 0.5);
  assert.equal(track.bufferedTrack(90, 60).colors[1][1], 1);
  assert.equal(track.bufferedTrack(-1, 60).colors[1][1], 0);

  const writes = [], storage = new Map();
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const api = { async reportWatchProgress(aid, cid, progress, cookie) {
    writes.push({ aid, cid, progress, cookie });
    if (writes.length === 1) await gate;
    return true;
  } };
  const { WatchHistoryHelper } = load('model/WatchHistoryHelper', {
    '../api/BilibiliHistoryApi': { BilibiliHistoryApi: { getInstance: () => api } },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
  }, { AppStorage: { get: k => storage.get(k), set: (k, v) => storage.set(k, v) } });
  const helper = WatchHistoryHelper.getInstance();
  helper.setCookie('account1');
  const item = { aid: 1, cid: 11, bvid: 'BVtest', epId: 0, seasonId: 0, playProgress: 20 };
  const old = helper.saveWatchRecord(item);
  const completed = helper.saveWatchRecord({ ...item, playProgress: -1 });
  helper.setCookie('account2');
  await new Promise(setImmediate);
  assert.equal(writes.length, 1, 'a later update cannot overtake a slow request');
  release();
  await Promise.all([old, completed]);
  assert.deepEqual(writes.map(x => x.progress), [20, -1]);
  assert.ok(writes.every(x => x.cookie === 'account1'), 'queued uploads retain their account');
  await helper.saveWatchRecord({ ...item, playProgress: 0 });
  assert.equal(writes.length, 2, 'startup zero must not erase cloud history');
  await helper.saveWatchRecord({ ...item, epId: 22, seasonId: 33, playProgress: -1 });
  assert.equal(writes[2].progress, -1, 'PGC completion passes the minimum progress guard');
  const bodies = [];
  const { BilibiliHistoryApi } = load('api/BilibiliHistoryApi', {
    '@kit.NetworkKit': { http: { RequestMethod: { POST: 'POST' }, createHttp: () => ({
      async request(_url, options) { bodies.push(options.extraData); return { responseCode: 200, result: '{"code":0}' }; },
      destroy() {}
    }) } },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} },
    './FeedbackService': { extractCsrfFromCookie: () => 'test' }
  });
  await BilibiliHistoryApi.getInstance().reportWatchProgress(1, 11, -1, 'test');
  assert.ok(bodies[0].includes('played_time=-1'), 'completion must survive form serialization');
  // Execute the real page seek method with the native callback arriving before
  // AVPlayer.currentTime catches up, as observed on the emulator.
  const page = fs.readFileSync(path.join(root, 'pages/VideoPlayerPage.ets'), 'utf8');
  const seekSource = page.slice(page.indexOf('  async seek('), page.indexOf('  applyFSResistance('));
  const seekExports = {};
  vm.runInNewContext(ts.transpileModule(`class Harness { ${seekSource} } exports.Harness = Harness;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports: seekExports, setTimeout, media: { SeekMode: { SEEK_CLOSEST: 0, SEEK_PREV_SYNC: 1 } } });
  const h = new seekExports.Harness();
  const savedPositions = [];
  Object.assign(h, { play: false, dur: 75, sg_: false, pendingSeekTarget_: -1,
    cancelVideoSpeedSync() {}, cancelDelayHide() {}, delayMs_: async () => {},
    saveWatchHistory() { savedPositions.push(this.ct); },
    av: { state: 'paused', currentTime: 46000,
      seek(ms) { h.videoSeekPosition = ms / 1000; h.videoSeekResolve_(); }
    }
  });
  await h.seek(13, false);
  assert.equal(h.av.currentTime, 46000, 'native currentTime is intentionally stale');
  assert.equal(savedPositions[0], 13, 'upload and local save use the acknowledged seek position');
  h.av.currentTime = 75000;
  h.av.state = 'completed';
  h.referencePlaybackCompleted = true;
  await h.seek(0, false);
  assert.equal(savedPositions[1], 0, 'replay must not upload the old duration as the new position');
  assert.equal(h.referencePlaybackCompleted, false);
  h.play = true;
  h.av.pause = async () => { h.av.state = 'paused'; };
  h.av.play = async () => { h.av.state = 'completed'; h.referencePlaybackCompleted = true; };
  await h.seek(75, false, true);
  assert.equal(h.play, false, 'completion during seek render wait must not restore playing state');
  assert.equal(h.referencePlaybackCompleted, true);
  h.play = false;
  h.av.state = 'paused';
  h.av.currentTime = 46000;
  h.av.seek = () => {}; // native callback misses the wait budget
  const beforeTimeout = savedPositions.length;
  await h.seek(13, false, true);
  assert.equal(savedPositions.length, beforeTimeout, 'seek timeout cannot upload the stale currentTime');
  assert.equal(h.seekProgressPending, true, 'a late native confirmation must remain eligible for saving');
  const seekCallback = page.slice(page.indexOf("    this.av.on('seekDone',"),
    page.indexOf('    // ⭐ 注册startRenderFrame'));
  const callbackExports = {};
  h.av.on = (name, callback) => { h[name] = callback; };
  vm.runInNewContext(ts.transpileModule(`exports.register = function() { ${seekCallback} };`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports: callbackExports, player: h.av, generation: 0, logInfo() {} });
  callbackExports.register.call(h);
  h.seekDone(13000);
  assert.equal(savedPositions.at(-1), 13, 'late seekDone must upload the confirmed position');
  assert.equal(h.seekProgressPending, false);
  const historyMethod = page.slice(page.indexOf('  private saveWatchHistory(): void {'),
    page.indexOf('  private playbackProgressKey(): string {'));
  const localStart = page.indexOf('  private saveLocalPlaybackProgress(): void {');
  const localMethod = page.slice(localStart, page.indexOf('\n  /**', localStart));
  const completionExports = {}, completionStorage = new Map(), completedUploads = [];
  vm.runInNewContext(ts.transpileModule(`class CompletionHarness {
    ${historyMethod} ${localMethod} playbackProgressKey() { return 'completed'; }
  } exports.CompletionHarness = CompletionHarness;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports: completionExports, PlaybackProgress: p, MIN_HEARTBEAT_PROGRESS_SEC: 5,
    WatchHistoryItem: class {}, logWarn() {},
    WatchHistoryHelper: { getInstance: () => ({ setCookie() {}, saveWatchRecord: item => completedUploads.push(item) }) },
    AppStorage: { get: key => key === 'biliCookie' ? 'test' : completionStorage.get(key),
      set: (key, value) => completionStorage.set(key, value) }
  });
  const completedPage = new completionExports.CompletionHarness();
  Object.assign(completedPage, { vi: { bvid: 'BVtest', cid: 11 }, vd: { aid: 1 },
    av: { state: 'completed' }, ct: 75, dur: 75,
    sk_: true, sg_: true, seekProgressPending: true, referencePlaybackCompleted: true });
  completedPage.saveWatchHistory();
  assert.equal(completedUploads[0].playProgress, -1, 'native completion bypasses seek upload guards');
  assert.equal(p.read(completionStorage.get('playbackProgressV1'), 'completed').completed, true,
    'completion during seek must be persisted before a process restart');
  console.log('PASS: resume, backwards seeks, replay, part/account isolation, buffering, ordered cloud updates, completion, zero guard');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
