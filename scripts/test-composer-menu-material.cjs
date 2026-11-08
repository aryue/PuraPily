const fs=require('node:fs');
const prefix=fs.readFileSync('scripts/test-comment-action-menu.cjs','utf8').split('const Menu=load(')[0];
const suite=`
c.HitTestMode={None:0};c.LayoutPolicy={fixAtIdealSize:'ideal'};
let inTitle=false;
for(const name of ['Stack','Column','Navigation','If']) c[name]=new Proxy({}, {get(_target,key){return (...args)=>{
 calls.push({name,key,args,inTitle});
 if(name==='Navigation'&&key==='title'){inTitle=true;args[0].builder();inTitle=false;}
};}});
const MenuSurface=load('CommentMenuSurface');
const Surface=load('NativeComposerSurface');
for(const dark of [true,false]) {
 let contentInTitle=null;
 const surface=new Surface(null,{surfaceWidth:320,surfaceHeight:184,content:()=>{contentInTitle=inTitle;}});
 surface.dark=dark;surface.aboutToAppear();calls=[];surface.initialRender();
 const material=calls.find(x=>x.key==='systemMaterial');
 assert.ok(material.inTitle,'material has a real native title scope');
 assert.equal(material.args[0].options.style,1);
 assert.equal(material.args[0].options.materialColor,dark?'#661C2022':'#88F2F3F5');
 assert.equal(material.args[0].options.interactive,false);assert.equal(material.args[0].options.lightEffect,null);
 assert.equal(contentInTitle,false,'editor and its focus remain in ordinary content subtree');
 const actualRecipe=JSON.stringify(material.args[0].options);
 const previousCalls=calls;calls=[];const reference=new MenuSurface(null,{surfaceWidth:320,surfaceHeight:184,interactive:false,content:()=>{}});reference.dark=dark;reference.aboutToAppear();reference.initialRender();
 assert.equal(actualRecipe,JSON.stringify(calls.find(x=>x.key==='systemMaterial').args[0].options),'recipe is identical to actual comment menu material');calls=previousCalls;
 assert.ok(calls.some(x=>x.name==='Navigation'&&x.key==='hitTestBehavior'&&x.args[0]===0),'material cannot consume editor touches');
 assert.ok(calls.some(x=>x.name==='Navigation'&&x.key==='focusable'&&x.args[0]===false),'material cannot take keyboard focus');
 const resize=calls.find(x=>x.key==='onSizeChange').args[0];resize({}, {width:390,height:484});
 assert.equal(surface.surfaceWidth,390);assert.equal(surface.surfaceHeight,484);
 calls=[];surface.initialRender();
 assert.equal(calls.find(x=>x.name==='Navigation'&&x.key==='height').args[0],516,'emote/expanded editor changes material size');
}
const small=new Surface(null,{surfaceWidth:180,surfaceHeight:36,allCorners:true,content:()=>{}});small.aboutToAppear();calls=[];small.initialRender();
assert.ok(calls.some(x=>x.name==='Column'&&x.key==='borderRadius'&&x.args[0]===12),'compact text fields keep rounded material on all corners');
assert.equal(calls.find(x=>x.name==='Navigation'&&x.key==='height').args[0],68,'compact fields do not inherit composer height');
const extended=new Surface(null,{surfaceWidth:320,surfaceHeight:52,content:()=>{}});extended.aboutToAppear();calls=[];extended.initialRender();
assert.equal(calls.find(x=>x.name==='Navigation'&&x.key==='height').args[0],84,'native scope has only its own edge margin');
assert.equal(extended.surfaceHeight,52,'material frame does not change measured content height');
assert.ok(calls.some(x=>x.name==='Stack'&&x.key==='height'&&x.args[0]===52),'oversized native title has a content-sized frame so it cannot inflate FIT_CONTENT sheets');
const inherited=new Surface(null,{surfaceWidth:320,surfaceHeight:484,active:false,content:()=>{}});inherited.aboutToAppear();calls=[];inherited.initialRender();
assert.ok(!calls.some(x=>x.key==='systemMaterial'),'editor does not create another scrolling material when viewport owns it');
assert.ok(calls.some(x=>x.key==='backgroundColor'&&x.args[0]===0),'inherited surface stays transparent');
c.uiMaterial.isImmersiveMaterialSupported=()=>false;
const fallback=new Surface(null,{content:()=>{}});fallback.aboutToAppear();calls=[];fallback.initialRender();
assert.ok(!calls.some(x=>x.key==='systemMaterial'));assert.ok(calls.some(x=>x.key==='backgroundColor'&&x.args[0]==='#171A1D'));
console.log('Compiled composer surface: matching menu recipe, dark/light tint, native scope, non-intercepting background, measured resize and fallback passed.');
`;
new Function('require',prefix+suite)(require);
