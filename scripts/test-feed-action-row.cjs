const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// 连刷底部操作行：四个按钮（点赞/投币/收藏/评论）原来各带 layoutWeight(1)，
// 与弹幕输入框按 2:1:1:1:1 的权重分屏宽 → 平板上单个按钮被拉到 200vp+，图标间距随屏宽无限变大。
// 现在：输入框吸收剩余宽度（并有上限），按钮组固定 FEED_ACTION_ITEM_W * 4 靠右。
const itemW = source.match(/const FEED_DANMAKU_MAX_W[^\n]*\n/);
assert.ok(itemW, 'FEED_DANMAKU_MAX_W must be declared');
const width = Number(source.match(/const FEED_ACTION_ITEM_W: number = (\d+)/)[1]);
assert.ok(width >= 44 && width <= 64, `action item width ${width}vp must stay in the touch-target range, not scale with screen`);
const cap = Number(source.match(/const FEED_DANMAKU_MAX_W: number = (\d+)/)[1]);
assert.ok(cap > width * 4, 'the input cap must sit above the button group so phones keep a natural input width');
assert.ok(cap <= 400, `input cap ${cap}vp is too wide to be useful on a tablet`);

// 两层（当前页 / 滑入页）必须同一口径，否则翻页交接时图标会左右跳。
const groups = [...source.matchAll(/\.width\(FEED_ACTION_ITEM_W \* 4\)\s*\n\s*\}\.width\('100%'\)\.justifyContent\(FlexAlign\.SpaceBetween\)/g)];
assert.equal(groups.length, 2, 'both feed action rows must pin the button group right and park slack in the middle');

const blocks = [];
let at = -1;
while ((at = source.indexOf("Text('发弹幕')", at + 1)) >= 0) {
  const start = source.lastIndexOf('Row() {', at);
  blocks.push(source.slice(start, source.indexOf('}.width(FEED_ACTION_ITEM_W * 4)', at) + 31));
}
assert.equal(blocks.length, 2, 'expected exactly two danmaku-input action rows (feed chrome + preview chrome)');
for (const [i, block] of blocks.entries()) {
  assert.match(block, /\}\.layoutWeight\(1\)\.constraintSize\(\{ maxWidth: FEED_DANMAKU_MAX_W \}\)/,
    `block ${i}: the danmaku input absorbs leftover width but stops growing on wide screens`);
  assert.ok(!/layoutWeight\(2\)/.test(block), `block ${i}: the input must no longer out-weight the buttons`);
  assert.equal([...block.matchAll(/ReferencePlayerAction\(/g)].length, 4, `block ${i}: four action buttons required`);
  assert.match(block, /\.width\(FEED_ACTION_ITEM_W \* 4\)$/, `block ${i}: the four buttons must sit in one fixed-width group`);
}

// 组件本身仍用权重均分——均分的是那个固定宽度的组，而不是整行。
const action = source.slice(source.indexOf('struct ReferencePlayerAction {'));
const actionBody = action.slice(0, action.indexOf('\n}\n'));
assert.match(actionBody, /\.layoutWeight\(1\)/, 'ReferencePlayerAction still splits the fixed group evenly');

// 图标同框：四个按钮的图标必须同一尺寸。点赞曾走 23vp 分支（其余三个走 originalIcon 的 32vp），
// 既显小，又让 Column 内容高度不同、居中后四个数字基线错开约 5vp。
const sizeFn = actionBody.match(/private actionIconSize\(\): number \{\s*return this\.intro \? (\d+) : (\d+);\s*\}/);
assert.ok(sizeFn, 'actionIconSize() must keep one size for the feed row and one for the intro row');
const [introSize, feedSize] = [Number(sizeFn[1]), Number(sizeFn[2])];
assert.ok(feedSize >= 30, `feed action icons must be at least 30vp (got ${feedSize}vp) or the SVG thumb looks smaller than the 32vp PNGs`);
assert.ok(introSize < feedSize, 'the intro stats row keeps its smaller 22vp icons');
assert.match(actionBody, /\.width\(this\.actionIconSize\(\)\)\.height\(this\.actionIconSize\(\)\)/,
  'the icon must take its size from actionIconSize()');
assert.match(actionBody, /\.objectFit\(ImageFit\.Contain\)/,
  'the comment bubble is 38x37; Cover would crop it');
assert.match(actionBody, /fillColor\(this\.selected \? '#D34E7E' :/,
  'selected state is a tint, so every icon must be a single-colour SVG');
assert.ok(!/originalIcon/.test(source), 'originalIcon (bitmap keeps its own colours) must be gone');
assert.ok(!/ref_apk_story_/.test(source), 'the feed row must not fall back to the APK story bitmaps');
for (const icon of ['ref_like', 'ref_coin', 'ref_favorite', 'ref_comment_fill']) {
  assert.ok(blocks.every((b) => b.includes(`app.media.${icon}`)), `both action rows must use ${icon}`);
}

console.log(`PASS: feed action group ${width}vp * 4 at the right edge, icons ${feedSize}vp uniform (intro ${introSize}vp), input capped at ${cap}vp`);
