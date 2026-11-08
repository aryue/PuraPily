const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source=fs.readFileSync(root+'pages/DynamicDetailPage.ts','utf8');
const ast=ts.createSourceFile('page.ts',source,ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicDetailPage');
const names=['openCommentEntry','scrollToComments','openForward','submitForward','toggleLike','correctTopGap','topGapCacheKey'];
const methods=names.map(name=>cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)===name).getText(ast)).join('\n');
let likes=[],forwards=[],result={ok:true},reject=false,finish;
const ctx={exports:{},AppStorage:{setOrCreate(){}},promptAction:{showToast(){}},TOP_EXTRA_GAP_VP:8,CONTENT_TOP_TARGET_VP:64,logInfo(){},
 setDynamicLike:async(id,value)=>{likes.push([id,value]);return result;},
 repostDynamic:async(id,text)=>{forwards.push([id,text]);if(reject)throw Error('offline');return result;}};
vm.runInNewContext(ts.transpileModule('export class Page {'+methods+'}',{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,ctx);
const p=new ctx.exports.Page();let route,scroll,cardY=128;
Object.assign(p,{item:{idStr:'123',forwardCount:4},forwardCount:4,likeState_:{liked:false,count:10},biliCookie:'test',
 hasLogin:()=>true,useSplitLayout:()=>false,statusBarVp_:24,topGap_:88,
 getUIContext:()=>({px2vp:x=>x/2,getRouter:()=>({pushUrl:x=>{route=x;return Promise.resolve();}}),getComponentUtils:()=>({getRectangleById:id=>id==='dynamic-detail-header'?{windowOffset:{y:48},size:{height:160}}:{windowOffset:{y:cardY},size:{height:100}}})}),
 scroller:{currentOffset:()=>({yOffset:100}),scrollTo:x=>{scroll=x;}},commentsScroller:{scrollTo:x=>{scroll=x;}}});
(async()=>{
 p.correctTopGap('test');assert.equal(p.topGap_,136,'measured header clears author card');
 cardY=400;p.topGap_=224;p.correctTopGap('shrink');assert.equal(p.topGap_,136,'excess padding can shrink instead of accumulating');cardY=128;
 p.replyRoot=3;p.replyParent=4;p.replyTargetName='user';p.openCommentEntry();assert.equal(p.replyRoot,0);assert.equal(p.entrySheetOn,true);
 p.entrySheetOn=false;p.scrollToComments();assert.equal(p.entrySheetOn,true,'already reading comments opens input');
 p.entrySheetOn=false;p.useSplitLayout=()=>true;p.scrollToComments();assert.equal(p.entrySheetOn,true,'visible split comments open input');
 await p.toggleLike();assert.equal(p.likeState_.liked,true);assert.equal(p.likeState_.count,11);
 result={ok:false,message:'fail'};await p.toggleLike();assert.equal(p.likeState_.liked,true);assert.equal(p.likeState_.count,11);
 p.hasLogin=()=>false;p.openForward();assert.equal(route.url,'pages/QrCodeLoginPage');
 p.hasLogin=()=>true;p.repostSending=false;p.openForward();assert.equal(p.repostVisible,true);assert.equal(forwards.length,0,'opening never publishes');
 p.repostText='draft';await p.submitForward();assert.equal(p.repostVisible,true);assert.equal(p.repostText,'draft');assert.equal(p.repostSending,false);
 reject=true;await p.submitForward();assert.equal(p.repostText,'draft');assert.equal(p.repostSending,false);reject=false;
 result={ok:true};await p.submitForward();assert.equal(p.forwardCount,5);assert.equal(p.item.forwardCount,5);assert.equal(p.repostVisible,false);assert.equal(p.repostText,'');
 console.log('PASS: compiled detail login, like rollback, comment entry/location, repost success/failure');
})().catch(e=>{console.error(e);process.exitCode=1;});
