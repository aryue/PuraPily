const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync('entry/src/main/ets/api/BilibiliApi.ets', 'utf8');
const from = source.indexOf('interface VideoDetailCacheEntry');
const to = source.indexOf('/** Bilibili CDN 图片缩放', from);
assert.ok(from >= 0 && to > from);
const program = ts.transpileModule(source.slice(from, to) +
  '\nexports.cacheState = () => [recentVideoDetails.size, videoDetailCache.size];', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
let now = 0;
const requests = [];
const api = {};
vm.runInNewContext(program, {
  exports: api,
  Date: { now: () => now },
  PlaybackStartup: { span: () => undefined },
  logInfo() {}, logError() {}, logWarn() {},
  fetchVideoDetail: async key => {
    requests.push(key);
    const id = Number(key.replace('BV', ''));
    return { aid: id, bvid: `BV${id}` };
  }
});

async function verify() {
  const [first, shared] = await Promise.all([api.getVideoDetail('BV1'), api.getVideoDetail('BV1')]);
  assert.equal(first, shared);
  assert.deepEqual(requests, ['BV1'], 'same-key in-flight requests still share one fetch');
  assert.equal(await api.getVideoDetail('1'), first, 'aid and bvid keep one shared result');
  for (let i = 2; i <= 64; i++) await api.getVideoDetail(`BV${i}`);
  assert.equal(await api.getVideoDetail('1'), first, 'access through either alias updates recency');
  await api.getVideoDetail('BV65');
  assert.deepEqual(Array.from(api.cacheState()), [64, 128]);
  assert.equal(await api.getVideoDetail('BV1'), first);
  await api.getVideoDetail('2');
  assert.equal(requests.at(-1), '2', 'eviction removes the aid alias as well as the bvid');

  api.invalidateVideoDetailCache('1');
  assert.notEqual(await api.getVideoDetail('BV1'), first, 'invalidating either alias removes the shared object');
  now = 5 * 60 * 1000;
  await api.getVideoDetail('BV80');
  assert.deepEqual(Array.from(api.cacheState()), [1, 2], 'a new fill also releases stale entries');
  api.invalidateVideoDetailCache();
  assert.deepEqual(Array.from(api.cacheState()), [0, 0]);
  console.log('PASS bounded video detail cache, alias lookup, deduplication and expiration');
}

verify().catch(error => { console.error(error); process.exitCode = 1; });
