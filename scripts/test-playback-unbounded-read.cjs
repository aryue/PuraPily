const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const cache = fs.readFileSync(path.join(root, 'scripts/ijk-dual-lab/cache.c'), 'utf8');
const prewarm = fs.readFileSync(path.join(root, 'scripts/ijk-dual-lab/prewarm.c'), 'utf8');

function body(source, signature) {
  const start = source.indexOf(signature);
  assert.ok(start >= 0, 'missing ' + signature);
  const end = source.indexOf('\n}', start);
  assert.ok(end > start, 'unterminated ' + signature);
  return source.slice(start, end + 2);
}

const openSource = body(cache, 'static AVIOContext *open_source(');
const ensureNet = body(cache, 'static AVIOContext *ensure_net(');
const cacheOpen = body(cache, 'AVIOContext *purapily_cache_open(');
const cacheSeek = body(cache, 'static int64_t cache_seek(');

// 1. Playback reads never get an end_offset: one Range serves until EOF or the next seek.
assert.match(openSource, /av_dict_set_int\(&options, "offset", offset, 0\)/);
assert.ok(!cache.includes('"end_offset"'), 'playback reads must not set a Range ceiling');
assert.match(ensureNet, /ctx->net_end = ctx->total > 0 \? ctx->total : INT64_MAX/,
  'a sequential read must keep reusing the same connection to EOF');
assert.match(ensureNet, /if \(ctx->net && offset >= ctx->net_pos && offset < ctx->net_end\) return ctx->net;/,
  'sequential reads must not reopen a connection');

// 2. The demuxer requests the length on the same connection used for reads.
assert.match(cacheSeek, /ctx->total < 0 && \(whence == AVSEEK_SIZE/);
assert.match(cacheSeek, /ensure_net\(ctx, ctx->pos\)/);
assert.doesNotMatch(cacheOpen, /ensure_net\(|open_source\(/,
  'allocating the cache must not start an idle full-response GET');

// 3. Speculative prewarming keeps its byte budget; only playback is unbounded.
assert.match(prewarm, /#define LIMIT \(512 \* 1024\)/);
assert.ok(!prewarm.includes('WINDOW_BYTES') && !prewarm.includes('WINDOW_US'),
  'user removed the rolling 30 second quota');
assert.match(prewarm, /int want = len - rel;/, 'the worker reads only the remaining slice');
assert.match(prewarm, /bytes > LIMIT/);
assert.match(prewarm, /"recv_buffer_size", "262144"/, 'idle sockets keep a bounded receive window');

console.log('Playback reads continuous; rolling prefix quota removed, per-request boundary retained.');
