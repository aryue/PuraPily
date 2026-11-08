const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/FloatingVideoSurface.ts','utf8');
function block(marker){const a=source.indexOf(marker);assert(a>=0,marker);let o=source.indexOf('{',a),depth=1,e=o+1;while(depth){const c=source[e++];if(c==='{')depth++;if(c==='}')depth--}return source.slice(a,e)}
let created=0,last,added=0,hidden=false;const seeks=[],video={surfaceId:'main',currentTime:12345,state:'paused',seek:(t,m)=>seeks.push([t,m])};
const ctx={exports:{},logInfo(){},logWarn(){},setTimeout:cb=>{cb();return 1},
 XComponentController:class{getXComponentSurfaceId(){return 'retained'}},wrapBuilder:x=>x,buildSource(){},
 media:{SeekMode:{SEEK_CLOSEST:2}},PlayerService:{getInstance:()=>({videoPlayer:video})},
 ComponentContent:class{constructor(ui,builder,params){created++;last=params}update(params){last=params}}};
vm.runInNewContext(ts.transpileModule(block('class SurfaceParams')+'\n'+block('export class FloatingVideoSurface'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const S=ctx.exports.FloatingVideoSurface;
const ui={px2vp:p=>p/3,getOverlayManager:()=>({addComponentContent(){added++},showComponentContent(){hidden=false},hideComponentContent(){hidden=true}}),getFrameNodeById:()=>({
 getMeasuredSize:()=>({width:last.rect.width*3,height:last.rect.height*3}),
 getPositionToWindow:()=>({x:last.visible?last.rect.x:-10000,y:last.rect.y+39})})};
async function main(){
 S.prepare(ui,{x:0,y:39,width:440,height:247.5});assert.equal(await S.waitForLayout(),false,'cannot launch before source Surface load');
 S.loaded();assert.equal(video.surfaceId,'retained');assert.equal(seeks.length,1);assert.equal(seeks[0][0],12345);assert.equal(video.state,'paused');
 assert.equal(await S.waitForLayout(),true);assert.equal(last.rect.y,0,'compensate actual safe-area origin');
 assert.equal(await S.waitForLayout(),true);assert.equal(last.rect.y,0,'repeated layout checks must not drift');
 S.park();assert.equal(last.visible,false);assert.equal(hidden,true,'parked source must leave the overlay input region');
 S.prepare(ui,{x:20,y:100,width:320,height:180});
 assert.equal(last.rect.y,61,'restore immediately retains the calibrated origin before native target lookup');
 assert.equal(await S.waitForLayout(),true);assert.equal(last.rect.y,61);
 assert.equal(hidden,false,'restore target must be visible before native source lookup');
 assert.equal(created,1);assert.equal(added,1,'Router/Home cannot recreate the source hierarchy');
 S.bindPlayer();assert.equal(seeks.length,1,'lifecycle does not rebind or seek');
 video.surfaceId='full-player';video.state='playing';S.bindPlayer();assert.equal(seeks.length,1,'playing handoff never seeks');
 console.log('PASS compiled source anchor: actual layout, safe-area calibration, retained overlay, paused-frame request, no rebind on lifecycle');
}main().catch(e=>{console.error(e);process.exitCode=1});
