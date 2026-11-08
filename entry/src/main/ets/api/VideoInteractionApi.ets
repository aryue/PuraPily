// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

import { http } from '@kit.NetworkKit';
import { getVideoDetail } from './BilibiliApi';
import { extractCsrfFromCookie, extractMidFromCookie } from './FeedbackService';
import { AppSign } from '../utils/SignUtils';
import { logWarn } from '../utils/Logger';
import { getLoginAccessKey } from '../utils/CredentialStore';
import { webInteractionCookie, WEB_INTERACTION_UA } from '../services/WebDeviceIdentity';

export interface VideoInteractionRequest {
  bvid: string;
  aid?: number;
  multiply?: number;
  type: 'like' | 'dislike' | 'coin' | 'favorite' | 'share' | 'triple';
  action: 'add' | 'cancel';
}

export interface TripleOutcome {
  like: boolean;
  coin: boolean;
  fav: boolean;
  multiply: number;
}

export interface VideoInteractionResult {
  success: boolean;
  message: string;
  triple?: TripleOutcome;
}

interface InteractionResponse {
  code: number;
  message?: string;
  data?: TripleOutcome;
}

interface FolderState { id: number; fav_state?: number; }
interface FolderList { code: number; data?: FolderListData; }
interface FolderListData { list?: FolderState[]; }

function encodeForm(params: Record<string, string>): string {
  return Object.keys(params).map((key: string): string =>
    `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
}

/** Mutation requests always use one captured account, and release their HTTP handle on errors. */
async function postInteraction(url: string, params: Record<string, string>, cookie: string,
  sessionCookie: string): Promise<InteractionResponse> {
  if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) {
    return { code: -101, message: '登录会话已变更，请重试' };
  }
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': url.startsWith('https://app.bilibili.com/') ?
          'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android_hd build/8430300' : WEB_INTERACTION_UA,
        'Origin': 'https://www.bilibili.com',
        'Referer': `https://www.bilibili.com/video/av${params['aid'] || ''}`,
        'Cookie': cookie
      },
      extraData: encodeForm(params), connectTimeout: 10000, readTimeout: 10000
    });
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) {
      return { code: -101, message: '登录会话已变更，请重试' };
    }
    if (response.responseCode !== 200) {
      return { code: response.responseCode, message: `请求失败（HTTP ${response.responseCode}）` };
    }
    const result = JSON.parse(response.result as string) as InteractionResponse;
    if (result.code !== 0) logWarn(`[互动接口] ${url.includes('app.bilibili.com') ? 'App' : 'Web'} ${url.substring(url.lastIndexOf('/') + 1)} code=${result.code}`);
    return result;
  } finally { request.destroy(); }
}

function resultOf(response: InteractionResponse, params: VideoInteractionRequest): VideoInteractionResult {
  const alreadyApplied = (params.type === 'like' && params.action === 'add' && response.code === 65006) ||
    (params.type === 'dislike' && response.code === (params.action === 'add' ? 65007 : 65005));
  if (response.code !== 0 && !alreadyApplied) {
    return { success: false, message: response.code === -101 ?
      (response.message || '登录已失效，请重新登录') :
      `${response.message && response.message !== '0' ? response.message : '操作失败'}（${response.code}）` };
  }
  if (params.type === 'triple') {
    if (!response.data || typeof response.data.like !== 'boolean' || typeof response.data.coin !== 'boolean' ||
      typeof response.data.fav !== 'boolean' || !Number.isInteger(response.data.multiply) ||
      response.data.multiply < 0 || response.data.multiply > 2) {
      return { success: false, message: '三连结果不完整，请重新进入视频确认状态' };
    }
    return { success: true, message: response.data.like && response.data.coin && response.data.fav ?
      '一键三连成功' : '三连已处理，部分项目未完成或此前已完成', triple: response.data };
  }
  return { success: true, message: '操作成功' };
}

async function favoriteFolders(mid: string, aid: number, cookie: string): Promise<FolderState[] | null> {
  const request = http.createHttp();
  try {
    const response = await request.request(
      `https://api.bilibili.com/x/v3/fav/folder/created/list-all?up_mid=${mid}&type=2&rid=${aid}`, {
        method: http.RequestMethod.GET,
        header: { 'Cookie': cookie, 'Referer': 'https://www.bilibili.com/', 'User-Agent': 'Mozilla/5.0' },
        connectTimeout: 10000, readTimeout: 10000
      });
    if (response.responseCode !== 200) return null;
    const result = JSON.parse(response.result as string) as FolderList;
    return result.code === 0 ? (result.data?.list || []) : null;
  } finally { request.destroy(); }
}

/** App like/dislike use 0=add, 1=cancel; Web like uses 1=add, 2=cancel. */
export async function sendVideoInteraction(params: VideoInteractionRequest, cookie: string): Promise<VideoInteractionResult> {
  const sessionCookie = AppStorage.get<string>('biliCookie') || '';
  const mid = extractMidFromCookie(sessionCookie);
  const csrf = extractCsrfFromCookie(sessionCookie);
  try {
    if (!sessionCookie) return { success: false, message: '请先登录' };
    if (params.type === 'coin' && (params.action !== 'add' ||
      ![1, 2].includes(params.multiply ?? 1))) return { success: false, message: '投币数量须为 1 或 2，投币不能取消' };
    let aid = params.aid || 0;
    if (!aid && /^[1-9][0-9]*$/.test(params.bvid)) aid = Number(params.bvid);
    if (!aid && /^BV[0-9A-Za-z]{10}$/.test(params.bvid)) aid = (await getVideoDetail(params.bvid))?.aid || 0;
    if (!Number.isSafeInteger(aid) || aid <= 0) return { success: false, message: '未获取到有效的视频编号，请稍后重试' };

    let accessKey = '';
    try { accessKey = await getLoginAccessKey(sessionCookie); }
    catch (_) { return { success: false, message: '客户端令牌暂不可读取，请解锁设备后重试' }; }
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) {
      return { success: false, message: '登录会话已变更，请重试' };
    }
    if (params.type === 'dislike' && !accessKey) {
      logWarn(`[互动鉴权] 客户端令牌缺失，安全存储状态=${AppStorage.get<string>('biliClientCredentialState') || 'unknown'}`);
      return { success: false, message: '当前会话缺少客户端令牌，请到“我的 → 补充 TV 授权”完成授权后再点不喜欢' };
    }
    if (accessKey && (params.type === 'like' || params.type === 'coin' || params.type === 'dislike')) {
      const appParams: Record<string, string> = {
        'aid': String(aid), 'access_key': accessKey, 'ts': String(Math.floor(Date.now() / 1000)),
        'mobi_app': 'android_hd', 'platform': 'android'
      };
      if (params.type === 'coin') {
        appParams['multiply'] = String(params.multiply ?? 1);
        appParams['select_like'] = '0';
      } else appParams[params.type] = params.action === 'add' ? '0' : '1';
      await AppSign.signParams(appParams, 'android_hd');
      const path = params.type === 'coin' ? 'coin/add' : params.type;
      const response = await postInteraction(`https://app.bilibili.com/x/v2/view/${path}`, appParams, cookie, sessionCookie);
      // Only an explicit authentication rejection permits a Web fallback. Never repeat a coin after a timeout.
      if (params.type === 'dislike' || (response.code !== -101 && response.code !== -3)) return resultOf(response, params);
      if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) return resultOf(response, params);
    }
    if (!csrf || mid === '0') return { success: false, message: '登录凭据不完整，请重新登录' };
    cookie = await webInteractionCookie(sessionCookie);
    if (sessionCookie !== (AppStorage.get<string>('biliCookie') || '')) {
      return { success: false, message: '登录会话已变更，请重试' };
    }
    let webParams: Record<string, string> = { 'aid': String(aid), 'csrf': csrf };
    let path = '';
    if (params.type === 'like') {
      path = '/x/web-interface/archive/like'; webParams['like'] = params.action === 'add' ? '1' : '2';
    } else if (params.type === 'coin') {
      path = '/x/web-interface/coin/add'; webParams['multiply'] = String(params.multiply ?? 1); webParams['select_like'] = '0';
    } else if (params.type === 'triple') {
      path = '/x/web-interface/archive/like/triple';
    } else if (params.type === 'favorite') {
      const folders = await favoriteFolders(mid, aid, cookie);
      if (!folders) return { success: false, message: '读取收藏夹失败，请稍后重试' };
      const selected = params.action === 'add' ? folders.slice(0, 1) : folders.filter((folder: FolderState): boolean => folder.fav_state === 1);
      if (selected.length === 0) return { success: false, message: params.action === 'add' ? '请先创建收藏夹' : '未找到该视频所在的收藏夹，请刷新后重试' };
      path = '/x/v3/fav/resource/batch-deal';
      webParams = { 'resources': `${aid}:2`, 'csrf': csrf };
      webParams[params.action === 'add' ? 'add_media_ids' : 'del_media_ids'] = selected.map((folder: FolderState): string => String(folder.id)).join(',');
    } else if (params.type === 'share') path = '/x/web-interface/share/add';
    else return { success: false, message: '不支持的操作' };
    return resultOf(await postInteraction(`https://api.bilibili.com${path}`, webParams, cookie, sessionCookie), params);
  } catch (error) {
    logWarn(`[互动] ${params.type}请求异常`);
    return { success: false, message: '请求未完成，请检查网络；请刷新状态后再重试' };
  }
}
