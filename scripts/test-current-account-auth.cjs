const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/CurrentAccountAuthorization.ts';
const cookie = 'SESSDATA=existing; bili_jct=csrf; DedeUserID=123';
let revision, activeCookie, confirmedCode, pollResult, onConfirm, requestCount, destroyed, polls, saves;
const codes = { SUCCESS: 0, ERROR: -1, EXPIRED: 86038, NOT_SCANNED: 86101 };
const reset = () => {
  revision = 1; activeCookie = cookie; confirmedCode = 0; requestCount = destroyed = polls = 0; saves = [];
  pollResult = { status: 0, accessKey: 'client-key', cookies: 'SESSDATA=new; DedeUserID=123' };
  onConfirm = () => {};
};
const context = { exports: {}, AppStorage: {
  get: key => key === 'biliCookie' ? activeCookie : 0, setOrCreate() {}
}, setTimeout: resolve => resolve(), require: name => {
  if (name.includes('net.http')) return { default: { RequestMethod: { POST: 'POST' }, createHttp: () => ({
    request: async (url, options) => {
      requestCount++; assert.ok(url.endsWith('/h5/qrcode/confirm'));
      assert.equal(options.header.Cookie, cookie); assert.ok(options.header['User-Agent'].includes('BiliDroid/'));
      assert.ok(options.extraData.includes('csrf=csrf')); onConfirm();
      return { responseCode: 200, result: JSON.stringify({ code: confirmedCode }) };
    }, destroy: () => destroyed++
  }) } };
  if (name.includes('BilibiliApi')) return { QrCodeStatus: codes,
    generateTvLoginQrCode: async () => ({ qrcode_key: 'ticket', url: 'https://passport.bilibili.com/ticket' }),
    pollTvQrCodeStatusApi: async () => { polls++; return pollResult; }
  };
  if (name.includes('CredentialStore')) return { loginCredentialRevision: () => revision,
    saveLoginCredentials: async (ctx, original, key, required, expected) => {
      assert.equal(original, cookie); assert.equal(required, true); assert.equal(expected, revision);
      saves.push(key); revision++;
    }
  };
  return { hasLoginSession: value => value.includes('SESSDATA=') };
} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const authorize = () => context.exports.authorizeCurrentAccount({}, cookie);
(async () => {
  reset(); await authorize(); assert.deepEqual(saves, ['client-key']); assert.equal(destroyed, 1);
  reset(); confirmedCode = 86096;
  await assert.rejects(authorize(), /86096/); assert.equal(polls, 0); assert.equal(saves.length, 0); assert.equal(destroyed, 1);
  reset(); onConfirm = () => { revision++; activeCookie = 'SESSDATA=other'; };
  await assert.rejects(authorize(), /账号已变化/); assert.equal(polls, 0); assert.equal(saves.length, 0);
  reset(); pollResult.cookies = 'DedeUserID=456';
  await assert.rejects(authorize(), /账号校验/); assert.equal(saves.length, 0);
  reset(); pollResult = { status: codes.NOT_SCANNED };
  await assert.rejects(authorize(), /暂未收到/); assert.equal(polls, 5); assert.equal(saves.length, 0);
  reset(); activeCookie = '';
  await assert.rejects(authorize(), /账号已变化/); assert.equal(requestCount, 0);
  const page = fs.readFileSync('entry/src/main/ets/pages/QrCodeLoginPage.ets', 'utf8');
  assert.ok(page.indexOf('if (choice.index !== 1') < page.indexOf('await authorizeCurrentAccount(context, cookie)'));
  assert.ok(page.includes("{ text: '确认授权'"));
  console.log('PASS: compiled explicit client authorization preserves Cookie, rejects denied/mismatched/stale authorization, bounds polling and gates UI confirmation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
