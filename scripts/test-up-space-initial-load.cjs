const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/UpSpacePage.ts';
const ast=ts.createSourceFile(path,fs.readFileSync(path,'utf8'),ts.ScriptTarget.Latest,true);
const cls=ast.statements.find(n=>ts.isClassDeclaration(n)&&n.name.text==='UpSpacePage');
const method=cls.members.find(n=>ts.isMethodDeclaration(n)&&n.name.getText(ast)==='loadAllData').getText(ast);
const c={exports:{},Curve:{EaseOut:0}};vm.runInNewContext(ts.transpileModule(`export class Subject {${method}}`,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,c);
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {resolve,promise};};
function page(){const p=new c.exports.Subject(),profile=deferred(),list=deferred();let commits=0;Object.assign(p,{mid:1,isPageActive:true,initialSpaceReady:false,spaceInfo:null,loadError:'',loadProfileData:async()=>{await profile.promise;p.spaceInfo={name:'real',sign:'actual'};p.isFollowed=true;},loadVideos:async()=>{await list.promise;p.videos=[{bvid:'BV1'}];},getUIContext:()=>({animateTo:(_o,f)=>{commits++;f();}})});return {p,profile,list,commits:()=>commits};}
(async()=>{
 const a=page(),pending=a.p.loadAllData();assert.equal(a.p.initialSpaceReady,false);a.profile.resolve();await new Promise(setImmediate);assert.equal(a.p.initialSpaceReady,false,'profile alone must not reveal a partial page');a.list.resolve();await pending;assert.equal(a.p.initialSpaceReady,true);assert.equal(a.p.isFollowed,true);assert.equal(a.commits(),1);
 a.p.loadProfileData=async()=>{};a.p.loadVideos=async()=>{};await a.p.loadAllData();assert.equal(a.commits(),1,'refresh retains the existing content tree');
 const b=page(),abandoned=b.p.loadAllData();b.p.isPageActive=false;b.profile.resolve();b.list.resolve();await abandoned;assert.equal(b.p.initialSpaceReady,false,'late loads cannot reveal a page after leaving');
 const e=page();e.p.loadProfileData=async()=>{};e.p.loadVideos=async()=>{};await e.p.loadAllData();assert.equal(e.p.initialSpaceReady,false,'failed profile never exposes the default false follow state');assert.match(e.p.loadError,/重试/);
 console.log('PASS compiled space initial render: atomic profile/list reveal, real follow state, retained refresh tree, early back and retryable failure.');
})().catch(e=>{console.error(e);process.exitCode=1;});
