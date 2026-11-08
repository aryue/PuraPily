const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const panel = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/CommentThreadPanel.ets'), 'utf8').replace(/\r\n/g, '\n');
const player = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const vm = require('node:vm');
const sortModule = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/CommentReplySort.ets'), 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, sortModule);
const { sortCommentReplies } = sortModule.exports;
const body = panel.match(/private async loadReplies\([^\n]+\{([\s\S]*?)\n  \}\n\n  build/)[1]
  .replace(/: ObservableComment\[\]/g, '')
  .replace(/: ObservableComment/g, '')
  .replace(/new Set<number>/g, 'new Set');

function state(fetch) {
  const load = new AsyncFunction('getCommentDetail', 'ObservableComment', 'sortCommentReplies', 'reset', body);
  return {
    alive: true, requestVersion: 0, page: 0, replies: [], total: 0,
    loading: false, failed: false, hasMore: true, sortByHeat: false,
    comment: { rpid: 1, oid: 2, rcount: 41 }, videoDetail: null,
    loadReplies(reset = false) { return load.call(this, fetch, { from: value => value }, sortCommentReplies, reset); },
  };
}
const rows = (start, length, total = 41) => ({
  totalCount: total, replies: Array.from({ length }, (_, i) => ({ rpid: start + i })),
});
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

(async () => {
  const queue = [rows(1, 20), rows(20, 20), rows(40, 2)];
  const pages = [];
  const thread = state(async (_aid, _root, page) => { pages.push(page); return queue.shift(); });
  await thread.loadReplies(true);
  await thread.loadReplies();
  await thread.loadReplies();
  await thread.loadReplies();
  assert.deepEqual(pages, [1, 2, 3]);
  assert.equal(thread.replies.length, 41);
  assert.equal(thread.hasMore, false);

  const retries = [null, rows(1, 2, 2)];
  const retry = state(async () => retries.shift());
  await retry.loadReplies(true);
  assert.equal(retry.failed, true);
  assert.equal(retry.page, 0);
  await retry.loadReplies(true);
  assert.equal(retry.failed, false);
  assert.equal(retry.replies.length, 2);

  const sortingResponse = deferred();
  const sorting = state(() => sortingResponse.promise);
  const loadingSort = sorting.loadReplies(true);
  sorting.sortByHeat = true; // User switches while the chronological page is pending.
  sortingResponse.resolve({ totalCount: 3, replies: [
    { rpid: 1, ctime: 10, like: 1 }, { rpid: 2, ctime: 20, like: 50 }, { rpid: 3, ctime: 30, like: 10 },
  ] });
  await loadingSort;
  assert.deepEqual(sorting.replies.map(reply => reply.rpid), [2, 3, 1]);
  sorting.replies = sortCommentReplies(sorting.replies, false);
  assert.deepEqual(sorting.replies.map(reply => reply.rpid), [1, 2, 3]);
  assert.equal(sorting.page, 1, 'local sort must not reset the API page cursor');

  const oldRequest = deferred();
  let requests = 0;
  const refreshed = state(() => ++requests === 1 ? oldRequest.promise : Promise.resolve(rows(100, 1, 1)));
  const old = refreshed.loadReplies(true);
  await refreshed.loadReplies(); // Loading guard must not start a second page.
  assert.equal(requests, 1);
  await refreshed.loadReplies(true);
  oldRequest.resolve(rows(1, 20));
  await old;
  assert.deepEqual(refreshed.replies.map(reply => reply.rpid), [100]);

  const pending = deferred();
  const closed = state(() => pending.promise);
  const work = closed.loadReplies(true);
  closed.alive = false;
  closed.requestVersion++;
  pending.resolve(rows(1, 20));
  await work;
  assert.equal(closed.replies.length, 0);

  const closeBody = player.match(/private closeCommentThread\(\): void \{([\s\S]*?)\n  \}/)[1];
  const closeThread = new Function('Curve', closeBody);
  for (const signature of ['onBackPress\\(\\): boolean', 'goBack\\(\\)', 'private onOverlayBack_\\(\\): void']) {
    const method = player.match(new RegExp(`${signature} \\{([\\s\\S]*?)\\n  \\}`))[1]
      .replace(/const now: number/g, 'const now');
    const context = {
      commentThread: { rpid: 1 }, referenceFeedComments: true, fs: true,
      closePlaybackOptionPanel() { return false; },
      closeCommentThread() { closeThread.call(this, { EaseOut: 'easeOut' }); },
      getUIContext() { return { animateTo(options, update) { assert.equal(options.duration, 280); update(); } }; },
      release() { throw new Error('Must keep video playing'); },
      toggleFS() { throw new Error('Must keep player layout'); },
      goBack() { throw new Error('Must keep current page'); },
    };
    new Function(method).call(context);
    assert.equal(context.commentThread, null);
    assert.equal(context.referenceFeedComments, true);
    assert.equal(context.fs, true);
  }
  console.log('Comment thread: paging, deduplication, retry, refresh races, dismissal and three back paths passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
