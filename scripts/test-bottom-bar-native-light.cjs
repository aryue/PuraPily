const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/FloatingBottomBar.ts';
const source=fs.readFileSync(file,'utf8').replace(/^import .*;\r?\n/gm,'');
const resources=fs.readFileSync('entry/build/default/intermediates/res/default/ResourceTable.txt','utf8');
const colorId=name=>parseInt(resources.match(new RegExp(`^color ${name} (0x[0-9a-f]+)`,'m'))[1],16);
// SDK 26 system resource ID for sys.color.font_primary, preserved by CompileArkTS.
const nativeForeground=125830982;
const calls=[],storage=new Map();let supports=true;
class Box{constructor(v){this.v=v;}get(){return this.v;}set(v){this.v=v;}}
class ViewPU{createStorageLink(k,v){return new Box(v);}declareWatch(){}observeComponentCreation2(f){f(1,true);}}
class Modifier{borderRadius(){return this;}clip(){return this;}backgroundColor(){return this;}systemMaterial(v){this.material=v;return this;}backgroundBlurStyle(v){this.blur=v;return this;}}
function component(name){return new Proxy({}, {get:(_,key)=>(...args)=>{calls.push({name,key,args});}});}
const c={exports:{},ViewPU,SynchedPropertySimpleOneWayPU:Box,ObservedPropertySimplePU:Box,CommonModifier:Modifier,
 deviceInfo:{distributionOSApiVersion:260000,apiAvailable(){return this.distributionOSApiVersion>=260000;}},motion:{HoldingHandStatus:{UNKNOWN_STATUS:0}},curves:{interpolatingSpring(){}},
 uiMaterial:{isImmersiveMaterialSupported:()=>supports,ImmersiveStyle:{ULTRA_THIN:0},ImmersiveMaterial:class{constructor(v){this.options=v;}}},
 Color:{White:'#FFFFFF',Transparent:0},BlurStyle:{COMPONENT_THICK:1},BarPosition:{End:1},TouchType:{Down:0,Move:1,Up:2,Cancel:3},
 FontWeight:{Bold:700,Medium:500},
 FlexAlign:{Center:0},HitTestMode:{None:0,Default:1,Transparent:2,BLOCK_HIERARCHY:3},Curve:{EaseIn:0,EaseOut:1,FastOutSlowIn:2},Context:{animation(){}},
 $r:(name)=>({resource:name}),AppStorage:{setOrCreate:(k,v)=>storage.set(k,v)}};
for(const name of ['Row','Column','Tabs','TabContent','Image','Text'])c[name]=component(name);
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
const bar=new c.exports.FloatingBottomBar(null,{});bar.aboutToAppear();bar.initialRender();
for(const dark of [false,true]) {
 bar.isDarkMode=dark;
 for(let selected=0;selected<3;selected++) {
  bar.activeIndex=selected;
  for(let index=0;index<3;index++) {
   const color=bar.itemColor(index);
   assert.equal(color.id,
    index===selected ? colorId(`floating_nav_selected_${dark?'dark':'light'}`) : nativeForeground);
   const start=calls.length;
   bar.Item('label','outline','selected',index);
   const rendered=calls.slice(start);
   assert.equal(rendered.find(x=>x.name==='Image'&&x.key==='create').args[0],index===selected?'selected':'outline');
   for(const [name,key] of [['Image','fillColor'],['Text','fontColor']]) {
    assert.equal(rendered.find(x=>x.name===name&&x.key===key).args[0].id,color.id);
   }
   assert.ok(!rendered.some(x=>x.key==='blendMode'),'native inversion must not use difference blending');
  }
 }
}
const options=calls.find(x=>x.name==='Tabs'&&x.key==='create').args[0];
assert.equal(options.barModifier.material.options.interactive,true);
assert.equal(options.barModifier.material.options.colorInvert,true,'use native material inversion for the special system foreground resource');
assert.equal(options.barModifier.material.options.lightEffect.color,'#FFFFFF');
assert.ok(!calls.some(x=>x.key==='barOverlap'),'overlap blur must not cover native material');
assert.equal(calls.find(x=>x.name==='Tabs'&&x.key==='hitTestBehavior').args[0],3,'visible tabs block lower siblings without blocking tab children');
bar.hidden=true;calls.length=0;bar.initialRender();assert.equal(calls.find(x=>x.name==='Tabs'&&x.key==='hitTestBehavior').args[0],0,'hidden bar passes input to content');
bar.hidden=false;calls.length=0;bar.initialRender();
const touch=calls.find(x=>x.name==='Tabs'&&x.key==='onTouch').args[0];
for(const [type,active]of [[0,true],[1,true],[2,false],[0,true],[3,false]]){touch({type});assert.equal(storage.get('nativeCardLightActive'),active);}
let selected=-1;bar.onSelect=i=>selected=i;calls.find(x=>x.name==='Tabs'&&x.key==='onTabBarClick').args[0](2);assert.equal(selected,2);
touch({type:0});bar.aboutToDisappear();assert.equal(storage.get('nativeCardLightActive'),false);
supports=false;bar.aboutToAppear();assert.equal(bar.barMaterial().blur,1);
for(const dark of [false,true]) {
 bar.isDarkMode=dark;
 assert.equal(bar.itemColor(0).id,colorId(`floating_nav_foreground_${dark?'dark':'light'}`));
 assert.equal(bar.itemColor(2).id,colorId(`floating_nav_selected_${dark?'dark':'light'}`));
}
c.deviceInfo.distributionOSApiVersion=250000;bar.aboutToAppear();assert.equal(bar.barMaterial().blur,1);
console.log('PASS: compiled bottom bar native source, direct Tabs touch, down/move/up/cancel/disappear, navigation, no covering overlap blur, unsupported/old-API fallback.');
