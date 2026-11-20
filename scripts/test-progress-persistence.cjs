// 进度记录落库回归（2026-11-20）
//
// 用户反馈：看几十秒就退出 / 连刷滑走时，本地与云端「经常没记录」，重进从头播。
// 根因是两条通道共用同一组**瞬时状态**守卫（sk_ / sg_ / seekProgressPending /
// restoringProgress / referenceFeedPreparingMain）：
//   1) 其中任何一个没复位（典型：seek 没等到 seekDone，seekProgressPending 留 true），
//      这个视频之后整场本地和云端都不再写 —— 两条同时失效；
//   2) 页面销毁 / 切后台这两次「最后机会」走的是非 force 保存，会被 3 秒节流吞掉；
//   3) 起播瞬间 ct=0，若被写进库就把上一次的记录抹成 0（resume(0) ⇒ 从头播）。
//
// 本脚本锁住修复后的语义，防止以后为了「少发一个请求」把 force 收回去。
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const pagePath = path.join(root, 'pages/VideoPlayerPage.ets');

function load(file, imports = {}, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, file + '.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => imports[name] || {}, ...globals });
  return exports;
}

async function main() {
  const page = fs.readFileSync(pagePath, 'utf8');
  const storage = new Map();
  const { PlaybackProgress: p } = load('utils/PlaybackProgress', {}, {
    AppStorage: { get: key => key === 'biliCookie' ? 'DedeUserID=99; SESSDATA=x' : storage.get(key),
      set: (key, value) => storage.set(key, value) }
  });

  // ── 结构约束：两次「可能回不来」的节点必须 force ──────────────────────────────
  assert.ok(/this\.saveWatchHistory\(true\);\s*\n\s*this\.reportWatchBehavior\(\)/.test(page),
    'page destroy must force the final save (otherwise the 3s throttle can swallow it)');
  const hide = page.slice(page.indexOf('  onPageHide(): void {'), page.indexOf('  onAppBackgroundConfirmed(): void {'));
  assert.ok(hide.includes('this.saveWatchHistory(true)'),
    'page hide must anchor the last position before any early return');
  assert.ok(page.includes('seekPendingSince_'),
    'a seek that never confirms must have a timeout fallback');

  // ── 行为：真页面的 saveWatchHistory / saveLocalPlaybackProgress ───────────────
  const historyStart = page.indexOf('  private saveWatchHistory(');
  const localStart = page.indexOf('  private saveLocalPlaybackProgress(');
  assert.ok(historyStart > 0 && localStart > historyStart);
  const historyMethod = page.slice(historyStart, localStart);
  const localMethod = page.slice(localStart, page.indexOf('\n  /**', localStart));
  const reporter = fs.readFileSync(path.join(root, 'services/PlaybackProgressReporter.ets'), 'utf8')
    .replace(/^import .*$/gm, '').replace(/^export /gm, '');

  const uploads = [];
  const harnessExports = {};
  let now = 100000;
  vm.runInNewContext(ts.transpileModule(`${reporter}\nclass ProgressHarness {
    ${historyMethod} ${localMethod}
  } exports.Page = ProgressHarness; exports.Reporter = PlaybackProgressReporter;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports: harnessExports, PlaybackProgress: p, MIN_HEARTBEAT_PROGRESS_SEC: 5,
    MIN_FINAL_PROGRESS_SEC: 1,
    WatchHistoryItem: class {}, logInfo() {}, logWarn() {}, logError() {},
    Date: { now: () => now },
    WatchHistoryHelper: { getInstance: () => ({ setCookie() {}, saveWatchRecord: item => uploads.push(item) }) },
    AppStorage: { get: key => key === 'biliCookie' ? 'DedeUserID=99; SESSDATA=x' : storage.get(key),
      set: (key, value) => storage.set(key, value) }
  });

  function harness(over = {}) {
    now += 10000;   // 每次用例都错开 3s 节流窗口
    const h = new harnessExports.Page();
    h.playbackProgressReporter_ = new harnessExports.Reporter();
    Object.assign(h, {
      vi: { bvid: 'BVprog', cid: 42 }, vd: { aid: 7 }, detailIsCurrentVideo: () => true,
      playbackResources_: { video: { state: 'playing' } },
      ct: 120, dur: 600, aidFromParams_: 7, epId_: 0, seasonId_: 0, isPgc_: false,
      sk_: false, sg_: false, seekProgressPending: false, restoringProgress: false,
      referenceFeedPreparingMain: false, initialProgress_: 0, referencePlaybackCompleted: false,
      progressCommitted_: false, seekPendingSince_: -1, progressFloor_: 0, pendingResumeSeekMs_: 0
    }, over);
    return h;
  }

  const key = p.storageKey('BVprog', 42, 0);
  assert.equal(key.split(':')[0], '99', 'harness must write into the logged-in account partition');

  uploads.length = 0;
  harness({ sk_: true }).saveWatchHistory();
  assert.equal(uploads.length, 0, 'a non-critical sample during a drag must stay throttled');

  uploads.length = 0;
  harness({ sk_: true }).saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'leaving during a drag must still anchor the position');

  uploads.length = 0;
  harness({ restoringProgress: true }).saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'leaving while a resume seek is in flight must still report');

  // 恢复点还没落地：ct 仍是 0，任何 force 都不能把旧记录清零。
  p.saveLocal(key, 300, 600, false);
  uploads.length = 0;
  harness({ initialProgress_: 600, ct: 0 }).saveWatchHistory(true);
  assert.equal(uploads.length, 0, 'resume point not applied yet must not upload 0');
  assert.equal(p.readLocal(key).position, 300, 'resume point not applied yet must not erase local history');

  uploads.length = 0;
  harness({ initialProgress_: 600, ct: 610 }).saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'once playback passed the resume point, records must flow again');
  assert.equal(uploads[0].playProgress, 610);
  assert.equal(p.readLocal(key).position, 610);

  // 起播瞬间 ct=0（本会话还没产生有效进度）不能覆盖已有记录。
  uploads.length = 0;
  harness({ ct: 0, progressCommitted_: false }).saveWatchHistory(true);
  assert.equal(p.readLocal(key).position, 610, 'a zero position must not erase an existing record');

  // 用户主动 seek 回 0 重播：本会话已提交过，0 是真实意图，必须写。
  harness({ ct: 0, progressCommitted_: true }).saveWatchHistory(true);
  assert.equal(p.readLocal(key).position, 0, 'replay from zero must be persisted once the session committed');

  // 播完：走 -1，不受 5s 阈值与 seek 守卫影响。
  uploads.length = 0;
  harness({ ct: 600, dur: 600, referencePlaybackCompleted: true,
    playbackResources_: { video: { state: 'completed' } } }).saveWatchHistory(true);
  assert.equal(uploads.at(-1).playProgress, -1, 'completion must still report -1');

  // ── 看几秒就退出：最终保存必须落云端（阈值 5s 只约束周期心跳）────────────────
  const shortKey = p.storageKey('BVshort', 43, 0);
  uploads.length = 0;
  harness({ vi: { bvid: 'BVshort', cid: 43 }, ct: 3, dur: 300, progressFloor_: 0 }).saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'watching a few seconds then leaving must still create a history record');
  assert.equal(uploads[0].playProgress, 3);
  assert.equal(p.readLocal(shortKey).position, 3, 'the short watch must also be kept locally');

  // 同一位置 1.5s 内的重复 force 保存（onPageHide + aboutToDisappear）只发一次。
  uploads.length = 0;
  const twice = harness({ vi: { bvid: 'BVshort', cid: 43 }, ct: 4, dur: 300 });
  twice.saveWatchHistory(true);
  twice.saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'the same position must not be pushed twice within 1.5s');

  // ── 续播点未落地：预热实例没按续播点起播时，更小的 ct 不许改小记录 ────────────
  const floorKey = p.storageKey('BVfloor', 44, 0);
  p.saveLocal(floorKey, 300, 600, false);
  uploads.length = 0;
  harness({ vi: { bvid: 'BVfloor', cid: 44 }, ct: 2, dur: 600, progressCommitted_: true,
    progressFloor_: 300 }).saveWatchHistory(true);
  assert.equal(uploads.length, 0, 'a position below the pending resume point must not reach the server');
  assert.equal(p.readLocal(floorKey).position, 300, 'a position below the pending resume point must not shrink local history');

  // 用户主动拖动进度条会清掉下限：回拖到 5 分钟是真实意图，必须能写。
  uploads.length = 0;
  harness({ vi: { bvid: 'BVfloor', cid: 44 }, ct: 280, dur: 600, progressCommitted_: true,
    progressFloor_: 0 }).saveWatchHistory(true);
  assert.equal(uploads.length, 1, 'an explicit user seek must be allowed to move the record backwards');
  assert.equal(p.readLocal(floorKey).position, 280);

  // ── 云端兜底：没有 aid 时用 bvid 上报（详情未加载的入口不再整条丢）───────────
  const writes = [];
  const historyStorage = new Map();
  const { WatchHistoryHelper } = load('model/WatchHistoryHelper', {
    '../api/BilibiliHistoryApi': { BilibiliHistoryApi: { getInstance: () => ({
      async reportWatchProgress(aid, cid, progress, cookie, options) {
        writes.push({ aid, cid, progress, options });
        return true;
      }
    }) } },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
  }, { AppStorage: { get: k => historyStorage.get(k), set: (k, v) => historyStorage.set(k, v) } });
  const helper = WatchHistoryHelper.getInstance();
  helper.setCookie('acct');
  await helper.saveWatchRecord({ aid: 0, bvid: 'BVprog', cid: 42, epId: 0, seasonId: 0, playProgress: 88 });
  assert.equal(writes.length, 1, 'a missing aid must fall back to bvid instead of dropping the record');
  assert.equal(writes[0].options.bvid, 'BVprog');
  assert.equal(writes[0].progress, 88);
  await helper.saveWatchRecord({ aid: 0, bvid: '', cid: 42, epId: 0, seasonId: 0, playProgress: 88 });
  assert.equal(writes.length, 1, 'both identities missing must still be rejected');

  // 最终保存（allowShortProgress）放宽到 1s；周期心跳仍然守 5s。
  await helper.saveWatchRecord({ aid: 0, bvid: 'BVshort', cid: 43, epId: 0, seasonId: 0, playProgress: 3 }, true);
  assert.equal(writes.length, 2, 'the final save must accept a 3s position');
  await helper.saveWatchRecord({ aid: 0, bvid: 'BVshort', cid: 43, epId: 0, seasonId: 0, playProgress: 3 });
  assert.equal(writes.length, 2, 'periodic heartbeats must still ignore positions below 5s');

  console.log('PASS: forced commits on exit/background, transient-state bypass, zero protection, short-watch save, resume floor, bvid fallback');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
