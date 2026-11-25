const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = path.resolve(__dirname, '../entry/src/main/ets');
const Orientation = { AUTO_ROTATION: 0, PORTRAIT: 1, LANDSCAPE: 2, PORTRAIT_INVERTED: 3,
  LANDSCAPE_INVERTED: 4, AUTO_ROTATION_PORTRAIT: 6, AUTO_ROTATION_LANDSCAPE: 7, AUTO_ROTATION_RESTRICTED: 8 };

const pageSource = fs.readFileSync(path.join(base, 'pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const exitStart = pageSource.indexOf('  private async exitFullscreenAnimated(');
const exitEnd = pageSource.indexOf('\n  async toggleFS()', exitStart);
assert.ok(exitStart >= 0 && exitEnd > exitStart, 'exitFullscreenAnimated must exist');
const exitBody = pageSource.slice(exitStart, exitEnd);
assert.ok(exitBody.indexOf('const target = this.fullscreenReturnLandscape();') >= 0,
  'exit direction must come from fullscreenReturnLandscape');
assert.ok(exitBody.indexOf('rotateReferenceFullscreen(false, target)') >= 0,
  'locked portrait exits must reuse the same rotation path as unlocked portrait exits');
assert.ok(exitBody.indexOf('this.fs = false;\n      this.fsPanProgress') < 0,
  'exit must not snap the layout before the rotation (that turns it into a whole-page rotation)');

const returnStart = pageSource.indexOf('  private fullscreenReturnLandscape(');
const returnEnd = pageSource.indexOf('\n  }', returnStart);
assert.ok(returnStart >= 0 && returnEnd > returnStart, 'fullscreenReturnLandscape must exist');
const returnBody = pageSource.slice(returnStart, returnEnd);
assert.ok(returnBody.indexOf('Math.min(this.cw, this.ch) < 600') >= 0,
  'phone/tablet distinction must come from the short viewport side');
assert.ok(returnBody.indexOf('phoneViewport') >= 0, 'phone flag must be forwarded');

const trackerContext = { exports: {}, window: { Orientation },
  sensor: { SensorId: { GRAVITY: 257 },
    on: (_id, callback) => { trackerContext.sample = callback; },
    off: (_id, callback) => { assert.equal(callback, trackerContext.sample); trackerContext.sample = undefined; } },
  settings: { general: { ACCELEROMETER_ROTATION_STATUS: 'rotation' }, getValueSync: () => trackerContext.rotation },
  Date: { now: () => trackerContext.now }, now: 100, rotation: '1', logInfo() {} };
const trackerSource = fs.readFileSync(path.join(base, 'utils/FullscreenDeviceOrientation.ets'), 'utf8')
  .replace(/^import .*$/gm, '');
vm.runInNewContext(ts.transpileModule(trackerSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, trackerContext);

const tracker = new trackerContext.exports.FullscreenDeviceOrientation();
tracker.start();
const target = (policy, current, phone) => tracker.returnLandscape(policy, current, phone, {});

// 未锁定：按实际方向（最近 800ms 采样），无样本回进入前方向。
trackerContext.sample({ x: 9, y: 0, z: 0 });
assert.equal(target(Orientation.AUTO_ROTATION, false, true), true, 'unlocked landscape phone follows gravity');
assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED, false, true), true, 'unlocked restricted policy follows gravity');
trackerContext.now += 900;
trackerContext.sample({ x: 0, y: 0, z: 9 });
assert.equal(target(Orientation.AUTO_ROTATION, true, true), true, 'flat/unavailable sample keeps the entry direction');

// 已锁定：手机固定竖屏（即使进入全屏时是横屏、重力仍是横屏）。
trackerContext.rotation = '0';
trackerContext.sample({ x: 9, y: 0, z: 0 });
assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED, true, true), false,
  'locked phone returns portrait regardless of entry direction or gravity');

// 已锁定：平板保持当前锁定方向 —— 有新鲜重力样本时按样本，无样本按进入前方向。
assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED, false, false), true,
  'locked tablet in landscape keeps landscape');
trackerContext.sample({ x: 0, y: 9, z: 0 });
assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED, true, false), false,
  'locked tablet in portrait keeps portrait');
trackerContext.now += 900;
trackerContext.sample({ x: 0, y: 0, z: 9 });
assert.equal(target(Orientation.AUTO_ROTATION_RESTRICTED, true, false), true,
  'flat locked tablet falls back to the entry direction');

// 应用内显式方向锁不受系统锁影响。
assert.equal(target(Orientation.PORTRAIT, true, true), false, 'explicit portrait lock');
assert.equal(target(Orientation.AUTO_ROTATION_LANDSCAPE, false, false), true, 'explicit landscape lock');
tracker.stop();

console.log('test-fs-exit-lock-policy: PASS — locked phone always returns portrait through the same rotation path as unlocked portrait exits; locked tablet keeps its locked direction.');
