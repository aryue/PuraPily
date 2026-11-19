/**
 * 退全屏「插值起点确定化」回归（2026-11-19 二次修正）。
 *
 * 真机反馈："还是看到了两个动画，一个是先缩小后旋转，一个是同步旋转和缩小，随机出现。"
 *
 * 方向判据保持原样（按实际方向：`returnLandscape` 看重力传感器；系统旋转锁定开启时跟随当前方向），
 * 真正的随机来自 **200ms 插值的起跑时机**：
 *   `waitForRotationEnd(() => this.rotationInProgress, …)` 在 `rotationInProgress` 尚未置位时
 *   **直接返回**。它要等 `applyPlaybackWindowSize` 发现方向翻转才置 true，
 *   而 `disableLandscapeMultiWindow()` 的窗口重排事件可能晚于本次判定 ⇒ 有时等到、有时不等：
 *   · 等到 → 系统先转完，再插值收起（"同步旋转和缩小"）
 *   · 不等 → 插值先跑，画面在仍是横屏的窗口里缩小（"先缩小后旋转"）
 *
 * 本脚本锁住：
 *   ① 插值前必须调 `waitForStableWindowSize()`（连续 3 拍尺寸不变），不得再用 `waitForRotationEnd`；
 *   ② `waitForStableWindowSize` 在窗口稳定时 ≈60~140ms 返回，窗口变化时等到变化结束再返回；
 *   ③ 方向判据不得回退成"进入前方向"静态快照（必须继续调 `returnLandscape`）。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const PAGE = path.resolve(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets');
const ORIENTATION_FILE = path.resolve(__dirname, '../entry/src/main/ets/utils/FullscreenDeviceOrientation.ets');
const source = fs.readFileSync(PAGE, 'utf8').replace(/\r\n/g, '\n');
const orientationSource = fs.readFileSync(ORIENTATION_FILE, 'utf8').replace(/\r\n/g, '\n');

function between(start, end) {
  const from = source.indexOf(start);
  assert.ok(from >= 0, `missing start: ${start}`);
  const to = source.indexOf(end, from + start.length);
  assert.ok(to > from, `missing end: ${end}`);
  return source.slice(from, to);
}

// ---- 结构约束 ----
assert.ok(
  /private async exitFullscreenAnimated\(\): Promise<void> \{[\s\S]*?this\.waitForStableWindowSize\(\)/.test(source),
  'exitFullscreenAnimated 必须调用 waitForStableWindowSize()'
);
assert.ok(
  !/exitFullscreenAnimated[\s\S]{0,4000}?playbackWindow_\.waitForRotationEnd\(/.test(source.slice(source.indexOf('private async exitFullscreenAnimated'))),
  'exitFullscreenAnimated 不得再用 waitForRotationEnd（rotationInProgress 未置位时会早退）'
);
assert.ok(
  /private fullscreenReturnLandscape\(\): boolean \{[\s\S]{0,300}?this\.fullscreenDeviceOrientation\.returnLandscape\(/.test(source),
  'fullscreenReturnLandscape 必须继续调用 returnLandscape（按实际方向），不得改成静态快照'
);
assert.ok(
  /returnLandscape\(\s*source\.orientation\s*,\s*source\.isLandscape\s*,/.test(source),
  'returnLandscape 的 current 必须是非全屏态方向 source.isLandscape'
);
assert.ok(
  !/returnLandscape\(\s*source\.orientation\s*,\s*this\.isLs\s*,/.test(source),
  'current 不得传全屏态 isLs：手机锁定开启时全屏恒横屏，会被误判成"退出回横屏"'
);
assert.ok(
  /this\.restoreFullscreenSource\(\);[\s\S]{0,420}?this\.cv = false;/.test(source),
  '退出到横屏（B 路）必须在 restoreFullscreenSource 后立即收起控件：fs=false 之前全屏控件会一直跟着画面缩'
);
assert.ok(
  /ACCELEROMETER_ROTATION_STATUS/.test(orientationSource),
  'returnLandscape 必须保留系统旋转锁定判断（锁定开启时返回非全屏态方向）'
);

// ---- 行为约束：抽 waitForStableWindowSize 在沙箱里跑 ----
const method = between('  private async waitForStableWindowSize(): Promise<void> {', '\n  }\n');
const context = { exports: {}, console, setTimeout, Date };
vm.runInNewContext(ts.transpileModule(`
export class Page {
  constructor() { this.cw = 0; this.ch = 0; }
${method}
}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

const Page = context.exports.Page;

(async () => {
  // 场景 1：窗口本来就稳定 → 3 拍后返回（≈60~140ms）
  const stable = new Page();
  stable.cw = 440;
  stable.ch = 744;
  let t0 = Date.now();
  await stable.waitForStableWindowSize();
  const stableMs = Date.now() - t0;
  const okStable = stableMs >= 55 && stableMs <= 220;
  console.log(`${okStable ? 'PASS' : 'FAIL'}  稳定窗口 → ${stableMs}ms（期望 3 拍稳定窗，Node 定时器不精确故上限放宽）`);
  assert.ok(okStable);

  // 场景 2：窗口在第 1 拍后翻转（横→竖）→ 必须等到翻转后重新稳定
  const moving = new Page();
  moving.cw = 744;
  moving.ch = 440;
  setTimeout(() => { moving.cw = 440; moving.ch = 744; }, 30);
  t0 = Date.now();
  await moving.waitForStableWindowSize();
  const movingMs = Date.now() - t0;
  const okMoving = movingMs >= 110 && movingMs <= 260;
  console.log(`${okMoving ? 'PASS' : 'FAIL'}  中途翻转窗口 → ${movingMs}ms（期望 120~240ms，翻转后重新计 3 拍）`);
  assert.ok(okMoving);

  // 场景 3：永远不会稳定的窗口（每拍都在变）→ 400ms 上限退出，不挂死
  const runaway = new Page();
  runaway.cw = 100;
  runaway.ch = 100;
  const tick = setInterval(() => { runaway.cw += 1; runaway.ch += 1; }, 25);
  t0 = Date.now();
  await runaway.waitForStableWindowSize();
  clearInterval(tick);
  const runawayMs = Date.now() - t0;
  const okRunaway = runawayMs >= 350 && runawayMs <= 800;
  console.log(`${okRunaway ? 'PASS' : 'FAIL'}  窗口持续变化 → ${runawayMs}ms（期望 400ms 上限附近，不挂死）`);
  assert.ok(okRunaway);

  console.log('\n全部通过：插值只在窗口尺寸稳定后起跑，同一姿态不再随机切换两种动画。');
})();
