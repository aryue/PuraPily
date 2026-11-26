const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '../entry/src/main/ets');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const ability = read('entryability/EntryAbility.ets');
const profile = read('pages/ProfilePage.ets');
const statusBars = read('utils/StatusBarUtils.ets').replace(/^import .*;\n/gm, '');

function method(source, name) {
  const start = source.search(new RegExp(`^  private (?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}

async function main() {
  const saved = new Map([
    ['hideNavigationIndicator', true], ['screenOrientationLock', '锁定竖屏'],
    ['landscapePlaybackSide', 'right'], ['playbackKernel', 'ijk'],
    ['danmakuApiSource', 'xml'], ['recommendApiSource', 'Web'], ['sponsorBlockEnabled', true]
  ]);
  const active = new Map();
  const pending = new Map();
  let reads = 0;
  const pref = {
    getSync: (key, fallback) => { reads++; return saved.has(key) ? saved.get(key) : fallback; },
    putSync: (key, value) => pending.set(key, value),
    flushSync: () => { for (const [key, value] of pending) saved.set(key, value); pending.clear(); }
  };
  const barCalls = [];
  const orientations = [];
  let inset = 24;
  const win = {
    getUIContext: () => ({ px2vp: n => n }),
    getWindowAvoidArea: () => ({ topRect: { height: 40 }, bottomRect: { height: inset } }),
    setWindowLayoutFullScreen: async () => {},
    setWindowSystemBarProperties: async () => {},
    setSpecificSystemBarEnabled: async (name, enabled) => {
      assert.ok(['status', 'navigationIndicator'].includes(name), `unsupported bar ${name}`);
      barCalls.push([name, enabled]);
    },
    setPreferredOrientation: async value => orientations.push(value)
  };
  const unexpectedError = (...args) => { throw new Error(args.join(' ')); };
  const context = {
    exports: {}, DOMAIN: 0, TAG: 'EntryAbility', errMsg: String,
    logError: unexpectedError, logWarn: unexpectedError, hilog: { info() {}, error: unexpectedError },
    AppStorage: { get: key => active.get(key), set: (key, value) => active.set(key, value),
      setOrCreate: (key, value) => active.set(key, value) },
    RecommendFilterSettings: { loadSync() {} },
    preferences: { getPreferencesSync: (_context, options) => {
      assert.equal(options.name, 'my_app_settings');
      return pref;
    } },
    window: { getLastWindow: async () => win, AvoidAreaType: { TYPE_SYSTEM: 0, TYPE_NAVIGATION_INDICATOR: 1 },
      Orientation: { PORTRAIT: 1, AUTO_ROTATION_LANDSCAPE: 2, AUTO_ROTATION: 3, AUTO_ROTATION_RESTRICTED: 4 } }
  };
  const source = `${statusBars}
    export class Ability { ${['loadCardSettings', 'setupImmersiveWindow', 'applyOrientationLockFromPrefs']
      .map(name => method(ability, name)).join('\n')} }
    export class Profile { ${method(profile, 'referenceSaveBoolean')} }
  `;
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const { Ability, Profile, StatusBarUtils } = context.exports;
  const instance = new Ability();
  instance.cellularPrefetchLaunchOverride = null;
  const page = new Profile();
  page.getUIContext = () => ({ getHostContext: () => ({}) });

  instance.loadCardSettings();
  for (const [key, value] of saved) assert.equal(active.get(key), value, key);
  await instance.setupImmersiveWindow();
  assert.deepEqual(barCalls, [['navigationIndicator', false], ['status', true]]);
  assert.equal(active.get('navIndicatorHeight'), 12);
  inset = 0;
  await instance.setupImmersiveWindow();
  assert.equal(active.get('navIndicatorHeight'), 12, 'keep the measured inset when a hidden bar reports zero');

  const startupReads = reads;
  active.set('hideNavigationIndicator', false);
  active.set('screenOrientationLock', '锁定横屏');
  await instance.setupImmersiveWindow();
  await instance.applyOrientationLockFromPrefs();
  assert.equal(reads, startupReads, 'window setup uses the current preference even if disk has an older value');
  assert.deepEqual(barCalls.at(-1), ['navigationIndicator', true]);
  assert.deepEqual(orientations, [2]);
  await StatusBarUtils.setSystemBars(win, true, false);
  assert.deepEqual(barCalls.slice(-2), [['navigationIndicator', false], ['status', true]]);

  for (const value of [false, true, false, true]) {
    assert.equal(page.referenceSaveBoolean('hideNavigationIndicator', value), true);
    assert.equal(saved.get('hideNavigationIndicator'), value, 'the latest toggle is on disk before the handler returns');
  }
  assert.equal(page.referenceSaveBoolean('floatingBottomBar', false), true);
  assert.equal(saved.get('floatingBottomBar'), false);
  active.clear();
  instance.loadCardSettings();
  assert.equal(active.get('hideNavigationIndicator'), true, 'cold start restores the last saved toggle');
  console.log('Settings persistence: cold start, foreground, navigation visibility, inset and rapid toggles passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
