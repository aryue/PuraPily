const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const source = fs.readFileSync('entry/src/main/ets/services/VideoShotService.ets', 'utf8');
const requests = [];
const timers = new Map();
let timerId = 0;
function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}
function frame() {
  return { releases: 0, async release() { this.releases++; } };
}
const context = {
  exports: {},
  require(module) {
    if (module.endsWith('/VideoShotApi')) {
      return { fetchVideoShot(bvid, cid) {
        const request = deferred();
        requests.push({ bvid, cid, ...request });
        return request.promise;
      } };
    }
    return {};
  },
  setTimeout(callback) {
    const id = ++timerId;
    timers.set(id, callback);
    return id;
  },
  clearTimeout(id) { timers.delete(id); }
};
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const { VideoShotService } = context.exports;
const data = { index: [0], image: ['sprite'], imgXLen: 1, imgYLen: 1, imgXSize: 160, imgYSize: 90 };
const tick = () => new Promise(resolve => setImmediate(resolve));
function service() {
  const shots = new VideoShotService();
  shots.downloadSprite = async () => new ArrayBuffer(1);
  shots.setOwner('BVexample', 1);
  return shots;
}

async function main() {
  const oldPage = service();
  const nextPage = service();
  const nextFrame = frame();
  nextPage.decodeCell = async () => nextFrame;
  const nextWork = nextPage.getFrame('BVexample', 1, 0);
  const oldDecode = deferred();
  oldPage.decodeCell = () => oldDecode.promise;
  const oldWork = oldPage.getFrame('BVexample', 1, 0);
  assert.equal(requests.length, 2, 'each page owns its in-flight cache');
  requests[0].resolve(data);
  requests[1].resolve(data);
  assert.equal((await nextWork).pm, nextFrame);
  await tick();
  oldPage.release();
  const oldFrame = frame();
  oldDecode.resolve(oldFrame);
  assert.equal(await oldWork, undefined);
  assert.equal(oldFrame.releases, 1);
  assert.equal(nextFrame.releases, 0);
  assert.equal((await nextPage.getFrame('BVexample', 1, 0)).pm, nextFrame);
  nextPage.release();
  assert.equal(nextFrame.releases, 1);

  const switched = service();
  switched.decodeCell = async () => frame();
  switched.schedulePrefetch('BVexample', 1);
  const oldTimer = [...timers.values()].at(-1);
  const first = switched.getFrame('BVexample', 1, 0);
  switched.setOwner('BVother', 2);
  switched.setOwner('BVexample', 1);
  switched.schedulePrefetch('BVexample', 1);
  const replacement = switched.getFrame('BVexample', 1, 0);
  requests[2].resolve(undefined);
  assert.equal(await first, undefined);
  oldTimer();
  const duplicate = switched.getFrame('BVexample', 1, 0);
  assert.equal(requests.length, 4, 'old completion neither deletes nor poisons the replacement request');
  requests[3].resolve(data);
  const result = await replacement;
  assert.equal((await duplicate).pm, result.pm, 'duplicate cell decodes retain one owned frame');
  switched.release();
  assert.equal(result.pm.releases, 1);
  assert.equal(timers.size, 0, 'a retired timer callback cannot lose the replacement timer handle');
  console.log('PASS: page-scoped seek thumbnails, retired decode cleanup and same-CID replacement');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
