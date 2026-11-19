const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');
function between(start, end) {
  const from = source.indexOf(start);
  assert.ok(from >= 0, start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(to > from, end);
  return source.slice(from, to);
}
const methods = [
  between('  private fullscreenTargetLandscape():', '  // ⭐ 退出全屏后恢复系统栏'),
  between('  private snapshotPreFsBranch():', '  /** ⭐ 关灯+竖屏非全屏'),
  between('  private contentBranchKey():', '  /** ⭐ 转场状态翻转'),
  between('  private manageSB(', '  async initW()'),
  between('  private async restoreOrientationOnly():', '  private restoreFullscreenSource():'),
  between('  private restoreFullscreenSource():', '  // ⭐ 带动画进入全屏'),
  between('  private applyPlaybackWindowSize(', '  /** 根据新的窗口尺寸'),
  between('  private referenceSetFeed(value:', '  private referenceStopFeedMotion()'),
  between('  private portraitPlateByArea():', '  /**\n   * ⭐ 全屏相关的圆角')
].join('\n');
const context = { exports: {}, window: { Orientation: { AUTO_ROTATION: 0, PORTRAIT: 1, AUTO_ROTATION_LANDSCAPE: 2, AUTO_ROTATION_PORTRAIT: 3 } },
  AppStorage: { setOrCreate() {} },
  setTimeout, clearTimeout, logInfo() {}, logWarn() {}, Date, Math };
const windowControls = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/services/PlaybackWindow.ets'), 'utf8')
  .replace(/^import .*$/gm, '');
const viewport = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/utils/PlaybackViewport.ets'), 'utf8');
vm.runInNewContext(ts.transpileModule(`${windowControls}
${viewport}
export class Page {
  playbackWindow_ = new PlaybackWindow();
  ${methods}
}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function test(feed) {
  const p = new context.exports.Page();
  const orientations = [];
  const windowEvents = [];
  p.playbackWindow_.applyBars = () => { windowEvents.push('bars'); };
  let sizeListener;
  Object.assign(p, { referenceAlive: true, playerPageVisible: true, referenceLayout: true, referenceFeed: feed, referenceFeedProgress: feed ? 1 : 0,
    referenceFeedComments: false, referenceInfoHidden: true, referencePanelOffset: -23,
    isLs: false, isLandscapeVertical: false, cw: 440, ch: 744, ar: 16 / 9,
    fs: false, fsEntering: false, isAnimatingToFS: true, rotationInProgress: false,
    fsLerpSnapX: 0, fsLerpSnapY: 39, fsLerpSnapW: 440, fsLerpSnapH: 247.5,
    fsLerpSnapVW: 440, fsLerpSnapVH: 247.5,
    fullscreenDeviceOrientation: { start() {}, stop() {} },
    mw: { getPreferredOrientation: () => 42, disableLandscapeMultiWindow: async () => { windowEvents.push('leave landscape'); },
      setPreferredOrientation: async orientation => { orientations.push(orientation); },
      on: (event, callback) => { assert.equal(event, 'windowSizeChange'); sizeListener = callback; },
      off: (event, callback) => { assert.equal(event, 'windowSizeChange'); assert.equal(callback, sizeListener); sizeListener = undefined; } },
    getUIContext: () => ({ px2vp: px => px / 3 }),
    applyOrientationState(w, h) { this.isLs = w > h; this.commitFullscreenRotationLayout(); },
    referenceAreaTop: () => 39, referenceAreaHeight: () => 247.5,
    updateIsLandscapeVertical() {}, updateVideoSize() {}, initOverlayRectSync() {}, resetFullscreenVideo() {},
    loadReferenceIntroExtras() {}
  });
  p.snapshotPreFsBranch();
  p.prepareFullscreenEnvironment = async () => {
    // A resolved orientation API must not be mistaken for a resolved viewport change.
    setTimeout(() => {
      p.cw = 744; p.ch = 440; p.isLs = true;
      p.commitFullscreenRotationLayout();
    }, 40);
  };
  const entering = p.rotateReferenceFullscreen(true, true);
  await pause(5);
  assert.equal(p.fsEntering, true, 'hold the original picture until the window really rotates');
  assert.equal(p.contentBranchKey(), 'portrait', 'do not mount landscape details during rotation');
  assert.equal(p.ovRectW(), 440); assert.equal(p.ovRectY(), 39);
  assert.equal(p.ovVideoW(), 440); assert.equal(p.ovVideoH(), 247.5);
  // Delayed panel gestures cannot turn half-screen details into the feed.
  p.referenceSetFeed(!feed);
  assert.equal(p.referenceFeed, feed);
  await entering;
  assert.equal(p.fs, true); assert.equal(p.fsEntering, false);
  assert.equal(p.referenceFeed, feed); assert.equal(p.fsLerpDir, 0);

  // Simulate unrelated state changes while fullscreen; returning restores the captured source.
  p.referenceFeed = !feed; p.referencePanelOffset = 0; p.referenceInfoHidden = false;
  windowEvents.length = 0;
  p.mw.setPreferredOrientation = async orientation => {
    orientations.push(orientation);
    windowEvents.push('request portrait');
    setTimeout(() => {
      assert.equal(typeof sizeListener, feed ? 'undefined' : 'function');
      if (sizeListener) {
        sizeListener({ width: 2232, height: 1320 });
        assert.equal(p.fs, true, 'ignore landscape window sizes while returning to portrait');
        sizeListener({ width: 1320, height: 2232 });
        assert.equal(p.fs, false, 'hand off when the window reports its portrait size');
        assert.equal(p.ovRectY(), 39, 'land directly below the status bar');
        assert.equal(p.ovRectW(), 440);
        assert.equal(p.ovRectH(), 247.5, 'land at the destination playback size');
      }
      if (!sizeListener) p.applyPlaybackWindowSize(440, 744);
      windowEvents.push('portrait layout');
      p.manageSB(true);
      assert.deepEqual(windowEvents, ['request portrait', 'portrait layout'], 'window mode and bars stay fixed while rotation is active');
    }, 40);
  };
  p.isAnimatingToFS = true;
  const exiting = p.rotateReferenceFullscreen(false, false);
  await pause(5);
  assert.equal(p.fs, true, 'do not show landscape detail layout before portrait viewport arrives');
  assert.equal(p.fsEntering, true);
  await exiting;
  assert.equal(p.fs, false); assert.equal(p.referenceFeed, feed);
  assert.equal(p.referenceFeedProgress, feed ? 1 : 0);
  assert.equal(p.referencePanelOffset, -23); assert.equal(p.referenceInfoHidden, true);
  assert.equal(p.fsPanProgress, 0); assert.equal(p.isAnimatingToFS, false);
  assert.equal(sizeListener, undefined, 'remove the listener after the rotation');
  assert.deepEqual(orientations, [42], 'restore the original policy in one request');
  assert.deepEqual(windowEvents, ['request portrait', 'portrait layout', 'leave landscape', 'bars']);
}
(async () => {
  const { fullscreenEntryProgress, fullscreenViewportExtent, fullscreenSurfaceExtent, fullscreenCornerRadius } = context.exports;
  assert.equal(fullscreenEntryProgress(0.3, 0.5), 0);
  assert.equal(fullscreenEntryProgress(0.75, 0.5), 0.5);
  assert.equal(fullscreenEntryProgress(1, 1), 1);
  assert.equal(fullscreenViewportExtent(744, 440, 500, 1, 0.75, 0.5), 622);
  assert.equal(fullscreenViewportExtent(744, 440, 500, 2, 0.25, 0), 516);
  assert.equal(fullscreenSurfaceExtent(440, 744, true, 2, 0.25, 0), 516);
  assert.equal(fullscreenSurfaceExtent(0, 744, false, 0, 0, 0), 1);
  assert.equal(fullscreenCornerRadius(0, 20, true, 1, 0.75, 0.5), 10);
  assert.equal(fullscreenCornerRadius(0, 20, true, 2, 0.25, 0), 15);
  const directionPage = new context.exports.Page();
  const requested = [];
  Object.assign(directionPage, { referenceLayout: true, isPcDevice: false,
    fullscreenDeviceOrientation: { start() {} },
    mw: { enableLandscapeMultiWindow: async () => {}, setPreferredOrientation: async value => requested.push(value) } });
  for (const isLandscape of [false, true]) for (const ar of [9/16, 3/4, 1, 16/9]) {
    Object.assign(directionPage, { ar, isLs: isLandscape, fullscreenSource: { isLandscape } });
    const expected = isLandscape || ar >= 1;
    assert.equal(directionPage.fullscreenTargetLandscape(), expected);
    await directionPage.prepareFullscreenEnvironment();
    assert.equal(requested.at(-1), expected ? 2 : 3, 'landscape half-screen portrait media stays landscape in fullscreen');
  }
  const compiledFile = path.resolve(__dirname, '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts');
  if (fs.existsSync(compiledFile)) {
    const compiled = fs.readFileSync(compiledFile, 'utf8');
    const bodies = ['fullscreenTargetLandscape', 'prepareFullscreenEnvironment'].map(name => {
      const start = Math.max(compiled.indexOf(`    private ${name}(`), compiled.indexOf(`    private async ${name}(`));
      assert.ok(start >= 0, `CompileArkTS must retain ${name}`);
      return compiled.slice(start, compiled.indexOf('\n    }', start) + 6);
    }).join('\n');
    vm.runInNewContext(ts.transpileModule(`export class CompiledPage { ${bodies} }`, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, context);
    const compiledPage = new context.exports.CompiledPage();
    Object.assign(compiledPage, { referenceLayout: true, isPcDevice: false, isLs: true,
      ar: 9/16, fullscreenSource: { isLandscape: true }, mw: directionPage.mw,
      playbackWindow_: directionPage.playbackWindow_,
      fullscreenDeviceOrientation: directionPage.fullscreenDeviceOrientation });
    await compiledPage.prepareFullscreenEnvironment();
    assert.equal(requested.at(-1), 2, 'compiled portrait video fullscreen must preserve landscape');
  }
  await test(false);
  await test(true);
  const p = new context.exports.Page();
  let alive = true;
  const settling = p.playbackWindow_.waitForStableViewport(() => true, () => alive);
  alive = false;
  assert.equal(await settling, false, 'an exiting page must stop waiting for a stable viewport');
  const applied = [];
  Object.assign(p, { referenceLayout: true, isPcDevice: false,
    isLs: true,
    getUIContext: () => ({ getHostContext: () => ({}) }),
    fullscreenDeviceOrientation: { stop() {}, returnLandscape: (policy, current) => {
      assert.equal(policy, 42);
      // current 是"非全屏态方向"（fullscreenSource.isLandscape），不是全屏中的 isLs：
      // 本用例从竖屏进入（isLandscape=false），锁定开时手机端必须据此回竖屏。
      assert.equal(current, false, 'current must be the non-fullscreen direction');
      return true;
    } },
    fullscreenSource: { isLandscape: false, orientation: 42 },
    mw: { disableLandscapeMultiWindow: async () => {}, setPreferredOrientation: async value => { applied.push(value); } } });
  p.fullscreenRotationTransition = true;
  assert.equal(p.fullscreenReturnLandscape(), true, 'landscape posture overrides portrait entry geometry');
  await p.restoreOrientationOnly();
  assert.deepEqual(applied, [42], 'rotating exit restores auto orientation directly');
  p.fullscreenRotationTransition = false;
  await p.restoreOrientationOnly();
  assert.equal(applied.at(-1), 42, 'same-orientation exit must retain the original orientation policy');
  console.log('Fullscreen origin: real viewport wait, frozen geometry, detail/feed return and gesture isolation passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
