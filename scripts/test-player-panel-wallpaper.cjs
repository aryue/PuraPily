const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/components/PageWallpaper.ts';const source=fs.readFileSync(file,'utf8');
function method(name){const a=source.search(new RegExp('^    (?:private )?'+name+'\\(','m'));assert.ok(a>=0,name);return source.slice(a,source.indexOf('\n    }',a)+6);}
const requests=[];const c={exports:{},PageWallpaperService:{getInstance:()=>({ensure:p=>{requests.push(p);return Promise.resolve();}})}};
vm.runInNewContext(ts.transpileModule('export class Subject {'+['portraitSlot','currentImage','reload'].map(method).join('\n')+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
const page=new c.exports.Subject();Object.assign(page,{portrait:true,portraitImage:'portrait-local',landscapeImage:'landscape-local',ready:true,orientation:'landscape'});
assert.equal(page.currentImage(),'landscape-local','narrow landscape player panel must use the device landscape crop, not its own aspect');page.reload();assert.equal(requests.pop(),false);
page.orientation='portrait';page.portrait=false;assert.equal(page.currentImage(),'portrait-local');page.reload();assert.equal(requests.pop(),true);
page.orientation='auto';assert.equal(page.currentImage(),'landscape-local');page.landscapeImage='';assert.equal(page.currentImage(),'portrait-local','cached orientation fallback remains available');
assert.match(source,/if \(!this.embedded\)/,'embedded panel must not replace full-page preview viewport');
console.log('PASS: compiled panel wallpaper: explicit device orientation overrides panel aspect, correct source/crop slot, fallback and viewport isolation.');
