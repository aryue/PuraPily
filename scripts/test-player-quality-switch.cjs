const fs=require('node:fs'), vm=require('node:vm'), assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const transpile=s=>ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
function extract(file,signature){
 const source=fs.readFileSync(root+file,'utf8'),start=source.indexOf(signature); assert.ok(start>=0,signature);
 let pos=source.indexOf('{',start),depth=1,end=pos+1;
 for(;depth;end++){if(source[end]==='{')depth++; if(source[end]==='}')depth--;}
 return source.slice(start,end);
}
const selector={exports:{}};
vm.runInNewContext(transpile(fs.readFileSync(root+'utils/DashQuality.ts','utf8')),selector);
const select=selector.exports.selectDashVideo;
const streams=[{id:120,codecid:7,baseUrl:'4k',frameRate:'30'},{id:80,codecid:7,baseUrl:'1080p30',frameRate:'30'},
 {id:116,codecid:13,baseUrl:'av1-60',frameRate:'60'}, {id:116,codecid:12,baseUrl:'1080p60',frameRate:'60000/1001'},
 {id:64,codecid:7,baseUrl:'720p',frameRate:'30'}];
assert.equal(select(streams,116).baseUrl,'1080p60');
assert.equal(select(streams,80).baseUrl,'1080p30');
assert.equal(select(streams,64).id,64);
assert.equal(select(streams,112).id,80);
assert.equal(select([],116),null);
assert.equal(streams[0].id,120,'selection does not reorder source');
const normalization={selectDashVideo:select,exports:{}};
vm.runInNewContext(transpile(extract('api/BilibiliApi.ts','function normalizeDashQuality(')+'\nexports.normalize=normalizeDashQuality;'),normalization);
const normalize=normalization.exports.normalize;
function source(quality,videoStreams=streams){return {url:'incorrect-highest',audioUrl:'audio',actualQn:quality,dash:{quality,videoStreams,timelength:10000}};}
let selected=normalize(source(116),116);
assert.equal(selected.actualQn,116);assert.equal(selected.url,'1080p60');assert.equal(selected.dash.quality,116);
selected=normalize(source(120),80);assert.equal(selected.actualQn,80);assert.equal(selected.url,'1080p30');
selected=normalize(source(80),116);assert.equal(selected.actualQn,80,'server downgrade must not masquerade as 60fps');
selected=normalize(source(116,streams.filter(x=>x.id!==116)),116);assert.equal(selected.actualQn,80);
const traceContext={exports:{},hilog:{debug(_domain,_tag,_format,json){traceContext.last=JSON.parse(json);}}};
vm.runInNewContext(transpile('export class Trace {'+extract('pages/VideoPlayerPage.ts','    private async traceQualityTrack(')+'}'),traceContext);
async function verifyTrackUnits(){
 const trace=new traceContext.exports.Trace();trace.av={getTrackDescription:async()=>[{width:1440,height:1080,frame_rate:6000}]};
 await trace.traceQualityTrack(trace.av,116,116);assert.equal(traceContext.last.fps,60,'native frame rate units are frames per 100 seconds');
 assert.deepEqual(Object.keys(traceContext.last).sort(),['actual','fps','height','requested','width'],'track trace contains no URLs or identifiers');
}
const switchCode=extract('pages/VideoPlayerPage.ts','    async switchQ(');
let response, saved=0, toast=[], requestArgs=[], decoderSupported=true, owner;
let preparation=null, ready=true, aligned=true, candidates=[], retiring=[];
const tick=()=>new Promise(r=>setImmediate(r));
function player(state='playing') { return {state,currentTime:20000,duration:100000,volume:1,releases:0,
 setVolume(v){this.volume=v;},async release(){this.releases++;}}; }
const ctx={exports:{},canDecodePlayUrl:()=>decoderSupported,getVideoPlayUrl:async(...args)=>{requestArgs=args;return await response;},
 getPgcPlayUrl:async()=>response, AppStorage:{get:()=>'',set(){saved++;}},
 PlaybackStartup:{begin:()=>({mark(){},end(){}}),deactivate(){}},
 PlaybackDeadline:require('./playback-deadline-test-helper.cjs')(),
 QualityPlaybackSession:class {
  constructor(){this.releases=0;this.taken=false;candidates.push(this);}
  async prepare(){if(preparation)await preparation;return ready;}
  async align(reference){this.reference=reference;this.driftMs=0;return aligned;}
  take(){this.taken=true;this.target=player(this.reference.state);return {video:this.target,audioPlayer:null,bridge:null};}
  async release(){if(!this.taken)this.releases++;}
 },
 retirePlayback:async handles=>handles.video.release(),
 setTimeout:fn=>{retiring.push(fn);return 1;},clearTimeout(){},setInterval:()=>1,clearInterval(){},console,logInfo(){},logWarn(){},logError(){},errMsg:String};
vm.runInNewContext(transpile('export class Subject {'+switchCode+'}'),ctx);
function page(state='playing'){
 const p=new ctx.exports.Subject();Object.assign(p,{qn:80,qs:false,ct:20,play:state==='playing',referenceAlive:true,
 referenceSwitchGeneration:1,vi:{bvid:'BVtest',cid:1},av:player(state),sId:'surface-a',referencePreviewSurfaceId:'surface-b',
 waitingForFirstFrame:false,ld:false,ar:16/9,rt:1,referenceSecondSurfaceActive:false,referencePreviewReleaseJob:Promise.resolve(),
 playbackListPrefetch:{pause(){}},stopSyncTimer(){},getVideoScaleType:()=>0,rateToSpeedIdx:()=>1,
 referenceWarmUpcomingFrames(){},startVideoSpeedSync(){},
 getQlList:()=>[{qn:80},{qn:116}],getQlLabel:n=>n===116?'1080P60':'1080P',getUIContext:()=>({getPromptAction:()=>({showToast:o=>toast.push(o.message)})}),
 applyAcceptQuality(){},async releaseReferenceFeedPreview(){},release(){throw Error('must keep current owner until candidate is ready');},
 setupL(){},setupAudioL(){},traceQualityTrack(){},sBH(){}});owner=p;return p;
}
async function verifyBridge() {
 const mpd={exports:{}};vm.runInNewContext(transpile(fs.readFileSync(root+'services/DashMpdBuilder.ts','utf8')),mpd);
 let config;
 const probe={timescale:1000,segments:[{fileOffset:200,size:100,duration:5000},{fileOffset:300,size:100,duration:5000}],initRange:'0-99',indexRange:'100-199',contentLength:400,headBuffer:new ArrayBuffer(200)};
 const imports={
  '../utils/PlaybackStartup':{PlaybackStartup:{span:()=>null}},'../utils/DashQuality':{selectDashVideo:select},
  './DashProbe':{probeM4sInitSegment:async()=>probe},'./DashMpdBuilder':mpd.exports,
  './DashCdnRoute':{DashCdnRoute:class{}},
  './DashMediaServer':{DashMediaServer:class {setConfig(value){config=value;}canRetainStartupSegments(){return true;}prefetchSegment(){return Promise.resolve(true);}prefetchSegmentAtTime(){return Promise.resolve(true);}async start(){}getPort(){return 1234;}async stop(){}}}
 };
 const context={exports:{},console:{info(){},warn(){},error(){}},require:name=>imports[name]||Object.entries(imports).find(([key])=>name.endsWith("/"+key.split("/").pop()+"&"))?.[1]||{}};
 vm.runInNewContext(transpile(fs.readFileSync(root+'services/DashPlayerBridge.ts','utf8')),context);
 for (const qn of [116,80]) {
  const bridge=new context.exports.DashPlayerBridge(null);
  const videoStreams=streams.map(s=>({...s,width:s.id===120?3840:1920,height:s.id===120?2160:1080,bandwidth:4000000}));
  assert.ok(await bridge.buildAndStart({quality:qn,timelength:10000,videoStreams,audioStreams:[{id:1,baseUrl:'audio'}]},'','',''));
  assert.equal(config.videoUrl,qn===116?'1080p60':'1080p30');
  assert.match(config.mpdXml,new RegExp('frameRate="'+(qn===116?'60000/1001':'30')+'"'));
  assert.equal((config.mpdXml.match(/<Representation /g)||[]).length,2,'manifest contains only one video and one audio rendition');
  await bridge.stopIfRunning();
 }
}
(async()=>{
 await verifyBridge(); await verifyTrackUnits();
 let p=page(),resolve;const original=p.av;response=new Promise(r=>resolve=r);const task=p.switchQ(116);
 await tick();assert.equal(p.qs,true);assert.equal(p.av,original);assert.equal(original.volume,1);
 resolve({url:'fallback',actualQn:80});await task;assert.equal(p.av,original);assert.equal(p.qn,80);assert.equal(p.qs,false);
 assert.match(toast.at(-1),/1080P60.*保留1080P/);assert.equal(saved,0);assert.equal(requestArgs[3],0);
 decoderSupported=false;response={url:'unsupported-hevc',actualQn:116};p=page();const unsupported=p.av;await p.switchQ(116);
 assert.equal(p.av,unsupported);assert.equal(saved,0);assert.equal(p.qn,80);decoderSupported=true;
 let prepared;preparation=new Promise(r=>prepared=r);response={url:'1080p60',actualQn:116};p=page();const outgoing=p.av;
 const warming=p.switchQ(116);await tick();assert.equal(p.av,outgoing);assert.equal(outgoing.volume,1);
 assert.equal(p.waitingForFirstFrame,false,'preparation never covers the playing source with a spinner');
 assert.equal(p.referenceSecondSurfaceActive,false);assert.equal(saved,0);
 prepared();await warming;preparation=null;
 assert.notEqual(p.av,outgoing);assert.equal(p.referenceSecondSurfaceActive,true);assert.equal(p.sId,'surface-b');
 assert.equal(p.referencePreviewSurfaceId,'surface-a');assert.equal(p.qn,116);assert.equal(saved,1);assert.equal(p.qs,false);
 assert.equal(outgoing.releases,0,'retain old native buffer through the Surface role update');
 const current=p.av;for(const fn of retiring.splice(0))fn();await p.referencePreviewReleaseJob;
 assert.equal(outgoing.releases,1);assert.equal(current.releases,0);
 response=Promise.reject(Error('network'));p=page();const networkOwner=p.av;await p.switchQ(116);assert.equal(p.av,networkOwner);
 response={url:'1080p60',actualQn:116};aligned=false;p=page();const failedOwner=p.av;await p.switchQ(116);
 assert.equal(p.av,failedOwner);assert.equal(p.qn,80);assert.equal(failedOwner.volume,1);assert.equal(p.waitingForFirstFrame,false);aligned=true;
 p=page('paused');await p.switchQ(116);assert.equal(p.play,false);assert.equal(p.av.state,'paused');assert.equal(p.waitingForFirstFrame,false);
 preparation=new Promise(r=>prepared=r);p=page();const staleOwner=p.av;const stale=p.switchQ(116);await tick();
 p.referenceSwitchGeneration++;prepared();await stale;preparation=null;assert.equal(p.av,staleOwner);assert.equal(staleOwner.volume,1);
 preparation=new Promise(r=>prepared=r);p=page();const cancelledOwner=p.av;const cancelled=p.switchQ(116);await tick();
 p.qualityDeadline_.cancel();await cancelled;assert.equal(p.av,cancelledOwner);assert.equal(p.qs,false);prepared();preparation=null;
 console.log('PASS: compiled rendition/catalogue correctness, background preparation, aligned Surface swap, retained old playback on failure/cancel, paused handoff and captured-resource retirement');
})().catch(e=>{console.error(e);process.exitCode=1;});
