const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function methods(file, names) {
  const source = fs.readFileSync(root + file, 'utf8');
  return names.map(name => {
    const start = source.search(new RegExp(`^    (?:private )?(?:async )?${name}\\(`, 'm'));
    assert.ok(start >= 0, name);
    return source.slice(start, source.indexOf('\n    }', start) + 6);
  }).join('\n');
}
function subject(body, globals = {}) {
  const context = { exports: {}, ...globals };
  vm.runInNewContext(ts.transpileModule(`export class Subject {${body}}`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return new context.exports.Subject();
}
(async () => {
  const writes = [];
  const page = subject(methods('pages/SearchPage.ts', ['beginHistoryDisintegration', 'settleHistoryDisintegration',
    'finishHistoryDisintegration', 'removeFromSearchHistory', 'saveSearchHistory', 'addToSearchHistory']), {
    Curve: { EaseOut: 0 }, logError() {},
    preferences: { getPreferences: async () => ({ put: async (key, value) => writes.push(JSON.parse(value)), flush: async () => {} }) }
  });
  page.getUIContext = () => ({ getHostContext: () => ({}), animateTo: (_, action) => action() });
  const reset = words => Object.assign(page, { searchHistory: words.slice(), dissolvingHistory: [],
    completedHistoryDust: [], visibleHistoryDust: [], searchHistoryRows: 1, showAllHistory: false, isLandscape: false });
  const saved = async () => { await new Promise(resolve => setImmediate(resolve)); return writes.at(-1); };
  reset(['A', 'B', 'C']);
  page.removeFromSearchHistory(1);
  assert.deepEqual(Array.from(page.searchHistory), ['A', 'B', 'C'], 'retain layout while particles fly');
  assert.deepEqual(await saved(), ['A', 'C'], 'persist deletion before the animation finishes');
  page.finishHistoryDisintegration('not pending');
  assert.equal(page.searchHistory.length, 3);
  page.finishHistoryDisintegration('B');
  assert.deepEqual(Array.from(page.searchHistory), ['A', 'C']);
  page.finishHistoryDisintegration('B');
  assert.deepEqual(Array.from(page.searchHistory), ['A', 'C'], 'duplicate/late callbacks cannot delete another word');
  const words = Array.from({ length: 30 }, (_, i) => `word-${i}`);
  reset(words); page.beginHistoryDisintegration(page.searchHistory);
  assert.equal(page.visibleHistoryDust.length, 5);
  assert.deepEqual(await saved(), [], 'clear also persists the folded entries');
  page.beginHistoryDisintegration(['other']);
  for (const word of words.slice(0, 4)) page.finishHistoryDisintegration(word);
  assert.equal(page.searchHistory.length, 30, 'clear keeps every chip in place until the visible batch finishes');
  page.finishHistoryDisintegration(words[4]);
  assert.equal(page.searchHistory.length, 0, 'hidden entries do not need impossible animation callbacks');
  reset(['A', 'B']); page.removeFromSearchHistory(0); page.settleHistoryDisintegration();
  assert.deepEqual(Array.from(page.searchHistory), ['B'], 'leaving during animation commits the pending deletion');
  page.finishHistoryDisintegration('A'); assert.equal(page.searchHistory.length, 1);
  reset(['A', 'B']); page.removeFromSearchHistory(0); page.addToSearchHistory('A');
  assert.deepEqual(Array.from(page.searchHistory), ['A', 'B'], 'a subsequent explicit search may add the word again');
  assert.deepEqual(await saved(), ['A', 'B']);

  let now = 0, frame, released = 0, gone = 0;
  const draws = [], transforms = [], alphas = [];
  const canvas = { clearRect() {}, save() {}, restore() {}, rotate() {},
    translate: (...args) => transforms.push(args), drawImage: (...args) => draws.push(args),
    set globalAlpha(value) { alphas.push(value); } };
  const bitmap = { getImageInfo: async () => ({ size: { width: 240, height: 60 } }),
    release: async () => { released++; } };
  const dust = subject(methods('components/HistoryDustChip.ts', ['startDust', 'drawDust', 'stopDust', 'aboutToDisappear']), {
    HistoryDustSnapshotQueue: { capture: action => action() }, logWarn() {}, errMsg: String,
    Date: { now: () => now }, setInterval: callback => { frame = callback; return 7; }, clearInterval() {}
  });
  Object.assign(dust, { canvasReady: true, dissolving: true, running: false, disposed: false,
    chipWidth: 120, chipHeight: 30, snapshotId: 'test', staggerMs: 0, context: canvas, timer: -1,
    onGone: () => { gone++; } });
  dust.getUIContext = () => ({ px2vp: pixels => pixels / 2,
    getComponentSnapshot: () => ({ get: async (id, options) => {
      assert.equal(id, 'test'); assert.equal(options.waitUntilRenderFinished, true); return bitmap;
    } }) });
  await dust.startDust();
  assert.equal(dust.captured, true);
  assert.ok(dust.tiles.length > 100 && dust.tiles.length < 600);
  assert.ok(draws.every(args => args[1] < 120 && args[2] < 30), 'API 18+ PixelMap source coordinates are vp');
  assert.ok(alphas.every(alpha => alpha === 1), 'snapshot handoff starts with intact pixels');
  draws.length = transforms.length = alphas.length = 0;
  now = 650; frame();
  assert.ok(alphas.some(alpha => alpha > 0 && alpha < 1), 'intermediate frames contain fading fragments');
  assert.ok(transforms.some((xy, i) => xy[0] > 24 + dust.tiles[i].x + dust.tiles[i].width / 2), 'fragments drift');
  now = 1200; frame(); assert.equal(gone, 1); assert.equal(released, 1);
  dust.aboutToDisappear(); assert.equal(released, 1, 'bitmap is released once');
  const queueFile = fs.readFileSync(root + 'components/HistoryDustChip.ts', 'utf8');
  const queueStart = queueFile.indexOf('export class HistoryDustSnapshotQueue');
  const queueSource = queueFile.slice(queueStart, queueFile.indexOf('\n}', queueStart) + 2);
  const queueContext = { exports: {} };
  vm.runInNewContext(ts.transpileModule(queueSource, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, queueContext);
  const queue = queueContext.exports.HistoryDustSnapshotQueue;
  let activeCaptures = 0, maximumCaptures = 0;
  await Promise.all([0, 1, 2, 3].map(index => queue.capture(async () => {
    activeCaptures++; maximumCaptures = Math.max(maximumCaptures, activeCaptures);
    await new Promise(resolve => setImmediate(resolve)); activeCaptures--;
    if (index === 1) throw Error('snapshot unavailable');
    return bitmap;
  }).catch(() => null)));
  assert.equal(maximumCaptures, 1, 'clear-all snapshots are serialized, including after a failed capture');
  console.log('PASS: compiled history dust: immediate persistence, atomic clear with folded entries, reentry, real pixel tiles, intermediate drift/fade, source units and cleanup.');
})().catch(error => { console.error(error); process.exitCode = 1; });
