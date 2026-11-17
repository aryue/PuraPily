import { getRelatedVideos } from '../api/BilibiliApi';
import { RecommendItem } from '../model/RecommendItem';
import { logError } from '../utils/Logger';
import { VideoCardFeedback } from './VideoCardFeedback';

export class PlaybackRelatedVideos {
  private requestVersion: number = 0;

  visible(items: RecommendItem[]): RecommendItem[] {
    return items.filter((item: RecommendItem) => !VideoCardFeedback.isDismissed(item.id, item.ownerMid));
  }

  async load(bvid: string, current: () => boolean): Promise<RecommendItem[] | null> {
    const request = ++this.requestVersion;
    try {
      const items = await getRelatedVideos(bvid);
      if (request !== this.requestVersion || !current()) return null;
      return this.visible(items);
    } catch (error) {
      if (request !== this.requestVersion || !current()) return null;
      logError(`[RelatedVideos] 获取相关视频失败: ${error}`);
      return [];
    }
  }
}
