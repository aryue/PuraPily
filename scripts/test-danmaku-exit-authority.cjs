// 弹幕「没滚完就消失」回归
//   ───────────────────────────────────────────────────────────────────────────
//   现象：正常弹幕应当整条滚出屏幕；偶发情况下它会在屏幕中间（第一个字离左边界还很远）
//        就被整条抹掉。
//   根因：可见性判定的锚点是【播放时间窗口】而不是【位置】。
//     ① 候选窗口写死 `7000 / config.speed`（把墙钟口径当播放口径），倍速越高窗口越小；
//        面板「弹幕速度」可选 3000~14000ms，极慢档穿越要 14000ms，窗口只有 11000ms，
//        于是滚到 ~78% 就被丢出候选集 —— 连下面那句"按自己的生存期兜底"都执行不到。
//     ② 那条"生存期"本身也是错的：锚点用 `item.time`（视频里的打卡时间），而弹幕真正上屏
//        要等下一次时间回调（timeUpdate ~1Hz），等于每条都凭空少活几百毫秒。
//     ③ 右侧（x > canvasWidth）也被直接剔除，画布变窄后那条弹幕的 x 永久冻结、再也回不来。
//   修法：已上屏的滚动弹幕**只看位置**（尾巴越过左边界才算出去），
//        时间只留一个极宽松的兜底（≥60s 播放时间）用来清理真的卡死不动的幽灵项；
//        候选窗口按用户设置推导，并把上一轮仍在屏内的弹幕 carryOver 续命。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.join(__dirname, '..');
const controllerSrc = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/DanmakuController.ets'), 'utf8');
const trackSrc = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/DanmakuTrackManager.ets'), 'utf8');
const itemSrc = fs.readFileSync(path.join(root, 'entry/src/main/ets/model/DanmakuItem.ets'), 'utf8');

// ── 1) 纯函数区：直接切片执行（它们不依赖 this / import，可以单独跑）
const from = controllerSrc.indexOf('  static trailWindowMs(');
const to = controllerSrc.indexOf('  /** 滚动弹幕穿越时长');
assert.ok(from > 0 && to > from, 'pure visibility helpers must stay in one contiguous block');
const helperSrc = controllerSrc.slice(from, to);

const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class DanmakuController { ${helperSrc} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const DC = context.exports.DanmakuController;

// ── 2) 候选窗口必须跟着「弹幕速度」设置走，且不能随倍速缩小
assert.equal(DC.trailWindowMs(7000), 11000, '默认 7s 穿越 → 11s 窗口（下限）');
assert.equal(DC.trailWindowMs(3000), 11000, '极快档不能把窗口压到穿越时长以下');
assert.equal(DC.trailWindowMs(10000), 13000, '较慢档 10s → 13s');
assert.equal(DC.trailWindowMs(14000), 17000, '极慢档 14s 必须给到 17s（旧实现只有 11s → 78% 处被删）');
assert.equal(DC.trailWindowMs(25000), 28000);
assert.equal(DC.trailWindowMs(40000), 30000, '窗口封顶 30s，防止分桶扫描量失控');
assert.equal(DC.trailWindowMs(Number.NaN), 11000, '非法值退回默认 7s 口径');
assert.equal(DC.trailWindowMs(0), 11000);

// ── 3) 出屏判定：位置是唯一判据
const mk = (x, width, time, shownAt, track) => ({ x, width, time, shownAt, track });
const LIFE = 60000;

// 3a. 关键回归：屏幕上滚到一半（尾巴还在屏内）时，哪怕已经远超旧的 11s 窗口，也必须留着
const mid = mk(180, 260, 1000, 1000, 3);
assert.equal(DC.scrollingGone(mid, 1000 + 11000, LIFE), false, '旧 11s 窗口不能再把屏内弹幕删掉');
assert.equal(DC.scrollingGone(mid, 1000 + 40000, LIFE), false, '穿越慢（极慢档/倍速错配）也要滚完');
assert.equal(DC.scrollingGone(mid, 1000 + 60000, LIFE), false, '兜底期边界内仍保留');

// 3b. 时间兜底只负责清理"位置不再推进"的幽灵项
assert.equal(DC.scrollingGone(mk(180, 260, 1000, 1000, 3), 1000 + 60001, LIFE), true, '超过兜底期才回收');
assert.equal(DC.scrollingGone(mk(180, 260, 1000, 0, 3), 1000 + 60001, LIFE), true, 'shownAt 缺失时退回 time 也能量出兜底期');

// 3c. 真正出屏（尾巴越过左边界）→ 立刻回收，不受兜底期影响
assert.equal(DC.scrollingGone(mk(-260, 260, 1000, 1000, 3), 2000, LIFE), true, 'x+width===0 即已完全出屏');
assert.equal(DC.scrollingGone(mk(-100, 60, 1000, 1000, 3), 2000, LIFE), true);

// 3d. 右侧（画布变窄 / 刚分配）不能剔除，否则 x 会永久冻结
assert.equal(DC.scrollingGone(mk(900, 120, 1000, 1000, 3), 2000, LIFE), false, 'x > canvasWidth 时要继续滚进来');

// ── 4) 候选续命：窗口外的"仍在屏内"弹幕必须捞回来
const a = mk(300, 100, 1000, 1000, 1);      // 窗口外、在屏内、已上屏 → 留
const b = mk(-260, 100, 1000, 1000, 2);     // 窗口外、已出屏 → 丢
const c = mk(300, 100, 9000, 0, -1);        // 窗口外、未上屏 → 丢（交给注入窗口逻辑）
const d = mk(300, 100, 6000, 6000, 4);      // 窗口内 → 不参与续命（分桶会取到）
const carried = DC.carryOver([a, b, c, d], 5000);
// VM 里造出来的数组/对象原型与本上下文不同，用引用身份比较（carryOver 不做拷贝）
assert.equal(carried.length, 1, 'carryOver 只捞窗口外、仍在屏内、已上屏的项');
assert.equal(carried[0], a);
assert.equal(DC.carryOver([], 5000).length, 0);

// ── 5) 接入点：候选要拼上 carryOver，旧的时间窗口写法不能再回来
assert.ok(/DanmakuController\.carryOver\(this\.visibleDanmaku, minTime\)/.test(controllerSrc),
  'updateVisibleDanmaku must merge carried-over items into candidates');
assert.ok(/DanmakuController\.trailWindowMs\(this\.config\.scrollDuration\)/.test(controllerSrc),
  'candidate window must be derived from the user scroll-duration setting');
assert.ok(!/7000 \/ this\.config\.speed/.test(controllerSrc), 'old hard-coded window must be gone');
assert.ok(!/now > item\.time \+ Math\.max\(trailWindow, life\)/.test(controllerSrc),
  'assigned danmaku must not be pruned by a playback-time window any more');
assert.ok(/return !DanmakuController\.scrollingGone\(item, now, scrollLifeMs\)/.test(controllerSrc),
  'scroll branch must delegate to the position-authoritative helper');

// ── 6) 上屏时间锚点必须真正被写入（四个分配路径 + 模型字段）
assert.equal((trackSrc.match(/item\.shownAt = currentTime/g) || []).length, 4,
  'scroll / reverse / top / bottom 四条分配路径都要记录 shownAt');
assert.ok(/shownAt: number = 0/.test(itemSrc), 'DanmakuItem must expose the shownAt anchor');

console.log('PASS: danmaku exit is position-authoritative (window follows scrollDuration, carry-over keeps on-screen items, shownAt anchors the safety net)');
