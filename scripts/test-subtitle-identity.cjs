/**
 * 字幕「取到其他视频的数据」根因回归（番剧每集是独立稿件）：
 *
 * 现场：/x/player/v2 是「按 bvid 定位作品、cid 只做分P 筛选」——
 *   bvid=BV15i421v7FQ（第1集）& cid=1602741611（第2集）实测返回 code 0 + aid=第1集 + page_no=1，
 *   也就是字幕会退化成那一集的第 1 个分P。而 bvid 为空时接口直接 -400（表现为误报"暂无可用字幕"）。
 *
 * 迁移到本项目的三条事实：
 *  - 番剧季接口每一集都带自己的 bvid（`episodes[i].bvid`），但 PgcEpisode 原先没解析；
 *  - 播放页 PGC 分支只维护 pgcEpIds_/pgcAids_，切集只改 cid → bvid 永远停在进入时那一集；
 *  - 字幕请求直接用 vi.bvid + vi.cid，于是切集后拿到的是 bvid 那一集的字幕。
 *
 * 修复口径：
 *  1) PgcEpisode 解析 bvid；三个入口共用同一分集表，并按 cid 反查同步 vi.bvid；
 *  2) 字幕请求前必须 bvid/cid 同源就绪（空 bvid、纯数字 aid、cid=0 都不发）；
 *  3) 落地校验接口回显的 bvid；字幕 cues 记录归属身份（bvid:cid），身份不符一帧都不显示。
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const source = read('entry/src/main/ets/pages/VideoPlayerPage.ets');
const apiSource = read('entry/src/main/ets/api/BilibiliApi.ets');

function extract(name, { braces = 1 } = {}) {
  const start = source.indexOf(`${name}(`);
  assert.ok(start > 0, `缺少 ${name}`);
  let i = source.indexOf('{', start);
  let depth = 0;
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') { depth--; if (depth === braces - 1) break; }
  }
  return source.slice(source.lastIndexOf('\n', start) + 1, i + 1);
}

// 1) PGC 分集要能拿到自己的 bvid。
const pgcEpisode = apiSource.slice(apiSource.indexOf('export interface PgcEpisode'));
assert.ok(/bvid\?: string;/.test(pgcEpisode.slice(0, 400)),
  'PgcEpisode 必须解析 bvid（番剧每集是独立稿件，字幕接口按 bvid 定位）');

// 2) 三个入口共用一次分集身份提交，建表后按 CID 补齐 BV。
assert.equal((source.match(/this\.applyPgcSeasonDetail\((?:pgcInfo|season),/g) || []).length, 3);
const applySeason = extract('private applyPgcSeasonDetail');
assert.match(applySeason, /this\.pgcEpisodes_\.load[\s\S]*this\.syncPgcBvidForCid\(this\.vi\.cid\)/);

// 3) setPlaybackCid 是唯一 cid 入口：PGC 下必须同步 bvid。
const setCid = extract('private setPlaybackCid');
assert.ok(setCid.includes('this.pgcBvidForCid(cid) || bvid'),
  'setPlaybackCid 必须在 PGC 下同步当前集的 bvid');

// 4) 反查按 cid 对齐，且非 PGC 不碰 bvid。
const pgcBvidForCid = extract('private pgcBvidForCid');
assert.ok(pgcBvidForCid.includes('if (!this.isPgc_ || cid <= 0) return'),
  'pgcBvidForCid 必须限定 PGC 且 cid>0');
assert.ok(pgcBvidForCid.includes('this.pgcEpisodes_.bvidForCid(cid)'),
  'pgcBvidForCid 必须从分集表按 cid 取 bvid');
const syncPgc = extract('private syncPgcBvidForCid');
assert.ok(syncPgc.includes('pgcBvidForCid(cid)') && syncPgc.includes('this.commitPlaybackIdentity(cid, bvid)'),
  'syncPgcBvidForCid 必须在查到 bvid 时写回 vi.bvid');

// 5) 字幕请求前置身份校验：空 bvid / 纯数字 aid / cid=0 都不发请求。
const awaitIdentity = extract('private async referenceAwaitSubtitleIdentity');
assert.ok(awaitIdentity.includes('this.vi.cid > 0'), '身份等待必须先等到 cid');
assert.ok(/!\/\^\\d\+\$\/\.test\(bvid\)/.test(awaitIdentity),
  '身份等待必须拒绝纯数字 bvid（aid 尚未解析成 BV 时接口认不出稿件）');
assert.ok(!awaitIdentity.includes('this.syncPgcBvidForCid(this.vi.cid)'),
  '读取字幕时不能反写当前媒体身份');
assert.ok(/await new Promise<void>[\s\S]*setTimeout\(resolve, 100\)/.test(awaitIdentity),
  '身份等待要轮询而不是空转一次');
assert.ok(/return null;\s*\}\s*$/.test(awaitIdentity.trimEnd()) || awaitIdentity.trimEnd().endsWith('return null;\n  }'),
  '身份等待超时必须返回 null（不能拿空 bvid 去换字幕）');

for (const name of ['private async referenceSetSubtitles', 'private async referenceOpenLandscapeSubtitles']) {
  const fn = extract(name);
  assert.ok(fn.includes('await this.referenceAwaitSubtitleIdentity()'),
    `${name} 请求前必须等身份就绪`);
  const guard = fn.indexOf('referenceAwaitSubtitleIdentity');
  const fetch = fn.indexOf('subtitleFetchTracks');
  assert.ok(guard > 0 && fetch > guard, `${name} 的身份校验必须在取轨之前`);
}

// 6) 取轨统一走 subtitleFetchTracks：轨归属靠 AI 文件名里的 aid+cid 校验
//    （接口回显的 bvid/cid 会与请求一致但轨道仍是别人的，见 test-subtitle-track-owner.cjs）。
const setSubs = extract('private async referenceSetSubtitles');
const menuSubs = extract('private async referenceOpenLandscapeSubtitles');
for (const [name, fn] of [['referenceSetSubtitles', setSubs], ['referenceOpenLandscapeSubtitles', menuSubs]]) {
  assert.ok(fn.includes('await this.subtitleTracks_.subtitleFetchTracks(playback)'),
    `${name} 必须走统一取轨入口`);
  assert.ok(!fn.includes('echoedBvid !== bvid'),
    `${name} 不该再只依赖接口回显（回显对、轨道错时拦不住）`);
}

// 7) cues 带归属身份：reset 清空、成功落地设置、显示前校验。
const reset = extract('private referenceResetSubtitles');
assert.ok(reset.includes('this.subtitleTracks_.resetPlayback()'), 'referenceResetSubtitles 必须清空字幕归属');
assert.ok(setSubs.includes('this.subtitleTracks_.setCues(cues, bvid, cid)'),
  'referenceSetSubtitles 落地时必须记录归属身份');
const select = extract('private async referenceSelectSubtitle');
assert.ok(select.includes('this.subtitleTracks_.setCues(cues, bvid, cid)'),
  'referenceSelectSubtitle 落地时必须记录归属身份');
assert.ok(select.includes('this.subtitleTracks_.clearCues()'),
  'referenceSelectSubtitle 关闭字幕时必须清空归属');

const key = extract('private referenceSubtitleKey');
assert.ok(key.includes('this.vi.bvid') && key.includes('this.vi.cid'), '身份键必须由 bvid + cid 组成');

// 8) Progress events use the ownership-aware subtitle lookup.
const timeUpdate = source.slice(source.indexOf("this.playbackResources_.video.on('timeUpdate'"), source.indexOf("this.playbackResources_.video.on('error'", source.indexOf("this.playbackResources_.video.on('timeUpdate'")));
assert.ok(timeUpdate.includes('this.updatePlaybackTimeline(player, t)'));
const timeline = extract('private updatePlaybackTimeline');
assert.ok(timeline.includes('this.subtitleTracks_.textAt(this.referenceSubtitleKey(), t / 1000)'));
assert.ok(timeline.includes('if (text === null) this.referenceSubtitleEnabled = false'));

console.log('test-subtitle-identity: all assertions passed');
