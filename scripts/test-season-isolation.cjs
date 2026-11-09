const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const page = fs.readFileSync('entry/src/main/ets/pages/VideoPlayerPage.ets', 'utf8').replace(/\r\n/g, '\n');
function between(source, start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a + start.length);
  assert.ok(a >= 0 && b > a, `missing slice: ${start}`);
  return source.slice(a, b);
}

let detailResolver = null;
const context = {
  exports: {},
  logInfo() {},
  setTimeout: (fn, ms) => setTimeout(fn, ms),
  getVideoDetail: () => new Promise(resolve => { detailResolver = resolve; })
};
vm.runInNewContext(ts.transpileModule(`export class Page {
  ${between(page, '  private pagesForCurrentVideo(', '  /** ⭐ 选集分段索引列表（0, 1, 2...） */')}
}`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, context);

const page1 = { cid: 10, page: 1, part: 'P1' };
const page2 = { cid: 11, page: 2, part: 'P2' };
const oldVd = {
  bvid: 'BVold', aid: 1, cid: 10, title: 'Old title', desc: 'Old desc', pic: '', pubdate: 0, ctime: 0, duration: 60,
  owner: { mid: 9, name: 'UP', face: '' }, stat: { aid: 1, view: 1, danmaku: 1, reply: 0, favorite: 0, coin: 0, share: 0, like: 0 },
  pages: [page1, page2],
  ugc_season: {
    id: 77, title: 'Season', sections: [
      { title: 'S1', episodes: [{ bvid: 'BVold', aid: 1, cid: 10, title: 'Old title' }] },
      { title: 'S2', episodes: [
        { bvid: 'BVnew', aid: 2, cid: 20, title: 'New title', arc: { pic: 'new.jpg', duration: 90, stat: { view: 1234 } } },
        { bvid: 'BVlast', aid: 3, cid: 30, title: 'Last title' }
      ] }
    ]
  }
};
const newEp = oldVd.ugc_season.sections[1].episodes[0];

function makePage() {
  const p = new context.exports.Page();
  const started = [], comments = [], related = [];
  Object.assign(p, {
    referenceAlive: true,
    vi: { bvid: 'BVold', cid: 10, title: 'Old title', cover: 'old.jpg', duration: 60 },
    vd: oldVd,
    vdBvid_: 'BVold',
    currentPageIndex: 1,
    referenceEpisodeSelection: 1,
    episodeSegment: 0,
    episodeSheetInitialIndex: 1,
    pendingEpisodeIndex_: 5,
    episodeSwitchJob_: null,
    seasonSwitchSeq_: 0,
    seasonSectionIndex: 0,
    ct: 42,
    lastHeartbeatTime: 99,
    initialProgress_: 42,
    commentCursor: 3,
    commentDataSource: { cleared: 0, clear() { this.cleared++; } },
    likeCount: 1, coinCount: 1, favoriteCount: 1,
    setPlaybackCid: cid => { p.vi.cid = cid; },
    release: async () => {},
    initP: async () => { started.push(p.vi.cid); },
    loadC: aid => comments.push(aid),
    fetchRelatedVideos: bvid => { related.push(bvid); },
    loadInitialVideoInteractions() {},
    applyDetailDimension() {},
    predecodeKeyImages() {}
  });
  p.started = started; p.comments = comments; p.related = related;
  return p;
}

async function main() {
  const p = makePage();
  // 合集切集是「换视频」：详情没回来之前，旧 vd 的分P 必须被视为不存在
  const switching = p.switchSeasonEpisode(newEp);
  await new Promise(setImmediate);
  assert.equal(p.vi.bvid, 'BVnew');
  assert.equal(p.vi.cid, 20);
  assert.equal(p.vi.title, 'New title');
  assert.equal(p.pagesForCurrentVideo().length, 0, 'stale pages must not stay selectable during the switch');
  assert.equal(p.detailIsCurrentVideo(), false);
  assert.equal(p.currentPageIndex, 0, 'page index belongs to the previous video');
  assert.equal(p.referenceEpisodeSelection, -1);
  assert.equal(p.episodeSegment, 0);
  assert.equal(p.pendingEpisodeIndex_, -1);
  assert.equal(p.seasonSectionIndex, 1, 'section follows the target episode');
  assert.equal(p.ct, 0);
  assert.equal(p.lastHeartbeatTime, 0);
  assert.equal(p.initialProgress_, 0);
  assert.equal(p.commentDataSource.cleared, 1);
  assert.deepEqual(p.started, [20], 'playback starts from the new episode cid');
  // 旧详情对象不能被就地改写（缓存里还存着同一条视频）
  assert.equal(oldVd.aid, 1);
  assert.equal(oldVd.bvid, 'BVold');
  // 高亮按 bvid 判定，不依赖还没更新的 vd.aid
  assert.equal(p.isCurrentSeasonEpisode(newEp), true);
  assert.equal(p.seasonCurrentEpisodeIndex(), 1);
  assert.equal(p.seasonTotalEpisodeCount(), 3);

  detailResolver({
    bvid: 'BVnew', aid: 2, cid: 20, title: 'New title', desc: 'New desc', pic: 'new.jpg',
    pubdate: 0, ctime: 0, duration: 90,
    owner: { mid: 9, name: 'UP', face: '' },
    stat: { aid: 2, view: 1234, danmaku: 5, reply: 0, favorite: 7, coin: 8, share: 9, like: 6 },
    pages: [{ cid: 20, page: 1, part: 'Only P' }],
    ugc_season: oldVd.ugc_season
  });
  await switching;

  assert.equal(p.vd.bvid, 'BVnew', 'detail is replaced, not patched');
  assert.equal(p.vd.aid, 2);
  assert.equal(p.vd.pages.length, 1);
  assert.equal(p.pagesForCurrentVideo().length, 1);
  assert.equal(p.detailIsCurrentVideo(), true);
  assert.equal(p.aidFromParams_, 2);
  assert.equal(p.likeCount, 6);
  assert.equal(p.coinCount, 8);
  assert.equal(p.favoriteCount, 7);
  assert.deepEqual(p.comments, [2]);
  assert.deepEqual(p.related, ['BVnew']);

  // 迟到的详情不得覆盖已经切走的那一集
  const p2 = makePage();
  detailResolver = null;
  const first = p2.switchSeasonEpisode(newEp);
  await new Promise(setImmediate);
  const late = detailResolver;
  const second = p2.switchSeasonEpisode(oldVd.ugc_season.sections[1].episodes[1]);
  await new Promise(setImmediate);
  const current = detailResolver;
  current({ bvid: 'BVlast', aid: 3, cid: 30, title: 'Last title', desc: '', pic: '', pubdate: 0, ctime: 0, duration: 30,
    owner: { mid: 9, name: 'UP', face: '' },
    stat: { aid: 3, view: 1, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0 },
    pages: [], ugc_season: oldVd.ugc_season });
  late({ bvid: 'BVnew', aid: 2, cid: 20, title: 'New title', desc: '', pic: '', pubdate: 0, ctime: 0, duration: 90,
    owner: { mid: 9, name: 'UP', face: '' },
    stat: { aid: 2, view: 1, danmaku: 0, reply: 0, favorite: 0, coin: 0, share: 0, like: 0 },
    pages: [], ugc_season: oldVd.ugc_season });
  await Promise.all([first, second]);
  assert.equal(p2.vd.bvid, 'BVlast', 'stale detail responses are dropped');
  assert.equal(p2.vi.bvid, 'BVlast');

  // aid 入口：vi.bvid 存的是数字 aid，详情仍应视为当前视频（否则简介统计和分P会被误判成过期）
  const p3 = makePage();
  Object.assign(p3, { vi: { bvid: '1', cid: 10 }, vdBvid_: 'BVold', vd: oldVd });
  assert.equal(p3.detailIsCurrentVideo(), true);
  assert.equal(p3.pagesForCurrentVideo().length, 2);
  console.log('PASS: 合集切集换整份详情、旧分P 立即失效、迟到响应丢弃');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
