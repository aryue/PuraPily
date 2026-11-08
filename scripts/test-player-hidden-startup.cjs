const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
function method(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, start);
  return source.slice(a, b);
}
const context = { exports: {}, logInfo() {}, LiveViewHelper: { updatePlayState() {} },
  PlayerService: { getInstance: () => ({ hasActivePlayer: false }) } };
const helpers = method('    private pagePlaybackAllowed(', '    /**',);
const hide = method('    onPageHide()', '    /**');
vm.runInNewContext(ts.transpileModule('export class Page {' + helpers + hide + '}', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
function gate() { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; }
function fixture() {
  const p = new context.exports.Page();
  const track = () => ({ state: 'prepared', plays: 0, pauses: 0,
    async play() { this.plays++; this.state = 'playing'; },
    async pause() { this.pauses++; this.state = 'paused'; } });
  Object.assign(p, { referenceAlive: true, playerPageVisible: true, bgp: false, appInBackground: false,
    userPaused_: false, play: false, av: track(), avAudio: track(),
    playbackListPrefetch: { pause() {} }, releaseReferenceFeedPreview() {} });
  return p;
}
async function main() {
  for (const bgp of [false, true]) {
    const p = fixture(); p.bgp = bgp;
    p.onPageHide();
    assert.equal(await p.startPagePlayback(p.av), false, 'late prepare after navigation must not start');
    assert.equal(p.av.plays + p.avAudio.plays, 0);
    assert.equal(p.av.pauses, 0, 'preparing/prepared player cannot be paused');
    p.playerPageVisible = true;
    assert.equal(await p.startPagePlayback(p.av), true, 'return resumes a prepared player');
    assert.equal(p.avAudio.plays, 1);
    p.play = true; p.onPageHide();
    assert.equal(p.av.state, 'paused'); assert.equal(p.avAudio.state, 'paused');
  }
  for (const duringAudio of [false, true]) {
    const p = fixture(), pending = gate(), track = duringAudio ? p.avAudio : p.av;
    track.play = async function () { this.plays++; await pending.promise; this.state = 'playing'; };
    const starting = p.startPagePlayback(p.av);
    await Promise.resolve();
    p.onPageHide(); pending.resolve();
    assert.equal(await starting, false, 'native play completion after hide must be stopped');
    assert.notEqual(p.av.state, 'playing'); assert.notEqual(p.avAudio.state, 'playing');
    if (!duringAudio) assert.equal(p.avAudio.plays, 0);
  }
  const seek = fixture(), waiting = gate();
  const resume = (async () => { await waiting.promise; return seek.startPagePlayback(seek.av); })();
  seek.onPageHide(); waiting.resolve();
  assert.equal(await resume, false, 'late resume seek must not start');
  const paused = fixture(); paused.userPaused_ = true;
  assert.equal(await paused.startPagePlayback(paused.av), false);
  const background = fixture(); background.bgp = true; background.appInBackground = true;
  background.onPageHide();
  assert.equal(await background.startPagePlayback(background.av), true, 'confirmed background playback remains allowed');
  const retired = fixture(), old = retired.av; retired.av = {};
  assert.equal(await retired.startPagePlayback(old), false);
  // Verify actual compiled startup callbacks route every audible start through the guard.
  const prepared = method("        case 'prepared':", "        case 'completed':");
  assert.ok(prepared.includes('startPagePlayback(player, false)'));
  assert.ok(prepared.includes('startPagePlayback(player)'));
  assert.equal((prepared.match(/\.play\(\)/g) || []).length, 1, 'only muted feed-frame preparation may play directly');
  console.log('PASS: compiled hidden-page prepare/seek/native-play races, dual-track pause, return, user pause, background and retired ownership');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
