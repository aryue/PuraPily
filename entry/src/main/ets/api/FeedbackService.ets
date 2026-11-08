// 部分实现基于 yunshang-bili (https://github.com/chunwcc/yunshang-bili) 修改
// Copyright (c) 2026 chunwcc
// SPDX-License-Identifier: MIT

/**
 * B站用户反馈服务
 * 
 * 核心功能：
 * 1. X-Bili-Mid 请求头 - 用户身份识别
 * 2. 不感兴趣反馈 - 训练推荐模型
 * 3. CSRF Token 提取
 */
import { http } from '@kit.NetworkKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { getVideoDetail, refreshAccessKeyFromCookie } from './BilibiliApi';
import { AppSign } from '../utils/SignUtils';
import { getLoginAccessKey } from '../utils/CredentialStore';

// ========== 类型定义 ==========

export interface FeedbackResult {
  success: boolean;
  message: string;
}

export interface DislikeReason {
  id: number;
  name: string;
}

// 预定义的不感兴趣原因
export const DISLIKE_REASONS: DislikeReason[] = [
  { id: 1, name: '不感兴趣' },
  { id: 2, name: '内容质量差' },
  { id: 3, name: '重复内容' },
  { id: 4, name: '封面与内容不符' },
  { id: 5, name: 'UP主不感兴趣' },
  { id: 6, name: '分区不感兴趣' }
];

// ========== 用户身份工具 ==========

/**
 * 从 Cookie 中提取 DedeUserID（用户 mid）
 * 格式: DedeUserID=123456789
 */
export function extractMidFromCookie(cookie: string): string {
  if (!cookie) return '0';
  
  // 匹配 DedeUserID=xxx
  const match = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)(?:;|$)/);
  if (match && match[1]) {
    return match[1];
  }
  
  return '0';
}

/**
 * 从 Cookie 中提取 CSRF Token（bili_jct）
 * 格式: bili_jct=xxxxxxxx
 */
export function extractCsrfFromCookie(cookie: string): string {
  if (!cookie) return '';
  
  // 匹配 bili_jct=xxx
  const match = cookie.match(/(?:^|;\s*)bili_jct=([a-fA-F0-9]+)(?:;|$)/);
  if (match && match[1]) {
    return match[1];
  }
  
  return '';
}

/**
 * 从 Cookie 中提取 SESSDATA
 */
export function extractSessdataFromCookie(cookie: string): string {
  if (!cookie) return '';
  
  const match = cookie.match(/SESSDATA=([^;]+)/);
  if (match && match[1]) {
    return match[1];
  }
  
  return '';
}

/**
 * 获取完整的请求头（包含用户身份）
 * ⭐ 关键：X-Bili-Mid 是服务器识别用户的关键
 */
export function getBiliHeaders(): Record<string, string> {
  const cookie = AppStorage.get<string>('biliCookie') || '';
  const mid = extractMidFromCookie(cookie);
  
  const headers: Record<string, string> = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
    'Referer': 'https://www.bilibili.com/',
    'Origin': 'https://www.bilibili.com',
    'Cookie': cookie
  };
  
  // ⭐ 关键：添加用户身份标识
  if (mid !== '0') {
    headers['X-Bili-Mid'] = mid;
    logInfo(`[BiliHeaders] 用户身份: mid=${mid}`);
  } else {
    logWarn('[BiliHeaders] 未检测到登录用户，推荐可能不精准');
  }
  
  return headers;
}

// ========== 用户反馈服务 ==========

export class FeedbackService {
  private static instance: FeedbackService | null = null;
  
  // 已反馈的视频缓存（避免重复提交）
  private feedbackCache: Set<string> = new Set();
  private feedbackSession: string = '';
  private feedbackPending: Map<string, Promise<FeedbackResult>> = new Map();
  
  static getInstance(): FeedbackService {
    if (!FeedbackService.instance) {
      FeedbackService.instance = new FeedbackService();
    }
    return FeedbackService.instance;
  }
  
  /**
   * 提交"不感兴趣"反馈
   * ⭐ 这是训练推荐模型的关键数据
   * 
   * @param bvid 视频ID
   * @param reasonId 原因ID（1-6）
   */
  async sendDislike(bvid: string, reasonId: number = 1): Promise<FeedbackResult> {
    return this.submitFeedback(bvid, reasonId, '');
  }

  async sendDislikeUp(bvid: string, uploaderMid: string): Promise<FeedbackResult> {
    if (!/^[1-9][0-9]*$/.test(uploaderMid)) return { success: false, message: '无效的UP主编号' };
    return this.submitFeedback(bvid, 5, uploaderMid);
  }

  private async submitFeedback(bvid: string, reasonId: number, uploaderMid: string): Promise<FeedbackResult> {
    const session = AppStorage.get<string>('biliCookie') || '';
    if (session !== this.feedbackSession) {
      this.feedbackCache.clear();
      this.feedbackPending.clear();
      this.feedbackSession = session;
    }
    if (!session || extractMidFromCookie(session) === '0') return { success: false, message: '请先登录' };
    if ((!/^BV[0-9A-Za-z]{10}$/.test(bvid) &&
      !(/^[1-9][0-9]*$/.test(bvid) && Number.isSafeInteger(Number(bvid)))) ||
      !Number.isSafeInteger(reasonId) || reasonId <= 0) return { success: false, message: '无效的反馈参数' };
    const key = `${bvid}:${reasonId}:${uploaderMid}`;
    if (this.feedbackCache.has(key)) return { success: true, message: '已反馈过' };
    const pending = this.feedbackPending.get(key);
    if (pending) return pending;
    const request = this.requestFeedback(bvid, reasonId, uploaderMid, session);
    this.feedbackPending.set(key, request);
    try {
      const result = await request;
      if (session !== (AppStorage.get<string>('biliCookie') || '')) return { success: false, message: '登录会话已变更' };
      if (result.success) this.feedbackCache.add(key);
      return result;
    } finally {
      if (this.feedbackPending.get(key) === request) this.feedbackPending.delete(key);
    }
  }

  private async requestFeedback(bvid: string, reasonId: number, uploaderMid: string,
    session: string): Promise<FeedbackResult> {
    const request = http.createHttp();
    try {
      const aid = /^[1-9][0-9]*$/.test(bvid) ? Number(bvid) : (await getVideoDetail(bvid))?.aid || 0;
      if (!Number.isSafeInteger(aid) || aid <= 0) return { success: false, message: '未获取到有效的视频编号' };
      const accessKey = await getLoginAccessKey(session) || await refreshAccessKeyFromCookie();
      if (session !== (AppStorage.get<string>('biliCookie') || '')) return { success: false, message: '登录会话已变更' };
      // Web 登录不保证能换取 App 凭据；失效的 Web feed-back 接口不能充当成功回退。
      if (!accessKey) return { success: false, message: '服务器反馈需要客户端登录凭据，请使用 TV 扫码登录；本地操作仍可生效' };
      const params: Record<string, string> = {
        'access_key': accessKey, 'goto': 'av', 'id': String(aid),
        'reason_id': String(reasonId), 'build': '1', 'mobi_app': 'android_hd',
        'platform': 'android', 'ts': String(Math.floor(Date.now() / 1000))
      };
      if (uploaderMid) params['rmid'] = uploaderMid;
      await AppSign.signParams(params, 'android_hd');
      if (session !== (AppStorage.get<string>('biliCookie') || '')) return { success: false, message: '登录会话已变更' };
      const query = Object.keys(params).map((key: string): string =>
        `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`).join('&');
      const response = await request.request(`https://app.bilibili.com/x/feed/dislike?${query}`, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/', 'Cookie': session },
        connectTimeout: 10000, readTimeout: 10000
      });
      if (response.responseCode !== 200) return { success: false, message: `服务器反馈失败（HTTP ${response.responseCode}）` };
      const json = JSON.parse(response.result as string) as Record<string, Object>;
      if (json['code'] === 0) return { success: true, message: uploaderMid ? '已减少该UP主的推荐' : '已减少此类推荐' };
      logWarn(`[Feedback] code=${json['code']}, message=${json['message']}`);
      return { success: false, message: `${json['message'] || '服务器反馈失败'}（${json['code']}）` };
    } catch (error) {
      logWarn('[Feedback] 推荐反馈请求未完成');
      return { success: false, message: '服务器反馈未完成，请检查网络后重试' };
    } finally { request.destroy(); }
  }

  /**
   * 提交视频观看反馈（用于训练推荐模型）
   * 
   * @param bvid 视频ID
   * @param progress 观看进度（0-100）
   * @param duration 观看时长（秒）
   */
  async sendWatchFeedback(bvid: string, progress: number, duration: number): Promise<void> {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const mid = extractMidFromCookie(cookie);
    
    if (mid === '0') return;  // 未登录不发送
    
    try {
      // 观看进度反馈（可选）
      // 这个接口帮助推荐系统理解用户的观看偏好
      logInfo(`[Feedback] 观看反馈: bvid=${bvid}, progress=${progress}%, duration=${duration}s`);
      
      // 实际项目中可以调用相关接口上报观看行为
      
    } catch (err) {
      logError(`[Feedback] 观看反馈异常: ${err}`);
    }
  }
  
  /**
   * 清除反馈缓存
   */
  clearCache(): void {
    this.feedbackCache.clear();
    this.feedbackPending.clear();
    this.feedbackSession = '';
  }
}

// ========== 便捷导出函数 ==========

/**
 * 提交UP主不感兴趣反馈
 */
export async function sendDislikeUpFeedback(bvid: string, mid: string): Promise<FeedbackResult> {
  return FeedbackService.getInstance().sendDislikeUp(bvid, mid);
}

/**
 * 提交不感兴趣反馈
 */
export async function sendDislikeFeedback(bvid: string, reasonId: number = 1): Promise<FeedbackResult> {
  return FeedbackService.getInstance().sendDislike(bvid, reasonId);
}
