const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const storage = new Map([['continuationMainTab', 2], ['homeChannelIndex', 0]]);
function compile(code, requireFn = () => ({})) {
  const context = { exports: {}, require: requireFn, AppStorage: {
    get: key => storage.get(key), setOrCreate: (key, value) => storage.set(key, value)
  }, PersistentStorage: { persistProp() {} }, LocalStorage: class {}, setTimeout, clearTimeout };
  vm.runInNewContext(ts.transpileModule(code, { compilerOptions: {
    target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS
  } }).outputText, context);
  return context.exports;
}
const service = compile(read('entry/src/main/ets/services/AppContinuation.ets'));
const { AppContinuation: continuation, CONTINUATION_KEY: key } = service;
const video = { page: 'pages/VideoPlayerPage', params: {
  bvid: 'BV1xx411c7mD', cid: 22, aid: 33, initialProgress: 91.25,
  continuationPaused: true, continuationRate: 1.5, cookie: 'secret',
  offlineVideoPath: '/data/private/file', url: 'https://stream/?token=secret'
} };
const snapshot = continuation.fromPage(video);
assert.equal(snapshot.tab, 2);
assert.equal(snapshot.channel, 0);
assert.equal(snapshot.destination.params.initialProgress, 91.25);
assert.equal(snapshot.destination.params.continuationPaused, true);
assert.equal(snapshot.destination.params.continuationRate, 1.5);
for (const field of ['cookie', 'offlineVideoPath', 'url']) assert.equal(snapshot.destination.params[field], undefined);
for (const bvid of ['170001', 'BV1xx411c7mD']) {
  assert.ok(continuation.fromPage({ page: video.page, params: { bvid, initialProgress: 0 } }));
}
assert.ok(continuation.fromPage({ page: video.page, params: { epId: 12345, seasonId: 22 } }));
assert.ok(continuation.fromPage({ page: 'pages/LivePlayerPage', params: { roomId: 123 } }));
assert.equal(continuation.fromPage({ page: 'pages/LivePlayerPage', params: { roomId: '123' } }), null);
for (const page of ['pages/QrCodeLoginPage', 'pages/WhisperDetailPage', '../private', 'pages/OfflineCachePage',
  'pages/Index', 'pages/SearchPage', 'pages/SettingsPage', 'pages/FavoritesPage', 'pages/UpSpacePage',
  'pages/WatchHistoryPage', 'pages/HotRankingPage', 'pages/AboutPage']) {
  assert.equal(continuation.fromPage({ page, params: {} }), null);
  continuation.register({}, page, () => ({ page, params: {} }));
  assert.equal(continuation.snapshot(page, {}), null);
}
for (const raw of [undefined, {}, 'null', '{bad', 'x'.repeat(16385), JSON.stringify({ ...snapshot, schema: 2 }),
  JSON.stringify({ ...snapshot, destination: { page: video.page, params: {} } })]) {
  assert.equal(continuation.decode(raw), null);
}
const old = {}, current = {};
continuation.register(old, video.page, () => video);
continuation.register(current, video.page, () => ({ ...video, params: { ...video.params, initialProgress: 155 } }));
continuation.unregister(old);
assert.equal(continuation.snapshot('/pages/VideoPlayerPage.ets', {}).destination.params.initialProgress, 155);
assert.equal(continuation.snapshot('pages/VideoPlayerPage.js', {}).destination.params.initialProgress, 155);
assert.equal(continuation.snapshot('pages/Index', {}), null);
continuation.unregister(current);
assert.equal(continuation.snapshot(video.page, {}), null);

// Execute Ability lifecycle methods against platform mocks, including the hot-start restore path.
const calls = [];
let route = { path: 'pages/', name: 'Index' };
let routeParams = {};
const uiRouter = { getState: () => route, getParams: () => routeParams,
  pushUrl: async options => calls.push(['push', options]) };
const win = { getUIContext: () => ({ getRouter: () => uiRouter, getPromptAction: () => ({ showToast: () => {} }) }) };
const stage = { getMainWindowSync: () => win, loadContent: (url, cb) => { calls.push(['load', url]); cb({ code: 0 }, {}); } };
const hosted = { hasActivePlayer: false, playerState: null, release: () => calls.push(['release']) };
const constants = { OnContinueResult: { AGREE: 0, REJECT: 1, MISMATCH: 2 }, LaunchReason: { CONTINUATION: 3 },
  ContinueState: { ACTIVE: 0, INACTIVE: 1 } };
const observer = { RouterPageState: { ON_PAGE_SHOW: 2, ON_PAGE_HIDE: 3 }, on() {}, off() {} };
const ability = compile(read('entry/src/main/ets/entryability/EntryAbility.ets'), name => {
  if (name === '@kit.AbilityKit') return { UIAbility: class {}, AbilityConstant: constants,
    wantConstant: { Params: { SUPPORT_CONTINUE_PAGE_STACK_KEY: 'stack', SUPPORT_CONTINUE_SOURCE_EXIT_KEY: 'exit' } } };
  if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, error() {} } };
  if (name === '@kit.ArkUI') return { uiObserver: observer };
  if (name.endsWith('/ReferenceAppearance')) return { syncThemeConfiguration() {} };
  if (name.endsWith('/CredentialStore')) return { initializeLoginCredentials: async () => {} };
  if (name.endsWith('/AppContinuation')) return service;
  if (name.endsWith('/PlayerService')) return { PlayerService: { getInstance: () => hosted, setAppContext() {} } };
  if (name.endsWith('/FloatingPiP')) return { FloatingPiP: { getInstance: () => ({ detach: async () => calls.push(['detach']) }) } };
  if (name.endsWith('/HighRefreshService')) return { HighRefreshService: { getInstance: () => ({ setMainWindow() {}, initialize() {} }) } };
  if (name.endsWith('/QualityPreferenceService')) return { QualityPreferenceService: { getInstance: () => ({ initialize() {} }) } };
  // 2.0.3 起启动时有静默更新检查，本用例只验接续，桩成「已是最新」即可。
  if (name.endsWith('/UpdateChecker')) return { checkForUpdate: async () => ({ status: 0 }),
    UpdateCheckStatus: { UP_TO_DATE: 0, UPDATE_AVAILABLE: 1, ERROR: 2 } };
  // 字号/密度在 loadContent 之前由 AppScaleService 下发，本用例不关心，全部空实现。
  if (name.endsWith('/AppScaleService')) return { AppScaleService: { watchSystemFontScale() {}, applyFromPrefsAtStartup: async () => {} } };
  if (name.endsWith('/ErrorLogCollector')) return { setErrorLogContext() {} };
  if (name.endsWith('/Logger')) return { errMsg: String };
  return {};
}).default;
const a = new ability();
a.context = { config: {}, windowStage: stage, setMissionContinueState: async state => calls.push(['mission', state]),
  restoreWindowStage: () => calls.push(['restore']) };
a.setupImmersiveWindow = async () => {};
a.applyOrientationLockFromPrefs = async () => {};
a.applyAppScale = async () => {};
let params = { version: service.CONTINUATION_MIN_VERSION };
assert.equal(a.onContinue(params), constants.OnContinueResult.REJECT);
assert.equal(a.onContinue({ version: service.CONTINUATION_MIN_VERSION - 1 }), constants.OnContinueResult.MISMATCH);
route = { path: 'pages/WhisperDetailPage', name: 'WhisperDetailPage' };
assert.equal(a.onContinue({}), constants.OnContinueResult.REJECT);
route = { path: 'pages/VideoPlayerPage.js', name: 'VideoPlayerPage' };
continuation.register(current, video.page, () => video);
params = {};
assert.equal(a.onContinue(params), constants.OnContinueResult.AGREE);
assert.equal(params.stack, false);
assert.equal(params.exit, true);
assert.equal(JSON.parse(params[key]).destination.params.initialProgress, 91.25);
storage.set('floatingPiPActive', true);
hosted.hasActivePlayer = true;
hosted.playerState = { bvid: '170001', cid: 22, aid: 170001, epId: 0, seasonId: 0,
  title: 'PiP', playbackRate: 2, isOffline: false };
hosted.videoPlayer = { currentTime: 123456 };
hosted.playbackState = 'playing';
params = {};
assert.equal(a.onContinue(params), constants.OnContinueResult.REJECT);
route = { path: 'pages/', name: 'Index' };
assert.equal(a.onContinue({}), constants.OnContinueResult.REJECT, 'PiP must not enable continuation from the home page');
hosted.playerState.isOffline = true;
assert.equal(a.onContinue({}), constants.OnContinueResult.REJECT);
storage.set('floatingPiPActive', false);
hosted.hasActivePlayer = false;
for (const page of ['Index', 'SearchPage', 'SettingsPage', 'LivePlayerPage', 'VideoPlayerPage']) {
  a.continuationPageChanged({ path: 'pages/' + page + '.js', name: page, state: 2 });
  assert.equal(calls.at(-1)[1], page.endsWith('PlayerPage') ? 0 : 1);
}
a.continuationPageChanged({ path: 'pages/VideoPlayerPage', name: 'VideoPlayerPage', state: 3 });
assert.equal(calls.at(-1)[1], 1, 'leaving playback disables the system continuation entry');
a.continuationPageChanged({ path: 'pages/LivePlayerPage', name: 'LivePlayerPage', state: 2 });
const beforeStaleHide = calls.length;
a.continuationPageChanged({ path: 'pages/VideoPlayerPage', name: 'VideoPlayerPage', state: 3 });
assert.equal(calls.length, beforeStaleHide);

async function main() {
  const cold = new ability();
  cold.context = a.context;
  cold.registerGlobalErrorHandler = () => {};
  cold.loadCardSettings = async () => {};
  cold.registerCalleeHandlers = () => {};
  cold.onCreate({ uri: 'bilibili://ignored', parameters: { [key]: JSON.stringify(snapshot) } }, { launchReason: 3 });
  assert.equal(cold.pendingContinuation.destination.params.initialProgress, 91.25);
  assert.equal(cold.pendingUri, null);
  a.onNewWant({ uri: 'bilibili://ignored', parameters: { [key]: JSON.stringify(snapshot) } }, { launchReason: 3 });
  assert.equal(storage.get('continuationMainTab'), 2);
  assert.equal(a.pendingUri, null);
  assert.ok(calls.some(c => c[0] === 'restore'));
  await a.restoreContinuationWindow(stage);
  // 字号/密度下发挪到了 loadContent 之前（多一拍 await），恢复回调晚一拍微任务才清 pendingContinuation。
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(a.pendingContinuation, null);
  assert.ok(calls.findIndex(c => c[0] === 'release') < calls.findIndex(c => c[0] === 'load'));
  const destination = calls.find(c => c[0] === 'push')[1];
  assert.equal(destination.url, video.page);
  assert.equal(destination.params.initialProgress, 91.25);
  const pushes = calls.filter(c => c[0] === 'push').length;
  a.receiveContinuation({ parameters: { [key]: '{bad' } });
  await a.restoreContinuationWindow(stage);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(calls.filter(c => c[0] === 'push').length, pushes);
  if (process.argv.includes('--compiled')) await testCompiledPages();
  console.log('PASS: continuation payload, privacy filtering, current-content capture, version guard and lifecycle restore');
}

async function testCompiledPages() {
  const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/';
  const definitions = [
    ['VideoPlayerPage', '    async aboutToAppear()', {
      vi: { bvid: '170001', cid: 42, title: 'current video' }, aidFromParams_: 170001,
      epId_: 0, seasonId_: 0, av: { currentTime: 65432 }, ct: 0, initialProgress_: 0,
      play: false, userPaused_: true, rt: 1.5, offlineVideoPath_: ''
    }],
    ['LivePlayerPage', '    aboutToAppear()', { roomId: 876, areaId: 1 }]
  ];
  const provider = {};
  for (const [name, nextMethod, fields] of definitions) {
    const compiled = read(base + name + '.ts').replace(/\r\n/g, '\n');
    const start = compiled.indexOf('    private registerContinuation(): void {');
    const end = compiled.indexOf(nextMethod, start);
    assert.ok(start >= 0 && end > start, `${name}: actual CompileArkTS output must retain the capture method`);
    const { Probe } = compile("import { AppContinuation } from 'service'; export class Probe {" + compiled.slice(start, end) + '}', () => service);
    const page = Object.assign(new Probe(), fields);
    provider[name] = page;
    page.registerContinuation();
    const state = continuation.snapshot('pages/' + name, {});
    assert.ok(state);
    if (name === 'VideoPlayerPage') {
      assert.equal(state.destination.params.initialProgress, 65.432);
      assert.equal(state.destination.params.continuationPaused, true);
      page.vi.cid = 99;
      page.av.currentTime = 3000;
      assert.equal(continuation.snapshot('pages/' + name, {}).destination.params.cid, 99);
      page.offlineVideoPath_ = '/local/video';
      assert.equal(continuation.snapshot('pages/' + name, {}), null);
    }
    if (name === 'LivePlayerPage') {
      page.roomId = 999;
      assert.equal(continuation.snapshot('pages/' + name, {}).destination.params.roomId, 999);
    }
  }
  const compiled = read(base + 'VideoPlayerPage.ts').replace(/\r\n/g, '\n');
  const start = compiled.indexOf('const preparedProgress = PlaybackProgress.resume(this.initialProgress_, this.dur);');
  const end = compiled.indexOf('else if (preparedProgress > 0', start);
  assert.ok(start > 0 && end > start);
  const code = `import { media, PlaybackProgress } from 'mock'; export class Probe { async prepared() { const player = this.av; ${compiled.slice(start, end)} } }`;
  const { Probe } = compile(code, () => ({ media: { SeekMode: { SEEK_CLOSEST: 2 } },
    PlaybackProgress: { resume: progress => progress } }));
  const seeks = [];
  const page = Object.assign(new Probe(), { initialProgress_: 91.25, dur: 300,
    continuationRestore_: true, continuationPaused_: true, continuationRate_: 1.5,
    setRate: async rate => seeks.push(['rate', rate]),
    av: { seek: pos => seeks.push(['video', pos]) }, avAudio: { seek: pos => seeks.push(['audio', pos]) }
  });
  await page.prepared();
  assert.equal(page.play, false);
  assert.equal(page.userPaused_, true);
  assert.equal(page.ct, 91.25);
  assert.deepEqual(seeks, [['rate', 1.5], ['video', 91250], ['audio', 91250]]);
  // Execute the compiled resume guard with a conflicting target-device watch history.
  const guardStart = compiled.indexOf('    private applyServerResumePoint(');
  const guardEnd = compiled.indexOf('\n    private ', guardStart + 10);
  const guard = compile("export class Guard {" + compiled.slice(guardStart, guardEnd) + '}').Guard;
  const instance = Object.assign(new guard(), { continuationRestore_: true, initialProgress_: 91.25 });
  instance.applyServerResumePoint({ lastPlayTimeMs: 200000 });
  assert.equal(instance.initialProgress_, 91.25);
  console.log('PASS: actual CompileArkTS page captures, switched video/live content, paused A/V seek and resume priority');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
