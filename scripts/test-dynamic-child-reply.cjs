const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const ast = ts.createSourceFile('comment.ts', fs.readFileSync(root+'components/CommentItemComponent.ts', 'utf8'), ts.ScriptTarget.Latest, true);
const cls = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'CommentItemComponent');
const methods = ['tapPreviewReply', 'openReplyPreview'].map(name => cls.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
const page = ts.createSourceFile('page.ts', fs.readFileSync(root+'pages/DynamicDetailPage.ts', 'utf8'), ts.ScriptTarget.Latest, true);
let callback;
function visit(node) {
  if (ts.isPropertyAssignment(node) && node.name.getText(page) === 'onReplyTap') callback = node.initializer;
  ts.forEachChild(node, visit);
}
visit(page); assert.ok(callback);
const ctx = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Comment {${methods}}
export class Page { select(root: number, parent: number, name: string) ${callback.body.getText(page)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, ctx);
const target = new ctx.exports.Page(), comment = new ctx.exports.Comment();
let expands = 0;
Object.assign(comment, { comment: { rpid: 100, loadingReplies: false }, replyPreviewDirectReply: true,
  onReplyTap: (...args) => target.select(...args), onExpandComment() { expands++; } });
for (const reply of [{ rpid: 201, member: { uname: 'child A' } }, { rpid: 202, member: { uname: 'child B' } }]) {
  target.entrySheetOn = false;
  comment.tapPreviewReply(reply);
  assert.equal(target.replyRoot, 100); assert.equal(target.replyParent, reply.rpid);
  assert.equal(target.replyTargetName, reply.member.uname); assert.equal(target.entrySheetOn, true);
}
assert.equal(expands, 0, 'dynamic child tap opens reply editor rather than toggling the thread');
comment.comment.loadingReplies = true; comment.tapPreviewReply({ rpid: 203 });
assert.equal(target.replyParent, 203); assert.equal(target.replyTargetName, '', 'reply does not depend on list loading or member metadata');
comment.replyPreviewDirectReply = false; comment.comment.loadingReplies = false;
target.entrySheetOn = false; comment.tapPreviewReply({ rpid: 204 });
assert.equal(expands, 1); assert.equal(target.entrySheetOn, false, 'video preview keeps its comment-detail navigation');
console.log('PASS compiled child reply: correct root/parent/name, editor open, loading independence and video preview behavior.');
