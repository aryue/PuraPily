/**
 * 竖屏半屏常驻层 / 弹幕画布口径：**播放器区域**（视频槽），不是视频画面。
 *
 * 背景（用户反馈「弹幕画布应该是除了安全区外的整个播放区域，但竖屏分栏下被限制到了视频实际画面大小」）：
 *   · 竖片（9:16 甚至更窄）在竖屏里只有半屏宽的一条，两侧是播放器黑底；超宽片则是上下留白。
 *   · 这些黑底属于播放区域 —— 常驻层（因此弹幕画布）必须铺满它们，画面本身仍居中。
 *   · 旧口径把常驻层收成 `referenceMedia*`，弹幕只在画面那条窄带里飞（实测 217.7/440 宽）。
 *
 * 断言：
 *   1. 竖屏半屏 `portraitPlateByArea()` 为真，常驻层 = (0, areaTop, cw, areaHeight)；
 *   2. 画面位置不变：`ovRectY + (ovRectH - ovVideoH)/2` 恒等于 `referenceMediaTop()`；
 *   3. 弹幕画布 = 区域宽（cw） × 静止态区域高（不随面板拖动逐帧变），且 1:1 不再借 surface 的 scale；
 *   4. 关灯 / 连刷 / 横屏三类继续走媒体框（旧行为不变）；
 *   5. 源码口径：竖屏画布不得再出现 portraitBase 基准或 >1 的 scale。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

function slice(startMark, endMark) {
  const start = source.indexOf(startMark);
  const end = source.indexOf(endMark);
  assert.ok(start > 0 && end > start, `method block not found: ${startMark}`);
  return source.slice(start, end);
}

// 常驻层矩形 + 弹幕几何两段拼成一个类（弹幕几何会调用 ovRect* / portraitPlateByArea）。
const plate = slice('  private portraitPlateByArea(', '  /** ⭐ 常驻层内视频实际尺寸');
const danmaku = slice('  private ovDanmakuCW(', '  /** ⭐ 首次 build 前同步估算常驻层矩形');
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Page { ${plate}\n${danmaku} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();

/**
 * 竖屏几何桩：440×744 窗口、状态栏 40、播放区从 40 到 40+areaH。
 *
 * @param areaH 当前（可见）播放区高度 —— 详情面板上推后变小
 * @param baseH 静止态播放区高度 —— 画布（surface）高度取它，必须恒定
 */
function portrait({ ar = 9 / 16, areaH = 386.9, baseH = null, mediaW = 217.7, mediaH = 386.9, lightsOff = false, feed = false } = {}) {
  const base = baseH === null ? areaH : baseH;
  Object.assign(page, {
    referenceLayout: true, isLs: false, fs: false, fsEntering: false,
    isLandscapeVertical: false, isLightsOff: lightsOff, referenceFeed: feed,
    referenceFeedProgress: 0, referenceFeedCommentAmount: () => 0,
    cw: 440, ch: 744, ar, ovW: 440, ovH: areaH, ovX: 0, ovY: 40,
    referenceSafeTop: () => 40,
    referenceAreaTop: () => 40,
    referenceAreaHeight: () => areaH,
    referenceDetailBaseHeight: () => base,
    referenceMediaTop: () => 40 + Math.max(0, areaH - mediaH) / 2,
    referenceMediaWidth: () => mediaW,
    referenceMediaHeight: () => mediaH,
    portraitScaleByTransform: () => !lightsOff && !feed,
    portraitScaleFactor: () => 0.52,
    portraitBaseW: () => 418.5, portraitBaseH: () => 744,
  });
  return page;
}

// 1) 竖片：常驻层 = 整个播放区域，画面仍居中
portrait();
assert.equal(page.portraitPlateByArea(), true);
assert.equal(page.ovRectX(), 0);
assert.equal(page.ovRectY(), 40, 'plate top = playback area top (below the safe area)');
assert.equal(page.ovRectW(), 440);
assert.equal(page.ovRectH(), 386.9, 'plate height = playback area height, not the narrow media box');
assert.equal(page.ovRectY() + (page.ovRectH() - page.referenceMediaHeight()) / 2, page.referenceMediaTop(),
  'video stays centered exactly where referenceMediaTop put it');

// 2) 弹幕画布 = 整个播放区域，1:1
assert.equal(page.ovDanmakuCW(), 440, 'danmaku width = playback area width');
assert.equal(page.ovDanmakuCH(), 386.9, 'danmaku height = playback area height');
assert.equal(page.dmTransformChannel(), false, 'portrait danmaku must not ride the video surface transform');
assert.equal(page.dmScaleFactor(), 1);
assert.equal(page.dmPositionX(), 0);
assert.equal(page.dmPositionY(), 0);
// 静止态：可用高度 = 画布高（没被遮挡时两者一致，不该白扣行数）
assert.equal(page.dmTrackAreaHeight(), 386.9);

// 2b) 上推详情面板：画布恒定、可用高度跟着可见区域走
//     旧版只靠 clip 裁 → 11 行里被遮住的 4 行照样吃弹幕，"弹幕从已遮挡区域冒出来"
portrait({ areaH: 247.5, baseH: 386.9 });
assert.equal(page.ovDanmakuCH(), 386.9, 'canvas (surface) height must stay at the static height: 逐帧重建 surface = 叠字');
assert.equal(page.ovDanmakuCW(), 440);
assert.equal(page.dmTrackAreaHeight(), 247.5, 'track area must follow the visible playback area');
assert.equal(page.ovRectH(), 247.5, 'plate height = current visible area');
// 下拉到比静止态更高（正在滑向连刷）：可用高度夹到画布高，不能越出 canvas
portrait({ areaH: 500, baseH: 386.9 });
assert.equal(page.dmTrackAreaHeight(), 386.9, 'track area must be clamped to the canvas height');

// 3) 16:9：区域 = 画面（数值与旧口径一致，不允许出现黑边或错位）
portrait({ ar: 16 / 9, areaH: 247.5, mediaW: 440, mediaH: 247.5 });
assert.equal(page.ovRectH(), 247.5);
assert.equal(page.ovDanmakuCW(), 440);
assert.equal(page.ovDanmakuCH(), 247.5);
assert.equal(page.ovRectY() + (page.ovRectH() - page.referenceMediaHeight()) / 2, page.referenceMediaTop());

// 4) 超宽片（>16:9）：上下留白属于播放区，画布按区域高
portrait({ ar: 2.35, areaH: 247.5, mediaW: 440, mediaH: 189 });
assert.equal(page.ovRectH(), 247.5);
assert.equal(page.ovDanmakuCH(), 247.5, 'letterbox bands carry danmaku too');
assert.equal(page.ovRectY() + (page.ovRectH() - page.referenceMediaHeight()) / 2, page.referenceMediaTop());

// 5) 关灯：画面会被放大到窗口，仍按画面口径（旧行为）
portrait({ lightsOff: true });
assert.equal(page.portraitPlateByArea(), false);
assert.equal(page.ovRectY(), page.referenceMediaTop());
assert.equal(page.ovRectH(), 386.9);
assert.equal(page.ovDanmakuCW(), 217.7, 'lights-off keeps the media width');
assert.equal(page.ovDanmakuCH(), 386.9, 'lights-off keeps the media height');
assert.equal(page.dmTrackAreaHeight(), 0, 'lights-off must not use the track-area channel');

// 6) 连刷：常驻层回到媒体框（连刷自己的整屏混算在 ovDanmakuCW/CH 里）
portrait({ feed: true });
assert.equal(page.portraitPlateByArea(), false);
assert.equal(page.ovRectY(), page.referenceMediaTop());
assert.equal(page.ovRectH(), 386.9);
assert.equal(page.dmTrackAreaHeight(), 0, 'feed must keep the full-canvas layout');

// 7) 横屏分支完全不经过新逻辑
Object.assign(page, {
  referenceLayout: true, isLs: true, fs: false, isLightsOff: false, referenceFeed: false,
  referenceLandscapeViewportWidth: () => 833,
  referenceLandscapeAreaHeight: () => 519,
  referenceLandscapeAreaTop: () => 0,
});
assert.equal(page.portraitPlateByArea(), false);
assert.equal(page.ovDanmakuCW(), 833);
assert.equal(page.ovDanmakuCH(), 519);
assert.equal(page.dmTrackAreaHeight(), 0, 'landscape must not use the track-area channel');

// 8) 源码口径：dmTransformChannel 恒 false；画布高静止、可用高度跟手
const block = slice('  private dmTransformChannel()', '  /** ⭐ 首次 build 前同步估算常驻层矩形');
assert.ok(/private dmTransformChannel\(\): boolean \{\s*return false/.test(block),
  'dmTransformChannel must stay false: the surface scale squeezes the canvas back to the media box');
assert.ok(/dmPortraitSurfaceHeight\(\)/.test(danmaku), 'portrait canvas height must use the static surface height');
assert.ok(/dmTrackAreaHeight\(\)/.test(danmaku), 'portrait track layout must follow the visible area');
// 页面必须把可用高度下发给弹幕组件（否则 controller 永远按整块画布排行）
assert.ok(/trackAreaHeight:\s*this\.dmTrackAreaHeight\(\)/.test(source),
  'DanmakuView mount must receive trackAreaHeight');

console.log('PASS: portrait danmaku canvas = whole playback area (video bars included), track area follows the visible area, video stays centered, lights-off/feed/landscape untouched');
