// Run real methods retained by CompileArkTS, including the data/controller accessors.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicsPage.ts';
const source = fs.readFileSync(file, 'utf8');
const names = ['isLargeScreen', 'contentWidth', 'railWidth', 'dynScroller', 'effectiveHostMid', 'effectiveType', 'saveTabFeed', 'resetScopeFeeds', 'switchFilter', 'selectUp', 'selectAllUp'];
const methods = names.map(name => {
  const match = new RegExp('    private ' + name + '\\(').exec(source);
  assert.ok(match, `CompileArkTS must retain ordinary method ${name}`);
  let i = source.indexOf('{', match.index), depth = 1;
  while (depth) { i++; if (source[i] === '{') depth++; if (source[i] === '}') depth--; }
  return source.slice(match.index, i + 1);
}).join('\n');
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule('export class Page {' + methods + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
function page(width, index) {
  const p = new context.exports.Page();
  Object.assign(p, { viewportWidth: width, lastTabsIndex: index, filterType: index === 0 ? 'video' : 'all',
    tabFeeds: [{ items: [], loaded: false }, { items: [], loaded: false }], upList: [{ mid: 7, uname: 'test', face: '', hasUpdate: true }],
    selectedUpMid: 0, readUpMids: [], dynTabsController: { changeIndex(i) { p.lastTabsIndex = i; } },
    videoScroller: { scrollTo() {} }, allScroller: { scrollTo() {} },
    emptyFeedHint: () => '', stopBreathe() {}, startBreathe() {}, syncLikeStates() {},
    loadDynamics: (...args) => { p.loads.push(args); }, loads: [] });
  return p;
}
for (const width of [600, 673, 1077, 1440]) {
  for (const index of [0, 1]) {
    const p = page(width, index);
    assert.equal(p.isLargeScreen(), true);
    assert.equal(p.contentWidth(), Math.min(width, 800));
    assert.ok(p.contentWidth() - p.railWidth() >= 440);
    p.selectUp(p.upList[0]);
    assert.equal(p.lastTabsIndex, index, 'author selection preserves current tablet tab');
    assert.equal(p.effectiveHostMid(), 7);
    assert.equal(p.effectiveType(), index === 0 ? 'video' : 'all');
    assert.equal(p.upList[0].hasUpdate, false, 'read marker cleared');
    assert.equal(p.dynScroller(), index === 0 ? p.videoScroller : p.allScroller);
    assert.equal(p.tabFeeds[1-index].items.length, 0, 'new scope never exposes previous author');
    p.dynamics = [{ idStr: 'kept' }]; p.dynOffset = 'page-3'; p.dynHasMore = true; p.isDynLoaded = true;
    p.saveTabFeed();
    const snapshot = p.tabFeeds[index], items = snapshot.items;
    p.switchFilter(index === 0 ? 'all' : 'video');
    const before = p.loads.length;
    p.switchFilter(index === 0 ? 'video' : 'all');
    assert.equal(p.dynamics, items, 'return reuses the same loaded item array');
    assert.equal(p.dynOffset, 'page-3'); assert.equal(p.dynHasMore, true);
    assert.equal(p.loads.length, before, 'loaded tab does not reload on return');
    p.selectAllUp();
    assert.equal(p.lastTabsIndex, index); assert.equal(p.effectiveHostMid(), 0);
    assert.equal(p.tabFeeds[1-index].items.length, 0, 'all scope clears author-only snapshot');
  }
}
const phone = page(440, 0);
assert.equal(phone.isLargeScreen(), false);
phone.selectUp(phone.upList[0]);
assert.equal(phone.filterType, 'up'); assert.equal(phone.lastTabsIndex, 1, 'phone keeps established selection flow');
console.log('PASS: CompileArkTS tablet breakpoints, author/tab scopes, read markers, controller identity and pagination restoration.');
