// Verify the actual CompileArkTS List setup, including both builder call sites.
// Native gesture arbitration and spring interruption still need a device.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const core = compiled.slice(compiled.indexOf('    commentListCore('), compiled.indexOf('    commentAreaCore('));
assert.match(core, /inRefresh: boolean = false/, 'builder must retain refresh context and its default');
const setup = core.slice(core.indexOf('List.create('), core.indexOf('}, List);'));
assert.ok(setup.startsWith('List.create('));
assert.ok(!setup.includes('List.nestedScroll('), 'Refresh must configure its direct List child natively, as on DynamicsPage');
const context = { Axis: { Vertical: 0 }, BarState: { Off: 0 }, EdgeEffect: { Spring: 0 },
  EffectEdge: { END: 2 }, NestedScrollMode: { SELF_ONLY: 0, SELF_FIRST: 1, PARENT_FIRST: 2 },
  ScrollState: { Idle: 0, Scroll: 1, Fling: 2 }, TouchType: { Down: 0, Move: 2, Up: 1, Cancel: 3 },
  HitTestMode: { Default: 0 },
  Visibility: { Visible: 0 }, exports: {} };
vm.runInNewContext(ts.transpileModule(`export function setup(inRefresh: boolean, useFsScroller: boolean) {
  const hideOnTransition = false;
  ${setup}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
const page = { commentScroller: {}, fsCommentScroller: {} };
for (const inRefresh of [true, false, true]) {
  for (const useFsScroller of [false, true]) {
    const calls = {};
    context.List = new Proxy({}, { get: (_, name) => (...args) => { calls[name] = args; } });
    context.exports.setup.call(page, inRefresh, useFsScroller);
    assert.equal(calls.create[0].scroller, useFsScroller ? page.fsCommentScroller : page.commentScroller);
    assert.equal(calls.edgeEffect[1].alwaysEnabled, inRefresh, 'short comments must still pass pulls to Refresh');
    assert.equal(calls.cachedCount[0], inRefresh ? 4 : 1, 'keep a bounded cache of heavy comment rows');
  }
}
const refreshPage = compiled.slice(compiled.indexOf('    ReferenceCommentPage('), compiled.indexOf('    ReferenceLandscapeResizeHandle('));
assert.match(refreshPage, /commentListCore\.bind\(this\)\(false, !this.isLs && this.referenceFeedComments, true\)/);
assert.ok(!refreshPage.includes('commentAreaCore.bind'), 'Refresh must not contain the card/overlay wrapper');
assert.match(compiled, /commentAreaCore\.bind\(this\)\(false, true, true\)/, 'fullscreen keeps independent scrolling');
const hitTestMethod = compiled.match(/referenceFeedChromeHitTest\(\): HitTestMode \{([\s\S]*?)\n    \}/);
assert.ok(hitTestMethod, 'compiler must retain the chrome hit-test method');
const chromeHitTest = new Function('HitTestMode', hitTestMethod[1]);
const hitTestModes = { Default: 0, None: 3, BLOCK_DESCENDANTS: 5 };
for (const referenceFeed of [false, true]) {
  for (const referenceFeedComments of [false, true]) {
    assert.equal(chromeHitTest.call({ referenceFeed, referenceFeedComments }, hitTestModes),
      referenceFeed && !referenceFeedComments ? 0 : 5,
      'hidden chrome must exclude every descendant, including Slider and action buttons');
  }
}
const chrome = compiled.slice(compiled.indexOf('    ReferenceChrome('));
assert.equal((chrome.match(/\.hitTestBehavior\(this.referenceFeedChromeHitTest\(\)\)/g) || []).length, 2,
  'both fullscreen shortcut and bottom chrome must apply the subtree policy');
const intercept = compiled.match(/referencePanelTouchIntercept\(event: TouchEvent\): HitTestMode \{([\s\S]*?)\n    \}/);
assert.ok(intercept, 'inertia interception must survive CompileArkTS');
vm.runInNewContext(ts.transpileModule(`export function intercept(event) { ${intercept[1]} }`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
for (const mode of ['intro', 'comments', 'feedComments', 'landscapeComments']) {
  const jumps = [];
  const scroller = name => ({ currentOffset: () => ({ xOffset: 0, yOffset: 321.75 }),
    scrollTo: options => jumps.push({ name, ...options }) });
  const state = { isLs: mode === 'landscapeComments', referenceFeedComments: mode === 'feedComments',
    at: mode === 'intro' ? 0 : 1, detailScroller: scroller('intro'), commentScroller: scroller('comments'), fsCommentScroller: scroller('feedComments'),
    referenceIntroScrollState: 2, referenceCommentScrollState: 2, referenceFsCommentScrollState: 2 };
  const event = type => ({ type, touches: [{ id: 0 }] });
  assert.equal(context.exports.intercept.call(state, event(0)), 0, 'hit testing must continue into native children');
  const expected = mode === 'intro' ? 1 : 0;
  assert.deepEqual(jumps, mode === 'intro' ? [{ name: 'intro', xOffset: 0, yOffset: 321.75, animation: false }] : [],
    'comments must use native inertia handling without any programmatic scrollTo on touch');
  context.exports.intercept.call(state, event(2));
  context.exports.intercept.call(state, event(1));
  assert.equal(jumps.length, expected, 'Move and Up must not interrupt the new drag');
  state.referenceIntroScrollState = state.referenceCommentScrollState = state.referenceFsCommentScrollState = 1;
  context.exports.intercept.call(state, event(0));
  assert.equal(jumps.length, expected, 'direct dragging must not be mistaken for old inertia');
}
const panel = compiled.slice(compiled.indexOf('    ReferencePanel('), compiled.indexOf('    ReferenceCommentPage('));
assert.match(panel, /Column\.onTouchIntercept\(.*referencePanelTouchIntercept/,
  'stop old inertia on the ancestor before child recognizers are hit-tested');
console.log('PASS: compiled comment List/Refresh handoff, short-list input, scroller identity and fullscreen isolation.');
const gestureSource = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/ReferenceFeedGestures.ts', 'utf8');
class FakeGesture {
  constructor(options) { this.options = options; }
  tag(value) { this.tagValue = value; return this; }
  onAction(fn) { this.action = fn; return this; }
  onActionStart(fn) { this.start = fn; return this; }
  onActionUpdate(fn) { this.update = fn; return this; }
  onActionEnd(fn) { this.end = fn; return this; }
  onActionCancel(fn) { this.cancel = fn; return this; }
}
const gestureContext = { exports: {}, TapGestureHandler: FakeGesture, PanGestureHandler: FakeGesture,
  PanDirection: { Vertical: 2 }, GesturePriority: { PRIORITY: 1 } };
vm.runInNewContext(ts.transpileModule(gestureSource, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, gestureContext);
let attached = ['stale'];
const gestureEvent = { clearGestures() { attached = []; },
  addParallelGesture(gesture) { attached.push({ gesture, priority: 'parallel' }); },
  addGesture(gesture, priority) { attached.push({ gesture, priority }); } };
for (const active of [false, true, false, true]) {
  const forwarded = [];
  new gestureContext.exports.ReferenceFeedGestures({ active, distance: 19,
    onDoubleTap: e => forwarded.push(e), onStart: e => forwarded.push(e),
    onUpdate() {}, onEnd() {}, onCancel() {} }).applyGesture(gestureEvent);
  assert.equal(attached.length, active ? 2 : 0, 'comments/intro must have no feed recognizers competing with List');
  if (active) {
    assert.equal(attached[0].gesture.options.count, 2);
    assert.equal(attached[1].gesture.options.distance, 19);
    assert.equal(attached[1].gesture.tagValue, 'reference-feed-pan');
    const touch = { offsetY: 80 };
    attached[1].gesture.start(touch);
    assert.equal(forwarded[0], touch);
  }
}
assert.match(compiled, /Stack\.gestureModifier\(new ReferenceFeedGestures/);
console.log('PASS: compiled feed recognizers are removed for comments/intro and restored with their original callbacks for feed viewing.');
const refresh = compiled.match(/async refreshReferenceComments\(\): Promise<void> \{([\s\S]*?)\n    \}/);
assert.ok(refresh, 'refresh guard must survive CompileArkTS');
vm.runInNewContext(ts.transpileModule(`export async function refresh() { ${refresh[1]} }`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
(async () => {
  for (const mode of ['half', 'feed', 'landscape']) {
    for (const offset of [-12, 0, 0.2, 1, 80, 300, NaN, Infinity]) {
      let calls = 0;
      const state = { isLs: mode === 'landscape', referenceFeedComments: mode === 'feed',
        referenceCommentRefreshing: true, commentCursor: 57, hm: false, vd: { aid: 123 }, ldc: false, isLoadingMore: false,
        commentScroller: { currentOffset: () => ({ yOffset: mode === 'feed' ? 999 : offset }) },
        fsCommentScroller: { currentOffset: () => ({ yOffset: mode === 'feed' ? offset : 999 }) },
        loadC: async aid => { assert.equal(aid, 123); calls++; } };
      const allowed = Number.isFinite(offset) && offset <= 0.5;
      await context.exports.refresh.call(state);
      assert.equal(calls, allowed ? 1 : 0, `${mode} offset=${offset}: only the real list top can refresh`);
      assert.equal(state.commentCursor, allowed ? 0 : 57, 'rejected refresh must preserve pagination');
      assert.equal(state.hm, allowed, 'rejected refresh must preserve end state');
      assert.equal(state.referenceCommentRefreshing, false);
    }
  }
  const failure = { isLs: false, referenceFeedComments: false, commentScroller: { currentOffset: () => ({ yOffset: 0 }) },
    vd: { aid: 123 }, ldc: false, isLoadingMore: false, referenceCommentRefreshing: true,
    loadC: async () => { throw new Error('offline'); } };
  await assert.rejects(context.exports.refresh.call(failure), /offline/);
  assert.equal(failure.referenceCommentRefreshing, false, 'failed refresh must release its spinner');
  console.log('PASS: compiled refresh guard rejects off-top pulls without clearing rows or pagination; top refresh and failure cleanup passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
