import { NetworkGate } from '../utils/NetworkGate';
import { ijkPlaybackRequested } from './PlaybackFactory';
import type { PlaybackPlayer } from './PlaybackPlayer';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { PlayUrlResult, DashFullInfo } from '../api/BilibiliApi';
import { DashPlayerBridge } from './DashPlayerBridge';
import { WarmSurfaceHost } from './WarmSurfaceHost';

const DOMAIN: number = 0x0000;
const TAG: string = 'WarmPlayer';
const TTL_MS: number = 12000;
const PREPARE_BUDGET_MS: number = 6000;
const DEFAULT_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

/** 已经 prepare 好、等在后台播放器：surface 还挂在宿主上，进页时改绑即可。 */
export class WarmPlayback {
  readonly cid: number;
  readonly quality: number;
  readonly player: PlaybackPlayer;
  readonly bridge: DashPlayerBridge;
  readonly playerUrl: string;
  readonly preparedAt: number;

  constructor(cid: number, quality: number, player: PlaybackPlayer, bridge: DashPlayerBridge,
    playerUrl: string, preparedAt: number) {
    this.cid = cid;
    this.quality = quality;
    this.player = player;
    this.bridge = bridge;
    this.playerUrl = playerUrl;
    this.preparedAt = preparedAt;
  }

  release(): void {
    try {
      this.player.release();
    } catch (e) { }
    this.bridge.stopIfRunning().catch(() => {});
  }
}

/**
 * 单槽"预热播放器"：点击后建 DASH 转播站 + 播放器，绑在首页常驻的宿主 surface 上 prepare（不播放）。
 * 播放页 initP 命中就接管：改绑到页面 surface → 复用冷启动那套 prepared 收尾。
 *
 * 只在宿主 surface 就绪时工作；关闭开关 AppStorage.playbackWarmPlayerOff = true。
 */
export class PlaybackWarmPlayer {
  private static shared: PlaybackWarmPlayer = new PlaybackWarmPlayer();

  static get(): PlaybackWarmPlayer {
    return PlaybackWarmPlayer.shared;
  }

  private entry: WarmPlayback | null = null;
  private building: boolean = false;
  private timer: number = -1;
  private pendingCid: number = 0;
  private pendingQuality: number = 0;
  private pendingDone: Promise<WarmPlayback | null> | null = null;
  private settlePending: (entry: WarmPlayback | null) => void = () => {};
  private pendingSettled: boolean = false;
  private buildingBridge: DashPlayerBridge | null = null;
  private buildingPlayer: PlaybackPlayer | null = null;

  private static enabled(): boolean {
    // 默认关闭：命中时能省 200–400ms，但预热慢于页面时会多等最多 1.5s。
    // 实测见 docs/bili-preload-compare-20261104.md 第 10 节，置 AppStorage.playbackWarmPlayer = true 可开启。
    return !NetworkGate.isMetered() && !ijkPlaybackRequested() && AppStorage.get<boolean>('playbackWarmPlayer') === true;
  }

  start(cid: number, source: PlayUrlResult): void {
    if (cid <= 0 || this.building || !PlaybackWarmPlayer.enabled()) {
      return;
    }
    const host: string = WarmSurfaceHost.get();
    const dash = source.dash;
    if (host.length === 0 || dash === undefined || dash === null || !source.audioUrl) {
      return;
    }
    const ready: WarmPlayback | null = this.entry;
    if (ready !== null && ready.cid === cid && Date.now() - ready.preparedAt < TTL_MS) {
      return;
    }
    this.release();
    this.building = true;
    this.pendingCid = cid;
    this.pendingSettled = false;
    this.pendingDone = new Promise<WarmPlayback | null>((resolve: (entry: WarmPlayback | null) => void) => {
      this.settlePending = resolve;
    });
    const bridge: DashPlayerBridge = new DashPlayerBridge(null);
    this.buildingBridge = bridge;
    const referer: string = source.mediaReferer ?? 'https://www.bilibili.com/';
    const agent: string = source.mediaUserAgent || DEFAULT_UA;
    const quality: number = dash.quality;
    this.pendingQuality = quality;
    const startedAt: number = Date.now();
    this.prepare(cid, quality, bridge, dash, referer, agent, host, startedAt)
      .then((entry: WarmPlayback | null) => {
        this.building = false;
        if (entry === null) {
          this.buildingBridge = null;
          this.buildingPlayer = null;
          bridge.stopIfRunning().catch(() => {});
          this.finishPending(null);
          hilog.info(DOMAIN, TAG, '%{public}s', `warm failed cid=${cid} ${Date.now() - startedAt}ms`);
          return;
        }
        this.buildingBridge = null;
        this.buildingPlayer = null;
        this.entry = entry;
        this.armTimer();
        this.finishPending(entry);
        hilog.info(DOMAIN, TAG, '%{public}s', `warm ready cid=${cid} qn=${quality} ${Date.now() - startedAt}ms`);
      })
      .catch(() => {
        this.building = false;
        bridge.stopIfRunning().catch(() => {});
        this.finishPending(null);
      });
  }

  private async prepare(cid: number, quality: number, bridge: DashPlayerBridge, dash: DashFullInfo,
    referer: string, agent: string, host: string, startedAt: number): Promise<WarmPlayback | null> {
    const url: string | null = await bridge.buildAndStart(dash, referer, agent, '', 0);
    if (url === null || url.length === 0) {
      return null;
    }
    const player: PlaybackPlayer = await media.createAVPlayer();
    this.buildingPlayer = player;
    const headers: Record<string, string> = { 'User-Agent': agent, 'Referer': referer };
    let settled: boolean = false;
    const prepared: Promise<boolean> = new Promise<boolean>((resolve: (ok: boolean) => void) => {
      const timer: number = setTimeout(() => {
        if (settled) return;
        settled = true;
        resolve(false);
      }, PREPARE_BUDGET_MS);
      player.on('stateChange', async (state: string) => {
        if (state === 'initialized') {
          try {
            player.surfaceId = host;
          } catch (e) { }
          try {
            await player.prepare();
          } catch (e) { }
        } else if (state === 'prepared' && !settled) {
          settled = true;
          clearTimeout(timer);
          resolve(true);
        } else if (state === 'error' && !settled) {
          settled = true;
          clearTimeout(timer);
          resolve(false);
        }
      });
    });
    try {
      player.setVolume(0);
    } catch (e) { }
    await player.setMediaSource(media.createMediaSourceWithUrl(url, headers));
    const ok: boolean = await prepared;
    if (!ok) {
      try { player.release(); } catch (e) { }
      return null;
    }
    hilog.info(DOMAIN, TAG, '%{public}s', `prepared cid=${cid} ${Date.now() - startedAt}ms`);
    return new WarmPlayback(cid, quality, player, bridge, url, Date.now());
  }

  /**
   * 页面接管：已经好的直接取走；还在准备就最多等 budgetMs。
   * 超时返回 null，页面回落冷路径（此时预热任务会被放弃，避免双实例）。
   */
  async take(cid: number, budgetMs: number): Promise<WarmPlayback | null> {
    const ready: WarmPlayback | null = this.entry;
    if (ready !== null && ready.cid === cid && ready.player.state === 'prepared' &&
      Date.now() - ready.preparedAt <= TTL_MS) {
      this.clearTimer();
      this.entry = null;
      this.finishPending(null);
      return ready;
    }
    const pending: Promise<WarmPlayback | null> | null = this.pendingDone;
    if (pending === null || this.pendingCid !== cid) {
      return null;
    }
    const settled: WarmPlayback | null = await PlaybackWarmPlayer.bounded(pending, budgetMs);
    if (settled === null) {
      // 超时：立刻掐掉预热（否则它会和冷路径抢带宽/解码器），页面走冷启动。
      this.abort();
      return null;
    }
    if (this.entry === settled) {
      this.clearTimer();
      this.entry = null;
    }
    return settled;
  }

  /** 页面在取到地址后先比对画质：不一致就没必要再等。 */
  peekQuality(cid: number): number {
    const ready: WarmPlayback | null = this.entry;
    if (ready !== null && ready.cid === cid) {
      return ready.quality;
    }
    if (this.pendingCid === cid) {
      return this.pendingQuality;
    }
    return 0;
  }

  /** 放弃正在进行的预热：停转播站、释放播放器，避免与冷路径竞争。 */
  abort(): void {
    this.pendingCid = 0;
    this.pendingDone = null;
    this.pendingSettled = true;
    this.building = false;
    const player: PlaybackPlayer | null = this.buildingPlayer;
    this.buildingPlayer = null;
    if (player !== null) {
      try { player.release(); } catch (e) { }
    }
    const bridge: DashPlayerBridge | null = this.buildingBridge;
    this.buildingBridge = null;
    if (bridge !== null) {
      bridge.stopIfRunning().catch(() => {});
    }
    hilog.info(DOMAIN, TAG, '%{public}s', 'warm aborted');
  }

  private finishPending(entry: WarmPlayback | null): void {
    if (this.pendingSettled) {
      return;
    }
    this.pendingSettled = true;
    this.settlePending(entry);
  }

  private static bounded(task: Promise<WarmPlayback | null>, budgetMs: number): Promise<WarmPlayback | null> {
    return new Promise<WarmPlayback | null>((resolve: (entry: WarmPlayback | null) => void) => {
      let settled: boolean = false;
      const timer: number = setTimeout(() => {
        if (settled) return;
        settled = true;
        resolve(null);
      }, Math.max(1, budgetMs));
      task.then((entry: WarmPlayback | null) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(entry);
      }).catch(() => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        resolve(null);
      });
    });
  }

  release(): void {
    this.clearTimer();
    const entry: WarmPlayback | null = this.entry;
    this.entry = null;
    if (entry !== null) {
      entry.release();
    }
  }

  private armTimer(): void {
    this.clearTimer();
    this.timer = setTimeout(() => {
      this.timer = -1;
      const entry: WarmPlayback | null = this.entry;
      if (entry !== null && Date.now() - entry.preparedAt > TTL_MS) {
        this.entry = null;
        entry.release();
        hilog.info(DOMAIN, TAG, '%{public}s', `expired cid=${entry.cid}`);
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
