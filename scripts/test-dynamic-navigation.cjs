const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicsPage.ts', 'utf8');
const methods = ['playDynVideo', 'openDynDetail'].map(name => {
  const start = source.indexOf('    private ' + name + '(');
  assert.ok(start >= 0);
  let end = source.indexOf('{', start), depth = 1;
  while (depth) { end++; if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(start, end + 1);
}).join('\n');
const context = { exports: {}, prefetchVideoPlayback() {}, AppStorage: { get() { return 116; } }, promptAction: { showToast() {} } };
vm.runInNewContext(ts.transpileModule('export class Page {' + methods + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
for (const videoId of ['BV1test123456', '12345678']) {
  for (const type of ['DYNAMIC_TYPE_AV', 'DYNAMIC_TYPE_WORD', 'DYNAMIC_TYPE_DRAW', 'DYNAMIC_TYPE_FORWARD']) {
    const routes = [];
    const page = new context.exports.Page();
    page.getUIContext = () => ({ getRouter: () => ({ pushUrl: route => { routes.push(route); return Promise.resolve(); } }) });
    const video = { bvid: videoId, title: 'video', cover: 'cover' };
    const item = { type, idStr: 'dynamic-1', video: type === 'DYNAMIC_TYPE_AV' ? video : null,
      orig: type === 'DYNAMIC_TYPE_FORWARD' ? { type: 'DYNAMIC_TYPE_AV', video } : null };
    page.openDynDetail(item);
    assert.equal(routes.length, 1);
    assert.equal(routes[0].url, type === 'DYNAMIC_TYPE_AV' ? 'pages/VideoPlayerPage' : 'pages/DynamicDetailPage');
    if (type === 'DYNAMIC_TYPE_AV') assert.equal(routes[0].params.bvid, videoId);
    else assert.equal(routes[0].params.preload, item);
  }
}
console.log('PASS: compiled video submission routing, AV/BV identifiers, ordinary text/images and forwarded video distinction.');
