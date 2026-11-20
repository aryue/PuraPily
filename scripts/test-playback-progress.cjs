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
  const completionStorage = new Map();
  const { PlaybackProgress: p } = load('utils/PlaybackProgress', {}, {
    AppStorage: { get: key => completionStorage.get(key), set: (key, value) => completionStorage.set(key, value) }
  });
  assert.equal(p.preparedDuration(75007, 80000, 500, false, 0), 75.007);
  assert.equal(p.preparedDuration(0, 75007, 500, false, 0), 75.007,
    'when the decoder reports zero, use this part’s MPD duration before whole-video metadata');
  assert.equal(p.preparedDuration(0, 0, 500, false, 0), 500);
  assert.equal(p.preparedDuration(75007, 80000, 76, true, 74), 74,
    'feed keeps its detail timeline even if native metadata differs');
  assert.equal(p.preparedDuration(75007, 80000, 76, true, 0), 76);
  assert.equal(p.preparedDuration(75007, 80000, 0, true, 0), 76);
  const key = p.key('1', 'BVtest', 11, 0);
  const entry = { key, position: 45.3, duration: 60, completed: false, updatedAt: 1 };
  const damagedStore = JSON.stringify([null, entry, 25]);
  assert.equal(p.read(damagedStore, key).position, 45.3);
  assert.equal(JSON.parse(p.write(damagedStore, { ...entry, position: 32 })).length, 1);
  assert.equal(p.startupResume(key, 12, 20000, 60), null, 'route position wins over server without local data');
  assert.equal(p.startupResume(key, 0, 20000, 60).position, 20);
  assert.equal(p.startupResume(key, 0, 57000, 60).source, 'serverEnd');
  assert.equal(p.startupResume(key, 0, 0, 60), null);
  p.saveLocal(key, 45.3, 60, false);
  assert.equal(p.startupResume(key, 12, 20000, 60).position, 45.3);
  p.saveLocal(key, 60, 60, true);
  assert.equal(p.startupResume(key, 12, 20000, 60).position, 0, 'local completion overrides route and cloud resume');
  assert.equal(p.confirmedPosition(11, 'paused', 12, 60, false), 12);
  assert.equal(p.confirmedPosition(11, 'completed', 2, 60, true), 60);
  assert.equal(p.confirmedPosition(11, 'prepared', 0, 60, false), null);
  assert.equal(p.confirmedPosition(0, 'playing', 12, 60, false), null);
  assert.equal(p.confirmedPosition(11, 'playing', NaN, 60, false), null);
  assert.equal(p.confirmedPosition(11, 'playing', -1, 60, false), null);
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
  vm.runInNewContext(ts.transpileModule(`class Harness { seekQueue_ = new PlaybackSeekQueue(); ${seekSource} } exports.Harness = Harness;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports: seekExports, setTimeout, logInfo() {}, ...load('utils/PlaybackTimeline'),
    ...load('services/PlaybackSeek', { '@kit.MediaKit': { media: { SeekMode: { SEEK_CLOSEST: 0, SEEK_PREV_SYNC: 1 } } } }),
    media: { SeekMode: { SEEK_CLOSEST: 0, SEEK_PREV_SYNC: 1 } } });
  const h = new seekExports.Harness();
  const savedPositions = [];
  Object.assign(h, { play: false, dur: 75, playbackResources_: { audioGain: 1 }, referenceSwitchGeneration: 0, rampAudio_() {}, sg_: false,
    cancelVideoSpeedSync() {}, cancelDelayHide() {}, delayMs_: async () => {},
    saveWatchHistory() { savedPositions.push(this.ct); },
    seekTrack: { state: 'paused', currentTime: 46000,
      seek(ms) { h.videoSeekPosition = ms / 1000; h.videoSeekResolve_(); }
    }
  });
  h.playbackResources_.video = h.seekTrack;
  await h.seek(13, false);
  assert.equal(h.playbackResources_.video.currentTime, 46000, 'native currentTime is intentionally stale');
  assert.equal(savedPositions[0], 13, 'upload and local save use the acknowledged seek position');
  h.playbackResources_.video.currentTime = 75000;
  h.playbackResources_.video.state = 'completed';
  h.referencePlaybackCompleted = true;
  await h.seek(0, false);
  assert.equal(savedPositions[1], 0, 'replay must not upload the old duration as the new position');
  assert.equal(h.referencePlaybackCompleted, false);
  h.play = true;
  h.playbackResources_.video.pause = async () => { h.playbackResources_.video.state = 'paused'; };
  let eofPlayCalls = 0;
  h.playbackResources_.video.play = async () => { eofPlayCalls++; };
  h.playbackResources_.video.seek = () => {
    h.playbackResources_.video.state = 'completed';
    h.referencePlaybackCompleted = true;
    h.play = false;
    h.videoSeekResolve_();
  };
  await h.seek(75, false, true);
  assert.equal(eofPlayCalls, 0, 'seeking to EOF must not restart the player');
  assert.equal(h.play, false);
  assert.equal(h.referencePlaybackCompleted, true);
  h.play = false;
  h.playbackResources_.video.state = 'paused';
  h.playbackResources_.video.currentTime = 46000;
  h.playbackResources_.video.seek = () => {}; // native callback misses the wait budget
  const beforeTimeout = savedPositions.length;
  await h.seek(13, false, true);
  assert.equal(savedPositions.length, beforeTimeout, 'seek timeout cannot upload the stale currentTime');
  assert.equal(h.seekProgressPending, true, 'a late native confirmation must remain eligible for saving');
  const seekCallback = page.slice(page.indexOf("    this.playbackResources_.video.on('seekDone',"),
    page.indexOf('    // ⭐ 注册startRenderFrame'));
  const callbackExports = {};
  h.playbackResources_.video.on = (name, callback) => { h[name] = callback; };
  vm.runInNewContext(ts.transpileModule(`exports.register = function() { ${seekCallback} };`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports: callbackExports, player: h.playbackResources_.video, generation: 0, logInfo() {} });
  callbackExports.register.call(h);
  h.seekDone(13000);
  assert.equal(savedPositions.at(-1), 13, 'late seekDone must upload the confirmed position');
  assert.equal(h.seekProgressPending, false);
  const historyMethod = page.slice(page.indexOf('  private saveWatchHistory(force: boolean = false): void {'),
    page.indexOf('  private saveLocalPlaybackProgress('));
  const localStart = page.indexOf('  private saveLocalPlaybackProgress(');
  const localMethod = page.slice(localStart, page.indexOf('\n  /**', localStart));
  const completionExports = {}, completedUploads = [];
  const reporter = fs.readFileSync('entry/src/main/ets/services/PlaybackProgressReporter.ets', 'utf8')
    .replace(/^import .*$/gm, '').replace(/^export /gm, '');
  let now = 10000;
  vm.runInNewContext(ts.transpileModule(`${reporter}\nclass CompletionHarness {
    ${historyMethod} ${localMethod}
  } exports.CompletionHarness = CompletionHarness; exports.Reporter = PlaybackProgressReporter;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports: completionExports, PlaybackProgress: p, MIN_HEARTBEAT_PROGRESS_SEC: 5,
    MIN_FINAL_PROGRESS_SEC: 1,
    WatchHistoryItem: class {}, logInfo() {}, logWarn() {}, logError() {}, Date: { now: () => now },
    WatchHistoryHelper: { getInstance: () => ({ setCookie() {}, saveWatchRecord: item => completedUploads.push(item) }) },
    AppStorage: { get: key => key === 'biliCookie' ? 'test' : completionStorage.get(key),
      set: (key, value) => completionStorage.set(key, value) }
  });
  const completedPage = new completionExports.CompletionHarness();
  completedPage.playbackProgressReporter_ = new completionExports.Reporter();
  Object.assign(completedPage, { vi: { bvid: 'BVtest', cid: 11 }, vd: { aid: 1 }, detailIsCurrentVideo: () => true,
    playbackResources_: { video: { state: 'completed' } }, ct: 75, dur: 75, progressFloor_: 0,
    sk_: true, sg_: true, seekProgressPending: true, referencePlaybackCompleted: true });
  completedPage.saveWatchHistory();
  assert.equal(completedUploads[0].playProgress, -1, 'native completion bypasses seek upload guards');
  assert.equal(p.readLocal(p.storageKey('BVtest', 11, 0)).completed, true,
    'completion during seek must be persisted before a process restart');
  now += 100;
  completedPage.saveWatchHistory();
  assert.equal(completedUploads.length, 1, 'early duplicate cloud pushes are throttled');
  // 同一位置 1.5s 内的重复强制保存也会被去重（onPageHide + aboutToDisappear 只发一次），
  // 想验证「force 绕过 3s 节流」就得先把时间推过去重窗口。
  now += 2000;
  completedPage.saveWatchHistory(true);
  assert.equal(completedUploads.length, 2, 'forced cloud push bypasses the throttle');
  const events = [];
  const first = completedPage.playbackProgressReporter_.enqueuePgc(async () => { events.push(1); throw Error('failed'); });
  const second = completedPage.playbackProgressReporter_.enqueuePgc(async () => { events.push(2); });
  await assert.rejects(first, /failed/);
  await second;
  assert.deepEqual(events, [1, 2], 'a failed PGC upload cannot poison the ordered queue');
  const pgc = new completionExports.Reporter();
  let current = true;
  const request = {
    cookie: 'test', epId: 21, watchTime: 4.9, minimumProgress: 5,
    current: () => current, ensureContext: async () => true,
    record: progress => ({ aid: 31, cid: 41, epId: 21, seasonId: 51, progress })
  };
  await pgc.reportPgc(request);
  assert.equal(completedUploads.length, 2, 'short PGC playback cannot overwrite season history');
  await pgc.reportPgc({ ...request, watchTime: -1 });
  assert.equal(completedUploads.at(-1).playProgress, -1);
  assert.equal(completedUploads.at(-1).epId, 21);
  await pgc.reportPgc({ ...request, watchTime: 20, ensureContext: async () => {
    current = false;
    return true;
  } });
  assert.equal(completedUploads.length, 3, 'switching during season lookup prevents a stale upload');
  completedPage.detailIsCurrentVideo = () => false;
  completedPage.vi = { bvid: 'BVnext', cid: 72, title: 'Next video' };
  completedPage.aidFromParams_ = 81;
  completedPage.saveWatchHistory(true);
  assert.equal(completedUploads.at(-1).aid, 81, 'a collection switch uses the current route identity');
  assert.equal(completedUploads.at(-1).cid, 72);
  console.log('PASS: resume, backwards seeks, replay, part/account isolation, buffering, ordered cloud updates, completion, zero guard');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
