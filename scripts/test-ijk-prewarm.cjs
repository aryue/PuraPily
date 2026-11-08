const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const settings = new Map([['playbackKernel', 'ijk']]);
let metered = false;
const calls = [];
let fail = false;
const context = vm.createContext({
  exports: {}, AppStorage: { get: key => settings.get(key) },
  require: name => {
    if (name.includes('NetworkGate')) return { NetworkGate: { allowsBoundedPrefix: () => !metered } };
    if (name === 'libpurapily_ijk.so') return { default: { prewarmUrl(...args) {
      calls.push(args);
      if (fail) throw new Error('unavailable');
      return 1;
    } } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    if (name.includes('DashQuality')) return { selectDashVideo: streams => streams[0] };
    return {};
  }
});
const source = fs.readFileSync('entry/src/main/ets/services/IjkPrewarm.ets', 'utf8');
vm.runInContext(ts.transpileModule(source, { compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
} }).outputText, context);
const warm = context.exports.IjkPrewarm.warm;
const result = { dash: { quality: 80, videoStreams: [{ baseUrl: 'https://test/video', codecid: 7 }],
  audioStreams: [{ baseUrl: 'https://test/audio' }] } };
warm(result);
assert.equal(calls.length, 2, 'unmetered candidates use bounded prefix jobs');
assert.equal(calls[0][4], 512 * 1024);
assert.equal(calls[1][4], 64 * 1024);
calls.length = 0;

metered = true;
warm(result);
assert.equal(calls.length, 0, 'metered networks never start speculative media requests');
metered = false;
warm(result);
warm(result);
assert.equal(calls.length, 4, 'native pool deduplicates repeated prefix requests');
fail = true;
warm(result);
fail = false;
warm(result);
assert.equal(calls.length, 7, 'failed requests remain retryable');
settings.set('biliCookie', 'test-account');
warm(result);
assert.equal(calls.at(-1)[3], 'test-account', 'renewals pass current credentials');
settings.set('playbackPrewarmOff', true);
warm(result);
settings.set('playbackPrewarmOff', false);
settings.set('playbackKernel', 'system');
warm(result);
warm(null);
assert.equal(calls.length, 9, 'disabled and non-IJK paths do not start network work');
console.log('Bounded IJK prefix policy passed');
