const fs=require('node:fs');
const prefix=fs.readFileSync('scripts/test-comment-action-menu.cjs','utf8').split('const Menu=load(')[0];
const suite=`
const Editor=load('CommentInputBar');
for(const [width,count] of [[264,23],[360,23],[400,23],[800,120],[320,80]]) {
 const state={emoteGridWidth:width,currentEmoteList:()=>Array(count)};
 const cell=Editor.prototype.emoteCellWidth.call(state);
 const columns=Math.min(Math.max(1,Math.floor((width+6)/54)),Math.max(1,Math.ceil(count/4)));
 assert.ok(cell>=48);assert.ok(Math.abs(columns*cell+(columns-1)*6-width)<0.01,'visible columns fill width without a clipped last cell');
 if(count>columns*4)assert.ok(Math.ceil(count/4)*cell+(Math.ceil(count/4)-1)*6>width,'larger packages retain horizontal scrolling');
}
assert.equal(Editor.prototype.emoteCellWidth.call({emoteGridWidth:0}),48);
const pageSource=fs.readFileSync(base.replace('/components/','/pages/')+'VideoPlayerPage.ts','utf8');
const sourceFile=ts.createSourceFile('player.ts',pageSource,ts.ScriptTarget.Latest,true);
const pageClass=sourceFile.statements.find(n=>ts.isClassDeclaration(n)&&n.name?.text==='VideoPlayerPage');
function method(name){return pageClass.members.find(n=>n.name?.getText(sourceFile)===name).body.getText(sourceFile);}
let scrolling=false,materialInScroll=null,editorInScroll=null;
const env={...c,exports:{},__Common__:ui('Common'),
 NativeComposerSurface:class {constructor(_parent,params){Object.assign(this,params);materialInScroll=scrolling;}},
 Scroll:new Proxy({}, {get(_target,key){return (...args)=>{calls.push({name:'Scroll',key,args});if(key==='create')scrolling=true;if(key==='pop')scrolling=false;};}})};
const frameMethods=['commentComposerTargetWidth','commentComposerFrameWidth','commentComposerFrameHeight','commentComposerFrameX','commentComposerFrameY'];
const code='function render() '+method('ReferenceCommentComposer')+';function viewport() '+method('commentComposerViewportHeight')+';globalThis.render=render;globalThis.viewport=viewport;'+frameMethods.map(name=>'globalThis.'+name+'=function() '+method(name)+';').join('');
vm.runInNewContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,env);
const page={isLs:false,fs:false,cw:360,ch:800,danmakuKeyboardHeight:300,commentComposerHeight:612,commentComposerProgress:1,commentComposerOrigin:[10,740,340,40],
 referenceSafeTop:()=>20,observeComponentCreation2:fn=>fn(1,true),
 commentSheetContent:()=>{editorInScroll=scrolling;}};
page.commentComposerViewportHeight=()=>env.viewport.call(page);
for(const name of frameMethods)page[name]=()=>env[name].call(page);
calls=[];env.render.call(page);
assert.equal(materialInScroll,false,'native top rim stays outside the editor scroll viewport');
assert.equal(editorInScroll,true,'only editor content scrolls');
assert.equal(page.commentComposerViewportHeight(),480);
assert.ok(calls.some(x=>x.name==='Column'&&x.key==='height'&&x.args[0]===480),'material frame uses viewport height');
assert.ok(calls.some(x=>x.name==='Scroll'&&x.key==='height'&&x.args[0]===480));
console.log('Compiled emote/viewport regression: adaptive complete columns, horizontal overflow and fixed material outside scrolling content passed.');
`;
new Function('require',prefix+suite)(require);
