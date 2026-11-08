const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(base + 'utils/CommentReplySort.ts', 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
const sort = context.exports.sortCommentReplies;
const replies = [{ rpid: 3, ctime: 30, like: 10 }, { rpid: 1, ctime: 10, like: 2 }, { rpid: 2, ctime: 20, like: 10 }];
assert.equal(sort(replies, true).map(r => r.rpid).join(), '2,3,1');
assert.equal(sort(replies, false).map(r => r.rpid).join(), '1,2,3');
assert.equal(replies.map(r => r.rpid).join(), '3,1,2', 'does not mutate input');
assert.equal(sort([...sort(replies, true), { rpid: 4, ctime: 40, like: 100 }], true)[0].rpid, 4,
  'later pages join the selected order');

function method(file, name) {
  const source = ts.createSourceFile('compiled.ts', fs.readFileSync(base + file, 'utf8'), ts.ScriptTarget.Latest, true);
  const cls = source.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
  return cls.members.find(m => ts.isMethodDeclaration(m) && m.name.getText(source) === name).getText(source);
}
const playerModule = { exports: {} };
vm.runInNewContext(ts.transpileModule('export class Player {' + method('pages/VideoPlayerPage.ts', 'onDanmakuComposerChanged') + '}',
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, playerModule);
for (const visible of [false, true]) {
  let mode = 'resize', timers = 0;
  const p = new playerModule.exports.Player();
  Object.assign(p, { cv: visible, commentSheetVisible: true, showDanmakuSheet: false,
    landscapeComposerAvoidMode: null, referenceAlive: true, playerPageVisible: true,
    cancelDelayHide() {}, resetCT() { timers++; },
    getUIContext() { return { getKeyboardAvoidMode: () => mode, setKeyboardAvoidMode(value) { mode = value; },
      getFocusController: () => ({ clearFocus() {} }) }; } });
  // Inject UI constants and timer helpers used by the compiled watcher.
  playerModule.KeyboardAvoidMode = { NONE: 'none' };
  playerModule.clearTimeout = () => {};
  p.onDanmakuComposerChanged();
  assert.equal(p.cv, false);
  p.showDanmakuSheet = true;
  p.onDanmakuComposerChanged(); // Repeated watchers must not overwrite the snapshot.
  p.commentSheetVisible = false;
  p.onDanmakuComposerChanged();
  assert.equal(p.cv, false, 'second composer still owns controls');
  p.showDanmakuSheet = false;
  p.onDanmakuComposerChanged();
  assert.equal(p.cv, visible, 'restores the original controls state');
  assert.equal(timers, visible ? 1 : 0);
  assert.equal(mode, 'resize');
}
for (const file of ['components/CommentThreadPanel.ts', 'pages/CommentDetailPage.ts']) {
  const compiled = fs.readFileSync(base + file, 'utf8');
  assert.match(compiled, /sortByHeat = !this.sortByHeat/);
  assert.match(compiled, /sortCommentReplies\(this.replies, this.sortByHeat\)/);
}
console.log('PASS: compiled controls restoration, overlapping composer watchers, reply sorting, pagination ordering and both sort controls');
