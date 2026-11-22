const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.join(__dirname, '../entry/src/main/ets');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const sampler = read('utils/PlayerStatusSampler.ets');
const controls = read('components/VideoControls.ets');
const page = read('pages/VideoPlayerPage.ets');
const live = read('pages/LivePlayerPage.ets');

assert.doesNotMatch(page, /coverGlowAngle|coverGlowTimer|onContentVisibleChange/);
assert.match(page, /statusStripAllowed: this\.playerPageVisible && !this\.appInBackground && !this\.referenceCleanViewing\(\)/);
assert.match(controls, /this\.statusOwnerAttached && this\.statusStripAllowed && this\.isControlsVisible &&\s*!this\.hidePlaybackControls && this\.statusStripLayout\(\) !== ''/);
assert.match(live, /samplingVisible: !this\.pageHidden && !this\.appInBackground && this\.informationVisible/);

const intervals = new Map();
const pendingRx = [];
const pendingTx = [];
let timerId = 0;
let now = 1000;
let charge = 41;
const context = {
  exports: {},
  Observed: (value) => value,
  Date: class extends Date { static now() { return now; } },
  setInterval(callback, delay) {
    assert.equal(delay, 1000);
    intervals.set(++timerId, callback);
    return timerId;
  },
  clearInterval(id) { intervals.delete(id); },
  require(name) {
    if (name === '@kit.BasicServicesKit') {
      return { batteryInfo: { get batterySOC() { return charge; }, chargingStatus: 0, BatteryChargeState: { ENABLE: 1 } } };
    }
    assert.equal(name, '@kit.NetworkKit');
    return { statistics: {
      getAllRxBytes: () => new Promise((resolve) => pendingRx.push(resolve)),
      getAllTxBytes: () => new Promise((resolve) => pendingTx.push(resolve))
    } };
  }
};
vm.runInNewContext(ts.transpileModule(sampler, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
}).outputText, context);

const flush = () => new Promise((resolve) => setImmediate(resolve));
async function resolveSample(rx, tx) {
  pendingRx.shift()(rx);
  await flush();
  pendingTx.shift()(tx);
  await flush();
}

async function main() {
  const status = new context.exports.PlayerStatusSampler();
  status.start();
  status.start();
  assert.equal(intervals.size, 1);
  assert.equal(pendingRx.length, 1);
  assert.equal(status.batteryText, '41%');
  assert.match(status.clockText, /^\d\d:\d\d$/);
  const firstTick = intervals.get(timerId);
  firstTick();
  assert.equal(pendingRx.length, 1, 'polls in the same visibility session never overlap');
  await resolveSample(100, 200);
  assert.equal(status.speedText, '--', 'first reading only captures the byte baseline');
  now = 2000;
  firstTick();
  await resolveSample(400, 500);
  assert.equal(status.speedText, '600B/s');

  firstTick();
  pendingRx.shift()(700);
  await flush();
  const staleTx = pendingTx.shift();
  status.stop();
  firstTick();
  assert.equal(intervals.size, 0);
  assert.equal(pendingRx.length, 0, 'a queued callback cannot sample after hide');

  now = 10000;
  charge = 18;
  status.start();
  await resolveSample(12000, 22000);
  assert.equal(status.speedText, '--', 'hidden traffic does not become the next visible sample');
  assert.equal(status.batteryText, '18%');
  assert.equal(status.isLowBattery, true);
  staleTx(900);
  await flush();
  assert.equal(status.speedText, '--', 'a hidden session cannot publish after reopening');

  now = 11000;
  intervals.get(timerId)();
  await resolveSample(12010, 22020);
  assert.equal(status.speedText, '30B/s');
  status.stop();
  assert.equal(intervals.size, 0);
  console.log('PASS: player status sampling follows visibility and discards stale traffic samples');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
