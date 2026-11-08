const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/';
const tick=()=>new Promise(r=>setImmediate(r));
const gate=()=>{let resolve;const promise=new Promise(r=>{resolve=r;});return{resolve,promise};};
const bytes=(n,v=11)=>new Uint8Array(n).fill(v).buffer;
function fixture() {
  const calls=[],events=[],timers=new Map();let next=0;
  const http={RequestMethod:{GET:1},HttpDataType:{ARRAY_BUFFER:1},createHttp(){
    const done=gate();const r={destroyed:0,request(url,options){r.url=url;r.options=options;return done.promise;},
      reply(body=bytes(64),total=1000,range='bytes 0-63/'+total){done.resolve({responseCode:206,result:body,header:{'Content-Range':range}});},destroy(){r.destroyed++;}};
    calls.push(r);return r;
  }};
  const c={exports:{},ArrayBuffer,Uint8Array,console,
    setTimeout(fn){timers.set(++next,fn);return next;},clearTimeout(id){timers.delete(id);},require:id=>
    id.includes('net.http')?{default:http}:id.includes('PlaybackStartup')?{PlaybackStartup:{span:()=>({mark:(...x)=>events.push(x),end(){}})}}:{}};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'DashCdnRoute.ts','utf8'),{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
  const route=new c.exports.DashCdnRoute('primary',['primary','alternate'],bytes(64),1000,'','App-UA',null);
  return{route,calls,events,timers};
}
(async()=>{
  {
    const f=fixture();assert.equal(f.calls.length,0,'no validation traffic during healthy playback');
    const a=f.route.fallback('primary'),b=f.route.fallback('primary');assert.equal(f.calls.length,1,'failed workers share validation');
    assert.equal(f.calls[0].options.header.Range,'bytes=0-63');
    assert.equal(f.calls[0].options.header.Cookie,undefined);assert.equal(f.calls[0].options.header.Referer,undefined);
    f.calls[0].reply();assert.equal(await a,'alternate');assert.equal(await b,'alternate');
    assert.equal(f.route.currentUrl,'alternate');assert.equal(f.calls[0].destroyed,1);assert.equal(f.timers.size,0);
    assert.equal(await f.route.fallback('primary'),'alternate');assert.equal(await f.route.fallback('alternate'),null);
    assert.equal(f.calls.length,1,'one candidate validation per track session');
    assert.ok(!JSON.stringify(f.events).includes('primary')&&!JSON.stringify(f.events).includes('alternate/'));
  }
  for(const mismatch of ['head','size','range','length']){
    const f=fixture(),job=f.route.fallback('primary');
    if(mismatch==='head')f.calls[0].reply(bytes(64,99));
    if(mismatch==='size')f.calls[0].reply(bytes(64),1001);
    if(mismatch==='range')f.calls[0].reply(bytes(64),1000,'bytes 1-64/1000');
    if(mismatch==='length')f.calls[0].reply(bytes(63));
    assert.equal(await job,null,mismatch);assert.equal(f.route.currentUrl,'primary');
    assert.equal(await f.route.fallback('primary'),null);assert.equal(f.calls.length,1,'rejected node is not retried repeatedly');
  }
  {
    const f=fixture(),job=f.route.fallback('primary');f.route.cancel();
    assert.equal(await job,null);assert.equal(f.calls[0].destroyed,1);assert.equal(f.timers.size,0);
    f.calls[0].reply();await tick();assert.equal(f.route.currentUrl,'primary','late validation cannot resurrect a cancelled route');
  }
  {
    const f=fixture(),job=f.route.fallback('primary');[...f.timers.values()][0]();
    assert.equal(await job,null);assert.equal(f.calls[0].destroyed,1,'validation has a two-second wall-clock bound');
  }
  console.log('PASS: compiled lazy/shared CDN validation, byte prefix/layout/size checks, privacy, bounded fallback and cancellation');
})().catch(e=>{console.error(e);process.exitCode=1;});
