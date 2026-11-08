const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(root, 'utils/FullscreenVideoTransform.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, { exports: exportsObject });
const { FullscreenVideoTransform } = exportsObject;
const close = (actual, expected) => assert.ok(Math.abs(actual - expected) < 0.00001, `${actual} != ${expected}`);
const pair = (ax, ay, bx, by) => [{ id: 1, x: ax, y: ay }, { id: 2, x: bx, y: by }];
// A point under the fingers stays anchored while zooming and rotating off center.
for (const [cx, cy] of [[400, 200], [200, 400]]) {
  const t = new FullscreenVideoTransform();
  t.update(pair(cx, cy, cx + 100, cy), cx, cy);
  t.update(pair(cx + 30, cy - 70, cx + 30, cy + 130), cx, cy);
  close(t.scale, 2); close(t.angle, 90);
  close(t.x, 30); close(t.y, -70);
  // Array ordering can change without rotating the image by 180 degrees.
  t.update(pair(cx + 30, cy - 70, cx + 30, cy + 130).reverse(), cx, cy);
  close(t.angle, 90);
  t.update(pair(cx + 60, cy - 50, cx + 60, cy + 150), cx, cy);
  close(t.x, 60); close(t.y, -50);
  // Repositioning fingers starts a fresh baseline, retaining the image transform.
  t.end();
  t.update(pair(0, 0, 10, 0), cx, cy);
  close(t.scale, 2); close(t.x, 60);
  t.update(pair(0, 0, 10000, 0), cx, cy);
  close(t.scale, 5);
  t.update(pair(0, 0, 8, 0), cx, cy);
  close(t.scale, 0.25);
  t.reset();
  close(t.scale, 1); close(t.angle, 0); close(t.x, 0); close(t.y, 0);
}
// Crossing the atan2 boundary must rotate by two degrees, not 358 degrees.
const rotation = new FullscreenVideoTransform();
const at = angle => pair(0, 0, Math.cos(angle * Math.PI / 180) * 100, Math.sin(angle * Math.PI / 180) * 100);
rotation.update(at(179), 0, 0);
rotation.update(at(-179), 0, 0);
close(rotation.angle, 2);

// Exercise the page's actual ownership handler, including the final one-finger tail.
const pageSource = fs.readFileSync(path.join(root, 'pages/VideoPlayerPage.ets'), 'utf8');
const start = pageSource.indexOf('  private resetFullscreenVideo():');
const end = pageSource.indexOf('  private onVT =', start);
const pageContext = { exports: {}, TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 }, setTimeout, clearTimeout };
vm.runInNewContext(ts.transpileModule(`export class Page { ${pageSource.slice(start, end)} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, pageContext);
const p = new pageContext.exports.Page();
Object.assign(p, { fs: true, lk: false, ip: false, fullscreenTransformTouch: false,
  fullscreenTransform: new FullscreenVideoTransform(), dt_: -1, ct_: -1,
  onTC() {}, clearGestureHint_() {}, cancelDelayHide() {}, resetCT() {},
  referencePortraitFeedActive: () => false,
  ovRectX: () => 0, ovRectY: () => 0, ovRectW: () => 400, ovRectH: () => 800 });
const touch = (type, points, changed = []) => ({ type, touches: points.map(q => ({ id: q.id, windowX: q.x, windowY: q.y })), changedTouches: changed });
assert.equal(p.handleFullscreenTransform(touch(0, pair(100, 300, 200, 300))), true);
assert.equal(p.handleFullscreenTransform(touch(1, pair(50, 300, 250, 300))), true);
close(p.fullscreenVideoScale, 2);
assert.equal(p.handleFullscreenTransform(touch(2, pair(50, 300, 250, 300), [{ id: 2 }])), true);
assert.equal(p.fullscreenTransformTouch, true);
assert.equal(p.handleFullscreenTransform(touch(1, [{ id: 1, x: 80, y: 300 }])), true);
assert.equal(p.handleFullscreenTransform(touch(2, [], [{ id: 1 }])), true);
assert.equal(p.fullscreenTransformTouch, false);
assert.equal(p.cv, true);
p.lk = true;
assert.equal(p.handleFullscreenTransform(touch(0, pair(100, 300, 200, 300))), false);
p.lk = false; p.fs = false;
assert.equal(p.handleFullscreenTransform(touch(0, pair(100, 300, 200, 300))), false);
p.referencePortraitFeedActive = () => true;
p.referenceStopFeedMotion = () => {};
p.referenceInfoHidden = true;
p.referenceFeedComments = false;
assert.equal(p.handleFullscreenTransform(touch(0, pair(100, 300, 200, 300))), true);
assert.equal(p.referenceVerticalSwipe, false);
assert.equal(p.referenceFeedDragY, 0);
assert.equal(p.handleFullscreenTransform(touch(1, pair(50, 300, 250, 300))), true);
assert.equal(p.handleFullscreenTransform(touch(3, [])), true);
assert.equal(p.fullscreenTransformTouch, false);
assert.equal(p.referenceInfoHidden, false);
console.log('Fullscreen transform: portrait/landscape anchoring, rotation, drag, bounds, reset and touch ownership passed.');
