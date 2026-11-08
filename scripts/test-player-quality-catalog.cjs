const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
function extract(file, signature) {
  const source = fs.readFileSync(root + file, 'utf8'), start = source.indexOf(signature);
  assert.ok(start >= 0, signature);
  let end = source.indexOf('{', start) + 1, depth = 1;
  for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(start, end);
}
const code = extract('api/BilibiliApi.ts', 'async function getVideoPlayUrlRaw(');
const empty = {durlUrl:'', dashVideoUrl:'', dashAudioUrl:'', actualQn:0, acceptQuality:[], acceptDescription:[], dashInfo:null};
const catalog = [125,120,116,80,64,32,16];
const full = {...empty, dashVideoUrl:'video', dashAudioUrl:'audio', actualQn:80,
  acceptQuality:catalog, acceptDescription:['HDR','4K','1080P60','1080P','720P','480P','360P']};
const compile = s => ts.transpileModule(s,{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
const ctx = { setTimeout, clearTimeout, logInfo(){}, logWarn(){}, logError(){}, normalizeFetchDashQuality:x=>x };
vm.runInNewContext(compile(extract('utils/PlaybackRequests.ts', 'function firstPreferredResults<') + '\n' + code),ctx);
async function main() {
  let requests = [];
  ctx.tryFetchPlayUrlMobile = ctx.tryFetchPlayUrl = async (_b,_c,qn,fnval) => {
    requests.push({qn,fnval}); assert.equal(fnval,3536,'primary probes must include HDR/4K without merged-stream bit');
    return {...full,actualQn:qn};
  };
  for (const qn of [80,120,125]) {
    const result = await ctx.getVideoPlayUrlRaw('BVfixture',1,qn,{});
    assert.equal(result.actualQn,qn); assert.equal(result.audioUrl,'audio');
    assert.equal(JSON.stringify(result.acceptQuality),JSON.stringify(catalog));
  }
  assert.equal(requests.length,6,'only two full-capability probes per request');
  // Wait for a better pending route when the first response is downgraded.
  let resolve, complete=false;
  ctx.tryFetchPlayUrlMobile = async()=>({...full,actualQn:64});
  ctx.tryFetchPlayUrl = ()=>new Promise(r=>resolve=r);
  const pending=ctx.getVideoPlayUrlRaw('BVfixture',2,125,{}).then(r=>{complete=true;return r;});
  await new Promise(r=>setImmediate(r)); assert.equal(complete,false);
  resolve({...full,actualQn:125}); assert.equal((await pending).actualQn,125);
  // Compare both downgraded routes instead of letting the mobile result hide a better web stream.
  ctx.tryFetchPlayUrl = async()=>({...full,actualQn:80});
  assert.equal((await ctx.getVideoPlayUrlRaw('BVfixture',3,125,{})).actualQn,80);
  // A missing audio track must use the merged fallback without losing the full catalogue.
  ctx.tryFetchPlayUrlMobile = async()=>({...full,dashAudioUrl:''});
  ctx.tryFetchPlayUrl = async(_b,_c,_qn,fnval)=>fnval===1 ? {...empty,durlUrl:'merged',actualQn:64,acceptQuality:[64,16]} : empty;
  const fallback=await ctx.getVideoPlayUrlRaw('BVfixture',4,125,{});
  assert.equal(fallback.url,'merged'); assert.equal(fallback.actualQn,64);
  assert.equal(JSON.stringify(fallback.acceptQuality),JSON.stringify(catalog));
  // Inspect the real compiled web request, rather than testing a duplicate parameter object.
  let parameters;
  const web={PlaybackStartup:{span:()=>null},AppSign:{generateWebParams:async p=>{parameters=p;return ''; }},
    logInfo(){},logWarn(){},logError(){},getCookieHeader:()=>'',http:{RequestMethod:{GET:0},createHttp:()=>({
      request:async()=>({responseCode:200,result:JSON.stringify({code:0,data:{quality:80,accept_quality:catalog}})}),destroy(){}})}};
  vm.runInNewContext(compile(extract('api/BilibiliApi.ts','async function tryFetchPlayUrl(')),web);
  await web.tryFetchPlayUrl('BVfixture',1,125,3536);
  assert.equal(parameters.platform,'pc'); assert.equal(parameters.fourk,'1'); assert.equal(parameters.fnval,'3536');
  const selection={exports:{}};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'utils/DashQuality.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText,selection);
  let checkedMime='';
  const codec={exports:{},require:name=>name.includes('DashQuality') ? selection.exports :
    {default:{hasVideoDecoder:mime=>{checkedMime=mime;return mime==='video/avc';}}}};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+'services/PlaybackCodecSupport.ts','utf8'),{
    compilerOptions:{target:ts.ScriptTarget.ES2020,module:ts.ModuleKind.CommonJS}}).outputText,codec);
  const canDecode=codec.exports.canDecodePlayUrl;
  assert.equal(canDecode({url:'legacy'}),true);
  assert.equal(canDecode({actualQn:125,dash:{quality:125,videoStreams:[{id:125,codecid:12}]}}),false);
  assert.equal(checkedMime,'video/hevc');
  assert.equal(canDecode({actualQn:120,dash:{quality:120,videoStreams:[{id:125,codecid:12},{id:120,codecid:7}]}}),true);
  assert.equal(checkedMime,'video/avc','capability matches the selected rendition, not the highest track');
  const cached={url:'hdr',actualQn:125,acceptQuality:catalog,audioUrl:'audio',dash:{quality:125,
    videoStreams:[{id:125,codecid:12,baseUrl:'hdr'},{id:120,codecid:7,baseUrl:'4k'}],audioStreams:[],timelength:1000}};
  const local=codec.exports.selectDecodablePlayUrl(cached);
  assert.equal(local.url,'4k');assert.equal(local.actualQn,120);assert.equal(local.dash.quality,120);
  assert.equal(local.audioUrl,'audio');assert.equal(JSON.stringify(local.acceptQuality),JSON.stringify(catalog));
  assert.equal(cached.url,'hdr');assert.equal(cached.dash.quality,125,'device fallback must not mutate shared cached sources');
  console.log('PASS: compiled HDR/4K catalogue, full-capability request race, highest fallback, audio preservation and PC platform');
}
main().catch(e=>{console.error(e);process.exitCode=1;});
