import { NetworkGate } from '../utils/NetworkGate';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getVideoDetail, getVideoPlayUrl, PlayUrlResult } from '../api/BilibiliApi';
import { IjkPrewarm } from './IjkPrewarm';
import { IjkWarmPool } from './IjkWarmPool';
import { RecommendItem } from '../model/RecommendItem';
import { PlaybackProgress } from '../utils/PlaybackProgress';

interface PlaybackListJob {
  item: RecommendItem;
  key: string;
  qn: number;
  credential: string;
}

/** Small-list address preparation, independent of Surfaces, decoders and media downloads. */
export class PlaybackListPrefetch {
  private items: RecommendItem[] = [];
  /** 预热实例应该对准窗口里的第几项：由页面按「首个可见卡片」算出来传进来。 */
  private warmIndex: number = 0;
  private qn: number = 116;
  private credential: string = '';
  private epoch: number = 0;
  private pending: PlaybackListJob[] = [];
  private wanted: Set<string> = new Set();
  private running: Set<string> = new Set();
  private completed: Set<string> = new Set();
  private sources: Map<string, PlayUrlResult> = new Map();
  private timer: number = -1;
  private enabled: () => boolean;

  constructor(enabled: () => boolean = () => true) { this.enabled = enabled; }

  update(items: RecommendItem[], qn: number, warmIndex: number = -1): void {
    if (warmIndex >= 0) this.warmIndex = warmIndex;
    if (!this.enabled() || !NetworkGate.allowsBoundedPrefix()) { this.pause(); return; }
    const credential = AppStorage.get<string>('biliCookie') || '';
    if (credential !== this.credential || qn !== this.qn) { this.completed.clear(); this.sources.clear(); this.epoch++; }
    this.credential = credential;
    this.qn = qn;
    const unique = new Set<string>();
    this.items = items.filter((item: RecommendItem) => {
      if (item.pgcEpId > 0 || item.pgcSeasonId > 0 || !/^(BV[0-9A-Za-z]+|[0-9]+)$/.test(item.id)) return false;
      const key = `${item.id}:${item.cid || 0}`;
      if (unique.has(key)) return false;
      unique.add(key);
      return true;
    }).slice(0, 8);
    this.wanted.clear();
    this.pending = [];
    for (const item of this.items) {
      const key = `${this.epoch}:${qn}:${item.id}:${item.cid || 0}`;
      this.wanted.add(key);
      if (!this.running.has(key) && !this.completed.has(key)) this.pending.push({ item, key, qn, credential });
    }
    this.completed.forEach((key: string) => { if (!this.wanted.has(key)) this.completed.delete(key); });
    this.sources.forEach((_source: PlayUrlResult, key: string) => { if (!this.wanted.has(key)) this.sources.delete(key); });
    this.prepareVisiblePrefixes();
    if (this.timer === -1 && this.items.length > 0) {
      // API cache lasts 60s. Recheck every 10s and renew entries older than 40s.
      this.timer = setInterval(() => {
        if ((AppStorage.get<string>('biliCookie') || '') !== this.credential) { this.pause(); return; }
        this.completed.clear();
        this.update(this.items, this.qn);
      }, 10000);
    }
    if (this.items.length === 0) this.pause();
    this.pump();
  }

  pause(): void {
    this.epoch++;
    if (this.timer !== -1) clearInterval(this.timer);
    this.timer = -1;
    this.items = [];
    this.sources.clear();
    this.pending = [];
    this.wanted.clear();
    this.completed.clear();
  }

  private current(job: PlaybackListJob): boolean {
    return this.enabled() && NetworkGate.allowsBoundedPrefix() && this.wanted.has(job.key) && this.qn === job.qn &&
      this.credential === job.credential && (AppStorage.get<string>('biliCookie') || '') === job.credential;
  }

  private pump(): void {
    while (this.running.size < 2 && this.pending.length > 0) {
      const job = this.pending.shift()!;
      if (!this.current(job) || this.running.has(job.key) || this.completed.has(job.key)) continue;
      this.running.add(job.key);
      this.prepare(job).finally(() => {
        this.running.delete(job.key);
        this.pump();
      });
    }
  }

  /**
   * 本地续播点（秒）：与播放页共用同一套存储，列表阶段就能知道该预热哪一段。
   * ⚠️ 卡片 id 可能是 aid、播放页存的 key 却是 bvid，精确 key 查不到时按 cid 兜底，
   *    否则预热永远按 0 秒准备，接管后还得 seek（真机实测首帧 125ms → 1031ms）。
   */
  private resumeSec(item: RecommendItem): number {
    let local: number = PlaybackProgress.current(item.id, item.cid || 0);
    if (local < 0) local = PlaybackProgress.currentByCid(item.cid || 0);
    return local > 0 ? local : 0;
  }

  private prepareVisiblePrefixes(): void {
    if (!this.enabled() || !NetworkGate.allowsBoundedPrefix()) return;
    // 实例池槽数（默认 1）：槽数大于 1 时把后面几张可见卡也准备到首帧。
    const slots: number = IjkWarmPool.get().capacity();
    const span: number = Math.max(2, slots);
    for (let i = this.warmIndex; i < Math.min(this.items.length, this.warmIndex + span); i++) {
      const item = this.items[i];
      const key = `${this.epoch}:${this.qn}:${item.id}:${item.cid || 0}`;
      const source = this.sources.get(key);
      if (!source) continue;
      // 实例池只对准前 N 张可见卡：把这几条准备到「已 prepared、已解出首帧、paused」，
      // 点击时直接 surface 改绑 + play（warm 内部对同一 cid 幂等，重复调用无副作用）。
      if (i < this.warmIndex + slots && (item.cid || 0) > 0) {
        // 池实例要按「用户会看到的位置」准备首帧：只传续播点才能在 prepare 之前
        // setPlaybackRange，避免接管后再 seek（seekDone 实测要 ~900ms 才回来）。
        const resumeMs: number = Math.round(this.resumeSec(item) * 1000);
        IjkWarmPool.get().warm(item.cid, source, resumeMs).catch(() => {});
      }
      IjkPrewarm.warm(source, this.resumeSec(item));
    }
  }

  private async prepare(job: PlaybackListJob): Promise<void> {
    const started = Date.now();
    try {
      let id = job.item.id;
      let cid = job.item.cid || 0;
      if (cid <= 0) {
        const detail = await getVideoDetail(id);
        if (!this.current(job) || !detail) return;
        id = detail.bvid || id;
        cid = cid || detail.cid || detail.pages?.[0]?.cid || 0;
      }
      if (!this.current(job) || cid <= 0) return;
      hilog.debug(0x0000, 'PlaybackList', 'fetch id=%{public}s cid=%{public}d qn=%{public}d', id, cid, job.qn);
      const result = await getVideoPlayUrl(id, cid, job.qn, 40000);
      if (!this.current(job) || !result.url) return;
      this.completed.add(job.key);
      this.sources.set(job.key, result);
      this.prepareVisiblePrefixes();
      // Counters and duration only; never log signed URLs, cookies or media IDs.
      hilog.debug(0x0000, 'PlaybackList', 'ready %{public}s cid=%{public}d %{public}dms (%{public}d/%{public}d)',
        id, cid, Date.now() - started, this.completed.size, this.wanted.size);
    } catch (_) {
      // Failed entries remain retryable at the next bounded refresh or list update.
    }
  }
}
