const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const code = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/api/DynamicFollowApi.ts', 'utf8');
let calls = [], destroyed = 0, repeat = false;
const show = id => ({ season_id: id, title: `show-${id}`, cover: `https://example.test/${id}.jpg` });
const first = Array.from({ length: 20 }, (_, i) => show(i + 1));
const http = { RequestMethod: { GET: 'GET' }, createHttp: () => ({ destroy() { destroyed++; },
  async request(url) {
    const type = Number(/type=(\d+)/.exec(url)[1]), page = Number(/pn=(\d+)/.exec(url)[1]);
    calls.push([type, page]);
    const list = type === 2 ? [show(1), show(30)] : page === 1 || repeat ? first : [show(21), show(22)];
    return { responseCode: 200, result: JSON.stringify({ code: 0, data: { list } }) };
  }
}) };
const context = { exports: {}, require: name => name.includes('net.http') ? { default: http } : name.includes('FeedbackService') ? { extractMidFromCookie: cookie => cookie ? '123' : '' } : { logInfo() {}, logWarn() {} } };
vm.runInNewContext(ts.transpileModule(code, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
(async () => {
  const f = context.exports.getDynamicFollowShows;
  assert.equal((await f('')).length, 0); assert.equal(calls.length, 0);
  assert.equal((await f('cookie')).length, 21); assert.equal(calls.length, 2, 'preview requests only the first page of each type');
  calls = []; destroyed = 0;
  assert.equal((await f('cookie', true)).length, 23);
  assert.ok(calls.some(([type, page]) => type === 1 && page === 2));
  assert.equal(destroyed, 2, 'both request handles released');
  repeat = true; calls = [];
  assert.equal((await f('cookie', true)).length, 21);
  assert.equal(calls.length, 3, 'repeated API pages terminate without looping');
  console.log('PASS: compiled follow API preview, on-demand pagination, deduplication, repeated-page guard and cleanup.');
})().catch(err => { console.error(err); process.exitCode = 1; });
