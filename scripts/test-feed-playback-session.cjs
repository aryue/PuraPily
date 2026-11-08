const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };

class Player {
  constructor({ manual = false, reverseFrames = false } = {}) {
    this.events = new Map(); this.state = 'idle'; this.currentTime = 0;
    this.duration = 10000; this.releases = 0; this.plays = 0;
    this.manual = manual; this.reverseFrames = reverseFrames;
  }
  on(name, callback) { this.events.set(name, callback); }
  off(name) { this.events.delete(name); }
  emit(name, ...args) { return this.events.get(name)?.(...args); }
  async setMediaSource(source, strategy) {
    this.strategy = strategy; this.source = source; this.state = 'initialized';
    if (!this.manual) await this.emit('stateChange', 'initialized');
  }
  async prepare() { this.state = 'prepared'; await this.emit('stateChange', 'prepared'); }
  async play() {
    this.plays++; this.state = 'playing';
    if (this.reverseFrames) this.emit('startRenderFrame');
    await this.emit('stateChange', 'playing');
    this.emit('videoSizeChange', 1920, 1080);
    if (!this.reverseFrames) this.emit('startRenderFrame');
    this.currentTime += 40;
    this.emit('timeUpdate', this.currentTime);
  }
  async pause() { this.state = 'paused'; await this.emit('stateChange', 'paused'); }
  setVolume(volume) { this.volume = volume; }
  async setSpeed(speed) { this.speed = speed; }
  seek(time) { this.currentTime = time; this.emit('seekDone', time); }
  async release() { this.releases++; this.state = 'released'; }
}

function loadSession(players, options = {}) {
  const bridges = [];
  class Bridge {
    constructor() { this.stops = 0; bridges.push(this); }
    async buildAndStart(_dash, referer, ua) { this.referer=referer; this.ua=ua; if (options.bridgeGate) await options.bridgeGate.promise; return 'http://localhost/manifest.mpd'; }
    async stopIfRunning() { this.stops++; }
  }
  let created = 0;
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.resolve(__dirname,
    '../entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/FeedPlaybackSession.ts'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    exports, setTimeout, clearTimeout,
    require(name) {
      if (name === '@kit.MediaKit' || name === '@ohos:multimedia.media') {
        const media = {
        async createAVPlayer() {
          if (options.creationGate) await options.creationGate.promise;
          assert.ok(players[created], 'no unplanned player allocation');
          return players[created++];
        },
        createMediaSourceWithUrl: (url, headers) => ({ url, headers })
        };
        return name === '@kit.MediaKit' ? { media } : { default: media };
      }
      if (name.includes('DashPlayerBridge')) return { DashPlayerBridge: Bridge };
      if (name.includes('PlayerStartupPolicy')) return { startupPlaybackStrategy: () => require('./test-player-startup-policy.cjs')(26) };
      if (name.includes('PlaybackDeadline')) return { PlaybackDeadline: require('./playback-deadline-test-helper.cjs')() };
      return {};
    }
  });
  return { Session: exports.FeedPlaybackSession, bridges, created: () => created };
}

function loadPageHandoff(detail = null) {
  const source = fs.readFileSync(path.join(root, 'pages/VideoPlayerPage.ets'), 'utf8');
  const start = source.indexOf('  private async referenceNextVideo(');
  const end = source.indexOf('\n  @Builder', start);
  const context = { exports: {}, console, logInfo() {}, logError() {}, setTimeout, clearTimeout,
    ContinuousRecommendationState: { markVisited() {} },
    common: {}, Curve: { Linear: 'linear' }, AppStorage: { get() { return ''; } },
    getVideoDetail: async () => detail,
    media: { SeekMode: { SEEK_CLOSEST: 1 }, VideoScaleType: { VIDEO_SCALE_TYPE_SCALED_ASPECT: 0 } },
    LiveViewHelper: { setControlHandlers() {}, async create() {} } };
  const aspectStart = source.indexOf('  private referenceFeedAspect(');
  const aspectEnd = source.indexOf('  private referencePublishStill(', aspectStart);
  vm.runInNewContext(ts.transpileModule(`export class Page { ${source.slice(aspectStart, aspectEnd)} ${source.slice(start, end)} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return new context.exports.Page();
}

async function main() {
  for (const reverseFrames of [false, true]) {
    const video = new Player({ reverseFrames });
    const { Session, created } = loadSession([video]);
    const session = new Session('BVnext', 'surface-b', { url: 'movie', actualQn: 80 });
    assert.equal(await session.prepare(0, ''), true);
    assert.equal(video.state, 'paused'); assert.equal(video.volume, 0);
    assert.equal(session.aspectRatio, 1920 / 1080);
    const handles = session.take();
    assert.equal(handles.video, video); assert.equal(created(), 1);
    assert.equal(session.take(), null, 'ownership can transfer only once');
    assert.equal(video.events.size, 0, 'preheat callbacks must be detached before page handlers');
    await session.release();
    assert.equal(video.releases, 0, 'retired session cannot release transferred playback');
  }
  // DASH hands off the very same bridge and decoder rather than rebuilding either.
  {
    const video = new Player();
    const { Session, bridges } = loadSession([video]);
    const session = new Session('BVdash', 'b', { url: 'v', audioUrl: 'a', dash: {}, mediaUserAgent: 'App-media-UA', mediaReferer: '' });
    assert.equal(await session.prepare(0, 'cookie'), true);
    const handles = session.take();
    assert.equal(handles.bridge, bridges[0]);
    assert.equal(handles.audioPlayer, null);
    assert.equal(video.source.url, 'http://localhost/manifest.mpd');
    assert.deepEqual(Object.keys(video.strategy), [], 'warm/quality sessions pass the compiled native buffering policy to AVPlayer');
    assert.equal(bridges[0].ua, 'App-media-UA'); assert.equal(bridges[0].referer, '');
    await session.release(); assert.equal(bridges[0].stops, 0);
  }
  // Separate audio is fully prepared but never played during preheat.
  {
    const video = new Player(); const audio = new Player();
    const { Session } = loadSession([video, audio]);
    const session = new Session('BVsplit', 'b', { url: 'v', audioUrl: 'a' });
    assert.equal(await session.prepare(0, ''), true);
    assert.equal(audio.state, 'prepared'); assert.equal(audio.plays, 0); assert.equal(audio.volume, 0);
    await Promise.all([session.release(), session.release()]);
    assert.equal(video.releases, 1); assert.equal(audio.releases, 1);
  }
  // Cancellation while native player creation is pending must release its late result.
  {
    const gate = deferred(); const video = new Player();
    const { Session } = loadSession([video], { creationGate: gate });
    const session = new Session('BVcancel', 'b', { url: 'v' });
    const preparing = session.prepare(0, '');
    const releasing = session.release();
    assert.equal(await preparing, false); await releasing;
    gate.resolve(); await tick();
    assert.equal(video.releases, 1); assert.equal(video.plays, 0);
  }
  // Cancellation during bridge startup also stops the late server, before allocating a decoder.
  {
    const gate = deferred();
    const { Session, bridges, created } = loadSession([], { bridgeGate: gate });
    const session = new Session('BVcancelDash', 'b', { url: 'v', audioUrl: 'a', dash: {} });
    const preparing = session.prepare(0, '');
    const releasing = session.release();
    assert.equal(await preparing, false); await releasing;
    assert.equal(bridges[0].stops, 1); assert.equal(created(), 0);
    gate.resolve(); await tick();
  }
  // Native errors while waiting for a first frame settle preparation and free resources.
  {
    const video = new Player({ manual: true });
    const { Session } = loadSession([video]);
    const session = new Session('BVerror', 'b', { url: 'v' });
    const preparing = session.prepare(0, ''); await tick();
    video.emit('error', { code: 1 });
    assert.equal(await preparing, false);
    await session.release(); assert.equal(video.releases, 1); assert.equal(session.take(), null);
  }
  // Exercise the actual page method over two swaps; it must never call cold initP.
  const page = loadPageHandoff();
  let cold = 0; let outgoingReleases = 0; let neighbourPrepares = 0;
  Object.assign(page, {
    referenceAlive: true, referenceSwitchGeneration: 1, playerPageVisible: true, userPaused_: false,
    referenceFeedLoading: false, referenceFeedDragY: 0, referenceSecondSurfaceActive: false,
    sId: 'surface-a', referenceFeedPreview: {}, vi: { title: 'next', cover: '', bvid: 'BVnext' },
    rt: 1, qn: 116, mute: false, referenceFeedSlotPending: true,
    async release() { outgoingReleases++; this.av = null; this.avAudio = null; },
    async initP() { cold++; },
    setupL() { this.av.on('timeUpdate', () => this.referenceFeedMainPresentResolve?.()); },
    setupAudioL() {}, getVideoScaleType() { return 0; },
    rateToSpeedIdx() { return 1; }, getQlLabel() { return '1080p'; }, applyAcceptQuality() {},
    prefetchVideoShot_() {}, startVideoSpeedSync() {},
    updateIsLandscapeVertical() {}, updateLSVSize() {}, updateVideoSize() {},
    getUIContext() { return { getHostContext() { return {}; }, animateTo(_options, action) { action(); } }; },
    requestReferenceFeedPreview() {
      assert.equal(this.referenceFeedSlotPending, false);
      neighbourPrepares++;
    }
  });
  for (const [generation, surface, active] of [[1, 'surface-b', true], [2, 'surface-a', false]]) {
    page.referenceSwitchGeneration = generation;
    const video = new Player(); video.state = 'paused';
    const { Session } = loadSession([video]);
    const warm = new Session('BVnext', surface, { url: 'v', actualQn: 80 });
    assert.equal(await warm.prepare(0, ''), true);
    await page.referencePrepareFeedMain({ bvid: 'BVnext', aid: 1, owner: { name: 'up' } }, generation, warm);
    assert.equal(page.av, video); assert.equal(page.sId, surface);
    assert.equal(page.referenceSecondSurfaceActive, active);
    assert.equal(video.state, 'playing'); assert.equal(video.volume, 1);
    assert.equal(page.referenceFeedPreviewPinned, false);
    assert.equal(video.releases, 0);
  }
  assert.equal(cold, 0); assert.equal(outgoingReleases, 2); assert.equal(neighbourPrepares, 2);
  // Slow same-target preparation is reserved and adopted, rather than cancelled
  // and restarted with another network request/decoder after the page commits.
  {
    const gate = deferred();
    const video = new Player();
    const { Session, created } = loadSession([video], { creationGate: gate });
    const warm = new Session('BVslow', 'surface-b', { url: 'slow' });
    const preparing = warm.prepare(0, '');
    warm.reserve();
    const handing = page.referencePrepareFeedMain({ bvid: 'BVslow', aid: 1, owner: { name: 'up' } }, 2, warm);
    await tick();
    assert.equal(cold, 0);
    assert.equal(warm.reserved, true);
    gate.resolve();
    await preparing;
    await handing;
    assert.equal(created(), 1);
    assert.equal(page.av, video);
    assert.equal(video.releases, 0);
    assert.equal(video.volume, 1);
    assert.equal(page.referencePinnedOpacity, 0);
    assert.equal(page.referenceFeedSurfaceReady, true);
  }
  // An obsolete queued handoff releases its reservation without touching the active player.
  {
    const video = new Player(); const { Session } = loadSession([video]);
    const warm = new Session('BVstale', 'b', { url: 'v' });
    await warm.prepare(0, '');
    await page.referencePrepareFeedMain({ bvid: 'BVstale' }, 1, warm);
    assert.equal(video.releases, 1); assert.equal(outgoingReleases, 3);
  }
  // A warm miss uses the existing cold path without changing the active Surface.
  {
    const surface = page.sId; const active = page.referenceSecondSurfaceActive;
    const video = new Player();
    const nativePlay = video.play.bind(video);
    video.play = async () => { await nativePlay(); page.referenceFeedMainPresentResolve?.(); };
    page.initP = async () => {
      cold++; page.av = video; video.state = 'playing';
      page.referenceFeedMainFrameResolve(); page.referenceFeedMainPreparedResolve();
    };
    await page.referencePrepareFeedMain({ bvid: 'BVcold', aid: 1 }, 2);
    assert.equal(cold, 1); assert.equal(page.sId, surface);
    assert.equal(page.referenceSecondSurfaceActive, active); assert.equal(video.state, 'playing');
  }
  // Cancellation while the outgoing player releases must free an unclaimed warm reservation.
  {
    const gate = deferred();
    const video = new Player();
    const { Session } = loadSession([video], { creationGate: gate });
    const warm = new Session('BVcancelPending', 'pending', { url: 'slow' });
    const preparing = warm.prepare(0, '');
    warm.reserve();
    const handing = page.referencePrepareFeedMain({ bvid: 'BVcancelPending', aid: 1 }, 2, warm);
    await tick();
    page.referenceSwitchGeneration = 3;
    page.referenceFeedPreviewPinned = true;
    page.referencePinnedFrame = 'new-destination';
    page.referenceFeedMainCancel();
    gate.resolve();
    await preparing;
    await handing;
    assert.equal(video.releases, 1);
    assert.equal(cold, 1, 'abandoned slow preheat must not start cold playback');
    assert.equal(page.referencePinnedFrame, 'new-destination');
    assert.equal(page.referenceFeedPreviewPinned, true, 'late completion cannot uncover another target');
    page.referenceSwitchGeneration = 2;
    page.referenceFeedPreviewPinned = false;
  }
  // Cancellation while the outgoing player releases must free an unclaimed warm reservation.
  {
    const video = new Player(); const { Session } = loadSession([video]);
    const warm = new Session('BVcancelHandoff', 'b', { url: 'v' });
    await warm.prepare(0, '');
    page.release = async () => { page.referenceSwitchGeneration++; };
    await page.referencePrepareFeedMain({ bvid: 'BVcancelHandoff' }, 2, warm);
    assert.equal(video.releases, 1);
  }
  // A rapid swipe into an unprepared video must commit its cover and schedule a
  // cold start instead of rejecting navigation or waiting on a preheat promise.
  {
    const detail = { bvid: 'BVcoldTarget', cid: 2, aid: 3, title: 'cold', pic: 'cover',
      owner: { name: 'up', face: 'face' }, stat: {}, dimension: { width: 1920, height: 1080 } };
    const next = { id: detail.bvid, cid: 2, coverUrl: 'recommend-cover' };
    const p = loadPageHandoff(detail);
    let coldScheduled = false;
    Object.assign(p, {
      vi: { bvid: 'BVcurrent' }, referenceAlive: true, referenceSwitchGeneration: 0,
      referenceFeedQueue: [{ id: 'BVcurrent' }, next], referenceStillFrames: new Map(),
      referencePreviewRequestedId: detail.bvid, referencePreviewFrame: undefined, referencePreviewAspectRatio: 9 / 16,
      referenceStillRatios: new Map(), referencePreviewGeneration: 0, referencePreviewPreparing: true,
      referenceWarmSession: null, referencePreviewReleaseJob: Promise.resolve(),
      referenceFeedMainJob: Promise.resolve(), referenceFeedDragY: 0, ch: 744, ar: 1,
      referenceQueuedFeedStep: 0, referenceVerticalSwipe: false, referenceFeedLoading: false,
      referencePortraitFeedActive: () => true, ensureReferenceRecommendQueue: async () => p.referenceFeedQueue,
      requestReferenceFeedPreview() {},
      referenceAnimateFeedTo: async () => {
        p.referenceStillFrames.set(detail.bvid, 'late-frame');
        p.referencePreviewFrame = 'late-frame';
        p.referencePreviewAspectRatio = 16 / 9;
      },
      saveWatchHistory() {}, reportWatchBehavior() {}, clearGestureHint_() {}, resetFullscreenVideo() {},
      updateIsLandscapeVertical() {}, updateLSVSize() {}, updateVideoSize() {},
      commentDataSource: { clear() {} }, referenceFeedNeighbor: () => null, loadD() {}, loadC() {},
      async referencePrepareFeedMain(_detail, _generation, warm) { assert.equal(warm, null); coldScheduled = true; },
      referenceFeedBounceBack() { assert.fail('unprepared media must not reject a swipe'); }
    });
    await p.referenceNextVideo(1); await p.referenceFeedMainJob;
    assert.equal(p.vi.bvid, detail.bvid); assert.equal(p.vi.cover, 'cover');
    assert.equal(p.referenceFeedPreviewPinned, true); assert.equal(p.referencePinnedFrame, undefined);
    assert.equal(p.referencePinnedCover, 'recommend-cover', 'do not swap to the detail thumbnail at commit');
    assert.equal(p.referencePinnedAspectRatio, 9 / 16, 'late dimensions may not resize the visible poster');
    assert.equal(p.ar, 16 / 9, 'native layout can settle independently behind the poster');
    assert.equal(p.referenceFeedLoading, false); assert.equal(coldScheduled, true);
    assert.equal(p.ct, 0, 'reverted continuous playback must restart on switching');
    assert.equal(p.initialProgress_, 0, 'recommendation changes must not restore the withdrawn resume behavior');
  }
  console.log('PASS: first-frame ordering, muted audio, DASH transfer, cancellation, native errors, one-time ownership, two Surface swaps, stale handoff, cold fallback');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
