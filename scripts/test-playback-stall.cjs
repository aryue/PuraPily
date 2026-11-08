const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/PlaybackStallMonitor.ts';
const source = process.argv.includes('--compiled') ? compiled : 'entry/src/main/ets/utils/PlaybackStallMonitor.ets';
const context = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const Monitor = context.exports.PlaybackStallMonitor;
let m = new Monitor(); m.reset(10000, 10000, 0);
for (let now = 1000; now < 30000; now += 1000) {
  assert.equal(m.stalled(10000, 10000 + now / 2, true, now), false, 'refilling must survive the old 8s cutoff');
}
assert.equal(m.stalled(10000, 26000, true, 30000), true, 'refill still has a hard upper bound');
m = new Monitor(); m.reset(10000, 10000, 0);
assert.equal(m.stalled(10000, 10000, true, 7999), false);
assert.equal(m.stalled(10000, 10000, true, 8000), true, 'no supply still fails promptly');
m = new Monitor(); m.reset(10000, 10000, 0);
for (let now = 1000; now <= 7000; now += 1000) m.stalled(10000, 10000 + now, true, now);
assert.equal(m.stalled(10000, 17000, true, 14999), false);
assert.equal(m.stalled(10000, 17000, true, 15000), true, 'supply that stops cannot postpone recovery forever');
m = new Monitor(); m.reset(10000, 10000, 0);
assert.equal(m.stalled(10000, 30000, false, 8000), true, 'queued bytes cannot mask a decoder freeze');
m.reset(10000, 10000, 0);
assert.equal(m.stalled(10250, 14000, false, 8000), false, 'actual progress resets the deadline');
assert.equal(m.stalled(0, 4000, false, 9000), false, 'seek backwards resets the deadline');
console.log('PASS: actual refill, absent supply, bounded wait, decoder freeze and seeks (' + source + ')');
const playerSource = process.argv.includes('--compiled')
  ? compiled.replace('utils/PlaybackStallMonitor.ts', 'services/IjkPlaybackPlayer.ts')
  : 'entry/src/main/ets/services/IjkPlaybackPlayer.ets';
const playerContext = { exports: {}, require: () => ({}) };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(playerSource, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, playerContext);
const backup = playerContext.exports.IjkPlaybackPlayer.firstBackup;
assert.equal(backup(['https://base/file', 'https://base/file?other', 'https://other/file'], 'https://base/file'), 'https://other/file');
assert.equal(backup(['https://base/file', 'https://base/file?other'], 'https://base/file'), 'https://base/file?other');
assert.equal(backup(['https://base/file'], 'https://base/file'), '');
assert.equal(backup(undefined, 'https://base/file'), '');
console.log('PASS: alternate CDN is preferred over duplicate base URLs');
