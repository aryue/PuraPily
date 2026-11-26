import { RecommendItem } from './RecommendItem';

/** 推荐过滤生效场景。App 与 Web 推荐的前置过滤条件不同，因此分开。 */
export enum RecommendFilterScene {
  HomeApp = 'homeApp',
  HomeWeb = 'homeWeb',
  Related = 'related',
  Hot = 'hot',
  Rank = 'rank',
  Search = 'search'
}

/** 纯规则快照：只包含判定所需数据，不依赖 AppStorage / Preferences。 */
export class RecommendFilterConfig {
  enabled: boolean = true;
  titleRules: RegExp[] = [];
  upNameRules: RegExp[] = [];
  zoneRules: RegExp[] = [];
  minDuration: number = 0;
  minPlay: number = 0;
  minLikeRatio: number = 0;
  exemptFollowed: boolean = true;
  applyRelated: boolean = true;
  applyHot: boolean = false;
  applyRank: boolean = false;
  applySearch: boolean = false;
  removeUnplayable: boolean = false;
  blockedMids: Set<string> = new Set<string>();
  whitelistMids: Set<string> = new Set<string>();
}

export class RecommendFilterDecision {
  drop: boolean = false;
  reason: string = '';

  constructor(drop: boolean = false, reason: string = '') {
    this.drop = drop;
    this.reason = reason;
  }
}

export function keywordLines(stored: string): string[] {
  const result: string[] = [];
  const lines = stored.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length > 0) {
      result.push(line);
    }
  }
  return result;
}

/** 每行一条独立正则；非法行只跳过该行，不影响其它关键词。 */
export function compileKeywordRules(stored: string): RegExp[] {
  const rules: RegExp[] = [];
  const lines = keywordLines(stored);
  for (let i = 0; i < lines.length; i++) {
    try {
      rules.push(new RegExp(lines[i], 'i'));
    } catch (_) {
      // 非法正则交给设置页提示；运行期静默跳过，避免整组规则失效。
    }
  }
  return rules;
}

export function invalidKeywordLineCount(stored: string): number {
  let invalid = 0;
  const lines = keywordLines(stored);
  for (let i = 0; i < lines.length; i++) {
    try {
      new RegExp(lines[i], 'i');
    } catch (_) {
      invalid++;
    }
  }
  return invalid;
}

export function keywordMatches(text: string, rules: RegExp[]): boolean {
  if (!text || rules.length === 0) return false;
  for (let i = 0; i < rules.length; i++) {
    if (rules[i].test(text)) return true;
  }
  return false;
}

export function isPgcItem(item: RecommendItem): boolean {
  return item.pgcSeasonId > 0 || item.pgcEpId > 0 ||
    item.id.startsWith('ss') || item.id.startsWith('media_');
}

function isWhitelisted(item: RecommendItem, config: RecommendFilterConfig): boolean {
  return item.ownerMid.length > 0 && config.whitelistMids.has(item.ownerMid);
}

function isBlocked(item: RecommendItem, config: RecommendFilterConfig): boolean {
  return item.ownerMid.length > 0 && config.blockedMids.has(item.ownerMid);
}

function matchesUserRules(item: RecommendItem, config: RecommendFilterConfig): RecommendFilterDecision {
  if (item.duration > 0 && item.duration < config.minDuration) {
    return new RecommendFilterDecision(true, '时长达不到下限');
  }
  if (item.playKnown && item.playCount > -1 && item.playCount < config.minPlay) {
    return new RecommendFilterDecision(true, '播放量达不到下限');
  }
  if (config.minLikeRatio > 0 && item.playKnown && item.likeKnown &&
    item.playCount > -1 && item.likeCount > -1 &&
    item.likeCount * 100 < config.minLikeRatio * item.playCount) {
    return new RecommendFilterDecision(true, '点赞率达不到下限');
  }
  if (keywordMatches(item.title, config.titleRules)) {
    return new RecommendFilterDecision(true, '标题关键词命中');
  }
  if (keywordMatches(item.ownerName, config.upNameRules)) {
    return new RecommendFilterDecision(true, 'UP 名称关键词命中');
  }
  return new RecommendFilterDecision(false, '');
}

/**
 * 推荐项判定。
 *
 * 顺序：场景开关/分区关键词 > 显式屏蔽 > 白名单 > 已关注豁免 > 常规规则。
 * 屏蔽是用户最明确的负反馈，不能被“已关注”或白名单悄悄抬回来。
 */
export function evaluateRecommendItem(item: RecommendItem, scene: RecommendFilterScene,
  config: RecommendFilterConfig): RecommendFilterDecision {
  if (!config.enabled) return new RecommendFilterDecision(false, '');

  const whitelisted = isWhitelisted(item, config);
  const pgc = isPgcItem(item);

  // PGC 排行只按标题关键词过滤；番剧/影视没有 UP、时长、点赞率等可比字段。
  if (scene === RecommendFilterScene.Rank && pgc) {
    if (config.applyRank && keywordMatches(item.title, config.titleRules)) {
      return new RecommendFilterDecision(true, 'PGC 标题关键词命中');
    }
    return new RecommendFilterDecision(false, '');
  }

  // App 推荐的无权查看视频（如充电专属）；Web / 相关视频没有可靠 can_play。
  if (scene === RecommendFilterScene.HomeApp && !whitelisted && config.removeUnplayable &&
    item.canPlay >= 0 && item.canPlay !== 1) {
    return new RecommendFilterDecision(true, '无权查看');
  }

  // 分区关键词在 App 推荐、热门、排行中始终生效，即使完整过滤关闭。
  if ((scene === RecommendFilterScene.HomeApp || scene === RecommendFilterScene.Hot ||
    scene === RecommendFilterScene.Rank) && !whitelisted && !pgc && item.tname.length > 0 &&
    keywordMatches(item.tname, config.zoneRules)) {
    return new RecommendFilterDecision(true, '分区关键词命中');
  }

  if (scene === RecommendFilterScene.Related && !config.applyRelated) {
    return new RecommendFilterDecision(false, '');
  }
  if (scene === RecommendFilterScene.Hot && !config.applyHot) {
    return new RecommendFilterDecision(false, '');
  }
  if (scene === RecommendFilterScene.Rank && !config.applyRank) {
    return new RecommendFilterDecision(false, '');
  }

  if (isBlocked(item, config)) {
    return new RecommendFilterDecision(true, '推荐屏蔽用户');
  }
  if (whitelisted) {
    return new RecommendFilterDecision(false, '');
  }

  // 已关注豁免只作用于首页推荐；相关/热门/排行没有可靠的关注标记。
  if ((scene === RecommendFilterScene.HomeApp || scene === RecommendFilterScene.HomeWeb) &&
    item.isFollowed && config.exemptFollowed) {
    return new RecommendFilterDecision(false, '');
  }

  return matchesUserRules(item, config);
}

/**
 * 搜索结果只应用“屏蔽用户 + 标题关键词”，与推荐流完整过滤区分开。
 * 用户搜索把昵称当作标题文本匹配，视频/专栏用标题。
 */
export function evaluateSearchResult(kind: string, item: RecommendItem,
  config: RecommendFilterConfig): RecommendFilterDecision {
  if (!config.enabled || !config.applySearch) return new RecommendFilterDecision(false, '');
  if (isBlocked(item, config)) {
    return new RecommendFilterDecision(true, '搜索命中推荐屏蔽用户');
  }
  if (isWhitelisted(item, config)) {
    return new RecommendFilterDecision(false, '');
  }
  const text = kind === 'bili_user' ? item.ownerName : item.title;
  if (keywordMatches(text, config.titleRules)) {
    return new RecommendFilterDecision(true, '搜索标题关键词命中');
  }
  return new RecommendFilterDecision(false, '');
}
