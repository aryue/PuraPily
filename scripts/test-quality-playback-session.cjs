const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const tick=()=>new Promise(r=>setImmediate(r));
let now=0;const clock={now:()=>now};
function advancing(reference){return setInterval(()=>{reference.currentTime+=100;now+=100;},1);}
const Deadline=require('./playback-deadline-test-helper.cjs')({Date:clock});
function player(state='paused'){
 return {state,currentTime:10000,duration:100000,releases:0,plays:0,seeks:0,events:{},
  on(name,fn){this.events[name]=fn;},off(name){delete this.events[name];},setSpeed(){},
  seek(time){this.seeks++;this.currentTime=time;this.onSeek?.();if(!this.holdSeek)this.events.seekDone?.(time);},
  async play(){this.plays++;this.state='playing';this.currentTime+=40;this.events.timeUpdate?.(this.currentTime);},
  async pause(){this.state='paused';},async release(){this.releases++;this.state='released';}};
}
function fixture(){
 const video=player(),audio=player(),bridge={stops:0,async stop(){this.stops++;}};
 const handles={video,audioPlayer:audio,bridge};
 class Warm {async prepare(){return true;}take(){this.taken=true;return handles;}async release(){if(!this.taken)video.release();}}
 const context={exports:{},setTimeout,clearTimeout,Date:clock,require:id=>{
  if(id==='@ohos:multimedia.media')return {default:{SeekMode:{SEEK_CLOSEST:1}}};
  if(id.includes('FeedPlaybackSession'))return {FeedPlaybackSession:Warm};
  if(id.includes('PlaybackStartup'))return {PlaybackStartup:{span:()=>null}};
  if(id.includes('PlaybackDeadline'))return {PlaybackDeadline:Deadline};return {};
 }};
 vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'services/QualityPlaybackSession.ts','utf8'),{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
 return {session:new context.exports.QualityPlaybackSession('BVfixture','spare',{},10000),video,audio,bridge,retire:context.exports.retirePlayback};
}
(async()=>{
 let f=fixture(),reference=player('playing');reference.currentTime=20000;
 assert.equal(await f.session.prepare(0,''),true);let timer=advancing(reference);
 try{assert.equal(await f.session.align(reference,1,1),true);}finally{clearInterval(timer);}
 assert.ok(Math.abs(f.video.currentTime-reference.currentTime)<=350);assert.equal(reference.plays,0);assert.equal(reference.releases,0);
 const handles=f.session.take();assert.equal(handles.video,f.video);await f.session.release();assert.equal(f.video.releases,0);
 await f.retire({video:f.video,audioPlayer:f.audio,bridge:f.bridge});assert.equal(f.video.releases,1);assert.equal(f.bridge.stops,1);
 f=fixture();reference=player('paused');reference.currentTime=35000;await f.session.prepare(0,'');
 assert.equal(await f.session.align(reference,1,1),true);assert.equal(f.video.plays,0);assert.equal(f.video.currentTime,35000);
 await f.session.release();assert.equal(f.video.releases,1);
 f=fixture();reference=player('playing');reference.currentTime=20000;await f.session.prepare(0,'');
 f.video.onSeek=()=>{now+=6000;reference.currentTime+=6000;};timer=advancing(reference);
 try{assert.equal(await f.session.align(reference,1,1),true);}finally{clearInterval(timer);}
 assert.ok(f.video.seeks>=2,'choose a later future frame when precise seek exceeded the initial lead');
 assert.ok(Math.abs(f.session.driftMs)<=350);await f.session.release();
 f=fixture();reference=player('playing');reference.currentTime=20000;f.video.currentTime=21000;await f.session.prepare(0,'');
 timer=advancing(reference);try{assert.equal(await f.session.align(reference,1,1),true);}finally{clearInterval(timer);}
 assert.equal(f.video.seeks,0,'a decoded future frame waits for the original instead of repeating precise seek');await f.session.release();
 f=fixture();reference=player('playing');reference.currentTime=20000;f.video.holdSeek=true;await f.session.prepare(0,'');
 const alignment=f.session.align(reference,1,1),rejected=assert.rejects(alignment,/已取消/);await tick();
 await f.session.release();await rejected;assert.equal(f.video.releases,1);assert.equal(reference.releases,0);
 console.log('PASS: compiled muted candidate ownership, live-timeline alignment/re-alignment, paused alignment, cancellation and captured-resource retirement');
})().catch(e=>{console.error(e);process.exitCode=1;});
