const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/VideoCardFeedback.ts';
const store = new Map();
const calls = [];
const blocked = new Set();
const watched = new Set();
let blacklistSuccess = false, resolveFeedback;
const ctx = { exports: {}, AppStorage: { get: k => store.get(k), setOrCreate: (k, v) => store.set(k, v) },
  require: name => name.includes('/FeedbackService') ? {
    sendDislikeFeedback: (id, reason) => { calls.push(['dislike', id, reason]); return new Promise(resolve => { resolveFeedback = resolve; }); },
    sendDislikeUpFeedback: async (id, mid) => { calls.push(['block', id, mid]); throw new Error('offline'); }
  } : name.includes('/BilibiliApi') ? {
    blacklistUploader: async mid => { calls.push(['blacklist', mid]); return blacklistSuccess; }
  } : { UserBehaviorService: {
    addWatchedVideo: id => watched.add(id), addBlockedUploader: mid => blocked.add(mid),
    isBlockedUploader: mid => blocked.has(mid)
  } } };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const f = ctx.exports.VideoCardFeedback;
const id = 'BV1234567890', other = 'BV0987654321';
(async () => {
  assert.equal(f.actions('ss123', '123').length, 0, 'season identity cannot be sent to archive feedback');
  assert.equal(f.actions(id, '0').length, 2, 'invalid uploader identity hides uploader actions');
  assert.equal(f.actions(id, '123').length, 4);
  // Use the actual compiled App-feed parser rather than an invented BV fixture.
  const modelContext = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/model/RecommendItem.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, modelContext);
  const appItem = modelContext.exports.RecommendItem.fromAppApi({
    card_goto: 'av', player_args: { aid: 113456789012345, cid: 123, duration: 60 },
    title: 'App recommendation', cover: 'https://example.com/cover.jpg', args: { up_id: 123, up_name: 'UP' }
  });
  assert.equal(appItem.id, '113456789012345');
  assert.equal(f.actions(appItem.id, appItem.ownerMid).length, 4, 'App AV identities must expose the same menu as Web BV identities');
  assert.equal(f.actions(appItem.id, '0').length, 2);
  for (const invalid of ['', '0', '-1', '1.5', '01', '9007199254740992', 'ep123', 'ss123', 'live123']) {
    assert.equal(f.actions(invalid, '123').length, 0, 'reject non-archive or unsafe identity: ' + invalid);
  }
  const appPending = f.perform('不感兴趣', appItem.id, appItem.ownerMid);
  assert.equal(f.isDismissed(appItem.id, appItem.ownerMid), true);
  assert.deepEqual(calls.pop(), ['dislike', appItem.id, 1], 'forward the numeric archive identity unchanged');
  resolveFeedback({ success: false });
  assert.match(await appPending, /本地移除/);

  await f.perform('拉黑UP主', 'ss123', '123'); assert.equal(calls.length, 0);
  const pending = f.perform('不感兴趣', id, '123');
  assert.equal(f.isDismissed(id, '123'), true, 'local dismissal precedes network completion');
  assert.ok(watched.has(id)); assert.ok(store.get('cardFeedbackRevision') > 0);
  resolveFeedback({ success: false });
  assert.match(await pending, /本地移除/);
  assert.match(await f.perform('屏蔽UP主', other, '456'), /本地屏蔽/);
  assert.equal(f.isDismissed('BV1111111111', '456'), true, 'all cards of blocked uploader react');
  assert.match(await f.perform('拉黑UP主', other, '789'), /失败/);
  assert.equal(blocked.has('789'), false, 'failed account request cannot masquerade as successful blacklist');
  blacklistSuccess = true;
  assert.match(await f.perform('拉黑UP主', other, '789'), /已拉黑/);
  assert.ok(blocked.has('789'));
  const n = calls.length;
  assert.match(await f.perform('看过类似', other, '321'), /已标记/);
  assert.equal(calls.length, n, 'seen-before is a local action');
  assert.equal(f.isDismissed(other, '321'), true);
  assert.equal(f.isDismissed('', ''), false);
  console.log('Compiled card feedback: identity guards, immediate removal, offline block, blacklist success/failure and shared visibility passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
