const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const pageClass = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'VideoPlayerPage');
const methods = ['setupL', 'release'].map(name => pageClass.members.find(n =>
  ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast)).join('\n');
const context = { exports: {}, logWarn() {} };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
(async () => {
  const page = new context.exports.Subject();
  const events = new Map();
  let resolveRelease, releases = 0, metrics = 0, syncStops = 0;
  const released = new Promise(resolve => { resolveRelease = resolve; });
  const player = {
    on(name, callback) { events.set(name, callback); },
    off(name) {
      assert.notEqual(name, 'timeUpdate', 'retirement must avoid synchronous media progress IPC');
      events.delete(name);
    },
    release() { releases++; return released; }
  };
  Object.assign(page, { av: player, avAudio: null, referenceSwitchGeneration: 1,
    stopSyncTimer() { syncStops++; },
    playbackProfile: { seen() { metrics++; return true; }, once() { metrics++; } } });
  page.setupL();
  const lateTime = events.get('timeUpdate');
  const pending = page.release();
  assert.equal(page.av, null, 'ownership must detach without waiting for native release');
  assert.equal(releases, 1);
  lateTime(5000);
  assert.equal(metrics, 0, 'retired callbacks cannot update page state or playback metrics');
  await page.release();
  assert.equal(releases, 1, 'repeated retirement cannot release the same native player twice');
  assert.equal(syncStops, 2);
  resolveRelease(); await pending;
  console.log('PASS: compiled release avoids progress IPC, invalidates late callbacks and releases each player once.');
})().catch(error => { console.error(error); process.exitCode = 1; });
