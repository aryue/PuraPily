const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.join(__dirname, '..');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;

// 退出播放页时，播控中心只应跟着仍在继续的后台播放保留下来。
// 暂停、播完、出错，或播放器仍归页面所有（release() 会把它一起停掉）都必须释放。
const pageSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');
const terminal = pageSource.match(/  private playbackIsTerminal\(\): boolean \{[\s\S]*?\n  \}/);
const keep = pageSource.match(/  private backgroundPlaybackOutlivesPage\(\): boolean \{[\s\S]*?\n  \}/);
assert.ok(terminal && keep, 'playback exit helpers must exist');

let service = { hasActivePlayer: false, videoPlayer: null };
const pageContext = {
  exports: {},
  PlayerService: { getInstance: () => service },
  logInfo() {}
};
vm.runInNewContext(compile(`export class Page {\n${terminal[0]}\n${keep[0]}\n}`), pageContext);
const Page = pageContext.exports.Page;

function page(state) {
  const value = new Page();
  Object.assign(value, {
    bgp: true, play: true, referencePlaybackCompleted: false,
    playbackResources_: { video: null }
  }, state);
  return value;
}

service = { hasActivePlayer: true, videoPlayer: { state: 'playing' } };
assert.equal(page({}).backgroundPlaybackOutlivesPage(), true,
  'handed-off background playback that is still playing keeps the media session');

service = { hasActivePlayer: false, videoPlayer: null };
assert.equal(page({}).backgroundPlaybackOutlivesPage(), false,
  'the page-owned player is released on exit, so the session must end');

service = { hasActivePlayer: true, videoPlayer: { state: 'playing' } };
assert.equal(page({ play: false }).backgroundPlaybackOutlivesPage(), false,
  'paused playback has no background consumer');
assert.equal(page({ bgp: false }).backgroundPlaybackOutlivesPage(), false,
  'background playback disabled must always release');
assert.equal(page({ referencePlaybackCompleted: true }).backgroundPlaybackOutlivesPage(), false,
  'completed playback is terminal');

service = { hasActivePlayer: true, videoPlayer: { state: 'paused' } };
assert.equal(page({}).backgroundPlaybackOutlivesPage(), false,
  'a paused handed-off player must release the media session');
service = { hasActivePlayer: true, videoPlayer: { state: 'error' } };
assert.equal(page({}).backgroundPlaybackOutlivesPage(), false,
  'a failed handed-off player must release the media session');

// 页面退出与最小化退出都必须走同一个判据，不能退回只看 bgp 的旧分支。
const disappear = pageSource.slice(pageSource.indexOf('  aboutToDisappear() {'),
  pageSource.indexOf('  private async sendHeartbeat()', pageSource.indexOf('  aboutToDisappear() {')));
assert.match(disappear, /this\.backgroundPlaybackOutlivesPage\(\)/,
  'aboutToDisappear must use the playback-continuation judgement');
assert.match(disappear, /LiveViewHelper\.end\(\)/, 'aboutToDisappear must release the session');
assert.doesNotMatch(disappear, /if \(!this\.bgp\)/,
  'aboutToDisappear must not keep the session merely because bgp is enabled');

const minimize = pageSource.slice(pageSource.indexOf('  private async minimizeToFloating()'),
  pageSource.indexOf('  private async resumeFromMinimized()'));
assert.match(minimize, /this\.backgroundPlaybackOutlivesPage\(\)/,
  'minimizing to the floating window must use the same judgement');
assert.match(minimize, /LiveViewHelper\.end\(\)/, 'minimizing while stopped must release the session');
assert.doesNotMatch(minimize, /if \(!this\.bgp\)/, 'minimizing must not retain a paused session');

// 浮窗/后台播放已经到结尾：先发布完成态，再释放播控中心。
const floatingSource = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/FloatingPiP.ets'), 'utf8');
const stateField = floatingSource.match(
  /  private onPlaybackState_: \(state: string\) => void = \(state: string\): void => \{[\s\S]*?\n  \};/);
assert.ok(stateField, 'floating playback state handler must exist');

const events = [];
const video = { duration: 90000 };
const floatingService = {
  videoPlayer: video, playbackState: '', playerState: { isPlaying: true }, hasActivePlayer: true
};
const floatingContext = {
  exports: {},
  PlayerService: { getInstance: () => floatingService },
  LiveViewHelper: {
    updateProgress(seconds) { events.push(['progress', seconds]); },
    updatePlayState(playing) { events.push(['state', playing]); },
    end() { events.push(['end']); }
  }
};
vm.runInNewContext(compile(`export class Floating {\n${stateField[0]}\n}`), floatingContext);
const Floating = floatingContext.exports.Floating;
const floating = new Floating();
floating.observedVideo_ = video;
floating.syncPlayback = () => events.push(['sync']);

floating.onPlaybackState_('completed');
assert.deepEqual(events, [['progress', 90], ['state', false], ['end'], ['sync']],
  'floating completion publishes the final state, ends the session, then syncs cards');

events.length = 0;
floating.onPlaybackState_('playing');
assert.deepEqual(events, [['state', true], ['sync']], 'ongoing floating playback keeps the session');
events.length = 0;
floating.onPlaybackState_('paused');
assert.deepEqual(events, [['state', false], ['sync']], 'floating pause alone keeps the controls');

console.log('PASS: media session survives only while handed-off background playback continues; '
  + 'page exit, minimization and floating completion release stopped sessions');
