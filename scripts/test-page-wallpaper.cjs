const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(base + 'services/PageWallpaperService.ts', 'utf8').replace(/^import .*;\r?\n/gm, '');
const shared = new Map(), stored = new Map(), files = new Map();
let requests = [], fail = false, invalid = false, failSave = false, decodes = 0, decodeGate;
const pref = { get: async (k, fallback) => stored.get(k) ?? fallback,
  put: async (k,v) => { if (failSave) throw Error('disk full'); stored.set(k,v); }, flush: async () => {} };
const fileIo = {
  OpenMode: {READ_ONLY:1, READ_WRITE:2, CREATE:4, TRUNC:8},
  statSync: p => { if (!files.has(p)) throw Error('missing'); return files.get(p); },
  openSync: p => ({fd:p}), closeSync() {},
  writeSync: (p,b) => { files.set(p, {size:b.byteLength,mtime:Date.now()/1000}); return b.byteLength; },
  renameSync: (a,b) => { files.set(b,files.get(a));files.delete(a); }, unlinkSync: p => files.delete(p)
};
const context = {exports:{}, ArrayBuffer, AppStorage: {get:k=>shared.get(k), setOrCreate:(k,v)=>shared.set(k,v)},
  preferences: {getPreferences:async()=>pref}, fileIo,
  image:{createImageSource:()=>({getImageInfo:async()=>{if(invalid)throw Error('html');return {size:{width:1080,height:1920}};}, createPixelMap:async()=>{decodes++;if(decodeGate)await decodeGate;return {decoded:true};}, release(){}})},
  http:{RequestMethod:{GET:0},HttpDataType:{ARRAY_BUFFER:0}, createHttp:()=>({request:async url=>{
    requests.push(url); if(fail)throw Error('offline');return {responseCode:200,result:new ArrayBuffer(16)};
  },destroy(){}})} };
const layout={exports:{}};vm.runInNewContext(ts.transpileModule(fs.readFileSync(base+'utils/WallpaperLayout.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,layout);
Object.assign(context,layout.exports);
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
(async()=>{
  const S=context.exports.PageWallpaperService, service=S.getInstance();
  assert.equal(context.exports.wallpaperEndpoint('pipw',true),'https://img-api.pipw.top/?phone=true');
  assert.equal(context.exports.wallpaperEndpoint('picsum',false),'https://picsum.photos/1920/1080');
  await service.open({filesDir:'/files'});
  assert.equal(shared.get('pageWallpaperEnabled'),false);
  await service.select('picsum',true);
  const portrait=shared.get('pageWallpaperPortrait');
  assert.ok(portrait.includes('picsum_portrait'));
  await Promise.all([service.ensure(false),service.ensure(false),service.ensure(true)]);
  assert.equal(requests.length,2,'deduplicate requests and restore orientation cache');
  assert.ok(shared.get('pageWallpaperLandscape').includes('picsum_landscape'));
  assert.equal(shared.get('pageWallpaperPortrait'),portrait);
  for(let i=0;i<6;i++)await service.ensure(i%2===0);
  assert.equal(requests.length,2,'rotation does not re-fetch current caches');
  fail=true;await assert.rejects(service.select('pipw',true));
  assert.equal(shared.get('pageWallpaperSource'),'picsum');
  assert.equal(shared.get('pageWallpaperPortrait'),portrait,'failed selection keeps active wallpaper');
  fail=false;invalid=true;await assert.rejects(service.select('picsum',true,true));
  assert.equal(shared.get('pageWallpaperPortrait'),portrait,'invalid response never replaces the cache');
  assert.equal(files.get('/files/page_wallpaper_picsum_portrait.img').size,16);
  invalid=false;failSave=true;await assert.rejects(service.select('pipw',false));
  assert.equal(shared.get('pageWallpaperSource'),'picsum','persistence failure cannot activate a new source');
  failSave=false;files.set('/files/local.img',{size:16,mtime:Date.now()/1000});
  await service.select('local',true,false,'/files/local.img');
  assert.equal(shared.get('pageWallpaperLandscape'),'/files/local.img');
  const count=requests.length;await service.ensure(false);assert.equal(requests.length,count,'local wallpaper never downloads');
  assert.equal(service.localWallpapers().length,1,'applied local copy enters the in-app library');
  const edited=service.localWallpapers()[0];
  edited.portrait={zoom:2,x:0.6,y:-0.2};edited.landscape={zoom:1.4,x:-0.3,y:0.5};
  await service.select('local',true,false,edited.path,edited);
  assert.equal(JSON.parse(shared.get('pageWallpaperLocalComposition')).portrait.zoom,2);
  await service.select('picsum',true);
  assert.equal(service.localWallpapers().length,1,'switching source preserves the library');
  await service.select('local',true,false,edited.path);
  assert.equal(service.localWallpapers()[0].landscape.y,0.5,'reselect preserves separate orientation edits');
  const restored = new S(); await restored.open({filesDir:'/files'});
  assert.equal(shared.get('pageWallpaperPortrait'),'/files/local.img','restart restores local copy');
  assert.equal(restored.localWallpapers()[0].portrait.zoom,2,'restart preserves crop and saved library');
  files.set('/files/page_wallpaper_local_cancel.img',{size:16});restored.discardImport('/files/page_wallpaper_local_cancel.img');assert.ok(!files.has('/files/page_wallpaper_local_cancel.img'));
  restored.discardImport('/files/local.img');assert.ok(files.has('/files/local.img'),'cancel never deletes a saved image');
  await restored.select('none',true);assert.equal(shared.get('pageWallpaperEnabled'),false);
  assert.equal(shared.get('pageWallpaperPortrait'),'');
  assert.equal(shared.get('pageWallpaperLandscape'),'');
  let finishDecode;
  decodeGate = new Promise(resolve => finishDecode = resolve);
  const decodeBefore = decodes;
  const warming = service.prepareImage('/files/next-wallpaper.img');
  const warmingAgain = service.prepareImage('/files/next-wallpaper.img');
  assert.equal(warming, warmingAgain, 'pages share the same in-flight decode');
  assert.equal(service.paintSource('/files/next-wallpaper.img'), 'file:///files/next-wallpaper.img', 'cold decoding does not block the render caller');
  finishDecode(); await warming;
  const bitmap = service.paintSource('/files/next-wallpaper.img');
  assert.equal(typeof bitmap, 'object');
  for (let i=0;i<10;i++) { await service.prepareImage('/files/next-wallpaper.img'); assert.equal(service.paintSource('/files/next-wallpaper.img'),bitmap); }
  assert.equal(decodes, decodeBefore+1, 'repeated navigation reuses one decoded image without decoding again');
  assert.ok(service.decoded.size<=3, 'decoded cache stays bounded');
  decodeGate = undefined;
  const component=fs.readFileSync(base+'components/PageWallpaper.ts','utf8');
  assert.match(component,/currentImage\(\)/,'ordinary method survives CompileArkTS');
  assert.match(component,/this\.createStorageLink\('pageWallpaperLandscape'/);
  console.log('PASS: compiled wallpaper service: both endpoints, orientation cache/deduplication, offline and invalid-response rollback, persistence failure, local restart, disable; compiled component methods.');
})().catch(e=>{console.error(e);process.exitCode=1;});
