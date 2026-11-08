const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/services/';
const PREFIX = 256 * 1024, SIZE = 2 * 1024 * 1024 + 8, TAIL = SIZE - PREFIX;
const tick = () => new Promise(resolve => setImmediate(resolve));
const data = (length, fill=7) => new Uint8Array(length).fill(fill).buffer;
function deferred() { let resolve,reject; const promise = new Promise((r,j) => { resolve=r;reject=j; }); return { promise, resolve,reject }; }
function load(name, imports, runtime = {}) {
  const context = { exports: {}, console: { info() {}, warn() {}, error() {} }, setTimeout, clearTimeout,
    ArrayBuffer, Uint8Array, require: id => imports(id), ...runtime };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(root+name+'.ts','utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}
class Request {
  constructor() { this.result=deferred(); this.destroyed=0; this.handlers={}; }
  request(url, options) { this.url=url; this.options=options; return this.result.promise; }
  requestInStream(url, options) { this.url=url; this.options=options; return this.result.promise; }
  on(event, callback) { this.handlers[event]=callback; }
  emit(event, value) { this.handlers[event]?.(value); }
  headers(range) {
    const [,start,end]=/bytes=(\d+)-(\d+)/.exec(this.options.header.Range);
    this.emit('headersReceive',{'Content-Range':range??`bytes ${start}-${end}/${+end+1}`});
  }
  body(buffer) { this.emit('dataReceive',buffer); }
  end(code=206) { this.emit('dataEnd'); this.result.resolve(code); }
  fail(code=2300028) { this.result.reject(Object.assign(new Error('network failure'),{code})); }
  destroy() { this.destroyed++; }
  reply(buffer, code=206) { if(code===206)this.headers(); this.body(buffer); this.end(code); }
}
const requests=[];
const http={ RequestMethod: { GET: 1 }, HttpDataType: { ARRAY_BUFFER: 1 },
  createHttp() { const r=new Request(); requests.push(r); return r; } };
const { DashRangeTransfer: Transfer } = load('DashRangeTransfer', id => {
  if (id.includes('net.http')) return { default: http };
  if (id.includes('PlaybackStartup')) return { PlaybackStartup: { trace() {}, span() { return null; } } };
  return {};
});
const { DashMediaServer: Server } = load('DashMediaServer', id => id.includes('DashRangeTransfer') ? { DashRangeTransfer: Transfer } : (id.includes('PlaybackStartup') ? { PlaybackStartup: { span() { return null; } } } : {}));
function server() {
  const s=new Server();
  const segments=[{ fileOffset:100, size:SIZE, duration:5000 },{ fileOffset:100+SIZE, size:SIZE, duration:5000 }];
  s.setConfig({ videoUrl:'video', audioUrl:'audio', mpdXml:'mpd', referer:'referer', userAgent:'agent', cookie:'must-not-send',
    videoSegments:segments, audioSegments:segments, videoTimescale:1000, audioTimescale:1000,
    videoFileSize:100+SIZE*2, audioFileSize:100+SIZE*2, videoInitSize:1, audioInitSize:1 });
  return s;
}
function client() {
  const sent=[], signal=deferred();
  const c={ closed:false, disconnected:signal.promise, markClosed() { c.closed=true; signal.resolve(null); },
    conn:{ async send({data}) { sent.push(data.slice(0)); structuredClone(data, { transfer:[data] }); }, async close() { c.markClosed(); } } };
  return { c, sent, text:() => Buffer.concat(sent.map(b=>Buffer.from(b))).toString('latin1') };
}
const req=(start=-1,end=-1,num=1)=>({method:'GET',path:`/video_seg_${num}.m4s`,rangeStart:start,rangeEnd:end});
(async()=>{
  {
    const s=server(),before=requests.length;
    const prefix=s.prefetchSegment(true,0,PREFIX);
    let wholeReady=false;
    const whole=s.prefetchSegment(true,0).then(ok=>{wholeReady=ok;return ok;});
    const [first,last]=requests.slice(before);
    first.reply(data(PREFIX,21));assert.equal(await prefix,true);
    assert.equal(wholeReady,false,'slow tail must not block publishing the native source');
    const a=client(),native=s.route(a.c,req());await tick();
    assert.equal(Buffer.concat(a.sent.slice(1).map(x=>Buffer.from(x))).length,PREFIX);
    assert.equal(requests.length,before+2,'prefetch and native demand share the in-flight slow tail');
    last.reply(data(TAIL,22));assert.equal(await whole,true);await native;
    assert.equal(Buffer.concat(a.sent.slice(1).map(x=>Buffer.from(x))).length,SIZE);
    await s.stop();
  }
  {
    const s=server(),before=requests.length;
    let ready=false;
    const waiting=s.prefetchSegment(true,0,PREFIX).then(ok=>{ready=ok;return ok;});
    const [first,last]=requests.slice(before);
    last.reply(data(TAIL,32));await tick();
    assert.equal(ready,false,'an out-of-order tail is not a contiguous startup prefix');
    first.body(data(65536,31));await tick();
    assert.equal(ready,false,'unvalidated response bytes cannot open startup');
    first.headers();await tick();
    assert.equal(ready,false,'64KiB alone does not satisfy the 256KiB prefix');
    first.body(data(PREFIX-65536,31));
    assert.equal(await waiting,true,'validated prefix unlocks preparation before response completion');
    const count=requests.length,a=client(),native=s.route(a.c,req());
    await tick();
    assert.equal(requests.length,count,'native demand adopts the same in-flight range');
    assert.ok(a.sent.length>1,'native receives prefix bytes without waiting for CDN dataEnd');
    first.end();await native;await s.stop();
  }
  {
    const s=server(),waiting=s.prefetchSegmentAtTime(true,6500,PREFIX);
    const r=requests.at(-2);
    assert.equal(r.options.header.Range,`bytes=${100+SIZE}-${100+SIZE+PREFIX-1}`);
    await s.stop();assert.equal(await waiting,false,'exit settles an awaited resume prefix');
  }
  {
    const before=requests.length,t=new Transfer('small-prefix',100,199);t.begin('','u');
    const waiting=t.waitForPrefix(PREFIX);
    requests[before].reply(data(100));assert.equal(await waiting,true,'short segments clamp to their actual end');
  }
  {
    const before=requests.length,t=new Transfer('bad-prefix',0,PREFIX-1);t.begin('','u');
    const waiting=t.waitForPrefix(PREFIX);
    requests[before].headers('bytes 1-262144/999999');
    assert.equal(await waiting,false,'invalid Content-Range fails startup, including pending readers');
  }
  {
    const s=server(),cfg=s.config,bytes=5*1024*1024;
    cfg.videoSegments=cfg.audioSegments=[{fileOffset:100,size:bytes,duration:5000}];
    cfg.videoFileSize=cfg.audioFileSize=100+bytes;s.setConfig(cfg);
    assert.equal(s.canRetainStartupSegments(0,true),true);
    s.cachePut(s.cacheKey('audio',100,99+bytes),data(bytes,2));
    s.cachePut(s.cacheKey('video',100,99+bytes),data(bytes,3));
    assert.equal(s.cache.size,2,'both startup tracks survive the ordinary 8MiB cache limit');
    const before=requests.length,a=client(),v=client();
    await s.route(a.c,{method:'GET',path:'/audio_seg_1.m4s',rangeStart:-1,rangeEnd:-1});
    await s.route(v.c,req());
    assert.equal(requests.length,before,'native consumes both prepared tracks without redownloading');
    assert.equal(s.startupPins.size,0,'startup retention ends after native delivery');
    assert.ok(s.cacheBytes<=8*1024*1024,'normal cache budget resumes');await s.stop();
  }
  {
    const s=server();assert.equal(s.canRetainStartupSegments(0),true);
    assert.equal(s.canRetainStartupSegments(6000),true,'startup ranges can share the 32MiB retention budget while pinned');
    const cfg=s.config;
    cfg.videoSegments=[{fileOffset:100,size:9*1024*1024,duration:5000}];cfg.videoFileSize=100+9*1024*1024;
    s.setConfig(cfg);assert.equal(s.canRetainStartupSegments(0),true,'large-segment retained storage can prime a 9MiB first segment');
    cfg.videoSegments[0].size=33*1024*1024;cfg.videoFileSize=100+33*1024*1024;s.setConfig(cfg);
    assert.equal(s.canRetainStartupSegments(0),false,'oversized startup must stream instead of exceeding retention budget');await s.stop();
  }
  {
    const s=server(),cfg=s.config;
    cfg.videoSegments=cfg.audioSegments=Array.from({length:5},(_,i)=>({fileOffset:100+i*100,size:100,duration:5000}));
    cfg.videoFileSize=cfg.audioFileSize=600;s.setConfig(cfg);
    const before=requests.length;s.refillForPlayback(0);
    const original=requests.slice(before);assert.equal(original.length,2);
    const a=client(),native=s.route(a.c,req());
    s.refillForPlayback(15000);await tick();
    assert.equal(original[0].destroyed,1,'seeking cancels obsolete speculative audio');
    assert.equal(original[1].destroyed,0,'a prefetch adopted by native demand must survive a seek');
    original[1].reply(data(100));await native;
    assert.equal(a.c.closed,false);await s.stop();
  }
  {
    const {DashCdnRoute:Route}=load('DashCdnRoute',id=>id.includes('net.http')?{default:http}:
      id.includes('PlaybackStartup')?{PlaybackStartup:{span:()=>null}}:{});
    const route=new Route('media',['alternate'],data(64,8),1048576,'','u',null);
    const before=requests.length,t=new Transfer('media',100,262243,'cdn-video',null,route);t.begin('','u');
    const first=requests[before];first.headers();first.body(data(65536,8));first.fail();await tick();
    const validation=requests[before+1];assert.equal(validation.url,'alternate');
    assert.equal(validation.options.header.Range,'bytes=0-63');
    validation.result.resolve({responseCode:206,result:data(64,8),header:{'Content-Range':'bytes 0-63/1048576'}});await tick();
    const retry=requests[before+2];assert.equal(retry.url,'alternate');
    const body=new Uint8Array(262144).fill(9);body.fill(8,0,65536);retry.reply(body.buffer);
    assert.equal(await t.completion,true);assert.equal(route.currentUrl,'alternate');
    const combined=new Uint8Array(t.collect(262144));assert.equal(combined[65535],8);assert.equal(combined[65536],9);
    route.cancel();
  }
  {
    const before=requests.length,route={currentUrl:'primary',async fallback(){return'alternate';}};
    const t=new Transfer('primary',0,1023,'cdn-video',null,route);t.begin('','u');
    requests[before].reply(data(128,99),403);await tick();
    assert.equal(requests[before+1].url,'alternate','an HTTP error body is not mistaken for valid media');
    requests[before+1].reply(data(1024,81));assert.equal(await t.completion,true);
    assert.ok(new Uint8Array(t.collect(1024)).every(x=>x===81));
  }
  {
    const s=server(),cfg=s.config;
    cfg.videoSegments=cfg.audioSegments=[{fileOffset:100,size:100,duration:5000}];
    cfg.videoFileSize=cfg.audioFileSize=200;s.setConfig(cfg);
    const before=requests.length;s.refillForPlayback(0);
    assert.equal(requests.length,before+2);requests[before].reply(data(0),503);requests[before+1].reply(data(100));await tick();
    const count=requests.length;s.lastRefillAt=-1000;s.refillForPlayback(0);
    assert.equal(requests.length,count,'failed speculative audio has a cooldown, not a retry every timer tick');
    const a=client(),job=s.route(a.c,{...req(),path:'/audio_seg_1.m4s'});
    assert.equal(requests.length,count+1,'native audio demand bypasses speculative cooldown');
    requests[count].reply(data(100));await job;await s.stop();
  }
  {
    const s=server(),cfg=s.config,before=requests.length;
    let endpoint='video',switches=0;
    cfg.videoRoute={get currentUrl(){return endpoint;},async fallback(failed){switches++;assert.equal(failed,'video');endpoint='alternate';return endpoint;},cancel(){}};
    const a=client(),job=s.route(a.c,req());const [first,last]=requests.slice(before);
    first.reply(data(PREFIX,71));last.headers();last.body(data(65536,72));await tick();last.fail();await tick();
    const retry=requests[before+2];assert.equal(retry.url,'alternate');
    assert.equal(retry.options.header.Range,`bytes=${100+PREFIX}-${100+SIZE-1}`);
    const resumed=new Uint8Array(TAIL).fill(73);resumed.fill(72,0,65536);
    retry.reply(resumed.buffer);await job;assert.equal(switches,1);
    const body=Buffer.concat(a.sent.slice(1).map(x=>Buffer.from(x)));
    assert.equal(body.length,SIZE);assert.equal(body[PREFIX],72);assert.equal(body[PREFIX+65536],73);
    assert.equal(a.c.closed,false,'node switch preserves the open native response');
    const count=requests.length;s.prefetchSegment(true,1);
    assert.equal(requests[count].url,'alternate','subsequent segments start on the validated healthy node');
    await s.stop();
  }
  {
    const s=server(),cfg=s.config,before=requests.length;
    cfg.videoRoute={currentUrl:'video',async fallback(){return'alternate';},cancel(){}};
    const a=client(),job=s.route(a.c,req()),[first,last]=requests.slice(before);
    first.reply(data(PREFIX,71));last.headers();last.body(data(65536,72));await tick();last.fail();await tick();
    requests[before+2].reply(data(TAIL,99));await job;
    assert.equal(a.c.closed,true,'a different overlap must never be concatenated with published primary bytes');
    assert.ok(a.sent.slice(1).every(x=>!new Uint8Array(x).includes(99)));
    await s.stop();
  }
  {
    const s=server(),cfg=s.config,size=100;
    cfg.videoSegments=cfg.audioSegments=Array.from({length:4},(_,i)=>({fileOffset:100+i*size,size,duration:5000}));
    cfg.videoFileSize=cfg.audioFileSize=500;s.setConfig(cfg);
    const complete=async from=>{for(const r of requests.slice(from)){const [,a,b]=/bytes=(\d+)-(\d+)/.exec(r.options.header.Range);r.reply(data(+b-+a+1));}await tick();};
    let from=requests.length;const v=s.prefetchSegment(true,0),a=s.prefetchSegment(false,0);await complete(from);await Promise.all([v,a]);
    from=requests.length;s.refillForPlayback(500);assert.equal(requests.length,from,'ample per-track coverage does not prefetch');
    s.lastRefillAt=-1000;s.refillForPlayback(2000);assert.equal(requests.length,from+2,'each low track gets exactly its next segment');
    s.lastRefillAt=-1000;s.refillForPlayback(2000);assert.equal(requests.length,from+2,'overlapping refill ticks share in-flight work');
    await complete(from);const count=requests.length;
    await s.route(client().c,req(-1,-1,2));assert.equal(requests.length,count,'native request consumes the prefetched video without another HTTP request');
    s.lastRefillAt=-1000;s.refillForPlayback(6000);assert.equal(requests.length,count,'four seconds of remaining coverage avoids unnecessary work');
    s.lastRefillAt=-1000;s.refillForPlayback(7000);assert.equal(requests.length,count+2);
    await complete(count);s.lastRefillAt=-1000;s.refillForPlayback(20000);
    assert.equal(requests.length,count+2,'end of stream never prefetches an invented segment');await s.stop();
  }
  {
    const s=server(),from=requests.length;s.cacheBytes=32*1024*1024;s.refillForPlayback(0);
    assert.equal(requests.length,from,'speculation respects retained plus in-flight byte budget');s.cacheBytes=0;
    const demand=s.prefetchSegment(true,0);s.lastRefillAt=-1000;s.refillForPlayback(0);
    assert.equal(requests.length,from+4,'existing video demand is not duplicated; only audio is added');
    await s.stop();assert.equal(await demand,false);
    s.refillForPlayback(0);assert.equal(requests.length,from+4,'stopped server starts no speculative work');
  }
  {
    let now=0,next=0;const timers=new Map();
    const clock={setTimeout(fn,ms){timers.set(++next,{fn,at:now+ms});return next;},clearTimeout(id){timers.delete(id);}};
    const advance=async ms=>{now+=ms;for(const [id,t] of [...timers])if(t.at<=now&&timers.delete(id))t.fn();await tick();};
    const {DashRangeTransfer:Timed}=load('DashRangeTransfer',id=>id.includes('net.http')?{default:http}:
      id.includes('PlaybackStartup')?{PlaybackStartup:{trace(){},span(){return null;}}}:{},clock);
    const before=requests.length,t=new Timed('stalled-body',0,262143);t.begin('r','u');
    const first=requests[before];first.headers();first.body(data(131072,61));
    await advance(3999);assert.equal(requests.length,before+1);
    await advance(1);assert.equal(requests.length,before+2,'idle request retries before the 15-second first-frame deadline');
    const retry=requests[before+1];assert.equal(retry.options.header.Range,'bytes=131072-262143');
    retry.reply(data(131072,62));assert.equal(await t.completion,true);await tick();
    assert.equal(first.destroyed,1);assert.equal(timers.size,0);
    const slowBefore=requests.length,slow=new Timed('slow-progress',0,131071);slow.begin('r','u');
    const r=requests[slowBefore];r.headers();
    for(let i=0;i<4;i++){await advance(3000);r.body(data(32768));}
    r.end();assert.equal(await slow.completion,true);assert.equal(requests.length,slowBefore+1,
      'ongoing progress is allowed even when total download time exceeds four seconds');
    await tick();assert.equal(timers.size,0);
    const cancelled=new Timed('cancel-idle',0,99);cancelled.begin('r','u');cancelled.cancel();
    assert.equal(await cancelled.completion,false);await tick();assert.equal(timers.size,0);
  }
  {
    const s=server(), a=client(), before=requests.length, job=s.route(a.c,req());
    const [first,last]=requests.slice(before);
    first.reply(data(PREFIX,41)); last.headers(); last.body(data(64*1024+123,42));
    await tick(); last.fail(); await tick();
    assert.equal(requests.length,before+3,'only the failed subrequest is retried');
    const retry=requests[before+2];
    assert.equal(retry.options.header.Range,`bytes=${100+PREFIX+64*1024}-${100+SIZE-1}`,
      'resume after validated published bytes; discard only the unpublished remainder');
    assert.equal(first.destroyed,1); assert.equal(a.c.closed,false,'transient failure keeps the native response open');
    // A destroyed request may still have queued callbacks; they cannot publish duplicates.
    last.body(data(500,99)); last.emit('dataEnd');
    retry.reply(data(TAIL-64*1024,43)); await job;
    const received=Buffer.concat(a.sent.slice(1).map(x=>Buffer.from(x)));
    assert.equal(received.length,SIZE); assert.equal(received[0],41);
    assert.equal(received[PREFIX],42); assert.equal(received[PREFIX+64*1024],43);
    assert.equal(a.c.closed,false); assert.equal((a.text().match(/HTTP\/1.1/g)||[]).length,1);
    await s.stop();
  }
  {
    const before=requests.length,t=new Transfer('retain-sibling',100,100+SIZE-1);t.begin('r','u');
    const [first,last]=requests.slice(before);last.reply(data(TAIL,52));first.fail();await tick();
    assert.equal(requests.length,before+3);requests[before+2].reply(data(PREFIX,51));
    assert.equal(await t.completion,true);assert.equal(new Uint8Array(t.collect(SIZE))[PREFIX],52,
      'a failed prefix does not discard a successful sibling');
  }
  {
    const before=requests.length,t=new Transfer('retry-exhausted',0,65535);t.begin('r','u');
    requests[before].fail();await tick();requests[before+1].fail();
    assert.equal(await t.completion,false);assert.equal(requests.length,before+2,'one retry per subrequest');
  }
  {
    const before=requests.length,t=new Transfer('cancel-retry',0,65535);t.begin('r','u');
    requests[before].fail();await tick();const retry=requests[before+1];t.cancel();
    retry.fail();await tick();assert.equal(await t.completion,false);
    assert.equal(requests.length,before+2,'cancellation does not start another request');
  }
  {
    const s=server(), before=requests.length;
    let ready=false;
    const waiting=s.prefetchSegment(false,0).then(ok=>{ready=ok;return ok;});
    const [first,last]=requests.slice(before);
    first.reply(data(PREFIX,31)); await tick();
    assert.equal(ready,false,'startup waits for the complete validated audio segment');
    last.reply(data(TAIL,32)); assert.equal(await waiting,true); await tick();
    const count=requests.length,a=client();
    await s.route(a.c,{...req(),path:'/audio_seg_1.m4s'});
    assert.equal(requests.length,count,'native startup receives prepared audio without another CDN request');
    assert.equal(a.sent[1].byteLength,SIZE); await s.stop();
  }
  {
    const s=server(),waiting=s.prefetchSegmentAtTime(false,20000);
    await s.stop(); assert.equal(await waiting,false,'cancellation settles an awaited resume audio transfer');
  }
  {
    const before=requests.length;
    const t=new Transfer('app-media',100,100+SIZE-1); t.begin('','App-media-UA');
    const [first,last]=requests.slice(before);
    assert.equal(first.options.header['User-Agent'],'App-media-UA');
    assert.equal('Referer' in first.options.header,false);
    assert.equal('Origin' in first.options.header,false);
    assert.equal('Cookie' in first.options.header,false);
    first.reply(data(PREFIX)); last.reply(data(TAIL)); assert.equal(await t.completion,true);
  }
  {
    const before=requests.length;
    const t=new Transfer('media',100,100+SIZE-1); t.begin('referer','agent');
    const [first,last]=requests.slice(before); const read=t.read(100,100+SIZE-1);
    assert.equal(first.options.header.Range,`bytes=100-${100+PREFIX-1}`);
    first.reply(data(PREFIX,1)); assert.equal((await read).byteLength,64*1024);
    let finished=false; t.completion.then(()=>{finished=true;}); await tick();
    assert.equal(finished,false,'prefix is available while later blocks are still downloading');
    last.reply(data(TAIL,2)); assert.equal(await t.completion,true);
    assert.equal(t.collect(SIZE).byteLength,SIZE); assert.equal(t.collect(SIZE-1),null);
    assert.equal(new Uint8Array(t.collect(SIZE))[PREFIX],2);
    assert.equal(first.destroyed,1); assert.equal(last.destroyed,1);
  }
  {
    const s=server(), before=requests.length; s.prefetchSegment(true,0);
    const [first,last]=requests.slice(before), count=requests.length;
    const a=client(),b=client(); const job=s.route(a.c,req()),partial=s.route(b.c,req(2,5));
    assert.equal(requests.length,count,'normal and subrange readers share prefetch');
    first.reply(data(PREFIX,10)); await tick();
    assert.match(a.text(),new RegExp(`Content-Length: ${SIZE}\\r\\n`)); assert.ok(a.sent.length>=2);
    assert.match(b.text(),/206 Partial Content/); assert.match(b.text(),new RegExp(`Content-Range: bytes 2-5/${SIZE}`));
    assert.equal(last.destroyed,0,'TCP delivery starts before the last CDN block completes');
    last.reply(data(TAIL,11)); await Promise.all([job,partial]);
    const again=client(); await s.route(again.c,req()); assert.equal(requests.length,count,'completed segment is cached');
    assert.equal(Buffer.from(again.sent[1]).byteLength,SIZE); await s.stop();
  }
  {
    const s=server(),a=client(),before=requests.length; const job=s.route(a.c,req());
    const [first,last]=requests.slice(before); first.reply(data(PREFIX)); await tick();
    last.reply(data(2)); await job;
    assert.equal(a.c.closed,true,'incomplete response closes the connection');
    assert.equal((a.text().match(/HTTP\/1.1/g)||[]).length,1,'never append an HTTP error after a partial body'); await s.stop();
  }
  {
    const s=server(),a=client(),before=requests.length; const job=s.route(a.c,req());
    requests[before].reply(data(0),503); await tick();
    const retry=requests.slice(before+2); assert.equal(retry.length,2);
    retry[0].reply(data(PREFIX)); retry[1].reply(data(TAIL)); await job;
    assert.match(a.text(),/200 OK/); assert.equal((a.text().match(/HTTP\/1.1/g)||[]).length,1);
    assert.equal(requests[before+1].destroyed,1); await s.stop();
  }
  {
    const s=server(),a=client(),before=requests.length; const job=s.route(a.c,req());
    requests[before].reply(data(0),503); await tick();
    requests[before+2].reply(data(0),503); await job;
    assert.match(a.text(),/502 Bad Gateway/); assert.equal(requests.length,before+4,'retry is bounded'); await s.stop();
  }
  {
    const before=requests.length,t=new Transfer('cancel',100,100+SIZE-1); t.begin('r','u');
    const read=t.read(100,100+SIZE-1); t.cancel();
    assert.equal(await read,null); assert.equal(await t.completion,false);
    for(const r of requests.slice(before)) assert.equal(r.destroyed,1);
    // Native request promises intentionally never settle after destroy.
  }
  {
    const s=server(),a=client(),before=requests.length; const job=s.route(a.c,req()); await s.stop(); await job;
    for(const r of requests.slice(before)) assert.equal(r.destroyed,1);
    assert.equal(s.cache.size,0);
  }
  {
    const before=requests.length,t=new Transfer('reverse',100,100+SIZE-1); t.begin('r','u');
    const [first,last]=requests.slice(before); let prefixReady=false;
    const read=t.read(100,100+SIZE-1).then(buffer=>{prefixReady=true;return buffer;});
    last.reply(data(TAIL,2)); await tick(); assert.equal(prefixReady,false,'tail finishing first must not leak out of order');
    first.reply(data(PREFIX,1)); await read; assert.equal(await t.completion,true);
    const combined=new Uint8Array(t.collect(SIZE)); assert.equal(combined[0],1); assert.equal(combined[PREFIX],2);
  }
  {
    const s=server(),before=requests.length; s.prefetchSegmentAtTime(true,6500);
    assert.equal(requests.length,before+2); assert.equal(requests[before].options.header.Range,`bytes=${100+SIZE}-${100+SIZE+PREFIX-1}`);
    const a=client(); await s.route(a.c,req(SIZE,SIZE+2)); assert.match(a.text(),/416 Range Not Satisfiable/); await s.stop();
  }
  {
    const before=requests.length,t=new Transfer('large',0,10*1024*1024); t.begin('r','u');
    assert.equal(requests.length-before,4,'limit parallel requests per transfer');
    for(const r of requests.slice(before)) { const [,start,end]=/bytes=(\d+)-(\d+)/.exec(r.options.header.Range); assert.ok(+end-+start+1<=2*1024*1024); }
    t.cancel();
  }
  {
    const before=requests.length,t=new Transfer('normal',0,1024*1024-1); t.begin('r','u');
    assert.equal(requests.length,before+1,'normal segments avoid an extra HTTP round trip'); t.cancel();
  }
  {
    const length=1024*1024, before=requests.length, t=new Transfer('stream',100,100+length-1);
    t.begin('r','u'); const r=requests[before]; r.headers();
    let settled=false; t.completion.then(()=>{settled=true;});
    let ready=false; const first=t.read(100,100+length-1).then(x=>{ready=true;return x;});
    const nativeBuffer=data(32*1024,19); r.body(nativeBuffer); await tick();
    assert.equal(ready,false,'batch small native fragments before socket delivery');
    r.body(data(32*1024,20)); const block=await first;
    assert.equal(block.byteLength,64*1024);
    new Uint8Array(nativeBuffer).fill(99);
    assert.equal(new Uint8Array(block)[0],19,'copy native event data before its lifetime ends');
    assert.equal(new Uint8Array(block)[32*1024],20);
    assert.equal(settled,false,'normal 1MB request must deliver before CDN response completion');
    r.body(data(length-64*1024,21)); r.end(); assert.equal(await t.completion,true);
    assert.equal(new Uint8Array(t.collect(length))[length-1],21);
  }
  {
    const s=server(), a=client(), before=requests.length, job=s.route(a.c,req());
    const first=requests[before],last=requests[before+1]; first.headers(); first.body(data(64*1024));
    await tick(); assert.ok(a.sent.length>=2,'real TCP route starts during the first CDN request');
    assert.equal(first.destroyed,0,'first CDN response has not completed at first socket send');
    first.body(data(PREFIX-64*1024)); first.end(); last.reply(data(TAIL)); await job; await s.stop();
  }
  {
    const before=requests.length,t=new Transfer('wrong-range',100,199); t.begin('r','u');
    const r=requests[before], read=t.read(100,199); r.headers('bytes 0-99/1000'); r.body(data(100)); r.end();
    assert.equal(await read,null); assert.equal(await t.completion,false,'reject incorrect absolute offsets');
    assert.equal(t.collect(100),null);
  }
  {
    const before=requests.length,t=new Transfer('ignored-range',0,65535); t.begin('r','u');
    const r=requests[before]; let ready=false; const read=t.read(0,65535).then(x=>{ready=true;return x;});
    r.emit('headersReceive',{'Content-Length':'65536'}); r.body(data(65536)); await tick();
    assert.equal(ready,false,'do not forward unverified HTTP 200 bodies'); r.end(200);
    assert.equal(await read,null); assert.equal(await t.completion,false);
  }
  {
    const before=requests.length,t=new Transfer('omitted-header',0,65535); t.begin('r','u');
    const r=requests[before]; let ready=false; const read=t.read(0,65535).then(x=>{ready=true;return x;});
    r.body(data(65536)); await tick(); assert.equal(ready,false);
    r.end(206); assert.equal((await read).byteLength,65536); assert.equal(await t.completion,true);
  }
  {
    const before=requests.length,t=new Transfer('overflow',0,65535); t.begin('r','u');
    const r=requests[before]; r.headers(); r.body(data(65537)); r.end();
    assert.equal(await t.completion,false,'oversized stream cannot enter range cache');
  }
  {
    const s=server(), cfg=s.config, largeSize=9*1024*1024;
    cfg.videoSegments=[{fileOffset:100,size:largeSize,duration:5000}];cfg.videoFileSize=100+largeSize;
    const before=requests.length;s.prefetchSegment(true,0);
    const transfer=[...s.inflight.values()][0];
    let handled=before;
    while(handled<requests.length){
      const r=requests[handled++], [,start,end]=/bytes=(\d+)-(\d+)/.exec(r.options.header.Range);
      r.reply(data(+end-+start+1));await tick();
    }
    assert.equal(await transfer.completion,true);await tick();
    assert.equal(s.completed.size,1,'a 9MB 4K/HDR segment survives the 8MB small-buffer limit');
    const count=requests.length,a=client();await s.route(a.c,req(100,199));
    assert.equal(requests.length,count,'native re-read must reuse the completed segment without CDN traffic');
    assert.match(a.text(),/206 Partial Content/);
    assert.ok(s.completedBytes+s.cacheBytes<=32*1024*1024,'combined retained memory remains bounded');
    await s.stop();assert.equal(s.completed.size,0);assert.equal(s.completedBytes,0);
  }
  for(const r of requests) assert.equal(r.options.header.Cookie,undefined,'media requests contain no login cookies');
  console.log('PASS: compiled in-response streaming, 64KB batching/ownership, header/range validation, ordered ranges, cache sharing, failure/retry/cancel and bounded concurrency');
})().catch(error=>{console.error(error);process.exitCode=1;});
