const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/HomePage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const callbackFile = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/PlaybackViewportFrameCallback.ts';
const callbackAst = ts.createSourceFile(callbackFile, fs.readFileSync(callbackFile, 'utf8'), ts.ScriptTarget.Latest, true);
const callback = callbackAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'PlaybackViewportFrameCallback');
const page = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'HomePage');
assert.ok(callback && page, 'compiled home prefetch structures must exist');

const methods = ['syncPlaybackListPrefetch', 'schedulePlaybackListPrefetch'].map(name => {
  const method = page.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(ast) === name);
  assert.ok(method, `${name} must survive CompileArkTS`);
  return method.getText(ast);
});

const callbacks = [];
const context = {
  exports: {},
  FrameCallback: class {},
  AppStorage: { get: key => key === 'defaultVideoQn' ? 120 : undefined },
  RecommendItem: class {}
};
vm.runInNewContext(ts.transpileModule(`${callback.getText(callbackAst)}\nexport class Subject { ${methods.join('\n')} }\n({ Subject, PlaybackViewportFrameCallback });`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);

const subject = Object.assign(new context.exports.Subject(), {
  isPageActive: true,
  playbackHomeActive: true,
  playbackHomeChannel: 2,
  REFRESH_SEPARATOR_ID: '__refresh__',
  playbackVisibleIndexes: new Set([5, 50000]),
  playbackListStart: 49999,
  playbackPrefetchScheduled: false,
  getUIContext: () => ({
    postFrameCallback: value => callbacks.push(value)
  })
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
    throw new Error('an active viewport must not pause');
  },
  updateViewport(visible, nearby, qn) {
    snapshots.push({ visible: visible.map(item => item.id), nearby: nearby.map(item => item.id), qn });
  }
};

subject.syncPlaybackListPrefetch();
const firstReads = indexedReads;
assert.equal(JSON.stringify(snapshots[0]), JSON.stringify({
  visible: ['5', '50000'],
  nearby: Array.from({ length: 8 }, (_, index) => String(49999 + index)),
  qn: 120
}), 'indexed lookup retains visible order and nearby entries');
assert.ok(firstReads < 20, `large feed must not be filtered in full (${firstReads} indexed reads)`);

subject.schedulePlaybackListPrefetch();
subject.schedulePlaybackListPrefetch();
subject.schedulePlaybackListPrefetch();
assert.equal(callbacks.length, 1, 'multiple visible events in one frame share a callback');
callbacks.shift().onFrame(0);
assert.equal(subject.playbackPrefetchScheduled, false);
assert.equal(snapshots.length, 2, 'the coalesced frame publishes exactly once');

subject.schedulePlaybackListPrefetch();
callbacks.shift().onFrame(0);
assert.equal(snapshots.length, 3, 'later visibility events schedule a new frame');

console.log(`PASS home prefetch indexed viewport and per-frame coalescing (${firstReads} indexed reads)`);
