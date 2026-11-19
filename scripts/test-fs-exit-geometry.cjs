/**
 * 退全屏几何基准回归（2026-11-19）。
 *
 * 背景：真机录屏（旋转锁定开 = 插值路径 B）里，退全屏期间
 *   `ovRectW/H` 用**实时 cw/ch**（容器跟窗口缩），
 *   `ovVideoW/H` 用**横屏快照 snapshot**（`fullscreenSurfaceExtent` 在 dir=2、P=1 返回 snapshot）
 * ⇒ 系统把窗口一步换成 440×744 后，744 宽的画面挂在 440 宽的容器里，只有屏幕边缘能切它，
 *   屏上就是"画面比屏幕大 / 飞到屏幕外"。
 *
 * 本脚本锁住两条规则（改坏了会直接 FAIL）：
 *   ① 退出方向（dir=2）与"退出旋转直提"冻结期，画面必须等比缩进容器（装得下则不动）；
 *   ② 进入全屏（dir=1）与进入侧冻结期不得被这条规则碰到。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');

function between(start, end) {
  const from = source.indexOf(start);
  assert.ok(from >= 0, `missing start: ${start}`);
  const to = source.indexOf(end, from + start.length);
  assert.ok(to > from, `missing end: ${end}`);
  return source.slice(from, to);
}

const methods = [
  between('  private portraitPlateByArea(): boolean {', '  private feedSurfaceW(): number {'),
  between('  private fsExitVideoScale(): number {', '  private fsLerpRadius(')
].join('\n');

const viewport = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils/PlaybackViewport.ets'), 'utf8');

const context = { exports: {}, Math, Number, console };
vm.runInNewContext(ts.transpileModule(`${viewport}
export class Page {
${methods}
}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

// 16:9 视频：横屏全屏 744×440 窗口 → 画面 744×418.5；竖屏 440×744 窗口 → videoDisplay 424×238.5
const LANDSCAPE_W = 744;
const LANDSCAPE_H = 440;
const PORTRAIT_W = 440;
const PORTRAIT_H = 744;
const FS_VIDEO_W = 744;
const FS_VIDEO_H = 418.5;
const SLOT_W = 440;
const SLOT_H = 247.5;
const PORTRAIT_VIDEO_W = 424;
const PORTRAIT_VIDEO_H = 238.5;

function page(overrides) {
  const p = new context.exports.Page();
  Object.assign(p, {
    referenceLayout: true, referenceFeed: false, referenceFeedProgress: 0,
    isLightsOff: false, isLandscapeVertical: false, isPcDevice: false,
    cw: PORTRAIT_W, ch: PORTRAIT_H, ar: 16 / 9,
    fs: true, fsEntering: false, fsFreezeToWindow: false,
    fsLerpDir: 2, fsPanProgress: 1, fsLerpStartP: 0,
    ovW: SLOT_W, ovH: SLOT_H, lsvw: LANDSCAPE_W, lsvh: LANDSCAPE_H,
    videoDisplayWidth: PORTRAIT_VIDEO_W, videoDisplayHeight: PORTRAIT_VIDEO_H,
    fsLerpSnapX: 0, fsLerpSnapY: 0, fsLerpSnapW: LANDSCAPE_W, fsLerpSnapH: LANDSCAPE_H,
    fsLerpSnapVW: FS_VIDEO_W, fsLerpSnapVH: FS_VIDEO_H,
    referenceLandscapeViewportWidth: () => LANDSCAPE_W,
    referenceLandscapeAreaTop: () => 0,
    referenceLandscapeAreaHeight: () => PORTRAIT_H,
    referenceLandscapeMediaWidth: () => FS_VIDEO_W,
    referenceLandscapeMediaHeight: () => FS_VIDEO_H,
    referenceLandscapePlayerX: () => 0,
    referenceAreaTop: () => 0, referenceAreaHeight: () => SLOT_H,
    referenceMediaWidth: () => SLOT_W, referenceMediaHeight: () => SLOT_H,
    referenceMediaTop: () => 0,
    effectiveScaleMode: () => 'auto',
    loVideoWidth: () => PORTRAIT_W, loVideoHeight: () => PORTRAIT_H,
    shrinkFillW: () => PORTRAIT_VIDEO_W, shrinkFillH: () => PORTRAIT_VIDEO_H,
    safeCM: () => 8,
    feedSurfaceW: () => PORTRAIT_VIDEO_W, feedSurfaceH: () => PORTRAIT_VIDEO_H
  });
  Object.assign(p, overrides || {});
  return p;
}

function assertContained(p, label) {
  const w = p.ovVideoW();
  const h = p.ovVideoH();
  const pw = p.ovRectW();
  const ph = p.ovRectH();
  assert.ok(w <= pw + 1e-6, `${label}: surface ${w.toFixed(1)} 宽超过容器 ${pw.toFixed(1)}`);
  assert.ok(h <= ph + 1e-6, `${label}: surface ${h.toFixed(1)} 高超过容器 ${ph.toFixed(1)}`);
  // 等比：不许为了塞进容器把画面压扁
  const surfaceAspect = w / h;
  const expected = FS_VIDEO_W / FS_VIDEO_H;
  assert.ok(Math.abs(surfaceAspect - expected) < 1e-6, `${label}: 宽高比被改坏 ${surfaceAspect.toFixed(4)}`);
}

// ① 路径 B：系统已把窗口换成竖屏，P 仍是 1（修复前 ovVideoW=744 > ovRectW=440）
{
  const p = page({});
  assert.equal(p.ovRectW(), PORTRAIT_W, '容器必须跟当前窗口宽');
  assert.equal(p.ovRectH(), PORTRAIT_H, '容器必须跟当前窗口高');
  assertContained(p, 'B/P=1');
  assert.ok(Math.abs(p.ovVideoW() - PORTRAIT_W) < 1e-6, `应缩到窗口宽，实际 ${p.ovVideoW()}`);
  assert.ok(Math.abs(p.ovVideoH() - SLOT_H) < 1e-6, `应等比缩到 ${SLOT_H}，实际 ${p.ovVideoH()}`);
}

// ② 路径 B 插值中段：全程不得超出容器
for (const progress of [0.9, 0.75, 0.5, 0.25, 0.1]) {
  const p = page({ fsPanProgress: progress });
  assertContained(p, `B/P=${progress}`);
}

// ③ 插值终点：本来就装得下 ⇒ 缩放系数必须是 1（不能把末帧改小）
{
  const p = page({ fsPanProgress: 0 });
  assert.equal(p.fsExitVideoScale(), 1, '末帧不应再缩放');
  assert.equal(p.ovVideoW(), PORTRAIT_VIDEO_W);
  assert.equal(p.ovVideoH(), PORTRAIT_VIDEO_H);
  assert.equal(p.ovRectW(), SLOT_W);
  assert.equal(p.ovRectH(), SLOT_H);
}

// ④ 进入全屏（dir=1）不得被这条规则碰到
{
  const p = page({
    isLs: true, cw: LANDSCAPE_W, ch: LANDSCAPE_H, fsLerpDir: 1, fsPanProgress: 0.5,
    fsLerpSnapW: SLOT_W, fsLerpSnapH: SLOT_H, fsLerpSnapVW: PORTRAIT_VIDEO_W, fsLerpSnapVH: PORTRAIT_VIDEO_H
  });
  assert.equal(p.fsExitVideoScale(), 1, 'dir=1 不允许缩放');
  assert.equal(p.ovVideoW(), p.ovVideoWidthRaw());
  assert.equal(p.ovVideoH(), p.ovVideoHeightRaw());
}

// ⑤ 全屏稳态（dir=0）不得被这条规则碰到
{
  const p = page({ fsLerpDir: 0, fsPanProgress: 1, isLs: true, cw: LANDSCAPE_W, ch: LANDSCAPE_H });
  assert.equal(p.fsExitVideoScale(), 1);
  assert.equal(p.ovVideoW(), p.ovVideoWidthRaw());
}

// ⑥ 退出全屏到横屏（PC / 横屏分栏）：容器就是横屏窗口，画面本来就装得下
{
  const p = page({ isLs: true, cw: LANDSCAPE_W, ch: LANDSCAPE_H, ovW: LANDSCAPE_W, ovH: LANDSCAPE_H });
  assert.equal(p.fsExitVideoScale(), 1, '横屏退出不该缩');
  assertContained(p, 'exit-to-landscape');
  assert.equal(p.ovVideoW(), FS_VIDEO_W);
}

// ⑦ 路径 A：退出旋转直提的冻结期 —— 常驻层跟窗口，画面等比缩进去
{
  const p = page({ fsEntering: true, fsFreezeToWindow: true, fsLerpDir: 0, fsPanProgress: 1, isLs: false });
  assert.equal(p.ovRectX(), 0, '冻结期常驻层从窗口左上角开始');
  assert.equal(p.ovRectY(), 0);
  assert.equal(p.ovRectW(), PORTRAIT_W, '冻结期常驻层宽度跟窗口');
  assert.equal(p.ovRectH(), PORTRAIT_H, '冻结期常驻层高度跟窗口');
  assertContained(p, 'A/freeze');
  assert.ok(Math.abs(p.ovVideoW() - PORTRAIT_W) < 1e-6, `冻结期画面应缩到窗口宽，实际 ${p.ovVideoW()}`);
}

// ⑧ 进入侧冻结（fsEntering 但 fsFreezeToWindow=false）必须保持原样：冻结在竖屏槽
{
  const p = page({
    fsEntering: true, fsFreezeToWindow: false, fs: false, fsLerpDir: 0, fsPanProgress: 0,
    cw: LANDSCAPE_W, ch: LANDSCAPE_H,
    fsLerpSnapX: 0, fsLerpSnapY: 39, fsLerpSnapW: SLOT_W, fsLerpSnapH: SLOT_H,
    fsLerpSnapVW: SLOT_W, fsLerpSnapVH: SLOT_H
  });
  assert.equal(p.ovRectX(), 0);
  assert.equal(p.ovRectY(), 39, '进入冻结仍停在竖屏槽的位置');
  assert.equal(p.ovRectW(), SLOT_W, '进入冻结不能铺满窗口');
  assert.equal(p.ovRectH(), SLOT_H, '进入冻结不能铺满窗口');
  assert.equal(p.ovVideoW(), SLOT_W);
  assert.equal(p.ovVideoH(), SLOT_H);
}

// ⑨ 结构约束：缩放只挂在退出方向，且 ovVideoW/H 必须走 raw+scale
{
  assert.ok(source.includes('this.ovVideoWidthRaw() * this.fsExitVideoScale()'), 'ovVideoW 必须 raw×scale');
  assert.ok(source.includes('this.ovVideoHeightRaw() * this.fsExitVideoScale()'), 'ovVideoH 必须 raw×scale');
  const scale = between('  private fsExitVideoScale(): number {', '  private ovVideoW(): number {');
  assert.ok(scale.includes('if (!this.fs) return 1;'), '非全屏不允许缩放');
  assert.ok(scale.includes('this.fsLerpDir !== 2 && !this.fsFreezeToWindow'), '只允许退出方向/退出冻结期生效');
  const exitFreeze = between('  private async rotateReferenceFullscreen(entering: boolean, target: boolean): Promise<void> {',
    '    const source = this.fullscreenSource;');
  assert.ok(exitFreeze.includes('this.fsFreezeToWindow = !entering;'), '冻结方向必须由 rotateReferenceFullscreen 决定');
  const enterFreeze = between('  async startFSAnimation() {', '    this.fsHapticPrev = 0;');
  assert.ok(enterFreeze.includes('this.fsFreezeToWindow = false;'), '手势进入全屏必须清掉退出冻结标记');
}

console.log('test-fs-exit-geometry: PASS');
