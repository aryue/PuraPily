const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('D:/Program Files/Huawei/DevEco Studio/tools/hvigor/hvigor/node_modules/typescript');
const read = name => fs.readFileSync(path.join(__dirname, '../entry/src/main/ets', name), 'utf8').replace(/\r\n/g, '\n');
const compile = source => ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
const messageData = {};
new Function('exports', compile(read('utils/MessageData.ets')))(messageData);
const exportsModel = {};
new Function('exports', compile(read('model/ImMessage.ets')))(exportsModel);
const { ImMessage } = exportsModel;
const source = read('components/WhisperChatView.ets');
const methods = source.slice(source.indexOf('  private async loadHistory()'), source.indexOf('  /**\n   * Msg → 展示模型'));
const makeHarness = new Function('ImGrpcService', 'logError', 'logWarn', 'errMsg', 'Edge', 'setTimeout',
  compile('class Harness {\n' + methods + '\n}\n') + '\nreturn Harness;');
let fetch;
let ack = [];
const Harness = makeHarness({ getMyMid: () => 1, fetchSessionMsgs: (...args) => fetch(...args), ackSessionMsg: (...args) => ack.push(args) }, () => {}, () => {}, String, { Bottom: 1 }, fn => fn());
function state() {
  return Object.assign(new Harness(), {
    alive: true, requestVersion: 0, talkerId: 2, myMid: 1, messages: [],
    endSeqno: null, hasMore: true, isLoading: false, isLoadingMore: false, isRefreshing: false,
    loadError: '', scroller: { scrollEdge() {}, isAtEnd: () => true },
    toChatItem: msg => ({ msg, text: msg.getText() }),
  });
}
function msg(seqno, content = '消息' + seqno) {
  return Object.assign(new ImMessage(), { msgSeqno: seqno, timestamp: seqno, content: JSON.stringify({ content }) });
}
const page = (ids, hasMore = 1) => ({ messages: ids.map(id => msg(id)), hasMore });
const ids = view => view.messages.map(item => item.msg.msgSeqno);
async function run() {
  assert.equal(msg(1, '包含 bvid 的普通文字').getText(), '包含 bvid 的普通文字');
  assert.equal(msg(1, '{"text":"保留 JSON 原文"}').getText(), '{"text":"保留 JSON 原文"}');
  const rich = new ImMessage();
  rich.content = JSON.stringify({ content: [{ text: '第一段' }, { text: '第二段' }] });
  assert.equal(rich.getText(), '第一段第二段');
  rich.content = JSON.stringify([{ text: '你好"' }, { text: '\n世界' }]);
  assert.equal(rich.getText(), '你好"\n世界');
  rich.content = 'null';
  assert.equal(rich.getText(), 'null');

  const view = state();
  fetch = async () => page([30, 28, 29, 30]);
  await view.loadHistory();
  assert.deepEqual(ids(view), [28, 29, 30]);
  assert.equal(view.hasMore, true);
  assert.equal(view.endSeqno, 28);
  fetch = async (talker, cursor) => { assert.equal(cursor, 28); return page([28, 27, 26], 0); };
  await view.loadMore();
  assert.deepEqual(ids(view), [26, 27, 28, 29, 30]);
  assert.equal(view.hasMore, false);

  const cursors = [];
  fetch = async (talker, cursor) => { cursors.push(cursor); return cursor === null ? page([34, 33]) : page([33, 32, 31, 30]); };
  await view.refreshMessages();
  assert.deepEqual(cursors, [null, 33]);
  assert.deepEqual(ids(view), [26, 27, 28, 29, 30, 31, 32, 33, 34]);
  assert.equal(view.endSeqno, 26);
  assert.equal(view.hasMore, false);
  assert.deepEqual(ack.at(-1), [2, 34]);
  fetch = async () => { throw new Error('offline'); };
  await view.refreshMessages();
  assert.equal(view.messages.length, 9);
  assert.equal(view.isRefreshing, false);

  let resolveOld;
  fetch = () => new Promise(resolve => { resolveOld = resolve; });
  const old = view.loadHistory();
  view.talkerId = 3;
  fetch = async () => page([90], 0);
  await view.loadHistory();
  resolveOld(page([1]));
  await old;
  assert.deepEqual(ids(view), [90]);
  assert.equal(view.isLoading, false);

  fetch = () => new Promise(resolve => { resolveOld = resolve; });
  view.hasMore = true;
  const staleMore = view.loadMore();
  view.requestVersion++;
  view.messages = [];
  resolveOld(page([89]));
  await staleMore;
  assert.deepEqual(ids(view), []);

  const stalled = state();
  fetch = async () => page([5]);
  await stalled.loadHistory();
  await stalled.loadMore();
  assert.equal(stalled.hasMore, false);
  assert.equal(stalled.messages.length, 1);
  fetch = async () => { throw new Error('offline'); };
  await stalled.loadHistory();
  assert.ok(stalled.loadError);
  assert.equal(stalled.messages.length, 1);

  assert.ok(source.includes('.onReachStart(() => {\n            this.loadMore();'));
  assert.ok(!source.includes('.onReachEnd(() => {\n            this.loadMore();'));
  const serviceExports = {};
  const serviceSource = read('services/ImGrpcService.ets').replace(/^import .*;\n/gm, '');
  new Function('exports', 'ImMessage', 'ImMsgType', 'util', 'logError', 'errMsg', 'ProtoWriter', 'messageTimestamp', 'messageImageUrl', 'logWarn', compile(serviceSource))(
    serviceExports, ImMessage, exportsModel.ImMsgType, {
      TextEncoder: { create: () => ({ encodeInto: text => new TextEncoder().encode(text) }) },
      TextDecoder: { create: () => ({ decodeToString: bytes => new TextDecoder().decode(bytes) }) },
    }, () => {}, String, class { writeMessageField() {} toUint8Array() { return new Uint8Array(); } }, messageData.messageTimestamp, messageData.messageImageUrl, () => {});
  const service = serviceExports.ImGrpcService;
  const requests = [];
  service.getAccessKey = () => '';
  service.webGet = async (url, params) => {
    requests.push({ url, params });
    if (url.includes('msgfeed/unread')) return { at: 1, like: 2, reply: 3, sys_msg: 4 };
    if (url.endsWith('/single_unread')) return { follow_unread: 2, unfollow_unread: 3 };
    if (url.includes('fetch_session_msgs')) return { messages: [{ sender_uid: 7, msg_seqno: 22, msg_type: 1, content: '{"content":"收到内容"}' }], has_more: 1 };
    if (url.includes('user_infos')) return [{ mid: 999, name: '其他人', face: 'wrong' }, { mid: 7, name: '昵称', face: '//i.example/avatar' }];
    return { session_list: [{ talker_id: 7, session_ts: 1700000000000000, unread_count: 2, last_msg: { msg_type: 1, content: '{"content":"消息预览"}' } }], has_more: 1 };
  };
  const webMessages = await service.fetchSessionMsgs(7, 25);
  assert.equal(webMessages.messages[0].getText(), '收到内容');
  assert.equal(webMessages.hasMore, 1);
  assert.equal(requests[0].params.end_seqno, '25');
  const webSessions = await service.fetchSessionList(null);
  assert.equal(webSessions.sessions[0].sessionName, '昵称');
  assert.equal(webSessions.sessions[0].face, 'https://i.example/avatar');
  assert.equal(webSessions.sessions[0].lastMsg, '消息预览');
  assert.equal(webSessions.sessions[0].timestamp, 1700000000);
  await service.fetchSessionList(webSessions.offsetBytes);
  assert.equal(requests.at(-1).params.end_ts, '1700000000000000');
  service.getAccessKey = () => 'test';
  service.grpcPost = async () => { throw new Error('grpc -400'); };
  const profiles = service.parseUserProfiles({ '8': { name: '另一昵称', face: 'http://i.example/8' } });
  assert.equal(profiles.get(8).name, '另一昵称');
  assert.equal(profiles.get(8).face, 'https://i.example/8');
  const fallback = await service.fetchSessionList(null);
  assert.equal(fallback.sessions[0].talkerUid, 7);
  assert.deepEqual(Object.values(await service.fetchTotalUnread()), [1, 2, 3, 4]);
  assert.equal(await service.fetchPrivateUnread(), 5);
  assert.equal(requests.at(-1).url, '/session_svr/v1/session_svr/single_unread');
  const index = read('pages/Index.ets');
  const pollingMethods = index.slice(index.indexOf('  private onMessageAccountChanged()'),
    index.indexOf('  private updateSearchVisibility()'));
  let cookie = 'SESSDATA=test';
  let timer;
  let privateUnread = async () => 5;
  const Home = new Function('ImGrpcService', 'AppStorage', 'setInterval', 'clearInterval', 'HOME_MESSAGE_REFRESH_MS',
    compile('class Home {\n' + pollingMethods + '\n}') + '\nreturn Home;')(
    { fetchPrivateUnread: () => privateUnread(), fetchTotalUnread: () => service.fetchTotalUnread() },
    { get: () => cookie }, fn => { timer = fn; return 1; }, () => { timer = undefined; }, 30000);
  const home = Object.assign(new Home(), {
    pageVisible: true, activeTab: 0, appInBackground: false, messageCookie: cookie,
    messagePollTimer: -1, messagePollGeneration: 0, messagePollInFlight: false,
  });
  const settle = () => new Promise(resolve => setImmediate(resolve));
  home.updateMessagePolling();
  await settle();
  assert.equal(home.messageUnread, 15);
  privateUnread = async () => { throw new Error('offline'); };
  timer();
  await settle();
  assert.equal(home.messageUnread, 15);
  privateUnread = async () => 0;
  home.pageVisible = false;
  home.updateMessagePolling();
  assert.equal(timer, undefined);
  home.pageVisible = true;
  home.updateMessagePolling();
  await settle();
  assert.equal(home.messageUnread, 10);
  let finishUnread;
  privateUnread = () => new Promise(resolve => { finishUnread = resolve; });
  timer();
  home.messageCookie = cookie = '';
  home.onMessageAccountChanged();
  finishUnread(99);
  await settle();
  assert.equal(home.messageUnread, 0);
  assert.equal(timer, undefined);
  const detail = read('pages/WhisperDetailPage.ets');
  assert.ok(detail.includes('WhisperChatView({'));
  assert.ok(!detail.includes('fetchSessionMsgs('));
  const sessions = read('pages/WhisperPage.ets');
  const refreshBody = sessions.slice(sessions.indexOf('  private async refreshSessions()'), sessions.indexOf('  /**\n   * 对 face 为空的会话'));
  let sessionResult;
  const Sessions = new Function('ImGrpcService', 'logWarn', 'errMsg', compile('class Sessions {\n' + refreshBody + '\n}') + '\nreturn Sessions;')(
    { fetchSessionList: async () => sessionResult }, () => {}, String);
  const list = Object.assign(new Sessions(), {
    alive: true, isLoading: false, isLoadingMore: false, isRefreshing: false,
    sessions: [{ talkerUid: 1, timestamp: 10, face: 'cached', lastMsg: 'old' }, { talkerUid: 2, timestamp: 5 }],
    loadUnread() {}, fetchFaces() {}, hasMore: true, offsetBytes: 'keep-pagination',
  });
  sessionResult = { sessions: [{ talkerUid: 1, timestamp: 20, face: '', lastMsg: 'new' }, { talkerUid: 3, timestamp: 30 }] };
  await list.refreshSessions();
  assert.deepEqual(list.sessions.map(s => s.talkerUid), [3, 1, 2]);
  assert.equal(list.sessions[1].face, 'cached');
  assert.equal(list.sessions[1].lastMsg, 'new');
  assert.equal(list.offsetBytes, 'keep-pagination');
  assert.equal(list.hasMore, true);
  console.log('IM messages: content, ordering, overlap, pagination, refresh catch-up, failures and stale requests passed.');
}
run().catch(error => { console.error(error); process.exitCode = 1; });
