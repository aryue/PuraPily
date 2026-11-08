// Exercise the methods retained by CompileArkTS with changing native geometry.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/HomePage.ts';
const source = fs.readFileSync(file, 'utf8');
const ast = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
const page = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'HomePage');
const frame = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'HomeLayoutFrameCallback');
const names = ['rememberHomeAnchor', 'beginHomeRelayout', 'finishHomeRelayout', 'afterHomeLayout',
  'updateHomeViewport', 'columnPreferenceKey', 'maximumColumns', 'loadColumnCountForOrientation'];
const members = names.map(name => {
  const member = page.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name);
  assert.ok(member, `${name} must survive CompileArkTS`);
  return member.getText(ast);
});
let prefGet = async (_key, fallback) => fallback;
const flush = () => new Promise(resolve => setImmediate(resolve));
const ctx = { exports: {}, FrameCallback: class {}, logInfo() {}, logError() {},
  ScrollSource: { DRAG: 1, FLING: 2, OTHER_USER_INPUT: 3, SCROLL_BAR: 4, SCROLL_BAR_FLING: 5, SCROLLER: 6 },
  AppStorage: { get: () => false, set() {} },
  preferences: { getPreferences: async () => ({ get: (...args) => prefGet(...args) }) } };
vm.runInNewContext(ts.transpileModule(`${frame.getText(ast)}\nexport class Subject {${members.join('\n')}}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const scrollCallbacks = {};
function visit(node) {
  if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
      ['onWillScroll', 'onDidScroll', 'onScrollStop'].includes(node.expression.name.text)) {
    scrollCallbacks[node.expression.name.text] = node.arguments[0].getText(ast);
  }
  ts.forEachChild(node, visit);
}
visit(page);
vm.runInNewContext(ts.transpileModule(`export function handlers() { return {
  will: ${scrollCallbacks.onWillScroll}, did: ${scrollCallbacks.onDidScroll}, stop: ${scrollCallbacks.onScrollStop}
}; }`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, ctx);

function subject() {
  const frames = [], rects = new Map(), movements = [], listeners = new Set();
  let offset = 720;
  const p = Object.assign(new ctx.exports.Subject(), {
    viewportWidth: 673, viewportHeight: 1077, isLandscape: false,
    homeLayoutRevision: 0, columnRequestRevision: 0, homeLayoutPending: false,
    homeLayoutCallbacks: new Set(),
    homeAnchorIndex: -1, homeAnchorTop: 0, isPageActive: true,
    statusBarHeight: 40, hideStatusBar: false, columnCount: 3,
    showHomeCarouselPortrait: true, showHomeCarouselLandscape: true, banners: [1, 2],
    playbackVisibleIndexes: new Set([12, 9, 10]), headerContentHeight: () => 48,
    recalcCarouselHeight() {}, recalcLandscapeCarouselWidth() {}, updatePaddings() {},
    getUIContext: () => ({
      // Node position is vp, measured height is px: deliberately use density 2.
      px2vp: n => n / 2, getHostContext: () => ({}),
      getFrameNodeById: id => id === 'home-recommend-flow' ? { getPositionToParent: () => ({ y: 0 }) } :
        id === 'home-recommend-scroll' ? { getPositionToWindow: () => ({ y: 0 }) } : rects.get(Number(id.split('-').at(-1))),
      getUIObserver: () => ({ on: (_event, f) => listeners.add(f), off: (_event, f) => listeners.delete(f) }),
      postFrameCallback: () => frames.push({ onIdle: () => [...listeners].forEach(f => { if (listeners.has(f)) f(); }) })
    }),
    externalScroller: {
      currentOffset: () => ({ yOffset: offset }),
      scrollTo: ({ yOffset }) => { movements.push(yOffset - offset); offset = yOffset; }
    }
  });
  function rect(index, top, height = 400) {
    const contentTop = top + offset;
    rects.set(index, { getPositionToWindow: () => ({ y: top }),
      getPositionToParent: () => ({ y: contentTop }), getMeasuredSize: () => ({ height }) });
  }
  rect(9, 62); rect(10, 62); rect(12, 270);
  return { p, rect, frames, movements, setOffset: n => { offset = n; } };
}

(async () => {
  const { p, rect, frames, movements } = subject();
  p.rememberHomeAnchor();
  assert.equal(p.homeAnchorIndex, 9, 'lowest visible card index, independent of callback order');
  assert.equal(p.homeAnchorTop, -26, 'keep a partially obscured card relative to the header');
  const rev = p.beginHomeRelayout();
  rect(9, -300);
  p.rememberHomeAnchor();
  assert.equal(p.homeAnchorTop, -26, 'intermediate layout must not overwrite the old anchor');
  p.statusBarHeight = 0;
  p.finishHomeRelayout(rev);
  frames.shift().onIdle(1);
  assert.deepEqual(movements, [-322], 'restore using new measured card position and new header');
  frames.shift().onIdle(1);
  assert.equal(p.homeLayoutPending, false);

  const old = p.beginHomeRelayout();
  p.finishHomeRelayout(old);
  const current = p.beginHomeRelayout();
  const stale = frames.shift(); stale.onIdle(1);
  assert.equal(movements.length, 1);
  assert.equal(p.homeLayoutPending, true, 'stale frame cannot end a newer rotation');
  p.finishHomeRelayout(current);
  p.isPageActive = false;
  frames.shift().onIdle(1);
  assert.equal(movements.length, 1, 'an exited page must not move');

  const columns = subject(); columns.p.rememberHomeAnchor();
  columns.p.finishHomeRelayout(columns.p.beginHomeRelayout());
  columns.p.columnRequestRevision++;
  columns.frames.shift().onIdle(1);
  assert.equal(columns.movements.length, 0, 'a new column read invalidates an already queued frame');
  assert.equal(columns.p.homeLayoutPending, true);

  const top = subject(); top.setOffset(0); top.p.rememberHomeAnchor();
  top.p.finishHomeRelayout(top.p.beginHomeRelayout()); top.frames.shift().onIdle(1);
  assert.equal(top.movements.length, 0, 'top-of-feed stays at the top');
  const covered = subject(); covered.rect(9, -150); covered.p.rememberHomeAnchor();
  assert.equal(covered.p.homeAnchorIndex, 10, 'exclude cards entirely behind the header using px height');
  const lag = subject(); lag.setOffset(731); lag.p.rememberHomeAnchor();
  assert.equal(lag.p.homeAnchorTop, 51 - 88, 'current controller offset must win over a stale window transform');
  const width = subject();
  width.p.sidePadding = 6; width.p.cardListMargin = 6;
  width.p.rememberHomeAnchor();
  const widthRevision = width.p.beginHomeRelayout();
  width.p.viewportWidth = 1077; width.p.columnCount = 4;
  const pendingNode = width.p.getUIContext().getFrameNodeById('home-recommend-card-9');
  let nativeWidth = 432;
  pendingNode.getMeasuredSize = () => ({ width: nativeWidth, height: 400 });
  width.p.finishHomeRelayout(widthRevision);
  width.frames.shift().onIdle(1);
  assert.equal(width.movements.length, 0, 'do not restore while native cards still use the old column width');
  nativeWidth = 523.5;
  width.frames.shift().onIdle(1);
  assert.equal(width.movements.length, 1, 'restore after native width agrees with the current column layout');
  const extent = subject(); extent.p.rememberHomeAnchor();
  const scrollTo = extent.p.externalScroller.scrollTo;
  let restoreCalls = 0;
  extent.p.externalScroller.scrollTo = args => {
    scrollTo(args);
    if (++restoreCalls === 1) extent.setOffset(0);
  };
  extent.p.finishHomeRelayout(extent.p.beginHomeRelayout());
  for (let i = 0; extent.frames.length && i < 10; i++) extent.frames.shift().onIdle(1);
  assert.equal(restoreCalls, 2, 'retry a target clamped by the temporary resized WaterFlow extent');
  assert.equal(extent.p.homeLayoutPending, false);

  const events = subject(), handlers = ctx.exports.handlers.call(events.p);
  handlers.will(0, 10, 0, ctx.ScrollSource.DRAG); handlers.did();
  assert.equal(events.p.homeAnchorIndex, 9);
  events.rect(9, 51);
  handlers.stop();
  events.frames.shift().onIdle(1);
  assert.equal(events.p.homeAnchorTop, 51 - 88, 'sample settled native geometry after the final fling update');
  events.rect(5, 62); events.p.playbackVisibleIndexes = new Set([5, 9, 10]);
  handlers.will(0, -400, 0, ctx.ScrollSource.SCROLLER); handlers.did();
  handlers.stop();
  assert.equal(events.frames.length, 0, 'programmatic restoration must not schedule another anchor sample');
  assert.equal(events.p.homeAnchorIndex, 9, 'restoring scroll must not replace anchor with an earlier item in its new row');
  handlers.will(0, 10, 0, ctx.ScrollSource.DRAG); handlers.did();
  assert.equal(events.p.homeAnchorIndex, 5, 'subsequent user scrolling updates the reading position');
  events.setOffset(0);
  handlers.will(0, -500, 0, ctx.ScrollSource.SCROLLER); handlers.did();
  assert.equal(events.p.homeAnchorIndex, -1, 'programmatic return to top clears the old reading anchor');

  // Same preference key, different viewport widths. Complete the newest read first.
  const racing = subject(), reads = [];
  racing.p.rememberHomeAnchor();
  prefGet = (key, fallback) => new Promise(resolve => reads.push({ key, fallback, resolve }));
  racing.p.updateHomeViewport(1000, 673);
  await flush();
  racing.p.updateHomeViewport(1200, 673);
  await flush();
  assert.equal(reads.length, 2);
  assert.equal(reads[0].key, reads[1].key);
  reads[1].resolve(5);
  await flush();
  reads[0].resolve(3);
  await flush();
  assert.equal(racing.p.columnCount, 5, 'late same-key preference read cannot overwrite current columns');
  assert.equal(racing.p.isLandscape, true);
  assert.equal(racing.p.viewportWidth, 1200);
  racing.frames.forEach(f => f.onIdle(1));
  assert.equal(racing.movements.length, 1, 'only latest layout restores the anchor');
  const count = reads.length;
  racing.p.updateHomeViewport(1200, 673);
  await Promise.resolve();
  assert.equal(reads.length, count, 'duplicate size notifications do not start another layout');

  // Portrait -> landscape -> portrait while the landscape preference is still pending.
  const reverse = subject(), turns = [];
  reverse.p.rememberHomeAnchor();
  prefGet = key => new Promise(resolve => turns.push({ key, resolve }));
  reverse.p.updateHomeViewport(1077, 673); await flush();
  reverse.p.updateHomeViewport(673, 1077); await flush();
  turns[1].resolve(3); await flush();
  turns[0].resolve(5); await flush();
  assert.equal(reverse.p.columnCount, 3);
  assert.equal(reverse.p.isLandscape, false);
  assert.equal(reverse.p.carouselVisible, true);
  reverse.frames.forEach(f => { f.onIdle(1); f.onIdle(1); });
  assert.equal(reverse.movements.length, 1, 'rapid reversal restores once and ignores the old direction');
  console.log('PASS: compiled home rotation anchor, density, header insets, stale frames, exit, top boundary and preference races.');
})().catch(error => { console.error(error); process.exitCode = 1; });
