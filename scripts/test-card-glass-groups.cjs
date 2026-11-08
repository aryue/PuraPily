const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiledRoot = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const restored = new Map(), saved = new Map();
const context = {
  exports: {},
  AppStorage: { setOrCreate: (key, value) => restored.set(key, value), has: key => restored.has(key),
    get: key => restored.get(key) },
  preferences: { getPreferences: async () => ({ get: async (key, fallback) => saved.has(key) ? saved.get(key) : fallback, put: async (key, value) => saved.set(key, value), flush: async () => {} }) },
  restoreLoginCredentials: async () => {}, logWarn() {},
  ConfigurationConstant: { ColorMode: { COLOR_MODE_DARK: 0, COLOR_MODE_LIGHT: 1 } }
};
const source = fs.readFileSync(compiledRoot + 'utils/ReferenceAppearance.ts', 'utf8').replace(/^import .*;\r?\n/gm, '');
vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);
const host = { getApplicationContext: () => ({ setColorMode() {} }) };
(async () => {
  await context.exports.initializeReferenceAppearance(host);
  assert.equal(restored.get('videoCardEdgeLight'), false);
  assert.equal(restored.get('videoCardGlassThickness'), 'thin');
  assert.equal(restored.get('otherCardGlassEnabled'), true);
  assert.equal(restored.get('otherCardGlassThickness'), 'thick');
  assert.equal(restored.get('videoCardGlassInvert'), false, 'video inversion defaults off');
  assert.equal(restored.get('otherCardGlassInvert'), false, 'other-card inversion defaults off');
  // Simulate a fresh launch with deliberately opposite settings in each group.
  for (const [key, value] of Object.entries({
    videoCardEdgeLight: true, videoCardGlassTint: false, videoCardGlassThickness: 'regular',
    videoCardGlassInvert: true, otherCardGlassEnabled: false, otherCardGlassTint: true,
    otherCardGlassThickness: 'ultra-thin', otherCardGlassInvert: false
  })) saved.set(key, value);
  restored.clear();
  await context.exports.initializeReferenceAppearance(host);
  for (const key of ['videoCardEdgeLight', 'videoCardGlassTint', 'videoCardGlassThickness', 'videoCardGlassInvert',
    'otherCardGlassEnabled', 'otherCardGlassTint', 'otherCardGlassThickness', 'otherCardGlassInvert']) {
    assert.equal(restored.get(key), saved.get(key), key + ' restores independently');
  }
  saved.set('videoCardGlassThickness', 'ultra-thick'); saved.set('otherCardGlassThickness', 'thick');
  await context.exports.initializeReferenceAppearance(host);
  assert.equal(restored.get('videoCardGlassThickness'), 'ultra-thick');
  assert.equal(restored.get('otherCardGlassThickness'), 'thick');
  saved.set('videoCardGlassThickness', 'invalid'); saved.set('otherCardGlassThickness', 'invalid');
  await context.exports.initializeReferenceAppearance(host);
  assert.equal(restored.get('videoCardGlassThickness'), 'thin');
  assert.equal(restored.get('otherCardGlassThickness'), 'thick');
  // Ensure both setting groups survived ArkTS compilation, including their handlers.
  const profile = fs.readFileSync(compiledRoot + 'pages/ProfilePage.ts', 'utf8');
  for (const id of ['setting-video-card-edge-light', 'setting-video-card-glass-tint', 'setting-video-card-glass-invert',
    'setting-glass-thickness', 'setting-other-card-glass', 'setting-other-card-glass-tint',
    'setting-other-card-glass-invert', 'setting-other-card-glass-thickness']) assert.ok(profile.includes(id), id);
  assert.match(profile, /SettingsOptions.*otherGlass/);
  console.log('PASS: compiled independent glass settings: defaults, restart restoration, invalid values and both settings groups.');
})().catch(error => { console.error(error); process.exitCode = 1; });
