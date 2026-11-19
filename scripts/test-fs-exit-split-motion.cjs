/**
 * 退全屏到横屏分栏：副栏是否跟着同一条插值进度滑入（2026-11-20）。
 *
 * 背景：用户反馈「硬的不只是控件，而是整个切换过程」。
 *   原先只有视频在动：全屏底板一撤，副栏（简介/评论）已经在静止位置原地出现，
 *   视频单独缩 200ms，最后 `fs=false` 又把分发线/顶栏一次性换上来 —— 三段互不相干。
 *   修法：按同一条 `fsPanProgress`(1→0) 把副栏连同分发线一起从窗口外推回来。
 *
 * 本脚本锁住：
 *   ① P=1 时副栏必须完全在窗口外（否则会在动画起点"啪"地出现）；
 *   ② P=0 时位移必须归零、分发线完全不透明（否则落位会跳一下）；
 *   ③ 位移随 P 单调、连续，不允许中途越过静止位置；
 *   ④ 只在 `fs && fsLerpDir===2` 生效（进入全屏/稳态/分栏拖动不得被碰到）；
 *   ⑤ 结构约束：副栏与分发线必须用**同一个**位移量。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const split = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/components/SplitPaneLayout.ets'), 'utf8').replace(/\r\n/g, '\n');

function between(text, start, end) {
  const from = text.indexOf(start);
  assert.ok(from >= 0, `missing start: ${start}`);
  const to = text.indexOf(end, from + start.length);
  assert.ok(to > from, `missing end: ${end}`);
  return text.slice(from, to);
}

const methods = between(source,
  '  private exitSplitShiftX(): number {',
  '  private referenceLandscapeResize(offset: number): void {');

const context = { exports: {}, Math, Number, console };
vm.runInNewContext(ts.transpileModule(`export class Page {
${methods}
}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

// 横屏分栏真机口径：窗口 744 宽，播放区 2/3、副栏 224、两侧 inset 12
const CW = 744;
const INSET = 12;
const PRIMARY_W = 496;
const PANEL_W = 224;
const PANEL_X = PRIMARY_W + INSET;      // 508
const PANEL_X_SWAPPED = INSET;          // 12

function page(overrides) {
  const p = new context.exports.Page();
  Object.assign(p, {
    cw: CW, ch: 418.5,
    fs: true, fsLerpDir: 2, fsPanProgress: 1,
    isLayoutSwapped: false,
    referenceLandscapePanelX: () => PANEL_X,
    referenceLandscapePanelWidth: () => PANEL_W
  });
  Object.assign(p, overrides || {});
  return p;
}

// ① 动画起点：副栏必须完全在窗口外
{
  const p = page({});
  const shift = p.exitSplitShiftX();
  assert.equal(shift, CW - PANEL_X, `P=1 应把副栏推到窗口外，实际 ${shift}`);
  assert.ok(PANEL_X + shift >= CW - 1e-6, 'P=1 时副栏左缘必须 ≥ 窗口右缘');
  assert.equal(p.exitSplitHandleOpacity(), 0, 'P=1 时分发线必须透明（它正卡在窗口边缘）');
}

// ② 动画终点：位移归零、分发线不透明
{
  const p = page({ fsPanProgress: 0 });
  assert.equal(p.exitSplitShiftX(), 0, 'P=0 位移必须归零');
  assert.equal(p.exitSplitHandleOpacity(), 1, 'P=0 分发线必须完全不透明');
}

// ③ 全程单调、连续，且不得越过静止位置
{
  const p = page({});
  let prev = p.exitSplitShiftX();
  let prevOpacity = p.exitSplitHandleOpacity();
  for (let i = 19; i >= 0; i--) {
    p.fsPanProgress = i / 20;
    const shift = p.exitSplitShiftX();
    const opacity = p.exitSplitHandleOpacity();
    assert.ok(shift <= prev + 1e-9, `P=${i / 20} 位移反向（${shift} > ${prev}）`);
    assert.ok(shift >= -1e-9, `P=${i / 20} 位移越过静止位置（${shift}）`);
    assert.ok(prev - shift <= (CW - PANEL_X) / 20 + 1e-6, `P=${i / 20} 位移跳变（${prev} → ${shift}）`);
    assert.ok(opacity >= prevOpacity - 1e-9, `P=${i / 20} 分发线透明度反向`);
    prev = shift;
    prevOpacity = opacity;
  }
  assert.equal(prev, 0, '扫描到 P=0 必须归零');
}

// ④ 播放区在右（swapped）：副栏从左缘外滑入
{
  const p = page({ isLayoutSwapped: true, referenceLandscapePanelX: () => PANEL_X_SWAPPED });
  const shift = p.exitSplitShiftX();
  assert.equal(shift, -(PANEL_X_SWAPPED + PANEL_W), `swapped P=1 位移错误：${shift}`);
  assert.ok(PANEL_X_SWAPPED + shift + PANEL_W <= 1e-6, 'swapped P=1 副栏右缘必须 ≤ 窗口左缘');
  p.fsPanProgress = 0;
  assert.equal(p.exitSplitShiftX(), 0);
}

// ⑤ 只在退出插值（fs && dir=2）生效
{
  assert.equal(page({ fs: false, fsLerpDir: 0 }).exitSplitShiftX(), 0, '非全屏不得位移');
  assert.equal(page({ fsLerpDir: 0 }).exitSplitShiftX(), 0, '全屏稳态不得位移');
  assert.equal(page({ fsLerpDir: 1, fsPanProgress: 0.5 }).exitSplitShiftX(), 0, '进入全屏不得位移');
  assert.equal(page({ fs: false, fsLerpDir: 0 }).exitSplitHandleOpacity(), 1, '非全屏分发线恒不透明');
  assert.equal(page({ fsLerpDir: 1, fsPanProgress: 0.5 }).exitSplitHandleOpacity(), 1, '进入全屏分发线恒不透明');
}

// ⑥ 结构约束：副栏与分发线必须共用同一个位移量
{
  assert.ok(split.includes('position({ x: this.secondaryX + this.secondaryShiftX'),
    '副栏位置必须叠加 secondaryShiftX');
  assert.ok(split.includes('splitHandleX(this.secondaryX + this.secondaryShiftX'),
    '分发线必须叠加同一个 secondaryShiftX（否则两者会分离）');
  assert.ok(split.includes('.opacity(this.handleOpacity)'), '分发线必须接受 handleOpacity');
  assert.ok(source.includes('secondaryShiftX: this.isLs ? this.exitSplitShiftX() : 0'),
    '页面必须把位移交给分栏组件');
  assert.ok(source.includes('handleOpacity: this.exitSplitHandleOpacity()'),
    '页面必须把分发线透明度交给分栏组件');
  const handle = between(source, 'showHandle: this.referenceLayout && this.isLs', 'swapped: this.isLayoutSwapped');
  assert.ok(handle.includes('this.fsLerpDir === 2'), '退全屏插值期间必须显示分发线（否则它是落位那帧才出现的）');
}

// ⑦ 落位不跳：浮动评论入口宽度不得再按全屏口径算
{
  const entry = between(source, 'FloatingCommentEntry({ bottomInset: this.navIndicatorHeight,', 'onOpen: () => this.openCommentSheet');
  assert.ok(!/isLs && !this\.fs/.test(entry), '副栏露出后入口宽度不能再按 cw 算（落位会突然缩窄）');
}

console.log('test-fs-exit-split-motion: PASS');
