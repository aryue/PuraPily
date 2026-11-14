// Exercise actual CompileArkTS artifacts: list scheduling and foreground cache reuse.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const tick = () => new Promise(resolve => setImmediate(resolve));
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
function compiled(file, imports, globals = {}) {
  imports['../utils/PlaybackDeadline'] ??= { PlaybackDeadline: require('./playback-deadline-test-helper.cjs')() };
  imports['@ohos:hilog'] ??= { default: { debug() {}, info() {}, warn() {}, error() {} } };
  const context = { exports: {}, console, setTimeout, clearTimeout, ...globals, require: name => {
    const normalized = name.replace(/^@normalized:.*entry\/src\/main\/ets\//, '../').replace(/&$/, '');
    return imports[name] || imports[normalized] || {};
  } };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(base + file + '.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context;
}
function fixture() {
  let credential = 'account-a', enabled = true;
  const timers = new Set(), details = [], urls = [], logs = [];
  const context = compiled('services/PlaybackListPrefetch', {
    '../utils/NetworkGate': { NetworkGate: { allowsBoundedPrefix: () => true } },
    '../utils/PlaybackProgress': { PlaybackProgress: { prewarmPosition: () => 0 } },
    '../services/IjkPrewarm': { IjkPrewarm: { warm() {} } },
    '../services/IjkWarmPool': { IjkWarmPool: { get: () => ({ capacity: () => 1, warm: async () => {} }) } },
    '@ohos:hilog': { default: { debug(...args) {
      if (String(args[2]).startsWith('ready ')) logs.push(args);
    } } },
    '../api/BilibiliApi': {
      getVideoDetail(id) { const job = { id, ...gate() }; details.push(job); return job.promise; },
      getVideoPlayUrl(id, cid, qn, maxAge) { const job = { id, cid, qn, maxAge, ...gate() }; urls.push(job); return job.promise; }
    }
  }, { AppStorage: { get: () => credential }, Date,
    setInterval(fn) { timers.add(fn); return fn; }, clearInterval(fn) { timers.delete(fn); } });
  const queue = new context.exports.PlaybackListPrefetch(() => enabled);
  return { queue, timers, details, urls, logs, account(value) { credential = value; }, hidden() { enabled = false; } };
}
const item = (id, cid = 1) => ({ id, cid, pgcEpId: 0, pgcSeasonId: 0 });
const ok = { url: 'signed-media', actualQn: 116 };
(async () => {
  {
    const f = fixture();
    const items = ['BVone', 'BVtwo', 'BVthree', 'BVfour', 'BVfive'].map(id => item(id));
    f.queue.update([...items, items[0], { ...item('BVpgc'), pgcEpId: 4 }], 116);
    assert.equal(f.details.length, 0, 'known CID goes straight to address extraction');
    assert.equal(f.urls.length, 2, 'maximum two list entries at a time');
    f.queue.update(items, 116);
    assert.equal(f.urls.length, 2, 'repeated list publication shares in-progress work');
    for (let i = 0; i < 5; i++) {
      f.urls[i].resolve(ok); await tick();
      assert.ok(f.urls.length <= Math.min(5, i + 3));
    }
    assert.equal(f.urls.length, 5, 'all entries in a small list are prepared, not just a neighbour');
    assert.equal(f.timers.size, 0);
    f.queue.update(items, 116); assert.equal(f.urls.length, 5);
    assert.ok(f.urls.every(x => x.maxAge === 40000));
    f.queue.pause();
    assert.equal(f.urls.length, 5, 'hidden pages start no remaining queued requests');
    assert.equal(f.timers.size, 0);
  }
  {
    const f = fixture();
    f.queue.update([item('123', 0)], 116);
    assert.equal(f.details.length, 1); assert.equal(f.urls.length, 0);
    f.queue.pause(); f.details[0].resolve({ bvid: 'BVresolved', cid: 9 }); await tick();
    assert.equal(f.urls.length, 0, 'exit during detail lookup cannot launch late address extraction');
    f.queue.update([item('123', 0)], 116);
    f.details[1].resolve({ bvid: 'BVresolved', cid: 9 }); await tick();
    assert.equal(f.urls[0].id, 'BVresolved'); assert.equal(f.urls[0].cid, 9);
    f.urls[0].resolve(ok); await tick(); f.queue.pause();
  }
  {
    const f = fixture();
    f.queue.update([item('BVone'), item('BVtwo'), item('BVthree')], 116);
    f.account('account-b'); f.queue.update([item('BVone')], 80);
    f.urls[0].resolve(ok); await tick();
    assert.equal(f.urls.length, 3); assert.equal(f.urls[2].qn, 80);
    assert.equal(f.logs.length, 0, 'old account/quality completions do not publish success');
    f.urls[1].resolve(ok); f.urls[2].resolve({ url: 'new-session', actualQn: 80 }); await tick();
    assert.equal(f.logs.length, 1);
    assert.equal(f.timers.size, 0);
  }
  {
    const f = fixture();
    f.queue.update([item('BVone'), item('BVtwo'), item('BVthree')], 116);
    f.hidden(); f.urls[0].resolve(ok); f.urls[1].resolve(ok); await tick();
    assert.equal(f.urls.length, 2, 'hidden owner blocks the next task even if the component watch is frozen');
    assert.equal(f.timers.size, 0);
  }
  {
    let credential = 'a', clock = 1000, probes = 0, result = gate();
    const helper = compiled('utils/PlaybackRequests', {}).exports;
    const api = compiled('api/BilibiliApi', {
      '../utils/CredentialStore': { loginCredentialsReady: () => null },
      '../utils/PlaybackRequests': helper,
      '../utils/PlaybackStartup': { PlaybackStartup: { span: () => null } },
      '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
    }, { AppStorage: { get: () => credential }, Date: class extends Date { static now() { return clock; } }, setTimeout, clearTimeout });
    api.tryFetchPlayUrl = api.tryFetchPlayUrlMobile = () => { probes++; return result.promise; };
    const response = url => ({ durlUrl: url, dashVideoUrl: '', dashAudioUrl: '', actualQn: 116,
      acceptQuality: [], acceptDescription: [], dashInfo: null });
    const background = api.exports.getVideoPlayUrl('BVone', 1, 116, 40000);
    result.resolve(response('first')); await background;
    assert.equal((await api.exports.getVideoPlayUrl('BVone', 1, 116)).url, 'first');
    assert.equal(probes, 2, 'foreground consumes the extracted address without HTTP');
    clock += 41000; result = gate();
    const renewal = api.exports.getVideoPlayUrl('BVone', 1, 116, 40000);
    assert.equal(probes, 4, 'background renewal starts before foreground TTL expires');
    assert.equal((await api.exports.getVideoPlayUrl('BVone', 1, 116)).url, 'first');
    result.resolve(response('renewed')); await renewal;
    assert.equal((await api.exports.getVideoPlayUrl('BVone', 1, 116)).url, 'renewed');
    result = gate();
    const stale = api.exports.getVideoPlayUrl('BVstale', 2, 116);
    credential = 'b'; result.resolve(response('old-account'));
    await assert.rejects(stale, /session changed/);
    result = gate(); const current = api.exports.getVideoPlayUrl('BVone', 1, 116);
    assert.equal(probes, 8, 'new account cannot consume the previous signed-address cache');
    result.resolve(response('current-account')); assert.equal((await current).url, 'current-account');
  }
  {
    let credential = '', probes = 0;
    const restore = gate();
    const helpers = compiled('utils/PlaybackRequests', {}).exports;
    const api = compiled('api/BilibiliApi', {
      '../utils/CredentialStore': { loginCredentialsReady: () => restore.promise },
      '../utils/PlaybackRequests': helpers,
      '../utils/PlaybackStartup': { PlaybackStartup: { span: () => null } },
      '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {} }
    }, { AppStorage: { get: () => credential }, setTimeout, clearTimeout });
    api.tryFetchPlayUrl = api.tryFetchPlayUrlMobile = async () => {
      probes++;
      return { durlUrl: 'restored-session', dashVideoUrl: '', dashAudioUrl: '', actualQn: 116,
        acceptQuality: [], acceptDescription: [], dashInfo: null };
    };
    const waiting = api.exports.getVideoPlayUrl('BVcold', 1, 116);
    await tick(); assert.equal(probes, 0, 'cold request waits for credential snapshot, not page rendering');
    credential = 'restored-account'; restore.resolve();
    assert.equal((await waiting).url, 'restored-session');
    assert.equal(probes, 2, 'restored account starts one shared probe group');
  }
  {
    const source = fs.readFileSync(base + 'pages/VideoPlayerPage.ts', 'utf8');
    const begin = source.indexOf('    private referencePrefetchPlaylistUrls(');
    const finish = source.indexOf('    private requestReferenceFeedPreview(', begin);
    assert.ok(begin >= 0 && finish > begin);
    const calls = [], context = { exports: {}, AppStorage: { get: () => 116 } };
    vm.runInNewContext(ts.transpileModule('export class Page {' + source.slice(begin, finish) + '}', {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, context);
    const page = new context.exports.Page();
    Object.assign(page, { referenceAlive: true, playerPageVisible: true, waitingForFirstFrame: false,
      isPgc_: false, referenceLayout: true, referencePreviewPreparing: true, referencePreviewSurfaceId: '',
      referenceFeedQueue: ['BVone', 'BVcurrent', 'BVtwo', 'BVthree'].map(id => item(id)),
      vi: { bvid: 'BVcurrent' }, preferredQn: 80,
      playbackListPrefetch: { update(items, qn) { calls.push({ ids: Array.from(items, x => x.id), qn }); }, pause() { calls.push('paused'); } } });
    page.referencePrefetchPlaylistUrls();
    assert.deepEqual(calls[0].ids, ['BVtwo', 'BVthree', 'BVone']);
    assert.equal(calls[0].qn, 80, 'feed keeps the current playback quality');
    page.referenceFeedQueue = []; page.relatedVideos = [item('BVrelated')];
    page.referencePrefetchPlaylistUrls(); assert.equal(calls[1].qn, 116, 'related-page navigation uses its default quality');
    page.waitingForFirstFrame = true; page.referencePrefetchPlaylistUrls(); assert.equal(calls[2], 'paused');
  }
  console.log('PASS: compiled list extraction, concurrency, whole small list, normalized IDs, expiry renewal, navigation reuse, cancellation and account/quality isolation');
})().catch(error => { console.error(error); process.exitCode = 1; });
