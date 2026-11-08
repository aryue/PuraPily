const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/SearchPage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const pageClass = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'SearchPage');
const names = ['aboutToAppear', 'goBack', 'performSearch', 'returnToSearchLanding', 'switchToTab', 'onBackPress', 'clearSearchText'];
const body = names.map(name => pageClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
const calls = [], animations = [], toasts = [];
const context = { exports: {}, Curve: { FastOutSlowIn: 0 }, clearTimeout() {}, logError() {}, logWarn() {},
  searchByType: (...args) => new Promise((resolve, reject) => calls.push({ args, resolve, reject })) };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${body} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
function page() {
  const instance = new context.exports.Subject();
  Object.assign(instance, { searchText: 'one', resultsKeyword: '', activeTab: 'video', activeOrder: 'totalrank',
    hasActiveSearch: false, activeResults: [], showSkeleton: false, isLoading: false, activePage: 1,
    activeHasMore: true, searchRequestVersion: 0, sceneVersion: 0, suggestTimer: 0, da: false, returnToCaller: false,
    cachedResults: new Map(), cachedPages: new Map(), cachedHasMore: new Map(), cachedOrders: new Map(),
    addToSearchHistory() {}, setResultOptionsHidden() {}, hideHistoryWithAnimation() {}, initFollowedUsers: async () => {},
    getUIContext: () => ({ getPromptAction: () => ({ showToast: options => toasts.push(options) }),
      animateTo: (options, update) => { animations.push(options); update(); } }) });
  return instance;
}
(async () => {
  for (const params of [{ keyword: '简介标签' }, { keyword: '外部搜索', fromHotRanking: true }, {}]) {
    const direct = page(); let backs = 0;
    Object.assign(direct, { registerContinuation() {}, saveAndSetStatusBarTransparent() {},
      initOrientationAndListen() {}, initSmartGrip() {}, recalcSearchTabBarW() {}, loadInitialData() {}, triggerHaptic() {} });
    const ui = direct.getUIContext();
    ui.getRouter = () => ({ getParams: () => params, back: () => backs++ });
    direct.getUIContext = () => ui;
    direct.aboutToAppear();
    if (params.keyword) {
      assert.equal(direct.hasActiveSearch, true, 'external keywords open results immediately');
      assert.equal(direct.onBackPress(), false, 'system back must pop to the caller');
      direct.goBack();
      assert.equal(backs, 1, 'header back must pop to the caller');
      direct.clearSearchText();
      direct.searchText = '再次搜索';
      direct.hasActiveSearch = true;
      assert.equal(direct.onBackPress(), false, 'editing a direct search must preserve its return destination');
    } else {
      direct.searchText = '普通搜索'; direct.hasActiveSearch = true;
      assert.equal(direct.onBackPress(), true, 'ordinary searches still return to the search landing');
      assert.equal(direct.hasActiveSearch, false);
    }
  }
  let p = page();
  const first = p.performSearch();
  assert.equal(p.hasActiveSearch, true, 'enter the result scene before awaiting the network');
  assert.equal(p.showSkeleton, true); assert.equal(p.isLoading, true);
  assert.equal(p.contentOpacity, 1, 'do not leave a dimmed landing page while waiting');
  calls.at(-1).resolve([{ id: 'first' }]); await first;
  assert.equal(p.activeResults[0].id, 'first'); assert.equal(p.isLoading, false);
  assert.equal(p.showSkeleton, false);

  p = page(); const pending = p.performSearch();
  assert.equal(p.onBackPress(), true);
  assert.equal(p.hasActiveSearch, false);
  const exit = animations.at(-1); exit.onFinish();
  calls.at(-1).resolve([{ id: 'late' }]); await pending;
  assert.equal(p.hasActiveSearch, false, 'a late response cannot reopen results');
  assert.equal(p.activeResults.length, 0); assert.equal(p.showSkeleton, false);

  p = page(); const older = p.performSearch(); const oldCall = calls.at(-1);
  p.searchText = 'two'; const newer = p.performSearch(); const newCall = calls.at(-1);
  newCall.resolve([{ id: 'new' }]); await newer;
  oldCall.resolve([{ id: 'old' }]); await older;
  assert.equal(p.activeResults[0].id, 'new', 'old keywords cannot overwrite newer results');

  p = page(); const leaving = p.performSearch(); const leavingCall = calls.at(-1);
  p.returnToSearchLanding(); const oldExit = animations.at(-1);
  p.searchText = 'again'; const reentry = p.performSearch(); const reentryCall = calls.at(-1);
  oldExit.onFinish(); assert.equal(p.showSkeleton, true, 'the previous exit cannot clear a new search');
  leavingCall.resolve([]); await leaving;
  assert.equal(p.isLoading, true, 'old finally blocks cannot stop the new loading state');
  reentryCall.resolve([]); await reentry;
  assert.equal(p.hasActiveSearch, true, 'empty results stay on the result scene');

  p = page(); const failure = p.performSearch(); calls.at(-1).reject(Error('offline')); await failure;
  assert.equal(p.hasActiveSearch, true); assert.equal(p.showSkeleton, false); assert.equal(p.isLoading, false);
  assert.ok(p.searchError);
  p = page(); p.searchText = '  '; const count = calls.length; await p.performSearch();
  assert.equal(calls.length, count); assert.equal(p.hasActiveSearch, false); assert.equal(p.isLoading, false);

  p = page(); p.cachedResults.set('bili_user', [{ id: 'wrong-keyword' }]);
  const fresh = p.performSearch(); assert.equal(p.cachedResults.size, 0, 'keyword changes invalidate category caches');
  const freshCall = calls.at(-1);
  p.switchToTab('bili_user'); const usersCall = calls.at(-1);
  assert.equal(p.cachedResults.has('video'), false, 'pending rows are not cached as another category');
  usersCall.resolve([{ id: 'user' }]);
  await new Promise(resolve => setImmediate(resolve));
  freshCall.resolve([{ id: 'wrong-tab' }]); await fresh;
  assert.equal(p.activeResults[0].id, 'user');
  p.cachedResults.set('article', [{ id: 'cached' }]); p.cachedHasMore.set('article', false);
  p.switchToTab('article'); assert.equal(p.activeHasMore, false, 'cached final-page state survives');
  console.log('PASS: compiled search entry: immediate loading, slow/empty/error responses, back/reentry, stale keywords/tabs and cache isolation.');
})().catch(error => { console.error(error); process.exitCode = 1; });
