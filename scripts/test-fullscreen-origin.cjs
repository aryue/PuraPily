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
  between('  private snapshotPreFsBranch():', '  /** ⭐ 内容分支常驻渲染'),
  between('  private contentBranchKey():', '  /** ⭐ 转场状态翻转'),
  between('  private async restoreOrientationOnly():', '  private restoreFullscreenSource():'),
  between('  private restoreFullscreenSource():', '  // ⭐ 带动画进入全屏'),
  between('  private referenceSetFeed(value:', '  private referenceStopFeedMotion()'),
  between('  private ovRectX():', '  /**\n   * ⭐ 全屏相关的圆角')
].join('\n');
const context = { exports: {}, window: { Orientation: { AUTO_ROTATION: 0, PORTRAIT: 1, AUTO_ROTATION_LANDSCAPE: 2, AUTO_ROTATION_PORTRAIT: 3 } },
  setTimeout, clearTimeout, logInfo() {}, logWarn() {}, Date, Math };
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function test(feed) {
  const p = new context.exports.Page();
  const orientations = [];
  Object.assign(p, { referenceLayout: true, referenceFeed: feed, referenceFeedProgress: feed ? 1 : 0,
    referenceFeedComments: false, referenceInfoHidden: true, referencePanelOffset: -23,
    isLs: false, isLandscapeVertical: false, cw: 440, ch: 744, ar: 16 / 9,
    fs: false, fsEntering: false, isAnimatingToFS: true, rotationInProgress: false,
    fsLerpSnapX: 0, fsLerpSnapY: 39, fsLerpSnapW: 440, fsLerpSnapH: 247.5,
    fsLerpSnapVW: 440, fsLerpSnapVH: 247.5,
    mw: { getPreferredOrientation: () => 42, setPreferredOrientation: async orientation => { orientations.push(orientation); } },
    updateIsLandscapeVertical() {}, updateVideoSize() {}, initOverlayRectSync() {}, manageSB() {}, resetFullscreenVideo() {},
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
  const entering = p.rotateReferenceFullscreen(true);
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
  p.restoreOrientationOnly = async () => {
    setTimeout(() => {
      p.cw = 440; p.ch = 744; p.isLs = false;
      p.commitFullscreenRotationLayout();
    }, 40);
  };
  p.isAnimatingToFS = true;
  const exiting = p.rotateReferenceFullscreen(false);
  await pause(5);
  assert.equal(p.fs, true, 'do not show landscape detail layout before portrait viewport arrives');
  assert.equal(p.fsEntering, true);
  await exiting;
  assert.equal(p.fs, false); assert.equal(p.referenceFeed, feed);
  assert.equal(p.referenceFeedProgress, feed ? 1 : 0);
  assert.equal(p.referencePanelOffset, -23); assert.equal(p.referenceInfoHidden, true);
  assert.equal(p.fsPanProgress, 0); assert.equal(p.isAnimatingToFS, false);
  assert.equal(orientations.at(-1), 42, 'restore the original window orientation policy');
}
(async () => {
  const directionPage = new context.exports.Page();
  const requested = [];
  Object.assign(directionPage, { referenceLayout: true, isPcDevice: false,
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
      ar: 9/16, fullscreenSource: { isLandscape: true }, mw: directionPage.mw });
    await compiledPage.prepareFullscreenEnvironment();
    assert.equal(requested.at(-1), 2, 'compiled portrait video fullscreen must preserve landscape');
  }
  await test(false);
  await test(true);
  const p = new context.exports.Page();
  const applied = [];
  Object.assign(p, { referenceLayout: true, isPcDevice: false,
    fullscreenSource: { isLandscape: false, orientation: 42 },
    mw: { disableLandscapeMultiWindow: async () => {}, setPreferredOrientation: async value => { applied.push(value); } } });
  p.fullscreenRotationTransition = true;
  await p.restoreOrientationOnly();
  assert.equal(applied.at(-1), 1, 'rotate to the source viewport before restoring auto orientation');
  p.fullscreenRotationTransition = false;
  await p.restoreOrientationOnly();
  assert.equal(applied.at(-1), 42, 'same-orientation exit must retain the original orientation policy');
  console.log('Fullscreen origin: real viewport wait, frozen geometry, detail/feed return and gesture isolation passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
