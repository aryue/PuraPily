const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const requests = [];
const decodes = [];
const http = {
  RequestMethod: { GET: 1 },
  HttpDataType: { ARRAY_BUFFER: 1 },
  HttpProtocol: { HTTP1_1: 1 },
  createHttp() {
    const record = {};
    requests.push(record);
    return {
      request: url => new Promise((resolve, reject) => Object.assign(record, { url, resolve, reject })),
      destroy: () => { record.destroyed = true; }
    };
  }
};
const image = {
  createImageSource() {
    const record = {};
    decodes.push(record);
    return {
      createPixelMap: () => new Promise(resolve => { record.resolve = resolve; }),
      release: async () => { record.released = true; }
    };
  }
};

const context = { exports: {}, require: name => name.includes('ImageKit') ? { image } : { http } };
const file = 'entry/src/main/ets/utils/ImageCache.ts';
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
}).outputText, context);
const { predecodeImage, getCachedPixelMap, clearImageCache } = context.exports;
const flush = () => new Promise(setImmediate);
const mib = 1024 * 1024;
const bitmap = (bytes = 5 * mib) => ({
  released: false,
  getPixelBytesNumber: () => bytes,
  async release() { this.released = true; }
});

async function startDecode(request) {
  request.resolve({ responseCode: 200, result: new ArrayBuffer(1) });
  await flush();
  assert.equal(request.destroyed, true);
  return decodes.at(-1);
}

async function cacheBitmap(url, frame = bitmap()) {
  const job = predecodeImage(url);
  const decode = await startDecode(requests.at(-1));
  decode.resolve(frame);
  await job;
  assert.equal(decode.released, true);
  return frame;
}

async function main() {
  const first = predecodeImage('a');
  assert.equal(predecodeImage('a'), first, 'the same URL shares one pending decode');
  assert.equal(requests.length, 1);
  const a = bitmap();
  (await startDecode(requests[0])).resolve(a);
  await first;

  const b = await cacheBitmap('b');
  assert.equal(getCachedPixelMap('a'), a, 'reading moves the image to the recent end');
  await cacheBitmap('c');
  assert.equal(getCachedPixelMap('b'), undefined, 'the byte budget evicts the least recently used image');
  assert.equal(b.released, false, 'eviction must not invalidate a bitmap borrowed by a mounted Image');

  const oldJob = predecodeImage('stale');
  const oldDecode = await startDecode(requests.at(-1));
  clearImageCache();
  const newJob = predecodeImage('stale');
  const late = bitmap();
  oldDecode.resolve(late);
  await oldJob;
  assert.equal(late.released, true, 'an unpublished bitmap is released across a clear');
  assert.equal(getCachedPixelMap('stale'), undefined);
  assert.equal(predecodeImage('stale'), newJob, 'old completion cannot remove a newer job');
  const fresh = bitmap();
  (await startDecode(requests.at(-1))).resolve(fresh);
  await newJob;
  assert.equal(getCachedPixelMap('stale'), fresh);

  const oversized = await cacheBitmap('large', bitmap(13 * mib));
  assert.equal(oversized.released, true);
  assert.equal(getCachedPixelMap('large'), undefined);
  const failure = predecodeImage('network-error');
  const failedRequest = requests.at(-1);
  failedRequest.reject(new Error('request failed'));
  await failure;
  assert.equal(failedRequest.destroyed, true, 'failed HTTP requests release their handle');
  await cacheBitmap('network-error');
  console.log('PASS image cache deduplication, LRU byte limit, stale decode release and retry');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
