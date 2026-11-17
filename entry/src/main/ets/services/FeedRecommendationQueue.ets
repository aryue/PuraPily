import { getStoryRecommendVideos } from '../api/StoryRecommendApi';
import { RecommendItem } from '../model/RecommendItem';
import { logInfo } from '../utils/Logger';
import { ContinuousRecommendationState } from './ContinuousRecommendationState';
import { VideoCardFeedback } from './VideoCardFeedback';

/** Recommendations accumulated by a single player page. */
export class FeedRecommendationQueue {
  items: RecommendItem[] = [];
  private job: Promise<boolean> | null = null;
  private sessionId: string = `${Date.now().toString(16)}${Math.random().toString(16).substring(2, 10)}`;

  /** Only the caller that publishes a batch gets true and schedules prefetch. */
  async append(isAlive: () => boolean): Promise<boolean> {
    if (this.job) {
      await this.job;
      return false;
    }
    const job = this.fetchNextPages(isAlive);
    this.job = job;
    try {
      return await job;
    } finally {
      if (this.job === job) this.job = null;
    }
  }

  private async fetchNextPages(isAlive: () => boolean): Promise<boolean> {
    const account = ContinuousRecommendationState.account();
    const history = ContinuousRecommendationState.syncRecentHistory(account);
    const seen = new Set<string>();
    for (const item of this.items) {
      seen.add(item.id);
      if (item.aid > 0) seen.add(item.aid.toString());
    }
    const added: RecommendItem[] = [];
    // Story 每页较少；最多连续取三页，空页也推进，避免反复拿同一页。
    for (let page = 0; page < 3 && added.length < 4; page++) {
      const index = ContinuousRecommendationState.reservePage(account);
      const batches = await Promise.all([getStoryRecommendVideos(index, this.sessionId), history]);
      const recommended = batches[0];
      if (!isAlive() || account !== ContinuousRecommendationState.account()) return false;
      const excluded = ContinuousRecommendationState.excluded(account);
      for (const item of recommended) {
        if (ContinuousRecommendationState.isExcluded(item, seen) ||
          ContinuousRecommendationState.isExcluded(item, excluded) ||
          VideoCardFeedback.isDismissed(item.id, item.ownerMid) ||
          (item.aid > 0 && VideoCardFeedback.isDismissed(item.aid.toString(), item.ownerMid))) continue;
        seen.add(item.id);
        if (item.aid > 0) seen.add(item.aid.toString());
        added.push(item);
      }
    }
    this.items = [...this.items, ...added];
    logInfo(`[ReferenceFeed] independent recommendations added=${added.length} total=${this.items.length}`);
    return true;
  }
}
