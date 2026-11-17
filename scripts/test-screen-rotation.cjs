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
const windowControls = fs.readFileSync(path.join(base, 'services/PlaybackWindow.ets'), 'utf8').replace(/^import .*$/gm, '');
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
  vm.runInNewContext(ts.transpileModule(`${windowControls}\nexport class Page { ${bodies} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const page = new context.exports.Page();
  page.playbackWindow_ = new context.exports.PlaybackWindow();
  return page;
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
  bars.playerPageVisible = true;
  bars.manageSB(false);
  const first = barCalls.length;
  bars.manageSB(false);
  assert.equal(barCalls.length, first, 'unchanged bars do not cause window relayout');
  bars.manageSB(true);
  assert.equal(barCalls.length, first + 1);
  let restored;
  const win = { getWindowProperties: () => ({ brightness: -1 }), setWindowBrightness(value) { restored = value; } };
  assert.equal(bars.playbackWindow_.captureBrightness(win), -1);
  bars.playbackWindow_.restoreBrightness(win);
  assert.equal(restored, -1, 'restore preserves system-controlled brightness');
  win.getWindowProperties = () => ({ brightness: 0.42 });
  assert.equal(bars.playbackWindow_.captureBrightness(win), 0.42);
  bars.playbackWindow_.restoreBrightness(win);
  assert.equal(restored, 0.42, 'restore preserves an explicit window brightness');
  const screenRequests = [];
  win.setWindowKeepScreenOn = async value => { screenRequests.push(value); };
  bars.playbackWindow_.keepScreenOn(win, true);
  bars.playbackWindow_.keepScreenOn(win, false);
  bars.playbackWindow_.keepScreenOn(null, true);
  assert.deepEqual(screenRequests, [true, false]);
  const restore = load('pages/VideoPlayerPage.ets', []).playbackWindow_;
  const exitWindow = { setPreferredOrientation: async () => {} };
  for (const isLandscape of [false, true]) {
    store.set('isLandscape', isLandscape);
    await restore.restoreAfterExit(exitWindow, () => ({}));
    assert.deepEqual(barCalls.at(-1), [true, true], 'leaving playback restores bars regardless of the old player viewport');
  }
  console.log('Rotation: system/default policy, explicit modes, lock/unlock and fullscreen restoration passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
