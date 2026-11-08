const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const installGlassMaterial=require('./glass-material-test-stub.cjs');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicDetailPage.ts';
const source=fs.readFileSync(file,'utf8'),ast=ts.createSourceFile('detail.ts',source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicDetailPage');
const names=['floatBtnMinBottom','floatBtnMaxBottom','floatBtnAnchorX','floatBtnX','floatBtnY','handleFloatBtnTouch'];
const methods=names.map(name=>cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===name).getText(ast)).join('\n');
const ctx={exports:{},TITLE_BAR_H_VP:56,TouchType:{Down:0,Move:1,Up:2,Cancel:3},curves:{springMotion:()=>0},Context:{animateTo:(_options,f)=>f()}};
vm.runInNewContext(ts.transpileModule('export class Page {'+methods+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,ctx);
function page(){const p=new ctx.exports.Page();Object.assign(p,{viewportWidth:800,viewportHeight:1280,statusBarVp_:24,maxFloatBtnBottom:592,
 dynDetailFloatBtnY:120,dynDetailFloatBtnSide:'left',isDragging:false,smartGripEnabled:false,isLandscape:false,
 smartGripLeft:40,smartGripRight:32,hand:1,da:false,saveFloatBtnPrefs(){this.saves=(this.saves||0)+1;},handleBackToTopClick(){this.clicks=(this.clicks||0)+1;}});return p;}
const touch=(p,type,x,y,snap=true)=>p.handleFloatBtnTouch({type,touches:type<2?[{windowX:x,windowY:y}]:[]},snap);
let p=page();touch(p,0,56,1136);touch(p,1,790,1270);
assert.equal(p.floatBtnX(),752,'drag reaches screen right edge, beyond 32vp placement inset');
assert.equal(p.dynDetailFloatBtnY,0,'drag reaches bottom, beyond 88vp placement reserve');
touch(p,2);assert.equal(p.dynDetailFloatBtnY,88);assert.equal(p.dynDetailFloatBtnSide,'right');assert.equal(p.floatBtnX(),720);assert.equal(p.saves,1);assert.equal(p.clicks,undefined);
p=page();touch(p,0,56,1136);touch(p,1,0,0);assert.equal(p.floatBtnX(),0);assert.equal(p.floatBtnY(),0,'drag reaches screen top');touch(p,2);assert.equal(p.dynDetailFloatBtnY,592);
p=page();touch(p,0,56,1136);touch(p,1,780,10);touch(p,3);assert.equal(p.dynDetailFloatBtnY,120);assert.equal(p.dynDetailFloatBtnSide,'left');assert.equal(p.clicks,undefined,'cancel never triggers back-to-top');
p=page();p.smartGripEnabled=true;touch(p,0,64,1136,false);touch(p,1,700,1270,false);assert.equal(p.floatBtnX(),676,'smart grip also permits horizontal dragging');touch(p,2,0,0,false);assert.equal(p.floatBtnX(),40,'smart grip returns to its designated placement side');assert.equal(p.dynDetailFloatBtnY,88);
p=page();touch(p,0,56,1136);touch(p,2);assert.equal(p.clicks,1,'tap retains back-to-top');assert.equal(p.saves,undefined);
p=page();p.viewportHeight=400;p.maxFloatBtnBottom=392;assert.equal(p.floatBtnMaxBottom(),272,'placement stays below current header after rotation');
const buttonFile=file.replace('pages/DynamicDetailPage.ts','components/DynamicBackToTopButton.ts');
const buttonSource=fs.readFileSync(buttonFile,'utf8'),buttonAst=ts.createSourceFile('button.ts',buttonSource,ts.ScriptTarget.Latest,true);
const buttonClass=buttonAst.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicBackToTopButton');
const region=['touchRegion','refreshMaterial','nativeButton'].map(name=>buttonClass.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(buttonAst)===name).getText(buttonAst)).join('\n');
ctx.HitTestMode={None:0,BLOCK_HIERARCHY:3};
ctx.Color={Transparent:0};ctx.ButtonType={Normal:0};ctx.BlurStyle={NONE:0,COMPONENT_ULTRA_THIN:1};ctx.HorizontalAlign={Start:0};ctx.Alignment={TopStart:0};ctx.Curve={EaseOut:0};ctx.Context.animation=()=>{};
ctx.uiMaterial={ImmersiveStyle:{ULTRA_THIN:0},ImmersiveMaterial:class {constructor(options){this.options=options;}}};
installGlassMaterial(ctx);
ctx.ObservedObject={GetRawObject:value=>value};
const materialCalls=[],touchCallbacks=[];
for(const name of ['Row','Column','Button','Stack'])ctx[name]=new Proxy({}, {get:(_target,key)=>(...args)=>{if(key==='systemMaterial')materialCalls.push(args[0]);if(key==='onTouch')touchCallbacks.push(args[0]);}});
vm.runInNewContext(ts.transpileModule('export class Target {'+region+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,ctx);
const target=new ctx.exports.Target();Object.assign(target,{shown:true,buttonX:100,buttonY:200});
assert.equal(target.touchRegion({touches:[{x:120,y:220}]}),3,'only actual button blocks lower siblings');
for(const point of [{x:99,y:220},{x:149,y:220},{x:120,y:249}])assert.equal(target.touchRegion({touches:[point]}),0,'outside button passes through full-page native scope');
target.shown=false;assert.equal(target.touchRegion({touches:[{x:120,y:220}]}),0,'hidden source never intercepts page');
Object.assign(target,{supported:true,dark:true,color:'#D34E7E',hostWidth:800,hostHeight:1280,buttonScale:1,shown:true,
 icon(){},observeComponentCreation2(f){f(1,true);},onButtonTouch(){}});
target.refreshMaterial();const receiver=target.material,sourceMaterial=target.touchMaterial;
target.nativeButton();target.buttonX=300;target.buttonY=800;target.nativeButton();
assert.deepEqual(materialCalls,[receiver,sourceMaterial,receiver,sourceMaterial],'drag frames retain native material and light-source identity');
assert.equal(receiver.options.interactive,false,'moving visual surface receives light without emitting a stale source');
assert.equal(sourceMaterial.options.lightEffect.color,'#D34E7E','fixed touch frame emits the button color');
for(const [type,pressed] of [[0,true],[1,true],[2,false],[0,true],[3,false]]){touchCallbacks.at(-1)({type,touches:[]});assert.equal(target.pressed,pressed,'full native touch stream retains and releases pressed state');}
console.log('PASS: compiled full-screen back-to-top drag, independent placement limits, nearest side, smart grip, cancel, tap and short viewport.');
