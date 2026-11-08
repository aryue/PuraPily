const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = process.argv.includes('--compiled');
const root = path.resolve(__dirname, compiled
  ? '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets'
  : '../entry/src/main/ets');
const extension = compiled ? '.ts' : '.ets';
const storage = new Map();
const appStorage = { get: k => storage.get(k), setOrCreate: (k, v) => storage.set(k, v) };
const logger = { logInfo() {}, logWarn() {} };
function load(file, imports = {}, globals = {}) {
  const context = { exports: {}, AppStorage: appStorage, ...globals,
    require: name => {
      if (imports[name]) return imports[name];
      if (name === '@ohos:net.http') return { default: imports['@kit.NetworkKit'].http };
      const match = Object.keys(imports).find(key => name.endsWith('/' + path.basename(key) + '&'));
      return match ? imports[match] : {};
    } };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, file + extension), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
async function main() {
  const { RecommendItem } = load('model/RecommendItem');
  const { hasLoginSession } = load('utils/LoginCookie');
  const raw = { bvid: 'BV1hb411c7RQ', aid: 10, cid: 11, title: 'story', goto: 'av', cover: 'https://cover',
    owner: { mid: 20 }, dimension: { width: 1920, height: 1080 } };
  const requests = [], web = [];
  let code = 0;
  const api = load('api/StoryRecommendApi', {
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
      async request(url, options) { requests.push({ url, options }); return {
        responseCode: 200, result: JSON.stringify({ code, data: { items: [raw, { ...raw, ad_info: {} }] } })
      }; }, destroy() {}
    }) } },
    '../model/RecommendItem': { RecommendItem }, '../utils/Logger': logger,
    '../utils/LoginCookie': { hasLoginSession },
    './BilibiliApi': { async getRecommendVideos(index, size) { web.push([index, size]); return [raw]; } },
    '../utils/SignUtils': { AppSign: { async signParams(params, platform) {
      assert.equal(platform, 'android_hd'); assert.equal(params.access_key, 'app-key');
      params.appkey = 'configured-key'; params.sign = 'signature';
    } } }
  });
  storage.set('biliCookie', 'SESSDATA=web; DedeUserID=1');
  await api.getStoryRecommendVideos(9, 'feed-session');
  assert.deepEqual(web, [[9, 20]]);
  assert.equal(requests.length, 0, 'Cookie-only sessions must never silently accept anonymous Story feeds');
  storage.set('biliAccessKey', 'app-key');
  const result = await api.getStoryRecommendVideos(10, 'feed-session');
  assert.equal(result.length, 1, 'filter advertising before queueing');
  assert.equal(result[0].aid, 10, 'keep the AV alias for history deduplication');
  const params = new URL(requests[0].url).searchParams;
  assert.equal(params.get('access_key'), 'app-key'); assert.equal(params.get('sign'), 'signature');
  assert.equal(params.get('display_id'), '10');
  assert.equal(requests[0].options.header.session_id, 'feed-session');
  code = -101;
  await api.getStoryRecommendVideos(11, 'feed-session');
  assert.deepEqual(web.at(-1), [11, 20], 'rejected App credentials can use an authenticated Web fallback');
  storage.delete('biliCookie');
  assert.equal((await api.getStoryRecommendVideos(12, 'feed-session')).length, 0,
    'without a Cookie session, rejected App credentials must not retry anonymously');
  storage.clear(); code = 0;
  await api.getStoryRecommendVideos(12, 'guest-session');
  assert.equal(new URL(requests.at(-1).url).searchParams.has('access_key'), false);

  const historyCalls = [];
  const stateImports = { '../api/BilibiliHistoryApi': { BilibiliHistoryApi: { getInstance: () => ({
    async getHistoryList(max, size, cookie) {
      historyCalls.push({ max, size, cookie });
      return [{ bvid: 'BV1hb411c7RQ', aid: 10, business: 'archive' },
        { aid: 99, business: 'pgc', type: 4 }];
    }
  }) } } };
  let { ContinuousRecommendationState: state } = load('services/ContinuousRecommendationState', stateImports);
  storage.set('biliCookie', 'SESSDATA=one; DedeUserID=1');
  const account = state.account();
  assert.equal(state.reservePage(account), 1);
  state.markVisited(raw.bvid, 10);
  assert.equal(state.isExcluded({ id: '10', aid: 0 }, state.excluded(account)), true);
  ({ ContinuousRecommendationState: state } = load('services/ContinuousRecommendationState', stateImports));
  assert.equal(state.reservePage(account), 2, 'reopening a player preserves its independent cursor');
  assert.ok(state.excluded(account).has(raw.bvid), 'visited records survive a new service instance');
  storage.set('playbackProgressV1', JSON.stringify([
    { key: '1:BV1234567890:12', position: 8 }, { key: '2:BV0987654321:13', position: 20 },
    { key: '1:ep99:14', position: 9 }, { key: '1:BV0000000000:15', position: 0 }
  ]));
  assert.ok(state.excluded('1').has('BV1234567890'));
  assert.equal(state.excluded('1').has('BV0987654321'), false);
  assert.equal(state.excluded('1').has('ep99'), false);
  assert.equal(state.excluded('1').has('BV0000000000'), false);
  await Promise.all([state.syncRecentHistory(account), state.syncRecentHistory(account)]);
  assert.equal(historyCalls.length, 1, 'share concurrent history requests');
  assert.equal(historyCalls[0].size, 100);
  assert.equal(state.excluded(account).has('99'), false, 'PGC identities are not archive identities');
  storage.set('biliCookie', 'SESSDATA=two; DedeUserID=2');
  assert.equal(state.reservePage(state.account()), 1, 'account paging is isolated');
  assert.equal(state.excluded(state.account()).has('10'), false, 'account history is isolated');
  storage.set('continuousRecommendationsV1', 'broken');
  assert.equal(state.reservePage('2'), 1);
  for (let i = 1; i <= 2100; i++) state.markVisited(String(i));
  assert.equal(state.excluded('2').size, 2001, 'visited storage is bounded; local history is also included');

  // Exercise the real page fetcher: excluded batches must advance the cursor,
  // remain excluded on later pages, and retain both queued and AV aliases.
  const source = fs.readFileSync(path.join(root, 'pages/VideoPlayerPage' + extension), 'utf8');
  const start = source.indexOf('private async referenceFetchRecommendations(');
  const end = source.indexOf('private async referenceNextVideo(', start);
  const calls = [];
  const context = { exports: {}, Set, Promise, logInfo() {},
    ContinuousRecommendationState: state,
    VideoCardFeedback: { isDismissed: (id, mid) => mid === 'blocked' || id === 'dismissed' },
    async getStoryRecommendVideos(index) {
      calls.push(index);
      return calls.length === 1 ? [{ id: 'BV1hb411c7RQ', aid: 10 }] : [
        { id: 'BV1hb411c7RQ', aid: 10 }, { id: 'queued', aid: 88 },
        { id: 'dismissed' }, { id: 'blocked', ownerMid: 'blocked' },
        { id: 'new', aid: 3000 }, { id: 'new-alias', aid: 3000 }
      ];
    }
  };
  state.markVisited(raw.bvid, 10);
  vm.runInNewContext(ts.transpileModule(`class Page { ${source.slice(start, end)} } exports.Page = Page;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const page = new context.exports.Page();
  Object.assign(page, { referenceAlive: true, referenceFeedQueue: [{ id: 'queued', aid: 88 }] });
  await page.referenceFetchRecommendations();
  assert.deepEqual(Array.from(page.referenceFeedQueue, item => item.id), ['queued', 'new']);
  assert.equal(calls.length, 3, 'all-excluded and sparse pages still advance within the request limit');
  assert.equal(calls[1], calls[0] + 1);
  assert.equal(calls[2], calls[1] + 1);
  console.log('PASS: Story login routing/signing, persistent account history/cursor, cloud/local history, AV/BV aliases, feedback, sparse paging and queue deduplication');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
