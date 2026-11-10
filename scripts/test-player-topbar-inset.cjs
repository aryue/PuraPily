const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const file = path.join(__dirname, '../entry/src/main/ets/components/VideoControls.ets');
const source = fs.readFileSync(file, 'utf8');

function constant(name) {
  const m = source.match(new RegExp(`const ${name}: number = (\\d+)`));
  assert.ok(m, `${name} must be declared as a module-level constant`);
  return Number(m[1]);
}

const inset = constant('PLAYER_TOP_BAR_INSET_X');
const padTop = constant('PLAYER_TOP_BAR_PAD_TOP');
const rowH = constant('PLAYER_TOP_BAR_ROW_H');
const bandH = constant('PLAYER_TOP_BAR_BAND_H');

// 1) 横向：顶栏与同一屏底部控件（ReferenceLandscapeBottomControls 全屏档）同一套边距。
//    底栏是 `left/right: referenceLandscapeHalfScreen ? 18 : 30`，全屏档 30。
assert.match(source, /\.width\('100%'\)\.height\(52\)\.padding\(\{ left: this\.referenceLandscapeHalfScreen \? 18 : 30, right: this\.referenceLandscapeHalfScreen \? 18 : 30 \}\)/,
  'landscape bottom controls must keep their 30vp fullscreen inset');
assert.equal(inset, 30, 'the landscape top bar must use the same 30vp inset as the bottom controls');

const row = source.slice(source.indexOf('ReferenceLandscapeFullscreenControls()'), source.indexOf('ReferenceLandscapeHalfScreenControls()'));
assert.match(row, /\.padding\(\{ left: PLAYER_TOP_BAR_INSET_X, right: PLAYER_TOP_BAR_INSET_X, top: PLAYER_TOP_BAR_PAD_TOP \}\)/,
  'the top bar row must take its insets from the shared constants');
assert.match(row, /\.width\('100%'\)\.height\(PLAYER_TOP_BAR_ROW_H\)/, 'row height must follow the constant');
assert.match(row, /\.height\(PLAYER_TOP_BAR_BAND_H\)/, 'the gradient band height must follow the constant');
assert.ok(!/left: 4, right: 22/.test(source), 'the old 4/22 insets (back button glued to the edge) must be gone');

// 2) 纵向：按钮要让开应用自绘的状态条。状态条 topBarStatusInfo 是 y:3、高约 20vp（电池图标 20）⇒ 下沿 23。
const statusRow = source.slice(source.indexOf('topBarStatusInfo()'), source.indexOf('topBarStatusLeft()'));
assert.match(statusRow, /\.position\(\{ x: '50%', y: 3 \}\)/, 'status row anchor moved; re-check the clearance below');
const statusBottom = 3 + 20;
assert.ok(padTop >= statusBottom + 4, `top padding ${padTop} must clear the status row bottom ${statusBottom}`);

// 内容区高度必须容得下 40vp 的圆形控件，加上 padding 不能把按钮压出可视区。
const contentH = rowH - padTop;
assert.ok(contentH >= 40, `row content ${contentH}vp must fit the 40vp glass buttons`);
assert.ok(contentH - 40 <= 4, `row content ${contentH}vp leaves ${contentH - 40}vp slack (keeps the row visually centred)`);
assert.equal(bandH, rowH + 8, 'the dim band keeps a small fade margin below the row');

console.log(`PASS: landscape top bar ${inset}vp insets (matches bottom controls), row top ${padTop}vp clears the status row, band ${bandH}vp`);
