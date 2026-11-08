const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const storage = new Map();
const requests = [];
const webRequests = [];
let apiCode = 0;
let destroyed = 0;
const videos = Array.from({ length: 8 }, (_, i) => ({ id: `BV${i}`, ownerMid: String(i), title: 'video', ownerName: 'up' }));
const logger = { logInfo() {}, logWarn() {}, logError() {}, errMsg: String };
const shared = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
const cache = new Map();
function load(file) {
  if (cache.has(file)) return cache.get(file);
  const context = { exports: {}, AppStorage: shared, require: name => {
    if (name === '@kit.NetworkKit') return { http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
      request: async (url, options) => {
        requests.push({ url, options });
        return { responseCode: 200, result: JSON.stringify({ code: apiCode, data: { items: videos } }) };
      }, destroy: () => destroyed++
    }) } };
    if (name.endsWith('/Logger')) return logger;
    if (name.endsWith('/SignUtils')) return { AppSign: { APP_KEYS: { android_hd: { appkey: 'test', appsec: 'test' } } }, WbiSign: { md5: async () => 'signature' } };
    if (name.endsWith('/BilibiliApi')) return { getRecommendVideos: async (...args) => { webRequests.push(args); return videos; } };
    if (name.endsWith('/RecommendItem')) return { RecommendItem: { fromAppApi: item => item } };
    if (name.endsWith('/UserBehaviorService')) return { UserBehaviorService: {} };
    return load(path.resolve(path.dirname(file), name + '.ets'));
  } };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context, { filename: file });
  cache.set(file, context.exports);
  return context.exports;
}

(async () => {
  const { getRecommendVideosOptimized: fetch } = load(path.join(root, 'api/RecommendApiOptimized.ets'));
  storage.set('biliCookie', 'SESSDATA=web-session; DedeUserID=123; bili_jct=csrf');
  assert.equal(await fetch(7, 24), videos);
  assert.deepEqual(webRequests, [[7, 24]], 'Cookie-only login must preserve pagination and use Web recommendations');
  assert.equal(requests.length, 0, 'do not accept a successful anonymous App feed for a logged-in Web user');

  storage.set('biliAccessKey', 'app-session');
  assert.equal((await fetch(8, 24)).length, videos.length);
  const request = requests.at(-1);
  assert.equal(new URL(request.url).searchParams.get('access_key'), 'app-session');
  assert.equal(request.options.header.Cookie, storage.get('biliCookie'));
  assert.equal(webRequests.length, 1, 'App credentials should retain the App source');
  assert.equal(destroyed, 1);

  storage.clear();
  await fetch(2, 30);
  assert.equal(new URL(requests.at(-1).url).searchParams.has('access_key'), false, 'anonymous browsing remains available');
  assert.equal(requests.length, 2);
  storage.set('biliCookie', 'fakeSESSDATA=invalid; DedeUserID=123');
  await fetch(3, 30);
  assert.equal(requests.length, 3, 'a misleading cookie name is not a login session');
  apiCode = -101;
  assert.equal((await fetch(4, 30)).length, 0, 'API rejection must allow the caller to fall back');
  assert.equal(destroyed, 4);

  const { RecommendDetector } = load(path.join(root, 'utils/RecommendDetector.ets'));
  storage.set('biliCookie', 'SESSDATA=web-session; DedeUserID=123; bili_jct=csrf');
  storage.set('watchedVideos', new Set(['BV0']));
  const result = await RecommendDetector.runFullDetection();
  assert.equal(result.details.recommendStatus.canFetchRecommend, true);
  assert.equal(result.details.recommendStatus.hasPersonalized, false, 'many different uploaders do not prove personalization');
  assert.equal(result.issues.includes('推荐内容不够个性化'), false, 'unknown personalization does not mean poor personalization');
  assert.match(RecommendDetector.generateReport(result), /个性化: 未验证/);
  console.log('PASS: Cookie-only, App, anonymous and rejected recommendation requests; personalization detection does not infer effectiveness from diversity.');
})().catch(error => { console.error(error); process.exitCode = 1; });
