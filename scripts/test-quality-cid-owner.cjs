const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
function method(name) {
  const start = source.indexOf('private ' + name + '(');
  assert.ok(start >= 0);
  let end = source.indexOf('{', start) + 1, depth = 1;
  for (; depth; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  return source.slice(start, end);
}
// Execute the compiler's actual page methods, including the real catalogue creation.
const code = 'class Page {' + method('applyAcceptQuality') + method('getQlList') + '} globalThis.Page=Page;';
const context = {};
vm.runInNewContext(ts.transpileModule(code, {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText, context);
const page = new context.Page();
page.vi = {bvid: '117517586596030', cid: 123};
page.ql_ = [];
page.applyAcceptQuality({url: 'media', actualQn: 120, acceptQuality: [120, 80], acceptDescription: ['4K', '1080P']});
assert.equal(page.getQlList().length, 2);
page.vi.bvid = 'BVcanonical';
assert.equal(page.getQlList().length, 2, 'AV to BV detail completion must preserve the same CID catalogue');
page.vi.cid = 124;
assert.equal(page.getQlList().length, 0, 'a different part must not inherit the catalogue');
page.vi.cid = 0;
page.aqCid = 0;
assert.equal(page.getQlList().length, 0, 'unknown CID is not a catalogue owner');
page.vi.cid = 125;
page.applyAcceptQuality({url: 'media', actualQn: 64});
assert.equal(page.getQlList()[0].qn, 64, 'missing catalogue exposes only the actual returned quality');
console.log('Compiled quality ownership: AV/BV alias survives, different/unknown CID rejected.');
