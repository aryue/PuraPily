const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function run(source, context) {
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, context);
}
async function main() {
  const context = { exports: {}, require: () => ({}) };
  run(fs.readFileSync(base + 'utils/SignUtils.ts', 'utf8'), context);
  const { AppSign, WbiSign } = context.exports;
  assert.equal(AppSign.hasConfiguredKey('android'), false);
  assert.equal(AppSign.hasConfiguredKey('unknown'), false);
  assert.equal(AppSign.hasConfiguredKey('android_hd'), true);
  let hashes = 0;
  WbiSign.md5 = async () => { hashes++; return 'test-signature'; };
  await assert.rejects(AppSign.generateMobileParams({}, 'android'), /android/);
  assert.equal(hashes, 0, 'placeholder keys never reach signing');
  const params = { example: 'value' };
  await AppSign.signParams(params, 'android_hd');
  assert.equal(params.sign, 'test-signature', 'existing configured HD callers remain available');
  const api = fs.readFileSync(base + 'api/BilibiliApi.ts', 'utf8');
  const cdn = { exports: {} };
  run(fs.readFileSync(base + 'utils/PlaybackCdn.ts', 'utf8'), cdn);
  const durlStart = api.indexOf('function preferredDurl(');
  const durlEnd = api.indexOf('export interface DashVideoItem', durlStart);
  assert.ok(durlStart >= 0 && durlEnd > durlStart);
  const begin = api.indexOf('function emptyPlayUrlResult(');
  const end = api.indexOf('function generateTraceId(', begin);
  assert.ok(begin >= 0 && end > begin);
  let requests = 0, ended = 0, requestedUrl = '', signedPlatform = '';
  let cookie = 'account-a', token = 'test-access-token', detailLookup = Promise.resolve({ aid: 123 });
  let responseData = { quality: 80, durl: [{ url: 'compatible-stream' }] };
  const sign = AppSign.signParams.bind(AppSign);
  AppSign.signParams = async (params, platform) => { signedPlatform = platform; await sign(params, platform); };
  const marks = [];
  const mobile = { exports: {}, ...cdn.exports, AppSign, PlaybackStartup: { span: () => ({
    mark: name => marks.push(name), end: () => { ended++; }, network() {}
  }) }, AppStorage: { get: () => cookie }, getLoginAccessKey: async () => token,
    getVideoDetail: () => detailLookup, getCookieHeader: () => cookie,
    http: { RequestMethod: { GET: 'GET' }, createHttp() {
    return { async request(url) { requests++; requestedUrl = url; return { responseCode: 200,
      result: JSON.stringify({ code: 0, data: responseData }) }; }, destroy() {} };
  } }, logInfo() {}, logWarn() {}, logError() {} };
  run(api.slice(durlStart, durlEnd) + api.slice(begin, end) +
    '\nexports.fetch = tryFetchPlayUrlMobile; exports.compat = tryFetchPlayUrlCompat; exports.web = tryFetchPlayUrlWebRoute;', mobile);
  const result = await mobile.exports.fetch('BVtest', 1, 116, 3536);
  assert.equal(result.actualQn, 80); assert.equal(result.durlUrl, 'compatible-stream');
  assert.equal(requests, 1); assert.equal(ended, 1);
  const url = new URL(requestedUrl);
  assert.equal(url.origin, 'https://app.bilibili.com');
  assert.equal(url.pathname, '/x/playurl');
  assert.equal(url.searchParams.get('aid'), '123');
  assert.equal(url.searchParams.get('cid'), '1');
  assert.equal(url.searchParams.get('mobi_app'), 'android_hd');
  assert.equal(url.searchParams.get('device'), 'pad');
  assert.equal(url.searchParams.get('force_host'), '2');
  assert.equal(url.searchParams.get('access_key'), token);
  assert.equal(url.searchParams.get('sign'), 'test-signature');
  assert.equal(signedPlatform, 'android_hd');
  assert.ok(marks.includes('account-token')); assert.equal(hashes, 2);
  const pcdn = 'https://edge.mountaintoys.cn:4483/v';
  const mirror = 'https://upos-sz-mirrorali.bilivideo.com/v?signature=keep';
  responseData = { quality: 80, durl: [{ url: pcdn, backup_url: [mirror] }] };
  assert.equal((await mobile.exports.fetch('BVtest', 1, 116, 3536)).durlUrl, mirror);
  responseData = { quality: 80, timelength: 75000, dash: {
    video: [{ id: 80, codecid: 7, base_url: pcdn, backup_url: [mirror], frame_rate: '30', start_with_sap: 1 }],
    audio: [{ id: 30280, base_url: 'app-audio', backup_url: ['app-audio-backup'] }]
  } };
  const dash = await mobile.exports.fetch('BVtest', 1, 116, 3536);
  assert.equal(dash.route, 'app-hd');
  assert.equal(dash.dashVideoUrl, mirror); assert.equal(dash.dashAudioUrl, 'app-audio');
  assert.equal(dash.dashInfo.videoStreams[0].backupUrl[0], pcdn);
  assert.equal(dash.dashInfo.videoStreams[0].frameRate, '30');
  assert.equal(dash.dashInfo.audioStreams[0].backupUrl[0], 'app-audio-backup');
  token = '';
  await mobile.exports.fetch('BVtest', 1, 116, 3536);
  assert.equal(new URL(requestedUrl).searchParams.has('access_key'), false, 'anonymous requests send no fabricated token');
  const before = requests;
  let resolveDetail;
  detailLookup = new Promise(resolve => { resolveDetail = resolve; });
  const stale = mobile.exports.fetch('BVtest', 1, 116, 3536);
  cookie = 'account-b'; resolveDetail({ aid: 123 });
  assert.equal((await stale).actualQn, 0); assert.equal(requests, before, 'account switch blocks stale signed requests');
  detailLookup = Promise.resolve({ aid: 123 });
  mobile.tryFetchPlayUrl = async () => ({ durlUrl: '', dashVideoUrl: '', dashAudioUrl: '' });
  await mobile.exports.web('BVtest', 1, 116, 3536);
  const fallback = new URL(requestedUrl);
  assert.equal(fallback.origin, 'https://api.bilibili.com');
  assert.equal(fallback.pathname, '/x/player/playurl');
  assert.equal(fallback.searchParams.has('sign'), false, 'Web fallback remains separate from signed App');
  assert.equal(fallback.searchParams.has('access_key'), false);
  const after = requests;
  mobile.tryFetchPlayUrl = async () => ({ durlUrl: 'wbi-stream' });
  assert.equal((await mobile.exports.web('BVtest', 1, 116, 3536)).durlUrl, 'wbi-stream');
  assert.equal(requests, after, 'healthy WBI does not start compatibility traffic');
  console.log('PASS: compiled HD App endpoint, signed parameters and token, snake_case DASH tracks, stale cancellation, distinct Web fallback');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
