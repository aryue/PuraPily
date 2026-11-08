const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/TvQrAuthorization.ts';
const store = new Map(), timers = new Map(), saves = [];
const codes = { SUCCESS: 0, ERROR: -1, EXPIRED: 86038, NOT_SCANNED: 86101, SCANNED: 86090 };
let now = 100000, revision = 0, tickId = 0, resolvePoll;
let poll = () => new Promise(resolve => { resolvePoll = resolve; });
const context = { exports: {}, AppStorage: { get: key => store.get(key), setOrCreate: (key, value) => store.set(key, value) },
  Date: { now: () => now }, setInterval: cb => { timers.set(++tickId, cb); return tickId; }, clearInterval: id => timers.delete(id),
  require: name => {
    if (name.includes('BilibiliApi')) return { QrCodeStatus: codes, pollTvQrCodeStatusApi: () => poll() };
    if (name.includes('LoginCookie')) return { hasLoginSession: cookie => cookie.includes('SESSDATA='), mergeLoginCookies: values => values.join('; ') };
    if (name.includes('CredentialStore')) return { loginCredentialRevision: () => revision,
      saveLoginCredentials: async (ctx, cookie, key, required, expected) => {
        assert.equal(expected, revision); assert.equal(required, true); revision++;
        saves.push({ cookie, key }); store.set('biliAccessKey', key);
      } };
    return { logWarn() {} };
  }
};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const auth = context.exports.TvQrAuthorization;
const flush = () => new Promise(resolve => setImmediate(resolve));
const approved = () => ({ status: codes.SUCCESS, cookies: 'SESSDATA=tv-session; DedeUserID=123', accessKey: 'tv-client-key' });
(async () => {
  let events = [];
  const first = auth.begin({}, 'qr-ticket', state => events.push(state));
  auth.detach(first); // User returns from the QR page before the next poll completes.
  const before = events.length;
  resolvePoll(approved()); await flush();
  assert.equal(saves.length, 1); assert.equal(store.get('biliAccessKey'), 'tv-client-key');
  assert.equal(store.get('refreshHomeFlag'), 1); assert.equal(store.get('biliTvAuthorizationStatus'), 'success');
  assert.equal(events.length, before, 'closed page must never receive an asynchronous UI callback');
  assert.equal(timers.size, 0);

  const loggedOut = auth.begin({}, 'qr-ticket', () => {});
  revision++; store.set('biliAccessKey', '');
  resolvePoll(approved()); await flush();
  assert.equal(saves.length, 1, 'logout or a new account rejects a late TV response');
  assert.equal(store.get('biliAccessKey'), ''); auth.cancel(loggedOut);

  const old = auth.begin({}, 'old-ticket', () => {}); const oldReply = resolvePoll;
  const replacement = auth.begin({}, 'new-ticket', () => {});
  oldReply(approved()); await flush(); assert.equal(saves.length, 1, 'new QR supersedes the old response');
  resolvePoll(approved()); await flush(); assert.equal(saves.length, 2);

  events = [];
  const expiring = auth.begin({}, 'expires', state => events.push(state));
  now += 181000;
  for (const tick of [...timers.values()]) tick();
  resolvePoll({ status: codes.SCANNED, cookies: '' }); await flush();
  assert.equal(events.at(-1).status, codes.EXPIRED); assert.equal(timers.size, 0);
  assert.equal(saves.length, 2, 'late scanned state never revives expired authorization');

  events = [];
  auth.begin({}, 'incomplete', state => events.push(state));
  resolvePoll({ status: codes.SUCCESS, cookies: '', accessKey: 'key' }); await flush();
  assert.equal(events.at(-1).status, codes.ERROR); assert.equal(saves.length, 2);
  console.log('PASS: compiled TV authorization survives page return, detaches UI, saves approved token, rejects logout/replacement, expires and rejects incomplete replies.');
})().catch(error => { console.error(error); process.exitCode = 1; });
