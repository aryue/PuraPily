export interface PlaybackProgressEntry {
  key: string;
  position: number;
  duration: number;
  completed: boolean;
  updatedAt: number;
}

export interface PlaybackStartupResume {
  source: 'local' | 'server' | 'serverEnd';
  position: number;
  completed: boolean;
}

export interface PlaybackProgressSample {
  bvid: string;
  cid: number;
  epId: number;
  state?: string;
  position: number;
  duration: number;
  completed: boolean;
}

// Keep the most recent position, including backwards seeks and completed playback.
// Partition by account and CID so different parts and signed-out playback stay separate.
export class PlaybackProgress {
  private static currentAccount(): string {
    const cookie: string = AppStorage.get<string>('biliCookie') || '';
    const account = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/);
    return account ? account[1] : '';
  }

  static storageKey(bvid: string, cid: number, epId: number): string {
    return PlaybackProgress.key(PlaybackProgress.currentAccount(), bvid, cid, epId);
  }

  static readLocal(key: string): PlaybackProgressEntry | undefined {
    return PlaybackProgress.read(AppStorage.get<string>('playbackProgressV1') || '[]', key);
  }

  static saveLocal(key: string, position: number, duration: number, completed: boolean): void {
    const raw = AppStorage.get<string>('playbackProgressV1') || '[]';
    AppStorage.set('playbackProgressV1', PlaybackProgress.write(raw, {
      key, position, duration, completed, updatedAt: Date.now()
    }));
  }

  static confirmedPosition(cid: number, state: string | undefined, position: number,
    duration: number, completed: boolean): number | null {
    if (!cid || duration <= 0 || (state !== 'playing' && state !== 'paused' && state !== 'completed')) return null;
    const confirmed = completed ? duration : position;
    return Number.isFinite(confirmed) && confirmed >= 0 ? confirmed : null;
  }

  static saveConfirmed(sample: PlaybackProgressSample): void {
    const position = PlaybackProgress.confirmedPosition(sample.cid, sample.state, sample.position,
      sample.duration, sample.completed);
    if (position === null) return;
    const key = PlaybackProgress.storageKey(sample.bvid, sample.cid, sample.epId);
    PlaybackProgress.saveLocal(key, position, sample.duration, sample.completed);
  }
  static key(account: string, bvid: string, cid: number, epId: number): string {
    return `${account || 'guest'}:${epId > 0 ? `ep${epId}` : bvid}:${cid}`;
  }

  private static entries(raw: string): PlaybackProgressEntry[] {
    try {
      const entries = JSON.parse(raw) as PlaybackProgressEntry[];
      if (Array.isArray(entries)) return entries.filter((entry: PlaybackProgressEntry) =>
        !!entry && typeof entry.key === 'string');
    } catch (_) {}
    return [];
  }

  static read(raw: string, key: string): PlaybackProgressEntry | undefined {
    return PlaybackProgress.entries(raw).find((entry: PlaybackProgressEntry) => entry.key === key);
  }

  static write(raw: string, entry: PlaybackProgressEntry): string {
    const entries = PlaybackProgress.entries(raw);
    return JSON.stringify([entry, ...entries.filter((old: PlaybackProgressEntry) => old.key !== entry.key)].slice(0, 300));
  }

  static resume(position: number, duration: number, completed: boolean = false): number {
    if (completed || !Number.isFinite(position) || position <= 0 || duration <= 0 || position >= duration - 1) return 0;
    return position;
  }

  static startupResume(key: string, routeSeconds: number, serverMs: number,
    duration: number): PlaybackStartupResume | null {
    const local = PlaybackProgress.readLocal(key);
    if (local) return { source: 'local', position: local.completed ? 0 : local.position, completed: local.completed };
    if (routeSeconds > 0 || serverMs <= 0) return null;
    const position = serverMs / 1000;
    return { source: duration > 0 && position >= duration - 3 ? 'serverEnd' : 'server', position, completed: false };
  }

  /** Resolve the timeline shown when the player reaches prepared. */
  static preparedDuration(playerMs: number, sourceMs: number, videoSeconds: number,
    feed: boolean, detailSeconds: number): number {
    if (feed) return detailSeconds || videoSeconds || Math.ceil(playerMs / 1000);
    if (playerMs > 0) return playerMs / 1000;
    // Some DASH streams report zero at prepare. The MPD describes this CID;
    // video metadata may describe all parts together.
    return sourceMs > 0 ? sourceMs / 1000 : videoSeconds;
  }

  /**
   * 当前账号下该视频的续播点（秒）。返回 -1 表示「没有记录」，0 表示「明确从头播」
   * （已看完或接近片尾）。调用方据此决定是否退回服务端续播点——本地记录优先，
   * 否则会出现「本地已看完从 0 播、预热却按服务端旧进度跳到片尾」的错位。
   */
  static current(bvid: string, cid: number, epId: number = 0): number {
    const entry = PlaybackProgress.readLocal(PlaybackProgress.storageKey(bvid, cid, epId));
    if (!entry) return -1;
    return PlaybackProgress.resume(entry.position, entry.duration, entry.completed);
  }

  static prewarmPosition(id: string, cid: number, serverMs: number): number {
    let position = PlaybackProgress.current(id, cid);
    if (position < 0) position = PlaybackProgress.currentByCid(cid);
    return position >= 0 ? position : Math.max(0, serverMs / 1000);
  }

  /**
   * 按 cid 兜底查续播点（列表阶段用）：首页卡片的 id 可能是 aid（数字），而播放页
   * 保存进度时 key 里用的是 bvid，两者拼出的 key 不同 —— 直接用 current() 会永远
   * 查不到，预热实例因此按 0 秒准备，接管后还要 seek（首帧多花 ~900ms）。
   * cid 是分P的唯一标识且固定在 key 末尾，按账号前缀 + cid 后缀匹配不会串集；
   * 多条同 cid 记录取 updatedAt 最新的一条。返回 -1 表示没有记录。
   */
  static currentByCid(cid: number): number {
    if (!(cid > 0)) return -1;
    // key 形如 `account:bvid|epN:cid`；未登录的 account 段是字面量 'guest'（见 key()）。
    // 按段比对而不是拼前缀，避免账号缺省值与 epId 形态写错时整段匹配失效。
    const accountPart = PlaybackProgress.currentAccount() || 'guest';
    const entries = PlaybackProgress.entries(AppStorage.get<string>('playbackProgressV1') || '[]');
    let best: PlaybackProgressEntry | undefined = undefined;
    for (const entry of entries) {
      const parts: string[] = entry.key.split(':');
      if (parts.length < 3 || parts[0] !== accountPart || Number(parts[parts.length - 1]) !== cid) continue;
      if (best === undefined || (entry.updatedAt ?? 0) >= (best.updatedAt ?? 0)) best = entry;
    }
    if (best === undefined) return -1;
    return PlaybackProgress.resume(best.position, best.duration, best.completed);
  }
}
