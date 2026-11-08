/**
 * 深浅色对比度回归（2026-11-08）。
 *
 * 覆盖两处修复：
 * ① GlassMaterial 的 colorInvert 由「11 类全写死 true」恢复为按类别决策
 *    （只有 capsule 有 sys.color.font_primary 配套才开反色）；
 * ② 语义前景色三档在深/浅两套底板上都达到 WCAG AA 4.5:1，
 *    动态页与评论组件不再残留不随主题的固定中灰。
 *
 * 用实际 CompileArkTS 产物而非手写副本，保证测的就是线上配方。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const installGlassMaterial = require('./glass-material-test-stub.cjs');

const BUILD = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets';
const SRC = 'entry/src/main/ets';

function loadCompiled(relPath, ctx) {
  const file = path.join(BUILD, relPath);
  assert.ok(fs.existsSync(file), `缺少编译产物 ${file}，请先跑 assembleHap`);
  const source = fs.readFileSync(file, 'utf8').replace(/^import .*;\r?\n/gm, '');
  const saved = ctx.exports;
  ctx.exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, ctx);
  const out = ctx.exports;
  ctx.exports = saved;
  return out;
}

// ---- ① 反色口径 ----
const glassCtx = { exports: {}, Color: { Transparent: 0, White: '#FFFFFF' } };
installGlassMaterial(glassCtx);
const GlassMaterial = glassCtx.GlassMaterial;
assert.ok(GlassMaterial, 'GlassMaterial 工厂未装载');

const kinds = ['sheet', 'panel', 'menu', 'control', 'staticControl', 'capsule',
  'header', 'headerRegular', 'hint', 'touch', 'accent'];
assert.equal(kinds.length, 11, '配方类别数变化，请同步核对反色口径');
for (const kind of kinds) {
  // 深浅两套主题下口径必须一致：反色不随 dark 翻转，否则底板与硬编码前景再次错位。
  for (const dark of [false, true]) {
    const material = GlassMaterial.create(kind, dark);
    assert.equal(material.options.colorInvert, kind === 'capsule',
      `${kind} (dark=${dark}) 的 colorInvert 应为 ${kind === 'capsule'}`);
  }
}
// 染色仍按主题分叉，关掉反色不能把深浅外观一起丢掉。
for (const kind of ['panel', 'menu', 'header', 'control']) {
  const light = GlassMaterial.create(kind, false).options.materialColor;
  const dark = GlassMaterial.create(kind, true).options.materialColor;
  assert.notEqual(light, dark, `${kind} 的深浅染色必须分叉`);
}
// 自定义配方默认关闭反色，显式 inverted 仍可开启（保留扩展能力）。
assert.equal(GlassMaterial.createWithStyle({ style: 0 }).options.colorInvert, false);
assert.equal(GlassMaterial.createWithStyle({ style: 0, inverted: true }).options.colorInvert, true);
// 底栏是唯一有 sys.color.font_primary 配套前景的控件，反色必须保留。
assert.equal(GlassMaterial.invertedFor('capsule'), true);
assert.equal(GlassMaterial.invertedFor('control'), false);
assert.ok(!fs.readFileSync(path.join(SRC, 'utils/GlassMaterial.ets'), 'utf8').includes('INVERTED'),
  'GlassMaterial.ets 仍残留写死反色常量');

// ---- ② 语义前景色对比度 ----
const colors = loadCompiled('utils/SurfaceColors.ts', { exports: {} });
function luminance(hex) {
  const rgb = hex.replace('#', '').match(/../g).map((h) => parseInt(h, 16) / 255)
    .map((v) => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
  return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
}
function contrast(a, b) {
  const l1 = luminance(a), l2 = luminance(b);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}
const levels = ['primaryTextColor', 'secondaryTextColor', 'tertiaryTextColor'];
const darkBgs = ['#17181A', '#101114'];
const lightBgs = ['#FFFFFF', '#F1F2F4'];
for (const level of levels) {
  const darkFg = colors[level](true);
  const lightFg = colors[level](false);
  assert.notEqual(darkFg, lightFg, `${level} 必须随主题变化`);
  for (const bg of darkBgs) {
    assert.ok(contrast(darkFg, bg) >= 4.5,
      `${level} 深色 ${darkFg} 压 ${bg} 只有 ${contrast(darkFg, bg).toFixed(2)}:1`);
  }
  for (const bg of lightBgs) {
    assert.ok(contrast(lightFg, bg) >= 4.5,
      `${level} 浅色 ${lightFg} 压 ${bg} 只有 ${contrast(lightFg, bg).toFixed(2)}:1`);
  }
}
// 旧的固定中灰必须已淘汰：深色约 5.9:1、浅色白底仅约 2.8:1。
assert.ok(contrast('#9499A0', '#FFFFFF') < 4.5, '基线校验：旧中灰在白底上本就不达标');

// ---- ③ 源码里不再残留不随主题的固定中灰前景色 ----
const fixedGray = /'(#9499A0|#757A81|#858A92|#999999|#888888|#777777|#AAAAAA|#BBBBBB)'/;
const touched = [
  'pages/DynamicsPage.ets',
  'pages/DynamicDetailPage.ets',
  'components/DynamicCardBody.ets',
  'components/DynamicFeedActions.ets',
  'components/CommentItemComponent.ets',
  'components/CommentInputBar.ets',
  'components/CommentConversationPanel.ets',
  'components/CommentThreadPanel.ets'
];
for (const rel of touched) {
  const source = fs.readFileSync(path.join(SRC, rel), 'utf8');
  const offenders = source.split(/\r?\n/)
    .filter((line) => /(fontColor|fillColor)\(/.test(line) && fixedGray.test(line));
  assert.deepEqual(offenders, [], `${rel} 仍有固定中灰前景色:\n${offenders.join('\n')}`);
}
// 动态信息流操作栏必须自己接主题，不能靠调用方透传。
const actions = fs.readFileSync(path.join(SRC, 'components/DynamicFeedActions.ets'), 'utf8');
assert.ok(/@StorageLink\('isDarkMode'\)/.test(actions), 'DynamicFeedActions 未订阅主题');
assert.ok(/secondaryTextColor\(this\.isDarkMode\)/.test(actions), 'DynamicFeedActions 未使用语义色');

console.log(`PASS: 11 类反色口径（仅 capsule 开启）、深浅染色分叉、` +
  `3 档语义色 × 4 种底板均 >= 4.5:1、${touched.length} 个文件无固定中灰残留、操作栏已订阅主题。`);
