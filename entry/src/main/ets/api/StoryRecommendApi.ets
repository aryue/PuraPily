// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

import { http } from '@kit.NetworkKit';
import { RecommendItem } from '../model/RecommendItem';
import { logInfo, logWarn } from '../utils/Logger';
import { getRecommendVideos } from './BilibiliApi';
import { hasLoginSession } from '../utils/LoginCookie';
import { AppSign } from '../utils/SignUtils';

interface StoryResponse {
  code: number;
  data?: StoryData;
}

interface StoryData { items?: Array<Record<string, Object>> }

/** 连续刷视频专用 Story 接口。分页/去重由播放会话持有，不共享首页状态。 */
export async function getStoryRecommendVideos(displayId: number, sessionId: string): Promise<RecommendItem[]> {
  const cookie = AppStorage.get<string>('biliCookie') || '';
  const accessKey = AppStorage.get<string>('biliAccessKey') || '';
  // App Story cannot be assumed to authenticate a Web Cookie. Keep the caller's
  // independent cursor while using the source that understands this login.
  if (!accessKey && hasLoginSession(cookie)) return getRecommendVideos(displayId, 20);
  const request = http.createHttp();
  try {
    const params: Record<string, string> = {
      'display_id': displayId.toString(), 'mobi_app': 'android',
      'platform': 'android', 'build': '8130300'
    };
    if (accessKey) {
      params['access_key'] = accessKey;
      params['ts'] = Math.floor(Date.now() / 1000).toString();
      await AppSign.signParams(params, 'android_hd');
    }
    const query = Object.keys(params).map((key: string) =>
      `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
    const response = await request.request(
      `https://app.bilibili.com/x/v2/feed/index/story?${query}`, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://www.bilibili.com/',
          'Cookie': cookie,
          'app-key': 'android_hd',
          'session_id': sessionId
        },
        connectTimeout: 10000,
        readTimeout: 10000
      });
    if (response.responseCode !== 200) {
      logWarn(`[Story推荐] HTTP ${response.responseCode}`);
      return hasLoginSession(cookie) ? getRecommendVideos(displayId, 20) : [];
    }
    const data: StoryResponse = JSON.parse(response.result as string);
    if (data.code !== 0) {
      logWarn(`[Story推荐] code=${data.code}`);
      return hasLoginSession(cookie) ? getRecommendVideos(displayId, 20) : [];
    }
    const items = data.data?.items || [];
    const blocked = AppStorage.get<Set<string>>('blockedUploaders') || new Set<string>();
    const result: RecommendItem[] = [];
    let portraitCount = 0;
    let landscapeCount = 0;
    for (const raw of items) {
      const type = (raw['goto'] as string) || (raw['card_goto'] as string) || '';
      if ((type !== 'av' && type !== 'vertical_av') || raw['ad_info']) continue;
      const dimension = raw['dimension'] as Record<string, number>;
      const item = RecommendItem.fromPopularApi(raw);
      const player = raw['player_args'] as Record<string, Object>;
      item.aid = Number(raw['aid'] || player?.['aid'] || 0);
      item.cid = player ? Number(player['cid'] || 0) : item.cid;
      item.coverUrl = (raw['cover'] as string) || item.coverUrl;
      item.cardGoto = type;
      if (item.id.startsWith('BV') && item.cid > 0 && !blocked.has(item.ownerMid)) {
        result.push(item);
        // 宽高仅用于验收统计，不作为推荐过滤条件；缺少尺寸也正常接收。
        if (dimension) {
          const rotated = Math.abs(dimension['rotate'] || 0) % 180 === 90;
          const width = rotated ? dimension['height'] : dimension['width'];
          const height = rotated ? dimension['width'] : dimension['height'];
          if (width > 0 && height > width) portraitCount++;
          else if (height > 0 && width >= height) landscapeCount++;
        }
      }
    }
    logInfo(`[Story推荐] display_id=${displayId} received=${items.length} accepted=${result.length} portrait=${portraitCount} landscape=${landscapeCount} first=${result[0]?.id ?? ''}`);
    return result;
  } catch (error) {
    logWarn('[Story推荐] 请求失败', error);
    return hasLoginSession(cookie) ? getRecommendVideos(displayId, 20) : [];
  } finally { request.destroy(); }
}
