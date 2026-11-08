const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts','utf8');
const begin=source.indexOf('    async seek('),end=source.indexOf('    applyFSResistance(',begin);
assert.ok(begin>=0&&end>begin);
const context={exports:{},media:{SeekMode:{SEEK_CLOSEST:1,SEEK_PREV_SYNC:0}},logInfo(){},setTimeout,clearTimeout};
vm.runInNewContext(ts.transpileModule('export class Page {'+source.slice(begin,end)+'}',{
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
}).outputText,context);
async function exercise(completes){
  const page=new context.exports.Page(),saved=[];
  Object.assign(page,{play:true,dur:75.007,sg_:false,cv:false,pendingSeekTarget_:-1,
    cancelVideoSpeedSync(){},cancelDelayHide(){},saveWatchHistory(){saved.push(this.ct);},
    delayMs_:()=>new Promise(()=>{}),avAudio:null});
  page.av={state:'playing',currentTime:74043,async pause(){this.state='paused';},
    seek(){page.videoSeekPosition=74.043;page.videoSeekResolve_();},
    async play(){
      this.state=completes?'completed':'playing';
      if(completes){page.referencePlaybackCompleted=true;page.ct=page.dur;}
      setImmediate(()=>page.startRenderFrameResolve_?.());
    }};
  await page.seek(74,false,true);
  assert.equal(page.referencePlaybackCompleted,completes,'seek cleanup must preserve native completion during frame wait');
  assert.equal(page.ct,completes?75.007:74.043);
  assert.equal(page.sg_,false);assert.equal(page.sk_,false);
  assert.equal(saved.at(-1),page.ct);
}
(async()=>{await exercise(true);await exercise(false);console.log('PASS: compiled seek completion/frame-wait race retains replay and final position; normal seek still clears completion');})()
  .catch(error=>{console.error(error);process.exitCode=1;});
