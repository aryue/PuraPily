// Exercise the actual CompileArkTS output with controlled image-cache completion order.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/FeedAvatarImage.ts';
const cache = new Map(), pending = [], images = [], syncLoads = [];
const noop = () => {};
class Property {
  constructor(value, owner, name) { Object.assign(this, { value, owner, name }); }
  get() { return this.value; }
  set(value) {
    if (this.value === value) return;
    this.value = value;
    this.owner.watches?.[this.name]?.call(this.owner);
  }
  reset(value) { this.set(value); }
}
class View {
  watches = {};
  children = new Map();
  declareWatch(name, callback) { this.watches[name] = callback; }
  finalizeConstruction() {}
  observeComponentCreation2(callback) { callback(1, true); }
  ifElseBranchUpdateFunction(_branch, callback) { callback(); }
  forEachUpdateFunction(_id, items, create, keyOf) {
    const keys = new Set(items.map(keyOf));
    for (const [key, child] of this.children) {
      if (!keys.has(key)) { child.aboutToDisappear(); this.children.delete(key); }
    }
    for (const item of items) {
      const key = keyOf(item);
      if (this.children.has(key)) continue;
      View.create = child => { this.children.set(key, child); child.aboutToAppear(); };
      create(item);
    }
  }
}
const container = { create: noop, pop: noop, width: noop, height: noop };
const context = {
  exports: {}, ViewPU: View,
  SynchedPropertySimpleOneWayPU: Property, ObservedPropertyObjectPU: Property,
  Stack: container, If: container, ForEach: container, ImageFit: { Cover: 'cover' },
  Image: { create: source => images.push(source), syncLoad: value => syncLoads.push(value),
    width: noop, height: noop, borderRadius: noop, objectFit: noop },
  require: name => {
    assert.ok(name.includes('ImageCache'));
    return {
      getCachedPixelMap: url => cache.get(url),
      predecodeImage: url => new Promise(resolve => pending.push({ url, resolve }))
    };
  }
};
const source = fs.readFileSync(file, 'utf8') + '\nexport { DecodedFeedAvatar };';
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
}).outputText, context);
const { FeedAvatarImage, DecodedFeedAvatar } = context.exports;
const flush = async () => { await Promise.resolve(); await Promise.resolve(); };
const finish = async (job, bitmap) => {
  if (bitmap) cache.set(job.url, bitmap);
  job.resolve(); await flush();
};
async function main() {
  const pageSource = fs.readFileSync(file.replace('components/FeedAvatarImage.ts', 'pages/VideoPlayerPage.ts'), 'utf8');
  const pageAst = ts.createSourceFile('page.ts', pageSource, ts.ScriptTarget.Latest, true);
  const page = pageAst.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'VideoPlayerPage');
  const faceMethod = page.members.find(node => node.name?.getText(pageAst) === 'referenceCurrentAvatarFace');
  assert.ok(faceMethod, 'identity guard must survive CompileArkTS');
  const faceContext = { exports: {}, imageUrlResize: url => url };
  vm.runInNewContext(ts.transpileModule(`export class Page { ${faceMethod.getText(pageAst)} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS }
  }).outputText, faceContext);
  const ownerPage = new faceContext.exports.Page();
  ownerPage.vi = { bvid: 'B', ownerFace: 'new-face' };
  ownerPage.vd = { bvid: 'A', aid: 1, owner: { face: 'old-face' } };
  assert.equal(ownerPage.referenceCurrentAvatarFace(), 'new-face', 'a previous detail cannot supply the new avatar');
  ownerPage.vi.ownerFace = '';
  assert.equal(ownerPage.referenceCurrentAvatarFace(), '', 'missing new face cannot fall back to the old author');
  ownerPage.vi.bvid = '1';
  assert.equal(ownerPage.referenceCurrentAvatarFace(), 'old-face', 'numeric AV identity remains supported');

  const a = { pixels: 'A' }, b = { pixels: 'B' };
  cache.set('warm', a);
  const warm = new DecodedFeedAvatar(null, { face: 'warm' });
  warm.aboutToAppear(); warm.initialRender();
  assert.equal(warm.bitmap, a);
  assert.equal(pending.length, 0, 'warm avatars never start a network request');
  assert.equal(images.pop(), a);
  assert.equal(syncLoads.pop(), true, 'compiled Image must load its bitmap synchronously');

  const cold = new DecodedFeedAvatar(null, { face: 'cold' });
  cold.aboutToAppear(); cold.initialRender();
  assert.equal(images.length, 0, 'cold avatars cannot render a URL or an old image');
  await finish(pending.shift(), b);
  assert.equal(cold.bitmap, b, 'cold decode completion must fill the mounted avatar');

  const stale = new DecodedFeedAvatar(null, { face: 'old' });
  stale.aboutToAppear(); const oldJob = pending.shift();
  stale.updateStateVars({ face: 'new' }); const newJob = pending.shift();
  await finish(newJob, b); await finish(oldJob, a);
  assert.equal(stale.bitmap, b, 'out-of-order completion cannot restore a previous face');

  const removed = new DecodedFeedAvatar(null, { face: 'removed' });
  removed.aboutToAppear(); const removedJob = pending.shift();
  removed.aboutToDisappear(); await finish(removedJob, a);
  assert.equal(removed.bitmap, undefined, 'unmounted avatar ignores a late decode');

  const failed = new DecodedFeedAvatar(null, { face: 'failed' });
  failed.aboutToAppear(); await finish(pending.shift());
  assert.equal(failed.bitmap, undefined, 'failure never substitutes another avatar');

  const feed = new FeedAvatarImage(null, { videoId: 'video-A', face: 'warm' });
  feed.initialRender(); const first = [...feed.children.values()][0];
  feed.initialRender();
  assert.equal([...feed.children.values()][0], first, 'ordinary rerender retains its Image subtree');
  feed.updateStateVars({ videoId: 'video-B', face: 'warm' }); feed.initialRender();
  assert.notEqual([...feed.children.values()][0], first, 'a different video gets a different Image subtree');
  assert.equal(first.alive, false, 'previous video is invalidated even with the same face URL');
  assert.equal(pending.length, 0);
  console.log('PASS: compiled avatar rendering, cold/warm cache, stale completion, disposal, failure, and per-video node identity.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
