const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');
const geometry = { exports: {} };
const geometrySource = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils/SplitPaneGeometry.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(geometrySource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, geometry);
function between(start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from);
  return source.slice(from, to);
}
const stored = new Map();
// The harness executes animation closures immediately; geometry remains real.
const context = { exports: {}, clearTimeout, KeyboardAvoidMode: { NONE: 4 }, TouchType: { Down: 0, Move: 1, Up: 2, Cancel: 3 }, preferences: { getPreferences: async () => ({
  get: async (key, fallback) => stored.has(key) ? stored.get(key) : fallback,
  put: async (key, value) => stored.set(key, value), flush: async () => {}
}) }, media: { VideoScaleType: {
  VIDEO_SCALE_TYPE_FIT: 'stretch', VIDEO_SCALE_TYPE_FIT_CROP: 'crop', VIDEO_SCALE_TYPE_SCALED_ASPECT: 'contain'
} } };
Object.assign(context, geometry.exports);
context.Curve = { EaseOut: 'ease-out' };
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${between('  private safeCM():', '  /** ⭐ 播放页竖屏评论区')}
  ${between('  private referenceHalfScreenControlsActive():', '  private referenceLandscapePlayerWidth():')}
  ${between('  private referenceLandscapePlayerWidth():', '  private referenceFeedCommentAmount():')}
  ${between('  private onRelatedVideoClick(', '  private async loadC(')}
  ${between('  private closePlaybackOptionPanel():', '  private onOverlayBack_():')}
  ${between('  private onDanmakuComposerChanged():', '  @Builder\n  ReferenceLandscapeDanmakuComposer()')}
  ${between('  private referenceFeedCommentAmount():', '  private referenceFullscreenButtonTop(')}
  ${between('  private referenceIntroScrollOffset(', '  private referenceFeedNeighbor(')}
  ${between('  private effectiveScaleMode(', '  private onPlaybackViewportChanged(')}
  ${between('  private getVideoScaleType():', '  private updateVideoSize()')}
  ${between('  private async loadSM()', '  private async loadD(')}
  ${between('  private portraitPlateByArea():', '  /**\n   * ⭐ 全屏相关的圆角')}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
const p = new context.exports.Page();
Object.assign(p, { cw: 400, ch: 850, referenceLayout: true, referenceFeed: false,
  referenceFeedProgress: 0, referenceFeedComments: false, referencePanelOffset: 0,
  fs: false, isLs: false, isLightsOff: false, mp: false, sm: 'auto', referenceFeedPortraitScaleMode: 'fill',
  referenceFeedPortraitScaleScope: 'standard', referenceSafeTop: () => 40 });
const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-7, `${a} != ${b}`);
// Test actual page geometry: ultra-wide, standard, square and portrait media,
// including expanded/collapsed panels and the comments/settings viewports.
for (const ar of [2.4, 32 / 9, 16 / 9, 4 / 3, 1, 9 / 16]) {
  p.ar = ar;
  for (const offset of [p.referenceMinimumPanelOffset(), 0, 100]) {
    p.referencePanelOffset = offset;
    for (const view of ['detail', 'comments', 'settings']) {
      p.referenceFeedComments = view === 'comments'; p.mp = view === 'settings';
      const topGap = p.referenceMediaTop() - p.referenceAreaTop();
      const bottomGap = p.referenceAreaTop() + p.referenceAreaHeight() -
        p.referenceMediaTop() - p.referenceMediaHeight();
      close(topGap, bottomGap);
      assert.ok(topGap >= -1e-7);
      close(p.referenceMediaWidth() / p.referenceMediaHeight(), ar);
      assert.ok(p.referenceMediaWidth() <= p.cw);
    }
  }
}
p.referenceFeedComments = false; p.mp = false; p.referencePanelOffset = 0;
p.ar = 2.4; p.referenceFeed = true;
let previous;
for (let step = 0; step <= 100; step++) {
  p.referenceFeedProgress = step / 100;
  const top = p.referenceMediaTop();
  assert.ok(Number.isFinite(top));
  if (previous !== undefined) assert.ok(Math.abs(top - previous) < 10);
  previous = top;
}
close(p.referenceMediaTop() + p.referenceMediaHeight() / 2, p.ch * 0.4);
// Feed portrait scaling is independent of the fullscreen selection.
p.sm = 'fill'; p.referenceFeed = false;
assert.equal(p.effectiveScaleMode(), 'auto');
p.fs = true; assert.equal(p.effectiveScaleMode(), 'fill');
p.fs = false; p.referenceFeed = true; p.ar = 9 / 16;
assert.equal(p.effectiveScaleMode(), 'fill');
p.sm = 'auto'; assert.equal(p.effectiveScaleMode(), 'fill');
assert.equal(p.getVideoScaleType(), 'crop');
for (const aspect of [3 / 4, 2 / 3, 9 / 20, 0.56, 0.565]) {
  p.ar = aspect;
  assert.equal(p.effectiveScaleMode(), 'auto', `standard scope excludes ${aspect}`);
  p.referenceFeedPortraitScaleScope = 'all';
  assert.equal(p.effectiveScaleMode(), 'fill', `all scope includes ${aspect}`);
  p.referenceFeedPortraitScaleScope = 'standard';
}
p.ar = 608 / 1080;
assert.equal(p.effectiveScaleMode(), 'fill', 'allow sub-pixel encoding roundoff near 9:16');
p.ar = 9 / 16;
// Both wider and taller displays fill their viewport without distorting 9:16 content.
for (const [width, height] of [[475, 800], [400, 850]]) {
  p.cw = width; p.ch = height;
  close(p.referenceMediaWidth(), width); close(p.referenceMediaHeight(), height);
  close(p.referenceMediaTop(), 0);
  const scale = Math.max(width / 9, height / 16);
  assert.ok(9 * scale >= width && 16 * scale >= height);
  p.referenceFeedPortraitScaleMode = 'auto';
  assert.equal(p.getVideoScaleType(), 'contain');
  close(p.referenceMediaWidth() / p.referenceMediaHeight(), 9 / 16);
  assert.ok(p.referenceMediaWidth() <= width && p.referenceMediaHeight() <= height);
  p.referenceFeedPortraitScaleMode = 'fill';
}
p.fs = true; assert.equal(p.effectiveScaleMode(), 'auto');
p.fs = false; p.ar = 16 / 9; assert.equal(p.effectiveScaleMode(), 'auto');
p.ar = 9 / 16; p.isLs = true; assert.equal(p.effectiveScaleMode(), 'auto');
p.isLs = false; p.mp = true; assert.equal(p.effectiveScaleMode(), 'auto');
p.mp = false;
p.referenceFeedComments = true; assert.equal(p.effectiveScaleMode(), 'auto');
// The boolean changes before the animator's first frame. Native surface geometry
// must be identical on both sides of that change, in both transition directions.
Object.assign(p, { cw: 440, ch: 744, ar: 9 / 16, referenceFeedComments: false,
  referenceModeAnimating: false, referenceFeed: false, referenceFeedProgress: 0 });
const rect = () => [p.ovRectX() + (p.ovRectW() - p.ovVideoW()) / 2,
  p.ovRectY() + (p.ovRectH() - p.ovVideoH()) / 2, p.ovVideoW(), p.ovVideoH()];
for (const [cw, ch] of [[440, 744], [400, 850]]) {
  p.cw = cw; p.ch = ch;
  for (const mode of ['auto', 'fill']) {
    p.referenceFeedPortraitScaleMode = mode;
    for (const offset of [0, 120, p.referenceMinimumPanelOffset()]) {
      p.referencePanelOffset = offset;
      p.referenceFeed = false; p.referenceFeedProgress = 0; p.referenceModeAnimating = false;
      const half = rect();
      p.referenceModeAnimating = true; p.referenceFeed = true;
      rect().forEach((v, i) => close(v, half[i]));
      const frames = [rect()];
      for (let step = 1; step <= 100; step++) {
        p.referenceFeedProgress = step / 100;
        const next = rect();
        next.forEach((v, i) => {
          assert.ok(Number.isFinite(v));
          assert.ok(Math.abs(v - frames.at(-1)[i]) < 15, `discontinuous ${mode} transition`);
        });
        frames.push(next);
      }
      const final = rect();
      p.referenceModeAnimating = false;
      rect().forEach((v, i) => close(v, final[i]));
      p.referenceModeAnimating = true;
      for (let step = 100; step >= 0; step--) {
        p.referenceFeedProgress = step / 100;
        rect().forEach((v, i) => close(v, frames[step][i]));
      }
      p.referenceFeed = false; p.referenceModeAnimating = false;
      rect().forEach((v, i) => close(v, half[i]));
    }
  }
}
// Upward drag first collapses the player; only its minimum unlocks intro scrolling.
Object.assign(p, { cw: 400, ch: 850, ar: 9 / 16, referencePanelOffset: 0, at: 0, isPgc_: false,
  detailScroller: { currentOffset: () => ({ yOffset: 0 }) } });
const touch = (type, y) => ({ type, touches: [{ windowX: 200, windowY: y }], changedTouches: [] });
p.referencePanelBodyTouch(touch(0, 700));
p.referencePanelBodyTouch(touch(1, 660));
assert.ok(p.referencePanelOffset > p.referenceMinimumPanelOffset());
assert.equal(p.referenceIntroScrollOffset(40), 0, 'intro must stay still while player is collapsing');
p.referencePanelBodyTouch(touch(1, 200));
close(p.referencePanelOffset, p.referenceMinimumPanelOffset());
assert.equal(p.referenceIntroScrollOffset(20), 20, 'same gesture can scroll once minimum is reached');
assert.equal(p.referenceIntroScrollOffset(-20), 0, 'downward drag at content top belongs to panel');
p.detailScroller = { currentOffset: () => ({ yOffset: 80 }) };
assert.equal(p.referenceIntroScrollOffset(-20), -20, 'scrolled content returns to top first');
p.referencePanelOffset = 0;
p.referencePanelBodyTouch(touch(0, 700));
assert.equal(p.referencePanelBodyCanDrag, true, 'already scrolled intro must not prevent player collapse');
p.referencePanelBodyTouch(touch(1, 660));
assert.equal(p.referenceIntroScrollOffset(40), 0);
console.log('Intro scroll waits for minimum player height, then continues; top pull-down and scrolled re-entry passed.');
console.log('Half-screen centering, feed transitions, independent portrait crop/contain and fullscreen isolation passed.');
// Comments share one continuous geometry timeline with the live Surface. Check
// both endpoint handoffs, reverse while opening, and stale animator callbacks.
let commentAnimator;
p.getUIContext = () => ({ createAnimator: options => (commentAnimator = {
  options, play() {}, cancel() {}
}) });
p.onPlaybackViewportChanged = () => {};
const commentRect = () => [p.referenceMediaWidth(), p.referenceMediaHeight(), p.referenceMediaTop(), p.referenceDetailPanelTop()];
for (const [cw, ch] of [[400, 850], [475, 800]]) {
  for (const ar of [9 / 16, 3 / 4, 16 / 9, 2.4]) {
    for (const mode of ['auto', 'fill']) {
      Object.assign(p, { cw, ch, ar, referenceFeed: true, referenceFeedProgress: 1,
        referenceFeedComments: false, referenceFeedCommentAnimator: null, referenceModeAnimating: false,
        referenceFeedPortraitScaleMode: mode, referenceFeedPortraitScaleScope: 'all', referencePanelOffset: 0 });
      const feed = commentRect();
      p.referenceSetFeedComments(true);
      commentRect().forEach((v, i) => close(v, feed[i]));
      const opening = commentAnimator;
      let previous = feed;
      for (let step = 0; step <= 100; step++) {
        opening.onFrame(step / 100);
        const next = commentRect();
        next.forEach((v, i) => assert.ok(Number.isFinite(v) && Math.abs(v - previous[i]) < 15));
        previous = next;
      }
      opening.onFinish();
      commentRect().forEach((v, i) => close(v, previous[i]));
      close(p.referenceMediaWidth() / p.referenceMediaHeight(), ar);
      p.referenceSetFeedComments(false);
      commentRect().forEach((v, i) => close(v, previous[i]));
      const closing = commentAnimator;
      closing.onFrame(0.4);
      const mid = commentRect();
      p.referenceSetFeedComments(true);
      commentRect().forEach((v, i) => close(v, mid[i]));
      closing.onFrame(0); closing.onFinish();
      commentRect().forEach((v, i) => close(v, mid[i]));
      commentAnimator.onFrame(1); commentAnimator.onFinish();
      p.referenceSetFeedComments(false);
      commentAnimator.onFrame(0); commentAnimator.onFinish();
      assert.equal(p.referenceFeedComments, false);
      commentRect().forEach((v, i) => close(v, feed[i]));
      p.referenceSetFeedComments(true);
      p.referenceSetFeedComments(false);
      assert.equal(p.referenceFeedComments, false, 'immediate back must close before first animation frame');
    }
  }
}
console.log('Feed comments: continuous open/close geometry, crop handoff, reversal and stale callbacks passed.');
(async () => {
  p.getUIContext = () => ({ getHostContext: () => ({}) });
  stored.set('sm', 'fitWidth');
  await p.loadSM();
  assert.equal(p.sm, 'fitWidth');
  assert.equal(p.referenceFeedPortraitScaleMode, 'fill', 'new preference defaults to crop');
  assert.equal(p.referenceFeedPortraitScaleScope, 'standard', 'default limits cropping to 9:16');
  p.referenceFeedPortraitScaleMode = 'auto';
  p.referenceFeedPortraitScaleScope = 'all';
  await p.saveFeedPortraitScaleMode();
  assert.equal(stored.get('sm'), 'fitWidth', 'feed choice must not overwrite fullscreen choice');
  p.referenceFeedPortraitScaleMode = 'fill';
  await p.loadSM();
  assert.equal(p.referenceFeedPortraitScaleMode, 'auto', 'restore feed choice on next launch');
  assert.equal(p.referenceFeedPortraitScaleScope, 'all', 'restore opted-in all-portrait scope');
  stored.set('feedPortraitScaleMode', 'invalid');
  stored.set('feedPortraitScaleScope', 'invalid');
  await p.loadSM();
  assert.equal(p.referenceFeedPortraitScaleMode, 'fill');
  assert.equal(p.referenceFeedPortraitScaleScope, 'standard');
  console.log('Independent feed preference default, persistence and invalid-value fallback passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });

const compiledFile = path.resolve(__dirname, '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts');
function verifyHalfScreenControls(page) {
  for (const isLs of [false, true]) {
    for (const fs of [false, true]) {
      for (const referenceFeed of [false, true]) {
        for (const referenceModeAnimating of [false, true]) {
          Object.assign(page, { referenceLayout: true, isLs, fs, referenceFeed, referenceModeAnimating });
          assert.equal(page.referenceHalfScreenControlsActive(), !fs && (isLs || (!referenceFeed && !referenceModeAnimating)));
        }
      }
    }
  }
  page.referenceLayout = false;
  assert.equal(page.referenceHalfScreenControlsActive(), false, 'alternative layout retains its controls');
}
verifyHalfScreenControls(p);
function verifyOptionPanelBack(page) {
  page.resetCT = () => {};
  for (const panel of ['qp', 'rp', 'sp']) {
    Object.assign(page, { qp: false, rp: false, sp: false, ip: true, cv: false });
    page[panel] = true;
    assert.equal(page.closePlaybackOptionPanel(), true);
    assert.equal(page[panel], false);
    assert.equal(page.cv, true);
    assert.equal(page.ip, false);
    assert.equal(page.closePlaybackOptionPanel(), false);
  }
}
verifyOptionPanelBack(new context.exports.Page());
function verifyComposer(page) {
  let avoidMode = 'offset';
  const keyboardListener = () => {};
  const subscriptions = [];
  Object.assign(page, { isLs: true, showDanmakuSheet: true, landscapeComposerAvoidMode: null,
    referenceAlive: true, playerPageVisible: true, ch: 625, danmakuKeyboardHeight: 0,
    onDanmakuKeyboardHeight: keyboardListener, cancelDelayHide() {}, resetCT() {}, referenceSafeTop: () => 40,
    mw: { on: (name, callback) => subscriptions.push([name, callback]), off() {} },
    getUIContext: () => ({ getKeyboardAvoidMode: () => avoidMode,
      setKeyboardAvoidMode: value => { avoidMode = value; }, getFocusController: () => ({ clearFocus() {} }) }) });
  page.onDanmakuComposerChanged();
  assert.equal(avoidMode, 4, 'manual keyboard positioning must disable whole-page offset');
  assert.equal(subscriptions[0][1], keyboardListener);
  for (const height of [0, 200, 312, 480]) {
    page.danmakuKeyboardHeight = height;
    const h = page.landscapeDanmakuComposerHeight();
    const top = Math.max(40, page.ch - height - h);
    assert.ok(top >= 40 && top + h <= page.ch - height, 'composer must stay above keyboard');
  }
  page.showDanmakuSheet = false;
  page.onDanmakuComposerChanged();
  assert.equal(avoidMode, 'offset', 'closing must restore the previous keyboard policy');
  assert.equal(page.danmakuKeyboardHeight, 0);
}
verifyComposer(new context.exports.Page());
function verifyLandscape(page) {
  for (const isLayoutSwapped of [false, true]) {
  for (const navIndicatorHeight of [0, 8, 24]) {
  for (const [cw, ch] of [[1000, 625], [850, 400], [744, 440]]) {
    for (const ar of [32/9, 16/9, 4/3, 1, 9/16]) {
      Object.assign(page, { cw, ch, ar, isLs: true, fs: false, fsEntering: false, fsLerpDir: 0,
        referenceLayout: true, referenceFeed: false, referencePanelOffset: 120, cardMargin: 12, isLayoutSwapped, navIndicatorHeight, referenceSafeTop: () => 40 });
      const half = [page.ovRectX(), page.ovRectY(), page.ovRectW(), page.ovRectH(), page.ovVideoW(), page.ovVideoH()];
      close(half[2], cw * 2/3 - 24);
      close(half[0], isLayoutSwapped ? cw / 3 + 12 : 12);
      close(page.referenceLandscapePanelX(), isLayoutSwapped ? 12 : cw * 2/3 + 12);
      const panelWidth = cw/3 - 24;
      close(isLayoutSwapped ? page.referenceLandscapePanelX() + panelWidth + 24 : half[0] + half[2] + 24,
        isLayoutSwapped ? half[0] : page.referenceLandscapePanelX());
      close(half[4] / half[5], ar);
      assert.ok(half[4] <= half[2] && half[5] <= ch);
      close(half[1], 40);
      close(half[1] + half[3], ch);
      assert.ok(half[5] <= half[3], 'media stays inside the full-height landscape viewport');
      if (ar === 9/16) close(half[1] + (half[3] + half[5]) / 2, ch);
      assert.equal(page.referenceIntroScrollOffset(30), 30, 'landscape intro scrolls independently');
      Object.assign(page, { fs: true, fsLerpDir: 2, fsLerpSnapVW: cw, fsLerpSnapVH: ch });
      for (let step=0; step<=100; step++) {
        page.fsPanProgress = step/100;
        const rect = [page.ovRectX(), page.ovRectY(), page.ovRectW(), page.ovRectH(), page.ovVideoW(), page.ovVideoH()];
        rect.forEach((v,i) => close(v, half[i] + ([0,0,cw,ch,cw,ch][i] - half[i])*step/100));
      }
    }
  }
  }
  }
  for (const value of ['right', 'left', 'invalid']) {
    page.landscapePlaybackSide = value;
    page.onLandscapePlaybackSideChanged();
    assert.equal(page.isLayoutSwapped, value === 'right');
  }
}
verifyLandscape(p);
function verifyLandscapeResize(page) {
  for (const isLayoutSwapped of [false, true]) {
    for (const cw of [600, 850, 1000, 1400]) {
      Object.assign(page, { cw, ch: 625, ar: 16/9, isLs: true, fs: false, referenceLayout: true,
        isLayoutSwapped, referenceLandscapePlayerRatio: 2/3, referenceLandscapeResizeStart: 2/3,
        referenceLandscapeExpandProgress: 0, isAnimatingToFS: false,
        cardMargin: 12, navIndicatorHeight: 0, referenceSafeTop: () => 40 });
      let last = page.referenceLandscapePlayerWidth();
      for (let step = 1; step <= 20; step++) {
        page.referenceLandscapeResize((isLayoutSwapped ? -1 : 1) * step * 5);
        const width = page.referenceLandscapePlayerWidth();
        assert.ok(width >= last && width - last <= 5.000001, 'resize follows each drag frame');
        last = width;
        const introEdge = page.referenceLandscapePanelX() + (isLayoutSwapped ? page.referenceLandscapePanelWidth() : 0);
        const handleX = geometry.exports.splitHandleX(page.referenceLandscapePanelX(),
          page.referenceLandscapePanelWidth(), isLayoutSwapped);
        close(handleX + 16, introEdge);
        const visibleGripX = handleX + 14 + (isLayoutSwapped ? -2 : 2);
        close(isLayoutSwapped ? visibleGripX + 4 : visibleGripX, introEdge);
        close(page.referenceLandscapeMediaWidth() / page.referenceLandscapeMediaHeight(), 16/9);
        const margin = page.safeCM() * (1 - page.referenceLandscapeExpandProgress);
        close(isLayoutSwapped ? page.referenceLandscapePanelX() + page.referenceLandscapePanelWidth() + margin + page.safeCM() :
          page.referenceLandscapePlayerX() + page.referenceLandscapeViewportWidth() + margin + page.safeCM(),
          isLayoutSwapped ? page.referenceLandscapePlayerX() : page.referenceLandscapePanelX());
      }
      for (const delta of [-10000, 10000, -50, 50, 0]) {
        page.referenceLandscapeResize(delta);
        const width = page.referenceLandscapePlayerWidth();
        assert.ok(width >= Math.min(280, cw*0.4));
        assert.ok(width <= cw);
        assert.ok(page.referenceLandscapePanelWidth() + 24 >= Math.min(220, cw*0.3));
      }
      close(page.referenceLandscapePlayerWidth(), cw*2/3);
      page.referenceLandscapeResize(50);
      const ratio = page.referenceLandscapePlayerRatio;
      page.fs = true; page.referenceLandscapeResize(200);
      close(page.referenceLandscapePlayerRatio, ratio);
      page.fs = false; page.isLs = false; page.referenceLandscapeResize(200);
      close(page.referenceLandscapePlayerRatio, ratio);
    }
  }
  page.referenceLandscapePlayerRatio = 2/3;
}
verifyLandscapeResize(p);
const resizePages = [new context.exports.Page()];
function verifyRelatedRatio(Page) {
  for (const isLayoutSwapped of [false, true]) {
    let params;
    const source = new Page();
    Object.assign(source, { referenceLandscapePlayerRatio: 0.57, isLayoutSwapped,
      getUIContext: () => ({ getRouter: () => ({ pushUrl: options => { params = options.params; return Promise.resolve(); } }) }) });
    for (const ratio of [0.57, 0.73, 0.42]) {
      source.referenceLandscapePlayerRatio = ratio;
      source.onRelatedVideoClick({ id: 'new-video', title: 'Next video' });
      const next = new Page();
      next.referenceLandscapePlayerRatio = 2/3;
      next.referenceLandscapeRestoreRatio(params.landscapePlayerRatio);
      close(next.referenceLandscapePlayerRatio, ratio);
      next.referenceLandscapePlayerRatio = 0.65;
      close(source.referenceLandscapePlayerRatio, ratio, 'back navigation retains the previous page split');
    }
    for (const invalid of [undefined, null, '0.7', NaN, Infinity, -1, 0, 1]) {
      source.referenceLandscapeRestoreRatio(invalid);
      close(source.referenceLandscapePlayerRatio, 0.42);
    }
  }
}
verifyRelatedRatio(context.exports.Page);
async function verifyResizeFullscreen(page) {
  for (const isLayoutSwapped of [false, true]) {
    for (const ar of [16/9, 2.4, 1, 9/16, 3/4]) {
      Object.assign(page, { cw: 1000, ch: 625, ar, isLs: true, fs: false, isAnimatingToFS: false,
        referenceLayout: true, referenceLandscapePlayerRatio: 0.64, referenceLandscapeExpandProgress: 0,
        isLayoutSwapped, cardMargin: 12, navIndicatorHeight: 8, referenceSafeTop: () => 40,
        getUIContext: () => ({ animateTo: (_options, action) => action() }) });
      const direction = isLayoutSwapped ? -1 : 1;
      page.referenceLandscapeBeginResize();
      const origin = [page.referenceLandscapePlayerX(), page.referenceLandscapeViewportWidth(), page.referenceLandscapeAreaTop()];
      let previous = origin;
      for (let step = 0; step <= 100; step++) {
        page.referenceLandscapeResize(direction * step * 3.6);
        const next = [page.referenceLandscapePlayerX(), page.referenceLandscapeViewportWidth(), page.referenceLandscapeAreaTop()];
        next.forEach((v, i) => assert.ok(Number.isFinite(v) && Math.abs(v - previous[i]) < 10));
        close(page.referenceLandscapeMediaWidth()/page.referenceLandscapeMediaHeight(), ar);
        previous = next;
      }
      close(page.referenceLandscapePlayerX(), 0);
      close(page.referenceLandscapeViewportWidth(), 1000);
      close(page.referenceLandscapeAreaTop(), 0);
      close(page.referenceLandscapeAreaHeight(), 625);
      // Reversal in the same gesture returns along the same geometry timeline.
      page.referenceLandscapeResize(0);
      [page.referenceLandscapePlayerX(), page.referenceLandscapeViewportWidth(), page.referenceLandscapeAreaTop()]
        .forEach((v, i) => close(v, origin[i]));
      await page.referenceLandscapeFinishResize(direction * 230); // only 41% into expansion
      close(page.referenceLandscapeExpandProgress, 0);
      assert.equal(page.fs, false);
      page.referenceLandscapePlayerRatio = 0.64;
      page.referenceLandscapeBeginResize();
      page.referenceLandscapeResize(direction * 310);
      await page.referenceLandscapeFinishResize(0, true);
      close(page.referenceLandscapePlayerRatio, 0.64);
      close(page.referenceLandscapeExpandProgress, 0);
      let entered = 0;
      page.enterFullscreenAnimated = async () => { entered++; assert.ok(page.referenceLandscapeExpandProgress >= 0.62); page.fs = true; };
      page.referenceLandscapeBeginResize();
      await page.referenceLandscapeFinishResize(direction * 310);
      assert.equal(entered, 1);
      assert.equal(page.fs, true);
      close(page.referenceLandscapePlayerRatio, 0.64);
      close(page.referenceLandscapeExpandProgress, 0);
      await page.referenceLandscapeFinishResize(0, true); // late cancel from handle unmount
      close(page.referenceLandscapePlayerRatio, 0.64);
    }
  }
}
if (fs.existsSync(compiledFile)) {
  const compiled = fs.readFileSync(compiledFile, 'utf8');
  // Logical geometry can be correct while implicit per-node animations make
  // the rendered Surface trail the divider. Check emitted animation policies.
  const parsed = ts.createSourceFile('VideoPlayerPage.ts', compiled, ts.ScriptTarget.Latest, true);
  const policies = [];
  function collectAnimations(node, inPlayer = false) {
    const inside = inPlayer || (ts.isMethodDeclaration(node) && node.name.getText(parsed) === 'buildPlayerOverlay');
    if (inside && ts.isCallExpression(node) && node.expression.getText(parsed) === 'globalThis.Context.animation') {
      const argument = node.arguments[0]?.getText(parsed);
      if (argument && argument !== 'null' && argument !== 'undefined') policies.push(argument);
    }
    ts.forEachChild(node, child => collectAnimations(child, inside));
  }
  collectAnimations(parsed);
  assert.equal(policies.length, 4, 'player slot, both Surfaces and controls must all share gesture animation');
  for (const isLs of [false, true]) for (const fs of [false, true]) {
    for (const expression of policies) {
      const policy = vm.runInNewContext(`(function() { return (${expression}); })`, { Curve: { EaseOut: 0 } });
      assert.equal(policy.call({ referenceLayout: true, isLs, fs, fullscreenRotationTransition: false }), undefined,
        'reference player must use direct drag updates and the shared release/fullscreen animateTo');
      assert.ok([120, 300].includes(policy.call({ referenceLayout: false, fullscreenRotationTransition: false }).duration));
    }
  }
  const names = ['closePlaybackOptionPanel', 'onDanmakuComposerChanged', 'landscapeDanmakuComposerHeight', 'danmakuComposerBottomInset', 'referenceLandscapeAreaHeight', 'referenceLandscapePlayerX', 'referenceLandscapePanelX', 'onLandscapePlaybackSideChanged', 'referenceHalfScreenControlsActive', 'safeCM', 'referenceLandscapeViewportWidth', 'referenceLandscapePlayerWidth', 'referenceLandscapeMediaWidth', 'referenceLandscapeMediaHeight',
    'referenceLandscapeResize', 'referenceLandscapePanelWidth', 'referenceLandscapeAreaTop',
    'referenceLandscapeBeginResize', 'referenceLandscapeFinishResize', 'referenceLandscapeRestoreRatio', 'onRelatedVideoClick',
    'referenceIntroScrollOffset', 'ovRectX', 'ovRectY', 'ovRectW', 'ovRectH', 'ovVideoW', 'ovVideoH'];
  const bodies = names.map(name => {
    const start = Math.max(compiled.indexOf(`    private ${name}(`), compiled.indexOf(`    private async ${name}(`));
    assert.ok(start >= 0, `CompileArkTS lost ${name}`);
    const end = compiled.indexOf('\n    }', start);
    return compiled.slice(start, end + 6);
  }).join('\n');
  const runtime = { ...geometry.exports, exports: {}, clearTimeout, Curve: { EaseOut: 'ease-out' }, KeyboardAvoidMode: { NONE: 4 } };
  vm.runInNewContext(ts.transpileModule(`export class Page { ${bodies} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, runtime);
  verifyLandscape(new runtime.exports.Page());
  verifyLandscapeResize(new runtime.exports.Page());
  resizePages.push(new runtime.exports.Page());
  verifyRelatedRatio(runtime.exports.Page);
  verifyHalfScreenControls(new runtime.exports.Page());
  verifyComposer(new runtime.exports.Page());
  verifyOptionPanelBack(new runtime.exports.Page());
  console.log('Compiled ArkTS: landscape split, aspect ratios, independent scrolling and fullscreen return passed.');
}
Promise.all(resizePages.map(verifyResizeFullscreen)).then(() => {
  console.log('Source and compiled ArkTS: left/right fullscreen drag frames, reversal, threshold, cancel and return ratio passed.');
}).catch(error => { console.error(error); process.exitCode = 1; });
