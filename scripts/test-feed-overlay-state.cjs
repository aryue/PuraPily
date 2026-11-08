const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const s=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts','utf8');
function section(start,end){const a=s.indexOf(start),b=s.indexOf(end,a);assert.ok(a>=0&&b>a);return s.slice(a,b)}
const ctx={exports:{},ContinuousRecommendationState:{markVisited(){}},logInfo(){},logWarn(){},logError(...args){throw Error(args.join(' '))}};
const methods=section('    private async referenceNextVideo(', '    private async referencePrepareFeedMain(')+section('    private referencePreviewDetailFor(', '    ReferencePreviewChrome(');
vm.runInNewContext(ts.transpileModule(`export class Page { ${methods} }`,{}).outputText,ctx);
(async()=>{
 const p=new ctx.exports.Page(), detail={bvid:'BVtarget',aid:123,cid:456,title:'target',pic:'target.jpg',duration:140,owner:{name:'target author',face:'target-face.jpg'},stat:{view:1,like:2,coin:3,favorite:4}};
 p.referencePreviewDetail=detail;
 assert.equal(p.referencePreviewDetailFor({id:'BVold'}),null,'old preview metadata cannot leak into a different neighbour');
 assert.equal(p.referencePreviewDetailFor({id:'123'}),detail,'numeric AV ids keep their own matching metadata');
 const next={id:'BVtarget',cid:456,duration:140,ownerName:'target author',coverUrl:'target.jpg'};
 const noop=()=>{};
 Object.assign(p,{referenceAlive:true,referenceQueuedFeedStep:0,referenceSwitchGeneration:0,referencePreviewGeneration:0,referencePortraitFeedActive:()=>true,vi:{bvid:'BVold'},play:false,
  ensureReferenceRecommendQueue:async()=>[{id:'BVold'},next],referencePreviewRequestedId:'BVtarget',referenceStillFrames:new Map(),referenceStillRatios:new Map(),referenceFeedAspect:()=>1,referencePreviewAspectRatio:1,referenceAnimateFeedTo:async()=>{},saveWatchHistory:noop,reportWatchBehavior:noop,clearGestureHint_:noop,resetFullscreenVideo:noop,updateIsLandscapeVertical:noop,updateLSVSize:noop,updateVideoSize:noop,commentDataSource:{clear:noop},referenceFeedNeighbor:()=>null,loadD:noop,loadC:noop,referenceFeedMainJob:Promise.resolve(),referencePrepareFeedMain:async()=>{}});
 await p.referenceNextVideo(1);
 assert.equal(p.vi.bvid,'BVtarget');assert.equal(p.vd.owner.name,'target author');assert.equal(p.play,true,'autoplay intent must survive the decoder handoff');assert.equal(p.dur,140);assert.equal(p.referenceFeedLoading,false);
 console.log('PASS: compiled feed preview BV/AV identity guard and atomic autoplay/author/duration commit.');
})().catch(e=>{console.error(e);process.exitCode=1});
