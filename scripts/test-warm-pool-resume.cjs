// 预热池按续播点准备首帧：接管后不该再 seek（真机实测 seek + 等 seekDone 要多花 ~900ms 才出首帧）。
// 回归点：warm 传 startTimeMs、take 回传 resumeMs、列表阶段按当前历史进度算、播放页登记「续播点已预置」。
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const ROOT = 'entry/src/main/ets/';
const sessions = [];
class FakeSession {
  constructor(id, surfaceId, source, startTimeMs) {
    this.surfaceId = surfaceId;
    this.aspectRatio = 16 / 9;
    this.args = { id, surfaceId, source, startTimeMs };
    sessions.push(this);
  }
  async prepare() { return true; }
  take() { return { video: { id: this.args.id } }; }
  async release() { this.released = true; }
}

const storage = { playbackKernel: 'ijk', ijkWarmSlots: 1 };
function load(file, imports) {
  const context = vm.createContext({
    exports: {},
    require: name => imports[name],
    AppStorage: { get(key) { return storage[key]; }, setOrCreate(key, value) { storage[key] = value; } },
    setTimeout, clearTimeout, Date, Math, Promise
  });
  vm.runInContext(ts.transpileModule(fs.readFileSync(ROOT + file + '.ets', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

const { IjkWarmPool } = load('services/IjkWarmPool', {
  '@kit.MediaKit': { media: { VideoScaleType: { VIDEO_SCALE_TYPE_FIT: 0 } } },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {} } },
  '../api/BilibiliApi': {},
  './FeedPlaybackSession': { FeedPlaybackSession: FakeSession },
  './WarmSurfaceHost': { WarmSurfaceHost: { ready: () => true, get: () => 'warm-surface' } },
  './PlaybackFactory': { ijkPlaybackRequested: () => true },
  '../utils/NetworkGate': { NetworkGate: { isMetered: () => false } }
});

async function main() {
  const pool = IjkWarmPool.get();
  const source = { dash: { quality: 112 } };
  const resumeMs = 214613;
  delete storage.ijkWarmSlots;
  assert.equal(pool.capacity(), 1);
  storage.ijkWarmSlotsWifi = 5;
  storage.ijkWarmSlotsCellular = 2;
  assert.equal(pool.capacity(), 5);
  storage.networkMetered = true;
  assert.equal(pool.capacity(), 2);
  storage.networkMetered = false;
  storage.ijkWarmSlots = 1;

  // 列表阶段带续播点预热：FeedPlaybackSession 的 startTimeMs 必须原样带到 prepare 之前。
  await pool.warm(43143530580, source, resumeMs);
  assert.equal(sessions.length, 1, 'one warm instance prepared');
  assert.equal(sessions[0].args.startTimeMs, resumeMs, 'warm forwards resume position to the session');

  // 页面命中时拿得到这个位置，播完/清空后不残留。
  const took = pool.take(43143530580, 112);
  assert.ok(took, 'warm instance is taken');
  assert.equal(took.resumeMs, resumeMs, 'take reports the pre-positioned resume point');
  assert.equal(pool.take(43143530580, 112), null, 'slot emptied after take');

  // 不带续播点（没有历史记录）仍按 0 准备，保持旧行为。
  await pool.warm(43143530581, source);
  assert.equal(sessions[1].args.startTimeMs, 0, 'omitted resume defaults to the head of the stream');
  const head = pool.take(43143530581, 112);
  assert.equal(head.resumeMs, 0, 'take reports 0 for a from-start instance');

  // 负数 / 小数不能污染预置位置（每次先取走，避免槽位重建冷却把 warm 挡掉）。
  await pool.warm(43143530582, source, -5);
  assert.equal(sessions[2].args.startTimeMs, 0, 'negative resume is clamped');
  pool.take(43143530582, 112);
  await pool.warm(43143530583, source, 3456.7);
  assert.equal(sessions[3].args.startTimeMs, 3457, 'fractional resume is rounded');

  storage.ijkWarmSlots = 3;
  const pending = pool.warm(43143530584, source);
  const selected = pool.warm(43143530585, source);
  pool.cancelBuildingExcept(43143530585);
  await Promise.all([pending, selected]);
  assert.equal(sessions[4].released, true, 'unrelated in-flight preparation is cancelled');
  assert.ok(pool.take(43143530583, 112), 'ready home instance stays available');
  assert.ok(pool.take(43143530585, 112), 'selected in-flight instance can finish');
  pool.release();
  storage.ijkWarmSlots = 5;
  for (let cid = 1; cid <= 5; cid++) await pool.warm(cid, source);
  assert.equal(pool.readyCount(), 5);
  await pool.warm(6, source, 0, 'portrait');
  assert.equal(pool.readyCount(), 5);
  assert.equal(pool.take(1, 112), null, 'portrait evicts the oldest home slot');
  assert.ok(pool.reservePreview('feed'));
  await pool.warm(7, source, 0, 'feed');
  assert.equal(pool.readyCount(), 4, 'feed preview and pooled instances share the global limit');
  assert.equal(pool.take(2, 112), null);
  assert.equal(pool.take(3, 112), null);
  assert.ok(pool.take(6, 112), 'newer portrait slot stays available');
  pool.releaseScene('feed');
  pool.release();
  pool.activateHomeScene('home:recommend');
  await pool.warm(11, source, 0, 'home:recommend');
  const oldTab = pool.warm(12, source, 0, 'home:recommend');
  pool.activateHomeScene('home:popular');
  await oldTab;
  assert.equal(pool.take(12, 112), null, 'switching tabs cancels unfinished work');
  assert.ok(pool.take(11, 112), 'switching tabs retains completed work');
  await pool.warm(13, source, 0, 'home:popular');
  assert.ok(pool.take(13, 112), 'the active popular tab gets its own slots');
  storage.ijkWarmSlots = 1;
  await pool.warm(21, source, 0, 'home:popular');
  assert.ok(pool.reservePreview('feed-minimum'));
  await pool.warm(22, source, 0, 'feed-minimum');
  assert.equal(pool.readyCount(), 1);
  assert.equal(pool.take(21, 112), null, 'the two-slot global minimum evicts the older home slot');
  assert.ok(pool.take(22, 112), 'the second feed slot fits even when the home setting is one');
  pool.releaseScene('feed-minimum');
  console.log('Warm pool resume-position handoff passed');
}

// 列表卡片 id 可能用 aid、播放页存的 key 却是 bvid：必须能按 cid 兜底查到同一条进度。
const { PlaybackProgress } = load('utils/PlaybackProgress', {});
storage.playbackProgressV1 = JSON.stringify([
  { key: 'guest:BV18t411v7dC:43143530580', position: 214.613, duration: 3600, completed: false, updatedAt: 100 },
  { key: 'guest:BVother:43143530580', position: 12, duration: 3600, completed: false, updatedAt: 50 },
  { key: '123:BV18t411v7dC:43143530580', position: 999, duration: 3600, completed: false, updatedAt: 999 }
]);
assert.equal(PlaybackProgress.current('117522317773138', 43143530580), -1,
  'aid-based item id cannot match a bvid-based progress key');
assert.equal(Math.round(PlaybackProgress.currentByCid(43143530580) * 1000), 214613,
  'cid fallback finds the newest record of the current account');
assert.equal(PlaybackProgress.currentByCid(0), -1, 'cid=0 has no fallback record');
storage.playbackProgressV1 = '[]';

const prefetch = fs.readFileSync(ROOT + 'services/PlaybackListPrefetch.ets', 'utf8');
assert.match(prefetch, /Math\.round\(resumeSec \* 1000\)/,
  'list prefetch computes the resume position in milliseconds');
assert.match(prefetch, /\.warm\(item\.cid, source, resumeMs, scene\)/,
  'list prefetch forwards the resume position into the instance pool');
assert.match(prefetch, /PlaybackProgress\.prewarmPosition\(item\.id, item\.cid \|\| 0,/,
  'list prefetch falls back to cid when the exact progress key misses');

const page = fs.readFileSync(ROOT + 'pages/VideoPlayerPage.ets', 'utf8');
assert.match(page, /const warmResumeMs: number = ijkWarm\.resumeMs/,
  'warm takeover reads the pre-positioned resume point');
assert.match(page, /this\.startupResumePlayer_ = player;\s*\n\s*this\.startupResumeMs_ = warmResumeMs/,
  'matching resume point is registered so applyPreparedState skips the seek wait');
assert.match(page, /Math\.abs\(warmResumeMs - this\.initialProgress_ \* 1000\) < 100/,
  'mismatched resume point must fall back to the seek path');

const session = fs.readFileSync(ROOT + 'services/FeedPlaybackSession.ets', 'utf8');
assert.match(session, /setPlaybackRange\(this\.startTimeMs, -1\)/,
  'session still pre-positions IJK before prepare (the fast early-resume path)');

main().catch(e => { console.error(e); process.exit(1); });
