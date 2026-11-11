const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// ── 1) 预热接管必须主动回灌画幅 ───────────────────────────────────────────
// 池实例在 prepare 阶段就把 videoSizeChange 发完了（ff_ffplay.c：prepared 前用
// codecpar 一次、videothread 首帧 alloc 再一次），take() 时监听被 detach，
// 页面 setupL 注册时收不到 —— 不回灌就永久停在默认 16:9。
const ijkWarmAt = source.indexOf('if (ijkWarm !== null) {');
assert.ok(ijkWarmAt > 0, 'IJK warm-adopt branch must stay');
const ijkWarmBlock = source.slice(ijkWarmAt, source.indexOf("PlaybackStartup.setPath('ijk-warm')"));
assert.match(ijkWarmBlock, /this\.adoptWarmAspect\(player, ijkWarm\.aspectRatio\)/,
  'IJK warm takeover must feed the pooled aspect ratio back into ar');
const rebindAt = ijkWarmBlock.indexOf('player.surfaceId = warmSurface');
const feedAt = ijkWarmBlock.indexOf('this.adoptWarmAspect(');
assert.ok(rebindAt > 0 && feedAt > rebindAt, 'aspect must be adopted after the surface handoff');

// AVPlayer 预热（PlaybackWarmPlayer）走的是同一类坑，prepared 后 width/height 可用。
const adoptWarmAt = source.indexOf('private async adoptWarmPlayback(');
const adoptWarmBlock = source.slice(adoptWarmAt, source.indexOf('private async applyPreparedState('));
assert.match(adoptWarmBlock, /this\.adoptWarmAspect\(player, 0\)/,
  'AVPlayer warm takeover must adopt player.width/height too');

// ── 2) prepared 收尾与 setupL 都要补一次尺寸快照 ─────────────────────────
const preparedAt = source.indexOf('private async applyPreparedState(');
assert.ok(preparedAt > 0);
const preparedHead = source.slice(preparedAt, preparedAt + 420);
assert.ok(preparedHead.indexOf('this.syncAspectFromPlayer(player)') > 0,
  'applyPreparedState must snapshot the prepared player size before first-frame bookkeeping');

const sizeListenerAt = source.indexOf("this.av.on('videoSizeChange'");
const setupLAt = source.indexOf('private setupL()');
const setupEnd = source.indexOf('private preparingPlayer_');
assert.ok(sizeListenerAt > setupLAt && setupEnd > sizeListenerAt);
const setupTail = source.slice(sizeListenerAt, setupEnd);
assert.ok(setupTail.indexOf('this.syncAspectFromPlayer(player)') > 0,
  'setupL must snapshot the current size after registering videoSizeChange');

// ── 3) 详情尺寸不能被 waitingForFirstFrame 永久挡掉 ────────────────────────
// 预热命中后几百毫秒就置 false，详情稍晚返回会被丢弃 —— 这是 16:9 卡死的另一半成因。
const applyDetailAt = source.indexOf('private applyDetailDimension(');
const applyDetailBlock = source.slice(applyDetailAt, source.indexOf('private setAspectFromMeta('));
assert.ok(!/dimension\.height <= 0 \|\| !this\.waitingForFirstFrame/.test(applyDetailBlock),
  'detail dimensions must not be gated by the first-frame flag');
assert.match(applyDetailBlock, /if \(this\.referenceFeed && !this\.waitingForFirstFrame\) return;/,
  'feed mode keeps its still/committedRatio ownership after the first frame');

// ── 4) 运行期语义 ────────────────────────────────────────────────────────
const methods = source.slice(applyDetailAt, source.indexOf('  // 半屏控件按播放模式选择'));
assert.ok(methods.length > 0);

const context = { exports: {}, logInfo: () => {} };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

function makePage(overrides) {
  const page = new context.exports.Page();
  Object.assign(page, {
    ar: 16 / 9,
    arFromMeta_: false,
    arMetaCid_: 0,
    referenceFeed: false,
    waitingForFirstFrame: true,
    vi: { cid: 100 },
    geometryUpdates: 0,
    updateIsLandscapeVertical() {},
    updateLSVSize() {},
    updateVideoSize() { this.geometryUpdates++; },
  }, overrides || {});
  return page;
}

// setAspectFromMeta：写入显示尺寸并打标；同值不重复刷几何。
let page = makePage();
assert.equal(page.setAspectFromMeta(9 / 16, 100), true);
assert.equal(page.ar, 9 / 16);
assert.equal(page.arFromMeta_, true);
assert.equal(page.arMetaCid_, 100);
assert.equal(page.setAspectFromMeta(9 / 16, 100), false, 'same ratio must not trigger a second layout pass');

// decoderAspectIgnored：rotate 的倒数关系 + 取整误差都要拦住。
assert.equal(page.decoderAspectIgnored(16 / 9), true, 'rotate=90 reports the reciprocal: keep the display ratio');
assert.equal(page.decoderAspectIgnored(9 / 16), true, 'same ratio is a no-op');
assert.equal(page.decoderAspectIgnored(9 / 16 + 0.005), true, 'codec padding noise must not relayout');
assert.equal(page.decoderAspectIgnored(0.75), false, 'a genuinely different frame must be able to correct ar');
page.vi.cid = 200;
assert.equal(page.decoderAspectIgnored(16 / 9), false, 'meta from the previous cid is stale and must not block');

// adoptWarmAspect：播放器尺寸优先；meta 是显示尺寸时不被编码尺寸覆盖。
page = makePage();
page.adoptWarmAspect({ width: 1080, height: 1920 }, 1);
assert.ok(Math.abs(page.ar - 9 / 16) < 1e-6, 'no metadata: pooled player size must set the ratio');
assert.equal(page.geometryUpdates, 1, 'adoption must relayout the surface');

page = makePage();
page.setAspectFromMeta(9 / 16, 100);
page.adoptWarmAspect({ width: 1920, height: 1080 }, 16 / 9);
assert.ok(Math.abs(page.ar - 9 / 16) < 1e-6, 'meta display ratio must survive a rotate-encoded player size');

// 会话实测值可用；初始值 1（正方形占位）必须当作"未知"。
page = makePage();
page.adoptWarmAspect({ width: 0, height: 0 }, 0.5625);
assert.ok(Math.abs(page.ar - 9 / 16) < 1e-6, 'measured session ratio is the fallback when player size is missing');
page = makePage();
page.adoptWarmAspect({ width: 0, height: 0 }, 1);
assert.ok(Math.abs(page.ar - 16 / 9) < 1e-6, 'the 1.0 placeholder must never be adopted as a square video');

// syncAspectFromPlayer：连刷自己管画幅，不能插手。
page = makePage({ referenceFeed: true });
page.syncAspectFromPlayer({ width: 1080, height: 1920 });
assert.ok(Math.abs(page.ar - 16 / 9) < 1e-6, 'feed mode owns its aspect ratio');

page = makePage();
page.syncAspectFromPlayer(null);
page.syncAspectFromPlayer({ width: 0, height: 0 });
assert.ok(Math.abs(page.ar - 16 / 9) < 1e-6, 'missing player size must be a no-op');

page = makePage();
page.setAspectFromMeta(9 / 16, 99);
page.vi.cid = 100;
page.syncAspectFromPlayer({ width: 1920, height: 1080 });
assert.ok(page.ar > 1, 'meta from the previous cid must not block the new source');

page = makePage();
page.syncAspectFromPlayer({ width: 1080, height: 1920 });
assert.ok(Math.abs(page.ar - 9 / 16) < 1e-6, 'cold path without metadata still recovers the ratio');

console.log('PASS: warm takeover adopts the pooled aspect ratio, prepared/setupL snapshot the player size, '
  + 'late detail dimensions are no longer gated by the first-frame flag, rotate-recoded sources keep the display ratio');
