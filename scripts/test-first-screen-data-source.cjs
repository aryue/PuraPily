const assert = require('node:assert/strict');
const fs = require('node:fs');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const modelPath = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/model/';

function loadModel(name, modules = {}) {
  const source = fs.readFileSync(modelPath + name + '.ts', 'utf8');
  const compiled = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  });
  const exports = {};
  new Function('exports', 'require', compiled.outputText)(exports, path => {
    const name = /([^/]+?)&?$/.exec(path)[1];
    assert.ok(modules[name], `Expected a test module for ${path}`);
    return modules[name];
  });
  return exports;
}

const { FirstScreenDataSource } = loadModel('FirstScreenDataSource', {
  GenericDataSource: loadModel('GenericDataSource'),
  PlaybackViewportFrameCallback: {
    PlaybackViewportFrameCallback: class {
      constructor(callback) { this.onFrame = callback; }
    }
  }
});

const queue = [];
const ui = { postFrameCallback(frame) { queue.push(frame); } };
function nextFrame() {
  assert.ok(queue.length > 0, 'a native frame must be queued');
  queue.splice(0).forEach(frame => frame.onFrame());
}

const popular = new FirstScreenDataSource();
const counts = [];
popular.registerDataChangeListener({ onDataReloaded() { counts.push(popular.totalCount()); } });
popular.replaceForViewport([1, 2, 3, 4, 5, 6, 7], 2, ui);
assert.deepEqual(counts, [2]);
assert.equal(popular.getRawItems().length, 7, 'the entire response is available immediately for data operations');
nextFrame();
assert.deepEqual(counts, [2], 'space the next batch after the first layout');
nextFrame();
assert.deepEqual(counts, [2, 4]);
assert.equal(popular.isPublishing(), true, 'the temporary bottom must not trigger pagination');
popular.removeItem(item => item === 2);
assert.deepEqual([0, 1, 2, 3].map(index => popular.getData(index)), [1, 3, 4, 5]);
popular.removeItem(item => item === 7);
nextFrame();
assert.equal(popular.isPublishing(), false);
assert.deepEqual(counts, [2, 4, 4, 5]);
assert.deepEqual(queue, []);

const dynamics = new FirstScreenDataSource();
dynamics.replaceForViewport(['old-1', 'old-2', 'old-3'], 1, ui);
dynamics.replaceForViewport([], 1, ui);
dynamics.replaceForViewport(['new-1', 'new-2'], 1, ui);
nextFrame();
assert.equal(dynamics.totalCount(), 1);
assert.equal(dynamics.getData(0), 'new-1');
nextFrame();
assert.equal(dynamics.totalCount(), 2);
dynamics.replaceForViewport(['refresh-1', 'refresh-2', 'refresh-3'], 1, ui);
assert.equal(dynamics.totalCount(), 3, 'refreshing a populated list publishes immediately');
assert.equal(queue.length, 0, 'stale scope callbacks do not restart staging');

console.log('PASS first-screen batching, feedback deletion, pagination guard and scope replacement');
