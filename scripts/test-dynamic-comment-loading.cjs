const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function ast(file){return ts.createSourceFile('file.ts',fs.readFileSync(base+file,'utf8'),ts.ScriptTarget.Latest,true);}
function run(src,ctx){vm.runInNewContext(ts.transpileModule(src,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,ctx);}
const api=ast('api/BilibiliApi.ts');
const fn=api.statements.find(n=>ts.isFunctionDeclaration(n)&&n.name?.text==='getCommentsByType').getText(api);
let cooldown=0,calls=0,destroyed=0,delays=[],response={responseCode:412};
const a={exports:{},logInfo(){},logWarn(){},logError(){},getRateLimitCooldown:()=>cooldown,triggerRateLimitCooldown:()=>cooldown=60000,
 AppSign:{generateWebParams:async()=>''},getRotatedHeaders:()=>({}),tryDynamicCommentThrottle:async()=>!cooldown,commentThrottleRequest:async()=>{},
 setTimeout:(fn,ms)=>{delays.push(ms);fn();return 1;},http:{RequestMethod:{GET:'GET'},createHttp:()=>({request:async()=>{calls++;if(response instanceof Error)throw response;return response;},destroy:()=>destroyed++})},AppStorage:{get:()=>''}};
run(fn+'\nexports.getCommentsByType=getCommentsByType;',a);
const page=ast('pages/DynamicDetailPage.ts'),cls=page.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='DynamicDetailPage');
const methods=['loadComments','restoreCommentCache','failComments'].map(name=>cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(page)===name).getText(page)).join('\n');
let seq=0,timers=new Map(),resolveRequest;
const c={exports:{},logError(){},ObservableComment:{from:x=>x},getDynComments:()=>new Promise(resolve=>resolveRequest=resolve),setTimeout:fn=>{timers.set(++seq,fn);return seq;},clearTimeout:id=>timers.delete(id)};
run('export class Page{'+methods+'}',c);
function subject(){const p=new c.exports.Page();Object.assign(p,{item:{commentIdStr:'123',commentType:17},commentsSort:3,comments:[],commentCaches:new Map(),commentRequests:new Map(),commentFailures:new Set(),commentRequestSeq:0,commentsHasMore:false,commentsCursor:0,repliesVersion:0});return p;}
(async()=>{
 assert.equal(await a.exports.getCommentsByType('123',17,0,20,3,true),null);assert.equal(calls,1);assert.equal(destroyed,1);assert.deepEqual(delays,[],'412 never enters minute-long retry queue');
 assert.equal(await a.exports.getCommentsByType('123',17,0,20,3,true),null);assert.equal(calls,1,'cooldown skips network');
 cooldown=0;response=new Error('offline');assert.equal(await a.exports.getCommentsByType('123',17,0,20,3,true),null);assert.equal(calls,2,'offline fails once without retry');
 assert.equal(await a.exports.getCommentsByType('123',17,0,20,3,true,()=>false),null);assert.equal(calls,2,'exited requests never send');
 const p=subject();const first=p.loadComments(true);resolveRequest(null);await first;assert.equal(p.commentsLoading,false);assert.equal(p.commentsLoaded,true);assert.equal(p.commentsError,true,'failure has retry state instead of empty comments');
 const q=subject();q.comments=[{rpid:9}];const list=q.comments;const slow=q.loadComments(true);const timeout=[...timers.values()][0];timeout();assert.equal(q.commentsLoading,false);assert.equal(q.commentsError,true);assert.equal(q.comments,list,'timeout retains visible comments');resolveRequest({comments:[{rpid:10}],nextCursor:0,isEnd:true});await slow;assert.equal(q.comments,list,'late result after timeout is discarded');
 console.log('PASS: compiled dynamic 412/cooldown/offline/exit policy, loading deadline, retry state and late-response rejection');
})().catch(e=>{console.error(e);process.exitCode=1;});
