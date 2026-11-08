const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/UpSpacePage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const pageClass = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'UpSpacePage');
const names = ['openSpaceSearch', 'closeSpaceSearch', 'resetSpaceSearch', 'submitSpaceSearch',
  'loadSpaceSearchVideos', 'loadSpaceSearchDynamics', 'loadSpaceSearch', 'onBackPress'];
const body = names.map(name => pageClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
const calls = [];
const context = { exports: {}, Curve: { FastOutSlowIn: 0 }, errMsg: error => error.message,
  getUserSpaceVideos: (...args) => new Promise(resolve => calls.push({ kind: 'video', args, resolve })),
  getUpSpaceDynamics: (...args) => new Promise(resolve => calls.push({ kind: 'dynamic', args, resolve })) };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${body} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
function page() {
  const p = new context.exports.Subject();
  Object.assign(p, { mid: 123, activeTab: 'home', spaceSearchVersion: 0, spaceSearchText: '',
    spaceSearchScroller: { scrollTo() {} }, spaceSearchInputController: { stopEditing() {} },
    getUIContext: () => ({ animateTo: (_options, update) => update() }),
    videos: [{ bvid: 'original' }], dynamics: [{ idStr: 'original' }] });
  p.openSpaceSearch();
  return p;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  let p = page();
  p.spaceSearchText = '  测试 & A  '; p.submitSpaceSearch();
  assert.equal(calls.length, 2, 'one submit starts video and dynamic API calls together');
  assert.deepEqual(calls.at(-2).args, [123, 1, 30, 'pubdate', '测试 & A']);
  assert.deepEqual(calls.at(-1).args, [123, '', '测试 & A', 1]);
  calls.at(-2).resolve({ list: { vlist: [{ bvid: 'match' }] }, page: { count: 31 } });
  calls.at(-1).resolve({ items: [{ idStr: 'dyn-match' }], offset: 'older', hasMore: true }); await tick();
  assert.equal(p.spaceSearchVideos[0].bvid, 'match');
  assert.equal(p.spaceSearchDynamics[0].idStr, 'dyn-match');
  const next = p.loadSpaceSearch(); assert.equal(calls.at(-2).args[1], 2);
  assert.deepEqual(calls.at(-1).args, [123, 'older', '测试 & A', 2]);
  calls.at(-2).resolve({ list: { vlist: [{ bvid: 'match' }, { bvid: 'second' }] }, page: { count: 31 } });
  calls.at(-1).resolve({ items: [{ idStr: 'dyn-match' }, { idStr: 'dyn-second' }], offset: 'last', hasMore: false }); await next;
  assert.equal(p.spaceSearchVideos.length, 2); assert.equal(p.spaceSearchHasMore, false);
  assert.equal(p.spaceSearchDynamics.length, 2);
  assert.equal(p.videos[0].bvid, 'original'); assert.equal(p.dynamics[0].idStr, 'original');

  p.spaceSearchText = 'partial'; p.submitSpaceSearch();
  calls.at(-2).resolve({ list: { vlist: [{ bvid: 'available' }] }, page: { count: 1 } });
  calls.at(-1).resolve(null); await tick();
  assert.ok(p.spaceSearchError); assert.equal(p.spaceSearchVideos[0].bvid, 'available');
  const count = calls.length; const retryDynamic = p.loadSpaceSearch();
  assert.equal(calls.length, count + 1, 'a failed dynamic query can retry without reloading completed videos');
  assert.equal(calls.at(-1).kind, 'dynamic');
  calls.at(-1).resolve({ items: [], offset: '', hasMore: false }); await retryDynamic;
  assert.equal(p.spaceSearchError, ''); assert.equal(p.spaceSearchHasMore, false);

  p = page(); p.spaceSearchText = 'old'; p.submitSpaceSearch(); const old = calls.slice(-2);
  p.spaceSearchText = 'new'; p.submitSpaceSearch(); const fresh = calls.slice(-2);
  old[0].resolve({ list: { vlist: [{ bvid: 'stale' }] }, page: { count: 1 } });
  old[1].resolve({ items: [{ idStr: 'stale' }], offset: '', hasMore: false }); await tick();
  assert.equal(p.spaceSearchLoading, true); assert.equal(p.spaceSearchVideos.length, 0);
  assert.equal(p.spaceSearchDynamics.length, 0);
  fresh.forEach(call => call.resolve(null)); await tick(); assert.ok(p.spaceSearchError);
  const retry = p.loadSpaceSearch();
  assert.equal(p.onBackPress(), true); assert.equal(p.spaceSearchOpen, false);
  calls.at(-2).resolve({ list: { vlist: [{ bvid: 'late' }] }, page: { count: 1 } });
  calls.at(-1).resolve({ items: [{ idStr: 'late' }], offset: '', hasMore: false }); await retry;
  assert.equal(p.spaceSearchVideos.length, 0); assert.equal(p.onBackPress(), false);
  p = page(); const before = calls.length; p.spaceSearchText = '  '; p.submitSpaceSearch();
  assert.equal(calls.length, before);
  console.log('PASS: compiled UP search: simultaneous scoped video/dynamic APIs, independent pagination, deduplication, partial failure/retry, stale responses, back and original-list preservation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
