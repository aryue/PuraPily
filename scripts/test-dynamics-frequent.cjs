const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicsPage.ts','utf8');
const a = source.indexOf('    private async loadUpList('), b = source.indexOf('    private switchFilter(', a);
assert.ok(a >= 0 && b > a);
let calls = [], repeat = false;
const ups = start => Array.from({length:5}, (_,i)=>({mid:start+i,uname:`up-${start+i}`,face:'',hasUpdate:true}));
const ctx = {exports:{},logInfo(){},logWarn(){},logError(){},getDynUpList: async offset => {
 calls.push(offset);
 return !offset ? {items:ups(1),offset:'next',hasMore:true} : {items:ups(repeat?1:6),offset:repeat?'next':'last',hasMore:repeat};
}};
vm.runInNewContext(ts.transpileModule(`export class Page { ${source.slice(a,b)} }`,{}).outputText,ctx);
const page = () => Object.assign(new ctx.exports.Page(),{upLoading:false,readUpMids:[7],upList:[],playUpRailEntrance(){}});
(async()=>{
 let p=page();await p.loadUpList('');assert.equal(p.upList.length,10);assert.deepEqual(calls,['','next']);assert.equal(p.upList[6].hasUpdate,false);assert.equal(p.upLoading,false);
 calls=[];repeat=true;p=page();await p.loadUpList('');assert.equal(p.upList.length,5);assert.deepEqual(calls,['','next'],'repeated cursor cannot loop or duplicate authors');
 console.log('PASS: compiled frequent UP initial ten, read markers, cursor termination and duplicate-page guard.');
})().catch(e=>{console.error(e);process.exitCode=1});
