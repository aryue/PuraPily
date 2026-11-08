const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const code = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/HighRefreshService.ets'), 'utf8');
function setup(saved = 0, supported = [60, 90, 120, 144]) {
  const storage = new Map();
  const data = new Map([['highRefreshRate', saved]]);
  const calls = [];
  let listener;
  let failRate = -1;
  let failFlush = false;
  const screen = { supportedRefreshRates: supported };
  const pref = {
    getSync: (key, fallback) => data.get(key) ?? fallback,
    putSync: (key, value) => data.set(key, value),
    flushSync: () => { if (failFlush) throw Error('disk failure'); }
  };
  const context = { exports: {}, AppStorage: { setOrCreate: (k, v) => storage.set(k, v) },
    require: name => {
      if (name === '@kit.ArkUI') return { display: {
        getDefaultDisplaySync: () => screen,
        getDisplayByIdSync: id => { assert.equal(id, 7); return screen; },
        on: (_event, fn) => { listener = fn; }, off: (_event, fn) => { assert.equal(listener, fn); listener = null; }
      } };
      if (name === '@kit.ArkData') return { preferences: { getPreferencesSync: () => pref } };
      if (name === 'libhigh_refresh.so') return { default: { setRate: rate => { calls.push(rate); return rate === failRate ? -1 : 0; } } };
      return { logInfo() {}, logError() {} };
    }
  };
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
  } }).outputText, context);
  const service = context.exports.HighRefreshService.getInstance();
  service.initialize({});
  return { service, storage, data, calls, screen, change: () => listener(7),
    failNative: rate => { failRate = rate; }, failPersistence: () => { failFlush = true; } };
}

for (const rate of [90, 120, 144]) {
  const t = setup(rate);
  t.service.setMainWindow({ getWindowProperties: () => ({ displayId: 7 }) });
  assert.deepEqual(t.calls, [], 'initialization must not request in the background');
  t.service.setForeground(true);
  t.service.setForeground(true);
  assert.deepEqual(t.calls, [rate], 'foreground must start one request');
  t.service.setForeground(false);
  t.service.setForeground(false);
  assert.deepEqual(t.calls, [rate, 0], 'background must release once');
  t.service.setForeground(true);
  t.service.choose(0);
  assert.deepEqual(t.calls, [rate, 0, rate, 0]);
  assert.equal(t.data.get('highRefreshRate'), 0);
  t.service.destroy();
}
{
  const t = setup(120, [60, 120, 120, 165]);
  assert.deepEqual(Array.from(t.service.supportedRates()), [120]);
  t.service.setForeground(true);
  assert.throws(() => t.service.choose(90));
  t.screen.supportedRefreshRates = [60];
  t.change();
  assert.deepEqual(t.calls, [120, 0]);
  assert.equal(t.storage.get('highRefreshAvailable'), false);
  assert.equal(t.data.get('highRefreshRate'), 120, 'screen changes must preserve preference');
  t.screen.supportedRefreshRates = [60, 120];
  t.change();
  assert.deepEqual(t.calls, [120, 0, 120]);
  t.service.destroy();
}
for (const support of [[], undefined, [60, 144]]) {
  const t = setup(90);
  t.screen.supportedRefreshRates = support;
  const expected = support?.includes(144) ? [144] : [];
  assert.deepEqual(Array.from(t.service.supportedRates()), expected, 'never infer lower modes from the maximum');
  t.service.setForeground(true);
  assert.deepEqual(t.calls, []);
  t.service.destroy();
}
for (const fail of ['native', 'persistence']) {
  const t = setup(90);
  t.service.setForeground(true);
  if (fail === 'native') t.failNative(120); else t.failPersistence();
  assert.throws(() => t.service.choose(120));
  assert.equal(t.storage.get('highRefreshRate'), 90);
  assert.equal(t.data.get('highRefreshRate'), 90);
  assert.deepEqual(t.calls, [90, 120, 90], 'failure must restore the running request');
  t.service.destroy();
}

// Exercise the menu method emitted by CompileArkTS, including dynamic tuples and cancel.
const compiled = fs.readFileSync(path.join(root, 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/ProfilePage.ts'), 'utf8');
const start = compiled.indexOf('    private async selectSetting(');
assert.ok(start >= 0, 'CompileArkTS must emit the menu method');
const method = compiled.slice(start, compiled.indexOf('\n    }', start) + 6);
(async () => {
  for (const support of [[], [90], [120, 144], [90, 120, 144]]) {
    for (const index of [-1, ...Array.from({ length: support.length + 1 }, (_, i) => i), 99]) {
      let menu;
      const choices = [];
      const context = { exports: {}, HighRefreshService: { getInstance: () => ({ supportedRates: () => support, choose: r => choices.push(r) }) }, logError() {} };
      vm.runInNewContext(ts.transpileModule(`export class Menu { ${method} }`, {
        compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
      }).outputText, context);
      const page = new context.exports.Menu();
      page.highRefreshRate = support[0] ?? 0;
      page.highRefreshSupportedRates = support;
      page.settingLabels = () => ['跟随系统', ...support.map(r => `${r} Hz`)];
      page.getUIContext = () => ({ getPromptAction: () => ({ showActionMenu: async m => { menu = m; return { index }; } }) });
      await page.selectSetting('refresh', index);

      assert.deepEqual(choices, index >= 0 && index <= support.length ? [[0, ...support][index]] : []);
    }
  }
  console.log('High refresh: supported modes, lifecycle, display changes, persistence/failure rollback and compiled menu passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
