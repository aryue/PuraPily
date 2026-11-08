const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/CommentContentRenderer.ets'), 'utf8').replace(/\r\n/g, '\n');
const behavior = {};
for (const name of ['previewContainedSize', 'clampPreviewPan', 'beginPreviewPan', 'updatePreviewPan', 'finishPreviewPan']) {
  const match = source.match(new RegExp(`private ${name}\\([^\\n]*\\): [^\\n]+\\{([\\s\\S]*?)\\n  \\}`));
  assert.ok(match, name);
  behavior[name] = new Function('deltaX', 'deltaY', match[1]);
}
const state = (width = 1000, height = 1000, zoomScale = 3) => Object.assign({}, behavior, {
  content: { pictures: [{ img_width: width, img_height: height }] },
  viewWidth: 400, viewHeight: 800, zoomScale, previewIndex: 0,
  offsetX: 0, offsetY: 0, panStartX: 0, panStartY: 0,
});
const picture = state();
picture.beginPreviewPan();
picture.updatePreviewPan(90, 80);
picture.finishPreviewPan();
assert.deepEqual([picture.offsetX, picture.offsetY, picture.zoomScale, picture.previewIndex], [90, 80, 3, 0]);
picture.beginPreviewPan();
picture.updatePreviewPan(20, -30);
picture.finishPreviewPan();
assert.deepEqual([picture.offsetX, picture.offsetY], [110, 50]);
picture.beginPreviewPan();
picture.updatePreviewPan(10000, -10000);
picture.finishPreviewPan();
assert.deepEqual([picture.offsetX, picture.offsetY, picture.zoomScale], [352, -152, 3]);

const wide = state(1600, 400, 2);
wide.beginPreviewPan();
wide.updatePreviewPan(100, 100);
wide.finishPreviewPan();
assert.deepEqual([wide.offsetX, wide.offsetY], [100, 0]);
const tall = state(400, 1600, 2);
tall.beginPreviewPan();
tall.updatePreviewPan(100, 100);
tall.finishPreviewPan();
assert.deepEqual([tall.offsetX, tall.offsetY], [0, 100]);
picture.zoomScale = 1;
picture.clampPreviewPan();
assert.deepEqual([picture.offsetX, picture.offsetY], [0, 0]);

const rotated = state();
rotated.offsetX = 300;
rotated.viewWidth = 800;
rotated.viewHeight = 400;
rotated.clampPreviewPan();
assert.equal(rotated.offsetX, 152);
assert.match(source, /\.loop\(false\)/);
console.log('Comment images: retained drag position, consecutive drags, no zoomed page switch, image bounds, shrink and rotation passed.');
