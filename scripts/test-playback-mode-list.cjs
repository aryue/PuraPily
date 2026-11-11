// 播放模式：连刷「自动连播/单集循环/播完暂停」、非连刷多一项「列表循环」。
// 自动连播 vs 列表循环的唯一区别：到分P/合集队尾时是否回到列表头。
// 非连刷不接相关推荐（用户 2026-11-11 明确「不搞推荐连播」）。
const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';

function extract(source, name) {
  const match = new RegExp('^\\s+private (?:async )?' + name + '\\(', 'm').exec(source);
  assert.ok(match, 'compiled method exists: ' + name);
  let pos = source.indexOf('{', match.index), depth = 1, end = pos + 1;
  for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(match.index, end);
}

const source = fs.readFileSync(root + 'pages/VideoPlayerPage.ts', 'utf8');
const body = ['referenceOnCompleted', 'referencePlayNextEpisode', 'seasonNeighborEpisode', 'seasonFirstEpisode',
  'isCurrentSeasonEpisode', 'detailIsCurrentVideo'].map(name => extract(source, name)).join('\n');
const transpiled = ts.transpileModule('class Subject {' + body + '}', { compilerOptions: { target: ts.ScriptTarget.ES2020 } }).outputText;
const context = { logInfo: () => {}, logWarn: () => {}, logError: () => {}, console };
vm.runInNewContext(transpiled + '\nglobalThis.Subject = Subject;', context);

function seasonOf(episodes) {
  return { ugc_season: { sections: [{ episodes }] } };
}

function makePage(overrides = {}) {
  const page = new context.Subject();
  page.effects = [];
  page.referenceAlive = true;
  page.referenceStopAtEnd = false;
  page.referencePlaybackMode = 'single';
  page.referencePlaybackCompleted = true;
  page.feed = false;
  page.pages = [];
  page.currentPageIndex = 0;
  page.isPgc_ = false;
  page.vd = null;
  page.vdBvid_ = '';
  page.offlineVideoPath_ = '';
  page.vi = { bvid: 'BVMAIN', cid: 1 };
  page.pagesForCurrentVideo = () => page.pages;
  page.referencePortraitFeedActive = () => page.feed;
  page.switchEpisode = async (index) => { page.effects.push('ep:' + index); };
  page.switchSeasonEpisode = async (ep) => { page.effects.push('season:' + ep.bvid); };
  page.referenceFeedQueue = [];
  page.ensureReferenceRecommendQueue = async () => page.queue || page.referenceFeedQueue;
  page.referenceNextVideo = async (step) => { page.effects.push('feed:' + step); };
  page.referencePause = () => { page.effects.push('pause'); };
  page.referenceSetSleep = (minutes) => { page.effects.push('sleep:' + minutes); };
  page.seek = async (time) => { page.effects.push('seek:' + time); };
  page.av = { play: async () => { page.effects.push('play'); } };
  page.avAudio = { play: async () => { page.effects.push('audio'); } };
  page.markAutoPlay = () => {};
  Object.assign(page, overrides);
  return page;
}

const episodes = [{ bvid: 'BVEP1', cid: 11 }, { bvid: 'BVEP2', cid: 22 }, { bvid: 'BVEP3', cid: 33 }];

(async () => {
  // 播完暂停：什么都不做
  let page = makePage({ referencePlaybackMode: 'single' });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, [], 'single stops at the end');

  // 单集循环：重播当前（不切集）
  page = makePage({ referencePlaybackMode: 'loop' });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['seek:0', 'play', 'audio'], 'loop replays current episode');

  // 自动连播：分P 中间 → 下一个 P
  page = makePage({ referencePlaybackMode: 'continuous', pages: [{ cid: 1 }, { cid: 2 }, { cid: 3 }], currentPageIndex: 0 });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['ep:1'], 'auto plays next part');
  assert.equal(page.referencePlaybackCompleted, false, 'auto play clears the completed terminal');

  // 自动连播：分P 末尾 → 停住，不回头、不接推荐
  page = makePage({ referencePlaybackMode: 'continuous', pages: [{ cid: 1 }, { cid: 2 }], currentPageIndex: 1 });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, [], 'auto play stops at the end of the part list');

  // 列表循环：分P 末尾 → 回到第 1 个 P
  page = makePage({ referencePlaybackMode: 'listLoop', pages: [{ cid: 1 }, { cid: 2 }], currentPageIndex: 1 });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['ep:0'], 'list loop wraps to the first part');

  // 自动连播：合集中间 → 下一集
  page = makePage({
    referencePlaybackMode: 'continuous', vi: { bvid: 'BVEP1', cid: 11 }, pages: [{ cid: 11 }],
    vd: seasonOf(episodes), vdBvid_: 'BVEP1'
  });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['season:BVEP2'], 'auto play moves to the next season episode');

  // 自动连播：合集最后一集 → 停住
  page = makePage({
    referencePlaybackMode: 'continuous', vi: { bvid: 'BVEP3', cid: 33 }, pages: [{ cid: 33 }],
    vd: seasonOf(episodes), vdBvid_: 'BVEP3'
  });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, [], 'auto play stops at the last season episode');

  // 列表循环：合集最后一集 → 回到第一集
  page = makePage({
    referencePlaybackMode: 'listLoop', vi: { bvid: 'BVEP3', cid: 33 }, pages: [{ cid: 33 }],
    vd: seasonOf(episodes), vdBvid_: 'BVEP3'
  });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['season:BVEP1'], 'list loop wraps to the first season episode');

  // 分P 优先于合集：多P 稿件的第 2 个 P 播完先走第 3 个 P，而不是跳到下一集
  page = makePage({
    referencePlaybackMode: 'continuous', vi: { bvid: 'BVEP1', cid: 12 }, pages: [{ cid: 11 }, { cid: 12 }, { cid: 13 }],
    currentPageIndex: 1, vd: seasonOf(episodes), vdBvid_: 'BVEP1'
  });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['ep:2'], 'parts come before the next season episode');

  // 单 P 且不在任何合集：没有可连播的列表，停在原处
  page = makePage({ referencePlaybackMode: 'continuous', pages: [{ cid: 1 }], vd: null });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, [], 'no episode list means nothing to play');

  // 连刷：列表循环按自动连播处理（story 队列本身就是无限流），到队尾兜底回队首
  page = makePage({
    referencePlaybackMode: 'listLoop', feed: true,
    referenceFeedQueue: [{ id: 'BVA' }, { id: 'BVMAIN' }]
  });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['feed:1'], 'feed always advances the story queue');
  assert.equal(page.referenceFeedQueue[0].id, 'BVMAIN', 'story queue wraps only at its real end');

  // 连刷 + 自动连播：非队尾时不重排队列
  page = makePage({ referencePlaybackMode: 'continuous', feed: true, referenceFeedQueue: [{ id: 'BVMAIN' }, { id: 'BVB' }] });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['feed:1']);
  assert.equal(page.referenceFeedQueue[0].id, 'BVMAIN', 'queue keeps its order mid-list');

  // 定时关闭的「播完当前视频」优先级最高：不再连播
  page = makePage({ referencePlaybackMode: 'continuous', referenceStopAtEnd: true, pages: [{ cid: 1 }, { cid: 2 }] });
  await page.referenceOnCompleted();
  assert.deepEqual(page.effects, ['sleep:0', 'pause'], 'stop-at-end wins over auto play');
  assert.equal(page.referenceStopAtEnd, false);

  console.log('PASS: playback modes — auto play advances parts/season episodes, list loop wraps, feed stays story-driven, no recommendation autoplay');
})();
