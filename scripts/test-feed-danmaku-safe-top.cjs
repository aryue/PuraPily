const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const methods = ['ovDanmakuCH', 'ovDanmakuSafeTopInset', 'ovDanmakuY'].map(name => {
  const start = source.indexOf(`    private ${name}(`);
  assert.ok(start >= 0, `compiled method ${name}`);
  let end = source.indexOf('{', start) + 1, depth = 1;
  for (; depth; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  return source.slice(start, end);
}).join('\n');
const context = {};
vm.runInNewContext(ts.transpileModule(`class Subject { ${methods} } globalThis.subject = new Subject();`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const s = context.subject;
Object.assign(s, { referenceLayout: true, fs: false, isLs: false, referenceFeed: true,
  referenceFeedProgress: 1, referenceSafeTop: () => 40, referenceMediaHeight: () => 800,
  ovRectY: () => 0, ovRectH: () => 800, referenceLandscapeAreaHeight: () => 300, ch: 800 });
for (const top of [0, 12, 39, 40, 100]) {
  s.ovRectY = () => top;
  assert.equal(s.ovDanmakuY(), Math.max(0, 40 - top));
  assert.equal(top + s.ovDanmakuY() + s.ovDanmakuCH(), top + 800, 'bottom edge stays fixed');
  assert.ok(top + s.ovDanmakuY() >= 40, 'top is outside safe area');
}
s.ovRectY = () => 20;
s.referenceFeed = false;
s.referenceFeedProgress = 0.5;
assert.equal(s.ovDanmakuY(), 20, 'exiting feed still avoids safe area');
s.referenceFeedProgress = 0;
assert.equal(s.ovDanmakuY(), 0, 'ordinary portrait unchanged');
s.fs = true;
assert.equal(s.ovDanmakuCH(), 800);
assert.equal(s.ovDanmakuY(), 0);
s.fs = false; s.isLs = true;
assert.equal(s.ovDanmakuCH(), 300);
assert.equal(s.ovDanmakuY(), 250);
console.log('PASS: compiled feed danmaku safe top, transition, fixed bottom, ordinary/fullscreen/landscape isolation');
