const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(base + 'pages/LivePlayerPage.ts', 'utf8');
const tree = ts.createSourceFile('page.ts', source, ts.ScriptTarget.Latest, true);
const page = tree.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'LivePlayerPage');
const names = ['stopLiveChat', 'startLiveChat', 'refreshLiveChat', 'chatOverlayMode', 'chatMaxHeight',
  'chatMessageLimit', 'visibleLiveChatMessages', 'landscapeLayout', 'landscapeInset', 'landscapeExpandAmount',
  'landscapePanelHeight'];
const methods = names.map(name => {
  const method = page.members.find(n => n.name?.getText(tree) === name);
  assert.ok(method, `CompileArkTS must emit ${name}`);
  return method.getText(tree);
}).join('\n');
let requests = [], timers = new Map(), nextTimer = 0;
const ctx = { exports: {}, getLiveChatHistory: () => new Promise((resolve, reject) => requests.push({ resolve, reject })),
  setTimeout: (cb, delay) => { const id = ++nextTimer; timers.set(id, { cb, delay }); return id; },
  clearTimeout: id => timers.delete(id) };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };
const message = i => ({ id: String(i), text: String(i), nickname: 'viewer', timeline: String(i).padStart(3, '0') });
async function main() {
  const p = new ctx.exports.Page();
  Object.assign(p, { liveChatGeneration: 0, roomId: 1, liveChatMessages: [], liveChatStatus: '', liveChatReceiver: { start() {}, stop() {} }, viewportWidth: 720, viewportHeight: 800,
    liveFullscreen: false, landscapeExpand: 0, chatSlotHeight: 0, LIVE_CHAT_LIMIT: 200 });
  p.startLiveChat(true);
  const old = requests.shift();
  p.roomId = 2; p.startLiveChat(true);
  old.resolve([message(1)]); await flush();
  assert.equal(p.liveChatMessages.length, 0, 'old room response must be discarded');
  assert.equal(timers.size, 0, 'old room must not schedule more requests');
  requests.shift().resolve(Array.from({ length: 9 }, (_, i) => message(i))); await flush();
  assert.deepEqual(Array.from(p.liveChatMessages, m => m.id), ['0', '1', '2', '3', '4', '5', '6', '7', '8'],
    'history keeps every recent row for the scrollable comment tab');
  assert.equal(timers.size, 1);
  const timer = [...timers.values()][0]; assert.equal(timer.delay, 3000);
  timers.clear(); timer.cb();
  requests.shift().resolve([message(8), message(9)]); await flush();
  assert.deepEqual(Array.from(p.liveChatMessages, m => m.id),
    ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'], 'overlapping history must not duplicate messages');
  p.startLiveChat(); p.liveChatConnected = true;
  requests.shift().resolve([message(88)]); await flush();
  assert.equal(p.liveChatMessages.at(-1).id, '9', 'late history cannot replace a connected live stream');
  assert.equal(timers.size, 0, 'connected live stream stops history polling');
  p.liveChatConnected = false;
  p.startLiveChat();
  requests.shift().reject(new Error('network')); await flush();
  assert.equal(p.liveChatMessages.length, 10, 'failure preserves received messages');
  assert.equal([...timers.values()][0].delay, 10000, 'failure backs off');
  p.startLiveChat(); p.pageHidden = true; p.stopLiveChat();
  requests.shift().resolve([message(99)]); await flush();
  assert.equal(p.liveChatMessages.at(-1).id, '9', 'background response must be discarded');
  assert.equal(timers.size, 0);
  p.pageHidden = false; p.startLiveChat(); p.disposed = true; p.stopLiveChat();
  requests.shift().resolve([message(100)]); await flush();
  assert.equal(p.liveChatMessages.at(-1).id, '9', 'exit response must be discarded');
  p.viewportHeight = 360; p.chatSlotHeight = 96;
  assert.equal(p.visibleLiveChatMessages().at(-1).id, '9', 'landscape keeps newest messages');
  assert.ok(p.visibleLiveChatMessages().length <= 2);
  // 评论 tab 的历史上限：250 条历史只丢最旧 50 条，不再被 12 条裁掉
  Object.assign(p, { disposed: false, pageHidden: false, liveChatConnected: false,
    liveChatMessages: [], liveChatStatus: '', roomId: 1, liveChatGeneration: 0 });
  timers.clear();
  p.startLiveChat();
  requests.shift().resolve(Array.from({ length: 250 }, (_, i) => message(i))); await flush();
  assert.equal(p.liveChatMessages.length, 200, 'comment tab keeps a bounded 200-message history');
  assert.equal(p.liveChatMessages[0].id, '50', 'oldest kept message is exactly at the cap');
  assert.equal(p.liveChatMessages.at(-1).id, '249', 'newest live message is visible');

  const api = fs.readFileSync(base + 'api/LiveApi.ts', 'utf8');
  const start = api.indexOf('export async function getLiveChatHistory(');
  assert.ok(start >= 0);
  let destroyed = 0, body = { code: 0, data: { room: [
    { id_str: '1', text: 'hello', nickname: 'viewer', timeline: '2026-11-07 12:00:00', uname_color: 'bad' }
  ], admin: [{ id_str: '1', text: 'hello', nickname: 'viewer', timeline: '2026-11-07 12:00:00' }] } };
  const apiContext = { exports: {}, HttpConstants: { liveBaseUrl: 'https://test.invalid' }, getBiliCookie: () => '',
    http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({ destroy: () => destroyed++, request: async () => ({ responseCode: 200, result: JSON.stringify(body) }) }) } };
  vm.runInNewContext(ts.transpileModule(api.slice(start), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, apiContext);
  const result = await apiContext.exports.getLiveChatHistory(1);
  assert.equal(result.length, 1, 'admin/history overlap is deduplicated');
  assert.equal(result[0].nameColor, '#8BDCEB');
  body = { code: -400 }; await assert.rejects(apiContext.exports.getLiveChatHistory(1));
  assert.equal(destroyed, 2, 'HTTP handles close on success and failure');
  console.log('Live chat CompileArkTS regression passed: parsing, deduplication, bounded rows, backoff, room/background/exit races.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
