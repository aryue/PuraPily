const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = process.argv.includes('--compiled');
const root = path.resolve(__dirname, compiled
  ? '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets'
  : '../entry/src/main/ets');
function evaluate(source, globals = {}) {
  const context = { exports: {}, ...globals };
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
const cookie = evaluate(fs.readFileSync(path.join(root, 'utils/LoginCookie' + (compiled ? '.ts' : '.ets')), 'utf8'));
const policy = evaluate(fs.readFileSync(path.join(root, 'utils/LoginUrlPolicy.ts'), 'utf8'));
const source = fs.readFileSync(path.join(root, 'api/BilibiliApi' + (compiled ? '.ts' : '.ets')), 'utf8');
function fn(name) {
  const start = source.indexOf('async function ' + name + '(') >= 0
    ? source.indexOf('async function ' + name + '(') : source.indexOf('function ' + name + '(');
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n}', start) + 2);
}
const calls = [];
let responses = [], destroyed = 0;
const flow = evaluate(`const QrCodeStatus = { SUCCESS: 0, NOT_SCANNED: 86101 };
${fn('pollQrCodeStatusApi')}
${fn('fetchCookiesFromCrossDomain')}
${fn('parseCookiesFromUrl')}
exports.poll = pollQrCodeStatusApi; exports.redeem = fetchCookiesFromCrossDomain;`, {
  ...cookie, ...policy, logInfo() {}, logWarn() {}, logError() {},
  http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
    async request(url, options) {
      calls.push({ url, options });
      assert.ok(responses.length, 'no unexpected request');
      return responses.shift();
    }, destroy() { destroyed++; }
  }) }
});
const response = (code, header = {}, cookies = '', result = '') => ({ responseCode: code, header, cookies, result });
function pollBody(url) { return JSON.stringify({ code: 0, data: { code: 0, url } }); }
async function main() {
  assert.equal(policy.isBilibiliHttpsUrl('https://passport.biligame.com/crossDomain'), false,
    'do not broaden the ordinary WebView trust policy');
  assert.equal(policy.isLoginRedirectUrl('https://passport.biligame.com/x/passport-login/web/crossDomain?ticket=test'), true);
  for (const url of ['https://biligame.com/', 'https://passport.biligame.com.evil.test/',
    'https://evil.test/?next=https://passport.biligame.com/', 'https://passport.biligame.com@evil.test/',
    'http://passport.biligame.com/', 'https://passport.biligame.com:8443/']) {
    assert.equal(policy.isLoginRedirectUrl(url), false, url);
  }
  // Real failure shape: successful poll has a biligame ticket, no session in URL.
  // Session is on an intermediate redirect, CSRF arrives at the following hop.
  responses = [response(200, {}, 'buvid3=device', pollBody('https://passport.biligame.com/x/passport-login/web/crossDomain?ticket=test')),
    response(302, { 'sEt-CoOkIe': ['SESSDATA=session%2Ctoken; HttpOnly; Path=/'],
      'Location': 'https://passport.bilibili.com/crossDomain?ticket=next' }, 'buvid3=device'),
    response(302, { 'Set-Cookie': ['bili_jct=csrf; Secure', 'DedeUserID=123; Path=/'],
      'location': 'https://unrelated.test/' })];
  const result = await flow.poll('test-key', 'initial=device');
  assert.equal(result.status, 0);
  assert.ok(result.cookies.includes('SESSDATA=session%2Ctoken'));
  assert.ok(result.cookies.includes('bili_jct=csrf'));
  assert.ok(result.cookies.includes('DedeUserID=123'));
  assert.equal(calls.length, 3, 'never follow unrelated final destinations');
  assert.equal(calls[1].options.maxRedirects, 0);
  assert.ok(calls[2].options.header.Cookie.includes('SESSDATA=session%2Ctoken'));
  assert.equal(destroyed, 3, 'all request resources must be released');

  calls.length = 0;
  responses = [response(200, { 'SET-COOKIE': ['SESSDATA=poll-session; Path=/', 'bili_jct=csrf; Secure'] },
    'buvid3=device', pollBody('https://passport.biligame.com/crossDomain?ticket=unused'))];
  assert.ok((await flow.poll('header-key')).cookies.includes('SESSDATA=poll-session'));
  assert.equal(calls.length, 1, 'read poll response headers even when native cookies are nonempty');

  calls.length = 0;
  responses = [response(200, {}, '', pollBody('https://passport.biligame.com/crossDomain?SESSDATA=legacy%2Ctoken&bili_jct=old'))];
  assert.ok((await flow.poll('legacy-key')).cookies.includes('SESSDATA=legacy%2Ctoken'));
  assert.equal(calls.length, 1, 'legacy QR format still works without redeeming a ticket');

  calls.length = 0;
  responses = [response(302, { Location: 'https://passport.biligame.com.evil.test/' })];
  await assert.rejects(flow.redeem('https://passport.biligame.com/crossDomain'), /不可信/);
  assert.equal(calls.length, 1, 'untrusted redirect is rejected before sending credentials');
  calls.length = 0;
  responses = [response(302, { Location: '/next', 'set-cookie': 'buvid3=first' }),
    response(200, { 'set-cookie': 'SESSDATA=relative; HttpOnly' })];
  assert.ok((await flow.redeem('https://passport.biligame.com/crossDomain')).includes('SESSDATA=relative'));
  assert.equal(calls[1].url, 'https://passport.biligame.com/next');
  console.log('PASS: actual QR poll/ticket redemption, biligame passport, intermediate cookies, header casing/arrays, legacy URLs, relative redirects and host validation');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
