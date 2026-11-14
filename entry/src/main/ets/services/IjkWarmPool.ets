import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { PlayUrlResult } from '../api/BilibiliApi';
import { FeedPlaybackSession, FeedPlaybackHandles } from './FeedPlaybackSession';
import { WarmSurfaceHost } from './WarmSurfaceHost';
import { ijkPlaybackRequested } from './PlaybackFactory';
import { NetworkGate } from '../utils/NetworkGate';

const log = (msg: string): void => { hilog.info(0x0000, 'Bilibili', '%{public}s', '[IjkWarm] ' + msg); };

export interface IjkWarmTake {
  handles: FeedPlaybackHandles;
  aspectRatio: number;
  /** 预热时用的宿主 surface，页面拿到后要改绑到自己的 surface。 */
  surfaceId: string;
  /**
   * 池实例 prepare 之前预置的续播点（毫秒，0 = 从头）。
   * 与页面本次起播的续播点一致时，接管后不用再 seek —— 省掉「seek + 等 seekDone」那段
   * 实测约 900ms 的首帧延迟（真机 2026-11-11：125ms → 1031ms 的差异全在这一段）。
   */
  resumeMs: number;
}

const TTL_MS: number = 25000;
/** 槽位内实例新建后 1.2s 内不因目标变化而重建，避免快速滑动时反复销毁/创建。 */
const REBUILD_COOLDOWN_MS: number = 1200;
const MAX_SLOTS: number = 5;

/** 一个槽：准备好首帧并暂停的一条视频。 */
class WarmSlot {
  session: FeedPlaybackSession | null = null;
  pending: FeedPlaybackSession | null = null;
  cid: number = 0;
  quality: number = 0;
  createdAt: number = 0;
  /** 本槽实例 prepare 前预置的续播点（毫秒）；列表阶段按当前历史进度确定。 */
  resumeMs: number = 0;
  /** 正在为该 cid 构建（0 = 空闲）。 */
  building: number = 0;
  timer: number = -1;
  scene: string = 'home';
  order: number = 0;
}

/**
 * IJK 实例池（槽数可配，默认 1）。
 *
 * 列表阶段把「接下来可能被点开的几条视频」准备到「已 prepared 且已解出首帧、paused」，
 * 进页时只做一次 surface 改绑 + play。IJK 的解码器是 buffer 输出（见 player_backend 的
 * bind 注释），换 surface 不需要重建解码器，所以这一步是安全的。
 *
 * 槽数：`--ps ijkWarmSlots 2` 可开到 2~5 个。每多一槽就多一个 IJK 实例
 * （解码器 + 15MiB 包队列上限 + 已缓冲数据），代价见 docs/… 实测。
 *
 * 默认开启。要求 IJK 内核、非计费网络且宿主 surface 就绪；--ps ijkWarm off 强制关闭。
 */
export class IjkWarmPool {
  private static shared: IjkWarmPool = new IjkWarmPool();
  static get(): IjkWarmPool {
    return IjkWarmPool.shared;
  }

  private slots: WarmSlot[] = [];
  private previewScenes: Map<string, number> = new Map();
  private sceneOrders: Map<string, number> = new Map();
  private sequence: number = 0;
  private activeHomeScene: string = '';

  activateHomeScene(scene: string): void {
    if (this.activeHomeScene === scene) return;
    this.activeHomeScene = scene;
    const order = ++this.sequence;
    this.sceneOrders.set(scene, order);
    for (const slot of this.slots) {
      if (slot.scene === scene) slot.order = order;
      else if (slot.scene.startsWith('home:') && slot.pending !== null) this.dispose(slot);
    }
  }

  retainHomeTargets(scene: string, targets: Set<number>): void {
    for (const slot of this.slots) {
      if (slot.scene !== scene) continue;
      const cid = slot.building || slot.cid;
      if (cid > 0 && !targets.has(cid)) this.dispose(slot);
    }
  }

  private sceneOrder(scene: string): number {
    let order = this.sceneOrders.get(scene);
    if (order === undefined) {
      order = ++this.sequence;
      this.sceneOrders.set(scene, order);
    }
    return order;
  }

  private makeRoom(scene: string): boolean {
    const order = this.sceneOrder(scene);
    const occupied = this.slots.filter((slot: WarmSlot) => slot.session !== null || slot.pending !== null);
    const needed = occupied.length + this.previewScenes.size - Math.max(2, this.capacity()) + 1;
    if (needed <= 0) return true;
    const older = occupied.filter((slot: WarmSlot) => slot.order < order)
      .sort((a: WarmSlot, b: WarmSlot) => a.order - b.order || a.createdAt - b.createdAt);
    if (older.length < needed) return false;
    for (const slot of older.slice(0, needed)) this.dispose(slot);
    return true;
  }

  reservePreview(scene: string): boolean {
    if (this.previewScenes.has(scene)) return true;
    if (!this.makeRoom(scene)) return false;
    this.previewScenes.set(scene, this.sceneOrder(scene));
    return true;
  }

  releasePreview(scene: string): void {
    this.previewScenes.delete(scene);
  }

  releaseScene(scene: string): void {
    this.releasePreview(scene);
    for (const slot of this.slots) {
      if (slot.scene === scene) this.dispose(slot);
    }
    this.sceneOrders.delete(scene);
  }

  takePreview(cid: number, quality: number, scene: string, surface: string): FeedPlaybackSession | null {
    for (const slot of this.slots) {
      if (slot.scene !== scene || slot.cid !== cid || slot.session === null ||
        slot.quality !== quality || Date.now() - slot.createdAt > TTL_MS) continue;
      const session = slot.session;
      if (!session.rebindPaused(surface)) return null;
      slot.session = null;
      this.dispose(slot);
      return session;
    }
    return null;
  }

  private enabled(): boolean {
    // 默认开启（IJK 内核 + 宿主 surface + 非计费网络三个条件同时满足才真预热）；
    // --ps ijkWarm off 可一键关闭做 A/B。
    if (AppStorage.get<boolean>('ijkWarmPool') === false) return false;
    if (!ijkPlaybackRequested() || !WarmSurfaceHost.ready()) return false;
    // 蜂窝网络不预热：一条预热要真下载首段，不能悄悄吃流量。
    return !NetworkGate.isMetered();
  }

  /** 允许同时预热的条数。默认 1，`--ps ijkWarmSlots n` 可在 1~5 之间调。 */
  capacity(): number {
    const key = AppStorage.get<boolean>('networkMetered') === true ? 'ijkWarmSlotsCellular' : 'ijkWarmSlotsWifi';
    const raw: number | undefined = AppStorage.get<number>('ijkWarmSlots') ?? AppStorage.get<number>(key);
    const n: number = raw === undefined ? 1 : Math.round(raw);
    return Math.max(1, Math.min(MAX_SLOTS, n));
  }

  /**
   * 列表阶段调用：把这条视频准备到「用户会看到的位置」的首帧。
   * `resumeMs` 是该卡片当前的历史进度：FeedPlaybackSession 会在 prepare 之前
   * setPlaybackRange 到这个点，池实例解出的首帧就是续播点的帧；页面接管时
   * 因此不必再 seek（seek + 等 seekDone 实测要多花 ~900ms 才出首帧）。
   * 已在槽内或正在构建的 cid 会被忽略。
   */
  async warm(cid: number, result: PlayUrlResult, resumeMs: number = 0, scene: string = 'home',
    videoId: string = String(cid)): Promise<void> {
    if (cid <= 0) {
      log('skip cid=0');
      return;
    }
    if (!this.enabled()) {
      log(`skip disabled ijk=${ijkPlaybackRequested() ? 1 : 0} off=${AppStorage.get<boolean>('ijkWarmPool') === false ? 1 : 0} host=${WarmSurfaceHost.ready() ? 1 : 0} metered=${NetworkGate.isMetered() ? 1 : 0}`);
      return;
    }
    for (const s of this.slots) {
      if (s.cid === cid || s.building === cid) return;
    }
    const target: WarmSlot | null = this.pickSlot(scene);
    if (target === null) {
      log('all slots fresh, skip ' + cid);
      return;
    }
    if (target.session !== null) this.dispose(target);
    if (!this.makeRoom(scene)) return;
    target.scene = scene;
    target.order = this.sceneOrder(scene);
    target.building = cid;
    const session = new FeedPlaybackSession(videoId, WarmSurfaceHost.get(), result,
      Math.max(0, Math.round(resumeMs)));
    target.pending = session;
    try {
      const ok: boolean = await session.prepare(media.VideoScaleType.VIDEO_SCALE_TYPE_FIT,
        AppStorage.get<string>('biliCookie') || '');
      if (!ok || target.pending !== session) {
        session.release().catch(() => {});
        return;
      }
      target.session = session;
      target.cid = cid;
      target.quality = result.dash?.quality ?? 0;
      target.resumeMs = Math.max(0, Math.round(resumeMs));
      target.createdAt = Date.now();
      this.arm(target);
      log(`ready cid=${cid} qn=${target.quality} resume=${target.resumeMs}ms slots=${this.readyCount()}/${this.slots.length}/${this.capacity()} host=${WarmSurfaceHost.get().slice(-6)} scene=${scene}`);
    } catch (e) {
      session.release().catch(() => {});
      log('failed ' + (e as Error).message);
    } finally {
      if (target.pending === session) {
        target.pending = null;
        target.building = 0;
      }
    }
  }

  /** 页面命中时取走实例（所有权转移给页面）。 */
  take(cid: number, quality: number): IjkWarmTake | null {
    for (const s of this.slots) {
      if (s.session === null || s.cid !== cid) continue;
      if (Date.now() - s.createdAt > TTL_MS) {
        this.dispose(s);
        return null;
      }
      if (quality > 0 && s.quality > 0 && quality !== s.quality) {
        // 画质不一致就别硬接：直接丢掉，走冷路径。
        this.dispose(s);
        return null;
      }
      const handles = s.session.take();
      if (handles === null) {
        this.dispose(s);
        return null;
      }
      this.clearTimer(s);
      const surfaceId: string = s.session.surfaceId;
      const aspectRatio: number = s.session.aspectRatio;
      const resumeMs: number = s.resumeMs;
      const age: number = Date.now() - s.createdAt;
      s.session = null;
      s.cid = 0;
      s.quality = 0;
      s.resumeMs = 0;
      s.createdAt = 0;
      log(`take cid=${cid} age=${age}ms resume=${resumeMs}ms left=${this.readyCount()}`);
      return { handles, aspectRatio, surfaceId, resumeMs };
    }
    const first: WarmSlot | undefined = this.slots.find((s: WarmSlot) => s.session !== null);
    if (first !== undefined) log(`miss cid=${cid} pool=${first.cid} building=${this.buildingCid()}`);
    return null;
  }

  /** 命中就直接给；正在为同一 cid 构建时最多等 budgetMs，避免"刚建到一半就错过"。 */
  async takeOrWait(cid: number, quality: number, budgetMs: number): Promise<IjkWarmTake | null> {
    const direct = this.take(cid, quality);
    if (direct !== null) return direct;
    if (!this.slots.some((s: WarmSlot) => s.building === cid)) return null;
    const deadline = Date.now() + budgetMs;
    while (Date.now() < deadline) {
      await new Promise<void>((resolve: () => void) => setTimeout(() => resolve(), 30));
      const got = this.take(cid, quality);
      if (got !== null) return got;
      if (!this.slots.some((s: WarmSlot) => s.building === cid)) return null;
    }
    log(`wait timeout cid=${cid}`);
    return null;
  }

  /** 释放全部槽。 */
  release(): void {
    for (const s of this.slots) this.dispose(s);
  }

  cancelBuildingExcept(cid: number): void {
    for (const s of this.slots) {
      if (s.pending !== null && s.building !== cid) this.dispose(s);
    }
  }

  /** 已就绪的槽数（不含正在构建/空的）。 */
  readyCount(): number {
    return this.slots.filter((s: WarmSlot) => s.session !== null).length;
  }

  /** 选择要用的槽：空槽优先；满了淘汰最旧且不在构建中的；全部新鲜则返回 null。 */
  private pickSlot(scene: string): WarmSlot | null {
    const limit = scene === 'home' || scene.startsWith('home:') ? this.capacity() : 1;
    const occupied = this.slots.filter((s: WarmSlot) =>
      s.scene === scene && (s.session !== null || s.pending !== null)).length;
    if (occupied > limit) return null;
    if (occupied < limit) {
      const empty = this.slots.find((s: WarmSlot) => s.session === null && s.building === 0);
      if (empty !== undefined) return empty;
    }
    if (occupied < limit && this.slots.length < MAX_SLOTS) {
      const fresh = new WarmSlot();
      this.slots.push(fresh);
      return fresh;
    }
    if (occupied < limit) {
      if (!this.makeRoom(scene)) return null;
      return this.slots.find((s: WarmSlot) => s.session === null && s.pending === null) ?? null;
    }
    let oldest: WarmSlot | null = null;
    for (const s of this.slots) {
      if (s.scene !== scene || s.building !== 0 || s.session === null) continue;
      if (oldest === null || s.createdAt < oldest.createdAt) oldest = s;
    }
    if (oldest === null) return null;
    if (Date.now() - oldest.createdAt < REBUILD_COOLDOWN_MS) return null;
    return oldest;
  }

  private buildingCid(): number {
    for (const s of this.slots) if (s.building !== 0) return s.building;
    return 0;
  }

  private arm(s: WarmSlot): void {
    this.clearTimer(s);
    s.timer = setTimeout(() => {
      s.timer = -1;
      log('expired cid=' + s.cid);
      this.dispose(s);
    }, TTL_MS);
  }

  private clearTimer(s: WarmSlot): void {
    if (s.timer !== -1) {
      clearTimeout(s.timer);
      s.timer = -1;
    }
  }

  private dispose(s: WarmSlot): void {
    this.clearTimer(s);
    const session = s.session;
    const pending = s.pending;
    s.session = null;
    s.pending = null;
    s.cid = 0;
    s.quality = 0;
    s.resumeMs = 0;
    s.createdAt = 0;
    s.building = 0;
    if (session !== null) session.release().catch(() => {});
    if (pending !== null && pending !== session) pending.release().catch(() => {});
  }
}
