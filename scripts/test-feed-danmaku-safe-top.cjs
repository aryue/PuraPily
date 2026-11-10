const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const methods = ['ovDanmakuCH', 'ovDanmakuSafeTopInset', 'ovDanmakuY', 'dmPositionY'].map(name => {
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
// 2026-11-10 起连刷弹幕区 = 整屏（顶部安全区下沿 → 屏幕底），不再贴媒体框；
// 评论展开（amount=1）时收回媒体框。ovDanmakuY 保留媒体框口径，供收回终态使用。
Object.assign(s, { referenceLayout: true, fs: false, isLs: false, referenceFeed: true,
  referenceFeedProgress: 1, referenceSafeTop: () => 40, referenceMediaHeight: () => 800,
  referenceFeedCommentAmount: () => 0,
  ovRectY: () => 0, ovRectH: () => 800, referenceLandscapeAreaHeight: () => 300, ch: 800 });
for (const top of [0, 12, 39, 40, 100]) {
  s.ovRectY = () => top;
  // 整屏口径：画布高 = 屏高 - 顶部安全区，顶边固定在安全区下沿，底边固定在屏幕底。
  assert.equal(s.ovDanmakuCH(), 800 - 40, 'feed danmaku spans safe-top to screen bottom');
  assert.equal(s.dmPositionY(), 40 - top, 'danmaku top anchored at the safe area in layer coordinates');
  assert.equal(top + s.dmPositionY() + s.ovDanmakuCH(), 800, 'bottom edge stays fixed at the screen bottom');
  assert.ok(top + s.dmPositionY() >= 40, 'top is outside safe area');
  // ovDanmakuY 仍是媒体框 inset 口径（评论收回终态用）。
  assert.equal(s.ovDanmakuY(), Math.max(0, 40 - top));
}
// 评论展开：收回媒体框，弹幕不盖评论列表。
s.ovRectY = () => 20;
s.referenceFeedCommentAmount = () => 1;
assert.equal(s.ovDanmakuCH(), 800 - 20, 'comments expanded: danmaku height back to the media rect minus inset');
assert.equal(s.dmPositionY(), 20, 'comments expanded: danmaku top back to the media rect');
// 过渡中间帧连续。
s.referenceFeedCommentAmount = () => 0.5;
assert.ok(Math.abs(s.ovDanmakuCH() - 770) < 1e-6, 'comment transition interpolates the danmaku height');
s.referenceFeedCommentAmount = () => 0;
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
console.log('PASS: compiled feed danmaku spans the full screen (safe-top to bottom), comments expansion shrinks back, transition/ordinary/fullscreen/landscape isolation');
