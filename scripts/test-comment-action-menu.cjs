const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/';
class Box { constructor(v) { this.v=v; } get(){return this.v;} set(v){this.v=v;} reset(v){this.v=v;} }
let calls=[], animations=[], finished=[], copied=[], reports=[], blacklisted=[], messages=[], timers=[];
class ViewPU {
  createStorageLink(_k,v){return new Box(v);}
  observeComponentCreation2(fn){fn(1,true);}
  ifElseBranchUpdateFunction(_i,fn){fn();}
  static create(v){v.content?.();}
  getUIContext(){return context;}
}
const prompt={showToast: v=>messages.push(v.message),showActionMenu: async()=>({index:1})};
let glyphWidth=14,glyphHeight=18;
const context={px2vp:v=>v/2,getMeasureUtils:()=>({measureTextSize:({textContent})=>({width:textContent.length*glyphWidth*2,height:glyphHeight*2})}),getPromptAction:()=>prompt,animateTo(options,fn){animations.push(options);fn();if(options.onFinish)finished.push(options.onFinish);}};
const ui=name=>new Proxy({}, {get(_t,key){return (...args)=>{calls.push({name,key,args});if(name==='Navigation'&&key==='title')args[0].builder();};}});
const c={exports:{},ColorFilter:class{constructor(v){this.values=v;}},ViewPU,SynchedPropertyNesedObjectPU:Box,SynchedPropertySimpleOneWayPU:Box,ObservedPropertySimplePU:Box,
  Stack:ui('Stack'),Column:ui('Column'),Row:ui('Row'),Image:ui('Image'),Text:ui('Text'),If:ui('If'),Button:ui('Button'),Scroll:ui('Scroll'),
  Navigation:ui('Navigation'),Gesture:ui('Gesture'),PanGesture:ui('PanGesture'),NavPathStack:class{},
  ScrollDirection:{Horizontal:0},BarState:{Off:0},TextAlign:{Center:0},GesturePriority:{Low:0},PanDirection:{Vertical:1},TouchType:{Down:0,Up:1,Cancel:2},
  Alignment:{TopStart:0,Center:1,Bottom:2},FlexAlign:{Center:0},HorizontalAlign:{Center:0},Curve:{EaseIn:0,EaseOut:1},Color:{Transparent:0,White:'#fff'},
  NavigationMode:{Stack:0},BarStyle:{STACK:0},BlurStyle:{NONE:0,COMPONENT_ULTRA_THIN:1,COMPONENT_THICK:2},
  curves:{springMotion:()=> 'spring'},setTimeout:fn=>timers.push(fn),
  CommentMenuSurface:class {constructor(_p,params){Object.assign(this,params);}},
  pasteboard:{MIMETYPE_TEXT_PLAIN:'text',createData:(_t,v)=>v,getSystemPasteboard:()=>({setData:async v=>copied.push(v)})},
  blacklistUploader:async mid=>{blacklisted.push(mid);return true;},reportComment:async(...args)=>{reports.push(args);return '举报已提交';},
  deviceInfo:{apiAvailable:()=>true,distributionOSApiVersion:260000},uiMaterial:{isImmersiveMaterialSupported:()=>true,ImmersiveStyle:{ULTRA_THIN:0,THICK:1},ImmersiveMaterial:class{constructor(o){this.options=o;}}}};
function load(file){c.exports={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(base+file+'.ts','utf8').replace(/^import .*;\r?\n/gm,''),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);return c.exports[file];}
const Menu=load('CommentActionMenu');
const target={oid:91,rpid:22,type:17,member:{mid:'44'},content:{message:'测试正文'}};
function make(){return new Menu(null,{comment:target,onClose:()=>calls.push({name:'closed'}),onReply:()=>calls.push({name:'reply'})});}
function finish(){while(finished.length)finished.shift()();}
async function tick(){await Promise.resolve();await Promise.resolve();await Promise.resolve();}
(async()=>{
 let menu=make();assert.ok(menu.actionWidth('加入黑名单')>=86,'custom font label plus side bearings must fit');glyphWidth=22;assert.ok(menu.actionWidth('加入黑名单')>=126,'large font expands item instead of truncating');glyphHeight=38;menu.aboutToAppear();assert.ok(menu.actionRowHeight>=104,'large font expands row height');timers=[];glyphWidth=14;glyphHeight=18;menu=make();menu.aboutToAppear();assert.equal(menu.offsetY,280);timers.shift()();assert.equal(menu.offsetY,0);
 calls=[];menu.panelContent();assert.ok(calls.some(v=>v.name==='Scroll'&&v.key==='align'&&v.args[0]===0),'short action rows remain left aligned');
 const update=calls.find(v=>v.name==='PanGesture'&&v.key==='onActionUpdate').args[0];
 const end=calls.find(v=>v.name==='PanGesture'&&v.key==='onActionEnd').args[0];
 const cancel=calls.find(v=>v.name==='PanGesture'&&v.key==='onActionCancel').args[0];
 update({offsetY:60});assert.equal(menu.offsetY,60,'downward drag follows finger');
 end({offsetY:60,velocityY:0});assert.equal(menu.offsetY,0);assert.equal(menu.closing,false);
 update({offsetY:-100});assert.equal(menu.offsetY,-18,'upward resistance');
 end({offsetY:-100,velocityY:1000});assert.equal(menu.offsetY,0);assert.equal(menu.closing,false);
 update({offsetY:45});cancel();assert.equal(menu.offsetY,0);assert.equal(menu.closing,false);
 const touch=calls.find(v=>v.name==='Stack'&&v.key==='onTouch').args[0];
 touch({type:0});assert.equal(menu.pressed,'reply');touch({type:2});assert.equal(menu.pressed,'');
 update({offsetY:110});end({offsetY:110,velocityY:0});assert.equal(menu.closing,true);assert.equal(menu.offsetY,280);
 assert.ok(!calls.some(v=>v.name==='closed'),'retain panel until exit finishes');finish();assert.ok(calls.some(v=>v.name==='closed'));
 menu=make();calls=[];menu.close('reply');menu.close('reply');assert.ok(!calls.some(v=>v.name==='reply'));finish();assert.equal(calls.filter(v=>v.name==='reply').length,1);
 menu=make();menu.close('copy');finish();await tick();assert.deepEqual(copied,['测试正文']);
 menu=make();menu.close('report');finish();await tick();assert.deepEqual(reports,[[91,22,17,7]],'selected reason and reply type preserved');
 menu=make();menu.close('blacklist');finish();await tick();assert.deepEqual(blacklisted,[44]);
 menu=make();menu.close('reply');menu.aboutToDisappear();calls=[];finish();assert.ok(!calls.length,'discard late exit callbacks');
 const Surface=load('CommentMenuSurface');
 for(const interactive of [true,false]){
  const surface=new Surface(null,{surfaceWidth:300,surfaceHeight:54,interactive,bottomExtension:interactive?0:160});surface.content=()=>{};surface.aboutToAppear();calls=[];surface.initialRender();
  const material=calls.find(v=>v.key==='systemMaterial');const options=material.args[0].options;
  assert.equal(options.style,interactive?0:1,'thick frosted panel with independent thin buttons');assert.equal(options.interactive,interactive);assert.equal(!!options.lightEffect,interactive,'only buttons receive native press light');
  assert.ok(calls.some(v=>v.name==='Navigation'&&v.key==='title'),'real native material title scope');
  assert.equal(calls.find(v=>v.name==='Stack'&&v.key==='height').args[0],interactive?54:214,'material root must include bottom extension to avoid native clipping');
  const height=calls.find(v=>v.name==='Navigation'&&v.key==='height').args[0];assert.equal(height,interactive?86:246,'panel material extends below its nominal content layout');
 }
 console.log('Compiled comment menu: finger tracking, upward resistance, rebound, cancellation, deferred dismissal, duplicate taps, action targets, report reason, native interactive surfaces passed.');
})().catch(e=>{console.error(e);process.exitCode=1;});
