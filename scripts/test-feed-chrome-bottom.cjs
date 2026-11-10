const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// 1) 位置只由「屏幕底部」决定：不能再按画幅把信息层贴到「全屏播放」按钮下方
//    （平板上的宽画幅视频会被压成中间一条，跟着画幅走就会飘到屏幕中间）。
const chromeSrc = source.slice(source.indexOf('  private feedChromeTop('), source.indexOf('  private trimReferenceDetails('));
assert.ok(!/aspect/.test(chromeSrc), 'feedChromeTop must not take the video aspect any more');
assert.ok(!/referenceFullscreenButtonTop|referenceMediaTop|referenceMediaHeight/.test(chromeSrc),
  'feedChromeTop must not follow the media rect');

// 2) 底部留白与顶部控件同一套安全区口径，且不小于系统手势条。
const methods = source.slice(source.indexOf('  private referenceChromeInset('), source.indexOf('  private trimReferenceDetails('));
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();
Object.assign(page, { ch: 744, referenceSafeTop: () => 40, navIndicatorHeight: 16, referenceFeedDragY: 0 });
assert.equal(page.referenceChromeInset(), 40);
assert.equal(page.feedChromeTop(), 744 - 244 - 40);
Object.assign(page, { referenceSafeTop: () => 12, navIndicatorHeight: 24 });
assert.equal(page.referenceChromeInset(), 28, 'a taller gesture bar still wins over the status bar inset');
assert.equal(page.feedChromeTop(), 744 - 244 - 28);
// 两套信息层用同一个函数：滑入页只多一个跟手提前量，滑到位收敛到同一个位置。
Object.assign(page, { referenceSafeTop: () => 40, navIndicatorHeight: 16, referenceFeedDragY: -744 });
assert.equal(page.feedChromeTop(true), page.feedChromeTop());
Object.assign(page, { referenceFeedDragY: 0 });
assert.ok(page.feedChromeTop(true) < page.feedChromeTop(), 'incoming layer is lifted while the page is still offscreen');

// 3) 两层容器同高、同内边距，横向 8vp 与顶栏（padding left/right 8）对齐。
const blocks = [...source.matchAll(/\.height\(244 \+ this\.referenceChromeInset\(\)\)[^\n]*\n\s*\.padding\(\{ left: 8, right: 8, bottom: this\.referenceChromeInset\(\) \}\)/g)];
assert.equal(blocks.length, 2, 'both feed info layers must use the same height and 8vp side insets');
assert.equal([...source.matchAll(/\.height\(244 \+ this\.referenceChromeInset\(\)\)\.justifyContent\(FlexAlign\.End\)/g)].length, 2,
  'content must hug the bottom inset instead of leaving the block slack underneath');
assert.ok(!source.includes("padding({ left: 12, right: 6 })"), 'old 12/6 action-row padding must be gone');
assert.ok(!source.includes(".width('96%').height(20)"), 'progress bar must span the padded content width');

console.log('PASS: feed info layer pinned to the screen bottom, safe-area inset, 8vp side insets, both layers identical');
