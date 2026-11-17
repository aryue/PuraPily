const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');
function section(start, end) {
  const a = source.indexOf(start);
  const b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a);
  return source.slice(a, b);
}
const context = { exports: {}, logInfo() {} };
const decoder = { exports: {}, setTimeout, require: () => context };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/FeedPreviewDecoder.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, decoder);
Object.assign(context, decoder.exports);
const resources = { exports: {}, require: () => ({}) };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/PlaybackResources.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, resources);
const methods = section('  private referenceFeedAspect(', '  private referenceDecodeStill(') +
  section('  private referenceDecodeStill(', '  private referenceWarmUpcomingFrames(') +
  section('  private displayAspect(', '  private setAspectFromMeta(') +
  section('  private requestReferenceFeedPreview(', '  private async prepareReferenceFeedPreview(') +
  section('  private async prepareReferenceFeedPreview(', '  private stillFrameInUse(') +
  section('  private effectiveScaleMode(', '  private onPlaybackViewportChanged(') +
  section('  private referenceMediaDimension(', '  private onReferencePreviewXc');
const viewport = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/utils/PlaybackViewport.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, viewport);
Object.assign(context, viewport.exports);
// Keep the opening animation on the same timeline as the comment media box.
for (const [aspect, contained, start, end] of [[16 / 9, true, 207.5, 47.5], [9 / 16, false, 0, 24]]) {
  for (const progress of [0, 0.25, 0.5, 1]) {
    const top = context.feedCommentMediaTop(400, 800, 24, aspect, contained, progress);
    assert.ok(Math.abs(top - (start + (end - start) * progress)) < 1e-7);
  }
}
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
async function main() {
  context.image = { PixelMapFormat: { RGBA_8888: 3, BGRA_8888: 4 } };
  const pixels = new Uint8Array(21 * 21 * 4);
  pixels.fill(255, 0, 21 * 4);
  const opening = {
    getImageInfoSync: () => ({ pixelFormat: 3, size: { width: 21, height: 21 } }),
    getBytesNumberPerRow: () => 21 * 4,
    getPixelBytesNumber: () => pixels.length,
    readPixelsToBuffer: async buffer => new Uint8Array(buffer).set(pixels)
  };
  assert.equal(await context.feedStillHasPicture(opening), false, 'a sparse bright logo does not make the frame usable');
  pixels.fill(90, 21 * 4, 5 * 21 * 4);
  assert.equal(await context.feedStillHasPicture(opening), true, 'a visible picture can be pinned');
  const pinned = section('  ReferenceFeedPinnedPage() {', '  ReferenceFeedPreviewPage() {');
  const preview = section('  ReferenceFeedPreviewPage() {', '  private referencePreviewDetailFor(');
  assert.match(pinned, /Image\(this\.referencePinnedFrame\)[\s\S]*?else if \(this\.vi\.cover\)/);
  assert.match(preview, /Image\(this\.referencePreviewFrame\)[\s\S]*?else if \(this\.referencePreviewCover\(\)\)/);
  const p = new context.exports.Page();
  Object.assign(p, {
    referencePreviewSurfaceId: 'b', referencePreviewRequestedId: 'oldPortrait',
    referencePreviewAspectRatio: 9 / 16, referencePreviewFrame: 'oldFrame',
    referenceStillFrames: new Map(), feedPreviewDetails_: new Map(), referenceStillRatios: new Map(),
    referenceDecodeStill: async () => false,
    requestReferenceDetail() {}, referenceFeedNeighbor: () => null, publishFeedNextChrome() {},
    referenceDecodeRatios: new Map(), vi: { bvid: 'playing' },
    referenceLayout: true, referenceFeed: true, referenceFeedProgress: 1,
    referenceFeedPortraitScaleScope: 'standard', referenceFeedPortraitScaleMode: 'fill',
    cw: 400, ch: 800, referenceAreaHeight: () => 800,
    referenceSafeTop: () => 24, referencePanelOffset: 0
  });
  // A cold landscape neighbour following a portrait must be landscape on its first render.
  const anime = { id: 'anime', videoWidth: 1920, videoHeight: 1080 };
  p.requestReferenceFeedPreview(anime);
  assert.equal(p.referencePreviewFrame, undefined);
  assert.equal(p.referencePreviewAspectRatio, 16 / 9);
  assert.equal(p.referenceMediaWidth(p.referencePreviewAspectRatio), 400);
  assert.equal(p.referenceMediaHeight(p.referencePreviewAspectRatio), 225);
  assert.equal(p.referenceMediaTop(p.referencePreviewAspectRatio), 207.5);
  // Repeated requests during URL/decoder preparation must preserve the resolved metadata.
  p.referencePreviewDetail = { bvid: 'anime' };
  p.requestReferenceFeedPreview(anime);
  assert.equal(p.referencePreviewDetail.bvid, 'anime');
  // Unknown targets may not inherit either the previous frame or previous aspect.
  p.requestReferenceFeedPreview({ id: 'unknown' });
  assert.equal(p.referencePreviewAspectRatio, 1);
  assert.equal(p.referencePreviewDetail, null);
  // Per-part dimensions and rotation take precedence; invalid dimensions use only the target fallback.
  assert.equal(p.referenceFeedAspect({ dimension: { width: 1920, height: 1080, rotate: 90 } }, 1, 1), 9 / 16);
  assert.equal(p.referenceFeedAspect({ dimension: { width: 1920, height: 1080 },
    pages: [{ cid: 2, dimension: { width: 720, height: 1280 } }] }, 2, 1), 9 / 16);
  assert.equal(p.referenceFeedAspect({ dimension: { width: 0, height: 0 } }, 1, 1), 1);
  // Even when signed URL retrieval is blocked, details must correct the preview
  // before any decoder or still becomes available (the original cold-miss failure).
  let releaseUrl;
  p.requestReferenceDetail = async () => ({ bvid: 'cold', cid: 7, dimension: { width: 1920, height: 1080 } });
  context.getVideoPlayUrl = () => new Promise(resolve => { releaseUrl = resolve; });
  Object.assign(p, { referenceAlive: true, referencePreviewGeneration: 3,
    referencePreviewRequestedId: 'cold', referencePreviewAspectRatio: 9 / 16 });
  p.publishReferencePreviewDetail = (_id, detail) => { p.referencePreviewDetail = detail; };
  context.IjkWarmPool = { get: () => ({ reservePreview: () => true, releasePreview() {} }) };
  const preparing = p.prepareReferenceFeedPreview({ id: 'cold', cid: 7 }, 3);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(p.referencePreviewAspectRatio, 16 / 9);
  assert.equal(p.referencePreviewDetail.bvid, 'cold');
  assert.equal(p.referenceWarmAspectRatio, 16 / 9);
  releaseUrl({ url: '' });
  assert.equal(await preparing, false);
  // A captured buffer must apply the Surface's transform; a raw decoder buffer
  // may be upside down even though native playback displays it correctly.
  let captures = 0;
  const still = { getImageInfoSync: () => ({ size: { width: 1920, height: 1080 } }) };
  context.deviceInfo = { abiList: 'arm64-v8a' };
  context.setTimeout = setTimeout;
  context.logInfo = () => {};
  context.logWarn = e => { throw new Error(e); };
  context.media = { VideoScaleType: { VIDEO_SCALE_TYPE_SCALED_ASPECT: 0 } };
  context.AppStorage = { get: () => '' };
  context.getVideoPlayUrl = async () => ({ url: 'video' });
  context.FeedPlaybackSession = class {
    constructor(id, surfaceId) { this.id = id; this.surfaceId = surfaceId; }
    async prepare(scale) { assert.equal(scale, 0); this.ready = true; this.onSizeChanged(this.aspectRatio); return true; }
  };
  context.supportsIjkPlayback = () => false;
  Object.assign(p, { referenceWarmSurfaceWidth: () => 1920, referenceWarmSurfaceHeight: () => 1080,
    referenceWarmStaleAttempts: new Map() });
  context.image = { ...context.image, async createPixelMapFromSurfaceWithTransformation(surface, transform) {
    captures++; assert.equal(surface, 'b'); assert.equal(transform, true); return still;
  } };
  assert.equal(await p.prepareReferenceFeedPreview({ id: 'cold', cid: 7 }, 3), true);
  assert.equal(p.referenceStillFrames.get('cold'), still);
  assert.equal(p.referenceStillRatios.get('cold'), 16 / 9);
  assert.equal(captures, 1);
  context.deviceInfo.abiList = 'x86_64';
  assert.equal(await p.prepareReferenceFeedPreview({ id: 'cold', cid: 7 }, 3), true);
  assert.equal(captures, 1, 'x86 must retain its warm decoder without caching unreliable Surface readback');
  // A cached still keeps its own geometry across a forward/reverse neighbour change.
  p.referenceStillFrames.set('dog', 'dogFrame');
  p.feedPreviewDetails_.set('dog', { bvid: 'dog' });
  p.referenceStillRatios.set('dog', 3 / 4);
  p.requestReferenceFeedPreview({ id: 'dog' });
  assert.equal(p.referencePreviewFrame, 'dogFrame');
  assert.equal(p.referencePreviewAspectRatio, 3 / 4);
  // The first decoded image replaces the fallback without resizing the card.
  p.referenceVerticalSwipe = true;
  p.referencePreviewFrame = undefined;
  p.referencePreviewAspectRatio = 16 / 9;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, 'dogFrame');
  assert.equal(p.referencePreviewAspectRatio, 16 / 9);
  p.referenceVerticalSwipe = false;
  p.referenceFeedLoading = true;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, 'dogFrame', 'settling animation keeps an already published first frame');
  p.vi.bvid = 'dog';
  p.referenceFeedPreviewPinned = true;
  p.referencePinnedAspectRatio = 16 / 9;
  p.referencePinnedFrame = undefined;
  p.referencePublishStill('dog');
  assert.equal(p.referencePinnedFrame, 'dogFrame', 'a late first frame fills the committed transition');
  assert.equal(p.referencePinnedAspectRatio, 16 / 9);
  p.referenceFeedPreviewPinned = false;
  p.referencePinnedFrame = undefined;
  p.referenceFeedLoading = false;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, 'dogFrame');
  // A page that reserves a still-preparing decoder owns its eventual result.
  // The obsolete preview task must not release that decoder when it wakes late.
  let finishPrepare, preparingDecoder;
  const decoderStarted = new Promise(resolve => { preparingDecoder = resolve; });
  let released = 0;
  context.FeedPlaybackSession = class {
    constructor(id, surfaceId) { this.id = id; this.surfaceId = surfaceId; }
    reserve() { this.reserved = true; }
    async prepare() { await new Promise(resolve => { finishPrepare = resolve; preparingDecoder(); }); this.ready = true; return true; }
    async release() { released++; }
  };
  p.referenceWarmSession = null;
  p.referencePreviewGeneration = 4;
  const late = p.prepareReferenceFeedPreview({ id: 'late', cid: 7 }, 4);
  await decoderStarted;
  p.referenceWarmSession.reserve();
  p.referencePreviewGeneration++;
  finishPrepare();
  assert.equal(await late, false);
  assert.equal(released, 0, 'obsolete preview cleanup cannot cancel the reserved target');
  context.deviceInfo.abiList = 'arm64-v8a';
  p.surfaceRetirement_ = new resources.exports.PlaybackSurfaceRetirement();
  context.FeedPlaybackSession.prototype.prepare = async function () {
    this.ready = true;
    this.onSizeChanged(this.aspectRatio);
    return true;
  };
  let resolveReadback, startReadback;
  const readbackStarted = new Promise(resolve => { startReadback = resolve; });
  context.image.createPixelMapFromSurfaceWithTransformation = () => new Promise(resolve => {
    resolveReadback = resolve;
    startReadback();
  });
  const capture = p.prepareReferenceFeedPreview({ id: 'cancelled-readback', cid: 7 }, p.referencePreviewGeneration);
  await readbackStarted;
  p.referencePreviewGeneration++;
  let releasedFrames = 0;
  resolveReadback({ async release() { releasedFrames++; } });
  assert.equal(await capture, false);
  assert.equal(releasedFrames, 1, 'a late readback is released once before publication');
  assert.equal(p.referenceStillFrames.has('cancelled-readback'), false);
  // Evaluate the actual native Surface position bindings. Opacity alone does not hide
  // an outgoing native buffer, so both slots must be outside the viewport while pinned.
  const bindings = [...source.matchAll(/\.position\(\{ x: ([^\n,]*this\.referenceSecondSurfaceActive[^\n]+),/g)].map(m => m[1]);
  assert.equal(bindings.length, 2);
  Object.assign(p, { ovRectW: () => 400, ovVideoW: () => 400, portraitScaleByTransform: () => false });
  for (const active of [false, true]) {
    p.referenceSecondSurfaceActive = active;
    for (const pinned of [false, true]) {
      p.referenceFeedPreviewPinned = pinned;
      for (const ready of [false, true]) {
        p.referenceFeedSurfaceReady = ready;
        const positions = bindings.map(expr => Function(`return ${expr}`).call(p));
        assert.equal(positions.filter(x => x >= 0).length, pinned && !ready ? 0 : 1);
      }
    }
  }
  const requests = new Map();
  const detailsContext = { exports: {}, require(id) {
    if (id.includes('BilibiliApi')) return {
      getVideoDetail: id => new Promise(resolve => requests.set(id, resolve))
    };
    return { logInfo() {}, logWarn() {} };
  } };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/services/FeedPreviewDetails.ets', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, detailsContext);
  const details = new detailsContext.exports.FeedPreviewDetails();
  for (let i = 0; i < 6; i++) details.set(`cached-${i}`, { bvid: `cached-${i}` });
  const published = [];
  const request = id => details.request(id, id => id === 'cached-0', detail => published.push(detail.bvid));
  const pending = request('next');
  assert.equal(request('next'), pending, 'preview and switching share one request');
  requests.get('next')({ bvid: 'next' });
  await pending;
  assert.deepEqual(published, ['next']);
  assert.ok(details.get('cached-0'), 'protected entries survive eviction');
  assert.equal(details.get('cached-1'), undefined);
  const closing = request('late');
  details.close();
  requests.get('late')({ bvid: 'late' });
  assert.equal(await closing, null);
  assert.equal(details.get('late'), undefined);
  assert.deepEqual(published, ['next']);
  const gate = new resources.exports.PlaybackSurfaceRetirement();
  let finishRelease, finishQualityRetirement;
  const releasing = new Promise(resolve => { finishRelease = resolve; });
  const retiringQuality = new Promise(resolve => { finishQualityRetirement = resolve; });
  gate.track(retiringQuality);
  let binds = 0;
  Object.assign(p, { surfaceRetirement_: gate, referenceWarmSession: { release: () => releasing },
    referencePreviewDecodePromise: Promise.resolve(false), referenceFeedSlotPending: false,
    neighborWarmMode: () => 0, prepareReferenceFeedPreview: async () => { binds++; return false; } });
  context.IjkWarmPool.get = () => ({ releaseScene() {} });
  const leaving = p.releaseReferenceFeedPreview();
  const next = context.exports.Page.prototype.referenceDecodeStill.call(p, { id: 'new' });
  finishQualityRetirement();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(binds, 0, 'the spare Surface remains occupied while preview release is pending');
  finishRelease();
  await Promise.all([leaving, next]);
  assert.equal(binds, 1);
  console.log('PASS: cold landscape geometry, repeated requests, unknown target isolation, rotated parts, cached reverse swipe, native buffer isolation, detail deduplication, eviction and exit');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
