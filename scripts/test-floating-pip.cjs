const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/FloatingPiP.ts';
const source=fs.readFileSync(file,'utf8').replace(/^import .*;\s*$/gm,'');
const storage=new Map([['videoMinimized',true],['appInBackground',false]]),controllers=[],timers=new Map(),routes=[];
let timerId=0,binds=0;
const S={ABOUT_TO_START:1,STARTED:2,ABOUT_TO_STOP:3,STOPPED:4,ABOUT_TO_RESTORE:5,ERROR:6};
const player={playbackState:'playing',releases:0,plays:0,pauses:0,hasActivePlayer:true,
 videoPlayer:{surfaceId:'retained',currentTime:10000,state:'playing'},
 playerState:{bvid:'BV-test',cid:1,title:'video',cover:'',currentTime:10,videoAspectRatio:16/9},
 release(){this.releases++},play(){this.plays++;this.playbackState='playing'},pause(){this.pauses++;this.playbackState='paused'}};
const ctx={exports:{},logInfo(){},logWarn(){},
 FloatingVideoSurface:{park(){},prepare(){},controller:{getXComponentSurfaceId:()=> 'retained'},node:()=> 'retained-node',waitForLayout:async()=>true,bindPlayer(){binds++}},
 FloatingVideoTransition:{clearPausedFrame(){this.pausedFrame=undefined},begin(direction){this.direction=direction},finish(){this.direction=''}},
 image:{createPixelMapFromSurfaceWithTransformation:async()=> 'paused-frame'},media:{SeekMode:{SEEK_CLOSEST:2}},
 LiveViewHelper:{end(){},setControlHandlers(handlers){this.handlers=handlers},updateProgress:value=>storage.set('notificationProgress',value),updatePlayState:value=>storage.set('notificationPlaying',value)},
 setTimeout:callback=>{timers.set(++timerId,callback);return timerId},clearTimeout:id=>timers.delete(id),
 setInterval:callback=>{timers.set(++timerId,callback);return timerId},clearInterval:id=>timers.delete(id),
 AppStorage:{get:key=>storage.get(key),set:(key,value)=>storage.set(key,value),setOrCreate:(key,value)=>storage.set(key,value)},
 PlayerService:{getInstance:()=>player},
 PiPWindow:{isPiPEnabled:()=>true,PiPState:S,PiPTemplateType:{VIDEO_PLAY:0},VideoPlayControlGroup:{FAST_FORWARD_BACKWARD:102},
 PiPControlType:{VIDEO_PLAY_PAUSE:0},PiPControlStatus:{PLAY:1,PAUSE:0},
 create:async(config,node)=>{assert.equal(node,undefined,'native XComponent path must receive real source geometry, not typeNode free-node mode');const callbacks=new Map();
 const c={config,starts:0,stops:0,auto:true,on:(event,callback)=>callbacks.set(event,callback),off:event=>callbacks.delete(event),
 emit:(state,reason='')=>callbacks.get('stateChange')?.(state,reason),action:(event,status)=>callbacks.get('controlPanelActionEvent')?.(event,status),
 setAutoStartEnabled(value){this.auto=value},updatePiPControlStatus(){},
 async startPiP(){this.starts++;this.emit(S.ABOUT_TO_START,'requestStart');this.emit(S.STARTED,'requestStart')},
 async stopPiP(){this.stops++;this.emit(S.ABOUT_TO_STOP,'requestDelete');this.emit(S.STOPPED,'requestDelete')}};
 controllers.push(c);return c;}}
};
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
async function main(){
 const pip=ctx.exports.FloatingPiP.getInstance();
 const ui={getHostContext:()=>({}),getRouter:()=>({pushUrl:async options=>{routes.push(options);ctx.LiveViewHelper.handlers={newPlayerPage:true}}})};
 assert.equal(await pip.open(ui,1920,1080),true);const first=controllers[0];
 assert.equal(first.starts,1);assert.equal(first.auto,false,'already-visible PiP cannot auto-start another desktop session');
 pip.foreground();storage.set('appInBackground',true);pip.foreground();storage.set('appInBackground',false);pip.foreground();
 assert.equal(first.stops,0,'Home/foreground never stops or reconstructs system PiP');
 assert.equal(await pip.open(ui,1920,1080),true);assert.equal(controllers.length,1,'opening active PiP reuses the session');
 first.emit(S.STOPPED,'other');assert.equal(player.releases,0,'OS interruption preserves decoder');
 await pip.detach();await pip.open(ui,1920,1080);controllers.at(-1).emit(S.STOPPED,'panelActionDelete');
 assert.equal(player.releases,1);assert.equal(storage.get('videoMinimized'),false);
 storage.set('videoMinimized',true);await pip.open(ui,1920,1080);
 controllers.at(-1).action('playbackStateChanged',0);controllers.at(-1).action('playbackStateChanged',1);
 assert.equal(player.pauses,1);assert.equal(player.plays,1);
  const makeVideo = (time, duration = 100000) => ({ currentTime: time, duration,
    targets: [], seek(target, mode) { assert.equal(mode, 2); this.targets.push(target); } });
  player.hasActivePlayer = true;
  player.videoPlayer = makeVideo(30000); player.audioPlayer = makeVideo(30000);
  player.playerState = { currentTime: 30, duration: 100 };
  pip.seekBy(15);
  assert.equal(player.videoPlayer.targets.at(-1), 45000);
  assert.equal(player.audioPlayer.targets.at(-1), 45000, 'audio/video seek to the same time');
  controllers.at(-1).action('fastForward');
  assert.equal(player.videoPlayer.targets.at(-1), 60000, 'rapid clicks accumulate before currentTime updates');
  controllers.at(-1).action('fastBackward');
  assert.equal(player.videoPlayer.targets.at(-1), 45000, 'system PiP uses the same fixed 15-second step');
  assert.equal(player.playerState.currentTime, 45);
  assert.equal(storage.get('notificationProgress'), 45);
  player.videoPlayer = makeVideo(2000); player.audioPlayer = makeVideo(2000);
  pip.seekBy(-15); assert.equal(player.videoPlayer.targets.at(-1), 0, 'rewind clamps at the start');
  player.videoPlayer = makeVideo(95000); player.audioPlayer = makeVideo(95000);
  player.playbackState = 'paused';
  pip.seekBy(15); assert.equal(player.videoPlayer.targets.at(-1), 100000, 'forward clamps at the duration');
  assert.equal(player.playbackState, 'paused', 'seeking preserves paused state');
  player.videoPlayer = makeVideo(30000); player.audioPlayer = makeVideo(30000);
  pip.beginSeek(1); pip.endSeek();
  assert.equal(player.videoPlayer.targets.at(-1), 45000, 'short press skips exactly 15 seconds');
  assert.equal(timers.size, 0);
  const countBeforeCancel = player.videoPlayer.targets.length;
  pip.beginSeek(-1); pip.endSeek(true);
  assert.equal(player.videoPlayer.targets.length, countBeforeCancel, 'cancelled short press does not seek');
  player.videoPlayer = makeVideo(30000); player.audioPlayer = makeVideo(30000);
  player.playbackState = 'playing';
  const plays = player.plays; const pauses = player.pauses;
  pip.beginSeek(1);
  const delay = [...timers.values()][0]; timers.clear(); delay();
  assert.equal(player.videoPlayer.targets.at(-1), 32000, 'hold starts scanning without a 15-second click');
  const repeat = [...timers.values()][0]; repeat(); repeat(); repeat();
  assert.equal(player.videoPlayer.targets.at(-1), 38000, 'holding continuously advances');
  assert.equal(player.pauses, pauses + 1);
  pip.endSeek();
  assert.equal(player.videoPlayer.targets.at(-1), 38000, 'release does not add a click');
  assert.equal(player.plays, plays + 1, 'release resumes prior playback');
  assert.equal(timers.size, 0, 'release clears scanning timers');
  player.videoPlayer = makeVideo(30000); player.audioPlayer = makeVideo(30000);
  player.playbackState = 'paused';
  pip.beginSeek(-1); const rewind = [...timers.values()][0]; timers.clear(); rewind();
  const repeatBack = [...timers.values()][0]; repeatBack();
  assert.equal(player.videoPlayer.targets.at(-1), 26000);
  pip.endSeek(true);
  assert.equal(player.playbackState, 'paused', 'cancel preserves prior paused state');
  assert.equal(timers.size, 0);
  const listeners=new Map();
  player.videoPlayer.on=(event,callback)=>listeners.set(event,callback);
  player.videoPlayer.off=(event,callback)=>{assert.equal(listeners.get(event),callback);listeners.delete(event)};
  pip.takeoverPlayback();
  listeners.get('stateChange')('completed');assert.equal(player.playbackState,'paused','native controls follow actual completion');
  assert.equal(storage.get('notificationPlaying'),false,'system media session follows PiP completion');
  listeners.get('stateChange')('playing');
  assert.equal(storage.get('notificationPlaying'),true,'system media session follows resumed playback');
  listeners.get('timeUpdate')(42000);assert.equal(player.playerState.currentTime,42);
  player.playerState={bvid:'BV-test',cid:1,title:'video',cover:'',currentTime:30,videoAspectRatio:16/9};
  player.videoPlayer.state='paused';player.videoPlayer.surfaceId='retained';
  const releases=player.releases,c=controllers.at(-1);
  c.emit(S.ABOUT_TO_RESTORE,'panelActionRestore');
  for(let i=0;i<12;i++)await Promise.resolve();
  assert.equal(routes.at(-1).url,'pages/VideoPlayerPage','prepare real target before STOPPED, while native window can animate');
  c.emit(S.STOPPED,'panelActionRestore');
  assert.equal(ctx.LiveViewHelper.handlers.newPlayerPage,true,'native completion must not clear the new page handlers');
  assert.equal(routes.at(-1).url,'pages/VideoPlayerPage');assert.equal(routes.at(-1).params.bvid,'BV-test');
  assert.equal(player.releases,releases,'fullscreen restore reuses the decoder');
  assert.equal(ctx.FloatingVideoTransition.pausedFrame,'paused-frame');
  assert.equal(c.stops,0,'system already stopped during restore, no repeated stop');
  assert.equal(listeners.size,0,'restoring removes only the global service listeners');
  console.log('PASS compiled system-only PiP: one foreground/desktop session, close, paused restore, 15s seek and hold state');
}
main().catch(error=>{console.error(error);process.exitCode=1});
