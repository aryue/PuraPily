const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const src=fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/DynamicDetailPage.ts','utf8');
const ast=ts.createSourceFile('page.ts',src,ts.ScriptTarget.Latest,true),c=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicDetailPage');
const names=['queueTopGapCorrection','recheckTopLayout','correctTopGap','useSplitLayout','restoreLayoutScroll'];
const methods=names.map(name=>c.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===name).getText(ast)).join('\n');
let next=0,timers=new Map(),mounted=false,bodyY=100,headerY=0,offset=0,ids=[];
const ctx={exports:{},TOP_EXTRA_GAP_VP:8,logInfo(){},setTimeout:fn=>{timers.set(++next,fn);return next;},clearTimeout:id=>timers.delete(id)};
vm.runInNewContext(ts.transpileModule('export class Page{'+methods+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,ctx);
const p=new ctx.exports.Page();Object.assign(p,{layoutActive:true,topLayoutRevision:0,topLayoutTimer:-1,item:{},contentReady_:true,topGap_:64,statusBarVp_:40,viewportWidth:900,viewportHeight:500,isLandscape:false,
 bodyScroller:{currentOffset:()=>({yOffset:offset})},scroller:{currentOffset:()=>({yOffset:offset})},getUIContext:()=>({px2vp:x=>x/2,getComponentUtils:()=>({getRectangleById:id=>{ids.push(id);if(!mounted)throw Error('pane not mounted');return id==='dynamic-detail-header'?{windowOffset:{y:headerY},size:{height:112}}:{windowOffset:{y:bodyY+2*(p.topGap_-64)}};}})})});
function step(){const [id,fn]=timers.entries().next().value;timers.delete(id);fn();}
assert.equal(p.useSplitLayout(),true,'actual viewport wins before media-query notification');
p.queueTopGapCorrection();step();assert.equal(p.topGap_,64,'missing pane is retried');mounted=true;step();assert.equal(p.topGap_,78,'first mounted landscape pane is corrected');assert.ok(ids.includes('dd_card'));
const old=[...timers.values()][0];p.viewportWidth=500;p.viewportHeight=900;p.queueTopGapCorrection();const prior=p.topGap_;old();assert.equal(p.topGap_,prior,'stale orientation callback ignored');step();assert.ok(ids.includes('dd_card'));
headerY=40;p.queueTopGapCorrection();step();assert.equal(p.topGap_,prior+20,'header settling can re-trigger correction');
offset=150;p.queueTopGapCorrection();const scrolled=p.topGap_;step();assert.equal(p.topGap_,scrolled,'scroll position never becomes top padding');
p.layoutActive=false;const disposed=p.topGap_;for(const fn of timers.values())fn();assert.equal(p.topGap_,disposed,'exited page ignores layout callbacks');
console.log('PASS: compiled immediate rotation, delayed pane mount, title settling, stale callbacks and scroll safety');
