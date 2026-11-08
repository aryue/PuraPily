const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(root + 'utils/PlaybackHdrUi.ts', 'utf8')
  .replace(/^import .*;\s*$/gm, '').replace(/export /g, '');
let deny = false, calls = [];
const context = {
  deviceInfo: { sdkApiVersion: 24 },
  uiEffect: { createFilter: () => ({ hdrBrightnessRatio: ratio => {
    if (deny) throw new Error('permission denied');
    calls.push(ratio); return { ratio };
  } }) }, console: { warn() {} }
};
vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText, context);
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
