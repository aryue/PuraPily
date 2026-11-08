const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const c={exports:{}};vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'utils/WallpaperLayout.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
const {wallpaperFrame,cleanWallpaperCrop}=c.exports;
for(const [w,h]of [[1600,2560],[2560,1600],[1080,1920],[1920,1080]])for(const [iw,ih]of [[800,1200],[3000,1000]])for(const zoom of [1,1.8,4])for(const x of [-1,0,1]){
 const crop={zoom,x,y:-x};const f=wallpaperFrame(w,h,iw,ih,crop);assert.ok(f.width>=w-1e-8&&f.height>=h-1e-8);
 assert.ok(Math.abs(f.x)<=(f.width-w)/2+1e-8&&Math.abs(f.y)<=(f.height-h)/2+1e-8,'drag can never reveal blank edges');
 const preview=wallpaperFrame(w/5,h/5,iw,ih,crop);for(const key of ['width','height','x','y'])assert.ok(Math.abs(preview[key]*5-f[key])<1e-7,'preview must match full screen');
}
assert.equal(cleanWallpaperCrop({zoom:NaN,x:Infinity,y:-5}).zoom,1);assert.equal(cleanWallpaperCrop({zoom:99,x:2,y:-2}).zoom,4);
assert.equal(cleanWallpaperCrop({zoom:2,x:2,y:-2}).x,1);
console.log('PASS: compiled wallpaper geometry: portrait/landscape preview matches applied layout, 1–4x zoom, pan limits, no blank edges, malformed crop recovery.');
