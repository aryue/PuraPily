const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const page = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
const names = ['onBackPress', 'onOverlayBack_', 'toggleLock'];
const methods = names.map(name => {
  const method = page.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name);
  assert.ok(method, `compiled ${name} exists`);
  return method.getText(ast);
}).join('\n');
const context = { exports: {}, logInfo() {}, $r: x => x, clearTimeout: id => cleared.push(id) };
let cleared = [];
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
for (const route of ['onBackPress', 'onOverlayBack_']) {
  for (const fullscreen of [false, true]) {
    for (const unlockVisible of [false, true]) {
      const p = new context.exports.Page();
      let fullscreenExits = 0, exits = 0, resets = 0, hints = [];
      cleared = [];
      Object.assign(p, { lk: true, fs: fullscreen, ub: unlockVisible, cv: false, ubt: 42, ovBackTs_: 0,
        cancelDelayHide() {}, resetCT() { resets++; }, sBH(_icon, text) { hints.push(text); },
        closePlaybackOptionPanel: () => false,
        // 共享元素返回（开关关闭/未走 morph）不接管：桩返回 false，后续返回语义必须保持原样
        beginReturnCoverMorph: () => false,
        toggleFS() { fullscreenExits++; this.fs = false; }, goBack() { exits++; } });
      const result = p[route]();
      if (route === 'onBackPress') assert.equal(result, true, 'locked back must be consumed');
      assert.equal(p.lk, false);
      assert.equal(p.fs, fullscreen, 'unlock must preserve fullscreen');
      assert.equal(p.cv, true, 'unlock restores playback controls');
      assert.equal(p.ub, false);
      assert.equal(p.ubt, -1);
      assert.deepEqual(cleared, [42], 'unlock cancels its pending hide timer');
      assert.deepEqual(hints, ['已解锁']);
      assert.equal(resets, 1);
      assert.equal(fullscreenExits, 0);
      assert.equal(exits, 0);
      const next = p[route]();
      if (fullscreen) assert.equal(fullscreenExits, 1, 'next back exits fullscreen');
      else if (route === 'onBackPress') assert.equal(next, false, 'next back permits normal route return');
      else assert.equal(exits, 1, 'next overlay back returns normally');
    }
  }
}
// 共享元素返回：beginReturnCoverMorph 接管时，系统 Back 必须被消费（否则会直接 pop，收回动画不会播）
{
  const p = new context.exports.Page();
  Object.assign(p, { lk: false, fs: false, commentSheetVisible: false, floatingMorph: false,
    showDanmakuSheet: false, referenceSubtitlePanelOpen: false, referenceLandscapeDanmakuOpen: false,
    closePlaybackOptionPanel: () => false, mp: false, commentThread: null, referenceFeedComments: false,
    referenceFeed: false, isLightsOff: false, beginReturnCoverMorph: () => true });
  assert.equal(p.onBackPress(), true, 'morph return must consume system back');
}
console.log('PASS: compiled system/overlay back unlocks first, restores controls and preserves subsequent back behavior (morph return consumes back).');
