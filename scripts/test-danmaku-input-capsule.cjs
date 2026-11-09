/**
 * 弹幕输入框与评论页输入胶囊对齐（2026-11-09）。
 *
 * 断言走实际 CompileArkTS 产物，改源码后必须先跑 assembleHap：
 * ① 编辑区是单层 40vp 全圆角 capsule 胶囊（与 FloatingCommentEntry 同款），
 *    不再是 36vp / cornerRadius:8 的内嵌圆角矩形；
 * ② 去掉 send_out 发送按钮，发送保留在键盘 EnterKeyType.Send / onSubmit；
 * ③ 弹幕样式「A」在 TextInput 之后（右侧），id 与设置面板不丢；
 * ④ 占位色改走评论页同款 color_player_text_secondary 资源；
 * ⑤ 其它播放布局的弹幕输入入口不再用 refractive:false 平涂底；
 * ⑥ 原生玻璃保留：宿主 NativeComposerSurface 只在「A」展开设置时挂载，收起态没有外框；
 * ⑦ 字号/位置选项走独立组件 + @Prop selected，@State 变化能刷新选中态。
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const BUILD = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets';
const SRC = 'entry/src/main/ets';

function compiled(rel) {
  const file = path.join(BUILD, rel + '.ts');
  assert.ok(fs.existsSync(file), `缺少编译产物 ${file}，请先跑 assembleHap`);
  return fs.readFileSync(file, 'utf8');
}
function source(rel) {
  return fs.readFileSync(path.join(SRC, rel + '.ets'), 'utf8');
}

// ---- ① 单层胶囊：40vp、无 cornerRadius，沿用 NativeGlassInput 的 capsule 材质 ----
const bar = compiled('components/DanmakuInputBar');
const barSrc = source('components/DanmakuInputBar');
assert.ok(/new NativeGlassInput\(this, \{\s*inputHeight: 40,\s*content:/.test(bar),
  'compiled danmaku editor must use a 40vp NativeGlassInput');
assert.ok(!/cornerRadius:\s*8/.test(bar), 'inner 8vp rounded rectangle must be gone');
assert.ok(!/inputHeight:\s*36/.test(bar), 'old 36vp input height must be gone');
assert.ok(/TextInput\.layoutWeight\(1\)/.test(bar) && /TextInput\.height\(40\)/.test(bar),
  'text input fills the capsule left side');
assert.ok(/TextInput\.padding\(\{ left: 14, right: 4 \}\)/.test(bar),
  'capsule keeps the comment entry 14vp leading inset');

// ---- ② 发送按钮移除，键盘发送链路保留 ----
assert.ok(!/send_out/.test(bar) && !/发送弹幕/.test(bar),
  'send button / accessibility label must be removed');
assert.ok(!/\.enabled\(!this\.sending && this\.text\.trim\(\)\.length > 0\)/.test(bar),
  'old send-button enable condition must be gone');
assert.ok(/TextInput\.enterKeyType\(EnterKeyType\.Send\)/.test(bar), 'keyboard Send key remains');
assert.ok(/TextInput\.onSubmit\(\(\) => \{ this\.send\(\); \}\)/.test(bar), 'Enter still submits the danmaku');
assert.ok(/private async send\(\)/.test(bar), 'send logic must survive the button removal');

// ---- ③ A 在右侧（TextInput 之后创建），id 与设置面板保留 ----
const inputAt = bar.indexOf("TextInput.create({ text: this.text, placeholder: '发个友善的弹幕见证当下' })");
const aAt = bar.indexOf("Text.create('A')", inputAt);
assert.ok(inputAt > 0 && aAt > inputAt, 'A must be created after the text input, i.e. on the right');
assert.ok(/Text\.id\('danmaku-style-toggle'\)/.test(bar), 'style toggle id retained for uitest');
assert.ok(/TextInput\.id\('danmaku_text_input'\)/.test(bar), 'focus id retained (focusDanmakuComposer + tests)');
for (const label of ['字体大小', '弹幕位置', '弹幕颜色']) {
  assert.ok(bar.includes(label), `settings row ${label} must remain`);
}

// ---- ④ 前景色与评论页输入胶囊同源 ----
assert.ok(barSrc.includes(".placeholderColor($r('app.color.color_player_text_secondary'))"),
  'placeholder uses the same secondary color as FloatingCommentEntry');
assert.ok(/TextInput\.placeholderColor\(\{ "id":/.test(bar), 'placeholder color compiles to a resource');
assert.ok(/private styleToggleColor\(\): ResourceColor/.test(bar), 'style toggle shares the secondary color');
const commentEntry = source('components/FloatingCommentEntry');
assert.ok(/capsuleHeight: 40/.test(commentEntry) && /color_player_text_secondary/.test(commentEntry),
  'reference comment capsule is still 40vp with the secondary foreground');

// ---- ⑤ 其它页面的弹幕输入入口统一 capsule 材质 ----
for (const [rel, label] of [
  ['components/VideoControls', '横屏/全屏控制栏弹幕输入入口'],
  ['pages/VideoPlayerPage', '竖屏 Tab / 连刷浮层弹幕输入入口'],
]) {
  const text = compiled(rel);
  assert.ok(!/refractive:\s*false/.test(text), `${label} must not use the flat non-material shell`);
  assert.ok(/NativeGlassInput\(this, \{/.test(text), `${label} still uses the shared capsule`);
}
const controlsSrc = source('components/VideoControls');
const playerSrc = source('pages/VideoPlayerPage');
assert.equal((controlsSrc.match(/NativeGlassInput\(\{ inputHeight: (32|34) \}\)/g) || []).length, 2,
  'both VideoControls danmaku entries aligned');
assert.equal((playerSrc.match(/NativeGlassInput\(\{ inputHeight: (28|34) \}\)/g) || []).length, 3,
  'all three VideoPlayerPage danmaku entries aligned');
assert.ok(playerSrc.includes(".fontColor($r('app.color.color_player_text_secondary'))"),
  'portrait tab entry uses the same secondary foreground');

// ---- ⑥ 原生玻璃保留，收起态不挂外层面板 ----
// Navigation title 作用域是本项目挂 systemMaterial 的通道，不能删；
// 用 active 条件挂载即可做到「收起只有胶囊、展开才有玻璃面板」。
const playerCompiled = compiled('pages/VideoPlayerPage');
assert.ok(/allCorners: true, active: this\.dmComposerSettings/.test(playerCompiled),
  'native glass panel mounts only while style settings are expanded');
assert.ok(!playerSrc.includes('danmakuComposerBackdrop'),
  'glass must not be replaced by a flat opaque backdrop');
assert.ok(/Column\.clip\(this\.dmComposerSettings\)/.test(playerCompiled) &&
  /Scroll\.clip\(this\.dmComposerSettings\)/.test(playerCompiled),
  'closed capsule is not clipped by an outer frame');
assert.ok(barSrc.includes('NativeComposerSurface({ active: this.materialEnabled && this.settings })'),
  'editor keeps its own optional glass scope for reuse');

// ---- ⑦ 设置选项用 @Prop 刷新选中态 ----
assert.ok(/@Prop selected: boolean = false/.test(barSrc) &&
  /struct DanmakuOption/.test(barSrc), 'style options are a component with @Prop selected');
assert.ok(!/@Builder\s+option\(/.test(barSrc),
  '@Builder value params do not refresh when @State changes');
assert.ok(/selected: this\.fontSize === 25/.test(barSrc) &&
  /selected: this\.fontSize === 18/.test(barSrc) &&
  /selected: this\.mode === mode/.test(barSrc),
  'font size and position options read @State directly');
assert.ok(barSrc.includes("this.selected ? ' 已选中' : ' 未选中'"),
  'accessibility text exposes the selected state');
assert.ok(/class DanmakuOption extends ViewPU/.test(bar) &&
  /this\.__selected\.reset\(params\.selected\)/.test(bar),
  'compiled @Prop is re-synced when the parent state changes');
assert.ok(/Button\.fontColor\(this\.selected \? '#FB7299' : '#92969D'\)/.test(bar) &&
  /Button\.border\(\{ width: 1, color: this\.selected \? '#FB7299' : '#646970' \}\)/.test(bar),
  'compiled component re-applies the selected colour on @Prop change');

console.log('PASS: danmaku input matches the comment capsule (40vp, no send button, A on the right, no outer frame); style options refresh via @Prop; all player entries share the capsule material.');
