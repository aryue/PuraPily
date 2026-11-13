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
  Object.assign(page,{play:true,dur:75.007,sg_:false,cv:false,pendingSeekTarget_:-1,audioGain_:1,mute:true,
    cancelVideoSpeedSync(){},cancelDelayHide(){},saveWatchHistory(){saved.push(this.ct);},
    rampAudio_(){},markAutoPlay(){},delayMs_:()=>new Promise(()=>{})});
  page.avAudio={async pause(){},async play(){assert.equal(completes,false);},
    seek(position){page.audioSeekResolve_?.(position);}};
  page.av={state:'playing',currentTime:72043,async pause(){this.state='paused';},
    seek(){page.videoSeekPosition=72.043;page.videoSeekResolve_();},
    async play(){
      this.state=completes?'completed':'playing';
      if(completes){page.referencePlaybackCompleted=true;page.ct=page.dur;}
      page.startRenderFrameResolve_?.();
    }};
  await page.seek(72,false,!completes);
  assert.equal(page.referencePlaybackCompleted,completes,'seek cleanup must preserve native completion during frame wait');
  assert.equal(page.ct,completes?75.007:72.043);
  assert.equal(page.sg_,false);assert.equal(page.sk_,false);
  assert.equal(saved.at(-1),page.ct);
}
async function exerciseMerged() {
  const page = new context.exports.Page(), requests = [];
  Object.assign(page, {
    play: false, dur: 100, sg_: false, pendingSeekTarget_: -1, audioGain_: 1, avAudio: null,
    rampAudio_() {}, cancelDelayHide() {}, cancelVideoSpeedSync() {}, saveWatchHistory() {},
    delayMs_: () => new Promise(() => {})
  });
  page.av = { state: 'paused', seek(position, mode) { requests.push([position, mode]); } };
  const first = page.seek(10, false, false);
  await page.seek(20, false, true);
  await page.seek(35, false, true);
  assert.equal(page.ct, 35);
  assert.equal(page.seekExpectedPosition, 10, 'callback still belongs to the in-flight request');
  assert.deepEqual(requests, [[10000, 0]]);
  page.videoSeekResolve_();
  await new Promise(setImmediate);
  assert.deepEqual(requests, [[10000, 0], [35000, 1]]);
  page.videoSeekPosition = 35;
  page.videoSeekResolve_();
  await first;
  assert.equal(page.ct, 35);
}
(async()=>{
  await exercise(true);
  await exercise(false);
  await exerciseMerged();
  console.log('PASS: compiled seek preserves completion, skips the frame wait for aligned DASH tracks, and dispatches the latest queued target after the in-flight callback.');
})()
  .catch(error=>{console.error(error);process.exitCode=1;});
