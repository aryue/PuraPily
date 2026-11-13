const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
let metered = false, refresh, requests = 0;
const warmed = [], settings = new Map(), prefixes = new Set();
const imports = {
  '../utils/NetworkGate': { NetworkGate: { allowsBoundedPrefix: () => !metered } },
  '../api/BilibiliApi': { getVideoPlayUrl: async id => { requests++; return { url: 'test', id }; } },
  './IjkPrewarm': { IjkPrewarm: { warm: source => {
    const key = [settings.get('biliCookie'), source.id].join(':');
    if (!prefixes.has(key)) warmed.push(source.id);
    prefixes.add(key);
    return true;
  } } },
  './IjkWarmPool': { IjkWarmPool: { get: () => ({
    capacity: () => 1,
    warm: async cid => assert.ok(prefixes.has([settings.get('biliCookie'), 'BVtest' + cid].join(':'))),
  }) } },
  '../utils/PlaybackProgress': { PlaybackProgress: { prewarmPosition: () => 0 } },
  '@kit.PerformanceAnalysisKit': { hilog: { debug() {} } }
};
const context = vm.createContext({ exports: {}, require: name => imports[name] || {},
  AppStorage: { get: key => settings.get(key) },
  setInterval: fn => { refresh = fn; return 1; }, clearInterval() {} });
vm.runInContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/PlaybackListPrefetch.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const tick = () => new Promise(setImmediate);
(async () => {
  const list = new context.exports.PlaybackListPrefetch();
  const items = [1, 2, 3, 4].map(cid => ({ id: 'BVtest' + cid, cid }));
  list.update(items, 80, 0);
  await tick();
  assert.deepEqual(warmed, ['BVtest1', 'BVtest2'], 'only two visible candidates may read media');
  refresh(); await tick();
  assert.equal(warmed.length, 2, 'idle address refresh must not renew media prefixes');
  list.update(items, 80, 1); await tick();
  assert.deepEqual(warmed, ['BVtest1', 'BVtest2', 'BVtest3'], 'scrolling can prepare the newly visible candidate');
  list.pause(); list.update(items, 80, 0); await tick();
  assert.equal(warmed.length, 3, 'returning to an idle list does not repeat previous speculative reads');
  const before = requests;
  metered = true; list.update(items, 80, 2); await tick();
  assert.equal(requests, before, 'a route change to metered stops speculative requests');
  metered = false; settings.set('biliCookie', 'new-account');
  list.update(items, 80, 0); await tick();
  assert.equal(warmed.length, 5, 'new credentials must not reuse an old account preparation decision');
  list.pause();
  console.log('Bounded visible prefix scheduling passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
