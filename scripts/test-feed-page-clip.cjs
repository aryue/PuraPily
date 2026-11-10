const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// 1) 拖拽页面节点（带 referenceFeedDragY offset 的那个 Stack）必须自己裁剪。
//    连刷翻页时整页被拖出屏幕，溢出裁剪只挂在整屏节点上时，cover 撑大的 Surface
//    会有一整条落到下一页顶部（用户截图里"应被裁掉却盖住下一个视频"的那条）。
const offsetAt = source.indexOf('.offset({ y: this.referencePortraitFeedActive() && !this.referenceFeedComments ? this.referenceFeedDragY : 0 })');
assert.ok(offsetAt > 0, 'feed drag offset must stay on the page node');
const chain = source.slice(Math.max(0, offsetAt - 260), offsetAt + 1100);
assert.match(chain, /\.width\('100%'\)\.height\('100%'\)/, 'page node needs an explicit size so the clip rect is the page, not a child-derived box');
const animAt = chain.indexOf('.animation({');
const clipAt = chain.indexOf('.clip(this.referenceFeed)');
assert.ok(clipAt > 0, 'the dragged page node must clip to its own bounds in feed mode');
assert.ok(clipAt > animAt, 'clip must sit after .animation() so it stays out of the implicit animation node');

// 2) 不能改成裁到视频视口：连刷里双指放大要能扩进原始黑边。
assert.match(source, /\.clip\(!this\.referencePortraitFeedActive\(\) \|\| this\.referenceFeedComments\)/,
  'playback overlay keeps its viewport clip disabled while the feed is active');

// 3) 填充模式的 Surface 确实会比视口高：溢出是设计的一部分，靠页面裁剪收口，不能靠缩小 Surface。
const methods = source.slice(source.indexOf('  private feedSurfaceW('), source.indexOf('  private portraitScaleByTransform('));
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();
Object.assign(page, { ar: 9 / 16, effectiveScaleMode: () => 'fill', referenceMediaWidth: () => 440, referenceMediaHeight: () => 744 });
assert.equal(page.feedSurfaceW(), 440);
assert.ok(page.feedSurfaceH() > 744, 'cover surface overflows the viewport vertically for a 9:16 clip on a taller-than-16:9 screen');
Object.assign(page, { ar: 16 / 9, effectiveScaleMode: () => 'auto', referenceMediaWidth: () => 440, referenceMediaHeight: () => 247.5 });
assert.equal(page.feedSurfaceH(), 247.5, 'contain mode keeps the exact viewport size');
assert.equal(page.feedSurfaceW(), 440);

console.log('PASS: feed page clips its own bounds, overlay keeps viewport clip off, cover surface still overflows');
