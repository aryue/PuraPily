const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
function method(name) {
  const start = source.indexOf('    private ' + name + '(');
  assert.ok(start >= 0, 'compiled method: ' + name);
  let pos = source.indexOf('{', start), end = pos + 1, depth = 1;
  for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(start, end);
}
const context = { Visibility: { Visible: 0, Hidden: 1 }, Curve: { EaseOut: 0 } };
vm.runInNewContext(ts.transpileModule('class Subject {' + method('referenceAnimateMenu') +
  method('referenceMenuVisibility') + '} globalThis.subject = new Subject();', {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const s = context.subject, finishes = [];
s.mp = false; s.ip = false; s.referencePortraitMotionToken = 0; s.referencePortraitSettingsAnimating = false;
s.getUIContext = () => ({ animateTo: (options, update) => { update(); finishes.push(options.onFinish); } });
assert.equal(s.referenceMenuVisibility(), 1, 'closed menu is hidden during layout/orientation changes');
s.referenceAnimateMenu(true);
assert.equal(s.referenceMenuVisibility(), 0); finishes.shift()();
assert.equal(s.referenceMenuVisibility(), 0, 'open menu remains visible after entry');
s.referenceAnimateMenu(false);
assert.equal(s.referenceMenuVisibility(), 0, 'same material survives the entire exit');
finishes.shift()(); assert.equal(s.referenceMenuVisibility(), 1, 'hide only after exit completion');
s.referenceAnimateMenu(true); finishes.shift()();
s.referenceAnimateMenu(false); const oldClose = finishes.shift();
s.referenceAnimateMenu(true); oldClose();
assert.equal(s.referencePortraitSettingsAnimating, true, 'old completion cannot end a newer animation');
finishes.shift()(); assert.equal(s.referenceMenuVisibility(), 0);
s.referenceAnimateMenu(false); finishes.shift()();
assert.equal(s.referenceMenuVisibility(), 1);
console.log('PASS: compiled menu visibility, exit lifetime and stale animation completion');
