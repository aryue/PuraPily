const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(base + 'services/LiveViewHelper.ts', 'utf8').replace(/^import .*;\r?\n/gm, '');
const states = [];
let releaseActivation;
const session = { async setAVMetadata() {}, async setAVPlaybackState(s) { states.push(s); },
  activate() { return new Promise(resolve => { releaseActivation = resolve; }); },
  on() {}, async setLaunchAbility() {} };
const context = { exports: {}, Date, logInfo() {}, logWarn() {}, errMsg: String,
  avSession: { PlaybackState: { PLAYBACK_STATE_PLAY: 1, PLAYBACK_STATE_PAUSE: 2 },
    async createAVSession() { return session; } },
  wantAgent: { OperationType: {}, WantAgentFlags: {}, async getWantAgent() { return {}; } },
  backgroundTaskManager: { BackgroundMode: {}, async startBackgroundRunning() {} } };
vm.runInNewContext(ts.transpileModule(source, {compilerOptions: {
  module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
}}).outputText, context);
const helper = context.exports.LiveViewHelper;
const tick = () => new Promise(resolve => setImmediate(resolve));
async function main() {
  const creating = helper.create({abilityInfo: {}}, 'test', '', 'video', 75);
  while (!releaseActivation) await tick();
  // Completion during asynchronous activation must survive the initial PLAY write.
  helper.updateProgress(75);
  helper.updatePlayState(false);
  releaseActivation();
  await creating;
  assert.equal(states.at(-1).state, 2);
  assert.equal(states.at(-1).position.elapsedTime, 75000);
  // Execute the actual compiled page completion branch, including auto-play ordering.
  const page = fs.readFileSync(base + 'pages/VideoPlayerPage.ts', 'utf8');
  const start = page.indexOf("case 'completed':");
  const end = page.indexOf("case 'paused':", start);
  assert.ok(start >= 0 && end > start);
  const branch = page.slice(start, end);
  const handle = vm.runInNewContext('(function(){switch("completed"){' + branch + '}})',
    {LiveViewHelper: helper, clearTimeout});
  const p = { dur: 75, ct_: -1, referenceLayout: true, saveWatchHistory() {}, cancelDelayHide() {},
    referenceOnCompleted() { assert.equal(states.at(-1).state, 2); } };
  handle.call(p);
  assert.equal(p.play, false);
  assert.equal(p.referencePlaybackCompleted, true);
  assert.equal(states.at(-1).state, 2);
  assert.equal(states.at(-1).position.elapsedTime, 75000);
  helper.updateProgress(0);
  helper.updatePlayState(true);
  assert.equal(states.at(-1).state, 1);
  assert.equal(states.at(-1).position.elapsedTime, 0);
  helper.updatePlayState(false);
  assert.equal(states.at(-1).state, 2);
  console.log('PASS: compiled completion publishes paused/final position before auto-play; activation race, replay and pause');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
