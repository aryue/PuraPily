import { getRelatedVideos } from '../api/BilibiliApi';
import { RecommendItem } from '../model/RecommendItem';
import { logError } from '../utils/Logger';
import { VideoCardFeedback } from './VideoCardFeedback';

interface RelatedVideoCacheEntry {
  items: RecommendItem[];
  at: number;
}

const RELATED_CACHE_TTL: number = 5 * 60 * 1000;
const RELATED_CACHE_LIMIT: number = 32;

export class PlaybackRelatedVideos {
  private requestVersion: number = 0;
  /**
   * 相关推荐是独立的 JSON 请求，和取流/播放地址无关。
   * 缓存它可以在二次进入、相关推荐页返回时直接出卡，不重复等 RTT。
   */
  private static cache: Map<string, RelatedVideoCacheEntry> = new Map();
  private static cacheOrder: string[] = [];
  /** 同一 bvid 的并发 load 复用同一个请求，避免页面重建时重复打接口。 */
  private static inflight: Map<string, Promise<RecommendItem[] | null>> = new Map();

  visible(items: RecommendItem[]): RecommendItem[] {
    return items.filter((item: RecommendItem) => !VideoCardFeedback.isDismissed(item.id, item.ownerMid));
  }

  async load(bvid: string, current: () => boolean): Promise<RecommendItem[] | null> {
    if (!bvid) return null;
    const cached = PlaybackRelatedVideos.cache.get(bvid);
    if (cached !== undefined && Date.now() - cached.at < RELATED_CACHE_TTL) {
      return current() ? this.visible(cached.items) : null;
    }
    const request = ++this.requestVersion;
    let task = PlaybackRelatedVideos.inflight.get(bvid);
    if (task === undefined) {
      task = this.fetchAndCache(bvid);
      PlaybackRelatedVideos.inflight.set(bvid, task);
      task.then(() => {
        if (PlaybackRelatedVideos.inflight.get(bvid) === task) {
          PlaybackRelatedVideos.inflight.delete(bvid);
        }
      }).catch(() => {
        if (PlaybackRelatedVideos.inflight.get(bvid) === task) {
          PlaybackRelatedVideos.inflight.delete(bvid);
        }
      });
    }
    const items = await task;
    if (items !== null) {
      if (!PlaybackRelatedVideos.cache.has(bvid)) PlaybackRelatedVideos.cacheOrder.push(bvid);
      PlaybackRelatedVideos.cache.set(bvid, { items: items, at: Date.now() });
      while (PlaybackRelatedVideos.cacheOrder.length > RELATED_CACHE_LIMIT) {
        const oldest = PlaybackRelatedVideos.cacheOrder.shift();
        if (oldest !== undefined) PlaybackRelatedVideos.cache.delete(oldest);
      }
    }
    if (request !== this.requestVersion || !current()) return null;
    if (items === null) {
      logError('[RelatedVideos] 获取相关视频失败');
      return [];
    }
    return this.visible(items);
  }

  private async fetchAndCache(bvid: string): Promise<RecommendItem[] | null> {
    try {
      return await getRelatedVideos(bvid);
    } catch (_error) {
      return null;
    }
  }
}
