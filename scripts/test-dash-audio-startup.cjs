const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const gate = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const tick = () => new Promise(resolve => setImmediate(resolve));
function load(name, dependencies = {}) {
  const context = { exports: {}, console: { info() {}, warn() {}, error() {} },
    require: id => Object.entries(dependencies).find(([key]) => id.includes(key))?.[1] || {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root + name + '.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
function fixture() {
  const first = gate(), resume = gate(), video = gate(); const requests = [], events = [];
  let server;
  const segment = { timescale: 1000, segments: [{ fileOffset: 100, size: 100, duration: 5000 }],
    initRange: '0-99', indexRange: '', contentLength: 200 };
  const { DashPlayerBridge: Bridge } = load('services/DashPlayerBridge', {
    PlaybackStartup: { PlaybackStartup: { span: () => ({ mark: e => events.push(e), end() {} }) } },
    DashQuality: load('utils/DashQuality'), DashMpdBuilder: load('services/DashMpdBuilder'),
    DashProbe: { probeM4sInitSegment: async () => segment },
    DashCdnRoute: { DashCdnRoute: class {} },
    DashMediaServer: { DashMediaServer: class {
      constructor() { server = this; this.stops = 0; }
      setConfig() {}
      canRetainStartupSegments() { return true; }
      prefetchSegment(isVideo, index, prefix=0) { requests.push([isVideo, index, prefix]); return isVideo ? video.promise : first.promise; }
      prefetchSegmentAtTime(isVideo, time, prefix=0) { requests.push([isVideo, time, prefix]); return isVideo ? video.promise : resume.promise; }
      async start() { this.listening = true; }
      getPort() { return 1234; }
      async stop() { this.stops++; first.resolve(false); resume.resolve(false); video.resolve(false); }
    } }
  });
  const dash = { quality: 125, timelength: 5000,
    videoStreams: [{ id: 125, codecid: 12, baseUrl: 'video' }], audioStreams: [{ id: 1, baseUrl: 'audio' }] };
  const bridge = new Bridge(null);
  return { bridge, first, resume, video, requests, events, server: () => server,
    start: time => bridge.buildAndStart(dash, '', '', '', time || 0) };
}
(async () => {
  {
    const f=fixture();
    let settled=false;const job=f.start().then(url=>{settled=true;return url;});await tick();
    f.first.resolve(true);await tick();assert.equal(settled,false);
    f.video.resolve(false);assert.equal(await job,null,'video failure cannot expose audio-only startup');
  }
  {
    const f = fixture(); let settled = false;
    const job = f.start().then(url => { settled = true; return url; }); await tick();
    assert.equal(f.server().listening, true);
    assert.equal(settled, false, 'late audio must not publish an apparently playable URL');
    assert.equal(f.bridge.isActive(), false);
    f.first.resolve(true); await tick(); assert.equal(settled,false,'prepared audio still waits for the validated video prefix');
    f.video.resolve(true);
    assert.equal(await job, 'http://127.0.0.1:1234/manifest.mpd');
    assert.equal(f.bridge.isActive(), true, 'complete audio and the validated video prefix expose the native source');
    assert.deepEqual(f.requests,[[true,0,262144],[false,0,0]],'only video uses prefix readiness; audio remains fully prepared');
    assert.ok(f.events.includes('audio-startup-ready')); await f.bridge.stop();
  }
  {
    const f = fixture(); let settled = false;
    const job = f.start(3500).then(url => { settled = true; return url; }); await tick();
    f.first.resolve(true); await tick();
    assert.equal(settled, false, 'resume must await its actual audio segment too');
    f.resume.resolve(true); f.video.resolve(true); assert.ok(await job); await f.bridge.stop();
    assert.deepEqual(f.requests,[[true,0,0],[false,0,0],[true,3500,0],[false,3500,0]],'resume/quality seeks keep complete video ranges to avoid the native range-start regression');
  }
  {
    const f = fixture(), job = f.start(); await tick(); f.first.resolve(false);
    assert.equal(await job, null); assert.equal(f.server().stops, 1);
    assert.equal(f.bridge.getServer(), null, 'failed audio cannot leak a listening server');
  }
  {
    const f = fixture(), job = f.start(); await tick();
    await f.bridge.stop(); assert.equal(await job, null);
    assert.equal(f.bridge.isActive(), false); assert.equal(f.bridge.getServer(), null);
  }
  console.log('PASS: compiled full-audio/video-prefix startup gate, resume, failure cleanup and cancellation');
})().catch(error => { console.error(error); process.exitCode = 1; });
