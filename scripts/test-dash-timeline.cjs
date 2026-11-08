const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/';
function load(name, imports={}) {
  const c={exports:{},console:{info(){},warn(){},error(){}},require:id=>
    Object.entries(imports).find(([key])=>id.includes(key))?.[1]||{}};
  const code=ts.transpileModule(fs.readFileSync(root+name+'.ts','utf8'),{
    compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
  vm.runInNewContext(code,c); return c.exports;
}
const u32=n=>{const b=Buffer.alloc(4);b.writeUInt32BE(n);return b;};
const box=(type,...parts)=>{const body=Buffer.concat(parts);return Buffer.concat([u32(body.length+8),Buffer.from(type),body]);};
function media(version=0,earliest=0) {
  const mdhd=Buffer.alloc(20);mdhd.writeUInt32BE(90000,12);
  const moov=box('moov',box('trak',box('mdia',box('mdhd',mdhd))));
  const durations=[6000,3000,1000],count=Buffer.from([0,0,0,3]);
  const time=version===0?Buffer.concat([u32(earliest),u32(10)]):Buffer.concat([u32(1),u32(earliest),u32(0),u32(10)]);
  const sidx=box('sidx',Buffer.from([version,0,0,0]),u32(1),u32(1000),time,count,
    ...durations.map(d=>Buffer.concat([u32(100),u32(d),u32(0x90000000)])));
  const result=Buffer.concat([box('ftyp'),moov,sidx,Buffer.alloc(310)]);
  return {buffer:result.buffer.slice(result.byteOffset,result.byteOffset+result.byteLength),
    firstOffset:8+moov.length+sidx.length+10,durations};
}
(async()=>{
  let payload=media();
  const {probeM4sInitSegment:probe}=load('DashProbe',{
    'net.http':{default:{RequestMethod:{GET:1},HttpDataType:{ARRAY_BUFFER:1},createHttp(){return{
      async request(){return{responseCode:200,result:payload.buffer,header:{'content-length':String(payload.buffer.byteLength)}};},destroy(){}};}}},
    PlaybackStartup:{PlaybackStartup:{span:()=>null}}
  });
  const info=await probe('media','','','');
  assert.equal(info.timescale,1000,'sidx durations must use sidx timebase, not mdhd=90000');
  assert.deepEqual(Array.from(info.segments,x=>x.duration),[6000,3000,1000]);
  assert.deepEqual(Array.from(info.segments,x=>x.startTime),[0,6000,9000]);
  assert.equal(info.segments[0].fileOffset,payload.firstOffset);
  payload=media(1,123);const v1=await probe('media','','','');
  assert.equal(v1.segments[0].startTime,4294967296+123,'version-one presentation timestamps retain high bits');
  const mpd=load('DashMpdBuilder');
  const params={durationMs:10000,videoStreams:[{id:120,codecid:7,bandwidth:100,width:1920,height:1080,frameRate:'30',sar:'1:1'}],
    audioStreams:[{id:1,bandwidth:1}],videoTimescale:1000,audioTimescale:48000,
    videoSegmentDuration:6000,audioSegmentDuration:240000,videoSegmentDurations:[6000,3000,1000],
    audioSegmentDurations:[240000,240000]};
  const xml=mpd.buildSegmentTemplateMpd(params),templates=[...xml.matchAll(/<SegmentTemplate\b([^>]*)>(.*?)<\/SegmentTemplate>/g)];
  assert.equal(templates.length,2);assert.ok(!templates[0][1].includes('duration='));
  const video=[...templates[0][2].matchAll(/<S\b[^>]*d="(\d+)"/g)].map(m=>+m[1]);
  assert.deepEqual(video,[6000,3000,1000],'all three indexed segments remain addressable; fixed 6000ms would request only two');
  assert.equal(video.reduce((a,b)=>a+b,0),10000);
  const longDurations=[5000,...Array(158).fill(4900),5357];
  assert.equal(longDurations.reduce((a,b)=>a+b,0),784557);
  const long=mpd.buildSegmentTemplateMpd({...params,durationMs:784557,videoSegmentDurations:longDurations});
  const longVideo=long.match(/<SegmentTimeline>(.*?)<\/SegmentTimeline>/)[1];
  assert.equal([...longVideo.matchAll(/<S\b/g)].length,160,
    'a 784.557-second irregular track keeps all 160 video segments; fixed 5s requests only 157');
  assert.equal(mpd.askSegmentCount(784557,1000,5000),157);
  const tail=mpd.buildSegmentTemplateMpd({...params,durationMs:75007,videoSegmentDurations:[...Array(14).fill(5000),5007]});
  assert.equal([...tail.matchAll(/<S\b[^>]*d="/g)].length,17,'15 real video segments plus two audio segments, with no invented tail');
  const fallback=mpd.buildSegmentTemplateMpd({...params,videoSegmentDurations:[6000,0]});
  assert.match(fallback,/timescale="1000" duration="6000"/);
  console.log('PASS: compiled sidx timebase/v0/v1 timestamps, variable GOP timeline, complete short tail and legacy fallback');
})().catch(e=>{console.error(e);process.exitCode=1;});
