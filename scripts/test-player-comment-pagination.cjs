const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8');
function between(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}

const context = { exports: {}, logInfo() {}, logWarn() {}, logError() {} };
function load(code) {
  vm.runInNewContext(ts.transpileModule(code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
}
load('export class Page {' + between('  private applyCommentPage(', '  private async scrollToTargetComment(') +
  between('  private async loadMC(', '  // ⭐ 切换评论排序') + '}');
const { Page } = context.exports;
context.require = () => ({});
load(fs.readFileSync('entry/src/main/ets/services/PlaybackComments.ets', 'utf8'));
const { PlaybackComments } = context.exports;

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

async function main() {
  const page = new Page();
  const requests = [];
  const data = [];
  let targetSearches = 0;
  const service = new PlaybackComments();
  service.fetch = (aid, cursor, sort) => {
    const pending = deferred();
    requests.push({ aid, cursor, sort, ...pending });
    return pending.promise;
  };
  Object.assign(page, {
    playbackComments_: service, referenceAlive: true, referenceSwitchGeneration: 1, vd: { aid: 33 },
    commentCursor: 12, commentSort: 2, hm: true, ldc: false, isLoadingMore: false, commentRootId_: 4,
    commentDataSource: {
      setComments: rows => { data.splice(0, data.length, ...rows); },
      appendComments: rows => data.push(...rows)
    },
    scrollToTargetComment() {
      assert.equal(this.ldc, false, 'the target lookup can paginate immediately after the first page');
      targetSearches++;
    }
  });
  const previous = page.loadMC();
  assert.equal(page.isLoadingMore, true);
  page.commentSort = 1;
  page.commentCursor = 0;
  const reload = page.loadC(33);
  assert.equal(page.isLoadingMore, false, 'reload supersedes the pagination spinner');
  assert.deepEqual(requests.map(({ aid, cursor, sort }) => [aid, cursor, sort]), [[33, 12, 2], [33, 0, 1]]);
  requests[1].resolve({ comments: [101], nextCursor: 22, isEnd: false });
  await reload;
  assert.equal(targetSearches, 1);
  assert.deepEqual(data, [101]);
  requests[0].resolve({ comments: [55], nextCursor: 40, isEnd: true });
  await previous;
  assert.deepEqual(data, [101], 'late pagination cannot append rows from the preceding sort');
  assert.equal(page.commentCursor, 22);
  assert.equal(page.hm, true);

  const next = page.loadMC();
  requests[2].resolve({ comments: [102], nextCursor: 30, isEnd: true });
  await next;
  assert.deepEqual(data, [101, 102]);
  assert.equal(page.commentCursor, 30);
  assert.equal(page.hm, false);
  assert.equal(page.isLoadingMore, false);
  console.log('PASS: stale pagination isolation, target lookup after initial results, and current cursor commits');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
