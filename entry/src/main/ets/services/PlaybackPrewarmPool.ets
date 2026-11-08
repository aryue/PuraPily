import { NetworkGate } from '../utils/NetworkGate';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { PlayUrlResult } from '../api/BilibiliApi';
import { DashPlayerBridge } from './DashPlayerBridge';

/** How long a ready relay stays worth keeping. */
const TTL_MS: number = 20000;
/** How long an intent may wait for its playurl before it is abandoned. */
const INTENT_TTL_MS: number = 8000;
/** Bytes of the first video segment that must be available before the MPD is handed over. */
const VIDEO_PREFIX_BYTES: number = 256 * 1024;
const DEFAULT_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
const DOMAIN: number = 0x0000;
const TAG: string = 'PlaybackPrewarm';

/** A ready relay: local MPD url plus the bridge that owns the server. */
export class PrewarmEntry {
  readonly cid: number;
  readonly id: string;
  readonly quality: number;
  readonly playerUrl: string;
  readonly bridge: DashPlayerBridge;
  readonly at: number;

  constructor(cid: number, id: string, quality: number, playerUrl: string, bridge: DashPlayerBridge, at: number) {
    this.cid = cid;
    this.id = id;
    this.quality = quality;
    this.playerUrl = playerUrl;
    this.bridge = bridge;
    this.at = at;
  }

  expired(now: number): boolean {
    return now - this.at > TTL_MS;
  }
}

/** Registered at tap time, before playurl resolves, so the page can wait for work that has not started yet. */
class PendingWarm {
  id: string;
  cid: number;
  readonly startedAt: number;
  readonly done: Promise<PrewarmEntry | null>;
  abandoned: boolean = false;
  private settle: (entry: PrewarmEntry | null) => void = () => {};
  private settled: boolean = false;

  constructor(id: string, cid: number, startedAt: number) {
    this.id = id;
    this.cid = cid;
    this.startedAt = startedAt;
    this.done = new Promise<PrewarmEntry | null>((resolve: (entry: PrewarmEntry | null) => void) => {
      this.settle = resolve;
    });
  }

  finish(entry: PrewarmEntry | null): void {
    if (this.settled) {
      return;
    }
    this.settled = true;
    this.settle(entry);
  }

  expired(now: number): boolean {
    return now - this.startedAt > INTENT_TTL_MS;
  }

  abandon(): void {
    this.abandoned = true;
    this.finish(null);
  }
}

/**
 * One-slot warm pool for the "tap -> play page" hop.
 *
 * The tap registers an intent synchronously; once playurl resolves the pool starts the DASH relay
 * (sidx probes + MPD + first segments) while the route transition and page build are still running.
 * The play page then adopts the relay instead of probing the CDN again. Ownership transfers on take():
 * the page stops it, the pool never touches it again.
 *
 * Keyed by cid because the tap may only know an aid while the page only knows the real bvid.
 */
export class PlaybackPrewarmPool {
  private static shared: PlaybackPrewarmPool = new PlaybackPrewarmPool();

  static get(): PlaybackPrewarmPool {
    return PlaybackPrewarmPool.shared;
  }

  private entry: PrewarmEntry | null = null;
  private pending: PendingWarm | null = null;
  private builder: DashPlayerBridge | null = null;
  private timer: number = -1;

  private static enabled(): boolean {
    // 默认关闭：模拟器 A/B 实测仅 ~30ms 收益（见 docs 记录），真机网络下再评估。
    // 置 AppStorage 'playbackPrewarm' = true 可开启（用于真机对比）。
    // 默认关闭：模拟器与真机 A/B 均无正收益（真机点击→页面仅 15–60ms，没有头程可抢，
    // 且预热与页面构建抢同一 JS 线程）。置 AppStorage 'playbackPrewarm' = true 可复测。
    return !NetworkGate.isMetered() && AppStorage.get<boolean>('playbackPrewarm') === true;
  }

  /** Called on tap, synchronously, before any network. cid may be 0 when the card only has an aid. */
  intent(id: string, cid: number): void {
    if (id.length === 0 || !PlaybackPrewarmPool.enabled()) {
      return;
    }
    const current: PendingWarm | null = this.pending;
    if (current !== null && !current.expired(Date.now()) &&
      (current.id === id || (cid > 0 && current.cid === cid))) {
      if (cid > 0) {
        current.cid = cid;
      }
      return;
    }
    this.release();
    this.pending = new PendingWarm(id, cid, Date.now());
    hilog.debug(DOMAIN, TAG, '%{public}s', `intent ${id} cid=${cid}`);
  }

  /** Called when playurl for that tap is available. */
  fulfill(id: string, cid: number, source: PlayUrlResult): void {
    const pending: PendingWarm | null = this.pending;
    if (pending === null || pending.abandoned) {
      return;
    }
    const matches: boolean = pending.id === id || (cid > 0 && pending.cid === cid);
    if (!matches) {
      return;
    }
    if (cid > 0) {
      pending.cid = cid;
    }
    const dash = source.dash;
    if (dash === undefined || dash === null || !source.audioUrl || pending.cid <= 0) {
      this.pending = null;
      pending.finish(null);
      return;
    }
    const bridge: DashPlayerBridge = new DashPlayerBridge(null);
    const referer: string = source.mediaReferer ?? 'https://www.bilibili.com/';
    const agent: string = source.mediaUserAgent || DEFAULT_UA;
    const quality: number = dash.quality;
    const realCid: number = pending.cid;
    this.builder = bridge;
    const startedAt: number = Date.now();
    bridge.buildAndStart(dash, referer, agent, '', 0)
      .then((url: string | null): PrewarmEntry | null => {
        if (url === null || url.length === 0) {
          return null;
        }
        return new PrewarmEntry(realCid, id, quality, url, bridge, Date.now());
      })
      .catch((): PrewarmEntry | null => null)
      .then((entry: PrewarmEntry | null): void => {
        if (this.builder === bridge) {
          this.builder = null;
        }
        if (entry === null) {
          bridge.stopIfRunning().catch(() => {});
          if (this.pending === pending) {
            this.pending = null;
          }
          pending.finish(null);
          hilog.info(DOMAIN, TAG, '%{public}s', `warm failed ${id} ${Date.now() - startedAt}ms`);
          return;
        }
        if (pending.abandoned || this.pending !== pending) {
          entry.bridge.stopIfRunning().catch(() => {});
          pending.finish(null);
          hilog.info(DOMAIN, TAG, '%{public}s', `warm abandoned ${id}`);
          return;
        }
        this.pending = null;
        this.entry = entry;
        this.armTimer();
        pending.finish(entry);
        hilog.info(DOMAIN, TAG, '%{public}s',
          `warm ready ${id} cid=${realCid} qn=${quality} ${Date.now() - startedAt}ms`);
      });
  }

  /**
   * Claims the warmed relay for this cid. Waits at most `budgetMs` for an in-flight warm;
   * returns null immediately when nothing was warmed for that tap.
   */
  async take(cid: number, quality: number, budgetMs: number): Promise<PrewarmEntry | null> {
    if (cid <= 0) {
      return null;
    }
    const ready: PrewarmEntry | null = this.entry;
    if (ready !== null && ready.cid === cid) {
      this.entry = null;
      this.clearTimer();
      if (ready.expired(Date.now()) || ready.quality !== quality) {
        ready.bridge.stopIfRunning().catch(() => {});
        hilog.info(DOMAIN, TAG, '%{public}s', `take stale cid=${cid}`);
        return null;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', `take hit cid=${cid} qn=${quality}`);
      return ready;
    }
    const pending: PendingWarm | null = this.pending;
    if (pending !== null && pending.cid === cid) {
      const settled: PrewarmEntry | null = await PlaybackPrewarmPool.bounded(pending.done, budgetMs);
      if (settled === null) {
        pending.abandon();
        hilog.info(DOMAIN, TAG, '%{public}s', `take timeout cid=${cid}`);
        return null;
      }
      if (this.entry === settled) {
        this.entry = null;
        this.clearTimer();
      }
      if (settled.quality !== quality) {
        settled.bridge.stopIfRunning().catch(() => {});
        return null;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', `take awaited cid=${cid} qn=${quality}`);
      return settled;
    }
    hilog.debug(DOMAIN, TAG, '%{public}s', `take miss cid=${cid}`);
    return null;
  }

  /** Resume points are prefetched after adoption so the later seek hits the relay cache. */
  async prefetchResume(entry: PrewarmEntry, positionMs: number): Promise<void> {
    if (positionMs <= 0) {
      return;
    }
    await entry.bridge.prefetchResume(positionMs, VIDEO_PREFIX_BYTES);
  }

  /** Stops the slot (leaving the app, account switch, or a new intent replacing it). */
  release(): void {
    this.clearTimer();
    const ready: PrewarmEntry | null = this.entry;
    this.entry = null;
    if (ready !== null) {
      ready.bridge.stopIfRunning().catch(() => {});
    }
    const pending: PendingWarm | null = this.pending;
    this.pending = null;
    if (pending !== null) {
      pending.abandon();
    }
    const builder: DashPlayerBridge | null = this.builder;
    this.builder = null;
    if (builder !== null) {
      builder.stopIfRunning().catch(() => {});
    }
  }

  private static bounded(task: Promise<PrewarmEntry | null>, budgetMs: number): Promise<PrewarmEntry | null> {
    return new Promise<PrewarmEntry | null>((resolve: (value: PrewarmEntry | null) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(null);
      }, Math.max(1, budgetMs));
      task.then((entry: PrewarmEntry | null) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(entry);
      }).catch(() => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(null);
      });
    });
  }

  private armTimer(): void {
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.timer = -1;
      const ready: PrewarmEntry | null = this.entry;
      if (ready !== null && ready.expired(Date.now())) {
        this.entry = null;
        ready.bridge.stopIfRunning().catch(() => {});
        hilog.info(DOMAIN, TAG, '%{public}s', `expired cid=${ready.cid}`);
      }
    }, TTL_MS + 50);
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
