const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const page = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');
const vc = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/components/VideoControls.ets'), 'utf8');

// ── 1) VideoControls 调用链不得再被「清屏态」整体隐藏 ────────────────────────────
// 快进快退胶囊/缩略图（type === 'seek'）与长按倍速胶囊（type === ''）都渲染在
// VideoControls 里；整棵 visibility(Hidden) 会把反馈一起吞掉（2026-11-17 用户反馈）。
const callStart = page.indexOf('      VideoControls({');
assert.ok(callStart > 0, 'VideoControls call must exist');
const callEnd = page.indexOf('// ⭐ 手势提示（原全屏/竖屏分支各自挂载', callStart);
assert.ok(callEnd > callStart, 'gesture hint section must follow the VideoControls call');
const call = page.slice(callStart, callEnd);
assert.ok(!/referenceCleanViewing/.test(call),
  'clean viewing must not hide the whole VideoControls subtree (it owns seek/hold feedback)');
assert.ok(!/Visibility\.Hidden/.test(call),
  'no blanket Hidden on VideoControls: hidePlaybackControls already suppresses the control bar');

// ── 2) 清屏态仍然不会露出播放控制栏 ────────────────────────────────────────────
assert.match(call,
  /hidePlaybackControls: this\.referenceLayout && !this\.fs && !this\.isLs && \(this\.referenceFeed \|\| this\.referenceModeAnimating\)/,
  'feed portrait must keep hidePlaybackControls=true so clean view shows no control bar');
assert.match(vc, /if \(this\.isControlsVisible && !this\.hidePlaybackControls\) \{/,
  'control layer stays gated by isControlsVisible && !hidePlaybackControls');

// ── 3) 两类手势反馈的渲染条件里不得叠加控制栏可见性 ──────────────────────────────
const seekHint = vc.indexOf("if (this.showGestureHint && this.gestureHintMainText && this.gestureHintType === 'seek')");
const holdHint = vc.indexOf("if (this.showGestureHint && this.gestureHintMainText && this.gestureHintType === '')");
assert.ok(seekHint > 0, 'seek hint branch must exist');
assert.ok(holdHint > 0, 'hold-speed hint branch must exist');
for (const line of vc.split(/\r?\n/)) {
  if (!/showGestureHint/.test(line)) continue;
  assert.ok(!/isControlsVisible|hidePlaybackControls/.test(line),
    `gesture hint must not depend on control-bar visibility: ${line.trim()}`);
}

// ── 4) 页面侧：两条反馈状态确实在连刷路径上产生 ────────────────────────────────
// 横滑：onTM 的 seek 分支调用 sGH(..., 'seek')
assert.match(page, /this\.sGH\(`\$\{this\.formatDuration\(Math\.round\(nt\)\)\}`[^\n]*'seek'\)/,
  'horizontal drag must emit the seek hint through sGH');
// 长按：连刷 Down 段挂 500ms 长按计时器
assert.match(page, /this\.playbackResources_\.video\?\.state === 'playing'\) this\.scheduleHoldSpeed\(true\)/,
  'feed touch start must arm the long-press speed timer');
assert.match(page, /this\.ght = '长按加速';\s*\n\s*this\.gh = true;[\s\S]{0,120}this\.ghtType = '';/,
  'hold speed must set the type-less hint (long-press pill)');

// ── 5) 清屏仍隐藏字幕：这次只放开手势反馈，别把字幕一起放出来 ──────────────────
assert.match(page, /if \(this\.referenceSubtitleEnabled && this\.referenceSubtitleText && !this\.referenceCleanViewing\(\)\)/,
  'clean viewing still hides subtitles');
//
console.log('PASS: clean viewing keeps seek + hold-speed feedback (VideoControls no longer blanket-hidden), control bar and subtitles stay hidden.');
