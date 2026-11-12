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
 *  1) PgcEpisode 解析 bvid；播放页建分集表时同步 pgcBvids_（三处），并按 cid 反查同步 vi.bvid；
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

// 2) 播放页维护与 pages 平行的 pgcBvids_，并在建表处填满。
assert.ok(/private pgcBvids_: string\[\] = \[\]/.test(source), '缺少 pgcBvids_ 字段');
const bvidPushes = source.match(/pgcBvids\.push\(ep\.bvid \|\| ''\)/g) || [];
assert.equal(bvidPushes.length, 3, '三处 PGC 分集表都必须 push ep.bvid');
const bvidAssigns = source.match(/this\.pgcBvids_ = pgcBvids;/g) || [];
assert.equal(bvidAssigns.length, 3, '三处 PGC 分集表都必须落地 pgcBvids_');
const syncCallsAfterTable = source.match(/this\.syncPgcBvidForCid\(this\.vi\.cid\);/g) || [];
assert.ok(syncCallsAfterTable.length >= 3, '三处分集表建好后必须按 cid 补一次 bvid');

// 3) setPlaybackCid 是唯一 cid 入口：PGC 下必须同步 bvid。
const setCid = extract('private setPlaybackCid');
assert.ok(setCid.includes('this.syncPgcBvidForCid(cid)'),
  'setPlaybackCid 必须在 PGC 下同步当前集的 bvid');

// 4) 反查按 cid 对齐，且非 PGC 不碰 bvid。
const pgcBvidForCid = extract('private pgcBvidForCid');
assert.ok(pgcBvidForCid.includes('if (!this.isPgc_ || cid <= 0) return'),
  'pgcBvidForCid 必须限定 PGC 且 cid>0');
assert.ok(pgcBvidForCid.includes('pages[i].cid === cid') && pgcBvidForCid.includes('this.pgcBvids_[i]'),
  'pgcBvidForCid 必须按 pages[i].cid 对齐取 pgcBvids_[i]');
const syncPgc = extract('private syncPgcBvidForCid');
assert.ok(syncPgc.includes('pgcBvidForCid(cid)') && syncPgc.includes('this.vi.bvid = bvid'),
  'syncPgcBvidForCid 必须在查到 bvid 时写回 vi.bvid');

// 5) 字幕请求前置身份校验：空 bvid / 纯数字 aid / cid=0 都不发请求。
const awaitIdentity = extract('private async referenceAwaitSubtitleIdentity');
assert.ok(awaitIdentity.includes('this.vi.cid > 0'), '身份等待必须先等到 cid');
assert.ok(/!\/\^\\d\+\$\/\.test\(bvid\)/.test(awaitIdentity),
  '身份等待必须拒绝纯数字 bvid（aid 尚未解析成 BV 时接口认不出稿件）');
assert.ok(awaitIdentity.includes('this.syncPgcBvidForCid(this.vi.cid)'),
  '身份等待必须给 PGC 补上当前集 bvid');
assert.ok(/await new Promise<void>[\s\S]*setTimeout\(resolve, 100\)/.test(awaitIdentity),
  '身份等待要轮询而不是空转一次');
assert.ok(/return false;\s*\}\s*$/.test(awaitIdentity.trimEnd()) || awaitIdentity.trimEnd().endsWith('return false;\n  }'),
  '身份等待超时必须返回 false（不能拿空 bvid 去换字幕）');

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
  assert.ok(fn.includes('await this.subtitleFetchTracks(bvid, cid)'),
    `${name} 必须走统一取轨入口`);
  assert.ok(!fn.includes('echoedBvid !== bvid'),
    `${name} 不该再只依赖接口回显（回显对、轨道错时拦不住）`);
}

// 7) cues 带归属身份：reset 清空、成功落地设置、显示前校验。
const reset = extract('private referenceResetSubtitles');
assert.ok(reset.includes("this.referenceSubtitleOwner = ''"), 'referenceResetSubtitles 必须清空字幕归属');
assert.ok(/private referenceSubtitleOwner: string = ''/.test(source), '缺少 referenceSubtitleOwner 字段');
assert.ok(setSubs.includes('this.referenceSubtitleOwner = `${bvid}:${cid}`'),
  'referenceSetSubtitles 落地时必须记录归属身份');
const select = extract('private async referenceSelectSubtitle');
assert.ok(select.includes('this.referenceSubtitleOwner = `${bvid}:${cid}`'),
  'referenceSelectSubtitle 落地时必须记录归属身份');
assert.ok(select.includes("this.referenceSubtitleOwner = ''"),
  'referenceSelectSubtitle 关闭字幕时必须清空归属');

const key = extract('private referenceSubtitleKey');
assert.ok(key.includes('this.vi.bvid') && key.includes('this.vi.cid'), '身份键必须由 bvid + cid 组成');

// 8) 渲染兜底：身份不符直接关字幕，绝不显示别的视频的 cues。
const timeUpdateIdx = source.indexOf("this.av.on('timeUpdate'");
assert.ok(timeUpdateIdx > 0, '缺少 timeUpdate 订阅');
const timeUpdate = source.slice(timeUpdateIdx, timeUpdateIdx + 1600);
assert.ok(timeUpdate.includes('this.referenceSubtitleOwner !== this.referenceSubtitleKey()'),
  'timeUpdate 必须在显示前核对字幕归属身份');
assert.ok(/referenceSubtitleCues\.length > 0 && this\.referenceSubtitleOwner !== this\.referenceSubtitleKey\(\)/.test(timeUpdate),
  '身份校验必须带 cues.length>0 守卫（请求中的空 cues 不能被误判成串数据）');
assert.ok(timeUpdate.includes('this.referenceSubtitleEnabled = false;'),
  '身份不符时必须关闭字幕，而不是继续显示旧 cues');

console.log('test-subtitle-identity: all assertions passed');
