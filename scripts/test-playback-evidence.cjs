// Exercise the CompileArkTS output, with asynchronous file I/O backed by real files.
const fs = require('node:fs');
const fsp = fs.promises;
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/';
const source = fs.readFileSync(compiled + 'PlaybackEvidence.ts', 'utf8');
let now = 100000, writeCount = 0, failWrites = false;
const handles = new Map(); let nextFd = 0;
const io = {
  OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
  stat: p => fsp.stat(p), readText: p => fsp.readFile(p, 'utf8'), unlink: p => fsp.unlink(p),
  rename: (from, to) => fsp.rename(from, to),
  async open(p) { if (failWrites) throw Error('simulated I/O failure'); const h = await fsp.open(p, 'w');
    const fd = ++nextFd; handles.set(fd, h); return { fd }; },
  async write(fd, text) { writeCount++; return handles.get(fd).write(text); },
  async close(file) { await handles.get(file.fd).close(); handles.delete(file.fd); }
};
function load() {
  const privacy = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(compiled + 'PrivacyLog.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, privacy);
  const timers = new Map(); let nextTimer = 0;
  const context = { exports: {}, Date: { now: () => now },
    setTimeout(fn) { timers.set(++nextTimer, fn); return nextTimer; }, clearTimeout(id) { timers.delete(id); },
    require(name) {
      if (name.includes('fileIo') || name === '@ohos:file.fs') return { default: io };
      if (name.includes('PrivacyLog')) return privacy.exports;
      throw Error(name);
    } };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020 } }).outputText, context);
  return { e: context.exports, timers };
}
(async () => {
  const dir = await fsp.mkdtemp(path.resolve('.local/playback-evidence-test-'));
  try {
    const { e, timers } = load(); e.setPlaybackEvidenceDirectory(dir); await e.playbackEvidenceReady();
    for (let i = 0; i < 3000; i++) { now += 20; e.recordPlaybackEvidence(JSON.stringify({ event: 'sample', n: i }), now); }
    assert.equal(writeCount, 0, 'normal playback has no evidence disk writes');
    e.recordPlaybackEvidence('old-secret-url https://example.invalid/private', now);
    e.triggerPlaybackEvidence(7, 'stall-position');
    e.recordPlaybackEvidence('after-trigger', now + 1000);
    let text = await e.readPlaybackEvidence();
    assert.match(text, /after-trigger/); assert.ok(!text.includes('example.invalid'));
    let packets = JSON.parse(await fsp.readFile(path.join(dir, 'playback_faults.json'), 'utf8'));
    assert.equal(packets.length, 1); assert.equal(packets[0].complete, false);
    assert.ok(packets[0].records.length <= 1500); assert.ok(!text.includes('"n":0}'));
    e.triggerPlaybackEvidence(7, 'player-error');
    assert.equal(JSON.parse((await e.readPlaybackEvidence()).split(' ===\n')[1]).length, 1, 'same fault coalesces');
    [...timers.values()][0]();
    await e.readPlaybackEvidence();
    packets = JSON.parse(await fsp.readFile(path.join(dir, 'playback_faults.json'), 'utf8'));
    assert.equal(packets[0].complete, true);
    const restarted = load().e; restarted.setPlaybackEvidenceDirectory(dir);
    await restarted.playbackEvidenceReady(); assert.match(await restarted.readPlaybackEvidence(), /after-trigger/);
    for (let i = 0; i < 4; i++) { now += 31000; restarted.triggerPlaybackEvidence(i + 10, 'player-error'); restarted.sealPlaybackEvidence(); }
    await restarted.readPlaybackEvidence();
    packets = JSON.parse(await fsp.readFile(path.join(dir, 'playback_faults.json'), 'utf8'));
    assert.equal(packets.length, 3); assert.equal(packets[2].root, 13);
    assert.ok((await fsp.stat(path.join(dir, 'playback_faults.json'))).size < 2 * 1024 * 1024);
    // Clear must invalidate the pending startup restore and queued snapshots.
    const clearing = load().e; clearing.setPlaybackEvidenceDirectory(dir); clearing.clearPlaybackEvidence();
    assert.equal(await clearing.readPlaybackEvidence(), '');
    assert.equal(fs.existsSync(path.join(dir, 'playback_faults.json')), false);
    failWrites = true; now += 31000; clearing.triggerPlaybackEvidence(20, 'stall-position');
    assert.match(await clearing.readPlaybackEvidence(), /stall-position/, 'I/O failure retains exportable memory evidence');
    console.log('PASS: compiled fault capture, real async disk persistence, pre/post window, rotation, restart, clear races, privacy and I/O failure');
  } finally { await fsp.rm(dir, { recursive: true, force: true }); }
})().catch(error => { console.error(error); process.exitCode = 1; });
