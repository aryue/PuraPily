// 4K 症状链回归：native 报 duration=0 时，UI 时长/进度条/seek 不能被拖垮，
// 且 cache.c 不能把有界 Range 的长度当成整条流的长度。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT ||
  'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const root = path.resolve(__dirname, '..');
const player = fs.readFileSync(path.join(root, 'entry/src/main/ets/services/IjkPlaybackPlayer.ets'), 'utf8');
const cache = fs.readFileSync(path.join(root, 'scripts/ijk-dual-lab/cache.c'), 'utf8');

function block(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, 'missing ' + signature);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error('unterminated ' + signature);
}

function cBody(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, 'missing ' + signature);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error('unterminated ' + signature);
}

// ---- native: total must be authoritative, never capped at a Range length ----
const ensureNet = cBody(cache, 'static AVIOContext *ensure_net(');
const fetchBlock = cBody(cache, 'static int fetch_block(');
const readDirect = cBody(cache, 'static int read_uncached_direct(');
const loadIndex = cBody(cache, 'static void load_index(');
const cacheOpen = cBody(cache, 'AVIOContext *purapily_cache_open(');

assert.match(ensureNet, /size > 0 && \(ctx->total <= 0 \|\| size != ctx->total\)/,
  'the live response must invalidate stale totals whether the media grew or shrank');
assert.match(ensureNet, /memset\(ctx->lens, 0,/,
  'blocks truncated against the old total must be invalidated');
assert.match(loadIndex, /extent > ctx->total/,
  'an index whose cached bytes exceed its stored total must be discarded');
assert.match(cacheOpen, /if \(hint > 0\) \{ ctx->total = hint;/,
  'a pending/failed prewarm must never set total to 0 or -1');
assert.match(fetchBlock, /if \(want <= 0\) \{[\s\S]*ensure_net\(ctx, start\)/,
  'reaching a stored EOF must re-check against the network before declaring EOF');
assert.match(fetchBlock, /room<=0\) break;/, 'a negative avio_read size must be impossible');
assert.match(readDirect, /remaining = ctx->net_end - ctx->net_pos/,
  'the EOF clamp must use the connection position, not the logical seek position');
assert.match(readDirect, /if \(remaining <= 0\) return AVERROR_EOF;/);

// ---- ArkTS: duration/seek/currentTime behaviour ----
const getter = block(player, 'get currentTime(): number {');
const seek = block(player, 'seek(position: number');
const case200 = block(player, 'case 200: {');
const caseBody = case200.slice(case200.indexOf('{') + 1, case200.lastIndexOf('}'))
  .replace(/\bbreak;/, '')
  .replace(/const nativeDuration = native\.controlPlayer\(this\.handle, 7, 0\);/, '');

function run(source, imports) {
  const context = vm.createContext(Object.assign({ exports: {} }, imports));
  vm.runInContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
  return context.exports;
}

let reportedDuration = 0;
let reportedPosition = 0;
const seeks = [];
const warnings = [];
const { PlayerProbe } = run(`
export class PlayerProbe {
  handle = 1; state = 'playing'; position = 0; total = 0; metadataDuration = 0;
  rate = 1; volume = 1; width = 0; height = 0;
  events = { emit() {} };
  preparedResolve: any = null; preparedReject: any = null;
  constructor(meta: number) { this.metadataDuration = meta; this.total = meta; }
  changeState() {}
  get duration(): number { return this.total; }
  ${getter}
  ${seek}
  applyPrepared(d: number) {
    const nativeDuration = d;
    ${caseBody}
  }
}`, {
  media: {},
  native: {
    controlPlayer: (_handle, op, arg) => {
      if (op === 7) return reportedDuration;
      if (op === 6) return reportedPosition;
      if (op === 3) seeks.push(arg);
      return 0;
    }
  },
  logWarn: msg => warnings.push(msg),
  logInfo() {}
});

const metadataMs = 10 * 60 * 1000; // playurl timelength: 10 minutes

// 1. A healthy native duration wins.
reportedDuration = 600500;
const good = new PlayerProbe(metadataMs);
good.applyPrepared(reportedDuration);
assert.equal(good.duration, 600500, 'a valid container duration should be used');
assert.equal(warnings.length, 0);

// 2. duration=0 (4K fMP4) must fall back to timelength, not wipe the progress bar.
reportedDuration = 0;
const fallback = new PlayerProbe(metadataMs);
fallback.applyPrepared(0);
assert.equal(fallback.total, metadataMs, 'native 0 must not clobber dash.timelength');
assert.equal(warnings.length, 1, 'the fallback must be logged');

// 3. Even if total somehow ends up 0, a seek must never be clamped back to 0.
const broken = new PlayerProbe(0);
seeks.length = 0;
broken.seek(125000);
assert.equal(seeks[0], 125000, 'an unknown duration must not collapse every seek to 0');
assert.equal(broken.position, 125000);
const healthy = new PlayerProbe(metadataMs);
seeks.length = 0;
healthy.seek(999999999);
assert.equal(seeks[0], metadataMs - 1, 'a known duration still bounds the seek');

// 4. Report the actual clock rather than freezing at a previous/future timestamp.
reportedPosition = 42000;
const clock = new PlayerProbe(metadataMs);
clock.state = 'playing';
assert.equal(clock.currentTime, 42000);
reportedPosition = 0;
assert.equal(clock.currentTime, 0, 'clock corrections must not be hidden by a monotonic clamp');
reportedPosition = 9400;
clock.seek(10000);
assert.equal(clock.currentTime, 9400, 'show the actual landing point rather than freezing until the target is reached');
reportedPosition = 11000;
assert.equal(clock.currentTime, 11000, 'forward progress still advances normally');

console.log('Playback duration/seek: timelength fallback, no zero clamp, actual clock, authoritative total passed.');
