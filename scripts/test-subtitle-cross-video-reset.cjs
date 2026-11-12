/**
 * 字幕功能「概率取到其他视频的数据」回归：
 *  - 根因①：分P/番剧切集、深链换 cid 走 setPlaybackCid，旧 referenceSubtitleCues 原样残留；
 *    同 bvid 换 P 后 bvid 校验永远通过，新 P 播到相同时间点就显示旧 P 的字幕。
 *  - 根因②：竖屏开关 referenceSetSubtitles 无请求令牌、落地只校验 bvid 不校验 cid，
 *    请求在途时切 P（cid 变、bvid 不变）响应照常落地，把旧 P 字幕挂到新 P；
 *    快速开关两次还会让已取消的请求复活。
 *  - 修复：setPlaybackCid 在 cid 实际变化时统一 referenceResetSubtitles()；
 *    referenceSetSubtitles 加令牌 + bvid/cid 双校验；连刷 commit 处也走统一重置。
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8')
  .replace(/\r\n/g, '\n');

function extract(name, { braces = 1 } = {}) {
  const start = source.indexOf(`${name}(`);
  assert.ok(start > 0, `缺少 ${name}`);
  let i = source.indexOf('{', start);
  let depth = 0;
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') { depth--; if (depth === braces - 1) break; }
  }
  return source.slice(source.lastIndexOf('\n', start) + 1, i + 1);
}

// 1) 统一重置：清全部字幕状态 + 递增全部请求令牌作废在途请求。
const reset = extract('private referenceResetSubtitles');
for (const field of ['referenceSubtitleToggleRequest', 'referenceSubtitleMenuRequest', 'referenceSubtitleSelectionRequest']) {
  assert.ok(reset.includes(`this.${field}++`), `referenceResetSubtitles 必须递增令牌 ${field}`);
}
for (const field of ['referenceSubtitleEnabled', 'referenceSubtitleText', 'referenceSubtitleCues',
  'referenceSubtitleOptions', 'referenceSubtitleTrackUrls', 'referenceSelectedSubtitleIndex']) {
  assert.ok(new RegExp(`this\\.${field}\\s*=\\s*(false|''|\\[\\]|-1)`).test(reset),
    `referenceResetSubtitles 必须清空 ${field}`);
}

// 2) setPlaybackCid：cid 实际变化才重置（同 cid 重试不误伤已开启的字幕）。
const setCid = extract('private setPlaybackCid');
assert.ok(setCid.includes("if (cid !== this.vi.cid) this.referenceResetSubtitles()"),
  'setPlaybackCid 必须在 cid 变化时重置字幕状态');
assert.ok(setCid.includes('this.vi.cid = cid') && setCid.includes('this.cidReady_?.()'),
  'setPlaybackCid 原有语义必须保留');

// 3) 竖屏开关：令牌 + bvid/cid 双校验，失败分支也不得翻转状态/弹 toast。
const toggle = extract('private async referenceSetSubtitles');
assert.ok(toggle.includes('++this.referenceSubtitleToggleRequest'),
  'referenceSetSubtitles 必须申请请求令牌');
assert.ok(toggle.includes('const cid = this.vi.cid'),
  'referenceSetSubtitles 必须捕获 cid');
assert.ok(/token === this\.referenceSubtitleToggleRequest[\s\S]*?bvid === this\.vi\.bvid[\s\S]*?cid === this\.vi\.cid[\s\S]*?this\.referenceAlive/.test(toggle),
  'referenceSetSubtitles 落地校验必须同时含令牌 + bvid + cid + 存活');
assert.ok(toggle.includes('if (!stillValid()) return;'),
  'referenceSetSubtitles 所有 await 后必须走 stillValid 早退');
assert.ok(toggle.includes('cid=${cid}') && !toggle.includes('cid=${this.vi.cid}'),
  '字幕列表请求 URL 必须用捕获的 cid，不能用实时值');

// 4) 横屏字幕列表：URL 用捕获 cid（原先用 this.vi.cid，列表可能落成另一个视频的轨道）。
const menu = extract('private async referenceOpenLandscapeSubtitles');
assert.ok(menu.includes('cid=${cid}'), 'referenceOpenLandscapeSubtitles 请求 URL 必须用捕获的 cid');

// 5) 连刷换片：整体赋值 vi 绕过 setPlaybackCid，必须显式统一重置。
const feedCommit = source.slice(source.lastIndexOf('ContinuousRecommendationState.markVisited'),
  source.lastIndexOf('ContinuousRecommendationState.markVisited') + 400);
assert.ok(feedCommit.includes('this.referenceResetSubtitles()'),
  '连刷 commit 必须调用 referenceResetSubtitles');
assert.ok(!feedCommit.includes('this.referenceSubtitleEnabled = false;') ||
  feedCommit.includes('this.referenceResetSubtitles()'),
  '连刷 commit 不应残留旧的三行手动重置');

// 6) 令牌字段都已声明。
for (const field of ['referenceSubtitleToggleRequest', 'referenceSubtitleMenuRequest', 'referenceSubtitleSelectionRequest']) {
  assert.ok(new RegExp(`private ${field}: number = 0;`).test(source), `缺少字段声明 ${field}`);
}

// 7) 选字幕接口（referenceSelectSubtitle）本就有令牌 + bvid/cid 校验，防回退。
const select = extract('private async referenceSelectSubtitle');
assert.ok(/token !== this\.referenceSubtitleSelectionRequest[\s\S]*?bvid !== this\.vi\.bvid[\s\S]*?cid !== this\.vi\.cid/.test(select),
  'referenceSelectSubtitle 落地校验必须保留令牌 + bvid + cid');

console.log('test-subtitle-cross-video-reset: all assertions passed');
