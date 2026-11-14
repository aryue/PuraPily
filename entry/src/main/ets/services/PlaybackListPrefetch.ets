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
  private prefixAttempted: Set<string> = new Set();
  private instanceAttempted: Set<string> = new Set();
  private enabled: () => boolean;
  private warmScene: () => string;
  private visibleIds: Set<string> = new Set();
  private viewportTimer: number = -1;
  private viewportOrder: string[] = [];

  constructor(enabled: () => boolean = () => true, warmScene: () => string = () => 'home') {
    this.enabled = enabled;
    this.warmScene = warmScene;
  }

  updateViewport(visible: RecommendItem[], nearby: RecommendItem[], qn: number): void {
    if (this.viewportTimer !== -1) clearTimeout(this.viewportTimer);
    this.viewportTimer = setTimeout(() => {
      this.viewportTimer = -1;
      if (!this.enabled()) return;
      const ids = new Set(visible.map((item: RecommendItem) => item.id));
      const changed = ids.size !== this.visibleIds.size ||
        visible.some((item: RecommendItem) => !this.visibleIds.has(item.id));
      if (changed) {
        const fresh = visible.filter((item: RecommendItem) => !this.visibleIds.has(item.id));
        const retained = visible.filter((item: RecommendItem) => this.visibleIds.has(item.id));
        this.viewportOrder = [...this.scatter(fresh), ...this.scatter(retained)].map((item: RecommendItem) => item.id);
        this.visibleIds = ids;
      }
      const ordered: RecommendItem[] = [];
      for (const id of this.viewportOrder) {
        const item = visible.find((candidate: RecommendItem) => candidate.id === id);
        if (item !== undefined) ordered.push(item);
      }
      this.update([...ordered, ...nearby], qn, 0, ordered.length);
    }, 100);
  }

  private scatter(items: RecommendItem[]): RecommendItem[] {
    if (items.length < 2) return items;
    // Rank by a stable hash so layout callbacks do not repeatedly reshuffle the same viewport.
    const ranks = new Map<string, number>();
    for (const item of items) {
      let hash = 2166136261;
      for (let i = 0; i < item.id.length; i++) hash = Math.imul(hash ^ item.id.charCodeAt(i), 16777619);
      ranks.set(item.id, hash >>> 0);
    }
    return items.slice().sort((a: RecommendItem, b: RecommendItem) =>
      (ranks.get(a.id) ?? 0) - (ranks.get(b.id) ?? 0));
  }

  private visibleLimit: number = 8;

  update(items: RecommendItem[], qn: number, warmIndex: number = -1, visibleLimit: number = 8): void {
    if (warmIndex >= 0) this.warmIndex = warmIndex;
    this.visibleLimit = visibleLimit;
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
    if (this.items.length === 0) this.pause();
    this.pump();
  }

  pause(): void {
    if (this.viewportTimer !== -1) clearTimeout(this.viewportTimer);
    this.viewportTimer = -1;
    this.visibleIds.clear();
    this.viewportOrder = [];
    this.epoch++;
    this.items = [];
    this.sources.clear();
    this.prefixAttempted.clear();
    this.instanceAttempted.clear();
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

  private prepareVisiblePrefixes(): void {
    const scene = this.warmScene();
    if (!scene || !this.enabled() || !NetworkGate.allowsBoundedPrefix()) return;
    // 实例池槽数（默认 1）：槽数大于 1 时把后面几张可见卡也准备到首帧。
    const home = scene === 'home' || scene.startsWith('home:');
    if (scene.startsWith('home:')) IjkWarmPool.get().activateHomeScene(scene);
    const slots: number = home ? IjkWarmPool.get().capacity() : 1;
    const span: number = home ? Math.max(2, slots) : 1;
    const end = Math.min(this.items.length, this.warmIndex + span, this.visibleLimit);
    if (scene.startsWith('home:') && this.visibleLimit > 0) {
      const targets = this.items.slice(this.warmIndex, Math.min(end, this.warmIndex + slots));
      IjkWarmPool.get().retainHomeTargets(scene, new Set(targets.map((item: RecommendItem) => item.cid || 0)));
    }
    const prefixCandidates = new Set<string>();
    const instanceCandidates = new Set<string>();
    for (let i = this.warmIndex; i < end; i++) {
      const item = this.items[i];
      const key = `${this.epoch}:${this.qn}:${item.id}:${item.cid || 0}`;
      const instanceCandidate = i < this.warmIndex + slots && (item.cid || 0) > 0;
      prefixCandidates.add(key);
      if (instanceCandidate) instanceCandidates.add(key);
      const source = this.sources.get(key);
      if (!source) continue;
      const preparePrefix = !this.prefixAttempted.has(key);
      const prepareInstance = instanceCandidate && !this.instanceAttempted.has(key);
      if (!preparePrefix && !prepareInstance) continue;
      const resumeSec = PlaybackProgress.prewarmPosition(item.id, item.cid || 0, source.lastPlayTimeMs ?? 0);
      // Each candidate gets one media attempt while it stays in the prefetch window.
      // Address refresh, failures and native TTL expiry must not restart media.
      if (preparePrefix) {
        this.prefixAttempted.add(key);
        IjkPrewarm.warm(source, resumeSec);
      }
      // 实例池只对准前 N 张可见卡：把这几条准备到「已 prepared、已解出首帧、paused」，
      // 点击时直接 surface 改绑 + play（warm 内部对同一 cid 幂等，重复调用无副作用）。
      if (prepareInstance) {
        this.instanceAttempted.add(key);
        // 池实例要按「用户会看到的位置」准备首帧：只传续播点才能在 prepare 之前
        // setPlaybackRange，避免接管后再 seek（seekDone 实测要 ~900ms 才回来）。
        const resumeMs: number = Math.round(resumeSec * 1000);
        IjkWarmPool.get().warm(item.cid, source, resumeMs, scene).catch(() => {});
      }
    }
    this.prefixAttempted.forEach((key: string) => {
      if (!prefixCandidates.has(key)) this.prefixAttempted.delete(key);
    });
    this.instanceAttempted.forEach((key: string) => {
      if (!instanceCandidates.has(key)) this.instanceAttempted.delete(key);
    });
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
      // Failed addresses can be retried on the next list update.
    }
  }
}
