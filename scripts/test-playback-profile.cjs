// Verify the compiled instrumentation cannot mix overlapping sessions or log response secrets.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/PlaybackStartup.ts', 'utf8');
let now = 1000;
const records = [];
const evidence = [], faults = [], exported = [];
const hilog = { debug(domain, tag, format, record) { if (tag === 'PlaybackProfile') records.push(JSON.parse(record)); } };
const context = { exports: {}, Date: { now: () => now },
  require(name) {
    if (name === '@ohos:hilog') return { default: hilog };
    if (name.includes('ErrorLogCollector')) return { appendErrorLog(...args) { exported.push(args); } };
    if (name.includes('PlaybackEvidence')) return {
      recordPlaybackEvidence(text) { evidence.push(JSON.parse(text)); },
      triggerPlaybackEvidence(...args) { faults.push(args); }
    };
    throw new Error(name);
  } };
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
} }).outputText, context);
const { PlaybackStartup: P } = context.exports;
P.navigation();
const prefetch = P.span('prefetch');
now += 30;
const first = P.page();
first.mark('sample-position', 0, 60000);
assert.ok(evidence.some(e => e.event === 'sample-position'), 'normal samples reach the memory ring');
assert.ok(!exported.some(args => args[2].includes('sample-position')), 'normal samples avoid synchronous disk logging');
first.mark('stall-position', 0, 3000);
assert.equal(faults[0][0], first.id, 'a real stall event automatically triggers a correlated fault packet');
assert.equal(prefetch.parent, first.id, 'prefetch and page must share the click root');
P.navigation();
const second = P.page();
P.deactivate(first);
assert.equal(P.span('second-request').parent, second.id, 'old first-frame callback cannot disable a newer root');
P.finish(first, 'exit');
assert.equal(P.span('still-second').parent, second.id);
const request = P.span('http');
now += 25;
request.network({ responseCode: 206, result: 'secret-body', header: { Cookie: 'secret-cookie' },
  performanceTiming: { dnsTiming: 1, tcpTiming: 2, tlsTiming: 3, firstSendTiming: 4,
    firstReceiveTiming: 5, totalFinishTiming: 6, redirectTiming: 0,
    responseHeaderTiming: 7, responseBodyTiming: 8, totalTiming: 9, url: 'secret-url' } });
const response = records.at(-1);
assert.equal(response.ms, 25);
assert.deepEqual(Object.keys(response.network).sort(), ['dnsTiming', 'tcpTiming', 'tlsTiming',
  'firstSendTiming', 'firstReceiveTiming', 'totalFinishTiming', 'redirectTiming',
  'responseHeaderTiming', 'responseBodyTiming', 'totalTiming'].sort());
assert.ok(!JSON.stringify(records).includes('secret'));
request.once('first-sent', 0, 20); now += 10; request.once('first-sent', 0, 40);
assert.equal(records.filter(e => e.id === request.id && e.event === 'first-sent').length, 1);
request.end();
const length = records.length;
request.mark('late'); request.network({ responseCode: 200 }); request.end();
assert.equal(records.length, length, 'ended spans must ignore late callbacks');
P.deactivate(second);
assert.equal(P.span('background-after-frame'), null);
P.navigation(); now += 2100;
const expired = P.page();
assert.ok(!records.some(e => e.id === expired.id && e.event === 'click'), 'expired navigation cannot own a new page');
P.finish(expired, 'exit');
assert.equal(P.span('after-exit'), null);
console.log('PASS playback profile: correlation, stale sessions, native timing privacy, and late callbacks');
