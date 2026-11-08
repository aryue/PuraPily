// Run the actual CompileArkTS methods with deterministic media and animation events.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/LivePlayerPage.ts', 'utf8');
const tree = ts.createSourceFile('page.ts', source, ts.ScriptTarget.Latest, true);
const pageClass = tree.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'LivePlayerPage');
const names = ['switchRoom', 'animateRoomOffset', 'clearPreview', 'disposePlayer', 'prepareAdjacentRoom',
  'preparePreview', 'bindPlayer', 'ownsPlayer', 'liveMediaSource', 'onTD', 'onTM', 'onTU', 'onTC',
  'cancelPendingTap', 'togglePlayPause', 'settleInformation', 'onPageHide', 'onPageShow',
  'slotHasCurrentFrame', 'releaseAVPlayer'];
const methods = names.map(name => {
  const method = pageClass.members.find(n => n.name?.getText(tree) === name);
  assert.ok(method, `compiled method ${name}`);
  return method.getText(tree);
}).join('\n');
let timerId = 0, timers = new Map(), players = [], events = [], liveCount = 0, maxLiveCount = 0;
function player() {
  const listeners = {};
  const p = { state: 'idle', volume: 1, listeners,
    on: (name, cb) => { listeners[name] = cb; }, off: name => { delete listeners[name]; },
    setVolume(value) { this.volume = value; events.push([this.id, 'volume', value]); },
    async release() { this.state = 'released'; liveCount--; },
    async prepare() { this.state = 'prepared'; await listeners.stateChange?.('prepared'); },
    async play() { this.state = 'playing'; await listeners.stateChange?.('playing'); },
    async pause() { this.state = 'paused'; await listeners.stateChange?.('paused'); },
    async setMediaSource() { this.state = 'initialized'; await listeners.stateChange?.('initialized'); },
    async frame() { await listeners.startRenderFrame?.(); }
  };
  p.id = players.length; players.push(p); liveCount++; maxLiveCount = Math.max(maxLiveCount, liveCount);
  return p;
}
const context = { exports: {}, logInfo() {}, logWarn() {}, logError() {},
  Curve: { EaseOut: 0 }, audio: { StreamUsage: { STREAM_USAGE_MOVIE: 4 }, InterruptMode: { SHARE_MODE: 0 } },
  setTimeout: cb => { timers.set(++timerId, cb); return timerId; }, clearTimeout: id => timers.delete(id),
  media: { createAVPlayer: async () => player(), createMediaSourceWithUrl: url => url },
  getLiveRoomInfo: async id => ({ roomId: id, liveStatus: 1, title: `room ${id}` }),
  getRoomPlayInfo: async () => ({ qualities: [{ qn: 250, desc: '超清' }] }),
  getLiveStreamUrl: async id => ({ url: `stream-${id}`, currentQn: 250, acceptQuality: [250] }),
  fetchLiveRoomsByArea: async () => [],
  LiveViewHelper: { updatePlayState() {} }
};
vm.runInNewContext(ts.transpileModule(`export class Page {${methods}}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
function page() {
  const p = new context.exports.Page();
  Object.assign(p, { roomIds: [1, 2, 3], roomId: 1, rooms: [], previewGeneration: 0, activeSlot: 0,
    previewRelease: Promise.resolve(), previewTask: Promise.resolve(), previewAV: null,
    playGeneration: 0, viewportWidth: 400, viewportHeight: 800, vol: 1, bri: 1, activeFrameReady: false,
    informationVisible: true, informationProgress: 0, dt_: -1, lt_: -1, previewQualities: [],
    portraitWindow: () => true, showBottomHintTemporarily() {}, ensureSurfaceId_: async slot => `surface-${slot}`,
    audioOutputMonitor: { bind() {} }, finishLevelGesture() {}, startLiveChat() {}, stopLiveChat() {}, applyStreamQuality() {}, setupLiveView_() {}, updateKeepScreen() {}, registerContinuation() {},
    onVideoPrepared() {}, onVideoStart() { this.isPlaying = true; }, onVideoPause() { this.isPlaying = false; },
    initPlayback: async () => { p.fallback = true; }, handlePlayError() { p.failed = true; },
    getUIContext: () => ({ animateTo: (options, action) => { action(); options.onFinish?.(); } }) });
  return p;
}
function flushTimers() { const pending = [...timers.values()]; timers.clear(); pending.forEach(cb => cb()); }
function tap(p) { p.onTD({ touches: [{ windowX: 200, windowY: 400 }] }); p.onTU({}); }
(async () => {
  const p = page(); p.av = player(); p.av.state = 'playing';
  p.rooms = [{ roomId: 2, uname: '主播二', face: 'avatar' }];
  p.prepareAdjacentRoom(1); await p.previewTask;
  const next = p.previewAV;
  assert.equal(next.volume, 0, 'preview muted before play');
  assert.equal(next.state, 'playing');
  assert.equal(p.previewReady, false, 'playing is not proof of a rendered frame');
  await next.frame(); assert.equal(p.previewReady, true);
  let finish;
  p.getUIContext = () => ({ animateTo: (options, action) => { action(); finish = options.onFinish; } });
  const old = p.av, transition = p.switchRoom(1);
  assert.equal(p.roomId, 1); assert.equal(old.volume, 1);
  assert.equal(next.volume, 0, 'outgoing owns sound throughout drag and settle');
  finish(); await transition;
  assert.equal(p.av, next, 'promote the same player'); assert.equal(p.activeSlot, 1);
  assert.equal(p.slotHasCurrentFrame(1), true, 'ready preview stays visible through promotion');
  assert.equal(p.roomId, 2); assert.equal(p.fallback, undefined);
  assert.equal(p.uname, '主播二', 'keep list identity when room API omits anchor name');
  assert.equal(p.availableQualities[0].label, '超清', 'preserve actual API quality labels on promotion');
  assert.equal(old.state, 'released'); assert.equal(next.volume, 1);
  const mute = events.findIndex(e => e[0] === old.id && e[1] === 'volume' && e[2] === 0);
  const unmute = events.findIndex(e => e[0] === next.id && e[1] === 'volume' && e[2] === 1);
  assert.ok(mute >= 0 && unmute > mute, 'mute outgoing before unmute incoming');
  await p.previewTask; assert.ok(maxLiveCount <= 2, 'no third decoder during handoff');
  p.clearPreview(); await p.previewRelease; await p.disposePlayer(p.av);

  const g = page(); g.av = player(); g.av.state = 'playing';
  tap(g); assert.equal(g.informationVisible, true, 'single waits for double-tap window');
  // The second click cancels the single-click action.
  tap(g); assert.equal(g.userPaused, true); flushTimers(); assert.equal(g.informationVisible, true);
  tap(g); tap(g); assert.equal(g.userPaused, false);
  tap(g); flushTimers(); assert.equal(g.informationVisible, false);
  tap(g); flushTimers(); assert.equal(g.informationVisible, true);
  g.onTD({ touches: [{ windowX: 200, windowY: 400 }] }); g.onTC(); flushTimers();
  assert.equal(g.informationVisible, true, 'cancel is not a tap');
  g.userPaused = true; g.av.state = 'paused'; g.onPageHide(); g.onPageShow();
  assert.equal(g.av.state, 'paused', 'foreground must preserve manual pause');
  await g.disposePlayer(g.av);

  const stale = page();
  stale.prepareAdjacentRoom(1); stale.clearPreview(); await stale.previewTask;
  assert.equal(stale.previewAV, null, 'cancelled preheat cannot attach a late player');
  assert.equal(stale.failed, undefined, 'preview cancellation never fails the current room');

  const surface = page(); surface.av = player(); surface.activeFrameReady = true;
  const previous = surface.av;
  surface.bindPlayer(previous, 0);
  const lateFrame = previous.listeners.startRenderFrame;
  assert.equal(surface.slotHasCurrentFrame(0), true);
  await surface.releaseAVPlayer();
  assert.equal(surface.activeFrameReady, false, 'release invalidates retained Surface pixels');
  // A reused native Surface may still contain previous pixels even with loading off on an error.
  surface.loading = false;
  surface.av = player(); surface.bindPlayer(surface.av, 0);
  await surface.av.setMediaSource('replacement-stream');
  assert.equal(surface.slotHasCurrentFrame(0), false, 'prepared/playing must not expose previous pixels');
  lateFrame();
  assert.equal(surface.slotHasCurrentFrame(0), false, 'late frame from released player cannot uncover replacement');
  await surface.av.frame();
  assert.equal(surface.slotHasCurrentFrame(0), true, 'only replacement first frame reveals the Surface');
  surface.previewAV = player(); surface.previewReady = true; surface.previewRoomId = 3;
  surface.roomSlideDirection = 1;
  assert.equal(surface.slotHasCurrentFrame(1), false, 'wrong adjacent room must remain covered');
  surface.previewRoomId = 2;
  assert.equal(surface.slotHasCurrentFrame(1), true);
  surface.clearPreview();
  assert.equal(surface.slotHasCurrentFrame(1), false, 'cancelled preheat cannot expose retained pixels');
  await surface.previewRelease; await surface.releaseAVPlayer();
  console.log('PASS compiled live handoff: first frame, audio ownership, two-decoder limit, tap arbitration, pause lifecycle and stale preheat');
})().catch(error => { console.error(error); process.exitCode = 1; });
