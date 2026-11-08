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
(async () => {
  const p = load('pages/HomePage', ['columnPreferenceKey', 'maximumColumns', 'loadColumnCountForOrientation', 'saveCurrentColumnCount', 'handlePinch']);
  Object.assign(p, { viewportWidth: 673, isLandscape: false, columnCount: 2, columnRequestRevision: 0, isPageActive: true,
    showHomeCarouselLandscape: false, recalcLandscapeCarouselWidth() {},
    getUIContext: () => ({ getHostContext: () => ({}), getPromptAction: () => ({ showToast() {} }) }) });
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 3);
  p.handlePinch(1.2); assert.equal(p.columnCount, 4);
  p.handlePinch(1.2); assert.equal(p.columnCount, 4, 'portrait tablet upper bound');
  await p.saveCurrentColumnCount();
  p.viewportWidth = 1077; p.isLandscape = true;
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 4);
  p.handlePinch(.8); assert.equal(p.columnCount, 3);
  await p.saveCurrentColumnCount();
  p.viewportWidth = 673; p.isLandscape = false;
  await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 4, 'independent portrait preference');
  p.columnCount = 2; await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 4, 'recreation restores preference');
  p.viewportWidth = 440; await p.loadColumnCountForOrientation(); assert.equal(p.columnCount, 2, 'phone preference remains independent');
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
  console.log('CompileArkTS tablet methods: responsive columns, gesture bounds, separate saved layouts and recreation passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
