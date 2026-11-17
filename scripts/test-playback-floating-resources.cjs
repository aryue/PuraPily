const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/src/main/ets/services/PlaybackResources.ets', 'utf8');
const closed = [];
const fileIo = {
  OpenMode: { READ_ONLY: 0 },
  openSync: () => ({ fd: 42 }),
  closeSync: file => closed.push(file.fd)
};
const ticks = [];
const context = { exports: {}, setTimeout: callback => ticks.push(callback), require: () => ({ logInfo() {}, logWarn() {}, fileIo }) };
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, context);
const { PlaybackResources } = context.exports;
const events = [];
const video = { off(name) { events.push(name); }, async release() { events.push('release'); } };
const service = {
  videoPlayer: video, audioPlayer: null, hasActivePlayer: true, playerState: {},
  setDashServer(value) { this.bridge = value; },
  takeDashServer() { const value = this.bridge; this.bridge = null; return value; }
};
let stops = 0;
const bridge = { async stop() { stops++; } };
(async () => {
  const oldPage = new PlaybackResources();
  const reopened = new PlaybackResources();
  const finalPage = new PlaybackResources();
  oldPage.video = video;
  oldPage.bridge = bridge;
  oldPage.handOffToFloating(service, () => assert.ok(events.includes('timeUpdate')));
  await Promise.all(oldPage.release());
  assert.equal(stops, 0);
  assert.equal(reopened.restoreFromFloating(service), true);
  assert.equal(reopened.video, video);
  assert.equal(service.videoPlayer, null);
  service.videoPlayer = video;
  reopened.handOffToFloating(service, () => {});
  await Promise.all(reopened.release());
  assert.equal(stops, 0, 'reopening PiP must transfer the restored bridge again');
  assert.equal(finalPage.restoreFromFloating(service), true);
  await Promise.all(finalPage.release());
  await Promise.all(finalPage.release());
  assert.equal(stops, 1);
  assert.equal(events.filter(event => event === 'release').length, 1);
  const quality = new PlaybackResources();
  const old = { setVolume(value) { this.volume = value; } };
  const audio = { setVolume(value) { this.volume = value; } };
  quality.video = old;
  quality.audio = audio;
  quality.restoredBridge = bridge;
  const replacement = {};
  const retired = quality.replaceForQuality({ video: replacement, audioPlayer: null, bridge: null }, old);
  assert.equal(retired.video, old);
  assert.equal(retired.audioPlayer, audio);
  assert.equal(retired.bridge, bridge);
  assert.equal(old.volume, 0);
  assert.equal(audio.volume, 0);
  assert.equal(quality.video, replacement);
  assert.equal(quality.restoredBridge, null);
  const offline = new PlaybackResources();
  const rejected = { set fdSrc(source) {
    assert.equal(source.fd, 42);
    throw Error('native source rejected');
  } };
  assert.throws(() => offline.bindOfflineSource(rejected, '/cache/video', true), /rejected/);
  await Promise.all(offline.release());
  await Promise.all(offline.release());
  assert.deepEqual(closed, [42], 'failed native assignment retains the file until one cleanup');
  const retiring = new PlaybackResources();
  const cleanup = [];
  let reentrantReleases = -1;
  retiring.video = {
    off() {
      reentrantReleases = retiring.release().length;
      throw Error('native detach failed');
    },
    async release() { cleanup.push('video'); }
  };
  retiring.audio = { off() {}, async release() { cleanup.push('audio'); } };
  retiring.bridge = { async stop() { cleanup.push('bridge'); } };
  await Promise.all(retiring.release());
  assert.equal(reentrantReleases, 0);
  assert.deepEqual(cleanup, ['video', 'audio', 'bridge']);
  const controls = new PlaybackResources();
  let finishPause;
  const previous = { pause: () => new Promise(resolve => { finishPause = resolve; }) };
  let pausedAudio = 0;
  controls.video = previous;
  controls.audio = { async pause() { pausedAudio++; } };
  const pausing = controls.setPlaying(previous, false, () => true);
  controls.video = {};
  controls.audio = { async pause() { pausedAudio++; } };
  finishPause();
  assert.equal(await pausing, false);
  assert.equal(pausedAudio, 0, 'late pause cannot touch either old or replacement audio');
  let speedUpdates = 0;
  let finishSpeed;
  controls.video = { setSpeed: () => new Promise(resolve => { finishSpeed = resolve; }) };
  controls.audio = { async setSpeed() { speedUpdates++; } };
  let latest = true;
  const changing = controls.setSpeed(4, () => latest);
  latest = false;
  finishSpeed();
  assert.equal(await changing, false);
  assert.equal(speedUpdates, 0, 'superseded speed cannot propagate to audio');
  const pageSource = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8');
  const toggleStart = pageSource.indexOf('  async togglePP()');
  const toggleEnd = pageSource.indexOf('  /**', toggleStart);
  assert.ok(toggleStart > 0 && toggleEnd > toggleStart);
  const liveView = [];
  Object.assign(context, {
    LiveViewHelper: { updatePlayState(playing) { liveView.push(playing); } },
    PlaybackAudioSession: { async activate() {} }
  });
  vm.runInNewContext(ts.transpileModule(
    'exports.Page = class Page {' + pageSource.slice(toggleStart, toggleEnd) + '}',
    { compilerOptions: { target: ts.ScriptTarget.ES2020 } }
  ).outputText, context);
  const page = new context.exports.Page();
  const active = new PlaybackResources();
  const actions = [];
  active.video = { currentTime: 3000, async pause() { actions.push('video pause'); },
    async play() { actions.push('video play'); } };
  active.audio = { async pause() { actions.push('audio pause'); }, async play() { actions.push('audio play'); } };
  Object.assign(page, {
    playbackResources_: active, play: true, userPaused_: false,
    cancelDelayHide() {}, markAutoPlay() {}
  });
  await page.togglePP();
  assert.equal(page.play, false);
  assert.equal(page.userPaused_, true);
  await page.togglePP();
  assert.equal(page.play, true);
  assert.equal(page.userPaused_, false);
  assert.deepEqual(actions, ['video pause', 'audio pause', 'video play', 'audio play']);
  assert.deepEqual(liveView, [false, true]);
  const volumes = [];
  const fading = new PlaybackResources();
  fading.video = {};
  fading.audio = { setVolume(value) { volumes.push(value); } };
  fading.rampAudio(0, 60);
  ticks.shift()();
  assert.ok(fading.audioGain < 1);
  fading.video = {};
  ticks.shift()();
  assert.equal(volumes.length, 1, 'a fade cannot touch audio after its video is replaced');
  fading.rampAudio(1, 60);
  fading.audioGain = 1;
  ticks.shift()();
  assert.equal(volumes.length, 1, 'an explicit gain reset cancels pending steps');
  fading.rampAudio(0, 60);
  while (ticks.length > 0) ticks.shift()();
  assert.equal(volumes.at(-1), 0);
  assert.equal(fading.audioGain, 0);
  console.log('PASS: PiP transfers the same player and bridge across repeated restores');
})().catch(error => { console.error(error); process.exitCode = 1; });
