const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.resolve(__dirname, '../entry/src/main/ets/pages/ProfilePage.ets'), 'utf8');
function method(name) {
  const start = source.search(new RegExp(`^  private (?:async )?${name}\\(`, 'm'));
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4);
}
const stored = new Map();
const shared = new Map();
let failFlush = false;
const context = { exports: {}, logError() {}, AppStorage: { setOrCreate: (key, value) => shared.set(key, value) },
  preferences: { getPreferences: async (_context, name) => {
    assert.equal(name, 'my_app_settings', 'use the same preferences as HomePage and VideoPlayerPage');
    return { put: async (key, value) => stored.set(key, value), flush: async () => { if (failFlush) throw new Error('flush failed'); } };
  } } };
vm.runInNewContext(ts.transpileModule(`export class Page { ${['saveApiSource', 'settingLabels', 'selectSetting', 'saveLandscapePlaybackSide'].map(method).join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
(async () => {
  const page = new context.exports.Page();
  let menu;
  let choice = 0;
  page.getUIContext = () => ({ getHostContext: () => ({}), getPromptAction: () => ({
    showToast() {}, showActionMenu: async options => { menu = options; return { index: choice }; }
  }) });
  for (const [key, options] of [['recommendApiSource', ['App', 'Web']], ['danmakuApiSource', ['grpc', 'xml']]]) {
    for (const value of options) {
      await page.saveApiSource(key, value);
      assert.equal(stored.get(key), value);
      assert.equal(shared.get(key), value);
    }
  }
  failFlush = true;
  await page.saveApiSource('recommendApiSource', 'App');
  assert.equal(shared.get('recommendApiSource'), 'Web', 'failed persistence must not change the active source');
  failFlush = false;
  const saved = [];
  page.saveApiSource = (key, value) => saved.push([key, value]);
  for (const [method, key, values] of [['recommend', 'recommendApiSource', ['App', 'Web']], ['danmaku', 'danmakuApiSource', ['grpc', 'xml']]]) {
    for (choice of [0, 1]) {
      await page.selectSetting(method, choice);
      await new Promise(resolve => setImmediate(resolve));
      assert.deepEqual(saved.at(-1), [key, values[choice]]);
      assert.equal(page.settingLabels(method).length, 2);
    }
    const count = saved.length;
    choice = -1;
    await page.selectSetting(method, choice);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(saved.length, count, 'cancel must preserve the source');
  }
  for (const side of ['left', 'right']) {
    await page.saveLandscapePlaybackSide(side);
    assert.equal(page.landscapePlaybackSide, side);
    assert.equal(stored.get('landscapePlaybackSide'), side);
  }
  await page.saveLandscapePlaybackSide('invalid');
  assert.equal(page.landscapePlaybackSide, 'right');
  failFlush = true;
  await page.saveLandscapePlaybackSide('left');
  assert.equal(page.landscapePlaybackSide, 'right', 'failed persistence must preserve current side');
  failFlush = false;
  const sides = [];
  page.saveLandscapePlaybackSide = value => sides.push(value);
  for (choice of [0, 1, -1]) {
    await page.selectSetting('side', choice);
    await new Promise(resolve => setImmediate(resolve));
  }
  assert.deepEqual(sides, ['left', 'right']);
  console.log('Landscape default side: saved values, invalid inputs, failure and menu cancellation passed.');
  console.log('Settings sources: shared persistence, immediate source update, save failure, menu mapping and cancellation passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
