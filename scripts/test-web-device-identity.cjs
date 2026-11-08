const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const prefValues = new Map();
let calls = 0, destroys = 0, fail = false;
const pref = { get: async (k, value) => prefValues.get(k) || value,
  put: async (k, value) => prefValues.set(k, value), flush: async () => {} };
function evaluate(file, require) {
  const context = { exports: {}, AppStorage: { get: () => ({}) }, require };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(base + file + '.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
const cookies = evaluate('utils/LoginCookie', () => ({}));
function load() {
  return evaluate('services/WebDeviceIdentity', name => {
    if (name.includes('LoginCookie')) return cookies;
    if (name.includes('data.preferences')) return { default: { getPreferences: async () => pref } };
    if (name.includes('net.http')) return { default: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
      request: async (url, options) => {
        calls++; assert.ok(url.endsWith('/x/frontend/finger/spi'));
        assert.equal(options.header.Cookie, undefined, 'device request never sends account credentials');
        if (fail) throw Error('offline');
        return { responseCode: 200, result: JSON.stringify({ code: 0, data: { b_3: 'server-device', b_4: 'server-device4==' } }) };
      }, destroy: () => destroys++
    }) } };
    throw Error(name);
  });
}
(async () => {
  let device = load();
  const cookie = 'SESSDATA=one; bili_jct=csrf; DedeUserID=123';
  const [first, second] = await Promise.all([device.webInteractionCookie(cookie), device.webInteractionCookie(cookie)]);
  assert.equal(first, second); assert.equal(calls, 1); assert.equal(destroys, 1);
  assert.match(first, /buvid3=server-device/); assert.match(first, /buvid4=server-device4==/);
  assert.equal(await device.webInteractionCookie(cookie), first); assert.equal(calls, 1);
  device = load(); assert.equal(await device.webInteractionCookie(cookie), first);
  assert.equal(calls, 1, 'process restart uses the persisted server ID');
  const existing = cookie + '; buvid3=login-device; buvid4=login-device4';
  assert.equal(await device.webInteractionCookie(existing), existing, 'login-issued device fields remain intact');
  const other = await device.webInteractionCookie('SESSDATA=two; DedeUserID=456');
  assert.ok(!other.includes('SESSDATA=one')); assert.match(other, /buvid3=server-device/);
  prefValues.clear(); device = load(); fail = true;
  await assert.rejects(device.webInteractionCookie(cookie), /offline/);
  assert.equal(destroys, 2); fail = false;
  await device.webInteractionCookie(cookie); assert.equal(calls, 3, 'failed acquisition can retry without fake fingerprints');
  console.log('PASS: compiled Web device identity shares concurrent acquisition, persists across restart, preserves login cookies, isolates accounts and retries failures without fabricating identifiers.');
})().catch(error => { console.error(error); process.exitCode = 1; });
