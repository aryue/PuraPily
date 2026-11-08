// Test binary framing, authentication, heartbeat and cancellation on CompileArkTS output.
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const nativeZlib = require('node:zlib');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/LiveChatReceiver.ts', 'utf8');
let connections = [], sockets = [], timers = new Map(), nextTimer = 0;
const socket = () => {
  const s = { handlers: {}, sent: [], on(event, cb) { this.handlers[event] = cb; }, off(event) { delete this.handlers[event]; },
    async connect() { this.handlers.open(); return true; }, async send(packet) { this.sent.push(packet); return true; }, async close() { this.closed = true; } };
  sockets.push(s); return s;
};
const mockZlib = { ReturnStatus: { OK: 0, STREAM_END: 1 }, CompressFlushMode: { FINISH: 4 }, createZipSync: () => ({
  uncompress: async (dest, source) => { const bytes = nativeZlib.inflateSync(Buffer.from(source)); new Uint8Array(dest).set(bytes); return { status: 0, destLen: bytes.length }; },
  getZStream: async () => ({}), inflateInit2: async () => 0, inflateEnd: async () => {},
  inflate: async stream => { const bytes = nativeZlib.inflateSync(Buffer.from(stream.nextIn)); new Uint8Array(stream.nextOut).set(bytes); stream.totalOut = bytes.length; return 1; }
}) };
const context = { exports: {}, AppStorage: { get: () => '' },
  setTimeout: (cb, delay) => { const id = ++nextTimer; timers.set(id, { cb, delay }); return id; }, clearTimeout: id => timers.delete(id),
  setInterval: (cb, delay) => { const id = ++nextTimer; timers.set(id, { cb, delay }); return id; }, clearInterval: id => timers.delete(id),
  require: name => name.includes('zlib') ? { default: mockZlib } : name.includes('Logger') ? { logWarn() {} } : name.includes('LiveApi') ? { getLiveChatConnection: () => new Promise(resolve => connections.push(resolve)) }
    : name.includes('webSocket') ? { default: { createWebSocket: socket } }
    : { default: { TextEncoder: { create: () => ({ encodeInto: text => { assert.notEqual(text, '', 'empty heartbeat body must bypass native encoder'); return new TextEncoder().encode(text); } }) },
      TextDecoder: { create: () => ({ decodeToString: data => new TextDecoder().decode(data) }) } } } };
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
const flush = async () => { await new Promise(setImmediate); };
(async () => {
  const messages = [], statuses = [];
  const r = new context.exports.LiveChatReceiver(m => messages.push(m), s => statuses.push(s));
  r.start(1); const old = connections.shift(); r.start(2);
  old({ token: 'old', host_list: [{ host: 'test.invalid' }] }); await flush();
  assert.equal(sockets.length, 0, 'cancelled config cannot create a socket');
  connections.shift()({ token: 'test', host_list: [{ host: 'test.invalid', wss_port: 443 }] }); await flush();
  const s = sockets[0];
  const auth = JSON.parse(new TextDecoder().decode(new Uint8Array(s.sent[0], 16)));
  assert.equal(auth.roomid, 2); assert.equal(auth.protover, 1);
  assert.equal(timers.size, 1, 'auth has bounded waiting');
  s.handlers.message(null, r.packet(8, '{"code":0}')); await flush();
  assert.equal(statuses.at(-1), '');
  assert.equal(new DataView(s.sent.at(-1)).getUint32(8), 2, 'auth sends first heartbeat');
  assert.equal([...timers.values()][0].delay, 30000);
  const one = r.packet(5, JSON.stringify({ cmd: 'DANMU_MSG:4:0:2:2:2:0', info: [[], '你好世界', [123, '用户']] }));
  const two = r.packet(5, JSON.stringify({ cmd: 'DANMU_MSG', info: [[], '下一条', [456, '观众']] }));
  const both = new Uint8Array(one.byteLength + two.byteLength); both.set(new Uint8Array(one)); both.set(new Uint8Array(two), one.byteLength);
  s.handlers.message(null, both.slice(0, 19).buffer); await flush();
  assert.equal(messages.length, 0, 'partial frame waits for remaining bytes');
  s.handlers.message(null, both.slice(19).buffer); await flush();
  assert.deepEqual(messages.map(m => m.text), ['你好世界', '下一条']);
  const compressed = nativeZlib.deflateSync(both);
  const frame = new ArrayBuffer(16 + compressed.length), header = new DataView(frame);
  header.setUint32(0, frame.byteLength); header.setUint16(4, 16); header.setUint16(6, 2); header.setUint32(8, 5);
  new Uint8Array(frame).set(compressed, 16);
  s.handlers.message(null, frame); await flush();
  assert.deepEqual(messages.slice(-2).map(m => m.text), ['你好世界', '下一条'], 'compressed nested packets decode in order');
  const late = s.handlers.message;
  r.stop(); late(null, one); await flush(); assert.equal(messages.length, 4, 'stopped socket ignores late messages');
  assert.equal(timers.size, 0, 'stop clears heartbeat and retries');
  assert.equal(s.closed, true);
  r.start(3); connections.shift()({ token: 'test', host_list: [{ host: 'test.invalid' }] }); await flush();
  sockets[1].handlers.message(null, r.packet(8, '{"code":-101}')); await flush();
  assert.equal([...timers.values()][0].delay, 10000, 'auth rejection schedules bounded retry');
  r.stop();
  console.log('Live chat receiver CompileArkTS passed: auth, UTF-8, split/coalesced frames, heartbeat, retry and stale socket cancellation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
