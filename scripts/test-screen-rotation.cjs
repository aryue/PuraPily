const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const Orientation = { AUTO_ROTATION: 0, PORTRAIT: 1, LANDSCAPE: 2, PORTRAIT_INVERTED: 3,
  LANDSCAPE_INVERTED: 4, AUTO_ROTATION_PORTRAIT: 6, AUTO_ROTATION_LANDSCAPE: 7, AUTO_ROTATION_RESTRICTED: 8 };
const store = new Map();
const barCalls = [];
function load(file, methods) {
  const source = fs.readFileSync(path.join(base, file), 'utf8');
  const bodies = methods.map(name => {
    const start = source.indexOf(`  private ${name}`);
    assert.ok(start >= 0, name);
    const end = source.indexOf('\n  }', start);
    return source.slice(start, end + 4);
  }).join('\n');
  const context = { exports: {}, window: { Orientation },
    StatusBarUtils: { setPlayerStatusBarContent() {}, restoreThemeStatusBarContent() {},
      setSystemBars: (_win, status, nav) => barCalls.push([status, nav]) },
    AppStorage: { get: key => store.get(key), setOrCreate: (key, value) => store.set(key, value) },
    setTimeout: () => 0, logInfo() {}, logWarn() {}, logError() {}, errMsg: String,
    VibrateUtils: { vibratePreset() {} } };
  vm.runInNewContext(ts.transpileModule(`export class Page { ${bodies} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return new context.exports.Page();
}
(async () => {
  for (const file of ['pages/VideoPlayerPage.ets', 'pages/LivePlayerPage.ets']) {
    const methods = ['async applyRotationMode():'];
    if (file.includes('LivePlayerPage')) methods.push('rotationOrientation():');
    const p = load(file, methods);
    const applied = [];
    Object.assign(p, { mw: { setPreferredOrientation: async value => applied.push(value) },
      triggerHaptic() {}, isWindowLandscape: () => false,
      getUIContext: () => ({ getPromptAction: () => ({ showToast() {} }) }) });
    for (const [mode, expected] of [['system', 8], ['auto', 0], ['portrait', 1], ['landscape', 7]]) {
      p.rotationMode = mode;
      await p.applyRotationMode();
      assert.equal(applied.at(-1), expected, `${file}: ${mode}`);
    }
  }
  const trackerContext = { exports: {}, window: { Orientation },
    sensor: { SensorId: { GRAVITY: 257 },
      on: (_id, callback) => { trackerContext.sample = callback; },
      off: (_id, callback) => { assert.equal(callback, trackerContext.sample); trackerContext.sample = undefined; } },
    settings: { general: { ACCELEROMETER_ROTATION_STATUS: 'rotation' }, getValueSync: () => trackerContext.rotation },
    Date: { now: () => trackerContext.now }, now: 100, rotation: '1' };
  const trackerSource = fs.readFileSync(path.join(base, 'utils/FullscreenDeviceOrientation.ets'), 'utf8')
    .replace(/^import .*$/gm, '');
  vm.runInNewContext(ts.transpileModule(trackerSource, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, trackerContext);
  const tracker = new trackerContext.exports.FullscreenDeviceOrientation();
  tracker.start();
  const target = (policy, current = true) => tracker.returnLandscape(policy, current, {});
  assert.equal(target(Orientation.AUTO_ROTATION), true, 'missing data falls back to the current window');
  trackerContext.sample({ x: 1, y: 9, z: 0 });
  assert.equal(target(Orientation.AUTO_ROTATION), false, 'upright device can return directly to portrait');
  assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED), false);
  trackerContext.rotation = '0';
  assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED), true, 'respect system auto-rotation lock');
  assert.equal(target(Orientation.AUTO_ROTATION_LANDSCAPE), true, 'respect app landscape lock');
  trackerContext.sample({ x: -9, y: 1, z: 0 });
  assert.equal(target(Orientation.AUTO_ROTATION, false), true, 'sideways device can return directly to landscape');
  assert.equal(target(Orientation.PORTRAIT), false, 'respect app portrait lock');
  trackerContext.now += 900;
  trackerContext.sample({ x: 0, y: 0, z: 9 });
  assert.equal(target(Orientation.AUTO_ROTATION, false), false, 'flat data cannot revive a stale sample');
  tracker.stop();
  assert.equal(trackerContext.sample, undefined);
  const p = load('pages/VideoPlayerPage.ets', ['async restoreOrientationOnly():']);
  const applied = [];
  Object.assign(p, { fullscreenDeviceOrientation: { stop() {} },
    mw: { disableLandscapeMultiWindow: async () => {}, setPreferredOrientation: async value => applied.push(value) } });
  for (const [setting, expected] of [[undefined, 8], ['跟随系统', 8], ['自动旋转', 0], ['锁定竖屏', 1], ['锁定横屏', 7]]) {
    store.clear();
    if (setting !== undefined) store.set('screenOrientationLock', setting);
    await p.restoreOrientationOnly();
    assert.equal(applied.at(-1), expected, `fullscreen exit: ${setting ?? 'default'}`);
  }
  const bars = load('pages/VideoPlayerPage.ets', ['manageSB(']);
  Object.assign(bars, { mw: {}, referenceAlive: true, playerPageVisible: true,
    referenceLayout: true, referenceFeed: false, referenceInfoHidden: false, sh_: false, isLightsOff: false });
  for (const isLs of [false, true]) {
    bars.isLs = isLs;
    bars.fs = false;
    bars.manageSB(true);
    assert.deepEqual(barCalls.at(-1), [true, !isLs], 'half-screen keeps status visible and hides landscape navigation indicator');
    bars.fs = true;
    bars.manageSB(true);
    assert.deepEqual(barCalls.at(-1), [false, false], 'fullscreen stays immersive');
  }
  bars.fs = false; bars.isLightsOff = true; bars.manageSB(true);
  assert.deepEqual(barCalls.at(-1), [false, false], 'lights off remains immersive');
  bars.isLightsOff = false; bars.playerPageVisible = false;
  const count = barCalls.length; bars.manageSB(true);
  assert.equal(barCalls.length, count, 'hidden page must not overwrite system bars');
  const restore = load('pages/VideoPlayerPage.ets', ['async restoreS()']);
  Object.assign(restore, { mw: { setPreferredOrientation: async () => {} },
    getUIContext: () => ({ getHostContext: () => ({}) }) });
  for (const isLandscape of [false, true]) {
    store.set('isLandscape', isLandscape);
    await restore.restoreS();
    assert.deepEqual(barCalls.at(-1), [true, true], 'leaving playback restores bars regardless of the old player viewport');
  }
  console.log('Rotation: system/default policy, explicit modes, lock/unlock and fullscreen restoration passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
