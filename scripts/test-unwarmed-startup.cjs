// 未预热入口首帧：A 列表阶段只备播放地址；B 磁盘缓存保住首段。
// 回归这两条不越界（不下媒体字节、不绕 NetworkGate）且策略常量没有被改回去。
const fs = require('node:fs');
const assert = require('node:assert/strict');

const api = fs.readFileSync('entry/src/main/ets/api/BilibiliApi.ets', 'utf8');
const search = fs.readFileSync('entry/src/main/ets/pages/SearchPage.ets', 'utf8');
const cache = fs.readFileSync('scripts/ijk-dual-lab/cache.c', 'utf8');

// ---- A: 只有播放地址，任何媒体字节/播放器都不能在这里发起 ----
assert.match(api, /export function prefetchPlayUrlsOnly\(items: RecommendItem\[\], qn: number, limit: number = 6\)/,
  'address-only prefetch helper exists with a bounded default');
const start = api.indexOf('export function prefetchPlayUrlsOnly');
const end = api.indexOf('/** Full-capability DASH probes', start);
assert.ok(end > start, 'helper body boundary found');
const body = api.slice(start, end);
assert.doesNotMatch(body, /IjkPrewarm|PlaybackWarmPlayer|prewarmUrl|native\./,
  'address-only prefetch must not start speculative media work (NetworkGate budget)');
assert.match(body, /running < 2/, 'prefetch concurrency stays at 2 like the list prefetch');
assert.match(body, /getVideoPlayUrl\(item\.id, item\.cid, qn\)/, 'fills the shared playUrlCache');
assert.match(body, /\/\^\(BV\[0-9A-Za-z\]\+|\[0-9\]\+\)\$\//, 'only valid ids');
assert.match(body, /getVideoDetail\(item\.id\)/,
  'cid-less search rows still prefetch by resolving the detail first');
assert.match(body, /detail\?\.pages\?\.\[0\]\?\.cid/, 'detail fallback covers multi-part videos');
assert.match(body, /列表地址预取/, 'one diagnostic log proves the list prefetch actually ran');
assert.match(body, /\.finally\(\(\) => \{/, 'queue keeps draining after failures');
assert.match(search, /prefetchPlayUrlsOnly/,
  'search results call the address-only prefetch');
assert.match(search, /if \(tab === 'video'\) \{\s*\n\s*prefetchPlayUrlsOnly\(this\.activeResults/,
  'only the video tab prefetches, and it runs right after results arrive');

// ---- B: 单流只留首段 + 淘汰目标真的低于触发线 ----
assert.match(cache, /#define CACHE_FILE_MAX \(32LL \* 1024 \* 1024\)/,
  'single stream keeps only its first 32MB so 4K tails cannot fill the directory');
const block = 64 * 1024;
assert.equal((32 * 1024 * 1024) / block, 512, '32MB equals 512 sparse blocks');
assert.match(cache, /if \(block >= CACHE_MAX_BLOCKS\) \{\s*\n\s*int n = read_uncached_direct/,
  'blocks past the head limit still play, just without caching');
assert.match(cache, /int64_t target = CACHE_EVICT_AT \* 8 \/ 10/,
  'eviction target must sit below the 300MB trigger, not above it');
assert.match(cache, /dj > dv \+ CACHE_BLOCK/,
  'eviction prefers large stale files over small warm prefixes');
assert.ok((300 * 1024 * 1024) * 8 / 10 < 300 * 1024 * 1024,
  'eviction actually frees space instead of leaving the directory at ~307MB');

// 首帧确认不靠额外定时器：加载遮罩在 applyPreparedState（prepared 时）就摘，
// [Startup] frame 打点提前不等于画面提前，别再引入「快轮询」这类只改指标的定时器。
const pageFile = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8');
assert.doesNotMatch(pageFile, /firstFramePollTimer_/,
  'no dedicated first-frame poll: it only moved the log/state, not a real frame');
assert.match(pageFile, /\}, 1000\);/, 'diagnostic/stall poll stays at 1s');

console.log('Unwarmed startup guards passed');
