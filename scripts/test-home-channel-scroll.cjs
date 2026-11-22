const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const cache = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets';
const offsetSource = fs.readFileSync(`${cache}/utils/HomeScrollOffset.ts`, 'utf8');
const offsetContext = {
  exports: {}, AppStorage: (() => {
    const values = new Map();
    const sets = [];
    return {
      sets,
      get: key => values.get(key),
      setOrCreate: (key, value) => { values.set(key, value); sets.push([key, value]); }
    };
  })()
};
vm.runInNewContext(ts.transpileModule(offsetSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, offsetContext);

offsetContext.exports.publishHomeScrollOffset(-4);
offsetContext.exports.publishHomeScrollOffset(0);
offsetContext.exports.publishHomeScrollOffset(12.5);
offsetContext.exports.publishHomeScrollOffset(12.5);
assert.deepEqual(Array.from(offsetContext.AppStorage.sets, entry => entry[1]), [0, 12.5],
  'shared home offset clamps negative values and publishes only changes');

for (const [page, call] of [
  ['LivePage.ts', 'publishHomeScrollOffset(absoluteOffset)'],
  ['PgcChannelPage.ts', 'publishHomeScrollOffset(absoluteOffset)'],
  ['RegionChannelPage.ts', 'publishHomeScrollOffset(offset)']
]) {
  const source = fs.readFileSync(`${cache}/pages/${page}`, 'utf8');
  assert.ok(source.includes(call), `${page} must publish through the shared deduplicating helper`);
  assert.ok(!/AppStorage\.set(?:OrCreate)?\('homeScrollOffset'/.test(source),
    `${page} must not bypass offset deduplication`);
}

const discoverFile = `${cache}/pages/DiscoverPage.ts`;
const discoverAst = ts.createSourceFile(discoverFile, fs.readFileSync(discoverFile, 'utf8'), ts.ScriptTarget.Latest, true);
const discover = discoverAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'DiscoverPage');
assert.ok(discover, 'compiled DiscoverPage must exist');
const names = ['syncPlaybackListPrefetch', 'schedulePlaybackListPrefetch', 'resetPlaybackViewportAfterRemoval'];
const methods = names.map(name => {
  const method = discover.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(discoverAst) === name);
  assert.ok(method, `${name} must survive CompileArkTS`);
  return method.getText(discoverAst);
});

const callbackFile = `${cache}/utils/PlaybackViewportFrameCallback.ts`;
const callbackAst = ts.createSourceFile(callbackFile, fs.readFileSync(callbackFile, 'utf8'), ts.ScriptTarget.Latest, true);
const callback = callbackAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'PlaybackViewportFrameCallback');
const context = {
  exports: {},
  FrameCallback: class {},
  RecommendItem: class {},
  AppStorage: { get: key => key === 'defaultVideoQn' ? 116 : undefined }
};
vm.runInNewContext(ts.transpileModule(`${callback.getText(callbackAst)}
export class Subject { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

const callbacks = [];
const subject = Object.assign(new context.exports.Subject(), {
  isPageActive: true,
  playbackHomeActive: true,
  playbackHomeChannel: 3,
  playbackVisibleIndexes: new Set([50000, 4]),
  playbackFirstIndex: 0,
  playbackPrefetchScheduled: false,
  getUIContext: () => ({ postFrameCallback: value => callbacks.push(value) })
});
const items = Array.from({ length: 100000 }, (_, id) => ({ id: String(id) }));
let indexedReads = 0;
const indexedItems = new Proxy(items, {
  get(target, property, receiver) {
    if (/^\d+$/.test(String(property))) indexedReads++;
    return Reflect.get(target, property, receiver);
  }
});
const snapshots = [];
subject.dataSource = { getRawItems: () => indexedItems };
subject.playbackListPrefetch = {
  pause() {
    throw new Error('an active popular viewport must not pause');
  },
  updateViewport(visible, nearby, qn) {
    snapshots.push({
      visible: visible.map(item => item.id),
      nearby: nearby.map(item => item.id),
      qn
    });
  }
};

subject.syncPlaybackListPrefetch();
const firstReads = indexedReads;
assert.equal(JSON.stringify(snapshots[0].visible), JSON.stringify(['4', '50000']));
assert.equal(snapshots[0].nearby[0], '4');
assert.equal(snapshots[0].qn, 116);
assert.ok(firstReads < 20, `popular page must index only visible entries (${firstReads} reads)`);

subject.schedulePlaybackListPrefetch();
subject.schedulePlaybackListPrefetch();
subject.schedulePlaybackListPrefetch();
assert.equal(callbacks.length, 1, 'popular visibility changes coalesce into one frame');
callbacks.shift().onFrame(0);
assert.equal(snapshots.length, 2);

subject.resetPlaybackViewportAfterRemoval();
assert.equal(subject.playbackVisibleIndexes.size, 0);
assert.equal(subject.playbackFirstIndex, 0);
assert.equal(callbacks.length, 1, 'removing a card invalidates stale indices and schedules a refresh');

const indexFile = `${cache}/pages/Index.ts`;
const indexAst = ts.createSourceFile(indexFile, fs.readFileSync(indexFile, 'utf8'), ts.ScriptTarget.Latest, true);
const indexPage = indexAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'Index');
const selectTab = indexPage.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(indexAst) === 'selectTab');
const indexStorage = new Map();
const indexContext = {
  exports: {},
  AppStorage: {
    get: key => indexStorage.get(key),
    setOrCreate: (key, value) => indexStorage.set(key, value)
  }
};
vm.runInNewContext(ts.transpileModule(`export class Subject { ${selectTab.getText(indexAst)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, indexContext);
const index = Object.assign(new indexContext.exports.Subject(), {
  activeTab: 0,
  homeScrollOffset: 240,
  lastExitBackTime: 0
});
index.selectTab(0);
assert.ok(indexStorage.get('scrollToTopFlag') > 0, 'home reselect still requests feed top');
assert.equal(indexStorage.get('refreshHomeFlag'), undefined, 'a scrolled feed scrolls instead of refreshing');
assert.equal(indexStorage.get('homeBarsHidden'), undefined, 'a visible home tab must not rewrite header visibility');
assert.equal(indexStorage.get('tabBarHidden'), undefined);

for (const [page, channel] of [['HomePage.ts', 2], ['DiscoverPage.ts', 3], ['LivePage.ts', 1]]) {
  const source = fs.readFileSync(`${cache}/pages/${page}`, 'utf8');
  const methodStart = source.indexOf('onScrollToTop()');
  const methodEnd = source.indexOf('\n    private ', methodStart + 1);
  const method = source.slice(methodStart, methodEnd < 0 ? source.length : methodEnd);
  assert.ok(method.includes("homeChannelIndex') !== "),
    `${page} must only return its active channel to top`);
  assert.ok(method.includes(String(channel)), `${page} must check channel ${channel}`);
  if (page === 'DiscoverPage.ts') {
    assert.ok(method.includes('scrollToIndex(0'), `${page} must align the first item to the content start`);
  }
  if (page === 'LivePage.ts') {
    assert.ok(method.includes('scrollTo({ xOffset: 0, yOffset: 0'),
      'LivePage uses a Scroll and must return its padding origin to zero');
  }
}
const pgcSource = fs.readFileSync(`${cache}/pages/PgcChannelPage.ts`, 'utf8');
const pgcStart = pgcSource.indexOf('onScrollToTop()');
const pgcEnd = pgcSource.indexOf('\n    private ', pgcStart + 1);
assert.ok(pgcSource.slice(pgcStart, pgcEnd).includes('this.channelIndex'),
  'PgcChannelPage must only return its own season channel to top');
assert.ok(pgcSource.slice(pgcStart, pgcEnd).includes('scrollTo({ xOffset: 0, yOffset: 0'),
  'PgcChannelPage uses a Scroll and must return its padding origin to zero');

const regionSource = fs.readFileSync(`${cache}/pages/RegionChannelPage.ts`, 'utf8');
const regionStart = regionSource.indexOf('onScrollToTop()');
const regionEnd = regionSource.indexOf('\n    private ', regionStart + 1);
assert.ok(regionSource.slice(regionStart, regionEnd).includes('scrollToIndex(0'),
  'RegionChannelPage must align the first item to the content start');

console.log(`PASS home channel scroll publishing and popular indexed viewport (${firstReads} reads)`);
