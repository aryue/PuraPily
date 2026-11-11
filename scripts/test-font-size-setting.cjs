const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const serviceSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/AppScaleService.ets'), 'utf8').replace(/\r\n/g, '\n');
const profile = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/ProfilePage.ets'), 'utf8').replace(/\r\n/g, '\n');
const ability = fs.readFileSync(path.join(root, 'entry/src/main/ets/entryability/EntryAbility.ets'), 'utf8').replace(/\r\n/g, '\n');

/** 去掉 import 行（类型注解会被转译抹掉，运行期只需要真正的依赖桩）。 */
function stripImports(source) {
  return source.split('\n').filter(line => !/^import\s/.test(line)).join('\n');
}

function loadService() {
  const harness = {
    exports: {},
    preferences: {
      store: new Map(),
      failFlush: false
    },
    display: { getDefaultDisplaySync: () => ({ densityPixels: 3 }) },
    deviceInfo: { sdkApiVersion: 26 },
    logInfo() {},
    logError() {}
  };
  harness.preferences.getPreferences = async () => ({
    get: async (key, fallback) => harness.preferences.store.has(key) ? harness.preferences.store.get(key) : fallback,
    put: async (key, value) => { harness.preferences.store.set(key, value); },
    flush: async () => { if (harness.preferences.failFlush) throw new Error('flush failed'); }
  });
  const context = vm.createContext(harness);
  vm.runInContext(ts.transpileModule(stripImports(serviceSource), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return harness;
}

/** 假 UIAbilityContext：config.fontSizeScale 是「系统倍率」，setFontSizeScale 记录下发序列。 */
function fakeContext(systemScale, applied, watchers) {
  return {
    config: { fontSizeScale: systemScale },
    getApplicationContext: () => ({
      setFontSizeScale(scale) { applied.push(scale); },
      onSystemConfigurationUpdated(cb) { watchers.push(cb); }
    })
  };
}

(async () => {
  const boot = loadService();
  const { AppScaleService, FONT_SCALE_MIN, FONT_SCALE_MAX, FONT_SCALE_STEP } = boot.exports;
  const applied = [];
  const watchers = [];
  const context = fakeContext(1.25, applied, watchers);

  // 1) 冷启动「跟随系统」：一次都不许调 setFontSizeScale（调了就永久脱离系统），系统倍率要留底。
  await AppScaleService.applyFontAtStartup(context);
  assert.deepEqual(applied, [], 'follow mode at cold start must not call setFontSizeScale');
  assert.equal(AppScaleService.currentSystemScale(), 1.25, 'system scale must be captured before any override');

  // 2) 冷启动自定义：在首帧前按保存的倍率下发。
  const saved = loadService();
  saved.preferences.store.set('fontSizeMode', 'custom');
  saved.preferences.store.set('appFontScale', 1.2);
  const applied2 = [];
  const ctx2 = fakeContext(1.25, applied2, []);
  await saved.exports.AppScaleService.applyFontAtStartup(ctx2);
  assert.deepEqual(applied2, [1.2], 'custom scale must be applied at startup');

  // 3) 运行中自定义 → 跟随系统：撤回不了 setFontSizeScale，只能下发系统倍率并自跟踪系统变化。
  const applied3 = [];
  const watchers3 = [];
  const svc3 = loadService();
  const ctx3b = fakeContext(1.25, applied3, watchers3);
  svc3.exports.AppScaleService.watchSystemFontScale(ctx3b);
  assert.equal(watchers3.length, 1, 'API 24+ must register the system configuration watcher');
  await svc3.exports.AppScaleService.applyFontAtStartup(ctx3b);
  svc3.exports.AppScaleService.applyFontSetting(ctx3b, false, 1.1);
  assert.deepEqual(applied3, [1.1], 'custom preset must be applied as-is');
  watchers3[0].onFontSizeScaleUpdated(1.4);
  assert.deepEqual(applied3, [1.1], 'custom mode must ignore system font changes');
  assert.equal(svc3.exports.AppScaleService.currentSystemScale(), 1.4,
    'custom mode still refreshes the cached system scale for a later switch back');
  svc3.exports.AppScaleService.applyFontSetting(ctx3b, true, 1.1);
  assert.deepEqual(applied3, [1.1, 1.4], 'switching back to follow must restore the latest system scale immediately');
  watchers3[0].onFontSizeScaleUpdated(1.6);
  assert.deepEqual(applied3, [1.1, 1.4, 1.6], 'follow-by-emulation must track later system changes');
  assert.equal(svc3.exports.AppScaleService.currentSystemScale(), 1.6);

  // 4) 低版本设备（无 onSystemConfigurationUpdated）不得注册，也不能因此报错。
  const oldSvc = loadService();
  oldSvc.deviceInfo.sdkApiVersion = 23;
  const oldWatchers = [];
  oldSvc.exports.AppScaleService.watchSystemFontScale(fakeContext(1, [], oldWatchers));
  assert.equal(oldWatchers.length, 0, 'pre-API-24 devices must skip the watcher');

  // 5) 持久化：跟随系统时仍保留上次自定义倍率，切回自定义能复用。
  const store = new Map();
  const persistSvc = loadService();
  await persistSvc.exports.AppScaleService.saveFontSetting(context, false, 1.2);
  assert.equal(persistSvc.preferences.store.get('fontSizeMode'), 'custom');
  assert.equal(persistSvc.preferences.store.get('appFontScale'), 1.2);
  await persistSvc.exports.AppScaleService.saveFontSetting(context, true, 1.2);
  assert.equal(persistSvc.preferences.store.get('fontSizeMode'), 'system', 'follow must be persisted as system');
  assert.equal(persistSvc.preferences.store.get('appFontScale'), 1.2, 'follow keeps the last custom ratio');
  const reloaded = await persistSvc.exports.AppScaleService.loadFontSetting(context);
  assert.equal(reloaded.followSystem, true);
  assert.equal(reloaded.scale, 1.2);
  assert.equal(store.size, 0);

  // 6) 滑条语义：0.8~2.5，0.05 一档。用户倍率必须吸附步长，否则滑条与落盘值来回差一档。
  assert.equal(FONT_SCALE_MIN, 0.8, 'slider min is 0.8x');
  assert.equal(FONT_SCALE_MAX, 2.5, 'slider max is 2.5x');
  assert.equal(FONT_SCALE_STEP, 0.05, 'slider step is 0.05x');

  // 6b) 落盘值被写坏（越界 / 非步长 / 浮点尾数）时夹住并吸附：用户倍率只允许 0.8~2.5，系统倍率不受此限制。
  const dirty = loadService();
  dirty.preferences.store.set('fontSizeMode', 'custom');
  dirty.preferences.store.set('appFontScale', 9);
  assert.equal((await dirty.exports.AppScaleService.loadFontSetting(context)).scale, 2.5);
  dirty.preferences.store.set('appFontScale', 0.2);
  assert.equal((await dirty.exports.AppScaleService.loadFontSetting(context)).scale, 0.8);
  dirty.preferences.store.set('appFontScale', 1.13);
  assert.equal((await dirty.exports.AppScaleService.loadFontSetting(context)).scale, 1.15,
    'off-step values snap to the slider grid');
  dirty.preferences.store.set('appFontScale', 0.8500000000000001);
  assert.equal((await dirty.exports.AppScaleService.loadFontSetting(context)).scale, 0.85,
    'floating point tails must not shift the slider by one step');

  // 6c) 进入自定义模式：跟随系统下实际生效的是系统倍率，不能沿用上次保存的自定义值
  //     （否则滑条显示 205% 而画面是 100%，且不会重新下发，画面永远不跟着走）。
  const seed = loadService();
  seed.exports.AppScaleService.captureSystemScale(fakeContext(1.3, [], []));
  assert.equal(seed.exports.AppScaleService.entryCustomScale(true, 2.1), 1.3,
    'entering custom from follow-system must start from the live system scale');
  assert.equal(seed.exports.AppScaleService.entryCustomScale(false, 2.1), 2.1,
    'already-custom keeps the current value');
  seed.exports.AppScaleService.captureSystemScale(fakeContext(1.13, [], []));
  assert.equal(seed.exports.AppScaleService.entryCustomScale(true, 2.1), 1.15,
    'seeded value must snap to the slider grid');
  seed.exports.AppScaleService.captureSystemScale(fakeContext(3.2, [], []));
  assert.equal(seed.exports.AppScaleService.entryCustomScale(true, 2.1), 2.5,
    'system scales above the slider range clamp to the max');

  // 6d) 运行中刷新系统倍率：只有从未下发过应用字号（= 引擎原生跟随）时才允许更新缓存，
  //     下发过之后 context.config 读到的是应用自己的倍率，不能当系统值用。
  const fresh = loadService();
  fresh.exports.AppScaleService.captureSystemScale(fakeContext(1, [], []));
  fresh.exports.AppScaleService.refreshSystemScale(fakeContext(1.2, [], []));
  assert.equal(fresh.exports.AppScaleService.currentSystemScale(), 1.2,
    'native follow mode may refresh the cached system scale at runtime');
  fresh.exports.AppScaleService.applyFontScale(fakeContext(1.2, [], []), 1.5);
  fresh.exports.AppScaleService.refreshSystemScale(fakeContext(2, [], []));
  assert.equal(fresh.exports.AppScaleService.currentSystemScale(), 1.2,
    'after an app-level override, config.fontSizeScale must not be treated as the system scale');

  // 7) 设置页：下拉菜单只有「跟随系统 / 自定义」两项，选自定义才出滑条（滑条不再有边界标签）。
  assert.match(profile, /@StorageLink\('fontSizeMode'\) fontSizeMode: string = 'system'/);
  assert.match(profile, /@StorageLink\('appFontScale'\) appFontScale: number = 1/);
  assert.match(profile, /@State fontScaleDraft: number = FONT_SCALE_DEFAULT/);
  assert.match(profile, /if \(kind === 'fontSize'\) return \['跟随系统', '自定义'\]/);
  assert.match(profile, /if \(kind === 'fontSize'\) return this\.fontSizeMode === 'custom' \? 1 : 0;/);
  assert.match(profile, /else if \(kind === 'fontSize'\) await this\.selectFontSizeMode\(index === 1\)/);
  assert.match(profile, /\.id\('setting-font-size'\)\.bindMenu\(this\.SettingsOptions\('fontSize'\)/);
  assert.match(profile, /if \(this\.fontSizeMode === 'custom'\) \{\s*\n\s*Column\(\) \{\s*\n\s*Slider\(\{/);
  assert.match(profile, /value: this\.fontScaleDraft,\s*\n\s*min: FONT_SCALE_MIN,\s*\n\s*max: FONT_SCALE_MAX,\s*\n\s*step: FONT_SCALE_STEP/);
  assert.match(profile, /\.id\('setting-font-scale-slider'\)/);
  // 滑条不显示边界值：两端的 0.8x / 2.5x 标签不能再回来。
  assert.ok(!/FONT_SCALE_(MIN|MAX) \+ 'x'/.test(profile), 'slider must not render min/max edge labels');

  // 7b) 实时生效：拖动中节流下发（不落盘），松手 / 点击才落盘，
  //     并且字号设置行高度写死——拖动中重排会让滑条跑离手指（minHeight 会跟着长高）。
  assert.match(profile, /const FONT_PREVIEW_INTERVAL_MS: number = 80;/);
  assert.match(profile, /private previewFontScale\(scale: number\): void \{/);
  assert.match(profile, /if \(now - this\.lastFontPreviewAt < FONT_PREVIEW_INTERVAL_MS\) return;/);
  assert.match(profile, /AppScaleService\.applyFontScale\(this\.getUIContext\(\)\.getHostContext\(\) as common\.UIAbilityContext, scale\)/);
  assert.match(profile, /if \(mode === SliderChangeMode\.End \|\| mode === SliderChangeMode\.Click\) \{\s*\n\s*this\.saveFontSize\(false, scale\);\s*\n\s*\} else \{\s*\n\s*this\.previewFontScale\(scale\);/);
  assert.match(profile, /\.width\('100%'\)\.height\(72\)\.padding\(\{ left: 16, right: 16, top: 12, bottom: 12 \}\)/,
    'font size row must keep a fixed height so the slider stays under the finger while dragging');

  // 8) 设置页写在 AppStorage 的值必须与开关、滑条同源；跟随系统时展示「跟随系统」。
  assert.match(profile, /if \(this\.fontSizeMode !== 'custom'\) return '跟随系统'/);
  assert.match(profile, /return AppScaleService\.formatFontScale\(this\.fontScaleDraft\)/);
  assert.match(profile, /this\.fontSizeMode = followSystem \? 'system' : 'custom'/);
  // 切自定义的起点、以及进页面时的草稿，都必须按「真实生效字号」取，不能直接用 appFontScale。
  assert.match(profile,
    /const seed = AppScaleService\.entryCustomScale\(this\.fontSizeMode !== 'custom', this\.appFontScale\)/);
  assert.match(profile,
    /this\.fontScaleDraft = AppScaleService\.entryCustomScale\(fontSetting\.followSystem, fontSetting\.scale\)/);
  // 系统字号可能被后台改过：切自定义前要刷新一次系统倍率缓存。
  assert.match(profile, /AppScaleService\.refreshSystemScale\(context\)/);

  // 9) 字号必须在 loadContent 之前下发：放到首帧之后会让整屏文字先按标准字号排一遍再跳档。
  const applyAt = ability.indexOf('AppScaleService.applyFromPrefsAtStartup');
  const loadAt = ability.indexOf("windowStage.loadContent('pages/Index'");
  assert.ok(applyAt > 0 && loadAt > applyAt, 'font scale must be applied before loadContent');
  assert.ok(ability.includes('AppScaleService.watchSystemFontScale(this.context)'),
    'startup must register the system font watcher');

  console.log('Font size setting: follow-system semantics, slider range/step, persistence and startup ordering passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
