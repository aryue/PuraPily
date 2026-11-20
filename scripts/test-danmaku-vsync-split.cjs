// 弹幕「一卡一卡」+「横屏分栏调节大小时整层闪烁」回归
//   ───────────────────────────────────────────────────────────────────────────
//   现象一：滚动弹幕一顿一顿（视频本身流畅）。
//   根因：渲染循环是 `setTimeout(16)` 自调度链。
//     ① setTimeout 只保证「不早于」，主线程忙时被推后，推送间隔在 16~30ms 之间抖；
//     ② 16ms ≈ 62.5Hz，与 120Hz 屏的 8.33ms 帧**不同步** —— 每次推送要等 1~2 个显示帧
//        才上屏，节奏忽快忽慢。屏幕上就是「一卡一卡」。
//   修法：displaySync 帧驱动（与屏幕刷新对齐），显式声明 60/120/120；位置推进仍按真实 dt。
//        displaySync 不可用时退回原定时器链，行为与改造前一致（不能因为一个 API 失败就不动）。
//
//   现象二：横屏拖分发线调分栏大小时弹幕整层闪。
//   根因：横屏非全屏的 `ovDanmakuCW()` = 分栏视口宽，拖动时**逐帧变**；Canvas 元素尺寸
//        跟着逐帧变 ⇒ ArkUI 每帧重建 canvas surface（内容被清空）⇒ 整层闪。
//   修法（不是冻结尺寸）：把"画布像素尺寸"和"逻辑视口"彻底解耦
//     · 画布像素尺寸 = 窗口宽（常量，`dmSurfaceW`）→ 拖动期间 surface 零重建；
//     · 可见区域 = 实时视口（弹幕层 `.clip(true)` + 左上对齐）；
//     · 几何口径 = 实时视口（`canvasWidth` → `setViewport`）→ 新弹幕仍从**画面**右缘进场；
//     · 清屏按画布像素（`DanmakuRenderer.setSurfaceSize`）→ 视口拖宽不会闪出上一帧的残影。
//   ⚠️ 曾经的错误修法是"拖动起点冻结画布尺寸、松手解冻"：弹幕会先在画面外空走 1~2 秒，
//      而且分栏比例写回后忘了解冻就留下错尺寸。这里断言代码里**不存在**那套状态。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.join(__dirname, '..');
const etsRoot = path.join(root, 'entry/src/main/ets');
// 统一成 LF：断言里有 \n，Windows 工作区源码是 CRLF
const read = (rel) => fs.readFileSync(path.join(etsRoot, rel), 'utf8').replace(/\r\n/g, '\n');
const controllerSrc = read('services/DanmakuController.ets');
const rendererSrc = read('services/DanmakuRenderer.ets');
const viewSrc = read('components/DanmakuView.ets');
const pageSrc = read('pages/VideoPlayerPage.ets');
const layerSrc = read('components/PlaybackDanmakuLayer.ets');

// ═══════════════════════════════════════════════════════════════════════════
// 1) 帧驱动：displaySync 取代 setTimeout(16)
// ═══════════════════════════════════════════════════════════════════════════

// 假 displaySync：记录 create/start/stop 次数与声明过的帧率范围，并保留 frame 回调
const syncs = [];
let failCreate = false;
function fakeSync() {
  const s = {
    range: null,
    cb: null,
    running: false,
    setExpectedFrameRateRange(r) { s.range = r; },
    on(evt, cb) { if (evt === 'frame') s.cb = cb; },
    off(evt, cb) { if (evt === 'frame' && s.cb === cb) s.cb = null; },
    start() { s.running = true; },
    stop() { s.running = false; },
  };
  syncs.push(s);
  return s;
}

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
    AppStorage: { setOrCreate() {}, get() { return undefined } },
    setTimeout, clearTimeout,
    require: (name) => {
      if (name.includes('Logger')) return { logInfo() {}, logWarn() {}, logError() {} };
      if (name === '@ohos.graphics.displaySync') {
        return {
          __esModule: true,
          default: {
            create: () => {
              if (failCreate) throw new Error('displaySync unavailable');
              return fakeSync();
            }
          }
        };
      }
      // 服务层依赖的系统 kit：只给构造期用得上的最小桩（DanmakuService 构造会 createHttp）
      if (name === '@kit.NetworkKit') return { http: { createHttp: () => ({}) }, webSocket: {} };
      if (name === '@kit.ArkTS') return { util: {} };
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(relative), name));
      if (fs.existsSync(path.join(etsRoot, target + '.ets'))) return load(target);
      return {};
    }
  }, { filename: file });
  modules.set(relative, output.exports);
  return output.exports;
}

const { DanmakuConfig } = load('model/DanmakuItem');
const { DanmakuController } = load('services/DanmakuController');

// render 是纯绘制入口：这里替换成计数器，只验证"帧驱动有没有按帧调到它"
function makeController() {
  const c = new DanmakuController(new DanmakuConfig());
  c.visibleDanmaku = [];
  c.renders = 0;
  c.render = () => { c.renders++; };
  return c;
}

// 1a) 启动 → 用 displaySync 驱动，且必须显式声明 120Hz（不声明系统按 60Hz 给回调）
const c1 = makeController();
c1.startRendering();
assert.equal(syncs.length, 1, 'startRendering 必须创建 displaySync 驱动');
const s1 = syncs[0];
assert.equal(s1.range.min, 60, '帧率范围下限 60');
assert.equal(s1.range.max, 120, '帧率范围上限 120');
assert.equal(s1.range.expected, 120,
  '帧率范围只允许 60/120/120：设备 120Hz，不声明就是每 2 帧一跳');
assert.equal(s1.running, true, 'startRendering 必须真正 start');
assert.equal(typeof s1.cb, 'function', 'frame 回调必须挂上');
assert.equal(c1.renderTimer, 0, '走 vsync 时不能再挂定时器，否则两条链同时推进弹幕（速度翻倍）');

// 1b) 有可见弹幕：每个 frame 回调都推进并重绘一次（不再按 16ms 定时器）
c1.visibleDanmaku = [{}];
s1.cb({});
s1.cb({});
assert.equal(c1.renders, 2, '每个 vsync 帧都要推进一次：120Hz 下就是 8.33ms 一帧');

// 1c) 空闲（屏上一条都没有）：250ms 节流，不每帧扫分桶/重绘
c1.visibleDanmaku = [];
const beforeIdle = c1.renders;
s1.cb({});
assert.equal(c1.renders, beforeIdle + 1, '空闲首帧要扫一次（恢复播放时不用等 250ms）');
s1.cb({});
s1.cb({});
assert.equal(c1.renders, beforeIdle + 1, '250ms 内的后续帧必须跳过（省电：不扫分桶、不清画布）');
c1.nextIdleScanAt = 0;                       // 模拟 250ms 过去
s1.cb({});
assert.equal(c1.renders, beforeIdle + 2, '节流窗口过后要重新扫描');

// 1d) 停止 → 必须真的 stop，且停后帧回调不再画（保留最后一帧，不清画布）
c1.stopRendering();
assert.equal(s1.running, false, 'stopRendering 必须停掉 vsync 驱动');
const afterStop = c1.renders;
s1.cb({});
assert.equal(c1.renders, afterStop, '已停止的驱动不能再推进弹幕');

// 1e) 恢复 → 复用同一个 DisplaySync 对象（不重复 create，也不重复挂回调）
c1.startRendering();
assert.equal(syncs.length, 1, '恢复播放复用同一个 DisplaySync（重复 create 会留下多条回调链）');
assert.equal(s1.running, true);
c1.stopRendering();

// 1f) displaySync 不可用 → 退回定时器链（老 SDK / 极端情况不能让弹幕彻底不动）
failCreate = true;
const c2 = makeController();
c2.startRendering();
assert.equal(c2.frameSyncUnavailable, true, 'create 抛错要标记为不可用，避免每次 start 都重试');
assert.notEqual(c2.renderTimer, 0, '不可用时必须退回 setTimeout 自调度链');
c2.visibleDanmaku = [{}, {}];
c2.render = () => { c2.renders++; };
c2.stopRendering();                          // 收尾：清掉定时器，否则测试进程会被自调度链挂住
assert.equal(c2.renderTimer, 0);
failCreate = false;

// 1g) 结构约束：destroy 必须摘掉 frame 回调（否则控制器连同整份弹幕数据被回调引用住）
assert.match(controllerSrc, /import displaySync from '@ohos\.graphics\.displaySync'/,
  '渲染驱动必须走 @ohos.graphics.displaySync');
assert.match(controllerSrc, /frameSync\s*\.off\('frame', this\.onFrameTick\)/,
  'destroy 必须 off 掉 frame 回调');
assert.doesNotMatch(controllerSrc, /this\.renderTimer = setTimeout\(\(\) => \{\s*this\.render\(\)/,
  '主渲染链不能再由 setTimeout 直接驱动');

// ═══════════════════════════════════════════════════════════════════════════
// 2) 横屏分栏拖动：画布像素尺寸与逻辑视口解耦（不是冻结）
// ═══════════════════════════════════════════════════════════════════════════

// 抽取弹幕几何方法（ovDanmakuCW → 首次 build 前的估算），和 test-feed-danmaku-fullscreen 同口径
const start = pageSrc.indexOf('  private ovDanmakuCW(');
const end = pageSrc.indexOf('  /** ⭐ 首次 build 前同步估算常驻层矩形');
assert.ok(start > 0 && end > start, 'danmaku geometry methods must stay in place');
const geometry = pageSrc.slice(start, end);
const context = { exports: {} };
const viewport = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(etsRoot, 'utils/PlaybackViewport.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, viewport);
Object.assign(context, viewport.exports);
vm.runInNewContext(ts.transpileModule(`export class Page { ${geometry} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();

// 横屏非全屏：窗口 840vp，分栏视口 520vp（真机横屏口径：视口 = 窗口 × 比例）
let liveViewportWidth = 520;
Object.assign(page, {
  referenceLayout: true, isLs: true, fs: false, referenceFeed: false, isLightsOff: false,
  cw: 840, ch: 519,
  referenceLandscapeViewportWidth: () => liveViewportWidth,
  referenceLandscapeAreaHeight: () => 470,
  referenceLandscapeAreaTop: () => 0,
});

assert.equal(page.ovDanmakuCW(), 520, '逻辑视口宽 = 实时分栏宽度');
assert.equal(page.ovDanmakuCH(), 470, '逻辑视口高 = 安全区以下的可用高度');
assert.equal(page.dmSurfaceW(), 840, '画布像素宽 = 窗口宽（不是分栏宽度）');
assert.equal(page.dmSurfaceH(), 519, '画布像素高 = 窗口高（拖到全屏时可用高度会逐帧涨，跟着变就闪）');

// ⭐ 核心断言：拖动分隔线（视口宽逐帧变）时画布像素尺寸**一动不动**
for (const w of [520, 700, 812, 560, 300, 840]) {
  liveViewportWidth = w;
  assert.equal(page.ovDanmakuCW(), w, `逻辑视口必须跟手（${w}）`);
  assert.equal(page.dmSurfaceW(), 840, `画布像素宽不能跟手（${w}）—— 否则每帧重建 surface = 闪`);
  assert.equal(page.dmSurfaceH(), 519, '画布像素高同样不能跟手');
  assert.ok(page.dmSurfaceW() >= page.ovDanmakuCW(),
    `画布必须覆盖视口（视口 ${w}），否则右侧内容被裁`);
}

// 结构约束：不许再有"拖动起点冻结画布 / 松手解冻"那套状态
assert.doesNotMatch(pageSrc, /dmSplitSurfaceW|dmSplitSurfaceH|releaseDanmakuSurfaceFreeze/,
  '不允许回到"冻结画布尺寸"的修法（弹幕会先在画面外空走，且有解冻遗漏风险）');

// 挂载点：几何拿实时视口，像素尺寸拿 dmSurfaceW/H
assert.match(pageSrc, /canvasWidth: this\.ovDanmakuCW\(\),\s*\n\s*canvasHeight: this\.ovDanmakuCH\(\),/,
  'controller 几何必须拿实时视口（新弹幕从画面右缘进场）');
assert.match(pageSrc, /surfaceWidth: this\.shrinkAnimating[^\n]*: this\.dmSurfaceW\(\),\s*\n\s*surfaceHeight: this\.shrinkAnimating[^\n]*: this\.dmSurfaceH\(\),/,
  '弹幕层必须拿到画布像素尺寸（窗口宽，常量）；收缩动画期间沿用冻结值');

// 弹幕层：可见区域按实时视口裁 + 左上对齐（画布比层宽时必须左对齐，否则整体右移）
assert.match(layerSrc, /\.width\(this\.layerWidth\)\s*\n\s*\.height\(this\.layerHeight\)/,
  '可见区域仍按实时视口裁剪');
assert.match(layerSrc, /\.alignContent\(Alignment\.TopStart\)\s*\n\s*\.position\(\{ x: this\.layerX, y: this\.layerY \}\)\s*\n\s*\.clip\(true\)/,
  '画布比层宽时必须左上对齐：默认 Center 会让画布原点与画面左缘错位');
assert.doesNotMatch(layerSrc, /\.width\(this\.paintWidth\(\)\)/,
  'DanmakuView 尺寸不能再由"冻结的绘制宽"决定');

// DanmakuView：视口变化走 setViewport（不防抖、不重排）；像素尺寸变化才重排 + 补画
const viewChange = viewSrc.slice(viewSrc.indexOf('  private onCanvasSizeChange('),
  viewSrc.indexOf('   * ⭐ 画布像素尺寸变化'));
assert.match(viewChange, /this\.controller\.setViewport\(this\.canvasWidth, this\.canvasHeight, this\.isFullscreen\)/,
  '视口变化必须走 setViewport（只更新几何口径）');
assert.doesNotMatch(viewChange, /setTimeout|applyDisplaySettings/,
  '拖动分隔线每帧都触发，不能再走 100ms 防抖 + 全量重排（逐条 measureText = 卡顿）');
assert.doesNotMatch(viewSrc, /pendingCanvasWidth|canvasSizeDebounceTimer/, '尺寸防抖那套必须删掉');

const surfaceChange = viewSrc.slice(viewSrc.indexOf('  private onSurfaceSizeChange('),
  viewSrc.indexOf('   * ⭐ 轨道可用高度变化'));
assert.match(surfaceChange, /setSurfaceSize\(this\.surfaceW\(\), this\.surfaceH\(\)\)/,
  '画布像素尺寸必须下发给渲染器（清屏范围）');
assert.match(surfaceChange, /applyDisplaySettings\(w, h, this\.isFullscreen\)/,
  'surface 重建后必须重排 + 立刻补画一帧（否则暂停态永远空白）');

// ═══════════════════════════════════════════════════════════════════════════
// 3) 运行时：setViewport 只改几何口径，不重排屏上弹幕
// ═══════════════════════════════════════════════════════════════════════════
const c3 = makeController();
c3.setRenderContext({ width: 840, height: 519, measureText: () => ({ width: 10 }), clearRect() {} });
c3.setSurfaceSize(840, 519);
c3.setCanvasSize(520, 519, true);
assert.equal(c3.renderer.canvasWidth, 520, '渲染器几何口径 = 逻辑视口');
assert.equal(c3.renderer.clearWidth(), 840, '清屏范围 = 画布像素（否则视口拖宽会闪出残影）');
assert.equal(c3.trackManager.canvasWidth, 520, '轨道分配口径 = 逻辑视口（新弹幕从这里进场）');

let reflows = 0;
c3.reflowVisibleDanmaku = () => { reflows++; };
c3.visibleDanmaku = [];
c3.isPlaying = true;

// 拖动：视口宽逐帧变 → 几何跟手，但绝不重排（每帧 measureText 就是卡顿本身）
for (const w of [560, 640, 700, 760, 820]) {
  c3.setViewport(w, 519, true);
  assert.equal(c3.renderer.canvasWidth, w, `视口必须逐帧跟手（${w}）`);
  assert.equal(c3.trackManager.canvasWidth, w, `新弹幕进场位置必须跟手（${w}）`);
  assert.equal(c3.renderer.clearWidth(), 840, '画布像素纹丝不动');
}
assert.equal(reflows, 0, '宽度变化不得重排屏上弹幕');

// 高度变化导致行数变了 → 该重排还是要重排（否则被遮住的行继续吃弹幕）
c3.setViewport(820, 80, true);
assert.ok(reflows > 0, '行数变化必须重排（这条路径和轨道可用高度共用判据）');

// 暂停态：视口变化要补画一帧，静止弹幕才会按新视口重新居中
const c4 = makeController();
c4.setRenderContext({ width: 840, height: 519, measureText: () => ({ width: 10 }), clearRect() {} });
c4.setCanvasSize(520, 519, true);
let pausedRenders = 0;
c4.renderer.render = () => { pausedRenders++; };
c4.isPlaying = false;
c4.visibleDanmaku = [];
c4.setViewport(600, 519, true);
assert.ok(pausedRenders > 0, '暂停时视口变了必须补画一帧（渲染循环是停的）');

// 渲染器结构约束：几何用 canvasWidth（视口），清屏用 surface
assert.match(rendererSrc, /ctx\.clearRect\(0, 0, this\.clearWidth\(\), this\.clearHeight\(\)\)/,
  '清屏必须覆盖整块 surface');
assert.match(rendererSrc, /item\.x = \(this\.canvasWidth - item\.measuredWidth\) \/ 2/,
  '静止弹幕居中的口径必须是逻辑视口（用像素宽会偏出可见区）');

console.log('PASS: danmaku is vsync-driven at 120Hz; landscape split keeps the canvas surface at window width while the logical viewport (geometry) follows the divider live');
