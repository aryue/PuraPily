const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function methods(file, names) {
  const source = fs.readFileSync(root + file, 'utf8');
  return names.map(name => {
    const start = source.indexOf('    private ' + name + '(');
    assert.ok(start >= 0, 'compiled method exists: ' + name);
    let pos = source.indexOf('{', start), depth = 1, end = pos + 1;
    for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
    return source.slice(start, end);
  }).join('\n');
}
function instance(body) {
  const code = ts.transpileModule('class Subject {' + body + '} globalThis.subject = new Subject();', {compilerOptions: {target: ts.ScriptTarget.ES2020}}).outputText;
  const context = {}; vm.runInNewContext(code, context); return context.subject;
}
const player = instance(methods('pages/VideoPlayerPage.ts', ['applyAcceptQuality','getQlList','getQlLabel']));
player.vi = {bvid:'BV-A',cid:1}; player.ql_ = [{qn:80,label:'1080P'},{qn:64,label:'720P'}]; player.aq = [];
assert.equal(player.getQlList().length,0, 'loading does not advertise fixed qualities');
player.applyAcceptQuality({url:'stream',actualQn:80,acceptQuality:[80,64,80,0],acceptDescription:['高清']});
assert.equal(JSON.stringify(player.getQlList()),JSON.stringify([{qn:80,label:'高清'},{qn:64,label:'720P'}]));
player.vi.cid = 2; assert.equal(player.getQlList().length,0, 'part change hides previous options');
// 画质目录按 cid 归属（bvid 可能只是详情补上的别名）：同 cid 换 bvid 沿用，换 cid 才清空。
player.vi = {bvid:'BV-B',cid:1}; assert.equal(player.getQlList().length,2, 'same cid keeps the catalog across bvid aliases');
player.vi = {bvid:'BV-B',cid:2}; assert.equal(player.getQlList().length,0, 'video change hides previous options');
player.applyAcceptQuality({url:'stream',actualQn:64}); assert.equal(player.getQlList().length,1);
assert.equal(player.getQlList()[0].qn,64, 'missing metadata offers only the actual returned quality');
player.applyAcceptQuality({url:'',actualQn:0}); assert.equal(player.getQlList().length,0, 'empty response clears old list');
const menu = instance(methods('components/ReferencePortraitSettings.ts',['optionLabels','currentOption','selectOption','onOpenChanged','playbackModeLabels','playbackModeLabel']));
menu.qualities = [{qn:64,label:'720P'}]; menu.quality = '720P'; menu.feedMode = false;
let selected = 0; menu.onQuality = n => selected = n;
menu.selectOption('quality',0); assert.equal(selected,64); assert.equal(menu.currentOption('quality'),'720P');
assert.equal(JSON.stringify(menu.optionLabels('quality')),JSON.stringify(['720P']));
// 播放模式：连刷三项、非连刷四项，列表循环只在非连刷出现（2026-11-11）
assert.equal(JSON.stringify(menu.optionLabels('mode')),JSON.stringify(['自动连播','列表循环','单集循环','播完暂停']));
menu.feedMode = true;
assert.equal(JSON.stringify(menu.optionLabels('mode')),JSON.stringify(['自动连播','单集循环','播完暂停']));
let mode = ''; menu.onMode = m => mode = m;
menu.selectOption('mode',0); assert.equal(mode,'continuous');
menu.mode = 'listLoop'; assert.equal(menu.currentOption('mode'),'自动连播','feed presents list loop as auto play');
menu.feedMode = false;
menu.selectOption('mode',1); assert.equal(mode,'listLoop');
menu.selectOption('mode',2); assert.equal(mode,'loop');
menu.selectOption('mode',3); assert.equal(mode,'single');
menu.mode = 'listLoop'; assert.equal(menu.currentOption('mode'),'列表循环');
let sleep = -1, stop = false; menu.onSleep = n => sleep = n; menu.onToggle = (k,v) => stop = v;
menu.selectOption('sleep',1); assert.equal(sleep,0); assert.equal(stop,true);
menu.selectOption('sleep',2); assert.equal(sleep,15); assert.equal(stop,false);
menu.selectOption('sleep',6); assert.equal(menu.customSleep,true); assert.equal(sleep,15);
menu.open = false; menu.choiceMenuVisible = true; menu.settingsPage = true;
menu.onOpenChanged(); assert.equal(menu.choiceMenuVisible,false, 'closing dismisses detached dropdown');
assert.equal(menu.settingsPage,true, 'outgoing settings content survives the slide out');
menu.open = true; menu.onOpenChanged();
assert.equal(menu.settingsPage,false, 'reopening the retained menu starts on its main page');
assert.equal(menu.customSleep,false);
console.log('PASS: compiled quality isolation, metadata fallback, dropdown quality mapping, playback mode sets (feed/non-feed) and sleep selection');
