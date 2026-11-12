const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// 提取弹幕几何相关方法（ovDanmakuCW → dmScaleFactor），转译后在桩对象上做数值断言。
const start = source.indexOf('  private ovDanmakuCW(');
const end = source.indexOf('  /** ⭐ 首次 build 前同步估算常驻层矩形');
assert.ok(start > 0 && end > start, 'danmaku geometry methods must stay in place');
const methods = source.slice(start, end);
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();

// 桩：连刷竖屏全屏态（cw×ch=440×744，状态栏 40）。
// media 系列模拟「完整显示」contain 后的视频框；ovRect 系列模拟常驻层矩形。
function feedPage({ cw = 440, ch = 744, safeTop = 40, mediaW, mediaH, rectX, rectY, amount = 0 }) {
  Object.assign(page, {
    referenceLayout: true, isLs: false, fs: false, referenceFeed: true,
    cw, ch,
    referenceFeedCommentAmount: () => amount,
    referenceSafeTop: () => safeTop,
    referenceMediaWidth: () => mediaW,
    referenceMediaHeight: () => mediaH,
    ovRectX: () => rectX, ovRectY: () => rectY,
    ovRectW: () => mediaW, ovRectH: () => mediaH,
    portraitScaleByTransform: () => true,          // 连刷 auto 模式下视频 surface 确实走基准+scale
    portraitScaleFactor: () => 0.5,
    portraitBaseW: () => 418.5, portraitBaseH: () => 744,
  });
  return page;
}

// 1) 竖片「完整显示」(contain)：媒体框 418.5 宽 ≠ 整屏 440 —— 弹幕区必须仍是整屏宽。
feedPage({ mediaW: 418.5, mediaH: 744, rectX: 10.75, rectY: 0 });
assert.equal(page.ovDanmakuCW(), 440, 'feed danmaku width must be the full screen width, not the contained media width');
assert.equal(page.ovDanmakuCH(), 744 - 40, 'feed danmaku height must span from the safe area to the screen bottom');
// 层内坐标 → 页面坐标：x + rectX = 0（页面左缘），y + rectY = safeTop。
assert.equal(page.dmPositionX(), -10.75, 'danmaku must reach the page left edge (layer origin sits at the media left)');
const pageX = page.dmPositionX() + page.ovRectX();
const pageY = page.dmPositionY() + page.ovRectY();
assert.equal(pageX, 0, 'danmaku left edge = page left edge');
assert.equal(pageY, 40, 'danmaku top edge = below the status bar safe area');
assert.equal(pageY + page.ovDanmakuCH(), 744, 'danmaku bottom edge = screen bottom');

// 2) 横片在连刷里居中成一条：弹幕也必须铺满整屏，不缩进 16:9 框。
feedPage({ mediaW: 440, mediaH: 247, rectX: 0, rectY: 174 });
assert.equal(page.ovDanmakuCW(), 440);
assert.equal(page.ovDanmakuCH(), 704);
assert.equal(page.dmPositionY(), 40 - 174, 'full-screen danmaku starts at the safe area even when the video sits mid-screen');
assert.equal(page.dmPositionY() + page.ovRectY() + page.ovDanmakuCH(), 744);

// 3) 连刷弹幕画布不再借用视频 surface 的基准+scale 通道（否则整屏口径被 scale 压回画幅）。
assert.equal(page.dmTransformChannel(), false, 'feed danmaku must not ride the portrait surface transform channel');
assert.equal(page.dmScaleFactor(), 1, 'feed danmaku canvas must render at 1:1');

// 4) 评论展开（amount=1）：弹幕收回视频区，不盖评论列表 —— 保持旧行为。
feedPage({ mediaW: 418.5, mediaH: 744, rectX: 10.75, rectY: 0, amount: 1 });
assert.equal(page.ovDanmakuCW(), 418.5, 'comments expanded: danmaku shrinks back to the media width');
assert.equal(page.ovDanmakuCH(), 744 - 40);
assert.equal(page.dmPositionX(), 0);
assert.equal(page.dmPositionY(), 40);
// 中间帧连续性：amount=0.5 时宽度介于整屏与媒体宽之间。
feedPage({ mediaW: 418.5, mediaH: 744, rectX: 10.75, rectY: 0, amount: 0.5 });
assert.ok(Math.abs(page.ovDanmakuCW() - 429.25) < 1e-6, 'comment transition interpolates the danmaku width');

// 5) 非连刷竖屏半屏：弹幕区 = **整个播放器区域**（视频槽），不是视频画面本身。
//    竖片只有半屏宽的一条、左右全是播放器黑底 —— 弹幕必须从屏幕左缘进、右缘出。
Object.assign(page, {
  referenceLayout: true, isLs: false, fs: false, referenceFeed: false, isLightsOff: false,
  cw: 440, ch: 744, referenceFeedProgress: 0,
  referenceFeedCommentAmount: () => 0,
  referenceSafeTop: () => 40,
  referenceAreaTop: () => 40, referenceAreaHeight: () => 386.9,
  referenceDetailBaseHeight: () => 386.9,
  referenceMediaWidth: () => 217.7, referenceMediaHeight: () => 386.9,
  ovRectX: () => 0, ovRectY: () => 40,
  ovRectW: () => 440, ovRectH: () => 386.9,
  portraitScaleByTransform: () => true,
  portraitScaleFactor: () => 0.52,
  portraitBaseW: () => 418.5, portraitBaseH: () => 744,
});
assert.equal(page.ovDanmakuCW(), 440, 'non-feed portrait: danmaku covers the whole playback area width, not the media strip');
assert.equal(page.ovDanmakuCH(), 386.9, 'non-feed portrait: danmaku covers the whole playback area height');
assert.equal(page.dmTransformChannel(), false, 'portrait danmaku must not ride the video surface scale channel (it would squeeze the canvas back to the media box)');
assert.equal(page.dmScaleFactor(), 1, 'portrait danmaku renders 1:1');
assert.equal(page.dmPositionX(), 0, 'portrait danmaku starts at the screen left edge');
assert.equal(page.dmPositionY(), 0, 'portrait danmaku starts at the playback area top (below the safe area)');

// 5b) 超宽片（>16:9）：上下留白同样属于播放区，画布按区域高而不是画面高。
Object.assign(page, {
  referenceMediaWidth: () => 440, referenceMediaHeight: () => 189,
  referenceAreaHeight: () => 247.5, referenceDetailBaseHeight: () => 247.5,
  ovRectH: () => 247.5,
});
assert.equal(page.ovDanmakuCH(), 247.5, 'ultrawide: letterbox bands are part of the playback area');

// 5c) 关灯：画面会被放大到窗口，仍按"贴画面"沿用媒体框（旧行为不变）。
Object.assign(page, {
  isLightsOff: true,
  referenceMediaWidth: () => 217.7, referenceMediaHeight: () => 386.9,
});
assert.equal(page.ovDanmakuCW(), 217.7, 'lights-off keeps the media width');
assert.equal(page.ovDanmakuCH(), 386.9, 'lights-off keeps the media height');
Object.assign(page, { isLightsOff: false });

// 6) 横屏分支完全不走新逻辑（横屏半屏：弹幕仍按横屏视口）。
Object.assign(page, {
  referenceLayout: true, isLs: true, fs: false, referenceFeed: true,
  referenceLandscapeViewportWidth: () => 833, referenceLandscapeAreaHeight: () => 519,
});
assert.equal(page.ovDanmakuCW(), 833, 'landscape fullscreen branch untouched');
assert.equal(page.ovDanmakuCH(), 519, 'landscape fullscreen branch untouched');

// 7) 源码口径：弹幕层定位/缩放必须用 dm 专用通道；视频 surface 的 portraitBase+scale 保持原样。
assert.ok(/dmPositionX\(\)/.test(source) && /dmPositionY\(\)/.test(source), 'danmaku stack must use the dm position helpers');
assert.ok(/\.scale\(\{ x: this\.dmScaleFactor\(\), y: this\.dmScaleFactor\(\) \}\)/.test(source), 'danmaku stack must use the dm scale factor');
const danmakuBlock = source.slice(source.indexOf('DanmakuView({'), source.indexOf('VideoControls({'));
assert.ok(!danmakuBlock.includes('this.portraitScaleByTransform()'), 'danmaku block must not consult the global portrait transform flag directly');
assert.ok(source.split('this.portraitScaleByTransform()').length > 5, 'video surface keeps using the portrait transform channel');

console.log('PASS: feed danmaku canvas spans the full screen (minus top safe area) regardless of video aspect; comments expansion still shrinks it back');
