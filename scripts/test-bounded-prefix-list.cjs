const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
let metered = false, requests = 0, viewport;
const warmed = [], instances = [], settings = new Map();
const imports = {
  '../utils/NetworkGate': { NetworkGate: { allowsBoundedPrefix: () => !metered } },
  '../api/BilibiliApi': { getVideoPlayUrl: async id => { requests++; return { url: 'test', id }; } },
  './IjkPrewarm': { IjkPrewarm: { warm: source => {
    warmed.push(source.id);
    return true;
  } } },
  './IjkWarmPool': { IjkWarmPool: { get: () => ({
    capacity: () => 1,
    activateHomeScene() {},
    retainHomeTargets() {},
    warm: async cid => { instances.push(cid); },
  }) } },
  '../utils/PlaybackProgress': { PlaybackProgress: { prewarmPosition: () => 0 } },
  '@kit.PerformanceAnalysisKit': { hilog: { debug() {} } }
};
const context = vm.createContext({ exports: {}, require: name => imports[name] || {},
  AppStorage: { get: key => settings.get(key) },
  setInterval: () => assert.fail('idle home must not schedule polling'),
  setTimeout: fn => { viewport = fn; return 1; }, clearTimeout() {} });
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
  const idleRequests = requests;
  list.update(items, 80, 0); await tick();
  assert.equal(requests, idleRequests);
  assert.deepEqual(instances, [1], 'unchanged candidates must not rebuild an expired instance');
  assert.equal(warmed.length, 2, 'unchanged candidates must not renew media prefixes');
  list.update(items, 80, 1); await tick();
  assert.deepEqual(warmed, ['BVtest1', 'BVtest2', 'BVtest3'], 'scrolling can prepare the newly visible candidate');
  list.pause(); list.update(items, 80, 0); await tick();
  assert.deepEqual(instances, [1, 2, 1], 'a new home visit may warm again');
  assert.equal(warmed.length, 5);
  const before = requests;
  metered = true; list.update(items, 80, 2); await tick();
  assert.equal(requests, before, 'a route change to metered stops speculative requests');
  metered = false; settings.set('biliCookie', 'new-account');
  list.update(items, 80, 0); await tick();
  assert.equal(warmed.length, 7, 'new credentials must not reuse an old account preparation decision');
  list.pause();
  const home = new context.exports.PlaybackListPrefetch(() => true, () => 'home:popular');
  home.updateViewport(items.slice(0, 3).reverse(), items, 80);
  viewport(); await tick();
  assert.equal(instances.at(-1), 1, 'hash selection is independent of card order');
  home.updateViewport(items.slice(1), items, 80);
  viewport(); await tick();
  assert.equal(instances.at(-1), 4, 'newly visible cards get priority');
  const count = instances.length;
  home.updateViewport(items.slice(1), items, 80);
  viewport(); await tick();
  assert.equal(instances.length, count, 'an unchanged viewport does not rewarm');
  console.log('Bounded visible prefix scheduling passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
