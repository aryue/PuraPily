const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/CommentReplySurface.ts';
const source=fs.readFileSync(file,'utf8').replace(/^import .*;\r?\n/gm,'');
class Box{constructor(value){this.value=value;}get(){return this.value;}set(value){this.value=value;}reset(value){this.value=value;}}
class ViewPU{createStorageLink(_key,value){return new Box(value);}observeComponentCreation2(f){f(1,true);}ifElseBranchUpdateFunction(_id,f){f();}}
const calls=[],surfaces=[];let rendered=0;
function ui(name){return new Proxy({}, {get:(_target,key)=>(...args)=>{calls.push({name,key,args});}});}
const context={exports:{},ViewPU,SynchedPropertySimpleOneWayPU:Box,ObservedPropertySimplePU:Box,
 Stack:ui('Stack'),Column:ui('Column'),If:ui('If'),__Common__:ui('__Common__'),Alignment:{TopStart:0},LayoutPolicy:{fixAtIdealSize:'ideal'},
 PageSurface:class{constructor(_parent,params){surfaces.push(params);params.content();}}};
ViewPU.create=()=>{};
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
for(const frosted of [false,true])for(const dark of [true,false]){
 const surface=new context.exports.CommentReplySurface(null,{frosted,content:()=>rendered++});surface.dark=dark;
 calls.length=0;surfaces.length=0;surface.initialRender();
 assert.equal(surfaces.length,frosted?1:0,'only dynamic previews join the other-card glass group');
 if(frosted){assert.equal(surfaces[0].radius,8);assert.ok(!calls.some(c=>c.key==='backgroundColor'),'no inset tint hides the native receiver');}
 else assert.equal(calls.find(c=>c.key==='backgroundColor').args[0],dark?'#0A0B0C':'#F1F2F3','ordinary playback reply previews retain their original panel');
}
assert.equal(rendered,4,'each preview retains exactly one real content tree');
console.log('PASS: compiled dynamic reply owns measured PageSurface glass/rim; ordinary replies unchanged; one content tree per preview.');
