const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const stored=new Map(),shared=new Map();let systemColor=0,applied;
const host={getApplicationContext:()=>({setColorMode:mode=>{applied=mode;}})};
const context={exports:{},AppStorage:{setOrCreate:(k,v)=>shared.set(k,v),get:k=>shared.get(k),has:k=>shared.has(k)},
 preferences:{getPreferences:async()=>({get:async(k,v)=>stored.has(k)?stored.get(k):v,put:async(k,v)=>stored.set(k,v),flush:async()=>{}})},
 ConfigurationConstant:{ColorMode:{COLOR_MODE_DARK:0,COLOR_MODE_LIGHT:1,COLOR_MODE_NOT_SET:-1}},
 resourceManager:{ColorMode:{DARK:0},getSystemResourceManager:()=>({getConfigurationSync:()=>({colorMode:systemColor})})},
 restoreLoginCredentials:async()=>{},logWarn(){}};
const source=fs.readFileSync(root+'utils/ReferenceAppearance.ts','utf8').replace(/^import .*;\r?\n/gm,'');
vm.runInNewContext(ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,context);
(async()=>{
 stored.set('referenceAppearanceVersion',1);stored.set('isDarkMode',false);
 await context.exports.initializeReferenceAppearance(host);assert.equal(shared.get('themeMode'),'light');assert.equal(applied,1);
 for(const mode of ['system','light','dark']){
  stored.set('themeMode',mode);await context.exports.initializeReferenceAppearance(host);
  assert.equal(shared.get('themeMode'),mode);assert.equal(applied,mode==='system'?-1:mode==='dark'?0:1);
 }
 for(systemColor of [0,1]){
  context.exports.applyThemeMode(host,'system');assert.equal(shared.get('isDarkMode'),systemColor===0);
  context.exports.syncThemeConfiguration(1-systemColor);assert.equal(shared.get('isDarkMode'),systemColor!==0);
 }
 for(const mode of ['light','dark']){
  context.exports.applyThemeMode(host,mode);context.exports.syncThemeConfiguration(mode==='dark'?1:0);
  assert.equal(shared.get('isDarkMode'),mode==='dark','fixed theme ignores system changes');
 }
 context.exports.applyThemeMode(host,'system');const before=shared.get('isDarkMode');context.exports.syncThemeConfiguration(undefined);assert.equal(shared.get('isDarkMode'),before);
 console.log('PASS: compiled theme legacy migration, restart, three modes, system changes and fixed-theme isolation.');
})().catch(e=>{console.error(e);process.exitCode=1;});
