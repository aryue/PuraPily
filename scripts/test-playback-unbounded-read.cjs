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

const openNet = body(cache, 'static AVIOContext *open_net(');
const ensureNet = body(cache, 'static AVIOContext *ensure_net(');
const probe = body(cache, 'static int64_t probe_total(');
const cacheOpen = body(cache, 'AVIOContext *purapily_cache_open(');

// 1. Playback reads never get an end_offset: one Range serves until EOF or the next seek.
assert.match(openNet, /if \(end > offset\) av_dict_set_int\(&options, "end_offset", end, 0\);/,
  'only explicitly bounded opens may set end_offset');
assert.match(ensureNet, /open_net\(ctx, offset, 0\)/, 'playback reads must request an unbounded Range');
assert.ok(!ensureNet.includes('end_offset'), 'playback reads must not set a Range ceiling');
assert.ok(!ensureNet.includes('offset + 1024 * 1024'), 'the old 1 MiB per-connection ceiling is gone');
assert.match(ensureNet, /ctx->net_end = ctx->total > 0 \? ctx->total : INT64_MAX/,
  'a sequential read must keep reusing the same connection to EOF');
assert.match(ensureNet, /if \(ctx->net && offset >= ctx->net_pos && offset < ctx->net_end\) return ctx->net;/,
  'sequential reads must not reopen a connection');

// 2. The only bounded request left is the length probe, and it must not leave an idle socket.
assert.match(probe, /open_net\(ctx, 0, 1024 \* 1024\)/, 'length probe stays bounded at 1 MiB');
assert.match(probe, /avio_closep\(&pb\)/, 'probe connection must be closed immediately');
assert.match(cacheOpen, /probe_total\(ctx\)/, 'cache_open probes for the length');
assert.ok(!cacheOpen.includes('ensure_net(ctx, 0)'),
  'cache_open must not keep an idle full-response GET alive (the 95MB regression)');

// 3. Speculative prewarming keeps its byte budget; only playback is unbounded.
assert.match(prewarm, /#define LIMIT \(512 \* 1024\)/);
assert.ok(!prewarm.includes('WINDOW_BYTES') && !prewarm.includes('WINDOW_US'),
  'user removed the rolling 30 second quota');
assert.match(prewarm, /"end_offset", j->limit/, 'each request must still stop at its prefix boundary');

// 4. Quantify the fix: a 4K stream needs ~4MB/s, so the old 1 MiB ceiling forced ~4 reconnects/sec.
const MiB = 1024 * 1024;
const oldReconnectsPerSecond = Math.ceil((4 * MiB) / MiB);
assert.equal(oldReconnectsPerSecond, 4);
assert.ok(!cache.includes('int64_t end = offset + 1024 * 1024;'),
  'the per-read ceiling must not reappear anywhere in cache.c');
const boundedOpens = (cache.match(/open_net\(ctx, [^,]*, 1024 \* 1024\)/g) || []).length;
assert.equal(boundedOpens, 1, 'exactly one bounded open remains, and it is the length probe');

console.log('Playback reads continuous; rolling prefix quota removed, per-request boundary retained.');
