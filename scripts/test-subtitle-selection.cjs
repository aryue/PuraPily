const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/VideoPlayerPage.ts','utf8');
const start = source.indexOf('    private async referenceSelectSubtitle(');
assert.ok(start >= 0);
let pos = source.indexOf('{',start), depth = 1, end = pos + 1;
for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
const pending = [];
const ctx = { http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({ request: () => new Promise(resolve => pending.push(resolve)), destroy() {} }) }, logWarn() {} };
vm.runInNewContext(ts.transpileModule('class Subject {'+source.slice(start,end)+'} globalThis.s = new Subject();', { compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,ctx);
const s=ctx.s; let closed=0;
Object.assign(s,{referenceSubtitleSelectionRequest:0, referenceSubtitleTrackUrls:['track-a','track-b'],vi:{bvid:'BV-test',cid:1},referenceAlive:true,
  closeLandscapeSubtitlePanel:()=>closed++,getUIContext:()=>({getPromptAction:()=>({showToast(){}})})});
const response = {responseCode:200,result:JSON.stringify({body:[{from:0,to:3,content:'subtitle'}]})};
(async()=>{
  const first=s.referenceSelectSubtitle(0,false); pending.shift()(response); await first;
  assert.equal(s.referenceSubtitleEnabled,true);assert.equal(s.referenceSelectedSubtitleIndex,0);assert.equal(closed,0,'portrait selection preserves its menu host');
  const older=s.referenceSelectSubtitle(1,false); await s.referenceSelectSubtitle(-1,false);
  pending.shift()(response); await older;
  assert.equal(s.referenceSubtitleEnabled,false,'late response cannot re-enable closed subtitles');assert.equal(s.referenceSelectedSubtitleIndex,-1);
  const changed=s.referenceSelectSubtitle(0,false);s.vi.cid=2;pending.shift()(response);await changed;
  assert.equal(s.referenceSubtitleEnabled,false,'another part rejects old cues');
  const bottom=s.referenceSelectSubtitle(1);pending.shift()(response);await bottom;
  assert.equal(s.referenceSelectedSubtitleIndex,1);assert.equal(closed,1,'bottom retains its existing completion path');
  console.log('PASS: compiled shared subtitle selection, portrait host lifetime and stale/off/part isolation');
})().catch(error=>{console.error(error);process.exitCode=1;});
