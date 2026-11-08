const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
let storage = {};
function load(file, imports) {
  const context = vm.createContext({ exports: {}, require: name => imports[name],
    AppStorage: { get(key) { return storage[key]; } }, setTimeout, clearTimeout, setInterval, clearInterval });
  vm.runInContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/' + file + '.ets', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
let handle = { netId: 1 }, caps = { bearerTypes: [1], networkCap: [11] }, throws = false, policyMetered = false;
const { NetworkGate } = load('utils/NetworkGate', { '@kit.PerformanceAnalysisKit': { hilog: { info() {} } }, '@kit.NetworkKit': { connection: {
  NetBearType: { BEARER_WIFI: 1, BEARER_ETHERNET: 3, BEARER_CELLULAR: 0 },
  isDefaultNetMeteredSync: () => policyMetered,
  getDefaultNetSync() { if (throws) throw Error('unavailable'); return handle; },
  getNetCapabilitiesSync() { return caps; }
} } });
assert.equal(NetworkGate.isMetered(), false);
assert.equal(NetworkGate.allowsBoundedPrefix(), true);
caps = { bearerTypes: [1], networkCap: [] };
assert.equal(NetworkGate.isMetered(), false, 'Wi-Fi with explicit unmetered policy works without NOT_METERED bit');
policyMetered = true;
assert.equal(NetworkGate.allowsBoundedPrefix(), true, 'user-approved metered Wi-Fi permits only bounded prefixes');
assert.equal(NetworkGate.isMetered(), true, 'switching away from unmetered must take effect immediately');
policyMetered = false;
caps = { bearerTypes: [0] };
assert.equal(NetworkGate.allowsBoundedPrefix(), false, 'cellular is denied by default');
assert.equal(NetworkGate.isMetered(), true, 'cellular is metered by default, including unmetered plans');
// Settings toggle / --ps override: cellular passes only while cellularPrefetch is on, and can be turned off live.
storage = { cellularPrefetch: true };
assert.equal(NetworkGate.allowsBoundedPrefix(), true, 'cellularPrefetch on permits bounded prefixes on cellular');
assert.equal(NetworkGate.isMetered(), false, 'cellularPrefetch on also unlocks decoder/neighbour experiments');
caps = {};
assert.equal(NetworkGate.allowsBoundedPrefix(), false, 'unknown bearers still deny bounded prefixes');
assert.equal(NetworkGate.isMetered(), true, 'unknown bearers still deny unbounded reads');
storage = {};
caps = { bearerTypes: [0] };
assert.equal(NetworkGate.allowsBoundedPrefix(), false, 'turning the flag off restores cellular denial immediately');
assert.equal(NetworkGate.isMetered(), true, 'turning the flag off restores metered denial immediately');
caps = {};
assert.equal(NetworkGate.isMetered(), true, 'unknown capabilities deny background downloads');
handle = { netId: 0 };
assert.equal(NetworkGate.isMetered(), true);
throws = true;
assert.equal(NetworkGate.allowsBoundedPrefix(), false, 'unknown state denies all speculative media');
assert.equal(NetworkGate.isMetered(), true, 'query failure must never grant unmetered permission');
let requests = 0;
const { PlaybackListPrefetch } = load('services/PlaybackListPrefetch', {
  '../utils/NetworkGate': { NetworkGate },
  '../api/BilibiliApi': { getVideoDetail() { requests++; }, getVideoPlayUrl() { requests++; } },
  '@kit.PerformanceAnalysisKit': { hilog: {} }, './IjkPrewarm': {}, './IjkWarmPool': {}
});
new PlaybackListPrefetch().update([{ id: 'BVtest', cid: 123 }], 80);
assert.equal(requests, 0, 'metered/unknown network must not start speculative list requests');
console.log('Metered playback guards passed');
