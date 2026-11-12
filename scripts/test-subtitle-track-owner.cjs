/**
 * 字幕「取到其他视频的数据」根因回归（服务端会把别的视频的 AI 轨当成本视频的返回）：
 *
 * 现场（2026-11-12 实测，登录态）：
 *  - BV1pCxP6SEoK / cid=43165618144（36s 预告）带正确 aid+bvid+cid 请求 /x/player/v2，
 *    回显的 bvid/cid 全对，subtitle_url 却是 BV1vFmAY4EeN（250s 探店 vlog）的 AI 轨；
 *  - 同一参数连打三次拿到三个不同的文件名前缀，全部不等于请求的 aid+cid；
 *  - 该视频自己的 wbi 版（/x/player/wbi/v2，带 w_rid/wts）返回 0 条 —— 也就是它本来就没字幕。
 *
 * 关键事实（外部资料 + 现场双向验证）：AI 字幕文件名 = `<aid><cid><32位md5>`
 *   aid=658265572&cid=1193639024 → 6582655721193639024b86c092b75e877a90c9875c93010dc52
 *   aid=113372557284811&cid=26470056562 → 11337255728481126470056562b611b9ad...
 * 正例 BV1k81sYbEDw：文件名前缀 == aid+cid，轨内容（离谱投稿第七集）与画面字幕一致。
 *
 * 修复口径：
 *  1) aid 由 /x/web-interface/view?bvid= 反查（权威），不用详情/路由里可能停在上一条的值；
 *  2) 列表先试 wbi 版再退回老版，两条都必须过「AI 轨文件名前缀 == aid+cid」的归属校验；
 *  3) 落地（下载 cue）再兜一层时间轴校验：覆盖时长不得明显超出视频时长；
 *  4) 校验不过 = 这条视频没有可用字幕，宁可提示"暂无"，绝不显示别人的台词。
 */
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n');
const source = read('entry/src/main/ets/pages/VideoPlayerPage.ets');

function extract(name) {
  const start = source.indexOf(`${name}(`);
  assert.ok(start > 0, `缺少 ${name}`);
  let i = source.indexOf('{', start);
  let depth = 0;
  for (; i < source.length; i++) {
    if (source[i] === '{') depth++;
    else if (source[i] === '}') { depth--; if (depth === 0) break; }
  }
  return source.slice(source.lastIndexOf('\n', start) + 1, i + 1);
}

// 0) 不再用「接口回显 bvid 相同」当唯一判据（回显对、轨道错就是这么漏的）。
assert.ok(!source.includes('referenceSubtitleApiUrl'),
  '旧的 referenceSubtitleApiUrl 组装入口应已被 subtitleFetchTracks 取代');

// 1) 文件名解析：去掉 query/auth_key，取最后 32 位 md5 之前的部分。
const prefixFn = extract('private subtitleTrackPrefix');
assert.ok(prefixFn.includes("url.split('?')[0]"), 'AI 轨前缀解析必须先剥掉 auth_key');
assert.ok(prefixFn.includes('name.length - 32'), 'AI 轨前缀 = 文件名去掉 32 位 md5');

// 2) 归属判定：只对 AI 轨比对文件名；人工字幕（纯 md5）放行，靠时长兜底。
const aiPathFn = extract('private subtitleIsAiTrack');
assert.ok(aiPathFn.includes("indexOf('/ai_subtitle/prod/')"), '必须区分 AI 轨路径');
const ownedFn = extract('private subtitleTrackOwned');
assert.ok(ownedFn.includes('this.subtitleIsAiTrack(url)'), '归属判定要先分流 AI/人工轨');
assert.ok(ownedFn.includes('this.subtitleTrackPrefix(url) === `${aid}${cid}`'),
  'AI 轨必须比对「文件名前缀 == aid+cid」');
assert.ok(ownedFn.includes('if (aid <= 0 || cid <= 0) return false'),
  'aid/cid 缺失时不能放行 AI 轨');

// 3) 权威 aid：由 bvid 反查，并缓存。
const identityFn = extract('subtitleAuthoritativeIdentity');
assert.ok(identityFn.includes('/x/web-interface/view?bvid='), 'aid 必须由 view 接口反查');
assert.ok(identityFn.includes('subtitleIdentityCache_.set'), '反查结果要缓存');
assert.ok(source.includes('private subtitleIdentityCache_: Map<string, SubtitleIdentity>'),
  '缺少 subtitleIdentityCache_ 字段');

// 4) 双通道取列表，两条都要过滤。
const fetchFn = extract('subtitleFetchTracks');
assert.ok(fetchFn.includes('/x/player/wbi/v2?'), '必须尝试网页播放器在用的 wbi 版接口');
assert.ok(fetchFn.includes("await AppSign.generateWebParams(params)"), 'wbi 版要签名');
assert.ok(fetchFn.includes('/x/player/v2?'), '必须保留老版接口兜底');
assert.ok(fetchFn.includes('raw.filter((track: ReferenceSubtitleTrack) => this.subtitleTrackOwned('),
  '列表落地前必须按归属过滤');
assert.ok(fetchFn.includes('if (owned.length > 0) return owned'), '只返回归属通过的轨');

// 4b) 请求口径 ≠ 校验口径：番剧带 aid 会返回空列表，但 AI 轨文件名的 aid 仍是这条视频的。
assert.ok(fetchFn.includes('const requestAid = this.isPgc_ ? 0 :'), 'PGC 请求必须保持不带 aid');
assert.ok(fetchFn.includes('const expectAid = identity ? identity.aid : requestAid'),
  '校验口径要用权威 aid');
assert.ok(fetchFn.includes('this.subtitleTrackOwned(track, expectAid, cid)'),
  '过滤必须用校验口径而不是请求口径');

// 5) 两个入口（开关/面板）都走 subtitleFetchTracks，不再各自拼 URL。
const toggleFn = extract('private async referenceSetSubtitles');
assert.ok(toggleFn.includes('await this.subtitleFetchTracks(bvid, cid)'),
  '开关字幕必须走统一取轨入口');
const menuFn = extract('private async referenceOpenLandscapeSubtitles');
assert.ok(menuFn.includes('await this.subtitleFetchTracks(bvid, cid)'),
  '字幕面板必须走统一取轨入口');

// 6) cue 落地校验：覆盖时长不得明显超出视频时长。
const fitsFn = extract('private subtitleCueFits');
assert.ok(fitsFn.includes('this.dur') && fitsFn.includes('return true'), '时长未知时必须放行，避免误杀');
assert.ok(fitsFn.includes('* 1.2 + 15'), '时间轴容差要留够（1.2 倍 + 15s）');
assert.ok(toggleFn.includes('if (!this.subtitleCueFits(cues))'), '开关路径要校验 cue 时间轴');
const selectFn = extract('private async referenceSelectSubtitle');
assert.ok(selectFn.includes('if (!this.subtitleCueFits(cues))'), '选轨路径要校验 cue 时间轴');

// 7) 归属校验失败必须落到"暂无可用字幕"，不能静默显示。
assert.ok(/当前视频暂无可用字幕/.test(toggleFn), '校验不过要提示暂无可用字幕');

// 8) 诊断代码不得留在仓库里。
assert.ok(!source.includes('[Probe]'), '临时诊断代码必须删除');
assert.ok(!source.includes('probe1'), '临时诊断代码必须删除');

// 9) 逻辑自测：用现场真实数据跑一遍前缀/归属判定。
function trackPrefix(url) {
  const p = String(url).split('?')[0];
  const name = p.slice(p.lastIndexOf('/') + 1);
  return name.length <= 32 ? '' : name.slice(0, name.length - 32);
}
function owned(url, aid, cid) {
  if (!url) return false;
  if (url.indexOf('/ai_subtitle/prod/') < 0) return true;
  if (aid <= 0 || cid <= 0) return false;
  return trackPrefix(url) === `${aid}${cid}`;
}
const AI = '//aisubtitle.hdslb.com/bfs/ai_subtitle/prod/';
// 正例：BV1k81sYbEDw（离谱投稿第七集）自己的轨
assert.equal(owned(`${AI}11337255728481126470056562b611b9add54b5f7ac182af4ae73dfec7?auth_key=1794465879-x-0-y`,
  113372557284811, 26470056562), true, '自己的 AI 轨应通过');
// 负例：BV1pCxP6SEoK 请求到的 BV1vFmAY4EeN（探店 vlog）的轨
assert.equal(owned(`${AI}11331482682071626310543338b611b9add54b5f7ac182af4ae73dfec7?auth_key=1-2-0-3`,
  117527183104815, 43165618144), false, '别人的 AI 轨必须拒绝');
// 负例：老版接口连打三次拿到的三条不同轨，全部应拒绝
for (const f of ['11337918428518926489785779', '11337785881569626484999041', '11333512724560726369261601']) {
  assert.equal(owned(`${AI}${f}b611b9add54b5f7ac182af4ae73dfec7`, 117527183104815, 43165618144), false,
    `连打错轨 ${f} 必须拒绝`);
}
// 人工字幕（纯 md5）不参与文件名比对
assert.equal(owned('//i0.hdslb.com/bfs/subtitle/9c2d1b3a4f5e6d7c8b9a0f1e2d3c4b5a.json', 1, 2), true,
  '人工字幕文件名无身份信息，应放行');
// 空地址不可用
assert.equal(owned('', 1, 2), false, '无地址的轨不可用');

console.log('test-subtitle-track-owner: ok');
