const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/NativeCardGlass.ts';
let source = fs.readFileSync(path,'utf8').replace(/^import .*;\r?\n/gm,'');
const calls=[]; let titleScope=false, supports=true, probes=0;
class Box { constructor(v){this.value=v;} get(){return this.value;} set(v){this.value=v;} reset(v){this.value=v;} }
class ViewPU { createStorageLink(_key,v){return new Box(v);} observeComponentCreation2(f){f(1,true);} ifElseBranchUpdateFunction(_id,f){f();} }
function ui(name){return new Proxy({}, {get(_target,key){if(key==='canRetake')return ()=>false; return (...args)=>{
  calls.push({name,key,args,titleScope});
  if(name==='Navigation'&&key==='title'){titleScope=true;args[0].builder();titleScope=false;}
};}});}
const c={exports:{},ViewPU,SynchedPropertySimpleOneWayPU:Box,SynchedPropertyObjectOneWayPU:Box,ObservedPropertySimplePU:Box,
  Stack:ui('Stack'),Column:ui('Column'),Navigation:ui('Navigation'),If:ui('If'),NavPathStack:class{},
  LayoutPolicy:{fixAtIdealSize:'ideal'},Alignment:{TopStart:0},HitTestMode:{None:0},NavigationMode:{Stack:0},BarStyle:{STACK:0},
  Color:{Transparent:0,White:'#FFFFFF'},BlurStyle:{NONE:0,COMPONENT_THIN:1},vp2px:v=>v*2,
  Path:class {commands(value){return {value};}},
  deviceInfo:{distributionOSApiVersion:260000,apiAvailable(){return this.distributionOSApiVersion>=260000;}},
  uiMaterial:{isImmersiveMaterialSupported(){probes++;return supports;},ImmersiveStyle:{ULTRA_THIN:0,THIN:1,REGULAR:2,THICK:3,ULTRA_THICK:4},
    ImmersiveMaterial:class {constructor(options){this.options=options;}}}};
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
const Subject=c.exports.NativeCardGlass;
for(const [thickness,expected]of[['ultra-thin',0],['thin',1],['regular',2],['thick',3],['ultra-thick',4]]){
  const card=new Subject(null,{surfaceWidth:250,surfaceHeight:200,radius:4});card.thickness=thickness;card.aboutToAppear();
  calls.length=0;card.initialRender();
  let material=calls.filter(x=>x.key==='systemMaterial');assert.equal(material.length,1);assert.ok(material[0].titleScope);
  assert.equal(material[0].args[0].options.style,expected);assert.equal(material[0].args[0].options.lightEffect,null);
  card.externalLightActive=true;calls.length=0;card.initialRender();
  material=calls.filter(x=>x.key==='systemMaterial');assert.equal(material.length,2);
  assert.equal(material[1].args[0].options.style,expected);assert.equal(material[1].args[0].options.lightEffect.color,'#FFFFFF');
  assert.equal(material[1].args[0].options.interactive,false,'card does not create its own touch light');
  for (const dark of [true,false]) {
    card.dark=dark;
    for (const enabled of [true,false]) {
      card.tintEnabled=enabled;calls.length=0;card.initialRender();
      const expectedTint=enabled?(dark?'#2017181A':'#20FFFFFF'):0;
      const layers=calls.filter(x=>x.key==='systemMaterial');
      assert.equal(layers.length,2);
      for(const layer of layers)assert.equal(layer.args[0].options.materialColor,expectedTint,'base and rim update tint together');
    }
  }
  const mask=calls.find(x=>x.key==='clipShape').args[0].value;
  assert.equal((mask.match(/ Z/g)||[]).length,2,'rim has outer path and oppositely wound center cutout');
  card.updateStateVars({surfaceWidth:180,surfaceHeight:80,radius:4});calls.length=0;card.initialRender();
  assert.equal(calls.find(x=>x.name==='Navigation'&&x.key==='width').args[0],212,'scope follows measured content width');
  assert.equal(calls.find(x=>x.name==='Navigation'&&x.key==='height').args[0],112,'scope follows measured content height');
  assert.ok(calls.some(x=>x.name==='Navigation'&&x.key==='hitTestBehavior'&&x.args[0]===0),'background cannot consume content input');
}
// Other-card material changes must not read the video group's style or tint.
for(const [otherThickness,expected] of [['ultra-thin',0],['thin',1],['regular',2],['thick',3],['ultra-thick',4]]) {
  const profile=new Subject(null,{surfaceWidth:400,surfaceHeight:120,radius:20,otherCards:true});
  profile.thickness='thin';profile.tintEnabled=false;profile.otherThickness=otherThickness;
  profile.aboutToAppear();
  for (const externalLightActive of [false, true, false]) {
  profile.externalLightActive=externalLightActive;
  for(const otherTintEnabled of [true,false]) {
    profile.otherTintEnabled=otherTintEnabled;calls.length=0;profile.initialRender();
    const layers=calls.filter(x=>x.key==='systemMaterial');
    assert.equal(layers.length,2,'other-card receiver persists without a bottom-bar press, including release');
    for(const layer of layers) {
      assert.equal(layer.args[0].options.style,expected,'other-card style is independent of video style');
      assert.equal(layer.args[0].options.materialColor,otherTintEnabled?'#2017181A':0,'other-card tint is independent of video tint');
    }
    assert.equal(layers[0].args[0].options.lightEffect,null);
    assert.equal(layers[1].args[0].options.lightEffect.color,'#FFFFFF');
    assert.ok(calls.some(x=>x.key==='clipShape'),'native light remains clipped to rim');
    assert.equal(layers[1].args[0].options.interactive,false,'persistent receiver never creates a card touch source');
  }
  }
}
// Each card group owns its own color-invert switch; both material layers follow it.
for (const [otherCards, field] of [[false, 'invertEnabled'], [true, 'otherInvertEnabled']]) {
  const card = new Subject(null,{surfaceWidth:260,surfaceHeight:120,radius:12,otherCards});
  card.thickness='ultra-thin';card.otherThickness='ultra-thin';card.externalLightActive=true;card.aboutToAppear();
  for (const on of [false,true,false]) {
    card[field]=on;calls.length=0;card.initialRender();
    const layers=calls.filter(x=>x.key==='systemMaterial');
    assert.equal(layers.length,2);
    for(const layer of layers)assert.equal(layer.args[0].options.colorInvert,on,'base and rim follow the same group switch');
  }
}
const mixed=new Subject(null,{surfaceWidth:200,surfaceHeight:100,otherCards:true});
mixed.invertEnabled=true;mixed.otherInvertEnabled=false;mixed.externalLightActive=true;mixed.aboutToAppear();
calls.length=0;mixed.initialRender();
for(const layer of calls.filter(x=>x.key==='systemMaterial'))
  assert.equal(layer.args[0].options.colorInvert,false,'other-card switch ignores the video switch');
const capsule=new Subject(null,{surfaceWidth:104,surfaceHeight:46,radius:24,clearGlass:true,otherCards:true});
capsule.thickness='regular';capsule.tintEnabled=true;capsule.dark=true;capsule.externalLightActive=true;
capsule.aboutToAppear();calls.length=0;capsule.initialRender();
for(const layer of calls.filter(x=>x.key==='systemMaterial')) {
  assert.equal(layer.args[0].options.style,0,'clear capsule stays ultra-thin independently of card settings');
  assert.equal(layer.args[0].options.materialColor,0,'clear capsule has no dark tint in either layer');
  assert.equal(layer.args[0].options.colorInvert,true,'clear capsule forces inversion regardless of switches');
}
const empty=new Subject(null,{});empty.aboutToAppear();calls.length=0;empty.initialRender();assert.ok(!calls.some(x=>x.name==='Navigation'));
supports=false;const fallback=new Subject(null,{surfaceWidth:200,surfaceHeight:100});fallback.aboutToAppear();calls.length=0;fallback.initialRender();
assert.ok(!calls.some(x=>x.key==='systemMaterial'));assert.ok(calls.some(x=>x.key==='backgroundBlurStyle'));
c.deviceInfo.distributionOSApiVersion=250000;probes=0;new Subject(null,{}).aboutToAppear();assert.equal(probes,0,'old API never calls the new capability API');
const surfaces=[];
const surfaceContext={...c,exports:{},__Common__:ui('__Common__'),NativeCardGlass:class {constructor(_parent,params){surfaces.push(params);}}};
surfaceContext.ordinaryCardColor=dark=>dark?'#17181A':'#FFFFFF';
ViewPU.create=()=>{};
const surfaceSource=fs.readFileSync(path.replace('NativeCardGlass.ts','PageSurface.ts'),'utf8').replace(/^import .*;\r?\n/gm,'');
vm.runInNewContext(ts.transpileModule(surfaceSource,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,surfaceContext);
for(const wallpaper of [false,true]) {
  const page=new surfaceContext.exports.PageSurface(null,{surfaceWidth:400,surfaceHeight:120,content:()=>{}});
  page.wallpaper=wallpaper;
  for(const glassEnabled of [true,false,true]) {
    page.glassEnabled=glassEnabled;surfaces.length=0;calls.length=0;page.initialRender();
    assert.equal(surfaces.length,glassEnabled?1:0,'other cards are controlled by their switch, independently of wallpaper');
    if(glassEnabled) {
      assert.equal(surfaces[0].otherCards,true,'other-card settings reach native child');
      assert.ok(calls.some(x=>x.name==='__Common__'&&x.key==='position'),'material is positioned outside content measurement');
    }
    assert.equal(calls.find(x=>x.key==='backgroundColor').args[0],glassEnabled?0:(wallpaper?'#D9202228':'#17181A'),'disabling restores the original wallpaper alpha or neutral surface');
  }
  const resize=calls.find(x=>x.key==='onSizeChange').args[0];
  resize({}, {width:320,height:60});
  surfaces.length=0;calls.length=0;page.initialRender();
  assert.equal(surfaces[0].surfaceHeight,60,'material shrinks when settings rows collapse');
  assert.equal(surfaces[0].surfaceWidth,320,'material follows resized content');
}
const lightPage=new surfaceContext.exports.PageSurface(null,{surfaceWidth:400,surfaceHeight:100,content:()=>{}});
lightPage.dark=false;lightPage.glassEnabled=false;
for(const [wallpaper,expected] of [[true,'#E6FFFFFF'],[false,'#FFFFFF']]) {
  lightPage.wallpaper=wallpaper;calls.length=0;lightPage.initialRender();
  assert.equal(calls.find(x=>x.key==='backgroundColor').args[0],expected,'light ordinary surface keeps original tint and opacity');
}
// The continuous-feed exception disables both native material and fallback without hiding content.
let contentRenders=0;
const bypassed=new surfaceContext.exports.PageSurface(null,{active:false,fullHeight:true,surfaceWidth:400,surfaceHeight:300,content:()=>{contentRenders++;}});
for(const enabled of [true,false]) {
  bypassed.glassEnabled=enabled;surfaces.length=0;calls.length=0;bypassed.initialRender();
  assert.equal(surfaces.length,0,'inactive feed surface never creates native glass');
  assert.equal(calls.find(x=>x.key==='backgroundColor').args[0],0,'inactive surface leaves original panel background intact');
  assert.ok(calls.some(x=>x.name==='Stack'&&x.key==='height'&&x.args[0]==='100%'),'bounded panels fill their existing slot');
}
assert.equal(contentRenders,2,'bypassing glass preserves real content and lists');
console.log('PASS: compiled native glass: five thicknesses, independent video/other styles, tints and inversion switches, shared ProfilePage ordinary recipe and other-card enable/disable without wallpaper, native rim-only light, resize, input pass-through and fallback.');
