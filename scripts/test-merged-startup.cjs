const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function load(file,deps={},globals={}){
  const c={exports:{},console,setTimeout,clearTimeout,AppStorage:{get:()=>''},...globals,require:id=>
    Object.entries(deps).find(([key])=>id.includes(key))?.[1]||{}};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+file+'.ts','utf8'),{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);return c;
}
const tick=()=>new Promise(r=>setImmediate(r));
const full={url:'video',audioUrl:'audio',dash:{},actualQn:80,acceptQuality:[80,116,120,125],acceptDescription:['1080P','60fps','4K','HDR'],lastPlayTimeMs:42000};
(async()=>{
  let fire;const policy=load('utils/MergedPlaybackPolicy',{}, {setTimeout(fn){fire=fn;return 1;},clearTimeout(){}}).exports;
  const direct=await policy.preferSameQualityMerged(full,Promise.resolve({url:'merged',actualQn:80}));
  assert.equal(direct.url,'merged');assert.equal(direct.audioUrl,undefined);assert.equal(direct.dash,undefined);
  assert.deepEqual(Array.from(direct.acceptQuality),full.acceptQuality);assert.equal(direct.lastPlayTimeMs,42000);
  for(const candidate of [{url:'low',actualQn:64},{url:'wrong',audioUrl:'audio',actualQn:80},null]){
    assert.equal(await policy.preferSameQualityMerged(full,Promise.resolve(candidate)),full,'do not lower quality or accept separated sources');
  }
  let late;const pending=new Promise(r=>{late=r;});const waiting=policy.preferSameQualityMerged(full,pending);
  fire();assert.equal(await waiting,full,'merged preference adds at most 250ms');late({url:'late',actualQn:80});await tick();
  assert.equal(full.url,'video','late merged replies cannot replace current media');
  const realPolicy=load('utils/MergedPlaybackPolicy').exports;
  const requests=load('utils/PlaybackRequests').exports,quality=load('utils/DashQuality').exports;
  let responseBody;
  const http={RequestMethod:{GET:1},HttpDataType:{STRING:1},createHttp(){return{async request(){return{responseCode:200,result:JSON.stringify(responseBody)};},destroy(){}};}};
  const api=load('api/BilibiliApi',{
    'net.http':{default:http},'hilog':{default:{debug(){}}},MergedPlaybackPolicy:realPolicy,PlaybackRequests:requests,DashQuality:quality,
    PlaybackStartup:{PlaybackStartup:{span:()=>null}},Logger:{logInfo(){},logWarn(){},logError(){}}
  });
  const calls=[],empty={durlUrl:'',dashVideoUrl:'',dashAudioUrl:'',actualQn:0,acceptQuality:[],acceptDescription:[],dashInfo:null};
  api.tryFetchPlayUrlMobile=async(_b,_c,qn)=>({...empty,dashVideoUrl:'video',dashAudioUrl:'audio',actualQn:qn,acceptQuality:[80,116,120,125]});
  api.tryFetchPlayUrlWebRoute=async(_b,_c,qn,fnval)=>{calls.push(fnval);return fnval===1?{...empty,durlUrl:'merged',actualQn:qn}:empty;};
  const result=await api.getVideoPlayUrlRaw('BVfixture',1,80,{ms:0});
  assert.equal(result.url,'merged');assert.deepEqual(Array.from(result.acceptQuality),[80,116,120,125]);
  calls.length=0;const hdr=await api.getVideoPlayUrlRaw('BVfixture',1,125,{ms:0});
  assert.equal(hdr.url,'video');assert.ok(!calls.includes(1),'HDR/high-frame-rate requests do not probe an incompatible merged format');
  responseBody={code:0,data:{quality:80,durl:[{url:'part-1'},{url:'part-2'}]}};
  const parsed=await api.fetchPlayUrlEndpoint('https://api.bilibili.com/fixture',{},null);
  assert.equal(parsed.durlUrl,'','a multi-file response cannot be mistaken for a complete single-file source');
  console.log('PASS: compiled same-quality merged preference, complete catalogue/resume preservation, bounded wait, late replies, HDR exclusion and multi-part rejection');
})().catch(e=>{console.error(e);process.exitCode=1;});
