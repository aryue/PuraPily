const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync('entry/src/main/ets/pages/ProfilePage.ets','utf8');
function method(name){const a=source.indexOf('  private '+(name==='selectSetting'?'async ':'')+name+'(');assert.ok(a>=0);return source.slice(a,source.indexOf('\n  }',a)+4);}
const saved=new Map();let index=0,fail=false,cancel=false,menu;
const c={exports:{},logError(){},preferences:{getPreferences:async()=>({put:async(k,v)=>saved.set(k,v),flush:async()=>{if(fail)throw Error('disk');}})}};
vm.runInNewContext(ts.transpileModule('export class Subject {'+method('glassThicknessLabel')+method('settingLabels')+method('selectSetting')+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
(async()=>{
 const page=new c.exports.Subject();page.isDarkMode=true;page.videoCardGlassThickness='thin';
 page.getUIContext=()=>({getHostContext:()=>({}),getPromptAction:()=>({showActionMenu:async options=>{menu=options;if(cancel)throw Error('cancel');return {index};}})});
 page.otherCardGlassThickness='thick';
 for(const otherCards of [false,true]) {
  const key=otherCards?'otherCardGlassThickness':'videoCardGlassThickness';
  const opposite=otherCards?'videoCardGlassThickness':'otherCardGlassThickness';
  const unchanged=page[opposite];
  for(const [choice,value,label]of[[0,'ultra-thin','超薄'],[1,'thin','薄'],[2,'regular','常规'],[3,'thick','厚'],[4,'ultra-thick','超厚']]){
   index=choice;await page.selectSetting(otherCards?'otherGlass':'videoGlass',index);assert.equal(page[key],value);assert.equal(saved.get(key),value);assert.equal(page.glassThicknessLabel(otherCards),label);
   assert.equal(page[opposite],unchanged,'changing one group must not change the other');
   assert.deepEqual(Array.from(page.settingLabels('videoGlass')),['超薄','薄','常规','厚','超厚']);
  }
  cancel=true;await page.selectSetting(otherCards?'otherGlass':'videoGlass',-1);assert.equal(page[key],'ultra-thick');
  cancel=false;fail=true;index=0;await page.selectSetting(otherCards?'otherGlass':'videoGlass',index);assert.equal(page[key],'ultra-thick','failed save keeps the active material');
  fail=false;index=-1;await page.selectSetting(otherCards?'otherGlass':'videoGlass',index);assert.equal(page[key],'ultra-thick','invalid selection leaves the material alone');
 }
 console.log('PASS: two independent glass groups: five native-style menu choices, immediate saved selection, cancellation and failed-save rollback.');
})().catch(e=>{console.error(e);process.exitCode=1;});
