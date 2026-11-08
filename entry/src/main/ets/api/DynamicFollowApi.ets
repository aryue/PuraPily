// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

import { http } from '@kit.NetworkKit';
import { extractMidFromCookie } from './FeedbackService';
import { logInfo, logWarn } from '../utils/Logger';

export interface DynamicFollowShow {
  season_id: number;
  title: string;
  cover: string;
  new_ep?: DynamicFollowEpisode;
}
interface DynamicFollowEpisode {
  index_show?: string;
  cover?: string;
}
interface DynamicFollowResponse {
  code: number;
  data?: DynamicFollowData;
}
interface DynamicFollowData {
  list?: DynamicFollowShow[];
}

/** 读取当前账号实际追番/追剧；无订阅或请求失败时不伪造推荐内容。 */
export async function getDynamicFollowShows(cookie: string, fetchAll: boolean = false): Promise<DynamicFollowShow[]> {
  const mid = extractMidFromCookie(cookie);
  if (!mid) return [];
  const requests = [1, 2].map(async (type: number): Promise<DynamicFollowShow[]> => {
    const request = http.createHttp();
    const shows: DynamicFollowShow[] = [];
    try {
      let page = 1;
      do {
        const result = await request.request(
          `https://api.bilibili.com/x/space/bangumi/follow/list?vmid=${mid}&type=${type}&pn=${page}&ps=20`, {
            method: http.RequestMethod.GET,
            header: { 'Cookie': cookie, 'Referer': 'https://www.bilibili.com/',
              'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json' },
            connectTimeout: 10000, readTimeout: 10000
          });
        if (result.responseCode !== 200) return shows;
        const body = JSON.parse(result.result as string) as DynamicFollowResponse;
        if (body.code !== 0) {
          logWarn(`[DynamicFollow] type=${type}, code=${body.code}`);
          return shows;
        }
        const items = (body.data?.list ?? []).filter((item: DynamicFollowShow) => item.season_id > 0 && !!item.title && !!item.cover);
        logInfo(`[DynamicFollow] type=${type}, items=${items.length}`);
        const previousCount = shows.length;
        for (const item of items) {
          if (!shows.some((show: DynamicFollowShow) => show.season_id === item.season_id)) shows.push(item);
        }
        if (!fetchAll || (body.data?.list?.length ?? 0) < 20 || shows.length === previousCount) break;
        page++;
      } while (true);
      return shows;
    } catch (_) {
      logWarn(`[DynamicFollow] type=${type}, request failed`);
      return shows;
    } finally {
      request.destroy();
    }
  });
  const pages = await Promise.all(requests);
  const shows: DynamicFollowShow[] = [];
  for (const page of pages) {
    for (const show of page) {
      if (!shows.some((item: DynamicFollowShow) => item.season_id === show.season_id)) shows.push(show);
    }
  }
  return shows;
}
