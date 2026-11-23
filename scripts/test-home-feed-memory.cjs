const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ets = path.join(__dirname, '..', 'entry', 'src', 'main', 'ets');
const read = (file) => fs.readFileSync(path.join(ets, file), 'utf8');

const container = read('components/HomeChannelContainer.ets');
assert.doesNotMatch(container, /\.cachedMaxCount\(/,
  'switching channels must keep their data, filter selections and scroll position');
assert.match(read('pages/HomePage.ets'), /reusePool: 'perInstance', poolAccepts: \[VideoCardComponent\]/,
  'the recommendation page must expose its card pool without changing the other channels');
assert.match(container, /onAnimationEnd\(\(index: number\) => \{[\s\S]*?this\.artworkTransition = false;\s*this\.onTabsChange/,
  'pool cleanup must wait for the committed channel after the transition');

const poolMethods = container.slice(container.indexOf('  private setRecommendReusePool('),
  container.indexOf('  private cancelArtworkRelease('))
  .replace(/\bprivate /g, '')
  .replace(/pool\?: IReusableInfo|event: TouchEvent/g, param => param.split(/[?:]/)[0])
  .replace(/: number/g, '')
  .replace(/\): (?:void|boolean) \{/g, ') {')
  .replace(/\.get<boolean>/g, '.get')
  .replace(/recommendReusePool!/g, 'recommendReusePool');
const restoreMethod = container.match(/  private showArtwork\([\s\S]*?\n  \}/)[0]
  .replace('private ', '').replace(/: number|: void/g, '');
const timerQueue = new Map();
const idleQueue = [];
let timerId = 0;
const appStorage = { get: () => true, setOrCreate() {} };
const touch = { Down: 0, Move: 1, Up: 2, Cancel: 3 };
const createChannel = new Function('AppStorage', 'TouchType', 'setTimeout', 'clearTimeout', 'ChannelIdleFrame', `
  const HIDDEN_RECOMMEND_CARD_LIMIT = 8;
  const RECOMMEND_POOL_QUIET_MS = 1500;
  const RECOMMEND_POOL_BATCH_SIZE = 3;
  const RECOMMEND_POOL_BATCH_INTERVAL_MS = 80;
  const RECOMMEND_POOL_IDLE_BUDGET_NS = 5_000_000;
  return new (class {
    ${poolMethods}
    ${restoreMethod}
  })();
`);
const channel = createChannel(appStorage, touch, (callback, delay) => {
  timerQueue.set(++timerId, { callback, delay });
  return timerId;
}, id => timerQueue.delete(id), class {
  constructor(run) { this.run = run; }
});
Object.assign(channel, {
  activeChannel: 2, channelIndex: 2, artworkTransition: false, channelTouching: false,
  recommendTrimTimer: -1, recommendTrimRevision: 0,
  getUIContext: () => ({ postFrameCallback: cb => idleQueue.push(cb) })
});
let maxCount = 100;
const pool = {
  count: 14,
  get maxCount() { return maxCount; },
  set maxCount(value) {
    maxCount = value;
    this.count = Math.min(this.count, value);
  }
};
channel.setRecommendReusePool(pool);
assert.equal(timerQueue.size, 0, 'recommendation must keep its regular pool while visible');
channel.activeChannel = channel.channelIndex = 3;
channel.artworkTransition = true;
channel.scheduleRecommendPoolTrim();
assert.equal(timerQueue.size, 0, 'never trim during the transition');
channel.artworkTransition = false;
channel.scheduleRecommendPoolTrim();
channel.onChannelTouch({ type: touch.Down });
assert.equal(timerQueue.size, 0, 'a new touch cancels pending cleanup');
channel.onChannelTouch({ type: touch.Up });
function finishDelay(expectedDelay = 1500) {
  assert.equal(timerQueue.size, 1);
  const [[id, { callback, delay }]] = timerQueue;
  assert.equal(delay, expectedDelay);
  timerQueue.delete(id);
  callback();
}
finishDelay();
channel.cancelRecommendPoolTrim();
idleQueue.shift().run(6_000_000);
assert.equal(pool.maxCount, 100, 'an already queued idle callback must be invalidated');
channel.scheduleRecommendPoolTrim();
finishDelay();
assert.equal(pool.maxCount, 100, 'wait for an actual idle frame');
idleQueue.shift().run(2_000_000);
assert.equal(pool.maxCount, 100, 'a tight frame budget must defer the cleanup');
finishDelay(80);
idleQueue.shift().run(6_000_000);
assert.equal(pool.maxCount, 11, 'release a small batch before scheduling more work');
finishDelay(80);
idleQueue.shift().run(6_000_000);
assert.equal(pool.maxCount, 8);
channel.showArtwork(3, 2);
assert.equal(pool.maxCount, 100, 'restore the original pool limit before showing recommendation');

for (const page of ['HomePage', 'LivePage', 'PgcChannelPage']) {
  const source = read(`pages/${page}.ets`);
  assert.match(source, /Scroll\(this\.[^)]*Scroller!?\)\s*\{\s*LazyColumnLayout\(\)/i,
    `${page} must forward the outer viewport through a lazy column`);
  assert.match(source, /LazyVWaterFlowLayout\(\)\s*\{\s*LazyForEach\(this\.dataSource,/,
    `${page} must create cards on demand within that viewport`);
  assert.doesNotMatch(source, /\bWaterFlow\(\s*(?:\{|\))/,
    `${page} must not put an independently scrolling waterfall inside the outer Scroll`);
}

console.log('PASS home retained channel state and viewport-driven card layouts');
