const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/PlayerStartupPolicy.ts', 'utf8');
const code = ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
function policy(api) {
  const context = {exports:{},require:()=>({default:{sdkApiVersion:api}})};
  vm.runInNewContext(code,context);
  return context.exports.startupPlaybackStrategy();
}
module.exports = policy;
if (require.main === module) {
  for (const api of [17,18,26]) {
    const strategy = policy(api);
    assert.deepEqual(Object.keys(strategy), [],
      'DASH must retain native startup/rebuffering: forcing 0.5s stalled both tracks in the 4K60 device regression');
  }
  console.log('PASS: compiled DASH policy preserves native buffering across supported SDKs');
}
