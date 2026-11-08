/**
 * 用户行为上报服务
 * 用于向B站推荐系统反馈用户行为，优化推荐结果
 * 
 * ⭐ 这是实现个性化推荐的关键！
 * B站推荐算法依赖用户行为数据来优化推荐内容
 * 
 * 实现的API：
 * 1. 观看心跳 - /x/report/web/heartbeat（影响推荐权重最大）
 * 2. 互动上报 - 点赞、投币、收藏、分享
 * 3. 推荐反馈 - 不感兴趣、屏蔽UP主
 */
import { http } from '@kit.NetworkKit';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { RecommendItem } from '../model/RecommendItem';
import { extractMidFromCookie, extractCsrfFromCookie, sendDislikeFeedback, sendDislikeUpFeedback } from '../api/FeedbackService';
import { sendVideoInteraction, VideoInteractionResult, VideoInteractionRequest } from '../api/VideoInteractionApi';
import { MIN_HEARTBEAT_PROGRESS_SEC } from '../model/WatchHistoryHelper';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

// ========== 类型定义 ==========

export interface WatchBehavior {
  bvid: string;
  cid: number;
  duration: number;      // 视频总时长（秒）
  watchTime: number;     // 实际观看时长（秒）
  progress: number;      // 观看进度 (0-100)
}

export type InteractionBehavior = VideoInteractionRequest;

export interface FeedbackBehavior {
  bvid: string;
  reason: 'not_interested' | 'seen_before' | 'block_uploader' | 'inappropriate';
  uploaderMid?: string;
  tagName?: string;
}

// 内部接口定义
interface WatchReportData {
  bvid: string;
  cid: number;
  mid: string;
  duration: number;
  watch_time: number;
  progress: number;
  ts: number;
  is_finish: number;
  is_effective: number;
  watch_type: string;
}


interface FeedbackReportData {
  goto: string;
  id: string;
  mid: string;
  reason: string;
  rmid: string;
  tag_name: string;
  ts: number;
}

// ⭐ 内部方法参数接口（替代内联对象类型）
interface HeartbeatParams {
  bvid: string;
  cid: number;
  csrf: string;
  played_time: number;
  type: number;  // 3=普通视频, 4=课程等
}


interface FeedbackReportParams {
  bvid: string;
  mid: string;
  csrf: string;
  reason: string;
  uploaderMid?: string;
}

/**
 * ⭐ 辅助函数：构建 URL 编码字符串
 * 替代 URLSearchParams（鸿蒙不支持）
 */
function buildUrlEncoded(params: Record<string, string>): string {
  const parts: string[] = [];
  const keys = Object.keys(params);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    const value = params[key];
    parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
  }
  return parts.join('&');
}

/** Preserve the login Cookie exactly; Web mutations obtain a stable server-issued device ID centrally. */
function buildEnhancedCookie(): string {
  return AppStorage.get<string>('biliCookie') || '';
}

export class UserBehaviorService {
  
  // ========== 观看行为上报 ==========
  
  /**
   * 上报视频播放行为
   * ⭐ 这是最重要的行为数据，直接影响推荐
   * 
   * @param params 观看行为参数
   */
  static async reportWatchBehavior(params: WatchBehavior): Promise<void> {
    try {
      // 使用当前登录会话；不随机改写设备 Cookie
      const cookie = buildEnhancedCookie();
      const mid = extractMidFromCookie(cookie);
      const csrf = extractCsrfFromCookie(cookie);
      
      // 判断观看质量
      const isEffective = params.progress >= 30;  // 观看30%以上算有效观看
      const isFinished = params.progress >= 90;   // 观看90%以上算看完
      
      // 构建上报数据
      const reportData: WatchReportData = {
        bvid: params.bvid,
        cid: params.cid,
        mid: mid,
        duration: params.duration,
        watch_time: params.watchTime,
        progress: params.progress,
        ts: Math.floor(Date.now() / 1000),
        
        // ⭐ 关键指标
        is_finish: isFinished ? 1 : 0,
        is_effective: isEffective ? 1 : 0,
        watch_type: isFinished ? 'finish' : (isEffective ? 'effective' : 'quick')
      };
      
      logInfo(`[行为上报] 观看: ${params.bvid}, 进度=${params.progress}%, 时长=${params.watchTime}s, 类型=${reportData.watch_type}`);
      
      // ⭐ 调用B站真实的心跳上报API（参考 bilibili-API-collect 规范）
      const heartbeatParams: HeartbeatParams = {
        bvid: params.bvid,
        cid: params.cid,
        csrf: csrf,
        played_time: Math.floor(params.watchTime),
        type: 3  // 普通视频
      };
      const success = await UserBehaviorService.sendWatchHeartbeat(heartbeatParams);
      
      if (success) {
        logInfo(`[行为上报] ✅ 心跳上报成功: ${params.bvid}`);
      } else {
        logWarn(`[行为上报] ⚠️ 心跳上报失败，已本地记录`);
      }
      
      // 本地记录（用于调试和离线缓存）
      UserBehaviorService.saveLocalBehavior('watch', reportData);
      
    } catch (err) {
      logError(`观看行为上报失败: ${err}`);
    }
  }
  
  /**
   * ⭐ 发送观看心跳到B站服务器
   * 使用 /x/click-interface/web/heartbeat 端点（bilibili-API-collect 规范）
   * 这是影响推荐算法最关键的API
   */
  private static async sendWatchHeartbeat(params: HeartbeatParams): Promise<boolean> {
    // ⭐ 近 0 秒不上报：本方法打的是 /x/click-interface/web/heartbeat（与历史进度同一接口），
    //   played_time 会**直接覆盖**该视频已有的观看进度。快速划过/打开即退出时 played_time 为 0，
    //   照发就会把"原本看过几分钟"的那个视频抹成 0%（B 站侧实测同样会落库，不是静默忽略）。
    if (params.played_time < MIN_HEARTBEAT_PROGRESS_SEC) {
      logInfo(`[行为上报] 进度仅 ${params.played_time}s（<${MIN_HEARTBEAT_PROGRESS_SEC}s），`
        + `跳过心跳以免覆盖已有进度: ${params.bvid}`);
      return false;
    }
    try {
      const httpRequest = http.createHttp();
      // 使用当前登录会话；不随机改写设备 Cookie
      const cookie = buildEnhancedCookie();

      // ⭐ 构造心跳参数（参考 PiliPlus / bilibili-API-collect）
      // csrf 仅登录用户有，匿名用户不发送
      const heartbeatData: Record<string, string> = {
        'bvid': params.bvid,
        'cid': String(params.cid),
        'played_time': String(params.played_time),
        'type': String(params.type)
      };
      if (params.csrf) {
        heartbeatData['csrf'] = params.csrf;
      }

      const response = await httpRequest.request(
        'https://api.bilibili.com/x/click-interface/web/heartbeat',
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': `https://www.bilibili.com/video/${params.bvid}`,
            'Cookie': cookie
          },
          extraData: buildUrlEncoded(heartbeatData),
          connectTimeout: 10000,
          readTimeout: 10000
        }
      );

      httpRequest.destroy();

      if (response.responseCode === 200) {
        const json = JSON.parse(response.result as string) as Record<string, Object>;
        if (json['code'] === 0) {
          return true;
        } else {
          logWarn(`[心跳] 返回错误: code=${json['code']}, msg=${json['message']}`);
          return false;
        }
      }

      return false;
    } catch (err) {
      logError(`[心跳] 请求异常: ${err}`);
      return false;
    }
  }
  
  /**
   * 批量上报观看历史
   * 用于应用启动时同步观看历史
   */
  static async reportWatchHistory(historyList: WatchBehavior[]): Promise<void> {
    try {
      logInfo(`[行为上报] 批量上报观看历史: ${historyList.length} 条`);
      
      for (const item of historyList) {
        await UserBehaviorService.reportWatchBehavior(item);
        // 避免请求过快
        await new Promise<void>(resolve => setTimeout(resolve, 100));
      }
      
    } catch (err) {
      logError(`批量上报失败: ${err}`);
    }
  }
  
  // ========== 互动行为上报 ==========
  
  /**
   * 上报互动行为（点赞、投币、收藏、分享）
   * ⭐ 这些行为权重很高，显著影响推荐
   */
  static async reportInteraction(params: InteractionBehavior): Promise<boolean> {
    return (await UserBehaviorService.performInteraction(params)).success;
  }

  static async performInteraction(params: InteractionBehavior): Promise<VideoInteractionResult> {
    const result = await sendVideoInteraction(params, buildEnhancedCookie());
    logInfo(`[互动] ${params.type} ${params.action}: ${result.success ? '成功' : result.message}`);
    if (!result.success) logWarn(`[互动] ${params.type} ${params.action}失败: ${result.message}`);
    return result;
  }

  static async reportFeedback(params: FeedbackBehavior): Promise<void> {
    try {
      const cookie = AppStorage.get<string>('biliCookie') || '';
      const mid = extractMidFromCookie(cookie);
      const csrf = extractCsrfFromCookie(cookie);
      
      logInfo(`[反馈上报] ${params.bvid}, 原因=${params.reason}, UP主=${params.uploaderMid || '无'}`);
      
      // ⭐ 调用B站真实的推荐反馈API
      const feedbackParams: FeedbackReportParams = {
        bvid: params.bvid,
        mid: mid,
        csrf: csrf,
        reason: params.reason,
        uploaderMid: params.uploaderMid
      };
      const success = await UserBehaviorService.sendFeedbackReport(feedbackParams);
      
      if (success) {
        logInfo(`[反馈上报] ✅ 反馈上报成功`);
      } else {
        logWarn(`[反馈上报] ⚠️ 反馈上报失败`);
      }
      
      // 本地记录（用于调试）
      const localFeedbackData: FeedbackReportData = {
        goto: 'av',
        id: params.bvid,
        mid: mid,
        reason: UserBehaviorService.mapReason(params.reason),
        rmid: params.uploaderMid || '',
        tag_name: params.tagName || '',
        ts: Math.floor(Date.now() / 1000)
      };
      UserBehaviorService.saveLocalBehavior('feedback', localFeedbackData);
      
      // 本地记录屏蔽的UP主
      if (params.reason === 'block_uploader' && params.uploaderMid) {
        UserBehaviorService.addBlockedUploader(params.uploaderMid);
      }
      
    } catch (err) {
      logError(`反馈上报失败: ${err}`);
    }
  }
  
  private static async sendFeedbackReport(params: FeedbackReportParams): Promise<boolean> {
    // 推荐反馈统一走 FeedbackService，避免两份接口参数及失效 Web 回退逻辑漂移。
    if (params.reason === 'block_uploader' && params.uploaderMid) {
      return (await sendDislikeUpFeedback(params.bvid, params.uploaderMid)).success;
    }
    return (await sendDislikeFeedback(params.bvid, Number(UserBehaviorService.mapReason(params.reason)))).success;
  }

  // ========== 本地过滤管理 ==========
  
  /**
   * 添加已观看视频
   */
  static addWatchedVideo(bvid: string): void {
    let watched = AppStorage.get<Set<string>>('watchedVideos') || new Set<string>();
    watched.add(bvid);
    
    // 限制大小，防止内存过大
    if (watched.size > 1000) {
      const arr = Array.from(watched);
      watched = new Set(arr.slice(-1000));
    }
    
    AppStorage.setOrCreate('watchedVideos', watched);
  }
  
  /**
   * 检查是否已观看
   */
  static isWatched(bvid: string): boolean {
    const watched = AppStorage.get<Set<string>>('watchedVideos') || new Set<string>();
    return watched.has(bvid);
  }
  
  /**
   * 添加屏蔽UP主
   * ⭐ 同时保存到持久化存储
   */
  static addBlockedUploader(mid: string): void {
    let blocked = AppStorage.get<Set<string>>('blockedUploaders') || new Set<string>();
    blocked.add(mid);
    AppStorage.setOrCreate('blockedUploaders', blocked);
    AppStorage.setOrCreate('cardFeedbackRevision', (AppStorage.get<number>('cardFeedbackRevision') ?? 0) + 1);
    logInfo(`[屏蔽] 已屏蔽UP主: ${mid}`);
    
    // ⭐ 异步保存到持久化存储
    UserBehaviorService.saveBlockedUploaders();
  }
  
  /**
   * ⭐ 保存屏蔽UP主列表到持久化存储
   */
  static async saveBlockedUploaders(): Promise<void> {
    try {
      const blocked = AppStorage.get<Set<string>>('blockedUploaders') || new Set<string>();
      const blockedArray = Array.from(blocked);
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        logWarn('[屏蔽] 无法获取context，跳过保存');
        return;
      }
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('blockedUploaders', JSON.stringify(blockedArray));
      await pref.flush();
      logInfo(`[屏蔽] 已保存 ${blockedArray.length} 个屏蔽UP主到持久化存储`);
    } catch (err) {
      logError(`[屏蔽] 保存失败: ${err}`);
    }
  }
  
  /**
   * 移除屏蔽UP主
   */
  static removeBlockedUploader(mid: string): void {
    let blocked = AppStorage.get<Set<string>>('blockedUploaders') || new Set<string>();
    blocked.delete(mid);
    AppStorage.setOrCreate('blockedUploaders', blocked);
    AppStorage.setOrCreate('cardFeedbackRevision', (AppStorage.get<number>('cardFeedbackRevision') ?? 0) + 1);
    logInfo(`[屏蔽] 已取消屏蔽UP主: ${mid}`);
    UserBehaviorService.saveBlockedUploaders();
  }

  /**
   * ⭐ 从持久化存储加载屏蔽UP主列表（应用启动时调用）
   */
  static async loadBlockedUploaders(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        logWarn('[屏蔽] 无法获取context，跳过加载');
        return;
      }
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      const stored = await pref.get('blockedUploaders', '') as string;
      if (stored) {
        const blockedArray: string[] = JSON.parse(stored) as string[];
        const blocked = new Set<string>(blockedArray);
        AppStorage.setOrCreate('blockedUploaders', blocked);
        logInfo(`[屏蔽] 已从持久化存储加载 ${blocked.size} 个屏蔽UP主`);
      } else {
        logInfo('[屏蔽] 持久化存储中无屏蔽UP主数据');
      }
    } catch (err) {
      logError(`[屏蔽] 加载失败: ${err}`);
    }
  }
  
  /**
   * 检查UP主是否被屏蔽
   */
  static isBlockedUploader(mid: string): boolean {
    const blocked = AppStorage.get<Set<string>>('blockedUploaders') || new Set<string>();
    return blocked.has(mid);
  }
  
  /**
   * 仅过滤屏蔽UP主（不过滤已观看）
   * ⭐ DiscoverPage 使用此方法，只屏蔽UP主，不屏蔽已看视频
   */
  static filterBlockedUploadersOnly(items: RecommendItem[]): RecommendItem[] {
    const originalCount = items.length;
    let blockedFiltered = 0;

    const result = items.filter((item: RecommendItem): boolean => {
      // 只过滤屏蔽UP主，不过滤已观看
      if (item.ownerMid && UserBehaviorService.isBlockedUploader(item.ownerMid)) {
        blockedFiltered++;
        logInfo(`[本地屏蔽] 过滤掉屏蔽UP主的视频: ${item.title?.substring(0, 20)}... (mid: ${item.ownerMid})`);
        return false;
      }

      return true;
    });

    if (blockedFiltered > 0) {
      logInfo(`[本地过滤] 原始${originalCount}条 → 过滤屏蔽UP主${blockedFiltered}条 → 剩余${result.length}条`);
    }

    return result;
  }

  /**
   * 过滤推荐列表
   * 移除已观看和屏蔽的视频
   * ⭐ 添加详细日志便于调试
   */
  static filterRecommendList(items: RecommendItem[]): RecommendItem[] {
    const originalCount = items.length;
    let watchedFiltered = 0;
    let blockedFiltered = 0;
    
    const result = items.filter((item: RecommendItem): boolean => {
      // 过滤已观看
      if (UserBehaviorService.isWatched(item.id)) {
        watchedFiltered++;
        return false;
      }
      
      // 过滤屏蔽UP主
      if (item.ownerMid && UserBehaviorService.isBlockedUploader(item.ownerMid)) {
        blockedFiltered++;
        logInfo(`[本地屏蔽] 过滤掉屏蔽UP主的视频: ${item.title?.substring(0, 20)}... (mid: ${item.ownerMid})`);
        return false;
      }
      
      return true;
    });
    
    // 输出过滤统计
    if (watchedFiltered > 0 || blockedFiltered > 0) {
      logInfo(`[本地过滤] 原始${originalCount}条 → 过滤已观看${watchedFiltered}条、屏蔽UP主${blockedFiltered}条 → 剩余${result.length}条`);
    }
    
    return result;
  }
  
  // ========== 辅助方法 ==========
  
  private static mapReason(reason: string): string {
    const reasonMap: Record<string, string> = {
      'not_interested': '1',
      'seen_before': '2',
      'block_uploader': '3',
      'inappropriate': '4'
    };
    return reasonMap[reason] || '1';
  }
  
  private static saveLocalBehavior(type: string, data: Object): void {
    try {
      const key = `behavior_${type}_${Date.now()}`;
      // 简单的本地记录，用于调试
      logInfo(`[本地记录] ${key}: ${JSON.stringify(data)}`);
    } catch (err) {
      logError(`本地记录失败: ${err}`);
    }
  }
}

// ========== 导出便捷方法 ==========

/**
 * 上报观看行为
 */
export async function reportWatch(bvid: string, cid: number, duration: number, watchTime: number): Promise<void> {
  const progress = duration > 0 ? Math.floor((watchTime / duration) * 100) : 0;
  await UserBehaviorService.reportWatchBehavior({
    bvid,
    cid,
    duration,
    watchTime,
    progress
  });
  
  // 标记为已观看
  UserBehaviorService.addWatchedVideo(bvid);
}

/**
 * 上报点赞
 */
export async function reportLike(bvid: string, aid: number, isLike: boolean): Promise<void> {
  await UserBehaviorService.reportInteraction({
    bvid,
    aid,
    type: 'like',
    action: isLike ? 'add' : 'cancel'
  });
}

/**
 * 上报投币
 */
export async function reportCoin(bvid: string, aid: number, isCoin: boolean, multiply: number = 1): Promise<void> {
  await UserBehaviorService.reportInteraction({
    bvid,
    aid,
    multiply,
    type: 'coin',
    action: isCoin ? 'add' : 'cancel'
  });
}

/**
 * 上报收藏
 */
export async function reportFavorite(bvid: string, isFavorite: boolean): Promise<void> {
  await UserBehaviorService.reportInteraction({
    bvid,
    type: 'favorite',
    action: isFavorite ? 'add' : 'cancel'
  });
}

/**
 * 上报分享
 */
export async function reportShare(bvid: string): Promise<void> {
  await UserBehaviorService.reportInteraction({
    bvid,
    type: 'share',
    action: 'add'
  });
}

/**
 * 上报不感兴趣
 */
export async function reportNotInterested(bvid: string, uploaderMid?: string): Promise<void> {
  await UserBehaviorService.reportFeedback({
    bvid,
    reason: 'not_interested',
    uploaderMid
  });
}

/**
 * 上报屏蔽UP主
 */
export async function reportBlockUploader(bvid: string, uploaderMid: string): Promise<void> {
  await UserBehaviorService.reportFeedback({
    bvid,
    reason: 'block_uploader',
    uploaderMid
  });
}
