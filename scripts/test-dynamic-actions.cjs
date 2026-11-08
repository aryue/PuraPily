// Exercise the actual CompileArkTS methods: retained card bindings, routes and write failures.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function extract(source, name) {
  const match = new RegExp('    (?:private )?(?:async )?' + name + '\\(').exec(source);
  assert.ok(match, `compiled method ${name}`);
  let end = source.indexOf('{', match.index), depth = 1;
  while (depth) { end++; if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(match.index, end + 1);
}
const source = fs.readFileSync(root + 'pages/DynamicsPage.ts', 'utf8');
let likeResult = { ok: true }, forwardResult = { ok: true }, calls = 0;
const context = { exports: {}, prefetchVideoPlayback() {}, AppStorage: { get() { return 116; } }, promptAction: { showToast() {} }, logError() {},
  ObservableDynLike: { from: (liked, count) => ({ liked, count }) },
  setDynamicLike: async () => { calls++; return likeResult; }, repostDynamic: async () => forwardResult };
const methods = ['likeStateOf', 'syncLikeStates', 'syncDynLikeCopies', 'toggleDynLike', 'playDynVideo',
  'openDynDetail', 'openDynComments', 'openDynForward', 'submitDynForward'];
vm.runInNewContext(ts.transpileModule('export class Page {' + methods.map(n => extract(source, n)).join('\n') + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
function page() {
  const p = new context.exports.Page();
  Object.assign(p, { isLoggedIn: true, likeStates_: new Map(), likingIds_: new Set(), dynFeedCache: new Map(),
    tabFeeds: [{ items: [] }, { items: [] }], routes: [], goToLogin() { p.login = true; }, saveTabFeed() {},
    getUIContext: () => ({ getRouter: () => ({ pushUrl: r => { p.routes.push(r); return Promise.resolve(); } }) }) });
  return p;
}
(async () => {
  const p = page(), item = { idStr: '1190000000000000001', liked: false, likeCount: 10, forwardCount: 4 };
  p.dynamics = [item]; p.syncLikeStates();
  const bound = p.likeStateOf(item);
  p.dynamics = [{ ...item }, { idStr: 'next', liked: false, likeCount: 0 }];
  p.syncLikeStates(); assert.equal(p.likeStateOf(item), bound, 'pagination keeps mounted ObjectLink identity');
  p.likingIds_.add(item.idStr); bound.liked = true; bound.count = 11;
  const duringRequest = { ...item };
  p.dynamics = [duringRequest]; p.syncLikeStates();
  assert.equal(duringRequest.liked, true); assert.equal(duringRequest.likeCount, 11, 'refresh during request preserves optimistic cache');
  p.likingIds_.clear(); bound.liked = false; bound.count = 10; p.dynamics = [item];
  const copy = { ...item };
  p.tabFeeds = [{ items: [item] }, { items: [copy] }];
  p.dynFeedCache.set('cached', { items: [{ ...item }] });
  await p.toggleDynLike(item);
  assert.equal(bound.liked, true); assert.equal(bound.count, 11);
  assert.equal(copy.liked, true); assert.equal(p.dynFeedCache.get('cached').items[0].likeCount, 11);
  p.dynamics = [copy]; p.syncLikeStates();
  assert.equal(p.likeStateOf(copy), bound); assert.equal(bound.liked, true, 'tab return retains successful like');
  likeResult = { ok: false, message: 'failed' }; await p.toggleDynLike(item);
  assert.equal(bound.liked, true); assert.equal(bound.count, 11); assert.equal(copy.liked, true, 'failed unlike rolls back all copies');
  p.likingIds_.add(item.idStr); const before = calls; await p.toggleDynLike(item); assert.equal(calls, before);
  p.likingIds_.clear(); p.isLoggedIn = false; await p.toggleDynLike(item); assert.equal(p.login, true);
  for (const bvid of ['BV1test123456', '12345678']) {
    const video = { bvid, title: 'video', cover: 'cover' };
    for (const type of ['DYNAMIC_TYPE_AV', 'DYNAMIC_TYPE_WORD', 'DYNAMIC_TYPE_DRAW', 'DYNAMIC_TYPE_FORWARD']) {
      const target = { ...item, type, video: type === 'DYNAMIC_TYPE_AV' ? video : null, orig: { video } };
      const q = page(); q.openDynComments(target);
      assert.equal(q.routes.length, 1);
      assert.equal(q.routes[0].url, type === 'DYNAMIC_TYPE_AV' ? 'pages/VideoPlayerPage' : 'pages/DynamicDetailPage');
      if (type === 'DYNAMIC_TYPE_AV') assert.equal(q.routes[0].params.openComments, true);
      q.routes = []; q.openDynDetail(target);
      if (type === 'DYNAMIC_TYPE_AV') assert.equal(q.routes[0].params.openComments, false);
    }
  }
  const q = page(); q.openDynForward(item);
  assert.equal(q.repostVisible, true); assert.equal(q.repostTarget, item); assert.equal(q.routes.length, 0);
  q.repostText = 'draft'; forwardResult = { ok: false, message: 'retry' }; await q.submitDynForward();
  assert.equal(q.repostText, 'draft'); assert.equal(q.repostVisible, true); assert.equal(q.repostSending, false);
  q.tabFeeds = [{ items: [item] }, { items: [item] }]; forwardResult = { ok: true }; await q.submitDynForward();
  assert.equal(item.forwardCount, 5, 'same item in two tabs only increments once'); assert.equal(q.repostVisible, false);
  const player = fs.readFileSync(root + 'pages/VideoPlayerPage.ts', 'utf8');
  const initStart = player.indexOf('    const p = router.getParams()');
  const init = player.slice(initStart, player.indexOf('    this.continuationRestore_', initStart));
  const state = {};
  vm.runInNewContext('(function(){' + ts.transpileModule(init, {}).outputText + '}).call(state)', {
    state, router: { getParams: () => ({ openComments: true }) }
  });
  assert.equal(state.at, 1); assert.equal(state.referenceTabProgress, 1);
  const actions = fs.readFileSync(root + 'components/DynamicFeedActions.ts', 'utf8');
  const handlers = [], dispatched = [];
  const node = new Proxy({}, { get: (_, key) => key === 'onClick' ? cb => handlers.push(cb) : () => {} });
  const usedColors = [];
  const ui = { exports: {}, Row: node, Text: node, Image: node, FlexAlign: { Center: 0 }, fmtCount: String,
    // 语义前景色桩：记录每次取色，验证操作栏不再写死中灰。
    secondaryTextColor: (dark) => { usedColors.push(dark); return dark ? '#C9CDD3' : '#50545A'; } };
  vm.runInNewContext(ts.transpileModule('export class Actions {' +
    extract(actions, 'initialRender') + extract(actions, 'countText') + extract(actions, 'actionColor') + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS }
  }).outputText, ui);
  const bar = new ui.exports.Actions();
  Object.assign(bar, { observeComponentCreation2: cb => cb(), like: { liked: false, count: 0 }, isDarkMode: true,
    onForward: () => dispatched.push('forward'), onComment: () => dispatched.push('comment'), onToggleLike: () => dispatched.push('like') });
  bar.initialRender(); handlers.forEach(cb => cb());
  assert.deepEqual(dispatched, ['forward', 'comment', 'like'], 'compiled UI dispatches independent callbacks');
  assert.ok(usedColors.length >= 6 && usedColors.every(d => d === true),
    '动态操作栏 6 处文字/图标都应按当前主题取语义色');
  bar.isDarkMode = false; bar.initialRender();
  assert.ok(usedColors.slice(-6).every(d => d === false), '切到浅色后取色应随之翻转');
  const api = fs.readFileSync(root + 'api/BilibiliApi.ts', 'utf8');
  const start = api.indexOf('export async function repostDynamic(');
  const end = api.indexOf('export async function setDynamicLike(', start);
  let response = { responseCode: 200, result: '{"code":0}' }, captured, destroyed = 0, csrf = 'test-token';
  const apiContext = { exports: {}, getCookieHeader: () => 'test-cookie', extractCsrfFromCookie: () => csrf,
    http: { RequestMethod: { POST: 'POST' }, createHttp: () => ({
      request: async (url, options) => { captured = { url, options }; if (response instanceof Error) throw response; return response; },
      destroy: () => destroyed++ }) } };
  vm.runInNewContext(ts.transpileModule(api.slice(start, end), { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, apiContext);
  const repost = apiContext.exports.repostDynamic;
  assert.equal((await repost(item.idStr, 'draft')).ok, true);
  const body = JSON.parse(captured.options.extraData).dyn_req;
  assert.equal(body.scene, 4); assert.equal(body.web_repost_src.dyn_id_str, item.idStr);
  assert.equal(body.content.contents[0].raw_text, 'draft'); assert.equal(destroyed, 1);
  response = { responseCode: 200, result: '{"code":-101,"message":"login required"}' };
  assert.equal((await repost(item.idStr, '')).ok, false);
  response = new Error('network'); assert.equal((await repost(item.idStr, '')).ok, false);
  assert.equal(destroyed, 3); csrf = ''; captured = null;
  assert.equal((await repost(item.idStr, '')).ok, false); assert.equal(captured, null);
  console.log('PASS: compiled like identity/pagination/tab cache/rollback, AV/BV comment routes, player comment selection, repost draft/failure/success.');
})().catch(e => { console.error(e); process.exitCode = 1; });
