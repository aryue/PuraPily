import { logInfo, logWarn } from '../utils/Logger';
import { WatchHistoryHelper } from '../model/WatchHistoryHelper';
import { WatchHistoryItem } from '../model/WatchHistoryItem';

export interface PlaybackHistoryRecord {
  aid: number;
  cid: number;
  bvid: string;
  title: string;
  coverUrl?: string;
  ownerName?: string;
  progress: number;
  duration: number;
  epId: number;
  seasonId: number;
}

export interface PgcProgressReport {
  cookie: string;
  epId: number;
  watchTime: number;
  minimumProgress: number;
  current: () => boolean;
  ensureContext: () => Promise<boolean>;
  record: (progress: number) => PlaybackHistoryRecord;
}

export interface PlaybackHistorySave {
  cookie: string;
  record: PlaybackHistoryRecord;
  force: boolean;
  completed: boolean;
  minimumProgress: number;
  reportEpisode?: (progress: number) => Promise<void>;
}

/** Page-scoped reporting cadence shared by successive players. */
export class PlaybackProgressReporter {
  private savedAt: number = 0;
  private liveViewTimer: number = -1;
  private heartbeatTimer: number = -1;
  private lastHeartbeatTime: number = 0;
  private lastCloudPushAt: number = 0;
  private pgcQueue: Promise<void> = Promise.resolve();

  private acceptCloudPush(force: boolean): boolean {
    const now = Date.now();
    if (!force && now - this.lastCloudPushAt < 3000) return false;
    this.lastCloudPushAt = now;
    return true;
  }

  async saveHistory(request: PlaybackHistorySave): Promise<void> {
    const entry = request.record;
    const episode = request.reportEpisode;
    if ((!entry.bvid && !episode) || !Number.isFinite(entry.progress) ||
      entry.progress < request.minimumProgress || !this.acceptCloudPush(request.force)) return;
    if (!request.cookie) {
      logWarn('[saveWatchHistory] 用户未登录，无法保存观看历史');
      return;
    }
    const progress = request.completed ? -1 : Math.floor(entry.progress);
    if (episode) {
      await episode(progress);
      return;
    }
    if (entry.aid <= 0) {
      logWarn('[saveWatchHistory] 缺少aid，无法上报到B站');
      return;
    }
    await this.upload(request.cookie, entry, progress);
  }

  enqueuePgc(upload: () => Promise<void>): Promise<void> {
    const task = this.pgcQueue.then(upload);
    this.pgcQueue = task.catch(() => {});
    return task;
  }

  reportPgc(report: PgcProgressReport): Promise<void> {
    const played = report.watchTime === -1 ? -1 : Math.max(0, Math.floor(report.watchTime));
    if (!report.cookie || report.epId <= 0 || !Number.isFinite(played) ||
      (played !== -1 && played < report.minimumProgress)) return Promise.resolve();
    return this.enqueuePgc(async () => {
      if (!report.current()) return;
      const ready = await report.ensureContext();
      if (!report.current()) return;
      if (!ready) {
        logWarn(`[心跳] PGC 上报无法取得 seasonId (epId=${report.epId})`);
        return;
      }
      const record = report.record(played);
      if (record.aid <= 0 || record.cid <= 0 || record.seasonId <= 0 || record.epId !== report.epId) {
        logWarn(`[心跳] PGC 上报缺少分集身份 (aid=${record.aid}, cid=${record.cid}, epId=${report.epId})`);
        return;
      }
      await this.upload(report.cookie, record);
    });
  }

  private upload(cookie: string, record: PlaybackHistoryRecord, progress: number = record.progress): Promise<void> {
    const item = new WatchHistoryItem();
    item.aid = record.aid;
    item.cid = record.cid;
    item.bvid = record.bvid;
    item.title = record.title;
    item.coverUrl = record.coverUrl ?? '';
    item.ownerName = record.ownerName ?? '';
    item.playProgress = progress;
    item.totalDuration = record.duration;
    item.watchedAt = Math.floor(Date.now() / 1000);
    item.epId = record.epId;
    item.seasonId = record.seasonId;
    const helper = WatchHistoryHelper.getInstance();
    helper.setCookie(cookie);
    return helper.saveWatchRecord(item);
  }

  startHeartbeat(report: () => void): void {
    if (this.heartbeatTimer !== -1) return;
    this.heartbeatTimer = setInterval(report, 15000);
    logInfo('[心跳] 已启动心跳定时器，间隔15秒');
  }

  stopHeartbeat(): void {
    if (this.heartbeatTimer === -1) return;
    clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = -1;
    logInfo('[心跳] 已停止心跳定时器');
  }

  acceptHeartbeat(progress: number): boolean {
    if (Math.abs(progress - this.lastHeartbeatTime) < 5) return false;
    this.lastHeartbeatTime = progress;
    return true;
  }

  resetHeartbeat(): void {
    this.lastHeartbeatTime = 0;
  }

  sample(saveLocal: () => void, updateLiveView: (() => void) | null): void {
    const now = Date.now();
    if (now - this.savedAt >= 2000) {
      this.savedAt = now;
      saveLocal();
    }
    if (updateLiveView && this.liveViewTimer === -1) {
      this.liveViewTimer = setTimeout(() => {
        this.liveViewTimer = -1;
        updateLiveView();
      }, 5000);
    }
  }

  cancel(): void {
    clearTimeout(this.liveViewTimer);
    this.liveViewTimer = -1;
  }
}
