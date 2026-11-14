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
const context = { exports: {} };
const methods = section('  private referenceFeedAspect(', '  private referenceDecodeStill(') +
  section('  private displayAspect(', '  private setAspectFromMeta(') +
  section('  private requestReferenceFeedPreview(', '  private async prepareReferenceFeedPreview(') +
  section('  private async prepareReferenceFeedPreview(', '  private async releaseReferenceFeedPreview(') +
  section('  private effectiveScaleMode(', '  private onPlaybackViewportChanged(') +
  section('  private referenceMediaWidth(', '  private onReferencePreviewXc');
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
async function main() {
  const p = new context.exports.Page();
  Object.assign(p, {
    referencePreviewSurfaceId: 'b', referencePreviewRequestedId: 'oldPortrait',
    referencePreviewAspectRatio: 9 / 16, referencePreviewFrame: 'oldFrame',
    referenceStillFrames: new Map(), referenceStillDetails: new Map(), referenceStillRatios: new Map(),
    referenceDecodeStill: async () => false,
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
  context.getVideoDetail = async () => ({ bvid: 'cold', cid: 7, dimension: { width: 1920, height: 1080 } });
  context.getVideoPlayUrl = () => new Promise(resolve => { releaseUrl = resolve; });
  Object.assign(p, { referenceAlive: true, referencePreviewGeneration: 3,
    referencePreviewRequestedId: 'cold', referencePreviewAspectRatio: 9 / 16 });
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
  const still = {};
  context.deviceInfo = { abiList: 'arm64-v8a' };
  context.setTimeout = setTimeout;
  context.logInfo = () => {};
  context.logWarn = e => { throw new Error(e); };
  context.media = { VideoScaleType: { VIDEO_SCALE_TYPE_SCALED_ASPECT: 0 } };
  context.AppStorage = { get: () => '' };
  context.getVideoPlayUrl = async () => ({ url: 'video' });
  context.FeedPlaybackSession = class {
    constructor(id, surfaceId) { this.id = id; this.surfaceId = surfaceId; }
    async prepare(scale) { assert.equal(scale, 0); this.ready = true; return true; }
  };
  context.image = { async createPixelMapFromSurfaceWithTransformation(surface, transform) {
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
  p.referenceStillDetails.set('dog', { bvid: 'dog' });
  p.referenceStillRatios.set('dog', 3 / 4);
  p.requestReferenceFeedPreview({ id: 'dog' });
  assert.equal(p.referencePreviewFrame, 'dogFrame');
  assert.equal(p.referencePreviewAspectRatio, 3 / 4);
  // A late decoded still may enter the cache while the visible incoming card stays
  // exactly as the finger first revealed it, until the current swipe is committed.
  p.referenceVerticalSwipe = true;
  p.referencePreviewFrame = undefined;
  p.referencePreviewAspectRatio = 16 / 9;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, undefined);
  assert.equal(p.referencePreviewAspectRatio, 16 / 9);
  p.referenceVerticalSwipe = false;
  p.referenceFeedLoading = true;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, undefined, 'settling animation must keep the same poster');
  p.referenceFeedLoading = false;
  assert.equal(p.referencePublishStill('dog'), true);
  assert.equal(p.referencePreviewFrame, 'dogFrame');
  // A page that reserves a still-preparing decoder owns its eventual result.
  // The obsolete preview task must not release that decoder when it wakes late.
  let finishPrepare;
  let released = 0;
  context.FeedPlaybackSession = class {
    constructor(id, surfaceId) { this.id = id; this.surfaceId = surfaceId; }
    reserve() { this.reserved = true; }
    async prepare() { await new Promise(resolve => { finishPrepare = resolve; }); this.ready = true; return true; }
    async release() { released++; }
  };
  p.referencePreviewGeneration = 4;
  const late = p.prepareReferenceFeedPreview({ id: 'late', cid: 7 }, 4);
  await new Promise(resolve => setImmediate(resolve));
  p.referenceWarmSession.reserve();
  p.referencePreviewGeneration++;
  finishPrepare();
  assert.equal(await late, false);
  assert.equal(released, 0, 'obsolete preview cleanup cannot cancel the reserved target');
  // Evaluate the actual native Surface position bindings. Opacity alone does not hide
  // an outgoing native buffer, so both slots must be outside the viewport while pinned.
  const bindings = [...source.matchAll(/\.position\(\{ x: (this\.referenceSecondSurfaceActive[^\n]+),/g)].map(m => m[1]);
  assert.equal(bindings.length, 2);
  Object.assign(p, { ovRectW: () => 400, ovVideoW: () => 400 });
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
  console.log('PASS: cold landscape geometry, repeated requests, unknown target isolation, rotated parts, cached reverse swipe, native buffer isolation');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
