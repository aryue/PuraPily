const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');
const start = source.indexOf('  private async cropStillToPicture(');
const end = source.indexOf('  private async prepareReferenceFeedPreview(', start);
assert.ok(start > 0 && end > start);
const context = { exports: {}, logInfo() {}, logWarn(error) { throw new Error(error); } };
const geometryStart = source.indexOf('  private referenceWarmSurfaceWidth(');
const geometryEnd = source.indexOf('  private activeVideoSurfaceId(', geometryStart);
assert.ok(geometryStart > 0 && geometryEnd > geometryStart);
const aspectStart = source.indexOf('  private referenceFeedAspect(');
const aspectEnd = source.indexOf('  private referencePreviewPresentationLocked(', aspectStart);
assert.ok(aspectStart > 0 && aspectEnd > aspectStart);
const displayStart = source.indexOf('  private displayAspect(');
const displayEnd = source.indexOf('\n  }', displayStart) + '\n  }'.length;
assert.ok(displayStart > 0 && displayEnd > displayStart);
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${source.slice(start, end)} ${source.slice(geometryStart, geometryEnd)} ${source.slice(aspectStart, aspectEnd)}
  ${source.slice(displayStart, displayEnd)}
}`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);

// Track the PixelMap operations: IJK requires whole-image scaling, whereas
// AVPlayer's letterboxed buffer requires a centered crop.
function bitmap(width, height) {
  return {
    width, height, cropped: false, scaled: false,
    getImageInfoSync() { return { size: { width: this.width, height: this.height } }; },
    async crop(rect) { this.cropped = true; this.rect = rect; this.width = rect.size.width; this.height = rect.size.height; },
    async scale(x, y) { this.scaled = true; this.width = Math.round(this.width * x); this.height = Math.round(this.height * y); }
  };
}
async function main() {
  const page = new context.exports.Page();
  Object.assign(page, { cw: 440, ch: 744, referenceAreaHeight: () => 248, portraitScaleByTransform: () => true });
  for (const [current, upcoming] of [[16 / 9, 9 / 16], [9 / 16, 16 / 9]]) {
    Object.assign(page, { ar: current, referenceWarmAspectRatio: upcoming });
    const width = Math.min(440, 744 * upcoming);
    assert.equal(page.referenceWarmSurfaceWidth(), width);
    assert.equal(page.referenceWarmSurfaceHeight(), width / upcoming);
  }
  assert.match(source, /\.width\(this\.referenceSecondSurfaceActive \? this\.referenceWarmSurfaceWidth\(\)/);
  assert.match(source, /\.height\(this\.referenceSecondSurfaceActive \? this\.referenceWarmSurfaceHeight\(\)/);
  assert.match(source, /\.width\(this\.referenceSecondSurfaceActive \? [^\n]+ : this\.referenceWarmSurfaceWidth\(\)\)/);
  assert.match(source, /\.height\(this\.referenceSecondSurfaceActive \? [^\n]+ : this\.referenceWarmSurfaceHeight\(\)\)/);
  const pinned = source.slice(source.indexOf('  ReferenceFeedPinnedPage()'), source.indexOf('  ReferenceFeedPreviewPage()'));
  assert.match(pinned, /referenceMediaHeight\(this\.referencePinnedAspectRatio\)/);
  assert.doesNotMatch(pinned, /this\.ar\b/, 'live decoder dimensions must not resize a pinned frame or cover');
  const rotated = page.referenceFeedAspect({ cid: 2, dimension: { width: 1920, height: 1080, rotate: 90 } }, 2, 0);
  assert.equal(rotated, 9 / 16);
  assert.equal(page.referenceFeedAspect({ cid: 2, dimension: { width: 3840, height: 2160, rotate: 1 } }, 2, 0), rotated);
  assert.equal(page.referenceFeedDisplayAspect(rotated, 16 / 9), rotated, 'encoded dimensions must not undo display rotation');
  assert.equal(page.referenceFeedDisplayAspect(16 / 9, 3 / 4), 3 / 4);
  assert.equal(page.referenceFeedAspect({ cid: 2, dimension: { width: 1920, height: 1080 } }, 3, 0), 0);
  for (const [width, height, aspect] of [[1920, 1080, 9 / 16], [720, 1280, 16 / 9], [1920, 1080, 3 / 4]]) {
    const ijk = bitmap(width, height);
    assert.equal(await page.cropStillToPicture(ijk, aspect, true), ijk);
    assert.equal(ijk.cropped, false, 'IJK contains real picture pixels at the buffer edges');
    assert.equal(ijk.scaled, true);
    assert.ok(Math.abs(ijk.width / ijk.height / aspect - 1) < 0.002);
    const av = bitmap(width, height);
    await page.cropStillToPicture(av, aspect, false);
    assert.equal(av.cropped, true, 'AVPlayer FIT output still removes letterbox bars');
    assert.equal(av.scaled, false);
  }
  const unchanged = bitmap(1920, 1080);
  await page.cropStillToPicture(unchanged, 16 / 9, true);
  assert.equal(unchanged.cropped || unchanged.scaled, false);
  console.log('PASS: landscape to portrait, portrait to landscape, 4:3, matching aspect, AVPlayer letterbox');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
