const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicDetailPage.ts','utf8');
const ast=ts.createSourceFile('page.ts',source,ts.ScriptTarget.Latest,true),cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicDetailPage');
const names=['aboutToAppear','applyItem','topGapCacheKey'];const methods=names.map(name=>cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===name).getText(ast)).join('\n');
const cache=new Map();let route,requests=0,timers=0;
const ctx={exports:{},TITLE_BAR_H_VP:56,TOP_EXTRA_GAP_VP:8,display:{getDefaultDisplaySync:()=>({width:800,height:1280})},AppStorage:{get:k=>cache.get(k)},setTimeout(){timers++;throw Error('body must not be gated by a timer');}};
vm.runInNewContext(ts.transpileModule(`export class Page {${methods}}`,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);
function page(params){const p=new ctx.exports.Page();Object.assign(p,{statusBarVp_:0,dynDetailFloatBtnY:120,maxFloatBtnBottom:592,likeState_:{},item:null,initSmartGrip(){},initOrientation(){},floatBtnMinBottom:()=>88,queueTopGapCorrection(){},loadFollowStatus(){},loadComments(){return new Promise(()=>{});},loadDetail(){requests++;return new Promise(()=>{});},getUIContext:()=>({px2vp:x=>x/2,getRouter:()=>({getParams:()=>params})})});return p;}
const item={idStr:'1',forwardCount:2,commentCount:3,liked:true,likeCount:4};const p=page({dynIdStr:'1',preload:item});p.aboutToAppear();assert.equal(p.item,item);assert.equal(p.loading,false);assert.equal(requests,1,'detail refresh remains asynchronous');assert.equal(timers,0,'preloaded content never waits for hide/show timers');assert.equal(p.likeState_.count,4);
cache.set(p.topGapCacheKey(),108);const cached=page({dynIdStr:'1',preload:item});cached.aboutToAppear();assert.equal(cached.topGap_,108,'reentry starts with measured geometry');
const cold=page({dynIdStr:'2'});cold.aboutToAppear();assert.equal(cold.item,null);cold.applyItem({...item,idStr:'2'});assert.equal(cold.item.idStr,'2','cold response becomes renderable immediately');assert.equal(timers,0);
assert.ok(!source.includes('contentShown_'),'no opacity gate survives compilation');assert.ok(!source.includes('CONTENT_SHOW_DELAY_MS'),'no fixed entry delay survives compilation');
console.log('PASS compiled detail: immediate preload, background refresh, immediate cold response, measured gap reuse, no body delay or opacity gate.');
