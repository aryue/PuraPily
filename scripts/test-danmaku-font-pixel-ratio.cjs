// 弹幕「字特别小、行距特别宽、首行下面一片空白」回归：Canvas font 的 px 单位标定
//   ───────────────────────────────────────────────────────────────────────────
//   现象（真机/模拟器实测）：设置面板显示 22 号字、轨道高 26vp，屏幕上量到的字只有 7vp
//   高（单字宽 7.3 = 22 ÷ 3），于是行与行之间空得能塞下三条弹幕，第一行下面也一片空白。
//
//   根因：ArkUI Canvas 的 `ctx.font` 字符串里 **`px` 是设备像素**，而画布坐标
//   （fillText 的 x/y、lineWidth、measureText 的返回值）都是 **vp** —— 差一个屏幕密度。
//   于是"量出来的宽度"和"画出来的样子"都缩小到 1/密度，两者自洽，只有跟轨道高对比才露馅。
//
//   修法：拿到渲染上下文时用 `100px` 量一个全角汉字（CJK 恒为 1em）实测标定比例，
//        拼字体串时把 vp 字号乘回设备像素。本脚本锁定：标定值、字体串、测量宽度三者一致。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const etsRoot = path.join(__dirname, '..', 'entry/src/main/ets');

const modules = new Map();
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const file = path.join(etsRoot, relative + '.ets');
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const output = { exports: {} };
  vm.runInNewContext(compiled, {
    exports: output.exports, module: output, console,
    require: (name) => {
      if (name.includes('Logger')) return { logInfo() {}, logWarn() {}, logError() {} };
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(relative), name));
      if (target === 'model/DanmakuItem') return load(target);
      return {};
    }
  }, { filename: file });
  modules.set(relative, output.exports);
  return output.exports;
}

const { DanmakuConfig } = load('model/DanmakuItem');
const { DanmakuRenderer } = load('services/DanmakuRenderer');

/**
 * 假画布上下文。`perVp` 表示"font 的 1px 等于多少 vp"：
 *   perVp = 1 → 平台把 font 的 px 当 vp（正确语义，不需要补偿）
 *   perVp = 3 → 平台把 font 的 px 当设备像素（本项目真机实测的情形，需要 ×3）
 * measureText 永远返回 **vp**（与画布坐标系一致），这也是它掩盖 bug 的原因。
 */
class FakeContext {
  constructor(perVp) {
    this.perVp = perVp;
    this.fontPx = 14;
    this._font = 'normal normal 14px sans-serif';
    this.drawn = [];
  }
  set font(value) {
    this._font = value;
    const m = /(\d+(?:\.\d+)?)px/.exec(value);
    if (m) this.fontPx = parseFloat(m[1]);
  }
  get font() { return this._font; }
  measureText(text) { return { width: this.fontPx * text.length / this.perVp }; }
  clearRect() {}
  fillText(text, x, y) { this.drawn.push({ text, x, y, fontPx: this.fontPx }); }
  strokeText() {}
}

// ── 1) 设备像素语义（perVp = 3）：必须标定出 3，字体串 ×3，测量宽度回到 vp ──
{
  const ctx = new FakeContext(3);
  const renderer = new DanmakuRenderer(new DanmakuConfig());
  renderer.setContext(ctx);
  renderer.setSize(440, 247.5);

  assert.equal(renderer.getFontPixelRatio(), 3, '100px 量出 33.3vp → 标定比例应为 3');

  // 22 号字：真机上曾经只画出 7.3vp 的宽度（22 / 3），这就是"字特别小"的直接来源
  assert.equal(renderer.measureWidth('国', 22), 22,
    'measureText 结果必须回到 vp：22 号字 = 单字 22vp（回归前是 7.3）');
  assert.ok(Math.abs(renderer.measureWidth('测试文本', 22) - 88) < 0.01,
    '4 个全角字 = 4 × 22vp');

  // 真正画一条：字体串里必须是 66px（22vp × 3），而不是 22px
  renderer.render([{
    content: '国', x: 100, y: 50, width: 22, fontSize: 22, visible: true,
    dropped: false, track: 0, speed: 0, duration: 7000,
    type: 1, isScrolling: () => true, getColorString: () => '#FFFFFF'
  }], 0, 0);
  assert.ok(ctx.drawn.length === 1, '应画出一条弹幕');
  assert.equal(ctx.drawn[0].fontPx, 66, '绘制字号 = 22vp × 3 = 66 设备像素');
}

// ── 2) vp 语义（perVp = 1）：不得补偿，保持原样 ────────────────────────────
{
  const ctx = new FakeContext(1);
  const renderer = new DanmakuRenderer(new DanmakuConfig());
  renderer.setContext(ctx);
  renderer.setSize(440, 247.5);

  assert.equal(renderer.getFontPixelRatio(), 1, '100px 量出 100vp → 平台语义已正确，比例必须是 1');
  assert.equal(renderer.measureWidth('国', 22), 22, 'vp 语义下单字仍是 22vp');

  renderer.render([{
    content: '国', x: 100, y: 50, width: 22, fontSize: 22, visible: true,
    dropped: false, track: 0, speed: 0, duration: 7000,
    type: 1, isScrolling: () => true, getColorString: () => '#FFFFFF'
  }], 0, 0);
  assert.equal(ctx.drawn[0].fontPx, 22, 'vp 语义下不得放大字号');
}

// ── 3) 度量异常（返回 0 / 离谱比例）必须退回 1，绝不能让字撑爆轨道 ──────────
{
  const broken = new FakeContext(3);
  broken.measureText = () => ({ width: 0 });
  const r0 = new DanmakuRenderer(new DanmakuConfig());
  r0.setContext(broken);
  assert.equal(r0.getFontPixelRatio(), 1, '量不到宽度时按 1 处理（保持旧行为）');

  const absurd = new FakeContext(3);
  absurd.measureText = () => ({ width: 1 });   // 比例 100，离谱
  const r1 = new DanmakuRenderer(new DanmakuConfig());
  r1.setContext(absurd);
  assert.equal(r1.getFontPixelRatio(), 1, '比例超出 [1.25,4) 一律按 1 处理');
}

// ── 4) 换上下文必须重新标定并清缓存（旋转 / 画布重建） ──────────────────────
{
  const renderer = new DanmakuRenderer(new DanmakuConfig());
  renderer.setContext(new FakeContext(3));
  assert.equal(renderer.getFontPixelRatio(), 3);
  assert.equal(renderer.measureWidth('国', 22), 22);

  renderer.setContext(new FakeContext(1));
  assert.equal(renderer.getFontPixelRatio(), 1, '画布重建后按新上下文重新标定');
  assert.equal(renderer.measureWidth('国', 22), 22, '旧的宽度缓存必须已作废（否则会拿到按 66px 量的值）');
}

console.log('test-danmaku-font-pixel-ratio: PASS');
