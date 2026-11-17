const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = new URL('../entry/src/main/ets/', require('node:url').pathToFileURL(__filename));
function load(file, modules = {}) {
  const source = fs.readFileSync(new URL(file, root), 'utf8');
  const exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, require: name => modules[name] ?? {} });
  return exports;
}

async function main() {
  const model = load('model/OfflineCacheItem.ts');
  const { CacheStatus } = model;
  const files = new Map([['video', 90], ['audio', 10]]);
  const { OfflineCacheService } = load('services/OfflineCacheService.ets', {
    '../model/OfflineCacheItem': model,
    '@kit.CoreFileKit': { fileIo: { statSync(path) {
      if (!files.has(path)) throw new Error('missing file');
      return { size: files.get(path) };
    } } }
  });
  const service = new OfflineCacheService();
  const request = { bvid: 'BVtest', cid: 1, title: '', cover: '', quality: 16, qualityLabel: '360P' };
  const entry = {
    status: CacheStatus.COMPLETED, quality: 16, videoPath: 'video', audioPath: 'audio', totalBytes: 100
  };
  let downloads = 0;
  service.getCachedItem = () => entry;
  service.download = async item => {
    downloads++;
    assert.equal(item.status, CacheStatus.WAIT);
    assert.equal(item.title, '未命名视频');
    return true;
  };
  const context = { filesDir: 'files' };
  assert.equal(await service.downloadVideo(context, request), CacheStatus.COMPLETED);
  assert.equal(downloads, 0, 'repeating a complete download should not issue a Range request');
  await service.downloadVideo(context, { ...request, quality: 32 });
  assert.equal(downloads, 1, 'a different requested quality still goes through the existing downloader');
  files.delete('audio');
  await service.downloadVideo(context, request);
  assert.equal(downloads, 2, 'a missing audio track cannot count as a complete cache');
  files.set('audio', 9);
  await service.downloadVideo(context, request);
  assert.equal(downloads, 3, 'truncated local tracks cannot count as a complete cache');
  entry.status = CacheStatus.PAUSED;
  service.download = async () => false;
  assert.equal(await service.downloadVideo(context, request), CacheStatus.PAUSED);
  entry.status = CacheStatus.FAILED;
  assert.equal(await service.downloadVideo(context, request), CacheStatus.FAILED);
  console.log('PASS: completed cache reuse, quality changes, missing or truncated files, paused and failed results');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
