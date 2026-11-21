const assert = require('node:assert/strict');
const fs = require('node:fs');

const page = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8');
const service = fs.readFileSync('entry/src/main/ets/services/PlaybackRelatedVideos.ets', 'utf8');

// 纵向揭开简介面板时，相关推荐尚未回填必须用骨架占位，不能整块空白。
assert.match(page, /@State private relatedLoading: boolean = false;/,
  'related recommendation loading state must exist');
assert.match(page, /private async fetchRelatedVideos\([\s\S]{0,800}?this\.relatedLoading = true;/,
  'related fetch must mark loading before awaiting network');
assert.match(page, /this\.relatedVideos = videos;[\s\S]{0,160}?this\.relatedLoading = false;/,
  'related fetch must clear loading after applying items');
assert.match(page, /if \(this\.relatedLoading && this\.relatedVideos\.length === 0\)[\s\S]{0,600}?VideoListItem\(\{[\s\S]{0,140}?loading: true/,
  'the introspection list must render loading skeletons while related cards are pending');

// 相关推荐独立于取流：不能进入预取/播放地址链路，只在详情返回后异步填充。
assert.ok(!/prefetchVideoPlayback\([^)]*related/i.test(service),
  'related videos must not touch the playback prefetch path');
assert.match(service, /private static cache: Map<string, RelatedVideoCacheEntry>/,
  'related videos must be cached across page instances');
assert.match(service, /private static inflight: Map<string, Promise<RecommendItem\[\] \| null>>/,
  'concurrent related requests must be deduplicated');

console.log('PASS: related video skeleton and cache are present without touching playback fetch.');
