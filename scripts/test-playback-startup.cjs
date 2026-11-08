const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
function load(file, imports = {}) {
  const context = vm.createContext({ exports: {}, console, setTimeout, clearTimeout, AppStorage: { get() { return ''; } },
    require: (name) => imports[name] || (name === '@kit.PerformanceAnalysisKit' ? { hilog: { debug() {}, info() {}, warn() {} } } : null) || (name.includes('PlaybackStartup') ? { PlaybackStartup: { span() { return null; }, navigation() {} } } : {}) });
  const source = fs.readFileSync(path.join(root, file + '.ets'), 'utf8');
  vm.runInContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, context);
  return context;
}
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const empty = { durlUrl: '', dashVideoUrl: '', dashAudioUrl: '', actualQn: 0,
  acceptQuality: [], acceptDescription: [], dashInfo: null };
const full = { ...empty, dashVideoUrl: 'video', dashAudioUrl: 'audio', actualQn: 116 };
async function main() {
  const helpers = load('utils/PlaybackRequests').exports;
  const slow = deferred();
  const snapshot = await helpers.firstPreferredResults([slow.promise, Promise.resolve(full)], empty, x => x.actualQn >= 116);
  assert.equal(snapshot[1].dashAudioUrl, 'audio');
  slow.resolve(full);
  await Promise.resolve();
  assert.equal(snapshot[0].actualQn, 0, 'late replies cannot mutate the returned snapshot');
  const pendingHigh = deferred();
  let selected = false;
  const waiting = helpers.firstPreferredResults([Promise.resolve({ ...full, actualQn: 64 }), pendingHigh.promise], empty,
    x => x.actualQn >= 116).then(x => { selected = true; return x; });
  await new Promise(r => setTimeout(r, 0));
  assert.equal(selected, false, 'a downgraded reply must not win before the requested quality');
  pendingHigh.resolve(full);
  assert.equal((await waiting)[1].actualQn, 116);
  const failed = await helpers.firstPreferredResults([Promise.reject(new Error('offline'))], empty, () => false);
  assert.equal(failed[0].actualQn, 0);
  const api = load('api/BilibiliApi', {
    '../utils/CredentialStore': { loginCredentialsReady: () => null },
    '../utils/PlaybackRequests': helpers,
    '../utils/PlaybackDeadline': { PlaybackDeadline: require('./playback-deadline-test-helper.cjs')() },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
  });
  let probes = 0;
  let next = deferred();
  api.tryFetchPlayUrl = async () => { probes++; return next.promise; };
  api.tryFetchPlayUrlMobile = async () => { probes++; return next.promise; };
  const a = api.exports.getVideoPlayUrl('BVtest', 1, 116);
  const b = api.exports.getVideoPlayUrl('BVtest', 1, 116);
  next.resolve(full);
  assert.equal((await a).url, 'video');
  await b;
  assert.equal(probes, 2, 'simultaneous consumers must share one set of probes');
  await api.exports.getVideoPlayUrl('BVtest', 1, 116);
  assert.equal(probes, 2, 'completed result is cached');
  next = deferred();
  const old = api.exports.getVideoPlayUrl('BVstale', 2, 116);
  api.exports.invalidatePlayUrlCache('BVstale', 2, 116);
  next.resolve(full);
  await old;
  next = deferred();
  const refreshed = api.exports.getVideoPlayUrl('BVstale', 2, 116);
  assert.equal(probes, 6, 'invalidated pending replies must not repopulate cache');
  next.resolve(full);
  await refreshed;
  api.getVideoDetail = async () => ({ bvid: 'BVprefetch', cid: 3 });
  next = deferred();
  api.exports.prefetchVideoPlayback('3', 0, 116);
  await new Promise(r => setTimeout(r, 0));
  const consumer = api.exports.getVideoPlayUrl('BVprefetch', 3, 116);
  assert.equal(probes, 8, 'click prefetch and the player must share the normalized BV/CID request');
  next.resolve(full);
  await consumer;
  // Each request carries its own progress even if a different video responds concurrently.
  api.tryFetchPlayUrlMobile = async () => empty;
  api.tryFetchPlayUrl = async (_bv, cid, _qn, _fnval, progress) => {
    await Promise.resolve(); progress.ms = cid * 1000; return full;
  };
  const results = await Promise.all([api.exports.getVideoPlayUrl('BVone', 11, 116), api.exports.getVideoPlayUrl('BVtwo', 22, 116)]);
  assert.equal(results[0].lastPlayTimeMs, 11000);
  assert.equal(results[1].lastPlayTimeMs, 22000);
  // A known BV/CID must start playback requests before the detail request completes.
  const direct = load('api/BilibiliApi', {
    '../utils/CredentialStore': { loginCredentialsReady: () => null },
    '../utils/PlaybackRequests': helpers,
    '../utils/PlaybackDeadline': { PlaybackDeadline: require('./playback-deadline-test-helper.cjs')() },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
  });
  const detailGate = deferred();
  let directProbes = 0;
  direct.getVideoDetail = () => detailGate.promise;
  direct.tryFetchPlayUrl = direct.tryFetchPlayUrlMobile = async () => { directProbes++; return full; };
  direct.exports.prefetchVideoPlayback('BVfast', 7, 116);
  assert.equal(directProbes, 2, 'known BV/CID does not wait for detail');
  assert.equal((await direct.exports.getVideoPlayUrl('BVfast', 7, 116)).url, 'video');
  assert.equal(directProbes, 2, 'navigation shares the prefetch already in progress');
  detailGate.resolve({ bvid: 'BVfast', cid: 7 });
  const avDetail = deferred();
  direct.getVideoDetail = () => avDetail.promise;
  const avSource = await direct.exports.getVideoPlayUrl('12345', 77, 116);
  assert.equal(avSource.url, 'video', 'known AV/CID starts with detail unresolved');
  const beforeAlias = directProbes;
  await direct.exports.getVideoPlayUrl('BValias', 77, 116);
  assert.equal(directProbes, beforeAlias, 'AV/BV entry points reuse the same CID source');
  await direct.exports.getVideoPlayUrl('BValias', 77, 116, 0);
  assert.equal(directProbes, beforeAlias + 2, 'forced refresh bypasses compatible alias cache');
  avDetail.resolve({ bvid: 'BValias', cid: 77 });

  api.tryFetchPlayUrlMobile = async () => ({ ...full, route: 'app-hd' });
  api.tryFetchPlayUrl = async () => empty;
  const appResult = await api.exports.getVideoPlayUrl('BVappHeaders', 9, 116);
  assert.match(appResult.mediaUserAgent, /BiliDroid/);
  assert.equal(appResult.mediaReferer, '', 'App CDN policy survives route selection and cache publication');
  console.log('PASS: early selection, quality preservation, errors, request sharing, invalidation, isolated resume points');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
