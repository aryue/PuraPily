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
vm.runInNewContext(ts.transpileModule(`export class Page { ${source.slice(start, end)} }`, {
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
