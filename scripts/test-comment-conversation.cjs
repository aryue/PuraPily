const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/', name), 'utf8').replace(/\r\n/g, '\n');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const api = read('api/BilibiliApi.ets');
const apiBody = api.match(/export async function getCommentDialog\([\s\S]*?Promise<CommentDialogResult> \{([\s\S]*?)\n\}\n\n\/\//)[1]
  .replace(/ as ApiResponse<CommentDialogData>/g, '').replace(/ as string/g, '');
const requestDialog = new AsyncFunction('http', 'replyThrottleRequest', 'getRotatedHeaders',
  'triggerRateLimitCooldown', 'logWarn', 'logInfo', 'oid', 'root', 'dialog', 'minFloor', 'pageSize', 'type', apiBody);

async function responseCase(json, status = 200, floor = 0) {
  let released = false;
  let cooldown = false;
  let url;
  const result = await requestDialog({
    RequestMethod: { GET: 'GET' },
    createHttp: () => ({
      request: async value => { url = value; return { responseCode: status, result: JSON.stringify(json) }; },
      destroy: () => { released = true; },
    }),
  }, async () => {}, () => ({}), () => { cooldown = true; }, () => {}, () => {}, 10, 20, 30, floor, 20, 1);
  assert.equal(released, true);
  assert.ok(url.includes('oid=10&root=20&dialog=30&min_floor=' + floor));
  return { result, cooldown };
}

const panel = read('components/CommentConversationPanel.ets');
const loadBody = panel.match(/private async loadConversation\([^\n]+\{([\s\S]*?)\n  \}\n\n  build/)[1]
  .replace(/: ObservableComment\[\]/g, '').replace(/: ObservableComment(?=\))/g, '')
  .replace(/new Set<number>/g, 'new Set');
const load = new AsyncFunction('getCommentDialog', 'ObservableComment', 'reset', loadBody);
function state(fetch) {
  return {
    root: { rpid: 20, oid: 10, type: 1 }, selected: { rpid: 31, dialog: 30 },
    videoDetail: null, floor: 0, replies: [], requestVersion: 0, alive: true,
    loading: false, failed: false, hasMore: true,
    load(reset = false) { return load.call(this, fetch, { from: value => value }, reset); },
  };
}
const page = (ids, nextFloor, hasMore) => ({ ok: true, replies: ids.map(rpid => ({ rpid })), nextFloor, hasMore });

(async () => {
  let result = (await responseCase({ code: 0, data: {
    replies: [{ rpid: 31 }], cursor: { max_floor: 99 }, dialog: { max_floor: 243 },
  } })).result;
  assert.equal(result.hasMore, true);
  assert.equal(result.nextFloor, 100);
  result = (await responseCase({ code: 0, data: {
    replies: [{ rpid: 32 }], cursor: { max_floor: 243 }, dialog: { max_floor: 243 },
  } }, 200, 99)).result;
  assert.equal(result.hasMore, false);
  assert.equal((await responseCase({ code: 0, data: { replies: [], cursor: { max_floor: 99 }, dialog: { max_floor: 243 } } })).result.hasMore, false);
  assert.equal((await responseCase({ code: -101 })).result.message, '请先登录后查看对话');
  assert.equal((await responseCase({}, 412)).cooldown, true);

  const queue = [page([30, 31], 2, true), { ok: false, message: 'retry' }, page([31, 32], 4, false)];
  const cursors = [];
  const conversation = state(async (oid, root, dialog, floor) => {
    assert.deepEqual([oid, root, dialog], [10, 20, 30]);
    cursors.push(floor);
    return queue.shift();
  });
  await conversation.load(true);
  assert.equal(conversation.replies[1], conversation.selected);
  await conversation.load();
  assert.equal(conversation.failed, true);
  assert.equal(conversation.floor, 2);
  await conversation.load();
  assert.deepEqual(cursors, [0, 2, 2]);
  assert.deepEqual(conversation.replies.map(reply => reply.rpid), [30, 31, 32]);
  assert.equal(conversation.hasMore, false);

  const stalled = state(async () => page([30], 0, true));
  await stalled.load(true);
  assert.equal(stalled.hasMore, false);
  let resolve;
  const pending = state(() => new Promise(done => { resolve = done; }));
  const work = pending.load(true);
  pending.alive = false;
  pending.requestVersion++;
  resolve(page([30], 1, false));
  await work;
  assert.equal(pending.replies.length, 0);

  const player = read('pages/VideoPlayerPage.ets');
  const closeBody = player.match(/private closeCommentThread\(\): void \{([\s\S]*?)\n  \}/)[1];
  const close = new Function('Curve', closeBody);
  const detail = { rpid: 20 };
  const screen = {
    commentThread: detail, commentDialog: { dialog: 30 },
    getUIContext: () => ({ animateTo: (_options, update) => update() }),
  };
  close.call(screen, { EaseOut: 0 });
  assert.equal(screen.commentDialog, null);
  assert.equal(screen.commentThread, detail);
  close.call(screen, { EaseOut: 0 });
  assert.equal(screen.commentThread, null);
  console.log('Conversation: API cursors, login failure, rate limit, retry, deduplication, dismissal and nested return passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
