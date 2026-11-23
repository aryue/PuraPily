const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/HomePage.ts', 'utf8');
const ast = ts.createSourceFile('HomePage.ts', source, ts.ScriptTarget.Latest, true);
const findClass = name => ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === name);
const page = findClass('HomePage');
const methods = ['requestMoreNearTail', 'loadMore'].map(name =>
  page.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(ast) === name).getText(ast));
const modelPath = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/model/';
const models = ['GenericDataSource', 'FirstScreenDataSource'].map(name =>
  fs.readFileSync(modelPath + name + '.ts', 'utf8').replace(/^import .*;\r?\n/gm, '').replace(/^export class /gm, 'class '));
const code = `${models.join('\n')}\n${findClass('VideoDataSource').getText(ast)}\nclass Pagination { ${methods.join('\n')} }\n({ VideoDataSource, Pagination });`;
const { Pagination, VideoDataSource } = vm.runInNewContext(ts.transpileModule(code, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, {
  DataOperationType: { ADD: 'add', RELOAD: 'reload' },
  UserBehaviorService: { filterRecommendList: items => items }
});

async function verify() {
  const dataSource = new VideoDataSource();
  const events = [];
  dataSource.registerDataChangeListener({
    onDatasetChange: changes => events.push(...changes.map(change => ({ ...change })))
  });
  dataSource.reloadItems(Array.from({ length: 30 }, (_, id) => ({ id: String(id) })));

  const deferred = [];
  const subject = Object.assign(new Pagination(), {
    dataSource, columnCount: 2, pageSize: 20, refreshIdx: 2, recommendationGeneration: 0,
    isPageActive: true, playbackHomeActive: true, playbackHomeChannel: 2, hasMore: true,
    filterWatched: items => items,
    fetchRecommendVideos: () => new Promise(resolve => deferred.push(resolve))
  });
  subject.requestMoreNearTail(16);
  assert.equal(deferred.length, 0, 'outside the six-row window');
  subject.requestMoreNearTail(17);
  subject.requestMoreNearTail(18);
  assert.equal(deferred.length, 1, 'prefetch before the bottom with only one request in flight');
  assert.ok(!subject.showPaginationFooter, 'prefetch does not open the footer');
  deferred[0]([{ id: '29' }, { id: '30' }, { id: '31' }, { id: '30' }]);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(dataSource.totalCount(), 32);
  assert.deepEqual(events, [{ type: 'reload' }, { type: 'add', index: 30, count: 2 }]);

  const staleRequest = subject.loadMore();
  subject.recommendationGeneration++;
  dataSource.reloadItems([{ id: 'refreshed' }]);
  deferred[1]([{ id: 'stale' }]);
  await staleRequest;
  assert.equal(dataSource.getData(0).id, 'refreshed');
  assert.equal(dataSource.totalCount(), 1);

  subject.isLoadingMore = false;
  let attempts = 0;
  subject.fetchRecommendVideos = async () => { attempts++; return [{ id: 'refreshed' }]; };
  await subject.loadMore();
  assert.equal(attempts, 3, 'consecutive unproductive pages are bounded');
  assert.equal(subject.paginationNeedsRetry, true);
  assert.equal(subject.isLoadingMore, false);
  await subject.loadMore();
  assert.equal(attempts, 3, 'visibility events cannot repeatedly retry a stalled page');
  subject.fetchRecommendVideos = async () => [{ id: 'after-retry' }];
  await subject.loadMore(true);
  assert.equal(dataSource.getData(1).id, 'after-retry');
  assert.equal(subject.paginationNeedsRetry, false);
}

verify().then(() => console.log('PASS home recommendation prefetch, batch append and retry')).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
