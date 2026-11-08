const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const profile = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ProfilePage.ets'), 'utf8');
const ability = fs.readFileSync(path.join(root, 'entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8');
const gate = fs.readFileSync(path.join(root, 'entry/src/main/ets/utils/NetworkGate.ets'), 'utf8');

function method(source, name) {
  const start = source.search(new RegExp(`^  private (?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, 'missing method ' + name);
  const end = source.indexOf('\n  }', start);
  assert.ok(end > start, 'unterminated method ' + name);
  return source.slice(start, end + 4);
}

function run(source, imports) {
  const context = vm.createContext(Object.assign({ exports: {} }, imports));
  vm.runInContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

// 1. The settings row must exist and be bound to the same AppStorage key NetworkGate reads.
assert.match(profile, /@StorageLink\('cellularPrefetch'\) cellularPrefetch: boolean = false/);
assert.match(profile, /this\.SectionTitle\('网络与流量'\)/);
assert.match(profile, /Toggle\(\{ type: ToggleType\.Switch, isOn: this\.cellularPrefetch \}\)/);
assert.match(profile, /\.id\('setting-cellular-prefetch'\)/);
assert.match(profile, /\.onChange\(\(value: boolean\) => \{ this\.saveCellularPrefetch\(value\); \}\)/);
assert.match(gate, /AppStorage\.get<boolean>\('cellularPrefetch'\) === true/,
  'the toggle and NetworkGate must share the same key');

(async () => {
  // 2. Toggling writes AppStorage immediately (live gate change) and persists for the next launch.
  const shared = new Map();
  const stored = new Map();
  const toasts = [];
  let flushFails = false;
  const { Page } = run(`export class Page { ${['referenceSaveBoolean', 'saveCellularPrefetch']
    .map(name => method(profile, name)).join('\n')} }`, {
    logError() {},
    AppStorage: { setOrCreate: (key, value) => shared.set(key, value) }
  });
  const page = new Page();
  page.dataPreferences = {
    put: async (key, value) => stored.set(key, value),
    flush: async () => { if (flushFails) throw new Error('flush failed'); }
  };
  page.getUIContext = () => ({ getPromptAction: () => ({ showToast: m => toasts.push(m.message) }) });

  await page.saveCellularPrefetch(true);
  assert.equal(shared.get('cellularPrefetch'), true, 'AppStorage must change immediately');
  assert.equal(stored.get('cellularPrefetch'), true, 'the setting must persist to my_app_settings');
  assert.equal(toasts.length, 1, 'opening the risky option warns about mobile data');
  await page.saveCellularPrefetch(false);
  assert.equal(shared.get('cellularPrefetch'), false, 'turning it off must restore the default gate');
  assert.equal(stored.get('cellularPrefetch'), false);
  assert.equal(toasts.length, 1, 'closing the option stays silent');
  flushFails = true;
  await page.saveCellularPrefetch(true);
  assert.equal(shared.get('cellularPrefetch'), true, 'a failed flush must not roll back the live gate');

  // 3. Cold start restores the saved value; a launch-time --ps flag overrides it without writing preferences.
  const saved = new Map();
  const restored = new Map();
  const writes = [];
  const { Ability } = run(`export class Ability { ${method(ability, 'loadCardSettings')} }`, {
    DOMAIN: 0, TAG: 'EntryAbility',
    hilog: { info() {}, error(msg) { throw new Error(msg); } },
    PersistentStorage: { persistProp() {} },
    AppStorage: { setOrCreate: (key, value) => restored.set(key, value) },
    preferences: { getPreferences: async () => ({
      get: async (key, fallback) => saved.has(key) ? saved.get(key) : fallback,
      put: async (key, value) => writes.push([key, value])
    }) }
  });
  const instance = new Ability();
  instance.context = {};
  for (const [savedValue, override, expected] of [
    [undefined, null, false],
    [true, null, true],
    [true, false, false],
    [false, true, true],
    [undefined, true, true]
  ]) {
    saved.clear();
    if (savedValue !== undefined) saved.set('cellularPrefetch', savedValue);
    instance.cellularPrefetchLaunchOverride = override;
    restored.clear();
    writes.length = 0;
    await instance.loadCardSettings();
    assert.equal(restored.get('cellularPrefetch'), expected,
      `saved=${String(savedValue)} --ps=${String(override)} must activate ${String(expected)}`);
    assert.ok(!writes.some(([key]) => key === 'cellularPrefetch'),
      'the --ps override must never be written back to preferences');
  }
  assert.ok(ability.indexOf("this.cellularPrefetchLaunchOverride = String(want.parameters['cellularPrefetch'])") <
    ability.indexOf('this.loadCardSettings();'), 'the --ps flag must be parsed before the async restore');

  console.log('Cellular prefetch setting: UI binding, live gate change, persistence and cold-start override passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
