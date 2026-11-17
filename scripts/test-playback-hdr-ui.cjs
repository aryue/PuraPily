const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(root + 'utils/PlaybackHdrUi.ts', 'utf8')
  .replace(/^import .*;\s*$/gm, '').replace(/export /g, '');
let deny = false, calls = [];
let brightnessListener, subscriptions = 0, removals = 0;
const context = {
  deviceInfo: { sdkApiVersion: 24, apiAvailable(version) { return this.sdkApiVersion >= version; } },
  display: {
    getDefaultDisplaySync: () => ({ id: 7 }),
    getBrightnessInfo: () => ({ currentHeadroom: 2.23, sdrNits: 100 }),
    on(event, callback) { assert.equal(event, 'brightnessInfoChange'); brightnessListener = callback; subscriptions++; },
    off(event, callback) { assert.equal(event, 'brightnessInfoChange'); assert.equal(callback, brightnessListener); removals++; }
  },
  uiEffect: { createFilter: () => ({ hdrBrightnessRatio: ratio => {
    if (deny) throw new Error('permission denied');
    calls.push(ratio); return { ratio };
  } }) }, console: { warn() {} }
};
vm.runInNewContext(ts.transpileModule(source + '\nglobalThis.Headroom = PlaybackHdrHeadroom;', {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText, context);
const ratio = context.playbackHdrUiRatio, filter = context.playbackHdrUiFilter;
for (const q of [16, 32, 64, 80, 112, 116, 120, 127]) assert.equal(ratio(q, 8), 1, 'SDR never enables HDR UI');
for (const q of [125, 126]) {
  for (const h of [NaN, Infinity, -1, 0, 1]) assert.equal(ratio(q, h), 1);
  assert.equal(ratio(q, 1.8), 1.8);
  assert.equal(ratio(q, 3), 3);
  assert.equal(ratio(q, 12), 4, 'limits glare at high headroom');
}
assert.equal(filter(1), undefined); assert.equal(filter(NaN), undefined);
assert.equal(calls.length, 0, 'SDR does not even construct an HDR effect');
context.deviceInfo.sdkApiVersion = 23; assert.equal(filter(3), undefined); assert.equal(calls.length, 0);
context.deviceInfo.sdkApiVersion = 24;
const first = filter(2); assert.equal(first.ratio, 2);
assert.equal(filter(2), first, 'reuse unchanged effect');
assert.equal(calls.length, 1);
assert.equal(filter(3).ratio, 3, 'reacts to display brightness change');
deny = true; assert.equal(filter(4), undefined, 'permission failure leaves usable SDR controls');
assert.equal(filter(1), undefined, 'leaving HDR removes the effect');
const headroom = new context.Headroom(), brightness = [];
headroom.start((value, nits) => brightness.push([value, nits]));
headroom.start(() => assert.fail('duplicate subscription'));
brightnessListener(8, { currentHeadroom: 3, sdrNits: 90 });
brightnessListener(7, { currentHeadroom: 2.24, sdrNits: 110 });
brightnessListener(7, { currentHeadroom: 2.27, sdrNits: 120 });
brightnessListener(7, { currentHeadroom: 8, sdrNits: 130 });
headroom.stop(); headroom.stop();
brightnessListener(7, { currentHeadroom: 1, sdrNits: 140 });
assert.deepEqual(brightness, [[2, 100], [2.25, 120], [4, 130]]);
assert.equal(subscriptions, 1); assert.equal(removals, 1);
const player = fs.readFileSync(root + 'pages/VideoPlayerPage.ts', 'utf8');
const group = player.match(/Stack\.renderGroup\((this\.qn !== 125[\s\S]*?)\);/);
assert.ok(group, 'compiled player contains HDR-aware group-cache policy');
vm.runInNewContext('globalThis.useGroup = function() { return ' + group[1] + '; }', context);
for (const qn of [125, 126]) {
  assert.equal(context.useGroup.call({ qn, referencePortraitFeedActive: () => false, referenceFeedComments: false }), false,
    'HDR playback controls bypass the shared offscreen cache');
}
assert.equal(context.useGroup.call({ qn: 120, referencePortraitFeedActive: () => false, referenceFeedComments: false }), true);
console.log('PASS: compiled HDR UI quality gating, display headroom, glare ceiling, effect reuse, API and permission fallback');
