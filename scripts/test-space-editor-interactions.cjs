const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function subject(file, cls, names, globals = {}) {
  const ast = ts.createSourceFile(file, fs.readFileSync(root + file, 'utf8'), ts.ScriptTarget.Latest, true);
  const node = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === cls);
  const methods = names.map(name => node.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
  const ctx = { exports: {}, ...globals };
  vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, ctx);
  return new ctx.exports.Subject();
}
let requests = 0, timerId = 0;
const timers = new Map();
const input = subject('components/CommentInputBar.ts', 'CommentInputBar', ['requestEditorFocus', 'aboutToDisappear'], {
  setTimeout(fn) { const id = ++timerId; timers.set(id, fn); return id; }, clearTimeout(id) { timers.delete(id); }
});
Object.assign(input, { editorReady: false, focusPending: false, focusTimer: -1, ctrl: { unbind() {} },
  getUIContext: () => ({ getFocusController: () => ({ requestFocus() { requests++; } }) }) });
input.requestEditorFocus(); assert.equal(requests, 0, 'wait for the real editor node');
input.editorReady = true; input.requestEditorFocus(); assert.equal(requests, 1);
for (let n = 0; n < 20 && timers.size; n++) {
  const [id, fn] = timers.entries().next().value; timers.delete(id); fn();
}
assert.equal(requests, 7, 'focus scope retries must be bounded');
input.requestEditorFocus(); assert.equal(timers.size, 1);
input.aboutToDisappear(); assert.equal(timers.size, 0); assert.equal(input.editorReady, false);
const animations = [];
const Animator = { create(options) { const a = { options, cancel() { this.cancelled = true; }, play() {} }; animations.push(a); return a; } };
const detail = subject('pages/DynamicDetailPage.ts', 'DynamicDetailPage', ['closeCommentEntry', 'onBackPress', 'animateEntryComposer'], { Animator, clearTimeout() {} });
let clears = 0;
Object.assign(detail, { entrySheetOn: true, entryKeyboardHeight: 0, entryProgress: 1, entryClosing: false,
  entryStartTimer: -1, entryEmoteCtrl: { collapseEmote: () => true },
  getUIContext: () => ({ getFocusController: () => ({ clearFocus() { clears++; } }) }) });
assert.equal(detail.onBackPress(), true); assert.equal(detail.entrySheetOn, true, 'emote back retains editor');
detail.entryKeyboardHeight = 300;
assert.equal(detail.onBackPress(), true); assert.equal(detail.entrySheetOn, true, 'keyboard back retains editor');
assert.equal(clears, 1); detail.entryKeyboardHeight = 0;
detail.entryEmoteCtrl.collapseEmote = () => false;
assert.equal(detail.onBackPress(), true); assert.equal(detail.entrySheetOn, true, 'retain editor/material through exit animation');
assert.equal(clears, 2); animations.at(-1).onframe(.5); assert.equal(detail.entryProgress, .5);
animations.at(-1).onfinish(); assert.equal(detail.entrySheetOn, false);
assert.equal(detail.onBackPress(), false, 'page back resumes after editor closes');
let mode = 2, subscribed = 0;
const keyboard = subject('pages/DynamicDetailPage.ts', 'DynamicDetailPage', ['onCommentEntryChanged', 'releaseEntryKeyboard'], { setTimeout: () => 1, clearTimeout() {} });
Object.assign(keyboard, { entrySheetOn: true, entryAvoidMode: null,
  captureEntryOrigin() {},
  getUIContext: () => ({ getKeyboardAvoidMode: () => mode, setKeyboardAvoidMode(value) { mode = value; },
    getHostContext: () => ({ windowStage: { getMainWindowSync: () => ({ on() { subscribed++; }, off() { subscribed--; } }) } }) }) });
keyboard.onCommentEntryChanged(); assert.equal(mode, 4); assert.equal(subscribed, 1);
keyboard.onCommentEntryChanged(); assert.equal(subscribed, 1, 'one keyboard subscription per editor');
keyboard.entrySheetOn = false; keyboard.onCommentEntryChanged();
assert.equal(mode, 2, 'restore previous page keyboard policy'); assert.equal(subscribed, 0);
const geometry = subject('pages/DynamicDetailPage.ts', 'DynamicDetailPage', ['entryAvailableHeight', 'entryTargetHeight', 'entryEditorTop', 'captureEntryOrigin', 'entryFrameWidth', 'entryFrameHeight']);
let host = { windowOffset: { x: 0, y: 0 }, size: { width: 1600, height: 2560 } };
Object.assign(geometry, { viewportHeight: 1241, entryKeyboardHeight: 384, statusBarVp_: 39, entryEditorHeight: 184,
  viewportWidth: 800, entryProgress: 1,
  entryWindow: { getWindowProperties: () => ({ windowRect: { height: 2560 } }) },
  getUIContext: () => ({ px2vp: value => value / 2, getComponentUtils: () => ({ getRectangleById: id =>
    id === 'dynamic-detail-root' ? host : { windowOffset: { x: 44, y: 2452 }, size: { width: 732, height: 84 } } }) }) });
assert.equal(geometry.entryEditorTop(), 712, 'expanded host must not subtract status bar again');
assert.equal(geometry.entryEditorTop() + geometry.entryTargetHeight(), 896, 'panel bottom exactly meets keyboard');
host = { windowOffset: { x: 0, y: 78 }, size: { width: 1600, height: 1714 } };
assert.equal(geometry.entryEditorTop(), 673, 'convert window keyboard position into actual host coordinates');
geometry.entryEditorHeight = 312;
assert.equal(geometry.entryEditorTop(), 545, 'expanded editor keeps all its controls above keyboard');
geometry.captureEntryOrigin(); assert.deepEqual(Array.from(geometry.entryOrigin), [22, 1187, 366, 42]);
geometry.entryProgress = .5;
assert.equal(geometry.entryFrameWidth(), 583); assert.equal(geometry.entryFrameHeight(), 177, 'morph interpolates one persistent viewport');
const space = subject('pages/UpSpacePage.ts', 'UpSpacePage', ['openDynDetail'], { DYN_TYPE_AV: 'DYNAMIC_TYPE_AV' });
let played = 0, routes = [];
Object.assign(space, { playDynVideo() { played++; }, getUIContext: () => ({ getRouter: () => ({ pushUrl(r) { routes.push(r); return Promise.resolve(); } }) }) });
space.openDynDetail({ type: 'DYNAMIC_TYPE_AV', video: {}, idStr: '1' }); assert.equal(played, 1);
space.openDynDetail({ type: 'DYNAMIC_TYPE_FORWARD', video: {}, idStr: '2' });
assert.equal(routes[0].url, 'pages/DynamicDetailPage', 'forward remains a dynamic even when it contains video');
console.log('PASS compiled editor readiness, bounded focus retries, teardown, layered back handling and space video/forward routing.');
