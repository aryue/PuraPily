const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('D:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const read = file => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', file), 'utf8').replace(/\r\n/g, '\n');
const compile = source => ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
const time = {};
new Function('exports', compile(read('utils/MessageData.ets')))(time);
let body;
let requested;
let destroyed = 0;
const exportsApi = {};
const apiSource = read('api/MsgFeedApi.ets').replace(/^import .*;\n/gm, '');
new Function('exports', 'http', 'AppStorage', 'messageTimestamp', 'messageImageUrl', 'logInfo', 'logWarn', 'logError', 'errMsg', compile(apiSource))(
  exportsApi, { RequestMethod: { GET: 'GET' }, createHttp: () => ({
    request: async url => { requested = url; return { responseCode: 200, result: body }; },
    destroy: () => { destroyed++; },
  }) }, { get: () => '' }, time.messageTimestamp, time.messageImageUrl, () => {}, () => {}, () => {}, String);
const { MsgFeedApi: api, noticePlainText } = exportsApi;

async function run() {
  const seconds = 1700000000;
  for (const value of [seconds, String(seconds), seconds * 1000, seconds * 1e6, seconds * 1e9]) {
    assert.equal(time.messageTimestamp(value), seconds);
  }
  assert.equal(time.messageTimestamp('2026-10-20 12:34:56'), Date.parse('2026-10-20T12:34:56+08:00') / 1000);
  assert.equal(time.messageTimestamp('2026-10-20T04:34:56Z'), Date.parse('2026-10-20T12:34:56+08:00') / 1000);
  for (const value of ['', 0, 'not-a-date', null, {}, NaN]) assert.equal(time.messageTimestamp(value), 0);
  assert.equal(time.formatMessageTime(0), '');
  const now = new Date(2026, 9, 20, 14, 0).getTime();
  assert.equal(time.formatMessageTime(new Date(2026, 9, 20, 12, 30).getTime() / 1000, false, now), '12:30');
  assert.equal(time.formatMessageTime(new Date(2025, 9, 20, 12, 30).getTime() / 1000, false, now), '2025-10-20 12:30');

  const actor = { mid: 9, nickname: '发通知的人', avatar: '//i.example/actor' };
  for (const field of ['reply_time', 'like_time', 'at_time']) {
    const item = api.parseItem({ id: 1, [field]: seconds, user: actor, item: { source_content: '正文' } });
    assert.equal(item.time, seconds);
    assert.equal(item.uname, actor.nickname);
    assert.equal(item.avatar, 'https://i.example/actor');
    assert.equal(item.mid, 9);
  }
  const like = api.parseItem({ id: 2, like_time: seconds, users: [actor] });
  assert.equal(like.mid, 9);
  assert.equal(like.avatar, 'https://i.example/actor');
  assert.equal(noticePlainText('<p>正文 &amp; 提醒<br>第二行</p>'), '正文 & 提醒\n第二行');
  const notification = api.parseSysItem({ id: 3, title: '系统标题', time_at: '2026-10-20 12:34:56', content: '{"web":"<p>完整正文</p>"}' });
  assert.equal(notification.title, '系统标题');
  assert.equal(notification.uname, '系统通知');
  assert.equal(notification.content, '完整正文');
  assert.ok(notification.time > 0);

  // 模拟真实 HTTP 正文，19 位数值游标必须逐位保留，不能经过 Number。
  const cursor = '1792499696123456789';
  body = '{"code":0,"data":[{"id":3,"cursor":' + cursor + ',"time_at":"2026-10-20 12:34:56","title":"系统标题","content":"正文"}]}';
  let result = await api.fetchList(4, 0, 0);
  assert.equal(result.cursor, cursor);
  assert.equal(result.isEnd, false);
  result = await api.fetchList(4, result.cursor, 0);
  assert.ok(requested.includes('cursor=' + cursor));
  assert.ok(!requested.includes('&id='));
  assert.equal(result.isEnd, true);
  body = '{"code":0,"data":[]}';
  assert.equal((await api.fetchList(4, cursor, 0)).isEnd, true);
  body = '{"code":-101,"message":"未登录"}';
  await assert.rejects(() => api.fetchList(4, 0, 0), /未登录/);
  assert.equal(destroyed, 4);
  console.log('Message notices: actor identity, time units, timezone strings, full system content, exact cursor and failures passed.');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
