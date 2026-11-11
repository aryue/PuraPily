// Exercise the actual CompileArkTS exit method in both page lifecycle orders.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const source = fs.readFileSync(file, 'utf8');
const start = source.indexOf('    private async restoreS(');
const end = source.indexOf('    private async loadSM(', start);
assert.ok(start >= 0 && end > start);
const js = ts.transpileModule('export class Page {' + source.slice(start, end) + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

async function main() {
  const Orientation = { AUTO_ROTATION_RESTRICTED: 1, PORTRAIT: 2, AUTO_ROTATION_LANDSCAPE: 3, AUTO_ROTATION: 4 };
  let cases = 0;
  for (const landscape of [false, true]) {
    for (const hidden of [false, true]) {
      for (const lock of ['跟随系统', '锁定竖屏', '锁定横屏']) {
        for (const exitLast of [false, true]) {
          const storage = new Map([['isLandscape', landscape], ['hideStatusBar', hidden], ['screenOrientationLock', lock]]);
          let status, navigation, orientation;
          const mw = { async setPreferredOrientation(value) { orientation = value; } };
          const bars = { async setSystemBars(win, visible, nav) {
            assert.equal(win, mw); status = visible; navigation = nav;
          // 播放页退出还会恢复状态栏内容色（浅色黑字/深色白字），本用例只验显隐与方向。
          }, async setPlayerStatusBarContent() {}, async restoreThemeStatusBarContent() {} };
          const context = { exports: {}, AppStorage: {
            get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value)
          }, StatusBarUtils: bars, window: { Orientation } };
          vm.runInNewContext(js, context);
          const page = new context.exports.Page();
          // A cached player preference must not override the current global preference.
          Object.assign(page, { mw, sh_: !hidden, getUIContext: () => ({ getHostContext: () => ({}) }) });
          const homeShow = () => bars.setSystemBars(mw, !hidden, true);
          if (exitLast) { await homeShow(); await page.restoreS(); }
          else { await page.restoreS(); await homeShow(); }
          assert.equal(status, !hidden, JSON.stringify({ landscape, hidden, lock, exitLast }));
          assert.equal(navigation, true);
          assert.equal(orientation, { '跟随系统': 1, '锁定竖屏': 2, '锁定横屏': 3 }[lock]);
          cases++;
        }
      }
    }
  }
  const methods = [
    ['    private onTransitionFlip(', '    private onContentVisibleChange('],
    ['    private manageSB(', '    async initW(']
  ].map(([a, b]) => {
    const from = source.indexOf(a), to = source.indexOf(b, from);
    assert.ok(from >= 0 && to > from);
    return source.slice(from, to);
  }).join('\n');
  const state = new Map();
  const requests = [];
  const context = {
    exports: {}, AppStorage: { setOrCreate: (key, value) => state.set(key, value) },
    StatusBarUtils: { setSystemBars: (_win, status, navigation) => requests.push([status, navigation]) },
    setTimeout: callback => callback(), clearInterval() {}, Curve: { EaseOut: 0 }
  };
  vm.runInNewContext(ts.transpileModule('export class Page {' + methods + '}', {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const page = new context.exports.Page();
  Object.assign(page, { mw: {}, referenceAlive: true, playerPageVisible: true,
    referenceLayout: true, isLs: true, fs: false, sh_: false, isLightsOff: false,
    rotationInProgress: false, contentVisible: true, resetFullscreenVideo() {},
    onPlaybackViewportChanged() {}, getUIContext: () => ({ getHostContext: () => ({}), animateTo: (_options, callback) => callback() }) });
  for (const rotating of [false, true]) {
    page.rotationInProgress = rotating;
    for (const fullscreen of [false, true, false, true, false]) {
      page.fs = fullscreen;
      page.onTransitionFlip();
      assert.deepEqual(requests.at(-1), [!fullscreen, false], 'landscape half/full switching updates bars immediately');
      assert.equal(state.get('isFullscreen'), fullscreen, 'foreground recovery sees the actual fullscreen state');
    }
  }
  const count = requests.length;
  page.playerPageVisible = false;
  page.fs = true;
  page.onTransitionFlip();
  assert.equal(requests.length, count, 'hidden player cannot override the returning page');
  console.log(`PASS: ${cases} compiled player exit cases (orientation, preferences, lifecycle ordering).`);
  console.log('PASS: same-orientation half/full transitions, rotation callbacks, foreground flag and inactive player guard.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
