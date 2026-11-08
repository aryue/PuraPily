const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function js(s){return ts.transpileModule(s,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;}
const layout={exports:{}};vm.runInNewContext(js(fs.readFileSync(base+'utils/WallpaperLayout.ts','utf8')),layout);
class Box{constructor(v){this.value=v;}get(){return this.value;}set(v){this.value=v;}}
class ViewPU{createStorageLink(k,v){return new Box(v);}}
let applied,fail=false,discarded='';const service={select:async(...args)=>{if(fail)throw Error('disk');applied=args;},localWallpapers:()=>[],discardImport:p=>discarded=p};
const c={exports:{},...layout.exports,ViewPU,ObservedPropertyObjectPU:Box,ObservedPropertySimplePU:Box,
 PageWallpaperService:{getInstance:()=>service},registerNamedRoute(){},vp2px:v=>v,Curve:{EaseOut:0}};
let source=fs.readFileSync(base+'pages/LocalWallpaperPage.ts','utf8').replace(/^import .*;\r?\n/gm,'');
source+='\nexports.Subject=LocalWallpaperPage;';vm.runInNewContext(js(source),c);
(async()=>{
const page=new c.exports.Subject(null,{});page.getUIContext=()=>({animateTo:(o,f)=>{f();o.onFinish?.();},getPromptAction:()=>({showToast(){}})});
const item=new c.LocalWallpaper();item.path='/files/local.img';item.width=1600;item.height=2560;
page.beginEdit(item);page.changeZoom(2);page.previewWidth=500;page.previewHeight=800;page.panX=0;page.panY=0;page.drag({offsetX:100,offsetY:-50});
page.actualWidth=640;page.actualHeight=986.8;assert.ok(Math.abs(page.previewRatio()-640/986.8)<1e-8,'preview follows actual wallpaper viewport');
assert.equal(item.portrait.zoom,1,'preview never mutates the saved entry');const portrait=JSON.stringify(page.crop);
page.switchOrientation(false);assert.equal(page.crop.zoom,1);page.changeZoom(1.5);page.switchOrientation(true);assert.equal(JSON.stringify(page.crop),portrait,'orientation switch preserves independent preview edits');
page.cancelEdit();assert.equal(page.editing,false);assert.equal(discarded,item.path);assert.equal(applied,undefined,'cancel never applies preview');
page.beginEdit(item);page.changeZoom(2);fail=true;await page.apply();assert.equal(page.editing,true,'save failure keeps editor and original');
fail=false;await page.apply();assert.equal(page.editing,false);assert.equal(applied[4].portrait.zoom,2);assert.equal(applied[4].landscape.zoom,1);
console.log('PASS: actual CompileArkTS editor: drag/zoom, independent orientations, preview isolation, cancel, failed-save retry, saved composition.');
})().catch(e=>{console.error(e);process.exitCode=1;});
