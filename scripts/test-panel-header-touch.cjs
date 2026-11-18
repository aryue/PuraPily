// 竖屏播放页详情面板头部：「把手 + 简介/评论标题行」必须是同一条下拉进连刷手势通道。
// 读 CompileArkTS 产物（改源码后必须先 assembleHap）：
//   1) 结构：把手 distance 1、标题行 distance 8，两条 PanGesture 都调同一套回调；
//   2) 行为：首帧吃掉识别位移（不跳 slop）、跟手、夹取、松手进连刷/回弹/取消还原，
//      评论半屏只做下拉关闭。
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');

// ── 1. 结构：两条手势挂点（把手 / 标题行）──
const handleAt = source.indexOf("Row.id('reference-portrait-resize-handle');");
assert.ok(handleAt > 0, '把手 reference-portrait-resize-handle 丢失');
const handleSegment = source.slice(handleAt, handleAt + 900);
assert.match(handleSegment, /PanGesture\.create\(\{ direction: PanDirection\.Vertical, distance: 1 \}\)/,
  '把手必须保留 1vp 死区（原来就是它）');
for (const call of ['referencePanelHeaderPanStart', 'referencePanelHeaderPanUpdate',
  'referencePanelHeaderPanEnd', 'referencePanelHeaderPanCancel']) {
  assert.ok(handleSegment.includes(call), `把手手势没有调用 ${call}`);
}

const tabAnchors = [...source.matchAll(/Row\.padding\(\{ top: 6, left: 14, right: 12 \}\);/g)].map(m => m.index);
assert.ok(tabAnchors.length > 0, '简介/评论标题行丢失');
for (const index of tabAnchors) {
  // 编译产物会把同一段注释按链式属性重复展开，窗口取到「简介 / 评论」的 ForEach 之前。
  const end = source.indexOf('ForEach.create();', index);
  assert.ok(end > index, '标题行后面必须紧跟 简介/评论 Tab');
  const tabSegment = source.slice(index, end);
  assert.match(tabSegment, /PanGesture\.create\(\{ direction: PanDirection\.Vertical, distance: 8 \}\)/,
    '简介/评论标题行必须挂 8vp 死区的下拉手势（标题本身有点击目标，不能 1vp）');
  for (const call of ['referencePanelHeaderPanStart', 'referencePanelHeaderPanUpdate',
    'referencePanelHeaderPanEnd', 'referencePanelHeaderPanCancel']) {
    assert.ok(tabSegment.includes(call), `标题行手势没有调用 ${call}（两条通道必须同源）`);
  }
}

// 把手 20 + 空隙 6 + 内容 32 = 头部 58（横屏 8 + 6 + 32 = 46）。
// 6vp 空隙属于父 Column，两个子节点都不认 ⇒ 把空隙并进标题行的盒子（热区），
// 用 padding top 6 把内容盒压回 32vp，Tab / 弹幕胶囊位置逐值不变。
const headerHeightAt = source.indexOf('Column.height(this.isLs ? 46 : 58);');
assert.ok(headerHeightAt > 0, '头部高度丢失');
const headerCreateAt = source.lastIndexOf('Column.create', headerHeightAt);
assert.ok(headerCreateAt > 0, '找不到头部 Column 的创建点');
assert.ok(source.slice(headerCreateAt, headerCreateAt + 16).startsWith('Column.create();'),
  '头部不能再用 Column({ space: 6 })：标题行已用 height 38 吃掉空隙，再加 space 会溢出 64 > 58');
const handleHeightAt = source.indexOf("Row.id('reference-portrait-resize-handle');");
assert.ok(source.slice(handleHeightAt - 260, handleHeightAt).includes('this.isLs ? 8 : 20'),
  '把手高度必须是 20（横屏 8）');
for (const index of tabAnchors) {
  const heightAt = source.lastIndexOf('Row.height(38);', index);
  assert.ok(heightAt > 0 && index - heightAt < 900,
    '标题行盒子要 38vp（20/8 + 38 = 58/46），把手与标题行之间才没有死区');
  assert.ok(source.slice(index, index + 120).includes('top: 6'),
    '内容盒必须靠 padding top 6 压回 32vp，否则 Tab/弹幕胶囊会被挤动');
}

// ── 2. 行为：抽取方法逐帧驱动 ──
const from = source.indexOf('private referencePanelHeaderPanStart(): void {');
const to = source.indexOf('private referencePanelBodyTouch(e: TouchEvent): void {');
assert.ok(from > 0 && to > from, '抽不到头部手势方法');
const context = { exports: {}, Curve: { EaseOut: 0 } };
vm.runInNewContext(ts.transpileModule(
  `export class Page { ${source.slice(from, to)} }`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText, context);

// 与 utils/PlaybackViewport.portraitPanelDragOffset 同口径：下限夹到最小播放区，
// 超过 110 之后 0.25 阻尼。
const clamp = x => Math.max(-200, x > 110 ? 110 + Math.min(50, (x - 110) * 0.25) : x);
function page(offset = 0) {
  const animations = [];
  const p = new context.exports.Page();
  Object.assign(p, {
    isLs: false, referenceFeedComments: false, referencePanelOffset: offset,
    referencePanelStart: 0, referencePanelHeaderAnchored: false, referencePanelHeaderAnchor: 0,
    referencePanelDragOffset: clamp,
    referenceSetFeed: value => { p.feedCalls = (p.feedCalls || []).concat(value); },
    referenceSetFeedComments: value => { p.commentCalls = (p.commentCalls || []).concat(value); },
    getUIContext: () => ({ animateTo: (options, update) => { animations.push(options); update(); } })
  });
  p.animations = animations;
  return p;
}

// 首帧吃掉识别位移：8vp 死区不写进面板，之后 1:1 跟手（不跳 slop）
const follow = page(0);
follow.referencePanelHeaderPanStart();
follow.referencePanelHeaderPanUpdate(8);
assert.equal(follow.referencePanelOffset, 0, '识别帧的 8vp 不能凭空补进面板（会跳一下）');
follow.referencePanelHeaderPanUpdate(20);
assert.equal(follow.referencePanelOffset, 12, '吃掉死区后必须 1:1 跟手');
follow.referencePanelHeaderPanUpdate(-30);
assert.equal(follow.referencePanelOffset, -38, '反向跟手沿用同一映射');
follow.referencePanelHeaderPanUpdate(2000);
assert.equal(follow.referencePanelOffset, 160, '超量下拉走 0.25 阻尼，不无限跟手');

// 松手：过 90 进连刷
const enter = page(0);
enter.referencePanelHeaderPanStart();
enter.referencePanelHeaderPanUpdate(8);
enter.referencePanelHeaderPanUpdate(140);
enter.referencePanelHeaderPanEnd(140, 300);
assert.deepEqual(enter.feedCalls, [true], '面板下拉过 90 必须进连刷');
assert.equal(enter.animations.length, 0, '进连刷不需要额外回弹动画');

// 松手：快甩（位移不大但速度够）也进连刷 —— 与原把手口径一致
const flick = page(0);
flick.referencePanelHeaderPanStart();
flick.referencePanelHeaderPanUpdate(8);
flick.referencePanelHeaderPanUpdate(50);
flick.referencePanelHeaderPanEnd(50, 900);
assert.deepEqual(flick.feedCalls, [true], '45vp + 850 速度的甩动必须进连刷');

// 松手：没到阈值回起点
const bounce = page(0);
bounce.referencePanelHeaderPanStart();
bounce.referencePanelHeaderPanUpdate(8);
bounce.referencePanelHeaderPanUpdate(60);
bounce.referencePanelHeaderPanEnd(60, 100);
assert.equal(bounce.feedCalls, undefined, '没到阈值不能进连刷');
assert.equal(bounce.animations.length, 1, '没到阈值要回弹到起点');
assert.equal(bounce.referencePanelOffset, 0);
assert.equal(bounce.animations[0].duration, 240);

// ⭐ 上推必须真的动：第一帧 offsetY 就是负数（-1 / -8），不能把「负数」当成「还没取锚点」。
//    用 anchor < 0 当哨兵会每帧重取锚点，`offsetY - anchor` 恒为 0，上推彻底失效（真机反馈过）。
const pushFirstFrame = page(0);
pushFirstFrame.referencePanelHeaderPanStart();
pushFirstFrame.referencePanelHeaderPanUpdate(-1);   // 把手 distance 1 的首帧
assert.equal(pushFirstFrame.referencePanelOffset, 0, '上推首帧只吃死区');
pushFirstFrame.referencePanelHeaderPanUpdate(-120);
assert.equal(pushFirstFrame.referencePanelOffset, -119, '上推从静止起手必须跟手，不能被锚点吃掉');

const pushEight = page(0);
pushEight.referencePanelHeaderPanStart();
pushEight.referencePanelHeaderPanUpdate(-8);        // 标题行 distance 8 的首帧
assert.equal(pushEight.referencePanelOffset, 0);
pushEight.referencePanelHeaderPanUpdate(-45);
assert.equal(pushEight.referencePanelOffset, -37);
pushEight.referencePanelHeaderPanUpdate(30);
assert.equal(pushEight.referencePanelOffset, 38, '上推途中折返同样 1:1 跟手');

// 上推（offset <= 0）松手不回弹：保持无级播放区
const pushUp = page(0);
pushUp.referencePanelHeaderPanStart();
pushUp.referencePanelHeaderPanUpdate(8);
pushUp.referencePanelHeaderPanUpdate(-120);
pushUp.referencePanelHeaderPanEnd(-120, -200);
assert.equal(pushUp.referencePanelOffset, -128);
assert.equal(pushUp.animations.length, 0, '上推松手必须停在手指位置，不能吸附');

// 取消：还原到起手时的偏移
const cancel = page(-35);
cancel.referencePanelHeaderPanStart();
cancel.referencePanelHeaderPanUpdate(8);
cancel.referencePanelHeaderPanUpdate(120);
cancel.referencePanelHeaderPanCancel();
assert.equal(cancel.referencePanelOffset, -35, '手势取消必须回到起手位置');
assert.equal(cancel.animations[0].duration, 180);

// 评论半屏：头部只做下拉关闭，不动面板几何
const comments = page(-35);
comments.referenceFeedComments = true;
comments.referencePanelHeaderPanStart();
comments.referencePanelHeaderPanUpdate(8);
comments.referencePanelHeaderPanUpdate(160);
assert.equal(comments.referencePanelOffset, -35, '评论半屏不能让面板跟着长高');
comments.referencePanelHeaderPanEnd(60, 100);
assert.deepEqual(comments.commentCalls, undefined, '小幅下拉不能关评论');
const closeComments = page(-35);
closeComments.referenceFeedComments = true;
closeComments.referencePanelHeaderPanStart();
closeComments.referencePanelHeaderPanUpdate(8);
closeComments.referencePanelHeaderPanUpdate(90);
closeComments.referencePanelHeaderPanEnd(90, 200);
assert.deepEqual(closeComments.commentCalls, [false], '下拉过 80 必须关掉评论半屏');
assert.equal(closeComments.feedCalls, undefined, '评论半屏下拉不能进连刷');

// 横屏：整套回调原地返回（横屏走分隔条 referenceLandscapeResize）
const landscape = page(0);
landscape.isLs = true;
landscape.referencePanelHeaderPanStart();
landscape.referencePanelHeaderPanUpdate(200);
landscape.referencePanelHeaderPanEnd(200, 2000);
assert.equal(landscape.referencePanelOffset, 0, '横屏不能被头部手势改几何');
assert.equal(landscape.feedCalls, undefined);
assert.equal(landscape.animations.length, 0);

// 下一次手势必须重新吞死区：锚点残留会让第二轮少 8vp
const again = page(0);
again.referencePanelHeaderPanStart();
again.referencePanelHeaderPanUpdate(8);
again.referencePanelHeaderPanEnd(0, 0);
again.referencePanelHeaderPanStart();
again.referencePanelHeaderPanUpdate(8);
assert.equal(again.referencePanelOffset, 0, '第二次手势的识别位移同样要吃掉');

console.log('PASS: 面板头部（把手 + 简介/评论标题行）共用下拉进连刷手势，首帧不跳、跟手/夹取/进连刷/回弹/取消/评论/横屏口径全部一致。');
