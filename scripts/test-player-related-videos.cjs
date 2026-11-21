const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const pending = [];
const failures = [];
const hidden = new Set(['dismissed']);
const context = { exports: {}, require(name) {
  if (name === '../api/BilibiliApi') return {
    getRelatedVideos: bvid => new Promise((resolve, reject) => pending.push({ bvid, resolve, reject }))
  };
  if (name === './VideoCardFeedback') return {
    VideoCardFeedback: { isDismissed: (id, owner) => hidden.has(id) || hidden.has(owner) }
  };
  if (name === '../utils/Logger') return { logError: message => failures.push(message) };
  return {};
} };
const source = fs.readFileSync('entry/src/main/ets/services/PlaybackRelatedVideos.ets', 'utf8');
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

async function main() {
  const service = new context.exports.PlaybackRelatedVideos();
  const stale = service.load('BVfirst', () => true);
  const current = service.load('BVsecond', () => true);
  assert.deepEqual(pending.map(item => item.bvid), ['BVfirst', 'BVsecond']);
  const item = { id: 'visible', ownerMid: 'up1' };
  pending[1].resolve([item, { id: 'dismissed' }, { id: 'blocked', ownerMid: 'dismissed' }]);
  assert.deepEqual(Array.from(await current), [item]);
  pending[0].reject(new Error('obsolete request failed'));
  assert.equal(await stale, null, 'late errors cannot clear the active recommendations');
  assert.equal(failures.length, 0);

  const cachedItems = await service.load('BVsecond', () => true);
  assert.deepEqual(Array.from(cachedItems), [item], 'successful results must be cached for the next page');
  assert.equal(pending.length, 2, 'cache hit must not start another related request');

  const oldGeneration = service.load('BVthird', () => false);
  pending[2].resolve([item]);
  assert.equal(await oldGeneration, null);
  const failure = service.load('BVfail', () => true);
  pending[3].reject(new Error('current request failed'));
  assert.deepEqual(Array.from(await failure), []);
  assert.equal(failures.length, 1);

  hidden.add(item.id);
  assert.deepEqual(Array.from(service.visible([item])), []);
  console.log('PASS: related video replacement, stale network failure, generation ownership and feedback filtering');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
