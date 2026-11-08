const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
module.exports = function loadDeadline(timers = {}) {
  const context = { exports: {}, Error, setTimeout, clearTimeout, ...timers };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(
    'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/PlaybackDeadline.ts', 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports.PlaybackDeadline;
};
