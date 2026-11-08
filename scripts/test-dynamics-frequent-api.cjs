const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const s=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/api/BilibiliApi.ts','utf8');
const a=s.indexOf('export async function getDynUpList('),b=s.indexOf('// ==================== 动态转发',a);assert.ok(a>=0&&b>a);
let calls=[],legacy=false,failSign=false,destroyed=0;
const up=i=>({mid:i,uname:`up-${i}`,face:`${i}.jpg`,has_update:true});
const ctx={exports:{},URLSearchParams,logInfo(){},logWarn(){},logError(){},dynamicThrottleRequest:async()=>{},getBiliRequestHeaders:()=>({}),AppSign:{generateWebParams:async params=>{if(failSign)throw Error('sign unavailable');return new URLSearchParams(params).toString()}},http:{RequestMethod:{GET:'GET'},createHttp:()=>({destroy(){destroyed++},request:async url=>{
 calls.push(url);const first=url.includes('/portal?');const items=[up(first?1:2)];
 return {responseCode:200,result:JSON.stringify({code:0,data:first?{up_list:legacy?items:{items,has_more:true,offset:'cursor'}}:{items,has_more:false,offset:''}})};
}})}};
vm.runInNewContext(ts.transpileModule(s.slice(a,b),{}).outputText,ctx);
(async()=>{
 const f=ctx.exports.getDynUpList;let r=await f();assert.equal(r.items[0].mid,1);assert.equal(r.hasMore,true);assert.equal(r.offset,'cursor');assert.ok(calls[0].includes('/portal?'));assert.equal(new URL(calls[0]).searchParams.get('up_list_more'),'1');
 r=await f(r.offset);assert.equal(r.items[0].mid,2);assert.ok(calls[1].includes('/uplist?'));assert.equal(new URL(calls[1]).searchParams.get('offset'),'cursor');
 legacy=true;failSign=true;r=await f();assert.equal(r.items.length,1);assert.equal(r.hasMore,false);assert.equal(new URL(calls[2]).searchParams.get('up_list_more'),'1');assert.equal(destroyed,3);
 console.log('PASS: compiled portal expanded first page, cursor continuation, legacy array, signing fallback and HTTP cleanup.');
})().catch(e=>{console.error(e);process.exitCode=1});
