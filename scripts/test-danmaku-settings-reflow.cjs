// 弹幕设置「改了不生效 / 10% 只有一行」回归
//   ───────────────────────────────────────────────────────────────────────────
//   现象一：拖动「显示区域 / 字体大小」后画面没反应，要等弹幕自己滚走（最长 14s）
//          才看到新设置；暂停时调整更是完全没变化。
//   根因：`applyDisplaySettings` 只重算了轨道几何，**屏上已有弹幕仍带旧字号/旧 y**；
//        而且 `updateGeometry` 在"行数没变"时直接 return（28→26 号字常见同一行数），
//        连 trackHeight 都不落到后续分配；暂停时渲染链是停的，也没有任何一次重绘。
//   现象二：显示区域 10% 只有一行。
//   根因：行数是 `floor(画布高 × 区域 ÷ 轨道高)`，轨道高 = 字号 × 1.2（28 号字 = 34vp）。
//        291vp 画布 × 10% = 29vp < 34vp → 0 行 → 代码兜底 1 行。不是 bug，是几何。
//   本脚本锁死：行数换算、行数不变时仍更新行高、屏上弹幕重排（字号/宽度/基线/越界退场）、
//              暂停时也重绘一帧。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.join(__dirname, '..');
const etsRoot = path.join(root, 'entry/src/main/ets');
const controllerSrc = fs.readFileSync(path.join(etsRoot, 'services/DanmakuController.ets'), 'utf8');
const trackSrc = fs.readFileSync(path.join(etsRoot, 'services/DanmakuTrackManager.ets'), 'utf8');
const panelSrc = fs.readFileSync(path.join(etsRoot, 'components/ReferenceDanmakuSettings.ets'), 'utf8');

const storage = new Map();
const AppStorage = {
  setOrCreate(key, value) { storage.set(key, value) },
  get(key) { return storage.get(key) },
};

const modules = new Map();
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const file = path.join(etsRoot, relative + '.ets');
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const output = { exports: {} };
  vm.runInNewContext(compiled, {
    exports: output.exports, module: output, console, AppStorage,
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

const { DanmakuConfig, DanmakuItem, DanmakuType } = load('model/DanmakuItem');
const { DanmakuTrackManager } = load('services/DanmakuTrackManager');
const { DanmakuController } = load('services/DanmakuController');

// ── 1) 行数与行高换算：与面板 label / 文档口径完全一致 ─────────────────────
const config = new DanmakuConfig();
const tm = new DanmakuTrackManager(config);
tm.initialize(320, 291);   // 320×291：宽高比 < 1.4，不触发横屏放大（纯字号口径）
assert.equal(tm.currentTrackHeight, 34, '28 号字 × 行高 1.2 = 34vp');
assert.equal(tm.trackRows, 7, '291 × 0.9 ÷ 34 = 7 行（默认显示区域 90%）');

config.displayArea = 0.1;
tm.updateGeometry(320, 291);
assert.equal(tm.trackRows, 1, '10% = 29vp < 34vp 一行轨道 → 兜底 1 行（这就是"为什么只有一行"）');

config.displayArea = 0.25;
tm.updateGeometry(320, 291);
assert.equal(tm.trackRows, 2, '25% = 72vp ÷ 34 = 2 行');

config.displayArea = 1;
tm.updateGeometry(320, 291);
assert.equal(tm.trackRows, 8, '100% = 291 ÷ 34 = 8 行');

// 大画布（连刷整屏）10% 可以放下 2 行 —— 行数取决于"画布高 × 区域"，不是固定的 1 行
tm.updateGeometry(600, 800);
assert.equal(tm.trackRows, 23, '800vp 画布 100% → 23 行');
config.displayArea = 0.1;
tm.updateGeometry(600, 800);
assert.equal(tm.trackRows, 2, '800vp 画布 10% → 2 行');

// ── 2) 行数不变时也必须更新轨道高（旧实现这里直接 return） ─────────────────
config.displayArea = 0.9;
config.fontSize = 28;
tm.updateGeometry(320, 340);          // 340 × 0.9 = 306；306 ÷ 34 = 9
assert.equal(tm.trackRows, 9);
assert.equal(tm.currentTrackHeight, 34);
config.fontSize = 26;
tm.updateGeometry(320, 340);          // 306 ÷ 31 = 9 —— 行数相同
assert.equal(tm.trackRows, 9, '字号 28→26 在 340vp 画布上仍是 9 行');
assert.equal(tm.currentTrackHeight, 31, '行数没变也要把行高从 34 换成 31');

// ── 3) applyDisplaySettings 必须重排屏上弹幕（而不是只重算轨道池） ─────────
config.fontSize = 28;
config.displayArea = 0.5;
const renders = [];
const renderer = {
  setSize() {},
  updateConfig() {},
  measureWidth(text, fontSize) { return text.length * fontSize },   // 确定性替身
  render(items, currentTime, dt) { renders.push({ count: items.length, dt, currentTime }) },
};
const controller = Object.create(DanmakuController.prototype);
controller.config = config;
controller.trackManager = tm;
controller.filter = { updateConfig() {} };
controller.renderer = renderer;
controller.currentTime = 5000;
controller.canvasWidth = 320;
controller.canvasHeight = 291;
controller.visibleDanmaku = [];
controller.stats = { displayedCount: 0 };

function makeItem(track, type = DanmakuType.ROLL, text = '测试') {
  const item = new DanmakuItem({ content: text, time: 1000, type });
  item.track = track;
  item.x = 200;
  item.y = -1;
  item.width = 0;
  item.widthFontSize = 0;
  item.shownAt = 1000;
  return item;
}

const track0 = makeItem(0);
const track3 = makeItem(3);
const track9 = makeItem(9);          // 新区域装不下（rows=4）
const pending = makeItem(-1);        // 尚未上屏
controller.visibleDanmaku = [track0, track3, track9, pending];

controller.applyDisplaySettings(320, 291);   // 区域 50% → floor(145.5/34) = 4 行

assert.equal(tm.trackRows, 4);
assert.equal(controller.visibleDanmaku.length, 3, '越界轨道上的弹幕必须退场');
assert.equal(controller.visibleDanmaku.includes(track9), false);
assert.equal(track9.track, -1, '退场项要复位 track，下一次才不会画到区域外');
assert.equal(track9.missed, true, '退场项标 missed，不再事后补位');
assert.equal(track0.y, 4 + 0 * 34 + 34 * 0.8, '第 1 行基线 = 4 + 0.8 × 行高');
assert.equal(track3.y, 4 + 3 * 34 + 34 * 0.8, '第 4 行基线 = 4 + 3 × 行高 + 0.8 × 行高');
assert.equal(track0.fontSize, 28);
assert.equal(track0.width, 2 * 28, '重排时按新字号重新量宽');
assert.equal(track0.widthFontSize, 28);
assert.equal(track0.height, 34);
assert.equal(pending.track, -1, '未上屏的项原样留给下一帧分配');
assert.ok(renders.length >= 1, '设置应用后必须重绘');
assert.equal(renders[renders.length - 1].dt, 0, '暂停时也要重画：dt=0，只重绘不推进位置');
assert.equal(storage.get('danmakuTrackRows'), 4);
assert.equal(storage.get('danmakuTrackHeight'), 34);
assert.equal(storage.get('danmakuCanvasHeight'), 291);

// ── 4) 改字号：屏上弹幕字号 / 宽度 / 基线一起变（不需要等它滚走） ───────────
config.displayArea = 1;
config.fontSize = 40;
track0.track = 0;
track3.track = 3;
controller.visibleDanmaku = [track0, track3];
controller.applyDisplaySettings(320, 291);   // 行高 48，行数 floor(291/48) = 6

assert.equal(tm.trackRows, 6);
assert.equal(tm.currentTrackHeight, 48);
assert.equal(track0.fontSize, 40, '屏上已有弹幕也要立刻换成新字号');
assert.equal(track0.width, 2 * 40, '宽度按新字号重测');
assert.equal(track0.widthFontSize, 40);
assert.equal(track0.y, 4 + 0.8 * 48);
assert.equal(track3.y, 4 + 3 * 48 + 0.8 * 48);

// ── 5) 底部静止弹幕按同一套网格自下而上排 ──────────────────────────────────
const bottom = makeItem(0, DanmakuType.BOTTOM, '底部');
controller.visibleDanmaku = [bottom];
controller.applyDisplaySettings(320, 291);
const bottomRow = tm.trackRows - 1;   // idx = trackRows-1-track
assert.equal(bottom.y, 4 + bottomRow * 48 + 48 * 0.8, '底部弹幕贴显示区最后一行');

// ── 6) 全屏放大只认显式标志，不认画布宽高比 ────────────────────────────────
//   回归：竖屏播放页的视频区本身是 16:9（440×247.5，比例 1.78），旧实现用
//   `width > height * 1.4` 判定"横屏"，于是竖屏也被放大 1.2 倍 ——「字体大小 100%」
//   在竖屏变成 34 号字（行高 41、只剩 6 行），在连刷整屏却是 28 号（行高 34）。
{
  const c2 = new DanmakuConfig();
  const t2 = new DanmakuTrackManager(c2);

  t2.initialize(440, 247.5);                       // 竖屏 16:9 视频区，非全屏
  assert.equal(t2.currentFontSize, 28, '竖屏 16:9 不得被当成横屏放大（100% = 28 号字）');
  assert.equal(t2.currentTrackHeight, 34);
  assert.equal(t2.trackRows, 6, '247.5 × 0.9 ÷ 34 = 6 行');

  t2.setFullscreen(true);
  t2.initialize(744, 440);                         // 横屏全屏
  assert.equal(t2.currentFontSize, 34, '真·全屏/横屏才放大 1.2 倍（28 → 34）');
  assert.equal(t2.currentTrackHeight, 41);

  t2.setFullscreen(true);
  t2.initialize(440, 744);                         // 横屏里的竖视频（画布反而更高）
  assert.equal(t2.currentFontSize, 28, '全屏但画布竖长时不得放大（避免竖视频被放大）');

  // 运行时改设置也必须沿用同一口径（updateGeometry 与 initialize 同源）
  t2.setFullscreen(false);
  t2.updateGeometry(440, 247.5);
  assert.equal(t2.currentFontSize, 28, 'updateGeometry 与 initialize 必须同口径');
}

// ── 7) 竖屏半屏上推面板：轨道可用高度跟手，画布尺寸一动不动 ────────────────
//   旧实现只靠常驻层 `.clip(true)` 裁：11 行里被遮住的 4 行照样吃弹幕，那几行永远看不见
//   （用户看到的是「弹幕从已遮挡区域冒出来」）。画布又不能跟着逐帧缩 —— 那会每帧重建
//   surface + 防抖后再 initialize 清空轨道池 = 满屏叠字。所以拆成「画布高恒定 / 可用高度跟手」。
{
  const c3 = new DanmakuConfig();
  c3.displayArea = 1;
  const t3 = new DanmakuTrackManager(c3);
  t3.initialize(440, 386.9);                    // 竖片静止态：440×386.9
  assert.equal(t3.trackRows, 11, '386.9 ÷ 34 = 11 行');

  const painted = [];
  const r3 = {
    setSize() {}, updateConfig() {},
    measureWidth(text, fontSize) { return text.length * fontSize },
    render(items) { painted.push(items.length) },
  };
  const ctl = Object.create(DanmakuController.prototype);
  ctl.config = c3;
  ctl.trackManager = t3;
  ctl.filter = { updateConfig() {} };
  ctl.renderer = r3;
  ctl.currentTime = 1000;
  ctl.canvasWidth = 440;
  ctl.canvasHeight = 386.9;
  ctl.visibleDanmaku = [];
  ctl.stats = { displayedCount: 0 };
  ctl.trackAreaHeight = 0;

  ctl.setTrackAreaHeight(247.5);                // 详情面板上推 → 可见区域 247.5
  assert.equal(t3.trackRows, 7, '247.5 ÷ 34 = 7 行（只剩可见区域）');
  assert.equal(ctl.canvasHeight, 386.9, '画布高不得改变：改了就是逐帧重建 surface');
  assert.equal(storage.get('danmakuCanvasHeight'), 247.5, '面板行数预览必须按可用高度算');
  assert.equal(storage.get('danmakuTrackRows'), 7);

  // 拖动过程中高度逐帧变但没跨行边界 → 不得重排/重绘（否则每帧 measureText + 一次重绘）
  const before = painted.length;
  ctl.setTrackAreaHeight(240);
  assert.equal(painted.length, before, '行数没变时不得重排重绘');

  ctl.setTrackAreaHeight(0);                    // 复位（面板回弹）
  assert.equal(t3.trackRows, 11, '复位后回到整块画布行数');
  assert.equal(storage.get('danmakuCanvasHeight'), 386.9);

  ctl.setTrackAreaHeight(500);                  // 下拉超过画布高（正滑向连刷）
  assert.equal(t3.trackRows, 11, '可用高度必须夹到画布高，不能越出 canvas');
  assert.equal(ctl.canvasHeight, 386.9);
}

// ── 8) 接入点守护 ─────────────────────────────────────────────────────────
assert.ok(/reflowVisibleDanmaku\(\)/.test(controllerSrc), 'applyDisplaySettings 必须调用重排');
assert.ok(/this\.renderer\.render\(kept, this\.currentTime, 0\)/.test(controllerSrc),
  '重排后必须以 dt=0 重绘一帧（暂停时唯一能看到设置的途径）');
assert.ok(!/if \(trackCount === this\.trackCount\) \{\s*return/.test(trackSrc),
  'updateGeometry 不能再"行数没变就 return"');
assert.ok(/trackBaselineY\(/.test(trackSrc), 'TrackManager 要公开基线换算给控制器');
assert.ok(/labelWidth: 76/.test(panelSrc), '面板要能给"10% · 1行"留出宽度');
assert.ok(/danmakuTrackHeight/.test(panelSrc), '面板按真实行高预览行数');

console.log('PASS: danmaku display settings reflow on-screen items (rows = floor(H×area/trackHeight), 10% = 1 row on 291vp canvas)');
