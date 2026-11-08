const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/UpSpacePage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const subject = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'UpSpacePage');
const methods = ['railStat', 'spaceStatText', 'loadVideos'].map(name =>
  subject.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast));
const callbacks = [];
let rendered;
const row = new Proxy({}, { get: () => () => {} });
const text = new Proxy({}, { get: (_, key) => key === 'create' ? value => { rendered = value; } : () => {} });
let response;
const context = { exports: {}, Row: row, Text: text, Blank: row, FontWeight: {},
  fmtN: n => n >= 10000 ? (n / 10000).toFixed(1) + '万' : String(n),
  getUserSpaceVideos: async () => response, logInfo() {}, logError() {} };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Subject();
Object.assign(page, { totalCount: -1, relationStat: null, ink() {}, muted() {}, hairlineSoft() {},
  observeComponentCreation2: callback => callbacks.push(callback), buildVideoGroups: () => [] });
// Execute the exact Text update closure emitted by CompileArkTS, then update state
// without rebuilding railStat. A primitive Builder argument used to stay at zero.
for (const [label, field, value] of [['投稿', 'totalCount', 1], ['粉丝', 'follower', 16], ['关注', 'following', 14]]) {
  callbacks.length = 0;
  page.totalCount = -1;
  page.relationStat = null;
  page.railStat(label);
  const updateText = callbacks[1];
  updateText();
  assert.equal(rendered, '—');
  if (field === 'totalCount') page.totalCount = value;
  else page.relationStat = { [field]: value };
  updateText();
  assert.equal(rendered, String(value));
  if (field === 'totalCount') page.totalCount = 0;
  else page.relationStat[field] = 0;
  updateText();
  assert.equal(rendered, '0', 'real zero remains a valid statistic');
}
(async () => {
  for (const count of [undefined, 0, 1]) {
    response = { list: { vlist: [{ bvid: 'BV-test', title: 'test' }] }, page: { count } };
    page.isLoadingMore = false;
    await page.loadVideos(1);
    assert.equal(page.totalCount, 1, 'total cannot be less than the loaded video count');
  }
  response = { list: { vlist: [] }, page: { count: 0 } };
  await page.loadVideos(1);
  assert.equal(page.totalCount, 0);
  console.log('PASS: compiled statistic update closures, unknown/zero states, and video count consistency.');
})().catch(error => { console.error(error); process.exitCode = 1; });
