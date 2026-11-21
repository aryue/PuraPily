import { http } from '@kit.NetworkKit';
import { errMsg, logInfo, logWarn } from '../utils/Logger';
import { SponsorBlockPrefs } from '../utils/SponsorBlockPrefs';
import {
  ClipInfoItem,
  SkipMode,
  SkipSegment,
  SponsorBlockItem,
  skipCategoryIndex,
  skipCategoryMeta
} from '../model/SkipSegment';

class SegmentCacheEntry {
  readonly at: number;
  readonly segments: SkipSegment[];

  constructor(at: number, segments: SkipSegment[]) {
    this.at = at;
    this.segments = segments;
  }
}

/**
 * SponsorBlock 客户端 + 番剧官方片段解析。
 *
 * 约定：
 * - 外部一律使用毫秒；只在请求/响应边界做秒 ↔ 毫秒换算；
 * - 请求失败永远返回空数组，绝不阻塞播放；
 * - 不向第三方服务器携带 B 站 Cookie。
 */
export class SponsorBlockService {
  private static readonly CACHE_TTL_MS: number = 10 * 60 * 1000;
  private static readonly cache: Map<string, SegmentCacheEntry> = new Map();
  private static readonly inflight: Map<string, Promise<SkipSegment[]>> = new Map();

  static async fetchSegments(bvid: string, cid: number): Promise<SkipSegment[]> {
    if (!SponsorBlockPrefs.enabled() || !bvid || cid <= 0 || /^\d+$/.test(bvid)) {
      return [];
    }
    const key = `${bvid}:${cid}`;
    const cached = SponsorBlockService.cache.get(key);
    if (cached && Date.now() - cached.at < SponsorBlockService.CACHE_TTL_MS) {
      return SponsorBlockService.clone(cached.segments);
    }
    const pending = SponsorBlockService.inflight.get(key);
    if (pending) return pending;
    const task = SponsorBlockService.requestSegments(bvid, cid)
      .then((segments: SkipSegment[]): SkipSegment[] => {
        // 空结果可能是一次限流/超时，不缓存，避免十分钟内不再重试。
        if (segments.length > 0) {
          SponsorBlockService.cache.set(key, new SegmentCacheEntry(Date.now(),
            SponsorBlockService.clone(segments)));
        }
        return segments;
      })
      .catch((error: Object): SkipSegment[] => {
        logWarn(`[SponsorBlock] 获取片段失败 ${key}: ${errMsg(error)}`);
        return [];
      })
      .finally(() => {
        SponsorBlockService.inflight.delete(key);
      });
    SponsorBlockService.inflight.set(key, task);
    return task;
  }

  /** 番剧 playurl 的 clip_info_list：OP/ED → intro/outro，其余按赞助处理。 */
  static fromClipInfo(list: ClipInfoItem[], mode: SkipMode): SkipSegment[] {
    const result: SkipSegment[] = [];
    if (mode === SkipMode.Disable || list.length === 0) return result;
    for (const item of list) {
      const start = item.start;
      const end = item.end;
      if (typeof start !== 'number' || typeof end !== 'number' ||
        !Number.isFinite(start) || !Number.isFinite(end) || end < start) {
        continue;
      }
      let category = 'sponsor';
      if (item.clipType === 'CLIP_TYPE_OP') category = 'intro';
      else if (item.clipType === 'CLIP_TYPE_ED') category = 'outro';
      result.push(new SkipSegment(Math.round(start * 1000), Math.round(end * 1000),
        category, mode, '', true));
    }
    return result;
  }

  static segmentLabel(segment: SkipSegment): string {
    return skipCategoryMeta(segment.category).shortTitle;
  }

  /** 缓存存模板，调用方拿独立对象：skipped 等播放态不能跨视频共享。 */
  private static clone(list: SkipSegment[]): SkipSegment[] {
    return list.map((item: SkipSegment): SkipSegment => new SkipSegment(
      item.startMs, item.endMs, item.category, item.mode, item.uuid, item.official));
  }

  private static async requestSegments(bvid: string, cid: number): Promise<SkipSegment[]> {
    const server = SponsorBlockPrefs.server();
    const url = `${server}/api/skipSegments?videoID=${encodeURIComponent(bvid)}&cid=${cid}`;
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'PuraPily/1.0 (HarmonyOS)'
        },
        connectTimeout: 6000,
        readTimeout: 6000
      });
      if (response.responseCode === 404) return [];
      if (response.responseCode !== 200) {
        logWarn(`[SponsorBlock] HTTP ${response.responseCode}: ${bvid}/${cid}`);
        return [];
      }
      const list = JSON.parse(response.result as string) as SponsorBlockItem[];
      if (!Array.isArray(list)) return [];
      const segments: SkipSegment[] = [];
      const minMs = SponsorBlockPrefs.minSegmentMs();
      for (const item of list) {
        const category = item.category;
        const rawSegment = item.segment;
        if (category === undefined || rawSegment === undefined || rawSegment.length < 2) continue;
        const categoryIndex = skipCategoryIndex(category);
        if (categoryIndex < 0) continue;
        let mode = SponsorBlockPrefs.categoryMode(categoryIndex);
        if (mode === SkipMode.Disable) continue;
        const rawStart = rawSegment[0];
        const rawEnd = rawSegment[1];
        if (!Number.isFinite(rawStart) || !Number.isFinite(rawEnd) || rawEnd < rawStart) continue;
        const startMs = Math.round(rawStart * 1000);
        const endMs = Math.round(rawEnd * 1000);
        // 零长度 = 时间点标记；短于阈值的片段也不自动跳。
        if (startMs === endMs || (minMs > 0 && endMs - startMs < minMs)) {
          mode = SkipMode.Show;
        }
        segments.push(new SkipSegment(startMs, endMs, category, mode, item.UUID ?? '', false));
      }
      logInfo(`[SponsorBlock] ${bvid}/${cid} 片段 ${segments.length} 条`);
      return segments;
    } finally {
      request.destroy();
    }
  }
}
