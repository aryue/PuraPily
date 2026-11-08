import { sendDislikeFeedback, sendDislikeUpFeedback } from '../api/FeedbackService';
import { blacklistUploader } from '../api/BilibiliApi';
import { UserBehaviorService } from './UserBehaviorService';

export type VideoFeedbackAction = '不感兴趣' | '屏蔽UP主' | '拉黑UP主' | '看过类似';

/** Feedback is shared by card layouts; archive/season/live identities must not be mixed. */
export class VideoCardFeedback {
  private static pending: Set<string> = new Set<string>();
  static actions(bvid: string, ownerMid: string): VideoFeedbackAction[] {
    // App feeds use decimal AV ids; Web feeds use BV ids. Both identify archives.
    const bv = /^BV[0-9A-Za-z]{10}$/.test(bvid);
    const av = /^[1-9][0-9]*$/.test(bvid) && Number.isSafeInteger(Number(bvid));
    if (!bv && !av) return [];
    return /^[1-9][0-9]*$/.test(ownerMid)
      ? ['不感兴趣', '屏蔽UP主', '拉黑UP主', '看过类似'] : ['不感兴趣', '看过类似'];
  }

  static isDismissed(bvid: string, ownerMid: string): boolean {
    const dismissed = AppStorage.get<Set<string>>('cardFeedbackDismissedVideos');
    return !!bvid && (!!dismissed?.has(bvid) ||
      (!!ownerMid && UserBehaviorService.isBlockedUploader(ownerMid)));
  }

  private static publish(): void {
    AppStorage.setOrCreate('cardFeedbackRevision', (AppStorage.get<number>('cardFeedbackRevision') ?? 0) + 1);
  }

  private static dismiss(bvid: string): void {
    const dismissed = new Set(AppStorage.get<Set<string>>('cardFeedbackDismissedVideos') ?? []);
    dismissed.add(bvid);
    if (dismissed.size > 1000) dismissed.delete(dismissed.values().next().value);
    AppStorage.setOrCreate('cardFeedbackDismissedVideos', dismissed);
    UserBehaviorService.addWatchedVideo(bvid);
    VideoCardFeedback.publish();
  }

  static async perform(action: VideoFeedbackAction, bvid: string, ownerMid: string): Promise<string> {
    const key = `${action}:${bvid}:${ownerMid}`;
    if (VideoCardFeedback.pending.has(key)) return '正在处理，请稍候';
    VideoCardFeedback.pending.add(key);
    try { return await VideoCardFeedback.performAction(action, bvid, ownerMid); }
    finally { VideoCardFeedback.pending.delete(key); }
  }

  private static async performAction(action: VideoFeedbackAction, bvid: string, ownerMid: string): Promise<string> {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    if (!VideoCardFeedback.actions(bvid, ownerMid).includes(action)) return '该内容不支持此操作';
    if (action === '看过类似') {
      VideoCardFeedback.dismiss(bvid);
      return '已标记为看过';
    }
    if (action === '不感兴趣') {
      VideoCardFeedback.dismiss(bvid);
      try {
        const result = await sendDislikeFeedback(bvid, 1);
        return result.success ? '已减少此类推荐' : '已本地移除，服务器反馈暂不可用';
      } catch (_) { return '已本地移除，服务器反馈暂不可用'; }
    }
    if (action === '屏蔽UP主') {
      UserBehaviorService.addBlockedUploader(ownerMid);
      VideoCardFeedback.publish();
      try {
        const result = await sendDislikeUpFeedback(bvid, ownerMid);
        return result.success ? '已屏蔽该UP主' : '已本地屏蔽该UP主';
      } catch (_) { return '已本地屏蔽该UP主'; }
    }
    try {
      if (await blacklistUploader(Number(ownerMid))) {
        if (cookie !== (AppStorage.get<string>('biliCookie') || '')) return '登录会话已变更，请重试';
        UserBehaviorService.addBlockedUploader(ownerMid);
        VideoCardFeedback.publish();
        return '已拉黑该UP主';
      }
    } catch (_) { }
    return '拉黑失败，请检查登录状态';
  }
}
