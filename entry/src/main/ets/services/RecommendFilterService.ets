import { RecommendItem } from '../model/RecommendItem';
import {
  RecommendFilterDecision,
  RecommendFilterScene,
  evaluateRecommendItem,
  evaluateSearchResult
} from '../model/RecommendFilterModel';
import { RecommendFilterSettings } from './RecommendFilterSettings';
import { logInfo } from '../utils/Logger';

/** 推荐流 / 相关 / 热门 / 排行 / 搜索的统一过滤入口。 */
export class RecommendFilterService {
  static shouldDrop(item: RecommendItem, scene: RecommendFilterScene): RecommendFilterDecision {
    return evaluateRecommendItem(item, scene, RecommendFilterSettings.config());
  }

  static filterList(items: RecommendItem[], scene: RecommendFilterScene, tag: string = ''): RecommendItem[] {
    const config = RecommendFilterSettings.config();
    if (!config.enabled) return items;
    const result: RecommendItem[] = [];
    const reasons = new Map<string, number>();
    for (let i = 0; i < items.length; i++) {
      const decision = evaluateRecommendItem(items[i], scene, config);
      if (decision.drop) {
        reasons.set(decision.reason, (reasons.get(decision.reason) ?? 0) + 1);
      } else {
        result.push(items[i]);
      }
    }
    if (result.length !== items.length) {
      const detail: string[] = [];
      reasons.forEach((count: number, reason: string) => detail.push(`${reason}×${count}`));
      logInfo(`[推荐过滤] ${tag || scene} ${items.length}→${result.length}（${detail.join('，')}）`);
    }
    return result;
  }

  /** 搜索只应用屏蔽用户 + 标题关键词；tab 决定标题用视频/专栏标题还是用户昵称。 */
  static filterSearchResults(items: RecommendItem[], searchKind: string,
    tag: string = ''): RecommendItem[] {
    const config = RecommendFilterSettings.config();
    if (!config.enabled || !config.applySearch) return items;
    if (searchKind !== 'video' && searchKind !== 'article' && searchKind !== 'bili_user') {
      return items;
    }
    const result: RecommendItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const decision = evaluateSearchResult(searchKind, items[i], config);
      if (!decision.drop) result.push(items[i]);
    }
    if (result.length !== items.length) {
      logInfo(`[推荐过滤] 搜索(${tag || searchKind}) ${items.length}→${result.length}`);
    }
    return result;
  }

  static isBlockedUser(mid: string): boolean {
    return mid.length > 0 && RecommendFilterSettings.config().blockedMids.has(mid);
  }

  static isWhitelistedUser(mid: string): boolean {
    return mid.length > 0 && RecommendFilterSettings.config().whitelistMids.has(mid);
  }
}
