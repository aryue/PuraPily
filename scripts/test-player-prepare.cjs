const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts', 'utf8');
const begin = source.indexOf('    private async bindS(');
const end = source.indexOf('    private referenceWarmSurfaceWidth(', begin);
const tick = () => new Promise(r => setImmediate(r));
function gate() { let resolve, reject; const promise = new Promise((r,j) => { resolve=r; reject=j; }); return {promise,resolve,reject}; }
const context = {exports:{}, deviceInfo:{sdkApiVersion:26}, media:{SeekMode:{SEEK_CLOSEST:1}}, errMsg:String,
  PlaybackDeadline: require('./playback-deadline-test-helper.cjs')(),
  logInfo(){},logWarn(){},logError(){}, PlaybackStartup:{trace(){}}};
vm.runInNewContext(ts.transpileModule('export class Page {'+source.slice(begin,end)+'}', {
  compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}
}).outputText,context);
(async()=>{
  const page = new context.exports.Page();
  const first=gate();let prepares=0,binds=0;
  const player={state:'initialized',set surfaceId(v){binds++;},prepare(){prepares++;return first.promise;}};
  Object.assign(page,{av:player,sId:'surface',vi:{duration:75},initialProgress_:0});
  const a=page.bindS(),b=page.bindS();
  assert.equal(prepares,1,'initialized and Surface callbacks must share one prepare');
  assert.equal(binds,1,'a second callback must not reassign the Surface during prepare');
  first.resolve(); await Promise.all([a,b]);
  const old=gate(); player.prepare=()=>old.promise;
  const pending=page.bindS();
  const replacement=gate();let newPrepares=0;
  page.av={state:'initialized',prepare(){newPrepares++;return replacement.promise;}};
  const current=page.bindS();
  old.reject(new Error('stale native failure')); await pending;await tick();
  assert.equal(page.err,undefined,'retired player cannot publish an error');
  const duplicate=page.bindS(); assert.equal(newPrepares,1,'retired cleanup cannot clear a newer prepare');
  replacement.resolve();await Promise.all([current,duplicate]);
  assert.equal(page.prepareTask_,null);
  const early=new context.exports.Page(), range=gate(), prepared=gate(); let rangeCalls=0, prepareCalls=0;
  const resumable={state:'initialized',async setPlaybackRange(start,end,mode){
    rangeCalls++;assert.equal(start,26043);assert.equal(end,-1);assert.equal(mode,1);await range.promise;
  },prepare(){prepareCalls++;return prepared.promise;}};
  Object.assign(early,{av:resumable,sId:'surface',vi:{duration:500},startupSourceDurationMs_:75007,initialProgress_:26.043,isDashStream_:true});
  const e1=early.bindS(),e2=early.bindS();assert.equal(rangeCalls,1);assert.equal(prepareCalls,0);
  range.resolve();await tick();assert.equal(prepareCalls,1);assert.equal(early.startupResumePlayer_,resumable);
  prepared.resolve();await Promise.all([e1,e2]);
  const fallback=new context.exports.Page();let fallbackPrepares=0;
  Object.assign(fallback,{av:{state:'initialized',async setPlaybackRange(){throw new Error('unsupported');},async prepare(){fallbackPrepares++;}},
    sId:'surface',vi:{duration:75},startupSourceDurationMs_:75007,initialProgress_:26.043,isDashStream_:true});
  await fallback.bindS();assert.equal(fallbackPrepares,1);assert.equal(fallback.startupResumePlayer_,undefined);
  for(const [sdk,position,dash,duration] of [[17,26,true,75007],[26,74,true,75007],[26,26,false,75007],[26,80,true,75007],[26,26,true,0]]){
    context.deviceInfo.sdkApiVersion=sdk;
    const p=new context.exports.Page();let calls=0, forbiddenRanges=0;
    Object.assign(p,{av:{state:'initialized',async setPlaybackRange(){forbiddenRanges++;throw new Error('must not set range');},async prepare(){calls++;}},
      sId:'surface',vi:{duration:500},initialProgress_:position,isDashStream_:dash,startupSourceDurationMs_:duration});
    await p.bindS();assert.equal(calls,1);assert.equal(forbiddenRanges,0);assert.equal(p.startupResumePlayer_,undefined);
  }
  context.deviceInfo.sdkApiVersion=26;
  const paused=new context.exports.Page();let pausedPrepares=0, pausedRanges=0;
  Object.assign(paused,{av:{state:'initialized',async setPlaybackRange(){pausedRanges++;throw new Error('paused continuation retains its render seek');},async prepare(){pausedPrepares++;}},
    sId:'surface',initialProgress_:26.043,isDashStream_:true,startupSourceDurationMs_:75007,continuationRestore_:true,continuationPaused_:true});
  await paused.bindS();assert.equal(pausedPrepares,1);assert.equal(pausedRanges,0);assert.equal(paused.startupResumePlayer_,undefined);
  console.log('PASS: compiled early exact resume before prepare, dedupe, CID duration/version/tail/paused gates, failure fallback, stable Surface and retired-player ownership');
})().catch(e=>{console.error(e);process.exitCode=1;});
