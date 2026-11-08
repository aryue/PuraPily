const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const store = new Map(), calls = [], modules = new Map();
const cookie = 'SESSDATA=test; bili_jct=012abc; DedeUserID=123; buvid3=real-device';
let refresh = async () => '', reply = async () => ({ code: 0 }), destroys = 0;
const shared = { get: key => store.get(key), setOrCreate: (key, value) => store.set(key, value) };
const logger = { logInfo() {}, logWarn() {}, logError() {}, errMsg: String };
const http = { RequestMethod: { POST: 'POST', GET: 'GET' }, createHttp: () => ({
  request: async (url, options) => { calls.push({ url, options }); return { responseCode: 200, result: JSON.stringify(await reply(url, options)) }; },
  destroy: () => destroys++
}) };
function evaluate(code, ctx) {
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
}
function load(file) {
  if (modules.has(file)) return modules.get(file);
  const ctx = { exports: {}, AppStorage: shared, require: name => {
    if (name.includes('net.http')) return { default: http };
    if (name.includes('Logger')) return logger;
    if (name.includes('CredentialStore')) return { getLoginAccessKey: async () => store.get('biliAccessKey') || await refresh() };
    if (name.includes('BilibiliApi')) return { refreshAccessKeyFromCookie: () => refresh(), getVideoDetail: async () => ({ aid: 123 }) };
    if (name.includes('SignUtils')) return { AppSign: { signParams: async p => { p.appkey = 'test'; p.sign = 'signature'; } } };
    for (const dep of ['api/FeedbackService', 'api/VideoInteractionApi', 'utils/LoginCookie', 'services/WebDeviceIdentity']) {
      if (name.includes(dep)) return load(dep + '.ts');
    }
    return {};
  } };
  modules.set(file, ctx.exports);
  evaluate(fs.readFileSync(base + file, 'utf8'), ctx);
  return ctx.exports;
}
const service = load('services/UserBehaviorService.ts').UserBehaviorService;
const feedback = load('api/FeedbackService.ts');
const params = { bvid: 'BV1234567890', aid: 123, action: 'add' };
const form = call => Object.fromEntries(new URLSearchParams(call.options.extraData));
function reset(key = '') {
  store.clear(); store.set('biliCookie', cookie); if (key) store.set('biliAccessKey', key);
  calls.length = 0; destroys = 0; refresh = async () => ''; reply = async () => ({ code: 0 });
  feedback.FeedbackService.getInstance().clearCache();
}
(async () => {
  for (const type of ['like', 'coin']) {
    reset();
    assert.equal(await service.reportInteraction({ ...params, type }), true);
    assert.equal(calls.length, 1, 'Cookie-only session must reach Web API');
    assert.match(calls[0].url, type === 'like' ? /archive\/like$/ : /coin\/add$/);
    assert.equal(form(calls[0]).aid, '123');
    assert.equal(calls[0].options.header.Cookie.match(/buvid3=/g).length, 1);
    assert.match(calls[0].options.header.Cookie, /buvid3=real-device/);
    if (type === 'like') assert.equal(form(calls[0]).like, '1');
    reset(); refresh = async () => 'new-key';
    assert.equal(await service.reportInteraction({ ...params, type }), true);
    assert.match(calls[0].url, /app\.bilibili\.com/);
    if (type === 'like') assert.equal(form(calls[0]).like, '0', 'App add differs from Web add');
    reset(); refresh = async () => { store.set('biliCookie', 'other-session'); return 'new-key'; };
    assert.equal(await service.reportInteraction({ ...params, type }), false);
    assert.equal(calls.length, 0, 'account switch cancels old mutation');
  }
  reset('app-key');
  await service.reportInteraction({ ...params, type: 'like', action: 'cancel' });
  assert.equal(form(calls[0]).like, '1');
  reset('app-key');
  for (const [action, value] of [['add', '0'], ['cancel', '1']]) {
    assert.equal(await service.reportInteraction({ ...params, type: 'dislike', action }), true);
    assert.match(calls.at(-1).url, /\/x\/v2\/view\/dislike$/);
    assert.equal(form(calls.at(-1)).dislike, value);
  }
  reset();
  assert.match((await service.performInteraction({ ...params, type: 'dislike' })).message, /令牌/);
  assert.equal(calls.length, 0, 'missing App credential must not call feed dislike or a nonexistent Web fallback');
  reset('app-key'); reply = async () => ({ code: -104, message: '硬币不足' });
  assert.match((await service.performInteraction({ ...params, type: 'coin' })).message, /硬币不足/);
  assert.equal(calls.length, 1, 'business rejection must not repeat a coin');
  reset('app-key'); reply = async () => { throw Error('timeout'); };
  assert.equal((await service.performInteraction({ ...params, type: 'coin' })).success, false);
  assert.equal(calls.length, 1); assert.equal(destroys, 1, 'timeout releases handle without a second coin');
  reset();
  assert.equal((await service.performInteraction({ ...params, type: 'coin' })).success, true);
  assert.equal((await service.performInteraction({ ...params, aid: 456, type: 'coin' })).success, true);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.header.Cookie, calls[1].options.header.Cookie, 'consecutive coins reuse device identity');
  assert.equal(calls[0].options.header['User-Agent'], calls[1].options.header['User-Agent']);
  assert.ok(!calls[1].options.header.Cookie.includes('buvid_fp='), 'never synthesize fingerprint cookies');
  reset('expired-key'); reply = async url => ({ code: url.includes('app.bilibili.com') ? -101 : 0 });
  assert.equal(await service.reportInteraction({ ...params, type: 'like' }), true);
  assert.equal(calls.length, 2); assert.equal(form(calls[0]).like, '0'); assert.equal(form(calls[1]).like, '1');
  reset(); reply = async url => url.includes('list-all') ? { code: 0, data: { list: [
    { id: 10, fav_state: 0 }, { id: 20, fav_state: 1 }, { id: 30, fav_state: 1 }
  ] } } : { code: 0 };
  assert.equal(await service.reportInteraction({ ...params, type: 'favorite', action: 'cancel' }), true);
  assert.equal(form(calls[1]).del_media_ids, '20,30', 'cancel uses folders actually containing the video');
  assert.equal(form(calls[1]).resources, '123:2');
  assert.equal(form(calls[1]).rid, undefined, 'batch-deal uses resources, unlike resource/deal');
  reset(); reply = async () => ({ code: 0, data: { like: true, coin: false, fav: true, multiply: 0 } });
  const triple = await service.performInteraction({ ...params, type: 'triple' });
  assert.equal(triple.success, true); assert.equal(triple.triple.coin, false);
  assert.match(triple.message, /部分/); assert.equal(calls.length, 1, 'triple does not require App-key or a folder lookup');
  reset('app-key');
  assert.equal(await service.reportInteraction({ ...params, type: 'coin', multiply: 3 }), false);
  assert.equal(calls.length, 0);

  // Exercise the real compiled feedback path with both App AV ids and Web BV ids.
  for (const id of ['123', 'BV1234567890']) {
    reset('app-key');
    assert.equal((await feedback.sendDislikeFeedback(id)).success, true);
    const url = new URL(calls[0].url);
    assert.equal(url.searchParams.get('id'), '123'); assert.equal(url.searchParams.get('goto'), 'av');
    assert.ok(url.searchParams.get('sign')); assert.equal(destroys, 1);
  }
  reset();
  assert.equal((await feedback.sendDislikeFeedback('123')).success, false);
  assert.equal(calls.length, 0, 'no calls to retired index/feed-back');
  reset('app-key'); let finish;
  reply = () => new Promise(r => { finish = r; });
  const f1 = feedback.sendDislikeFeedback('123'); const f2 = feedback.sendDislikeFeedback('123');
  await new Promise(r => setImmediate(r)); assert.equal(calls.length, 1);
  finish({ code: 0 }); await Promise.all([f1, f2]);
  await feedback.sendDislikeFeedback('123'); assert.equal(calls.length, 1, 'cache applies within one account');
  store.set('biliCookie', cookie.replace('123', '456')); reply = async () => ({ code: 0 });
  await feedback.sendDislikeFeedback('123'); assert.equal(calls.length, 2, 'account change invalidates feedback cache');

  reset();
  const favorites = load('api/FavoritesApi.ts');
  assert.equal(await favorites.batchDealFavResource(123, 2, '10', ''), true);
  assert.equal(form(calls[0]).resources, '123:2', 'shared favorites API must use batch-deal resources too');

  const apiText = fs.readFileSync(base + 'api/BilibiliApi.ts', 'utf8');
  const apiAst = ts.createSourceFile('api.ts', apiText, ts.ScriptTarget.Latest, true);
  const stateFunction = apiAst.statements.find(node => ts.isFunctionDeclaration(node) && node.name?.text === 'getVideoUserStatus');
  assert.ok(stateFunction);
  const stateCtx = { exports: {}, http, AppStorage: shared, ...logger,
    getLoginAccessKey: async () => store.get('biliAccessKey') || '',
    getCookieHeader: () => store.get('biliCookie'), getBiliMid: () => '123',
    AppSign: { signParams: async () => {} } };
  evaluate(stateFunction.getText(apiAst), stateCtx);
  reset('app-key');
  reply = async () => ({ code: 0, data: { req_user: { like: 0, dislike: 1, coin: 2, favorite: 1 } } });
  const state = await stateCtx.exports.getVideoUserStatus('BV1234567890', 123);
  assert.equal(state.like, false); assert.equal(state.dislike, true); assert.equal(state.coin, 2); assert.equal(state.favorite, true);
  assert.equal(calls.length, 1, 'App state restores dislike on re-entry'); assert.equal(destroys, 1);
  reset();
  reply = async url => ({ code: 0, data: url.includes('has/like') ? 1 : url.includes('archive/coins') ? { multiply: 1 } : { favoured: true } });
  const webState = await stateCtx.exports.getVideoUserStatus('123', 123);
  assert.equal(webState.like, true); assert.equal(webState.coin, 1); assert.equal(webState.favorite, true);
  assert.match(calls[0].url, /has\/like\?aid=123$/);

  // The adjacent comment, dynamic and relationship APIs have different action enums.
  const adjacent = new Set(['setCommentLike', 'setCommentDislike', 'setCommentLikeByType', 'setDynCommentLike',
    'setDynamicLike', 'modifyRelation', 'modifyFollow', 'blacklistUploader', 'unblacklistUploader']);
  stateCtx.extractCsrfFromCookie = feedback.extractCsrfFromCookie;
  evaluate(apiAst.statements.filter(node => ts.isFunctionDeclaration(node) && adjacent.has(node.name?.text))
    .map(node => node.getText(apiAst)).join('\n'), stateCtx);
  const adjacentApi = stateCtx.exports;
  for (const enabled of [true, false]) {
    reset();
    assert.equal((await adjacentApi.setCommentLike(123, 456, enabled)).ok, true);
    assert.equal(form(calls.at(-1)).action, enabled ? '1' : '0');
    assert.match(calls.at(-1).url, /reply\/action$/);
    assert.equal((await adjacentApi.setCommentDislike(123, 456, enabled)).ok, true);
    assert.match(calls.at(-1).url, /reply\/hate$/);
    assert.equal(form(calls.at(-1)).action, enabled ? '1' : '0');
    assert.equal((await adjacentApi.setDynamicLike('1234567890123456789', enabled)).ok, true);
    assert.equal(JSON.parse(calls.at(-1).options.extraData).up, enabled ? 1 : 2);
    assert.equal((await adjacentApi.setDynCommentLike('1234567890123456789', 456, enabled)).ok, true);
    assert.equal(form(calls.at(-1)).oid, '1234567890123456789', 'dynamic comment ids retain full precision');
  }
  for (const act of [1, 2, 5, 6]) {
    reset(); assert.equal(await adjacentApi.modifyRelation(789, act), true);
    assert.equal(form(calls[0]).fid, '789'); assert.equal(form(calls[0]).act, String(act));
  }
  reset(); reply = async () => ({ code: -111, message: 'csrf rejected' });
  assert.equal((await adjacentApi.setCommentLike(123, 456, true)).ok, false);
  assert.equal((await adjacentApi.setDynamicLike('1234567890123456789', true)).ok, false);
  assert.equal(await adjacentApi.blacklistUploader(789), false);
  assert.equal(destroys, calls.length, 'all adjacent requests release handles on business rejection');

  const source = fs.readFileSync(base + 'pages/VideoPlayerPage.ts', 'utf8');
  const ast = ts.createSourceFile('page.ts', source, ts.ScriptTarget.Latest, true);
  let restoreBranch;
  function findRestore(node) {
    if (ts.isIfStatement(node) && node.expression.getText(ast) === 'interactionRevision === this.interactionRevision' &&
        node.getText(ast).includes('if (d.req_user')) restoreBranch = node;
    ts.forEachChild(node, findRestore);
  }
  findRestore(ast); assert.ok(restoreBranch);
  let stateReads = 0;
  const restoreCtx = { exports: {}, interactionRevision: 2, requestedBvid: params.bvid, requestedGeneration: 1,
    d: { aid: 123, req_user: { like: 0, coin: 0, favorite: 0 } },
    getVideoUserStatus: async () => { stateReads++; return { like: false, dislike: true, coin: 0, favorite: false }; }
  };
  evaluate('exports.restore = async function() { ' + restoreBranch.getText(ast) + ' };', restoreCtx);
  const restoring = { referenceAlive: true, vi: { bvid: params.bvid }, referenceSwitchGeneration: 1, interactionRevision: 2 };
  await restoreCtx.exports.restore.call(restoring);
  assert.equal(restoring.isDisliked, true, 'Web req_user without dislike must fetch App state'); assert.equal(stateReads, 1);
  restoreCtx.d.req_user.dislike = false;
  await restoreCtx.exports.restore.call(restoring); assert.equal(restoring.isDisliked, false); assert.equal(stateReads, 1);
  restoring.interactionRevision++;
  await restoreCtx.exports.restore.call(restoring); assert.equal(stateReads, 1, 'late initial state cannot replace new interaction');
  const wanted = new Set(['toggleLike', 'toggleCoin', 'toggleFavorite', 'tripleAction', 'runVideoInteraction', 'referenceDislike', 'toggleFollow']);
  const methods = [];
  function visit(node) {
    if (ts.isMethodDeclaration(node) && wanted.has(node.name?.getText(ast))) methods.push(node.getText(ast));
    else ts.forEachChild(node, visit);
  }
  visit(ast); assert.equal(methods.length, wanted.size);
  let resolve, requests = 0;
  const messages = [];
  const playerCtx = { exports: {}, AppStorage: shared, setTimeout: () => 0,
    UserBehaviorService: { performInteraction: () => { requests++; return new Promise(r => { resolve = r; }); } },
    VibrateUtils: { vibrateTime() {} }, ...logger };
  evaluate('exports.Player = class { ' + methods.join('\n') + ' };', playerCtx);
  const p = new playerCtx.exports.Player();
  Object.assign(p, { vd: { aid: 123 }, vi: { bvid: params.bvid }, interactionPending: new Set(),
    referenceSwitchGeneration: 1, referenceAlive: true, interactionRevision: 0, isLiked: false, isDisliked: false, likeCount: 10,
    isCoined: false, coinCount: 20, isFavorited: false, favoriteCount: 30,
    getUIContext: () => ({ getPromptAction: () => ({ showToast: m => messages.push(m.message) }) }) });
  const first = p.toggleLike(); await p.toggleLike(); await p.toggleFavorite();
  assert.equal(requests, 1); resolve({ success: false, message: 'error' }); await first;
  assert.equal(p.likeCount, 10); assert.equal(p.isLiked, false);
  p.isLiked = true;
  const dislike = p.referenceDislike(); assert.equal(p.isDisliked, true); assert.equal(p.isLiked, false);
  resolve({ success: false, message: 'TV' }); await dislike;
  assert.equal(p.isDisliked, false); assert.equal(p.isLiked, true); assert.equal(p.likeCount, 10);
  const favorite = p.toggleFavorite(); resolve({ success: false, message: '收藏失败' }); await favorite;
  assert.equal(p.isFavorited, false); assert.equal(p.favoriteCount, 30); assert.equal(messages.at(-1), '收藏失败');
  const partial = p.tripleAction(); resolve(triple); await partial;
  assert.equal(p.likeCount, 10, 'already liked does not increment');
  assert.equal(p.coinCount, 20, 'failed coin stays unchanged'); assert.equal(p.favoriteCount, 31);
  const second = p.toggleCoin(); p.vi = { bvid: 'BV0987654321' }; p.referenceSwitchGeneration++; p.coinCount = 99;
  resolve({ success: false, message: 'old error' }); await second;
  assert.equal(p.coinCount, 99); assert.equal(p.interactionPending.size, 0);
  console.log('PASS: compiled interactions, App/Web values, dislike toggles, credential and account guards, feedback AV/BV/cache, favorite rollback, partial triple and timeout safety.');
})().catch(error => { console.error(error); process.exitCode = 1; });
