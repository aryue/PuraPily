const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/api/BilibiliApi.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const body = ['getUserSpaceVideos', 'getUpSpaceDynamics'].map(name => ast.statements.find(n => ts.isFunctionDeclaration(n) && n.name.text === name).getText(ast)).join('\n');
const urls = [], signed = []; let failSignature = false, response;
const context = { exports: {}, throttleRequest: async () => {}, logInfo() {}, logWarn() {}, logError() {},
  getBiliRequestHeaders: () => ({}), normalizeSpaceVideoData: data => data, parseSpaceDynItem: raw => raw,
  AppSign: { generateWebParams: async params => {
    signed.push({ ...params }); if (failSignature) throw Error('signature unavailable');
    return Object.entries(params).map(([k,v]) => k + '=' + encodeURIComponent(v)).join('&');
  } },
  http: { RequestMethod: { GET: 0 }, createHttp: () => ({ request: async url => {
    urls.push(new URL(url)); return { responseCode: 200, result: JSON.stringify(response) };
  }, destroy() {} }) } };
vm.runInNewContext(ts.transpileModule(body, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
(async () => {
  for (const fallback of [false, true]) {
    failSignature = fallback;
    response = { code: 0, data: { items: [{ idStr: 'dynamic-match' }], offset: 'next', has_more: true, total: 20 } };
    const result = await context.exports.getUpSpaceDynamics(123, 'cursor', '  中 & 文  ', 2);
    const url = urls.at(-1);
    assert.equal(url.pathname, '/x/polymer/web-dynamic/v1/feed/space/search');
    for (const [k,v] of Object.entries({ host_mid: '123', offset: 'cursor', keyword: '中 & 文', page: '2', features: 'itemOpusStyle' })) assert.equal(url.searchParams.get(k), v);
    assert.equal(result.items[0].idStr, 'dynamic-match'); assert.equal(result.hasMore, true);
    response = { code: 0, data: { list: { vlist: [{ bvid: 'video-match' }] }, page: { count: 1 } } };
    await context.exports.getUserSpaceVideos(123, 1, 30, 'pubdate', '  中 & 文  ');
    assert.equal(urls.at(-1).searchParams.get('keyword'), '中 & 文');
    assert.equal(urls.at(-1).searchParams.get('mid'), '123');
    response = { code: 0, data: { items: [], offset: '', has_more: false } };
    await context.exports.getUpSpaceDynamics(123);
    assert.equal(urls.at(-1).pathname, '/x/polymer/web-dynamic/v1/feed/space', 'ordinary space lists keep their endpoint');
    assert.equal(urls.at(-1).searchParams.has('keyword'), false);
  }
  response = { code: -101, message: 'not logged in' };
  assert.equal(await context.exports.getUpSpaceDynamics(123, '', 'test'), null);
  console.log('PASS: compiled UP search APIs: scoped endpoints, keyword encoding, signed/fallback parameters, pagination, ordinary-list isolation and API errors.');
})().catch(error => { console.error(error); process.exitCode = 1; });
