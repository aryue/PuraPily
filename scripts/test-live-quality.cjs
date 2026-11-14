const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/api/LiveApi.ets', 'utf8');
const start = source.indexOf('function selectLivePlaybackStream(');
const end = source.indexOf('/** V2 API: playurl_info', start);
assert.ok(start >= 0 && end > start);
const ctx = { exports: {}, getLiveQualityLabel: qn => `Quality ${qn}` };
vm.runInNewContext(ts.transpileModule(source.slice(start, end) +
  '\nexports.select = selectLivePlaybackStream; exports.qualities = supportedLiveQualities;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const codec = (codec_name, accept_qn, current_qn) => ({ codec_name, accept_qn, current_qn,
  base_url: '/stream.m3u8', url_info: [{ host: 'https://example.com', extra: '' }] });
const avc = codec('avc', [250, 80, 250], 250);
const hevc = codec('hevc', [30000, 20000, 10000, 250], 30000);
const streams = [{ protocol_name: 'http_hls', format: [
  { format_name: 'ts', codec: [codec('avc', [10000, 250], 10000)] },
  { format_name: 'fmp4', codec: [hevc, avc] }
] }];
const selected = ctx.exports.select(streams);
assert.equal(selected.codec, avc);
assert.equal(selected.format, 'fmp4');
const options = ctx.exports.qualities({ stream: streams, g_qn_desc: [
  { qn: 30000, desc: '杜比' }, { qn: 10000, desc: '原画' }, { qn: 250, desc: '超清' }, { qn: 80, desc: '流畅' }
] }, selected.codec);
assert.deepEqual(Array.from(options, q => q.qn), [250, 80], 'description table must not advertise unsupported codec qualities');
assert.equal(options[0].desc, '超清');
assert.equal(ctx.exports.select([{ protocol_name: 'http_hls', format: [{ format_name: 'fmp4', codec: [hevc] }] }]), undefined);
assert.equal(ctx.exports.select([{ protocol_name: 'http_hls', format: [{ format_name: 'fmp4', codec: [{ ...avc, url_info: [] }] }] }]), undefined);
assert.deepEqual(Array.from(ctx.exports.qualities({}, codec('avc', [], 250)), q => q.qn), [250]);
console.log('Live quality codec selection, accepted qualities, unavailable streams and actual quality fallback passed');

const cdn = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/utils/PlaybackCdn.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, cdn);
const pcdnHost = 'https://edge.mountaintoys.cn:4483';
const regularHost = 'https://d1--cn-gotcha04.bilivideo.com';
avc.url_info = [
  { host: pcdnHost, extra: '?sign=pcdn' },
  { host: regularHost, extra: '?sign=regular' }
];
Object.assign(ctx, cdn.exports, {
  HttpConstants: { liveBaseUrl: 'https://api.live.bilibili.com' },
  getBiliCookie: () => '',
  logInfo() {}, logWarn() {}, logError() {},
  http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
    request: async () => ({ responseCode: 200, result: JSON.stringify({
      code: 0, data: { playurl_info: { playurl: { stream: streams } } }
    }) }),
    destroy() {}
  }) }
});
const fetchStart = source.indexOf('async function tryFetchV2PlayUrl(');
const fetchEnd = source.indexOf('async function tryFetchNewPlayUrl(', fetchStart);
assert.ok(fetchStart >= 0 && fetchEnd > fetchStart);
vm.runInNewContext(ts.transpileModule(source.slice(fetchStart, fetchEnd) + '\nexports.fetch = tryFetchV2PlayUrl;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
(async () => {
  const result = await ctx.exports.fetch(1, 250);
  assert.equal(result.url, regularHost + '/stream.m3u8?sign=regular');
  assert.equal(result.currentQn, 250);
  avc.url_info.pop();
  assert.equal((await ctx.exports.fetch(1, 250)).url, pcdnHost + '/stream.m3u8?sign=pcdn');
  console.log('PASS: live V2 prefers a conventional CDN and accepts a PCDN-only response');
})().catch(error => { console.error(error); process.exitCode = 1; });
