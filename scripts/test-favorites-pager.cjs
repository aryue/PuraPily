const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/FavoritesPage.ts';
const ast = ts.createSourceFile(path, fs.readFileSync(path, 'utf8'), ts.ScriptTarget.Latest, true);
const cls = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'FavoritesPage');
const names = ['loadFolders', 'loadAllFolderCovers', 'onTabChange', 'folderScroller'];
const methods = cls.members.filter(n => ts.isMethodDeclaration(n) && names.includes(n.name.getText(ast))).map(n => n.getText(ast)).join('\n');
const requests = [];
const pending = [];
const api = index => { requests.push(index); return new Promise(resolve => pending[index] = resolve); };
const context = { exports: {}, AppStorage:{get:()=> 'session'}, FavoritesDataService:{getInstance:()=>({loadFolders:(_mid,index)=>api(index),rememberFolders(){}})}, getCreatedFavFolders: () => api(0), getCollectedFavFolders: () => api(1),
  getFavFolderResources: async () => ({ medias: [] }), logError() {}, logWarn() {} };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const state = () => ({ folders: [], loading: false, loaded: false, error: '', refreshing: false, generation: 0 });
(async () => {
  const page = new context.exports.Subject();
  Object.assign(page, { folderPages: [state(), state()], folderScrollers: [
    { currentOffset: () => ({ yOffset: 440 }) }, { currentOffset: () => ({ yOffset: 0 }) }
  ], activeTabIndex: 0, tabPosition: 0, isLoggedIn: true, userMid: 1, sessionCookie:'session' });
  const first = page.loadFolders(0);
  page.onTabChange(1);
  page.onTabChange(0);
  assert.deepEqual(requests, [0, 1], 'switching while loading cannot duplicate requests');
  pending[1]([{ id: 2, title: '订阅', cover: 'cover', media_count: 3 }]);
  await new Promise(setImmediate);
  assert.equal(page.activeTabIndex, 0, 'late response must not change selected page');
  pending[0]([{ id: 1, title: '收藏夹', cover: 'cover', media_count: 4 }]);
  await first;
  const folders = page.folderPages[0].folders;
  for (const i of [1, 0, 1, 0]) page.onTabChange(i);
  assert.deepEqual(requests, [0, 1], 'visited pages must reuse data');
  assert.equal(page.folderPages[0].folders, folders, 'cached image/list identity is retained');
  assert.equal(page.showBackToTop, true, 'selection restores the matching scroller state');
  assert.equal(page.folderPages[1].folders[0].id, 2, 'responses stay isolated by page');
  const refresh = page.loadFolders(0);
  pending[0](null);
  await refresh;
  assert.equal(page.folderPages[0].folders, folders, 'failed refresh preserves current content');
  console.log('PASS: compiled favorites loading, concurrent switch isolation, cached list identity, scrollers and failed refresh.');
})().catch(e => { console.error(e); process.exitCode = 1; });
