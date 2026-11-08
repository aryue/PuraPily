const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stripTypeScriptTypes } = require('node:module');

const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/utils/LoginCookie.ets'), 'utf8');
const context = vm.createContext({});
vm.runInContext(stripTypeScriptTypes(source).replace(/export /g, ''), context);
const { mergeLoginCookies: merge, hasLoginSession: hasSession,
  loginCookiesFromUrl: fromUrl, classifyLoginVerification: classify } = context;

// HTTP response cookies may include Set-Cookie attributes and Expires commas.
assert.equal(merge(['SESSDATA=a%2Cb%2Fz==; Path=/; HttpOnly; Secure, bili_jct=csrf; Expires=Wed, 21 Oct 2026 07:28:00 GMT; SameSite=None']),
  'SESSDATA=a%2Cb%2Fz==; bili_jct=csrf');
assert.equal(merge(['buvid3=generated; buvid4=undefined', 'buvid3=server; SESSDATA=a+b==\r\nDedeUserID=123; Domain=.bilibili.com']),
  'buvid3=server; SESSDATA=a+b==; DedeUserID=123');
assert.equal(merge(['SESSDATA=old', 'SESSDATA=new; Max-Age=100; Partitioned']), 'SESSDATA=new');
assert.equal(hasSession(merge(['bili_jct=csrf; DedeUserID=123'])), false);
assert.equal(hasSession('fakeSESSDATA=token'), false);
assert.equal(hasSession('SESSDATA='), false);
assert.equal(hasSession(merge(['SESSDATA=undefined'])), false);
assert.equal(hasSession('DedeUserID=123; SESSDATA=token'), true);
// Redirect cookie values must survive extraction with their transport encoding intact.
assert.equal(fromUrl('https://passport.bilibili.com/crossDomain?DedeUserID=123&SESSDATA=a%2Cb%2Fz%3D%3D&bili_jct=csrf&gourl=https%3A%2F%2Fexample.com#ignored'),
  'DedeUserID=123; SESSDATA=a%2Cb%2Fz%3D%3D; bili_jct=csrf');
assert.equal(fromUrl('https://example.com/'), '');
// Login success must not depend on a separately rate-limited profile request.
assert.equal(classify(412, 0, false), 'unavailable');
assert.equal(classify(503, 0, false), 'unavailable');
assert.equal(classify(200, -352, false), 'unavailable');
assert.equal(classify(200, -101, false), 'rejected');
assert.equal(classify(200, 0, false), 'rejected');
assert.equal(classify(200, 0, true), 'authenticated');
console.log('PASS: login cookie parsing and incomplete-session regression checks');
