/**
 * 设置页「壁纸透明度 / 壁纸遮罩」滑条必须实时生效：
 *  - 拖动中（Begin/Moving）只写 AppStorage → PageWallpaper 的 StorageLink 立即重绘，**不落盘**；
 *  - 松手 / 点击（End/Click）才 setOpacity / setScrim 持久化（一条滑条一次 flush，不是每帧一次）。
 *  - 滑条值与标签绑本地草稿，不绑 StorageLink：0.55 写回再 *100 会得到 55.00000000000001，
 *    滑块会在拖动中自己抖一档。
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const serviceSource = read('entry/src/main/ets/services/PageWallpaperService.ets');
const layoutSource = read('entry/src/main/ets/utils/WallpaperLayout.ets');
const profile = read('entry/src/main/ets/pages/ProfilePage.ets');
const component = read('entry/src/main/ets/components/PageWallpaper.ets');

function transpile(source) {
  return ts.transpileModule(source.split('\n').filter(line => !/^import\s/.test(line)).join('\n'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
}

function loadService() {
  const shared = new Map();
  const stored = new Map();
  let flushes = 0;
  const layout = { exports: {} };
  vm.runInNewContext(transpile(layoutSource), layout);
  const harness = {
    exports: {},
    ArrayBuffer,
    AppStorage: {
      get: key => shared.get(key),
      setOrCreate: (key, value) => shared.set(key, value)
    },
    preferences: {
      getPreferences: async () => ({
        get: async (key, fallback) => stored.has(key) ? stored.get(key) : fallback,
        put: async (key, value) => { stored.set(key, value); },
        flush: async () => { flushes++; }
      })
    },
    fileIo: {
      OpenMode: { READ_ONLY: 1, READ_WRITE: 2, CREATE: 4, TRUNC: 8 },
      statSync: () => { throw new Error('missing'); },
      openSync: p => ({ fd: p }), closeSync() {},
      writeSync: (p, b) => b.byteLength, renameSync() {}, unlinkSync() {}
    },
    image: { createImageSource: () => ({ getImageInfo: async () => ({ size: { width: 1080, height: 1920 } }), createPixelMap: async () => ({}), release() {} }) },
    http: { RequestMethod: { GET: 0 }, HttpDataType: { ARRAY_BUFFER: 0 }, createHttp: () => ({ request: async () => { throw new Error('offline'); }, destroy() {} }) }
  };
  Object.assign(harness, layout.exports);
  vm.runInNewContext(transpile(serviceSource), harness);
  return { harness, shared, stored, flushCount: () => flushes };
}

(async () => {
  // 1) 服务：拖动预览只改 AppStorage，绝不碰 preferences（否则 120Hz 拖动 = 120 次 flush）。
  const { harness, shared, stored, flushCount } = loadService();
  const { PageWallpaperService, clampWallpaperOpacity, clampWallpaperScrim, WALLPAPER_OPACITY_MIN } = harness.exports;
  const service = PageWallpaperService.getInstance();
  await service.open({ filesDir: '/files' });
  assert.equal(shared.get('pageWallpaperOpacity'), 0.7, 'cold start publishes the default opacity');
  assert.equal(shared.get('pageWallpaperScrim'), 0, 'cold start publishes the default scrim');

  const flushesBeforeDrag = flushCount();
  for (let percent = 100; percent >= 20; percent -= 5) {
    service.previewOpacity(percent / 100);
    service.previewScrim(percent * 0.6);
  }
  assert.equal(shared.get('pageWallpaperOpacity'), 0.2, 'live preview reaches AppStorage');
  assert.equal(shared.get('pageWallpaperScrim'), 12, 'live preview reaches AppStorage (scrim)');
  assert.equal(flushCount(), flushesBeforeDrag, 'dragging must not flush preferences');
  assert.ok(!stored.has('opacity') && !stored.has('scrim'), 'dragging must not persist anything');

  // 2) 松手落盘：写盘 + AppStorage 同步，值被夹在允许区间内。
  await service.setOpacity(0.55);
  await service.setScrim(41);
  assert.equal(stored.get('opacity'), 0.55, 'release persists the opacity');
  assert.equal(stored.get('scrim'), 41, 'release persists the scrim');
  assert.equal(shared.get('pageWallpaperOpacity'), 0.55);
  assert.equal(shared.get('pageWallpaperScrim'), 41);
  assert.equal(flushCount(), flushesBeforeDrag + 2, 'one flush per released slider, not per frame');

  service.previewOpacity(0);
  assert.equal(shared.get('pageWallpaperOpacity'), WALLPAPER_OPACITY_MIN, 'preview clamps below the slider min');
  service.previewScrim(999);
  assert.equal(shared.get('pageWallpaperScrim'), 60, 'preview clamps above the slider max');
  await service.setOpacity(3);
  assert.equal(stored.get('opacity'), 1, 'persisted opacity is clamped to 100%');
  await service.setOpacity(0);
  assert.equal(stored.get('opacity'), WALLPAPER_OPACITY_MIN, 'persisted opacity is clamped to the slider min');
  await service.setScrim(-5);
  assert.equal(stored.get('scrim'), 0);
  await service.setScrim(88);
  assert.equal(stored.get('scrim'), 60);

  // 3) 夹取纯函数：NaN / Infinity 都当「坏值」回落到安全默认，滑条范围 20%~100% 与 0~60%。
  assert.equal(clampWallpaperOpacity(NaN), 0.7);
  assert.equal(clampWallpaperOpacity(Infinity), 0.7);
  assert.equal(clampWallpaperOpacity(0.05), 0.2);
  assert.equal(WALLPAPER_OPACITY_MIN, 0.2, 'slider min stays 20%');
  assert.equal(clampWallpaperScrim(Number.NaN), 0);
  assert.equal(clampWallpaperScrim(60.4), 60);
  assert.equal(clampWallpaperScrim(-0.4), 0);

  // 4) 重启后读回已落盘值（不带浮点尾数也必须落在滑条档位上）。
  const reload = loadService();
  reload.stored.set('opacity', 0.8499999999999999);
  reload.stored.set('scrim', 33);
  await reload.harness.exports.PageWallpaperService.getInstance().open({ filesDir: '/files' });
  assert.equal(reload.shared.get('pageWallpaperOpacity'), 0.8499999999999999);
  assert.equal(reload.shared.get('pageWallpaperScrim'), 33);

  // 5) 设置页：两条滑条绑草稿、拖动即时预览、松手落盘。
  assert.match(profile, /@State wallpaperOpacityDraft: number = 70;/);
  assert.match(profile, /@State wallpaperScrimDraft: number = 0;/);
  assert.match(profile,
    /this\.wallpaperOpacityDraft = Math\.round\(clampWallpaperOpacity\(this\.pageWallpaperOpacity\) \* 100\);/,
    'entering the page seeds the opacity draft from the live value');
  assert.match(profile, /this\.wallpaperScrimDraft = clampWallpaperScrim\(this\.pageWallpaperScrim\);/);
  assert.match(profile, /Slider\(\{ value: this\.wallpaperOpacityDraft, min: 20, max: 100, step: 5 \}\)/);
  assert.match(profile, /Slider\(\{ value: this\.wallpaperScrimDraft, min: 0, max: 60, step: 1 \}\)/);
  assert.match(profile, /\.id\('setting-wallpaper-opacity'\)/);
  assert.match(profile, /\.id\('setting-wallpaper-scrim'\)/);
  assert.match(profile, /Text\('壁纸透明度 ' \+ Math\.round\(this\.wallpaperOpacityDraft\) \+ '%'\)/,
    'the label must follow the drag, not the persisted value');
  assert.match(profile, /Text\('壁纸遮罩 ' \+ Math\.round\(this\.wallpaperScrimDraft\) \+ '%'\)/);

  // 拖动分支在前（Begin/Moving → preview），落盘分支在后（End/Click → set*）。
  assert.match(profile,
    /this\.wallpaperOpacityDraft = Math\.round\(value\);\s*\n\s*if \(mode === SliderChangeMode\.End \|\| mode === SliderChangeMode\.Click\) \{\s*\n\s*PageWallpaperService\.getInstance\(\)\.setOpacity\(this\.wallpaperOpacityDraft \/ 100\)[^\n]*\n\s*\} else \{\s*\n\s*PageWallpaperService\.getInstance\(\)\.previewOpacity\(this\.wallpaperOpacityDraft \/ 100\);/,
    'opacity slider previews while dragging and persists on release');
  assert.match(profile,
    /this\.wallpaperScrimDraft = Math\.round\(value\);\s*\n\s*if \(mode === SliderChangeMode\.End \|\| mode === SliderChangeMode\.Click\) \{\s*\n\s*PageWallpaperService\.getInstance\(\)\.setScrim\(this\.wallpaperScrimDraft\)[^\n]*\n\s*\} else \{\s*\n\s*PageWallpaperService\.getInstance\(\)\.previewScrim\(this\.wallpaperScrimDraft\);/,
    'scrim slider previews while dragging and persists on release');
  // 不能再把 StorageLink 直接当滑条值（0.55*100 = 55.00000000000001 → 拖动中抖一档）。
  assert.ok(!/Slider\(\{ value: this\.pageWallpaperOpacity \* 100/.test(profile),
    'slider value must not be the StorageLink (floating point tail jitters the thumb)');
  assert.ok(!/Slider\(\{ value: this\.pageWallpaperScrim,/.test(profile),
    'slider value must not be the StorageLink (scrim)');

  // 6) 背景组件靠 StorageLink 订阅这两条值：预览写进 AppStorage 即可重绘整个页面壁纸。
  assert.match(component, /@StorageLink\('pageWallpaperOpacity'\) imageOpacity: number = 0\.7;/);
  assert.match(component, /@StorageLink\('pageWallpaperScrim'\) scrim: number = 0;/);
  assert.match(component, /\.opacity\(this\.imageOpacity\)/, 'image opacity must be driven by the live value');
  assert.match(component, /backgroundColor\(this\.scrimColor\(\)\)/, 'scrim overlay must be driven by the live value');

  console.log('Wallpaper live sliders: preview-without-flush, release persistence, clamping, draft binding and StorageLink-driven repaint passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
