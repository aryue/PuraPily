const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const file = base + 'components/PageHeader.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const subject = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'PageHeader');
const method = subject.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === 'initialRender');
let calls = [], measure;
const component = name => new Proxy({}, { get: (_target, key) => (...args) => {
  calls.push([name, key, ...args]);
  if (key === 'onSizeChange') measure = args[0];
  return false;
} });
const context = { exports: {}, Stack: component('Stack'), Column: component('Column'),
  If: component('If'), ForEach: component('ForEach'), __Common__: component('Common'),
  Alignment: { TopStart: 1 }, BlendMode: { DST_IN: 1, SRC_OVER: 2 },
  BlendApplyType: { OFFSCREEN: 1 }, GradientDirection: { Bottom: 1 },
  BlurStyleActivePolicy: { ALWAYS_ACTIVE: 1 }, HitTestMode: { None: 1 },
  HistoryHeaderBlur: class { constructor(_parent, params) { calls.push(['history', params]); } },
  NativeHeaderGlass: class { constructor(_parent, params) { calls.push(['glass', params]); } },
  ViewPU: { create() {} } };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${method.getText(ast)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Subject();
Object.assign(page, { surfaceWidth: 400, surfaceHeight: 120, showSurface: true, withTabs: true, materialHeight: 140,
  scopeId: 'test-header', surfaceRevision: 0, dark: true, content() { calls.push(['content']); },
  observeComponentCreation2: fn => fn(1, true), ifElseBranchUpdateFunction: (_branch, fn) => fn(),
  forEachUpdateFunction: (_id, items, render, key) => items.forEach(item => {
    calls.push(['surface-key', key(item)]); render(item);
  }) });
for (const height of [120, 90, 60]) {
  calls = []; page.surfaceHeight = height; page.initialRender();
  assert.equal(calls.find(c => c[0] === 'glass')[1].surfaceHeight, 140,
    'collapsing controls must retain a stable native material scope');
  assert.ok(calls.some(c => c[0] === 'Stack' && c[1] === 'height' && c[2] === height),
    'the material viewport must shrink with the controls, without sizing the title');
  assert.equal(calls.filter(c => c[1] === 'backgroundEffect').length, 0);
  assert.ok(calls.some(c => c[0] === 'content'));
}
for (const revision of [0, 1, 2]) {
  page.surfaceRevision = revision; calls = []; page.initialRender();
  assert.equal(calls.find(c => c[0] === 'surface-key')[1], String(revision));
  assert.equal(calls.filter(c => c[0] === 'glass').length, 1);
  assert.equal(calls.filter(c => c[0] === 'content').length, 1,
    'refreshing the material must not key or duplicate header controls');
}
page.withTabs = false;
for (const dark of [false, true]) {
  calls = []; page.dark = dark; page.initialRender();
  assert.ok(!calls.some(c => c[0] === 'glass'));
  const history = calls.find(c => c[0] === 'history');
  assert.ok(history, 'non-Tab headers must use the history HDS renderer');
  assert.equal(history[1].surfaceWidth, page.surfaceWidth);
  assert.equal(history[1].surfaceHeight, page.surfaceHeight);
  assert.equal(calls.filter(c => c[1] === 'linearGradient' || c[1] === 'backgroundEffect').length, 0,
    'no second custom gradient/blur implementation may remain');
  assert.ok(calls.findIndex(c => c[0] === 'content') > calls.findIndex(c => c[0] === 'history'));

}
for (const withTabs of [false, true]) {
  calls = []; page.showSurface = false; page.withTabs = withTabs; page.initialRender();
  assert.ok(!calls.some(c => c[0] === 'glass' || c[0] === 'history'), 'media overlays must create no material nodes');
  assert.ok(calls.some(c => c[0] === 'content'), 'transparent overlays retain controls');
}
page.showSurface = true;
measure({}, { width: 720, height: 84 });
assert.equal(page.surfaceWidth, 720);
assert.equal(page.surfaceHeight, 84);
console.log('PASS: compiled header rendering: native Tab material, stable animation scope, history HDS renderer, clear controls and rotation measurements.');

const historyFile = base + 'components/HistoryHeaderBlur.ts';
const historyAst = ts.createSourceFile(historyFile, fs.readFileSync(historyFile, 'utf8'), ts.ScriptTarget.Latest, true);
const historyClass = historyAst.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'HistoryHeaderBlur');
const historyRender = historyClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(historyAst) === 'initialRender');
const styleSource = fs.readFileSync(base + 'utils/HeaderStyle.ts', 'utf8').replace(/^import .*;\r?\n/gm, '');
Object.assign(context, { HdsNavigation: component('HdsNavigation'), NavPathStack: class {},
  HdsNavigationTitleMode: { MINI: 0 }, NavigationMode: { Stack: 0 }, Color: { Transparent: 0 },
  DividerShowType: { OFF: 0 }, LengthMetrics: { vp: value => value }, ScrollEffectType: { GRADIENT_BLUR: 2 } });
vm.runInNewContext(ts.transpileModule(styleSource, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
context.gradientTitleBarStyle = context.exports.gradientTitleBarStyle;
vm.runInNewContext(ts.transpileModule(`export class HistorySubject { ${historyRender.getText(historyAst)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
for (const dark of [false, true]) {
  calls = [];
  const historyPage = new context.exports.HistorySubject();
  Object.assign(historyPage, { surfaceWidth: 400, surfaceHeight: 84, dark,
    observeComponentCreation2: fn => fn(1, true) });
  historyPage.initialRender();
  const options = calls.find(c => c[0] === 'HdsNavigation' && c[1] === 'titleBar')[2];
  assert.deepEqual(options.style, context.gradientTitleBarStyle(dark));
  assert.equal(options.content.divider.showType, 0);
  assert.equal(options.style.originalStyle.backgroundStyle.maskExtraHeight, 0,
    'the native gradient must finish inside the title instead of covering the first record');
  assert.equal(options.style.scrollEffectStyle.backgroundStyle.maskExtraHeight, 0,
    'scrolling must not restore the old extension over body content');
  assert.ok(calls.some(c => c[0] === 'HdsNavigation' && c[1] === 'height' && c[2] > 84 + 32),
    'the native gradient must not be clipped at the controls boundary');
  assert.ok(!calls.some(c => c[1] === 'clip' && c[2] === true));
}
console.log('PASS: actual compiled HDS history style, disabled divider, native gradient overscan and dark/light parity.');

const playerFile = base + 'pages/VideoPlayerPage.ts';
const playerAst = ts.createSourceFile(playerFile, fs.readFileSync(playerFile, 'utf8'), ts.ScriptTarget.Latest, true);
const playerClass = playerAst.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
const panel = playerClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(playerAst) === 'ReferencePanel');
let surfaceExpression;
function visit(n) {
  if (ts.isPropertyAssignment(n) && n.name.getText(playerAst) === 'showSurface') surfaceExpression = n.initializer.getText(playerAst);
  ts.forEachChild(n, visit);
}
visit(panel);
const panelText = panel.getText(playerAst);
assert.ok(panelText.includes('surfaceRevision: this.referencePanelHeaderRevision'));
let animationEnd;
function findAnimationEnd(node) {
  if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === 'onAnimationEnd') animationEnd = node.arguments[0];
  ts.forEachChild(node, findAnimationEnd);
}
findAnimationEnd(panel);
assert.ok(animationEnd, 'cached panel swipes must invalidate the native backdrop after settling');
const settle = vm.runInNewContext(ts.transpileModule('const settle = function(index) ' + animationEnd.body.getText(playerAst) + '; settle;', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText);
const pager = { referencePanelHeaderRevision: 0, at: 1, referenceTabProgress: 0.4,
  commentDataSource: {}, detailScroller: {}, referencePanelSwiper: {} };
const originals = { ...pager };
// Forward, reverse and snap-back completion all refresh the backdrop, never pager contents.
for (const index of [1, 0, 0, 1]) settle.call(pager, index);
assert.equal(pager.referencePanelHeaderRevision, 4);
for (const key of ['at', 'referenceTabProgress', 'commentDataSource', 'detailScroller', 'referencePanelSwiper']) {
  assert.equal(pager[key], originals[key]);
}
assert.ok(surfaceExpression, 'actual player panel must explicitly opt out of surfaces in feed states');
const surfacePolicy = new Function('return ' + surfaceExpression);
for (const referenceFeed of [false, true]) {
  for (const referenceFeedComments of [false, true]) {
    assert.equal(surfacePolicy.call({ referenceFeed, referenceFeedComments }), !referenceFeed && !referenceFeedComments);
  }
}
const topBar = playerClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(playerAst) === 'ReferenceTopBar');
assert.ok(!topBar.getText(playerAst).includes('new PageHeader'), 'player overlay buttons must stay transparent');
const liveFile = base + 'pages/LivePlayerPage.ts';
const liveAst = ts.createSourceFile(liveFile, fs.readFileSync(liveFile, 'utf8'), ts.ScriptTarget.Latest, true);
const liveClass = liveAst.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'LivePlayerPage');
const liveInfo = liveClass.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(liveAst) === 'RoomInformation');
assert.ok(!liveInfo.getText(liveAst).includes('new PageHeader'), 'live overlay controls must stay transparent in both information states');
console.log('PASS: compiled player/feed-comment material policy and transparent video/live overlay controls.');
