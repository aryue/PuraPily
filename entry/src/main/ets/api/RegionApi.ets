// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

/**
 * RegionApi.ets — 分类（分区排行榜）API
 *
 * 数据源：/x/web-interface/ranking/v2?rid=X（无需登录）
 * 分区列表为 B 站主分区硬编码（rid 稳定不变）
 */
import { http } from '@kit.NetworkKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { RecommendItem } from '../model/RecommendItem';
import { fetchPgcSeasonsByParams } from './PgcApi';

// ==================== 接口定义 ====================

/** 分区 Tab */
export interface RegionTab {
  rid: number;
  name: string;
  seasonType?: number;
  rankingRid?: number;
}

/** B 站主分区列表（rid 为官方稳定值） */
export const REGION_TABS: RegionTab[] = [
  { rid: 0, name: '全站' },
  { rid: -1, name: '番剧', seasonType: 1 },
  { rid: -4, name: '国创', seasonType: 4 },
  { rid: 1, name: '动画', rankingRid: 1005 },
  { rid: 3, name: '音乐', rankingRid: 1003 },
  { rid: 129, name: '舞蹈', rankingRid: 1004 },
  { rid: 4, name: '游戏', rankingRid: 1008 },
  { rid: 36, name: '知识', rankingRid: 1010 },
  { rid: 188, name: '科技', rankingRid: 1012 },
  { rid: 234, name: '运动', rankingRid: 1018 },
  { rid: 223, name: '汽车', rankingRid: 1013 },
  { rid: 211, name: '美食', rankingRid: 1020 },
  { rid: 217, name: '动物', rankingRid: 1024 },
  { rid: 119, name: '鬼畜', rankingRid: 1007 },
  { rid: 155, name: '时尚', rankingRid: 1014 },
  { rid: 5, name: '娱乐', rankingRid: 1002 },
  { rid: 181, name: '影视', rankingRid: 1001 },
  { rid: -3, name: '纪录', seasonType: 3 },
  { rid: -2, name: '电影', seasonType: 2 },
  { rid: -5, name: '剧集', seasonType: 5 },
  { rid: -7, name: '综艺', seasonType: 7 }
];

export async function fetchRegionContent(rid: number, page: number = 1): Promise<RecommendItem[]> {
  const region = REGION_TABS.find(item => item.rid === rid);
  if (!region) throw new Error('未知分区');
  if (!region.seasonType) return page === 1 ? fetchRegionRanking(region.rankingRid ?? rid) : [];
  const seasons = await fetchPgcSeasonsByParams(region.seasonType, page, 30, { 'type': '1', 'order': '2' });
  return seasons.filter(season => season.seasonType === region.seasonType).map(season => {
    const item = new RecommendItem();
    item.id = `ss${season.seasonId}`;
    item.pgcSeasonId = season.seasonId;
    item.pgcEpId = season.epId;
    item.title = season.title;
    item.coverUrl = season.cover;
    item.ownerName = season.indexShow;
    item.rcmdReason = season.score ? `${season.score} 分` : season.badge;
    return item;
  });
}

// ==================== 常量和请求头 ====================

const WEB_BASE = 'https://api.bilibili.com';

function getHeaders(): Record<string, string> {
  const cookie = AppStorage.get<string>('biliCookie') || '';
  return {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Xiaomi13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36 BiliApp/6770600',
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Cookie': cookie || 'buvid3=undefined; b_nut=100; PVID=1'
  };
}

// ==================== API 方法 ====================

/**
 * 获取分区排行榜视频（ranking/v2）
 * @param rid 分区 id（0=全站，其余见 REGION_TABS）
 */
export async function fetchRegionRanking(rid: number = 0): Promise<RecommendItem[]> {
  const httpRequest = http.createHttp();
  try {
    const url = `${WEB_BASE}/x/web-interface/ranking/v2?rid=${rid}&type=all`;
    logInfo(`[RegionApi] 请求分区排行: rid=${rid}`);

    const response = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: getHeaders(),
      connectTimeout: 10000,
      readTimeout: 10000
    });

    if (response.responseCode !== 200) {
      logWarn(`[RegionApi] HTTP ${response.responseCode}`);
      return [];
    }

    const body = JSON.parse(response.result as string) as Record<string, Object>;
    if (body['code'] !== 0) {
      logWarn(`[RegionApi] API错误: code=${body['code']}, msg=${body['message']}`);
      return [];
    }

    const data = body['data'] as Record<string, Object> || {};
    const rawList = data['list'] as Array<Record<string, Object>> || [];

    return rawList.map((item: Record<string, Object>): RecommendItem => {
      const rec = new RecommendItem();
      rec.id = (item['bvid'] as string) || '';
      rec.aid = Number(item['aid'] ?? 0);
      rec.title = (item['title'] as string) || '';
      const pic = item['pic'] as string;
      rec.coverUrl = pic ? (pic.startsWith('http') ? pic : `https:${pic}`) : '';
      rec.duration = Number(item['duration'] ?? 0);
      rec.pubdate = Number(item['pubdate'] ?? 0);

      const stat = item['stat'] as Record<string, number> || {};
      rec.playCount = stat['view'] || 0;
      rec.danmakuCount = stat['danmaku'] || 0;
      rec.likeCount = stat['like'] || 0;

      const owner = item['owner'] as Record<string, Object> || {};
      rec.ownerName = (owner['name'] as string) || '';
      rec.ownerFace = (owner['face'] as string) || '';
      rec.ownerMid = owner['mid'] ? String(owner['mid']) : '';

      return rec;
    });
  } catch (err) {
    logError(`[RegionApi] 异常: ${err}`);
    return [];
  } finally {
    httpRequest.destroy();
  }
}
