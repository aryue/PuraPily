const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const read = name => fs.readFileSync('entry/src/main/ets/' + name, 'utf8').replace(/\r\n/g, '\n');
const compile = (code, ctx) => vm.runInNewContext(ts.transpileModule(code, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
const section = (s, a, b) => s.slice(s.indexOf(a), s.indexOf(b, s.indexOf(a)));
const channels = read('components/HomeChannelContainer.ets');
const ctx = { exports: {}, Curve: { EaseOut: 0 }, logError() {}, AppStorage: { get: () => 0 } };
compile(section(channels, 'export const CHANNEL_TABS', '@Component'), ctx);
assert.deepEqual(Array.from(ctx.exports.CHANNEL_TABS, c => c.name), ['直播','推荐','热门','分区','番剧','影视']);
for (let i = 0; i < 6; i++) assert.equal(ctx.exports.channelPagerIndex(ctx.exports.channelAtPager(i)), i);
const api = read('api/RegionApi.ets');
compile(section(api, 'export const REGION_TABS', '// ==================== 常量'), ctx);
ctx.REGION_TABS = ctx.exports.REGION_TABS;
assert.deepEqual(Array.from(ctx.REGION_TABS, c => c.name), ['全站','番剧','国创','动画','音乐','舞蹈','游戏','知识','科技','运动','汽车','美食','动物','鬼畜','时尚','娱乐','影视','纪录','电影','剧集','综艺']);
ctx.RecommendItem = class { pgcSeasonId = 0; };
ctx.fetchPgcSeasonsByParams = async (type, page, size, params) => {
  assert.equal(params.type, '1'); assert.equal(size, 30);
  return [{ seasonType: type, seasonId: 123, epId: 7, title: '正确节目', cover: 'cover', indexShow: '全12集', score: '9.5' },
    { seasonType: 99, seasonId: 999, title: '错误分类' }];
};
ctx.fetchRegionRanking = async rid => [{ id: 'BV' + rid }];
const page = read('pages/RegionChannelPage.ets');
assert.equal((page.match(/Refresh\(\{/g) || []).length, 1, 'one refresh controller for both permanent panes');
assert.ok(!page.includes('private get '), 'ArkUI component accessors must not be stripped by the UI compiler');
compile('export ' + section(page, 'class RegionContentState', '/** 首页分区'), ctx);
ctx.RegionContentState = ctx.exports.RegionContentState;
ctx.VideoCardFeedback = { isDismissed: () => false };
const compiledPath = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/RegionChannelPage.ts';
const compiled = process.argv.includes('--compiled') ? fs.readFileSync(compiledPath, 'utf8') : null;
const methods = compiled
  ? section(compiled, '    private currentDataSource()', '    private Sidebar(')
  : section(page, '  private currentDataSource()', '  private sidebarScroller:') +
    section(page, '  private regionState(', '  @Builder\n  private Sidebar(');
assert.ok(methods.includes('currentDataSource()'), 'compiled component retains data source access methods');
compile('export class Page {' + methods + '}', ctx);
async function main() {
  const food = await ctx.exports.fetchRegionContent(211);
  assert.equal(food[0].id, 'BV1020', 'use current ranking id rather than frozen legacy ranking');
  const mapped = await ctx.exports.fetchRegionContent(-4);
  assert.equal(mapped.length, 1); assert.equal(mapped[0].pgcSeasonId, 123);
  assert.equal(mapped[0].id, 'ss123');
  const p = new ctx.exports.Page();
  let routed;
  const source = () => ({ items: [], reloads: 0, reloadItems(a) { this.items = [...a]; this.reloads++; },
    totalCount() { return this.items.length; } });
  const scroller = () => ({ currentOffset: () => ({ yOffset: 120 }), scrollTo(args) { p.lastOffset = args.yOffset; } });
  Object.assign(p, { generation: 0, selectedRid: 0, ids: new Set(), regionStates: new Map(), page: 1, itemCount: 0,
    activePane: 0, paneRids: [0,0], paneCounts: [0,0], paneLoaded: [false,false],
    paneDataSources: [source(), source()], paneScrollers: [scroller(), scroller()],
    paneItemSets: [[], []],
    waitForPaneLayout: async () => {},
    getUIContext: () => ({ getRouter: () => ({ pushUrl: args => { routed = args; return Promise.resolve(); } }),
      animateTo: (options, action) => { action(); options.onFinish?.(); } }),
    contentWidth: 300 });
  let oldResolve, newResolve;
  ctx.fetchRegionContent = rid => new Promise(resolve => { if (rid === 0) oldResolve = resolve; else newResolve = resolve; });
  const oldRequest = p.loadRanking(true);
  p.selectedRid = 211;
  const newRequest = p.loadRanking(true);
  newResolve([{ id: 'new' }]); await newRequest;
  oldResolve([{ id: 'old' }]); await oldRequest;
  assert.deepEqual(p.currentDataSource().items.map(r => r.id), ['new'], 'late old category cannot overwrite selected category');
  assert.equal(p.regionState(0).items[0].id, 'old', 'offscreen first load is retained for later visits');
  let requests = 0;
  ctx.fetchRegionContent = async rid => { requests++; return [{ id: 'cached-' + rid }]; };
  await p.onRegionSelect(0);
  assert.equal(requests, 0, 'return to a loaded category must not refetch');
  assert.equal(p.currentDataSource().items[0].id, 'old');
  await p.onRegionSelect(211);
  assert.equal(requests, 0);
  assert.equal(p.currentDataSource().items[0].id, 'new');
  assert.equal(p.lastOffset, 120, 'restore per-category scroll position');
  await p.loadRanking(true);
  assert.equal(requests, 1, 'explicit refresh still fetches');
  assert.equal(p.currentDataSource().items[0].id, 'cached-211');
  let resolvePending;
  ctx.fetchRegionContent = () => { requests++; return new Promise(resolve => { resolvePending = resolve; }); };
  p.selectedRid = 3;
  const firstLoad = p.loadRanking(true, true);
  const returnBeforeReady = p.loadRanking(true, true);
  assert.equal(requests, 2, 'reuse first in-flight load rather than send duplicate requests');
  resolvePending([{ id: 'music' }]);
  await Promise.all([firstLoad, returnBeforeReady]);
  assert.equal(p.currentDataSource().items[0].id, 'music');
  // Both pages move in the same animation and share one edge at every progress.
  for (const direction of [-1, 1]) {
    p.transitionDirection = direction;
    for (const progress of [0, 0.1, 0.25, 0.5, 0.75, 1]) {
      const positions = [p.outgoingTranslation(progress), p.incomingTranslation(progress)].sort((a,b) => a-b);
      assert.equal(positions[0] + p.contentWidth, positions[1], 'no gap between outgoing and incoming pages');
      assert.ok(positions[0] <= 0 && positions[1] + p.contentWidth >= p.contentWidth);
    }
  }
  let finishAnimation, animations = 0;
  const originalContext = p.getUIContext;
  p.getUIContext = () => ({ ...originalContext(), animateTo: (options, action) => {
    animations++; action(); finishAnimation = options.onFinish;
  } });
  const changing = p.onRegionSelect(211);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(animations, 1, 'one simultaneous transition, not exit then entry');
  assert.equal(p.currentDataSource().items[0].id, 'music', 'outgoing live list stays intact throughout the slide');
  assert.equal(p.incomingItems[0].id, 'cached-211', 'target cache is already mounted during the slide');
  assert.equal(p.transitionActive, true);
  const incomingSource = p.incomingDataSource();
  const incomingController = p.incomingScroller();
  const incomingReloads = incomingSource.reloads;
  finishAnimation(); await changing;
  assert.equal(p.currentDataSource().items[0].id, 'cached-211');
  assert.equal(p.currentDataSource(), incomingSource, 'promote the same list instead of copying to a second list');
  assert.equal(p.currentScroller(), incomingController, 'keep incoming scroll controller');
  assert.equal(p.currentDataSource().reloads, incomingReloads, 'completion must not reload or re-key incoming cover nodes');
  await p.loadRanking(true, true);
  assert.equal(p.currentDataSource().reloads, incomingReloads, 'restoring identical cached data must not trigger another image reload');
  assert.equal(p.paneTranslation(p.activePane), 0);
  assert.equal(p.transitionActive, false);
  p.getUIContext = originalContext;
  p.transitionActive = true;
  ctx.fetchRegionContent = async () => [{ id: 'arrived-during-handoff' }];
  await p.loadRanking(true);
  assert.equal(p.currentDataSource().items[0].id, 'cached-211', 'late data must leave outgoing cover nodes intact');
  assert.equal(p.incomingItems[0].id, 'arrived-during-handoff');
  p.transitionActive = false;
  p.selectedRid = -4; p.hasMore = true;
  ctx.fetchRegionContent = async () => [{ id: 'new' }, { id: 'more' }];
  await p.loadRanking(false);
  assert.deepEqual(p.currentDataSource().items.map(r => r.id), ['new', 'more']);
  p.onCardClick(mapped[0]); assert.equal(routed.params.mediaId, 123);
  p.onCardClick({ pgcSeasonId: 0, id: 'BV1', aid: 42 }); assert.equal(routed.params.bvid, 'BV1');
  p.selectedRid = 188;
  ctx.fetchRegionContent = async () => { throw new Error('network unavailable'); };
  await p.loadRanking(true, true);
  assert.equal(p.paneLoaded[p.activePane], true, 'failed initial request exits indefinite spinner');
  assert.equal(p.isLoading, false);
  assert.equal(p.isRefreshing, false);
  assert.equal(p.regionState(188).loaded, false, 'failed request remains retryable');
  ctx.fetchRegionContent = async () => [{ id: 'retried' }];
  await p.loadRanking(true);
  assert.equal(p.currentDataSource().items[0].id, 'retried');
  assert.equal(p.regionState(188).failed, false);
  console.log('Region navigation, cache reuse, scroll restoration, in-flight request reuse, manual refresh, pagination and playback routes passed');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
