const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('entry/src/main/ets/api/BilibiliApi.ets', 'utf8');
const start = source.indexOf('function normalizeSpaceVideoData(');
const end = source.indexOf('\n/**', start);
const fn = source.slice(start, end)
  .replace('data: UpSpaceVideoData): UpSpaceVideoData', 'data)')
  .replace('(item: UpSpaceVideoItem): UpSpaceVideoItem', '(item)')
  .replace(' as UpSpaceRawVideoItem', '');
const normalize = vm.runInNewContext('(' + fn.trim() + ')');
function video(fields) {
  return normalize({ list: { vlist: [{ aid: 1, bvid: 'BV1', title: 'title', pic: 'cover', ...fields }] }, page: { count: 1 } }).list.vlist[0];
}
const web = video({ length: '01:24', created: 1791388800, video_review: 12, play: 4957 });
assert.equal(web.duration, 84);
assert.equal(web.pubdate, 1791388800);
assert.equal(web.danmaku, 12);
assert.equal(video({ length: '1:02:03' }).duration, 3723);
const numeric = video({ duration: 9, length: '00:30', pubdate: 100, created: 200, danmaku: 0, video_review: 3 });
assert.equal(numeric.duration, 9);
assert.equal(numeric.pubdate, 100);
assert.equal(numeric.danmaku, 0);
assert.equal(video({}).duration, 0);
assert.equal(video({ length: 'invalid' }).duration, 0);
assert.equal(video({ length: '-1:03' }).duration, 0);
assert.ok(source.includes('retryResult = normalizeSpaceVideoData(retryData.data)'));
console.log('Space video normalization passed: web duration, hours, date, danmaku, numeric precedence, missing/malformed data, retry path.');
const headerStart = source.indexOf('export function resolveSpaceHeaderImage(');
const headerEnd = source.indexOf('\n/**', headerStart);
const headerFn = source.slice(headerStart, headerEnd)
  .replace('export function', 'function')
  .replace('images: UpSpaceImages | null, dark: boolean, webPhoto: string): string', 'images, dark, webPhoto)');
const headerImage = vm.runInNewContext('(' + headerFn.trim() + ')');
const images = { imgUrl: 'https://example.com/day.jpg', night_imgurl: 'https://example.com/night.jpg' };
assert.equal(headerImage(images, false, 'web'), images.imgUrl);
assert.equal(headerImage(images, true, 'web'), images.night_imgurl);
assert.equal(headerImage({ imgUrl: images.imgUrl }, true, 'web'), images.imgUrl);
assert.equal(headerImage({ night_imgurl: images.night_imgurl }, false, 'web'), images.night_imgurl);
assert.equal(headerImage(null, true, 'http://example.com/web.jpg'), 'https://example.com/web.jpg');
assert.equal(headerImage({ imgUrl: ' //example.com/day.jpg ' }, false, ''), 'https://example.com/day.jpg');
assert.equal(headerImage({ imgUrl: '', night_imgurl: ' ' }, true, ''), '');
const defaultBackground = JSON.parse(fs.readFileSync('scripts/fixtures/up-space-profile.json', 'utf8'))[0].images;
for (const dark of [false, true]) {
  assert.equal(headerImage(defaultBackground, dark, ''), '', 'API default backgrounds must leave the header transparent');
  assert.equal(headerImage(defaultBackground, dark, images.imgUrl), '', 'explicit App defaults must not fall back to stale Web headers');
  assert.equal(headerImage(null, dark, defaultBackground.imgUrl + '@800w'), '', 'Web fallback must also reject resized default backgrounds');
}
assert.equal(headerImage({ ...defaultBackground, night_imgurl: images.night_imgurl }, false, ''), images.night_imgurl);
assert.equal(headerImage(null, false, 'bfs/space/custom.png'), 'https://i0.hdslb.com/bfs/space/custom.png');
console.log('Space background selection passed: day/night, missing variant, Web fallback, URL normalization, empty response.');
const mergeStart = source.indexOf('export function mergeUpSpaceProfile(');
const mergeEnd = source.indexOf('\n/**', mergeStart);
const mergeFn = source.slice(mergeStart, mergeEnd).replace('export function', 'function')
  .replace('mid: number, webInfo: UpSpaceInfo | null,', 'mid, webInfo,')
  .replace('webRelation: UpRelationStat | null, webCard: CardData | null, app: UpAppSpaceData | null): UpSpaceInitData', 'webRelation, webCard, app)')
  .replaceAll('(tag: UpAppSpaceTag)', '(tag)');
const mergeProfile = vm.runInNewContext('(' + mergeFn.trim() + ')');
const fixturePath = 'scripts/fixtures/up-space-profile.json';
for (const fixture of JSON.parse(fs.readFileSync(fixturePath, 'utf8'))) {
  const profile = mergeProfile(Number(fixture.card.mid), null, null, null, fixture);
  assert.equal(profile.relation.follower, fixture.card.fans);
  assert.equal(profile.relation.following, fixture.card.attention);
  assert.equal(profile.likes, fixture.card.likes.like_num);
  assert.equal(profile.info.name, fixture.card.name);
}
const webInfo = { name: 'Web name', ip_location: 'IP属地：湖北', is_followed: 1 };
const webStats = { follower: 8, following: 9 };
const appProfile = mergeProfile(1, webInfo, webStats, { like_num: 30, following: true }, {
  card: { name: 'App name', fans: 0, attention: 0, likes: { like_num: 0 },
    space_tag: [{ type: 'school', title: '学校' }, { type: 'location', title: 'IP属地：广东' }], relation: { is_follow: 0 } }
});
assert.equal(appProfile.relation.follower, 0);
assert.equal(appProfile.relation.following, 0);
assert.equal(appProfile.likes, 0);
assert.equal(appProfile.info.ip_location, 'IP属地：广东');
assert.equal(appProfile.isFollowed, false);
const webFallback = mergeProfile(1, webInfo, webStats, { like_num: 30, following: true }, null);
assert.equal(webFallback.info.ip_location, 'IP属地：湖北');
assert.equal(webFallback.relation.follower, 8);
assert.equal(webFallback.likes, 30);
assert.equal(webFallback.isFollowed, true);
assert.equal(mergeProfile(1, null, null, null, null).likes, null);
console.log('Space profile merge passed: real App fixtures, all counters, zero values, location tag, follow state and Web fallback.');
