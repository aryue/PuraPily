const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const etsRoot = path.join(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(etsRoot, 'services/BackgroundPlaybackPreference.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

let saved, legacy = true, flushed = 0;
const pref = {
  getSync(key, fallback) { assert.equal(key, 'bgp'); return saved ?? fallback; },
  putSync(key, value) { assert.equal(key, 'bgp'); saved = value; },
  flushSync() { flushed++; }
};

function start() {
  const app = new Map();
  const context = {
    exports: {},
    require: () => ({ preferences: { getPreferencesSync(_ctx, options) {
      assert.equal(options.name, 'my_app_settings');
      return pref;
    } }, logWarn: assert.fail }),
    AppStorage: { get: key => app.get(key), setOrCreate: (key, value) => app.set(key, value) },
    PersistentStorage: {
      persistProp(key, fallback) { app.set(key, legacy ?? fallback); },
      deleteProp(key) { legacy = undefined; app.delete(key); }
    }
  };
  vm.runInNewContext(compiled, context);
  context.exports.restoreBackgroundPlayback({});
  return { app, set: enabled => context.exports.setBackgroundPlayback({}, enabled) };
}

const first = start();
assert.equal(first.app.get('bgp'), true);
assert.equal(saved, true);
assert.equal(legacy, undefined);
assert.equal(flushed, 1, 'migrate a legacy value once');
first.set(false);
assert.equal(first.app.get('bgp'), false);
legacy = true;
const second = start();
assert.equal(second.app.get('bgp'), false, 'persisted false takes priority over the legacy store');
second.set(true);
assert.equal(start().app.get('bgp'), true, 'the latest toggle survives a fresh process');
console.log('PASS: background playback preference migration and restart');
