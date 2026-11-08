const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts','utf8');
const start=source.indexOf('private async minimizeToFloating(');assert(start>=0);let open=source.indexOf('{',start),depth=1,end=open+1;
while(depth){const c=source[end++];if(c==='{')depth++;if(c==='}')depth--}
const storage=new Map(),video={surfaceId:'main',state:'playing',width:1920,height:1080},player={takeoverPlayer(v,a,state){this.videoPlayer=v;this.audioPlayer=a;this.playerState=state;this.hasActivePlayer=true}};
let toasts=0,finished=0;
const ctx={exports:{},logInfo(){},logWarn(){},logError(){},setTimeout:()=>1,
 AppStorage:{set:(k,v)=>storage.set(k,v)},PlayerService:{getInstance:()=>player},
 FloatingVideoTransition:{active:()=>false,begin(){},finish(){finished++}},
 FloatingVideoSurface:{prepare(){},park(){}},FloatingPiP:{getInstance:()=>({open:async()=>{video.surfaceId='failed-pip';return false}})}};
vm.runInNewContext(ts.transpileModule('exports.Page=class{'+source.slice(start,end)+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
async function main(){const page=new ctx.exports.Page();Object.assign(page,{floatingMorph:false,play:true,av:video,avAudio:null,
 vi:{bvid:'BV-test',cid:1,title:'video',cover:''},ar:16/9,ct:10,dur:75,prepareFloatingGeometry(){},triggerHaptic(){},
 activeVideoSurfaceId:()=> 'main',getUIContext:()=>({getPromptAction:()=>({showToast(){toasts++}})})});
 await page.minimizeToFloating();assert.equal(page.av,video);assert.equal(video.surfaceId,'main');assert.equal(video.state,'playing');
 assert.equal(player.videoPlayer,null);assert.equal(player.hasActivePlayer,false);assert.equal(storage.get('videoMinimized'),false);
 assert.equal(finished,1);assert.equal(toasts,1);console.log('PASS compiled PiP startup failure: decoder/page/Surface retained, no orphaned minimized state');}
main().catch(error=>{console.error(error);process.exitCode=1});
