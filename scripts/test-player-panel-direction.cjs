// Exercise the emitted ArkTS gesture handler: horizontal intent must never resize the panel.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const method = source.match(/referencePanelBodyTouch\(e: TouchEvent\): void \{([\s\S]*?)\n    \}/);
assert.ok(method);
const context = { exports: {}, TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 }, Curve: { EaseOut: 0 } };
vm.runInNewContext(ts.transpileModule(`export function touch(e) { ${method[1]} }`, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);
function page(offset = -35, tab = 0) {
  const animations = [];
  return { isLs: false, at: tab, isPgc_: false, referencePanelOffset: offset,
    referencePanelBodyDirection: 0, detailScroller: { currentOffset: () => ({ yOffset: 0 }) },
    referenceMinimumPanelOffset: () => -200, referencePanelDragOffset: x => Math.max(-200, x),
    referenceSetFeed: () => { throw new Error('horizontal input entered feed'); },
    getUIContext: () => ({ animateTo: (options, update) => { animations.push(options); update(); } }), animations };
}
function send(p, type, x, y) {
  const point = { windowX: 200 + x, windowY: 700 + y };
  context.exports.touch.call(p, { type, touches: [point], changedTouches: [point] });
}
for (const sign of [-1, 1]) {
  for (const ending of [2, 3]) {
    const p = page(); send(p, 0, 0, 0);
    for (const [x, y] of [[8, 7], [14, 12], [22, 16], [100, 25]]) {
      send(p, 1, x * sign, y);
      assert.equal(p.referencePanelOffset, -35, 'diagonal horizontal onset must not resize video or move panel');
    }
    send(p, ending, 100 * sign, 25);
    assert.equal(p.referencePanelOffset, -35);
    assert.equal(p.animations.length, 0, 'horizontal completion/cancel must not start a competing vertical animation');
  }
}
for (const ending of [2, 3]) {
  const p = page(); send(p, 0, 0, 0); send(p, 1, 7, 6); send(p, ending, 7, 6);
  assert.equal(p.referencePanelOffset, -35, 'tap and undecided movement must preserve partial panel position');
  assert.equal(p.animations.length, 0);
}
const vertical = page(0); send(vertical, 0, 0, 0); send(vertical, 1, 3, -40);
assert.equal(vertical.referencePanelOffset, -40, 'vertical drag must still follow the finger');
send(vertical, 1, 5, -260); assert.equal(vertical.referencePanelOffset, -200);
send(vertical, 3, 5, -260); assert.equal(vertical.referencePanelOffset, 0, 'cancel restores vertical origin');
const comments = page(-35, 1); send(comments, 0, 0, 0); send(comments, 1, 5, 150); send(comments, 2, 5, 150);
assert.equal(comments.referencePanelOffset, -35, 'comments retain native scrolling without panel resizing');
console.log('PASS: emitted handler isolates diagonal horizontal gestures, taps, cancel, vertical follow/clamp/restore and comment scrolling.');
