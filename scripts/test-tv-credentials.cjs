const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const storage = new Map(), secrets = new Map(), prefs = new Map(), requests = [];
const AppStorage = { get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) };
const logger = { logInfo() {}, logWarn() {}, logError() {} };
function evaluate(source, globals = {}) {
  const ctx = { exports: {}, AppStorage, ...globals };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, ctx);
  return ctx.exports;
}
const text = file => fs.readFileSync(base + file + '.ts', 'utf8');
const Tag = Object.fromEntries(['ALIAS', 'RETURN_TYPE', 'SECRET', 'ACCESSIBILITY', 'SYNC_TYPE', 'CONFLICT_RESOLUTION'].map(key => [key, key]));
const alias = value => new TextDecoder().decode(value.get(Tag.ALIAS));
const asset = { Tag, ReturnType: { ALL: 1 }, Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, SyncType: { NEVER: 0 }, ConflictResolution: { OVERWRITE: 1 },
  query: async q => secrets.has(alias(q)) ? [new Map([[Tag.SECRET, secrets.get(alias(q))]])] : [],
  add: async q => { secrets.set(alias(q), q.get(Tag.SECRET)); }, remove: async q => secrets.delete(alias(q)) };
let uuid = 0;
const util = { TextEncoder: class { encodeInto(s) { return new TextEncoder().encode(s); } },
  TextDecoder: { create: () => ({ decodeWithStream: bytes => new TextDecoder().decode(bytes) }) }, generateRandomUUID: () => String(++uuid) };
const pref = { get: async (key, fallback) => prefs.has(key) ? prefs.get(key) : fallback,
  put: async (key, value) => prefs.set(key, value), delete: async key => prefs.delete(key), flush: async () => {} };
const credentials = evaluate(text('utils/CredentialStore'), { require: name => {
  if (name.includes('security.asset')) return { default: asset };
  if (name.includes('data.preferences')) return { default: { getPreferences: async () => pref } };
  if (name.includes('util')) return { default: util };
  return {};
} });
const cookies = evaluate(text('utils/LoginCookie'));
const session = 'SESSDATA=tv-session; bili_jct=abc123; DedeUserID=123';
const AppSign = { signParams: async (params, platform) => { assert.equal(platform, 'android_hd'); params.sign = 'test-signature'; } };
let nextResponse;
const http = { RequestMethod: { GET: 'GET', POST: 'POST' }, createHttp: () => ({
  request: async (url, options) => { requests.push({ url, options }); return nextResponse; }, destroy() {} }) };
function functions(file, names) {
  const source = text(file), ast = ts.createSourceFile(file + '.ts', source, ts.ScriptTarget.Latest, true);
  return ast.statements.filter(node => ts.isFunctionDeclaration(node) && names.includes(node.name?.text))
    .map(node => node.getText(ast)).join('\n');
}
const polling = evaluate(functions('api/BilibiliApi', ['pollTvQrCodeStatusApi', 'parseCookiesFromUrl']), {
  http, AppSign, ...cookies, ...logger, QrCodeStatus: { ERROR: -1, SUCCESS: 0, NOT_SCANNED: 86101, SCANNED: 86090, EXPIRED: 86038 }
});
const pageSource = text('pages/QrCodeLoginPage');
const pageAst = ts.createSourceFile('page.ts', pageSource, ts.ScriptTarget.Latest, true);
let loginMethod, appearMethod, generateMethod, pollMethod, expireMethod;
let now = 1000000, polls = 0, pagePollResult = { status: 86101, cookies: '' };
let pagePoll = async () => { polls++; return pagePollResult; };
let tvGenerated = 0;
function visit(node) {
  if (ts.isMethodDeclaration(node) && node.name?.getText(pageAst) === 'onLoginSuccess') loginMethod = node.getText(pageAst);
  else if (ts.isMethodDeclaration(node) && node.name?.getText(pageAst) === 'aboutToAppear') appearMethod = node.getText(pageAst);
  else if (ts.isMethodDeclaration(node) && node.name?.getText(pageAst) === 'generateQrCode') generateMethod = node.getText(pageAst);
  else if (ts.isMethodDeclaration(node) && node.name?.getText(pageAst) === 'doPoll') pollMethod = node.getText(pageAst);
  else if (ts.isMethodDeclaration(node) && node.name?.getText(pageAst) === 'onQrCodeExpired') expireMethod = node.getText(pageAst);
  else ts.forEachChild(node, visit);
}
visit(pageAst); assert.ok(loginMethod);
const Page = evaluate('exports.Page = class { ' + loginMethod + '\n' + appearMethod + '\n' + generateMethod + '\n' + pollMethod + '\n' + expireMethod + ' };', {
  TvQrAuthorization: { cancel() {}, begin: () => 1 },
  ...logger, ...cookies, ...credentials, setTimeout() {}, Date: { now: () => now },
  QrCodeStatus: { ERROR: -1, SUCCESS: 0, NOT_SCANNED: 86101, SCANNED: 86090, EXPIRED: 86038 },
  pollTvQrCodeStatusApi: () => pagePoll(),
  generateTvLoginQrCode: async () => { tvGenerated++; return { qrcode_key: 'tv-code', url: 'tv-url' }; },
  generateLoginQrCode: async () => { throw Error('TV repair must not generate a Web QR'); }, verifyLoginSession: async () => ({ state: 'authenticated' })
}).Page;
function page() {
  return Object.assign(new Page(), { isSuccess: false, loginProcessing: false, isTvMode: true, loginGeneration: 1, qrExpiresAt: now + 180000, lastPollAt: 0, pollInFlight: false,
    stopPolling() { this.isPolling = false; },
    getUIContext: () => ({ getHostContext: () => ({}), getPromptAction: () => ({ showToast() {} }) }) });
}
const interactions = evaluate(text('api/VideoInteractionApi'), { require: name => {
  if (name.includes('WebDeviceIdentity')) return { webInteractionCookie: async cookie => cookie, WEB_INTERACTION_UA: 'test' };
  if (name.includes('net.http')) return { default: http };
  if (name.includes('CredentialStore')) return credentials;
  if (name.includes('SignUtils')) return { AppSign };
  if (name.includes('Logger')) return logger;
  if (name.includes('BilibiliApi')) return { getVideoDetail: async () => ({ aid: 123 }), refreshAccessKeyFromCookie: async () => '' };
  if (name.includes('FeedbackService')) return {
    extractMidFromCookie: cookie => /DedeUserID=(\d+)/.exec(cookie)?.[1] || '0',
    extractCsrfFromCookie: cookie => /bili_jct=([^;]+)/.exec(cookie)?.[1] || ''
  };
  throw Error('Unexpected module ' + name);
} });
(async () => {
  const repair = page(); repair.loginGeneration = 0; repair.startPolling = () => {};
  repair.getUIContext = () => ({ getHostContext: () => ({}), getRouter: () => ({ getParams: () => ({ tvMode: true }) }) });
  await repair.aboutToAppear();
  assert.equal(tvGenerated, 1); assert.equal(repair.isTvMode, true); assert.equal(repair.qrContent, 'tv-url');
  for (const nested of [false, true]) {
    nextResponse = { responseCode: 200, header: {}, cookies: session, result: JSON.stringify({ code: 0,
      data: nested ? { token_info: { access_token: 'tv-client-key' } } : { access_token: 'tv-client-key' } }) };
    const poll = await polling.pollTvQrCodeStatusApi('auth-code');
    assert.equal(poll.status, 0); assert.equal(poll.accessKey, 'tv-client-key');
    const p = page(); await p.onLoginSuccess(poll.cookies, poll.accessKey);
    assert.equal(p.isSuccess, true, 'TV success must include a saved client credential');
    assert.equal(storage.get('biliAccessKey'), 'tv-client-key');
    // Reproduce the reported failure: Cookie exists, but the live access-key slot is empty.
    storage.set('biliAccessKey', '');
    requests.length = 0;
    nextResponse = { responseCode: 200, result: JSON.stringify({ code: 0 }) };
    for (const type of ['dislike', 'coin']) {
      const result = await interactions.sendVideoInteraction({ bvid: '123', aid: 123, type, action: 'add' }, session);
      assert.equal(result.success, true);
      assert.match(requests.at(-1).url, /app\.bilibili\.com/);
      assert.equal(new URLSearchParams(requests.at(-1).options.extraData).get('access_key'), 'tv-client-key');
    }
    assert.equal(storage.get('biliAccessKey'), 'tv-client-key', 'recover protected key before attempting Web requests');
    await credentials.restoreLoginCredentials({}); assert.equal(storage.get('biliAccessKey'), 'tv-client-key');
  }
  // Rejected or incomplete TV responses must not silently leave the page waiting forever.
  for (const response of [{ code: -3, message: 'API signature rejected' }, { code: 0, data: {} }]) {
    nextResponse = { responseCode: 200, header: {}, cookies: '', result: JSON.stringify(response) };
    const rejected = await polling.pollTvQrCodeStatusApi('auth-code');
    assert.equal(rejected.status, -1); assert.ok(rejected.message);
    pagePollResult = rejected;
    const p = page(); await p.doPoll();
    assert.equal(p.isExpired, true); assert.equal(p.statusText, 'TV 授权未完成');
    assert.equal(p.statusSubText, rejected.message);
  }
  const expired = page(); expired.qrExpiresAt = now - 1;
  const before = polls; await expired.doPoll();
  assert.equal(expired.isExpired, true); assert.equal(polls, before, 'expired QR must not keep polling');
  const late = page(); let finish;
  pagePoll = () => new Promise(resolve => { finish = resolve; });
  const pendingPoll = late.doPoll(); now += 181000; await late.doPoll();
  assert.equal(late.isExpired, true);
  finish({ status: 86090, cookies: '' }); await pendingPoll;
  assert.equal(late.statusText, '二维码已过期', 'late scanned response must not revive an expired QR');
  const pollForm = new URLSearchParams(requests.find(r => r.url.includes('qrcode/poll')).options.extraData);
  assert.equal(pollForm.has('platform'), false); assert.equal(pollForm.has('mobi_app'), false);

  const broken = page(); await broken.onLoginSuccess(session, '');
  assert.equal(broken.isSuccess, false); assert.match(broken.statusSubText, /令牌/);
  await assert.rejects(credentials.saveLoginCredentials({}, session, '', true), /令牌/);
  // A Web renewal for the same verified account retains TV capability.
  const renewal = 'SESSDATA=renewed-session; bili_jct=abc123; DedeUserID=123';
  await credentials.saveLoginCredentials({}, renewal, '');
  assert.equal(storage.get('biliAccessKey'), 'tv-client-key');
  storage.set('biliAccessKey', '');
  assert.equal(await credentials.getLoginAccessKey(renewal), 'tv-client-key');
  // An unrelated live Cookie can never borrow the previous account's token.
  storage.set('biliCookie', 'SESSDATA=other-session; DedeUserID=456'); storage.set('biliAccessKey', '');
  assert.equal(await credentials.getLoginAccessKey(storage.get('biliCookie')), '');
  await credentials.saveLoginCredentials({}, 'SESSDATA=other-session; DedeUserID=456', '');
  assert.equal(storage.get('biliAccessKey'), '');
  await credentials.saveLoginCredentials({}, session, 'tv-client-key', true);
  storage.set('biliAccessKey', '');
  const recovering = credentials.getLoginAccessKey(session);
  await credentials.clearLoginCredentials({});
  assert.equal(await recovering, ''); assert.equal(storage.get('biliAccessKey'), '');
  console.log('PASS: compiled TV poll -> login save -> protected-key recovery -> App dislike/coin, nested token, Web renewal, account isolation and logout.');
})().catch(error => { console.error(error); process.exitCode = 1; });
