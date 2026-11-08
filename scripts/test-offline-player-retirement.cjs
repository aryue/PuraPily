const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/OfflineInlinePlayer.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const subject = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'OfflineInlinePlayer');
const methods = ['setupL', 'releaseAll'].map(name => subject.members.find(n =>
  ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
const context = { exports: {}, logWarn() {} };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const events = new Map();
let videosReleased = 0, audioReleased = 0;
const video = {
  on(name, callback) { events.set(name, callback); },
  off(name) {
    assert.notEqual(name, 'timeUpdate', 'retirement must avoid synchronous progress-report IPC');
    events.delete(name);
  },
  release() { videosReleased++; return Promise.resolve(); }
};
const page = new context.exports.Subject();
Object.assign(page, { av: video, avAudio: { off() {}, release() { audioReleased++; return Promise.resolve(); } },
  currentTime: 0, cancelSpeedSync() {}, vFd: null, aFd: null });
page.setupL();
const oldTime = events.get('timeUpdate');
oldTime(7100);
assert.equal(page.currentTime, 7.1, 'live progress still updates normally');
page.releaseAll();
assert.equal(page.av, null);
assert.equal(page.avAudio, null);
oldTime(8100);
assert.equal(page.currentTime, 7.1, 'queued progress from a retired player cannot update the component');
page.av = {};
oldTime(9100);
assert.equal(page.currentTime, 7.1, 'retired callbacks cannot write into a replacement session');
page.av = null;
page.releaseAll();
assert.equal(videosReleased, 1);
assert.equal(audioReleased, 1);
console.log('PASS: compiled offline progress, stale-session protection, asynchronous release and no progress IPC.');
