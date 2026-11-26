const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

const modelSource = read('entry/src/main/ets/model/RecommendFilterModel.ets');
const serviceSource = read('entry/src/main/ets/services/RecommendFilterService.ets');
const settingsSource = read('entry/src/main/ets/services/RecommendFilterSettings.ets');
const apiSource = read('entry/src/main/ets/api/BilibiliApi.ets');
const appApiSource = read('entry/src/main/ets/api/RecommendApiOptimized.ets');
const regionSource = read('entry/src/main/ets/api/RegionApi.ets');
const searchSource = read('entry/src/main/ets/pages/SearchPage.ets');
const profileSource = read('entry/src/main/ets/pages/ProfilePage.ets');
const sectionSource = read('entry/src/main/ets/pages/SettingsSectionPage.ets');
const filterPageSource = read('entry/src/main/ets/pages/ContentFilterPage.ets');

assert.match(modelSource, /blockedMids\.has\(item\.ownerMid\)/);
assert.ok(modelSource.indexOf('if (isBlocked(item, config))') < modelSource.indexOf('if (whitelisted)'),
  'explicit block must be evaluated before whitelist');
assert.match(modelSource, /scene === RecommendFilterScene\.Rank && pgc/);
assert.match(modelSource, /PGC 标题关键词命中/);
assert.match(modelSource, /config\.removeUnplayable/);
assert.match(modelSource, /item\.playKnown/);
assert.match(modelSource, /item\.likeKnown/);
assert.match(modelSource, /item\.isFollowed && config\.exemptFollowed/);
assert.match(modelSource, /evaluateSearchResult/);
assert.match(modelSource, /kind === 'bili_user' \? item\.ownerName : item\.title/);

assert.match(serviceSource, /static filterList/);
assert.match(serviceSource, /filterSearchResults/);
assert.match(settingsSource, /rcmdFilterTitleKeywords/);
assert.match(settingsSource, /rcmdFilterWhitelistUsers/);
assert.match(settingsSource, /compileKeywordRules/);
assert.match(settingsSource, /cachedRevision/);

assert.match(apiSource, /RecommendFilterScene\.HomeWeb/);
assert.match(apiSource, /RecommendFilterScene\.Hot/);
assert.match(apiSource, /RecommendFilterScene\.Related/);
assert.match(appApiSource, /RecommendFilterScene\.HomeApp/);
assert.match(regionSource, /RecommendFilterScene\.Rank/);
assert.match(searchSource, /filterSearchResults\(rawItems, tab/);

assert.match(profileSource, /内容过滤/);
assert.match(sectionSource, /ContentFilterPage\(\)/);
assert.match(filterPageSource, /titleKeywordCount/);
assert.match(filterPageSource, /currentNumberValue/);
assert.match(filterPageSource, /编辑|保存/);

const js = ts.transpileModule(modelSource, {
  compilerOptions: {
    module: ts.ModuleKind.CommonJS,
    target: ts.ScriptTarget.ES2020
  }
}).outputText;
const context = { exports: {}, RegExp, Set, Array, String, Number };
vm.runInNewContext(js, context);
const {
  RecommendFilterConfig,
  RecommendFilterScene,
  compileKeywordRules,
  invalidKeywordLineCount,
  evaluateRecommendItem,
  evaluateSearchResult
} = context.exports;

function item(overrides = {}) {
  return Object.assign({
    id: 'BV1test',
    title: '普通标题',
    ownerName: '普通UP',
    ownerMid: '100',
    tname: '动画',
    duration: 300,
    durationKnown: true,
    playCount: 10000,
    playKnown: true,
    likeCount: 400,
    likeKnown: true,
    isFollowed: false,
    canPlay: 1,
    pgcSeasonId: 0,
    pgcEpId: 0
  }, overrides);
}

function config(overrides = {}) {
  const cfg = new RecommendFilterConfig();
  cfg.enabled = true;
  cfg.exemptFollowed = true;
  cfg.applyRelated = true;
  cfg.applyHot = false;
  cfg.applyRank = false;
  cfg.applySearch = false;
  return Object.assign(cfg, overrides);
}

function drop(scene, overrides = {}, cfg = config()) {
  return evaluateRecommendItem(item(overrides), scene, cfg);
}

let d = drop(RecommendFilterScene.HomeApp, {}, config({
  blockedMids: new Set(['100']),
  whitelistMids: new Set(['100'])
}));
assert.equal(d.drop, true, 'whitelisted+blocked should stay blocked before whitelist');
assert.equal(d.reason, '推荐屏蔽用户');

let cfg = config({
  blockedMids: new Set(['100']),
  whitelistMids: new Set(['999'])
});
d = drop(RecommendFilterScene.HomeApp, { isFollowed: true }, cfg);
assert.equal(d.drop, true, 'explicit block must beat followed exemption');

cfg = config({
  titleRules: compileKeywordRules('广告'),
  whitelistMids: new Set(['100'])
});
d = drop(RecommendFilterScene.HomeApp, { title: '广告标题', duration: 10 }, cfg);
assert.equal(d.drop, false, 'whitelist bypasses keyword and duration');

cfg = config({ titleRules: compileKeywordRules('广告') });
d = drop(RecommendFilterScene.HomeWeb, { isFollowed: true, title: '广告标题' }, cfg);
assert.equal(d.drop, false, 'home feed followed item is exempted');
d = drop(RecommendFilterScene.Related, { isFollowed: true, title: '广告标题' }, cfg);
assert.equal(d.drop, true, 'related videos have no followed metadata');

cfg = config({ minDuration: 60, minPlay: 1000, minLikeRatio: 2 });
d = drop(RecommendFilterScene.HomeWeb, { duration: 30 }, cfg);
assert.equal(d.reason, '时长达不到下限');
d = drop(RecommendFilterScene.HomeWeb, { playCount: 500 }, cfg);
assert.equal(d.reason, '播放量达不到下限');
d = drop(RecommendFilterScene.HomeWeb, { playCount: 10000, likeCount: 100 }, cfg);
assert.equal(d.reason, '点赞率达不到下限');
d = drop(RecommendFilterScene.HomeWeb, { playKnown: false, likeKnown: false, playCount: 0, likeCount: 0 }, cfg);
assert.equal(d.drop, false, 'unknown play/like fields must not be treated as zero');
d = drop(RecommendFilterScene.HomeWeb, { duration: 0 }, cfg);
assert.equal(d.drop, false, 'unknown duration 0 must not be filtered');

cfg = config({ zoneRules: compileKeywordRules('动画'), applyHot: false });
d = drop(RecommendFilterScene.Hot, { title: '普通标题', likeCount: 400 }, cfg);
assert.equal(d.drop, true, 'zone keyword applies to hot even with full filter off');
d = drop(RecommendFilterScene.Hot, { title: '普通标题' }, config({
  blockedMids: new Set(['100']),
  applyHot: false
}));
assert.equal(d.drop, false, 'local block belongs to full filter and is off until hot filter is enabled');
d = drop(RecommendFilterScene.Hot, { title: '普通标题' }, config({
  blockedMids: new Set(['100']),
  applyHot: true
}));
assert.equal(d.drop, true, 'local block applies once hot full filter is enabled');
d = drop(RecommendFilterScene.Hot, { title: '普通标题' }, config({
  zoneRules: compileKeywordRules('动画'),
  whitelistMids: new Set(['100'])
}));
assert.equal(d.drop, false, 'whitelist bypasses zone keyword');

cfg = config({ applyRank: true, titleRules: compileKeywordRules('广告'), minDuration: 60 });
d = drop(RecommendFilterScene.Rank, {
  id: 'ss123', pgcSeasonId: 123, title: '广告番剧', duration: 5
}, cfg);
assert.equal(d.drop, true, 'PGC rank filters title only');
d = drop(RecommendFilterScene.Rank, {
  id: 'ss123', pgcSeasonId: 123, title: '正常番剧', duration: 5
}, cfg);
assert.equal(d.drop, false, 'PGC rank must not apply duration');

d = drop(RecommendFilterScene.HomeApp, { canPlay: 0 }, config({ removeUnplayable: true }));
assert.equal(d.reason, '无权查看');
d = drop(RecommendFilterScene.HomeWeb, { canPlay: 0 }, config({ removeUnplayable: true }));
assert.equal(d.drop, false, 'unplayable switch is App-feed only');
d = drop(RecommendFilterScene.HomeApp, { canPlay: 0 }, config({
  removeUnplayable: true,
  whitelistMids: new Set(['100'])
}));
assert.equal(d.drop, false, 'whitelist bypasses unplayable check');

cfg = config({ titleRules: compileKeywordRules('测试') });
d = drop(RecommendFilterScene.Related, { title: '测试标题' }, cfg);
assert.equal(d.drop, true);
cfg.applyRelated = false;
d = drop(RecommendFilterScene.Related, { title: '测试标题' }, cfg);
assert.equal(d.drop, false, 'related switch disables full rules');

const rules = compileKeywordRules('广告\n[非法正则');
assert.equal(rules.length, 1, 'invalid line is skipped without killing valid lines');
assert.equal(keywordMatch(rules, '广告标题'), true);
assert.equal(keywordMatch(rules, '正常标题'), false);
assert.equal(invalidKeywordLineCount('广告\n[非法'), 1);

function keywordMatch(list, text) {
  return list.some(rule => rule.test(text));
}

cfg = config({ applySearch: true, titleRules: compileKeywordRules('广告'), blockedMids: new Set(['200']) });
d = evaluateSearchResult('video', item({ title: '广告视频', ownerMid: '100' }), cfg);
assert.equal(d.drop, true);
d = evaluateSearchResult('bili_user', item({ title: '', ownerName: '广告UP', ownerMid: '100' }), cfg);
assert.equal(d.drop, true);
d = evaluateSearchResult('bili_user', item({ title: '无关', ownerName: '正常UP', ownerMid: '200' }), cfg);
assert.equal(d.drop, true, 'blocked search user is removed');
d = evaluateSearchResult('bili_user', item({ title: '无关', ownerName: '正常UP', ownerMid: '300' }), cfg);
assert.equal(d.drop, false);
cfg.applySearch = false;
d = evaluateSearchResult('video', item({ title: '广告视频' }), cfg);
assert.equal(d.drop, false, 'search switch off disables search filter');

console.log('PASS: recommend filter priority, scenes, unknown stats, PGC, search and keyword isolation.');
