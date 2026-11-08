const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const ts=require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const path='entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts';
const src=fs.readFileSync(path,'utf8'),sf=ts.createSourceFile(path,src,ts.ScriptTarget.Latest,true);
const cls=sf.statements.find(n=>ts.isClassDeclaration(n)&&n.name?.text==='VideoPlayerPage');
const names=['commentComposerViewportHeight','commentComposerTargetWidth','commentComposerFrameWidth','commentComposerFrameHeight','commentComposerFrameX','commentComposerFrameY','captureCommentComposerOrigin','animateCommentComposer','closeCommentComposer','backCommentComposer','onDanmakuKeyboardHeight','focusDanmakuComposer','onOverlayBack_'];
const members=names.map(name=>{
 if(name==='onDanmakuKeyboardHeight') {
  const ctor=cls.members.find(ts.isConstructorDeclaration);
  const assignment=ctor.body.statements.find(n=>ts.isExpressionStatement(n)&&ts.isBinaryExpression(n.expression)&&n.expression.left.getText(sf)==='this.'+name);
  assert.ok(assignment,name);return name+'='+assignment.expression.right.getText(sf)+';';
 }
 const member=cls.members.find(n=>n.name?.getText(sf)===name);assert.ok(member,name);return member.getText(sf);
});
const animations=[],timers=[],focusRequests=[];let cleared=0;
const context={Animator:{create(options){const a={options,cancel(){this.cancelled=true;},play(){}};animations.push(a);return a;}},setTimeout(fn){timers.push(fn);return timers.length;},clearTimeout(){}};
vm.runInNewContext(ts.transpileModule('class Harness {'+members.join('\n')+'}\nglobalThis.Harness=Harness;', {compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
const p=new context.Harness();Object.assign(p,{cw:360,ch:800,isLs:false,fs:false,navIndicatorHeight:20,commentComposerHeight:184,
 commentComposerProgress:0,commentSheetVisible:true,commentComposerClosing:false,danmakuKeyboardHeight:0,
 referenceSafeTop:()=>20,cmSheetEmoteCtrl:{collapseEmote:()=>false},
 getUIContext:()=>({px2vp:x=>x/2,getFocusController:()=>({clearFocus(){cleared++;},requestFocus(id){focusRequests.push(id);}}),getComponentUtils:()=>({getRectangleById:id=>id==='floating-comment-entry'?{windowOffset:{x:40,y:1500},size:{width:680,height:80}}:{windowOffset:{x:20,y:40}}})})});
p.captureCommentComposerOrigin('new');
assert.deepEqual(Array.from(p.commentComposerOrigin),[10,730,340,40],'source is converted from px and relative to the actual page origin');
assert.equal(p.commentComposerFrameY(),730);assert.equal(p.commentComposerFrameHeight(),40);
p.animateCommentComposer(1);let a=animations.at(-1);a.onframe(.5);
assert.equal(p.commentComposerFrameWidth(),350);assert.equal(p.commentComposerFrameHeight(),112);assert.equal(p.commentComposerFrameY(),673);
a.onfinish();assert.equal(p.commentComposerProgress,1);assert.equal(p.commentComposerFrameY(),616);
p.onDanmakuKeyboardHeight(600);a=animations.at(-1);
assert.equal(p.danmakuKeyboardHeight,0,'keyboard event does not jump the panel to final height');
a.onframe(.5);assert.equal(p.danmakuKeyboardHeight,150);assert.equal(p.commentComposerFrameY(),466);
p.onDanmakuKeyboardHeight(0);assert.ok(a.cancelled,'reversed keyboard motion cancels stale animation');
a=animations.at(-1);a.onframe(.5);assert.equal(p.danmakuKeyboardHeight,75);a.onfinish();assert.equal(p.commentComposerFrameY(),616);
p.danmakuKeyboardHeight=300;p.backCommentComposer();assert.equal(cleared,1);assert.equal(p.commentSheetVisible,true,'first back hides keyboard and keeps the editor');
p.danmakuKeyboardHeight=0;p.backCommentComposer();a=animations.at(-1);assert.equal(p.commentSheetVisible,true,'editor remains mounted during closing');
const count=animations.length;p.closeCommentComposer();assert.equal(animations.length,count,'duplicate close is ignored');
a.onframe(.5);assert.equal(p.commentComposerFrameHeight(),112);assert.equal(p.commentSheetVisible,true);
a.onfinish();assert.equal(p.commentSheetVisible,false);assert.equal(p.commentComposerProgress,0);
p.isLs=true;p.referenceLandscapeViewportWidth=()=>500;p.referenceLandscapePlayerX=()=>100;p.captureCommentComposerOrigin('reply');p.commentComposerProgress=1;
assert.equal(p.commentComposerFrameX(),100);assert.equal(p.commentComposerFrameWidth(),500,'landscape morph stays in player viewport');
Object.assign(p,{commentComposerProgress:0,commentSheetVisible:true,commentComposerClosing:false,commentComposerAnimator:null,danmakuKeyboardHeight:0});
const previous=animations.length;p.onDanmakuKeyboardHeight(600);
assert.equal(animations.length,previous+2,'keyboard starts capsule expansion and lift in the same event');
assert.equal(animations.at(-2).options.duration,300);assert.equal(animations.at(-1).options.duration,260);
animations.at(-2).onframe(.5);animations.at(-1).onframe(.5);
assert.equal(p.commentComposerProgress,.5);assert.equal(p.danmakuKeyboardHeight,150);
p.showDanmakuSheet=true;p.referenceAlive=true;p.focusDanmakuComposer();
assert.equal(focusRequests.length,0,'focus waits for the sheet window');p.showDanmakuSheet=false;timers.shift()();
assert.equal(focusRequests.length,0,'closing before delayed focus cannot reopen keyboard');
p.showDanmakuSheet=true;p.focusDanmakuComposer();timers.shift()();assert.deepEqual(focusRequests,['danmaku_text_input']);
p.commentSheetVisible=false;p.dmSheetEmoteCtrl={collapseEmote:()=>false};p.onOverlayBack_();
assert.equal(p.showDanmakuSheet,false,'overlay Back dismisses the unified danmaku panel before leaving the player');
console.log('Compiled composer motion: measured origin, intermediate geometry, keyboard reversal, staged Back, deferred close and landscape bounds passed.');
