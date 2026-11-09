// Exercise the methods retained by CompileArkTS, rather than source-only copies.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function methods(file, names) {
  const source = fs.readFileSync(base + file + '.ts', 'utf8');
  return names.map(name => {
    const match = new RegExp('    private (?:async )?' + name + '\\(').exec(source);
    assert.ok(match, `compiled method ${name}`);
    const start = match.index;
    let i = source.indexOf('{', start), depth = 1;
    while (depth) { i++; if (source[i] === '{') depth++; if (source[i] === '}') depth--; }
    return source.slice(start, i + 1);
  }).join('\n');
}
const values = new Map();
const pref = { get: async (key, fallback) => values.get(key) ?? fallback,
  put: async (key, value) => values.set(key, value), flush: async () => {} };
const context = { exports: {}, preferences: { getPreferences: async () => pref }, logInfo() {}, logWarn() {}, logError() {} };
function load(file, names) {
  vm.runInNewContext(ts.transpileModule('export class Page {' + methods(file, names) + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS }
  }).outputText, context);
  return new context.exports.Page();
}
const drain = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const p = load('pages/HomePage', ['columnPreferenceKey', 'maximumColumns', 'loadColumnCountForOrientation', 'saveCurrentColumnCount', 'handlePinch']);
  Object.assign(p, { viewportWidth: 673, isLandscape: false, columnCount: 2, columnRequestRevision: 0, isPageActive: true,
    showHomeCarouselLandscape: false, recalcLandscapeCarouselWidth() {},
    getUIContext: () => ({ getHostContext: () => ({}), getPromptAction: () => ({ showToast() {} }) }) });
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 3);
  // 张开 = 放大卡片 = 减列；捏合 = 缩小卡片 = 加列（2026-11-09 方向修正）
  p.handlePinch(1.2); assert.equal(p.columnCount, 2, 'spread removes a column');
  p.handlePinch(1.2); assert.equal(p.columnCount, 2, 'portrait tablet lower bound');
  p.handlePinch(.8); assert.equal(p.columnCount, 3, 'pinch adds a column');
  p.handlePinch(.8); assert.equal(p.columnCount, 4, 'portrait tablet upper bound');
  p.handlePinch(1.2); p.handlePinch(1.2); assert.equal(p.columnCount, 2);
  await drain(); // 让 handlePinch 内部未 await 的异步保存全部落地
  await p.saveCurrentColumnCount();
  p.viewportWidth = 1077; p.isLandscape = true;
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 4);
  p.handlePinch(.8); assert.equal(p.columnCount, 5, 'landscape tablet pinch adds a column');
  await drain();
  await p.saveCurrentColumnCount();
  p.viewportWidth = 673; p.isLandscape = false;
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 2, 'independent portrait preference');
  p.columnCount = 6; await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 2, 'recreation restores preference');
  p.viewportWidth = 440; await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 2, 'phone preference remains independent');

  // 手机三分支：竖屏 2/3 列、横屏（无轮播）3/4 列、横屏（有轮播）2/3 列
  const phone = load('pages/HomePage', ['columnPreferenceKey', 'maximumColumns', 'loadColumnCountForOrientation', 'saveCurrentColumnCount', 'handlePinch']);
  Object.assign(phone, { viewportWidth: 360, isLandscape: false, columnCount: 2, columnRequestRevision: 0, isPageActive: false,
    showHomeCarouselLandscape: false, recalcLandscapeCarouselWidth() {},
    getUIContext: () => ({ getHostContext: () => ({}), getPromptAction: () => ({ showToast() {} }) }) });
  phone.handlePinch(.8); assert.equal(phone.columnCount, 3, 'portrait phone pinch adds a column');
  phone.handlePinch(1.2); assert.equal(phone.columnCount, 2, 'portrait phone spread removes a column');
  phone.isLandscape = true; phone.columnCount = 3;
  phone.handlePinch(.8); assert.equal(phone.columnCount, 4, 'landscape phone pinch adds a column');
  phone.handlePinch(1.2); assert.equal(phone.columnCount, 3, 'landscape phone spread removes a column');
  phone.showHomeCarouselLandscape = true; phone.columnCount = 2;
  phone.handlePinch(1.2); assert.equal(phone.columnCount, 2, 'carousel landscape lower bound');
  phone.handlePinch(.8); assert.equal(phone.columnCount, 3, 'carousel landscape pinch adds a column');
  phone.handlePinch(.8); assert.equal(phone.columnCount, 3, 'carousel landscape upper bound');

  const pgc = load('pages/PgcChannelPage', ['getColumnTemplate']);
  pgc.cardListMargin = 6;
  for (const [width, expected] of [[360, 3], [673, 4], [1077, 7]]) {
    pgc.gridWidth = width;
    assert.equal(pgc.getColumnTemplate().split(' ').length, expected);
  }
  const region = load('pages/RegionChannelPage', ['contentColumns', 'contentItemWidth']);
  region.cardListMargin = 16;
  for (const [width, columns] of [[300, 1], [559, 1], [560, 2], [601, 2], [1005, 2]]) {
    region.contentWidth = width;
    assert.equal(region.contentColumns(), columns);
    assert.equal(region.contentItemWidth() * columns + (columns - 1) * 16 + 16, width,
      'region cards fill their own lanes without overflowing');
  }
  console.log('CompileArkTS tablet methods: responsive columns, pinch direction (spread=fewer / pinch=more), bounds, separate saved layouts and recreation passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
