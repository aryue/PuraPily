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
        VideoScaleType: { VIDEO_SCALE_TYPE_SCALED_ASPECT: 0 },
        createMediaSourceWithUrl: (url, headers) => ({ url, headers })
        };
        return name === '@kit.MediaKit' ? { media } : { default: media };
      }
      if (name.includes('PlaybackFactory')) return { supportsIjkPlayback: () => false,
        createPlaybackPlayer: async () => {
          if (options.creationGate) await options.creationGate.promise;
          assert.ok(players[created], 'no unplanned player allocation');
          return players[created++];
        } };
      if (name.includes('IjkPlaybackPlayer')) return { IjkPlaybackPlayer: class {} };
      if (name.includes('DashPlayerBridge')) return { DashPlayerBridge: Bridge };
      if (name.includes('PlayerStartupPolicy')) return { startupPlaybackStrategy: () => require('./test-player-startup-policy.cjs')(26) };
      if (name.includes('PlaybackDeadline')) return { PlaybackDeadline: require('./playback-deadline-test-helper.cjs')() };
      if (name.includes('Logger')) return { logWarn() {} };
      return {};
    }
  });
  return { Session: exports.FeedPlaybackSession, takeFeedPlayback: exports.takeFeedPlayback, bridges, created: () => created };
}

function loadPageHandoff(detail = null, schedule = setTimeout) {
  const source = fs.readFileSync(path.join(root, 'pages/VideoPlayerPage.ets'), 'utf8');
  const start = source.indexOf('  private async referenceNextVideo(');
  const end = source.indexOf('\n  @Builder', start);
  const context = { exports: {}, console, logInfo() {}, logError() {}, logWarn() {}, setTimeout: schedule, clearTimeout,
    require: () => ({}),
    takeFeedPlayback: loadSession([]).takeFeedPlayback,
    IjkWarmPool: { get: () => ({ releasePreview() {} }) },
    PlaybackAudioSession: { activate: async () => {} },
    ContinuousRecommendationState: { markVisited() {} },
    common: {}, Curve: { Linear: 'linear' }, AppStorage: { get() { return ''; } },
    getVideoDetail: async () => detail,
    media: { SeekMode: { SEEK_CLOSEST: 1 }, VideoScaleType: { VIDEO_SCALE_TYPE_SCALED_ASPECT: 0 } },
    LiveViewHelper: { setControlHandlers() {}, async create() {} } };
  const startup = fs.readFileSync(path.join(root, 'services/PlaybackStartupSource.ets'), 'utf8');
  const retirement = startup.slice(startup.indexOf('export async function releaseUnattachedPlayback'),
    startup.indexOf('/** Keep the startup slot'));
  vm.runInNewContext(ts.transpileModule(retirement, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const presentation = fs.readFileSync(path.join(root, 'services/FeedPlaybackPresentation.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(presentation, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const resources = fs.readFileSync(path.join(root, 'services/PlaybackResources.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(resources, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  Object.assign(context, context.exports);
  const identityStart = source.indexOf('  private commitPlaybackIdentity(');
  const identityEnd = source.indexOf('  private applyPgcSeasonDetail(', identityStart);
  const aspectStart = source.indexOf('  private referenceFeedAspect(');
  const aspectEnd = source.indexOf('  private referencePublishStill(', aspectStart);
  const displayStart = source.indexOf('  private displayAspect(');
  const displayEnd = source.indexOf('  private setAspectFromMeta(', displayStart);
  const promoteStart = source.indexOf('  private promoteSpareSurface(');
  const promoteEnd = source.indexOf('\n  }', promoteStart) + '\n  }'.length;
  assert.ok(promoteStart >= 0 && promoteEnd > promoteStart);
  vm.runInNewContext(ts.transpileModule(`export class Page {
    ${source.slice(promoteStart, promoteEnd)}
    ${source.slice(identityStart, identityEnd)} ${source.slice(displayStart, displayEnd)} ${source.slice(aspectStart, aspectEnd)} ${source.slice(start, end)}
  }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const page = new context.exports.Page();
  page.skipSegments_ = { reset() {}, rawMarks() { return ''; } };
  page.skipPromptTimer_ = -1;
  page.surfaceRetirement_ = new context.PlaybackSurfaceRetirement();
  page.referenceCancelFeedPlayerTouch = () => {};
  page.getUIContext = () => ({ animateTo(_options, action) { action(); }, getPromptAction: () => ({
    showToast({ message }) { throw Error(message); }
  }) });
  page.playbackStartupSlot_ = { busy: false };
  page.delayMs_ = ms => ms === 64 ? Promise.resolve() : new Promise(resolve => { const timer = schedule(resolve, ms); if (schedule === setTimeout) timer?.unref?.(); });
  page.playbackResources_ = new context.exports.PlaybackResources();
  return page;
}

function checkStillFrameRetirement() {
  let now = 0;
  let serial = 0;
  const timers = new Map();
  const context = {
    exports: {}, Date: { now: () => now },
    setTimeout(callback, delay) { timers.set(++serial, { callback, at: now + delay }); return serial; },
    clearTimeout(id) { timers.delete(id); }
  };
  const source = fs.readFileSync(path.join(root, 'services/FeedStillFrameRetirement.ets'), 'utf8');
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  const protectedFrames = new Set();
  const retirement = new context.exports.FeedStillFrameRetirement(frame => protectedFrames.has(frame));
  function advance(time) {
    now = time;
    for (const [id, timer] of timers) {
      if (timer.at > now) continue;
      timers.delete(id);
      timer.callback();
    }
  }
  function frame() {
    return { releases: 0, async release() { this.releases++; } };
  }
  const pinned = frame();
  const removedDuringExit = frame();
  protectedFrames.add(pinned);
  retirement.retire(pinned);
  retirement.retire(pinned);
  advance(290);
  retirement.retire(removedDuringExit);
  advance(300);
  assert.equal(pinned.releases, 0, 'a pinned frame survives the first sweep');
  assert.equal(removedDuringExit.releases, 0, 'an earlier timer cannot shorten a newer frame’s grace period');
  advance(590);
  assert.equal(removedDuringExit.releases, 1);
  protectedFrames.delete(pinned);
  advance(1100);
  assert.equal(pinned.releases, 1, 'dropping the pin makes a queued frame eligible for one release');
  assert.equal(timers.size, 0);

  const onExit = frame();
  protectedFrames.add(onExit);
  retirement.retire(onExit);
  retirement.close();
  advance(1399);
  assert.equal(onExit.releases, 0, 'closing preserves the native frame grace period');
  advance(1400);
  assert.equal(onExit.releases, 1, 'the closed queue drains without calling into a destroyed UI');
}

async function main() {
  {
    const video = new Player();
    const { Session } = loadSession([video]);
    const picture = deferred();
    const sampling = deferred();
    const session = new Session('BVdark', 'surface-b', { url: 'movie' });
    const preparing = session.prepare(0, '', async () => {
      assert.equal(video.state, 'playing');
      assert.equal(video.volume, 0);
      sampling.resolve();
      await picture.promise;
    });
    await sampling.promise;
    assert.equal(session.take(), null, 'the decoder cannot transfer while its opening picture is being sampled');
    session.reserve();
    picture.resolve();
    assert.equal(await preparing, true);
    assert.equal(session.take()?.video, video);
    assert.equal(video.state, 'paused');
  }
  checkStillFrameRetirement();
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
    video.off = () => { throw Error('native event removal failed'); };
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
  let cold = 0; let neighbourPrepares = 0;
  Object.assign(page, {
    referenceAlive: true, referenceSwitchGeneration: 1, playerPageVisible: true, userPaused_: false,
    referenceFeedLoading: false, referenceFeedDragY: 0, referenceSecondSurfaceActive: false, referencePinnedOpacity: 0,
    sId: 'surface-a', referenceFeedPreview: {}, vi: { title: 'next', cover: '', bvid: 'BVnext' },
    rt: 1, qn: 116, mute: false, referenceFeedSlotPending: true,
    markAutoPlay() {},
    async initP() { cold++; },
    setupL() { this.playbackResources_.video.on('timeUpdate', () => this.referenceFeedReadiness_?.positionChanged(Number.MAX_SAFE_INTEGER)); },
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
    page.referenceFeedPreviewPinned = true;
    page.referenceFeedSurfaceReady = false;
    const startWarm = video.play.bind(video);
    video.play = async () => {
      assert.equal(page.referenceFeedSurfaceReady, true, 'warm Surface enters before playback resumes');
      assert.equal(page.referenceFeedPreviewPinned, true, 'cover remains during the first visible update');
      await startWarm();
    };
    await page.referencePrepareFeedMain({ bvid: 'BVnext', aid: 1, owner: { name: 'up' } }, generation, warm);
    assert.equal(page.playbackResources_.video, video); assert.equal(page.sId, surface);
    assert.equal(page.referencePreviewSurfaceId, active ? 'surface-a' : 'surface-b');
    assert.equal(page.referenceSecondSurfaceActive, active);
    assert.equal(video.state, 'playing'); assert.equal(video.volume, 1);
    assert.equal(page.referenceFeedPreviewPinned, false);
    assert.equal(video.releases, 0);
  }
  assert.equal(cold, 0); assert.equal(neighbourPrepares, 2);
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
    assert.equal(page.playbackResources_.video, video);
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
    assert.equal(video.releases, 1); assert.equal(page.playbackResources_.video.state, 'playing');
  }
  // A warm miss uses the existing cold path without changing the active Surface.
  {
    const surface = page.sId; const active = page.referenceSecondSurfaceActive;
    const video = new Player();
    const nativePlay = video.play.bind(video);
    video.play = async () => { await nativePlay(); page.referenceFeedReadiness_?.positionChanged(Number.MAX_SAFE_INTEGER); };
    page.initP = async () => {
      cold++; page.playbackResources_.video = video; video.state = 'playing';
      page.referenceFeedReadiness_.frameRendered(); page.referenceFeedReadiness_.preparationCompleted();
    };
    await page.referencePrepareFeedMain({ bvid: 'BVcold', aid: 1 }, 2);
    assert.equal(cold, 1); assert.equal(page.sId, surface);
    assert.equal(page.referenceSecondSurfaceActive, active); assert.equal(video.state, 'playing');
  }
  // Cancelling a pending handoff must release its reserved decoder.
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
  // IJK can report playing while its media clock remains stuck. Retire that
  // decoder, retry the committed video once, and leave the successful one in use.
  {
    const p = loadPageHandoff(null, (callback, delay) => setTimeout(callback, delay >= 6000 ? 25 : delay));
    const stalled = new Player();
    stalled.play = async () => { stalled.state = 'playing'; };
    const recovered = new Player();
    const nativePlay = recovered.play.bind(recovered);
    recovered.play = async () => { await nativePlay(); p.referenceFeedReadiness_?.positionChanged(Number.MAX_SAFE_INTEGER); };
    const attempts = [stalled, recovered];
    Object.assign(p, {
      referenceAlive: true, referenceSwitchGeneration: 1, playerPageVisible: true,
      referenceFeedDragY: 0, referenceFeedMainRetry_: 0, vi: { bvid: 'BVstalled' },
      referencePinnedOpacity: 0, referenceFeedPreviewPinned: true,
      markAutoPlay() {}, startVideoSpeedSync() {},
      getUIContext() { return { animateTo(_options, action) { action(); } }; },
      async release() { await this.playbackResources_.video.release(); this.playbackResources_.video = null; },
      async initP() {
        this.playbackResources_.video = attempts.shift();
        this.playbackResources_.video.state = 'prepared';
        this.referenceFeedReadiness_.frameRendered();
        this.referenceFeedReadiness_.preparationCompleted();
      }
    });
    const detail = { bvid: 'BVstalled', aid: 1 };
    const first = Promise.resolve().then(() => p.referencePrepareFeedMain(detail, 1));
    p.referenceFeedMainJob = first;
    await first;
    assert.equal(stalled.releases, 1);
    assert.equal(p.referenceFeedMainRetry_, 1);
    await p.referenceFeedMainJob;
    assert.equal(p.playbackResources_.video, recovered);
    assert.equal(recovered.state, 'playing');
    assert.equal(recovered.volume, 1);
    assert.equal(p.referenceFeedPreviewPinned, false);
  }
  // A cold start waits for its slot. A prepared player on the other Surface can start immediately.
  for (const useWarm of [false, true]) {
    const detail = { bvid: 'BVcoldTarget', cid: 2, aid: 3, title: 'cold', pic: 'cover',
      owner: { name: 'up', face: 'face' }, stat: {}, dimension: { width: 1920, height: 1080 } };
    const next = { id: detail.bvid, cid: 2, coverUrl: 'recommend-cover' };
    const p = loadPageHandoff(detail);
    let scheduled = false;
    const warmSession = useWarm ? { id: detail.bvid, surfaceId: 'surface-b', ready: true, reserve() {} } : null;
    let cancels = 0;
    const outgoing = new Player();
    outgoing.state = 'playing';
    outgoing.volume = 1;
    const releaseGate = deferred();
    let offset = 0;
    Object.assign(p, {
      vi: { bvid: 'BVcurrent' }, referenceAlive: true, referenceSwitchGeneration: 0,
      referenceRecommendations_: { items: [{ id: 'BVcurrent' }, next] }, referenceStillFrames: new Map(),
      playbackProgressReporter_: { resetHeartbeat() {} },
      referencePreviewRequestedId: detail.bvid, referencePreviewFrame: undefined, referencePreviewAspectRatio: 9 / 16,
      referenceStillRatios: new Map(), referencePreviewGeneration: 0, referencePreviewPreparing: true,
      referencePreviewDecodingId: detail.bvid,
      sId: 'surface-a', referenceWarmSession: warmSession,
      referenceDecodeRatios: new Map(),
      referenceFeedMainCancel() { cancels++; },
      async release() {
        assert.equal(this.playbackResources_.video.volume, 0, 'old audio must be silenced before waiting for cleanup');
        assert.equal(this.vi.bvid, 'BVcurrent', 'release starts before publishing the new identity');
        this.playbackResources_.video = null;
        await releaseGate.promise;
        await outgoing.release();
      },
      referenceFeedMainJob: Promise.resolve(), referenceFeedDragY: 0, ch: 744, ar: 1,
      referenceQueuedFeedStep: 0, referenceVerticalSwipe: false, referenceFeedLoading: false,
      referencePortraitFeedActive: () => true, ensureReferenceRecommendQueue: async () => p.referenceRecommendations_.items,
      requestReferenceFeedPreview() {},
      referencePreviewDetailFor: () => detail,
      settleFeedTransition: async () => offset,
      referenceAnimateFeedTo: async () => {
        p.referenceStillFrames.set(detail.bvid, 'late-frame');
        p.referencePreviewFrame = 'late-frame';
        p.referencePreviewAspectRatio = 16 / 9;
      },
      resetVideoShot_() {}, referenceResetSubtitles() {},
      saveWatchHistory() {}, reportWatchBehavior() {}, clearGestureHint_() {}, resetFullscreenVideo() {},
      updateIsLandscapeVertical() {}, updateLSVSize() {}, updateVideoSize() {},
      commentDataSource: { clear() {} }, referenceFeedNeighbor: () => null, loadD() {}, loadC() {},
      async referencePrepareFeedMain(_detail, _generation, warm) { assert.equal(warm, warmSession); scheduled = true; },
      referenceFeedBounceBack() {}
    });
    p.playbackResources_.video = outgoing;
    await p.referenceNextVideo(1);
    assert.equal(p.vi.bvid, 'BVcurrent');
    assert.equal(p.referenceSwitchGeneration, 0, 'an interrupted swipe preserves callback ownership');
    assert.equal(cancels, 0);
    assert.equal(outgoing.volume, 1);

    p.referenceStillRatios.set(detail.bvid, 9 / 16);
    p.referenceDecodeRatios.set(detail.bvid, 16 / 9);
    p.referencePreviewFrame = 'incoming-frame';
    p.referencePreviewAspectRatio = 9 / 16;
    offset = -744;
    if (useWarm) {
      const capture = deferred();
      p.referenceStillFrames.clear();
      p.referencePreviewDecodePromise = capture.promise;
      p.referenceAnimateFeedTo = async () => { p.referencePreviewFrame = undefined; };
      p.delayMs_ = () => new Promise(() => {});
      const switching = p.referenceNextVideo(1);
      await tick();
      assert.equal(cancels, 0, 'a ready decoder keeps its pending capture alive through the visual handoff');
      p.referenceStillFrames.set(detail.bvid, 'late-frame');
      p.referencePreviewFrame = 'late-frame';
      capture.resolve(true);
      await switching;
    } else {
      await p.referenceNextVideo(1);
    }
    assert.equal(cancels, 1);
    assert.equal(outgoing.volume, 0);
    await tick();
    assert.equal(scheduled, useWarm, 'only a separate warm Surface can start before the outgoing decoder releases');
    releaseGate.resolve();
    await p.referenceFeedMainJob;
    await p.surfaceRetirement_.wait();
    assert.equal(outgoing.releases, 1);
    assert.equal(p.vi.bvid, detail.bvid); assert.equal(p.vi.cover, 'cover');
    assert.equal(p.referenceFeedPreviewPinned, true); assert.equal(p.referencePinnedFrame, 'late-frame');
    assert.equal(p.referencePinnedAspectRatio, 9 / 16, 'late dimensions may not resize the visible poster');
    assert.equal(p.ar, 16 / 9, 'native layout can settle independently behind the poster');
    assert.equal(p.referenceFeedLoading, false); assert.equal(scheduled, true);
    assert.equal(p.ct, 0, 'reverted continuous playback must restart on switching');
    assert.equal(p.initialProgress_, 0, 'recommendation changes must not restore the withdrawn resume behavior');
  }
  console.log('PASS: first-frame ordering, muted audio, DASH transfer, cancellation, native errors, one-time ownership, two Surface swaps, stale handoff, cold fallback');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
