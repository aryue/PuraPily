const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('D:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
function load(name, mocks = {}, sourceOnly = false) {
  const compiled = path.join(__dirname, '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets', name.replace(/\.ets$/, '.ts'));
  const source = process.argv.includes('--compiled') && !sourceOnly ? fs.readFileSync(compiled, 'utf8') : read(name);
  const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const exports = {};
  new Function('exports', 'require', 'AppStorage', js)(exports, id => {
    id = id.replace(/^@normalized:.*entry\/src\/main\/ets\//, '../').replace(/&$/, '');
    // CompileArkTS resolves kit imports into platform module imports.
    const resolved = {
      '@ohos:security.asset': mocks['@kit.AssetStoreKit']?.asset,
      '@ohos:util': mocks['@kit.ArkTS']?.util,
      '@ohos:data.preferences': mocks['@kit.ArkData']?.preferences,
      '@ohos:net.http': mocks['@kit.NetworkKit']?.http
    }[id];
    if (resolved) return { default: resolved };
    assert.ok(Object.hasOwn(mocks, id), 'unexpected dependency: ' + id);
    return mocks[id];
  }, appStorage);
  return exports;
}
const storage = new Map();
const appStorage = { setOrCreate: (key, value) => storage.set(key, value), get: key => storage.get(key) };
const { redactPrivateLog: redact } = load('utils/PrivacyLog.ts');
const { isBilibiliHttpsUrl: trusted } = load('utils/LoginUrlPolicy.ts');
for (const url of ['https://passport.bilibili.com/login', 'https://www.bilibili.com/', 'https://api.bilibili.com:443/x']) assert.equal(trusted(url), true);
for (const url of ['http://passport.bilibili.com/', 'https://evilbilibili.com/', 'https://bilibili.com.evil.invalid/',
  'https://bilibili.com@evil.invalid/', 'https://evil.invalid/?next=https://bilibili.com/', 'https://bilibili.com:8443/']) assert.equal(trusted(url), false, url);
for (const input of [
  'SESSDATA=credential-sentinel; bili_jct=csrf-sentinel',
  '{"access_token":"credential-sentinel","auth_code":"auth-sentinel"}',
  'qrcode_key=credential-sentinel',
  'Authorization: identify_v1 credential-sentinel',
  '初始Cookie=credential-sentinel; sid=private',
  'https://example.invalid/?data=credential-sentinel&x=private',
  'wss://example.invalid/sub?token=credential-sentinel'
]) {
  const output = redact(input);
  assert.ok(!/credential-sentinel|csrf-sentinel|auth-sentinel/.test(output), output);
  assert.equal(redact(output), output, 'exporting an already sanitized log is safe');
}
assert.equal(redact('HTTP 503; decode failed'), 'HTTP 503; decode failed');

const saved = new Map();
const prefData = new Map();
let assetFailure = false;
let failPart = -1;
let partWrites = 0;
let uuid = 0;
const Tag = Object.fromEntries(['ALIAS', 'SECRET', 'RETURN_TYPE', 'ACCESSIBILITY', 'SYNC_TYPE', 'IS_PERSISTENT', 'CONFLICT_RESOLUTION'].map(x => [x, x]));
const alias = query => new TextDecoder().decode(query.get(Tag.ALIAS));
const asset = {
  Tag, Accessibility: { DEVICE_FIRST_UNLOCKED: 1 }, SyncType: { NEVER: 0 },
  ReturnType: { ALL: 0 }, ConflictResolution: { OVERWRITE: 0 },
  async query(query) {
    if (assetFailure) throw { code: 24000001 };
    if (!saved.has(alias(query))) throw { code: 24000002 };
    return [new Map([[Tag.SECRET, saved.get(alias(query))]])];
  },
  async add(attributes) {
    const name = alias(attributes);
    if (assetFailure || (name !== 'bilibili.login.v1' && partWrites++ === failPart)) throw { code: 24000001 };
    assert.equal(attributes.get(Tag.SYNC_TYPE), 0, 'credentials must never sync to another device');
    assert.equal(attributes.has(Tag.IS_PERSISTENT), false, 'use default nonpersistent storage without requesting a privileged tag');
    assert.ok(attributes.get(Tag.SECRET).length <= 1024, 'respect Asset Store secret size limit');
    saved.set(name, attributes.get(Tag.SECRET));
  },
  async remove(query) { saved.delete(alias(query)); }
};
const pref = {
  async get(key, fallback) { return prefData.has(key) ? prefData.get(key) : fallback; },
  async put(key, value) { prefData.set(key, value); },
  async delete(key) { prefData.delete(key); }, async flush() {}
};
const credentials = load('utils/CredentialStore.ets', {
  '@kit.AssetStoreKit': { asset },
  '@kit.ArkTS': { util: { TextEncoder: class { encodeInto(s) { return new TextEncoder().encode(s); } },
    TextDecoder: { create: () => ({ decodeWithStream: bytes => new TextDecoder().decode(bytes) }) }, generateRandomUUID: () => 'revision' + ++uuid } },
  '@kit.ArkData': { preferences: { getPreferences: async () => pref } }
});
async function run() {
  // Migrate a long UTF-8 cookie across several 1024-byte assets without splitting decoded strings.
  const cookie = 'SESSDATA=test-session; extra=' + '长'.repeat(1700);
  prefData.set('biliCookie', cookie); prefData.set('biliAccessKey', 'mobile-session');
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliCookie'), cookie);
  assert.equal(storage.get('biliAccessKey'), 'mobile-session');
  assert.equal(prefData.has('biliCookie'), false);
  assert.equal(prefData.has('biliAccessKey'), false);
  storage.clear();
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliCookie'), cookie, 'cold restart restores the full cookie');

  // A partial replacement must retain the previously committed credential pair.
  partWrites = 0; failPart = 1;
  await assert.rejects(credentials.saveLoginCredentials({}, 'SESSDATA=new;' + 'x'.repeat(2500), 'new-mobile'));
  failPart = -1;
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliCookie'), cookie);
  assert.equal(storage.get('biliAccessKey'), 'mobile-session');

  // Logout must clear both live values immediately and survive a failed asset operation on disk.
  assetFailure = true;
  const clearing = credentials.clearLoginCredentials({});
  assert.equal(storage.get('biliCookie'), '');
  assert.equal(storage.get('biliAccessKey'), '');
  await assert.rejects(clearing);
  assetFailure = false; storage.clear();
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliCookie'), '');
  assert.equal(storage.get('biliAccessKey'), '');
  await credentials.saveLoginCredentials({}, 'SESSDATA=web-only', '');
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliAccessKey'), '', 'Web login must not reuse an old mobile token');

  // A queued restore/save followed by logout cannot republish credentials after logout completes.
  await Promise.all([credentials.restoreLoginCredentials({}), credentials.clearLoginCredentials({})]);
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliCookie'), '');
  assert.equal(storage.get('biliAccessKey'), '');

  saved.clear(); prefData.clear(); storage.clear();
  prefData.set('biliCookie', 'SESSDATA=legacy'); prefData.set('biliAccessKey', 'legacy-mobile');
  assetFailure = true;
  await assert.rejects(credentials.restoreLoginCredentials({}));
  assert.equal(storage.has('biliCookie'), false, 'never activate plaintext credentials on a migration failure');
  assert.equal(prefData.get('biliCookie'), 'SESSDATA=legacy', 'allow retry after secure storage recovers');
  assetFailure = false;
  await credentials.restoreLoginCredentials({});
  assert.equal(prefData.has('biliCookie'), false);

  saved.clear(); prefData.clear(); storage.clear();
  prefData.set('biliAccessKey', 'orphaned-mobile');
  await credentials.restoreLoginCredentials({});
  assert.equal(storage.get('biliAccessKey'), '', 'do not resurrect an old incomplete logout');

  // These boundaries must stay closed regardless of caller-supplied cookies.
  for (const name of ['services/DashProbe.ets', 'services/DashMediaLoader.ets', 'services/DashMediaServer.ets']) {
    assert.ok(!/\[['"]Cookie['"]\]\s*=/.test(read(name)), name);
  }
  assert.ok(!read('pages/QrCodeLoginPage.ets').includes('qrserver.com'));
  assert.ok(read('pages/QrCodeLoginPage.ets').includes('QRCode(this.qrContent)'));
  assert.ok(!read('pages/BilibiliLoginPage.ets').includes('setWebDebuggingAccess(true)'));
  assert.ok(!read('pages/BilibiliLoginPage.ets').includes('.onConsole('));
  const wireRequests = [];
  const http = { RequestMethod: { GET: 1 }, HttpDataType: { ARRAY_BUFFER: 1 }, createHttp: () => ({
    async request(url, options) {
      wireRequests.push({ url, options });
      return { responseCode: 403, header: {}, result: new ArrayBuffer(0) };
    }, destroy() {}
  }) };
  const probe = load('services/DashProbe.ets', { '@kit.NetworkKit': { http }, '../utils/PlaybackStartup': { PlaybackStartup: { span() { return null; } } } });
  const originalError = console.error;
  console.error = () => {};
  try {
    await probe.probeM4sInitSegment('https://untrusted.invalid/media.m4s', 'https://www.bilibili.com/', 'test-agent', 'SESSDATA=never-send');
  } finally { console.error = originalError; }
  assert.ok(wireRequests.length > 0);
  for (const { options } of wireRequests) assert.equal(options.header.Cookie, undefined, 'CDN probes must never send login cookies');
  let releaseSignature;
  let signature = () => new Promise(resolve => { releaseSignature = resolve; });
  let releaseReply;
  let sent = 0;
  let destroyed = 0;
  const { ImGrpcService: im } = load('services/ImGrpcService.ets', {
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 1 }, createHttp: () => ({
      request() { sent++; return new Promise(resolve => { releaseReply = resolve; }); },
      destroy() { destroyed++; }
    }) } },
    '@kit.CoreFileKit': {}, '@kit.BasicServicesKit': {}, '@kit.ArkTS': {},
    '../services/ImProto': {}, '../model/ImMessage': {}, '../api/FeedbackService': {},
    '../utils/SignUtils': { AppSign: { generateWebParams: () => signature() } },
    '../utils/Logger': { logInfo() {}, logWarn() {}, logError() {}, errMsg: String },
    '../utils/MessageData': {}
  }, true);
  const beforeSend = im.webGet('/test', {});
  im.resetSession();
  releaseSignature('signed');
  await assert.rejects(beforeSend, /登录会话已变更/);
  assert.equal(sent, 0, 'logout during signing must prevent the old request from being sent');
  signature = async () => 'signed';
  const inFlight = im.webGet('/test', {});
  await Promise.resolve();
  assert.equal(sent, 1);
  im.resetSession();
  assert.ok(destroyed > 0, 'logout cancels active private-message requests');
  releaseReply({ responseCode: 200, result: JSON.stringify({ code: 0, data: { private: 'stale-account' } }) });
  await assert.rejects(inFlight, /登录会话已变更/, 'late replies must not restore the old account data');
  const apiSource = read('api/BilibiliApi.ets');
  const ssoStart = apiSource.indexOf('export async function refreshAccessKeyFromCookie()');
  const ssoSource = apiSource.slice(ssoStart, apiSource.indexOf('/**', ssoStart));
  const ssoExports = {};
  let releaseSso;
  new Function('exports', 'http', 'AppStorage', 'logInfo', 'logWarn', 'logError',
    ts.transpileModule(ssoSource, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText)(
    ssoExports, { RequestMethod: { GET: 1 }, createHttp: () => ({
      request: () => new Promise(resolve => { releaseSso = resolve; }), destroy() {}
    }) }, appStorage, () => {}, () => {}, () => {});
  storage.set('biliCookie', 'SESSDATA=old-account');
  storage.set('biliAccessKey', '');
  const refreshing = ssoExports.refreshAccessKeyFromCookie();
  storage.set('biliCookie', '');
  releaseSso({ responseCode: 200, result: JSON.stringify({ code: 0, data: { sso: ['https://passport.bilibili.com/?access_key=old-mobile'] } }) });
  assert.equal(await refreshing, '');
  assert.equal(storage.get('biliAccessKey'), '', 'a late SSO reply cannot resurrect the logged-out account');
  assetFailure = true;
  const failedStartup = credentials.initializeLoginCredentials({});
  assert.equal(credentials.initializeLoginCredentials({}), failedStartup, 'startup routes share one credential restore');
  assert.equal(credentials.loginCredentialsReady(), failedStartup);
  await assert.rejects(failedStartup);
  assert.equal(credentials.loginCredentialsReady(), null, 'locked credentials can be retried after unlock');
  assetFailure = false;
  const restored = credentials.initializeLoginCredentials({});
  assert.equal(credentials.initializeLoginCredentials({}), restored);
  await restored;
  console.log('PASS: startup credential readiness/retry, privacy redaction, secure migration, partial-write recovery, logout failure/restart, and network credential boundaries');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
