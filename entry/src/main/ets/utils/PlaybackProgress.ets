export interface PlaybackProgressEntry {
  key: string;
  position: number;
  duration: number;
  completed: boolean;
  updatedAt: number;
}

// Keep the most recent position, including backwards seeks and completed playback.
// Partition by account and CID so different parts and signed-out playback stay separate.
export class PlaybackProgress {
  static key(account: string, bvid: string, cid: number, epId: number): string {
    return `${account || 'guest'}:${epId > 0 ? `ep${epId}` : bvid}:${cid}`;
  }

  static read(raw: string, key: string): PlaybackProgressEntry | undefined {
    try {
      const entries = JSON.parse(raw) as PlaybackProgressEntry[];
      if (!Array.isArray(entries)) return undefined;
      return entries.find((entry: PlaybackProgressEntry) => entry.key === key);
    } catch (_e) { return undefined; }
  }

  static write(raw: string, entry: PlaybackProgressEntry): string {
    let entries: PlaybackProgressEntry[] = [];
    try { entries = JSON.parse(raw) as PlaybackProgressEntry[]; } catch (_e) {}
    if (!Array.isArray(entries)) entries = [];
    return JSON.stringify([entry, ...entries.filter((old: PlaybackProgressEntry) => old.key !== entry.key)].slice(0, 300));
  }

  static resume(position: number, duration: number, completed: boolean = false): number {
    if (completed || !Number.isFinite(position) || position <= 0 || duration <= 0 || position >= duration - 1) return 0;
    return position;
  }

  /**
   * 当前账号下该视频的续播点（秒）。返回 -1 表示「没有记录」，0 表示「明确从头播」
   * （已看完或接近片尾）。调用方据此决定是否退回服务端续播点——本地记录优先，
   * 否则会出现「本地已看完从 0 播、预热却按服务端旧进度跳到片尾」的错位。
   */
  static current(bvid: string, cid: number, epId: number = 0): number {
    const cookie: string = AppStorage.get<string>('biliCookie') || '';
    const account: RegExpMatchArray | null = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/);
    const entry: PlaybackProgressEntry | undefined = PlaybackProgress.read(
      AppStorage.get<string>('playbackProgressV1') || '[]',
      PlaybackProgress.key(account ? account[1] : '', bvid, cid, epId));
    if (!entry) return -1;
    return PlaybackProgress.resume(entry.position, entry.duration, entry.completed);
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
    const cookie: string = AppStorage.get<string>('biliCookie') || '';
    const account: RegExpMatchArray | null = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/);
    // key 形如 `account:bvid|epN:cid`；未登录的 account 段是字面量 'guest'（见 key()）。
    // 按段比对而不是拼前缀，避免账号缺省值与 epId 形态写错时整段匹配失效。
    const accountPart: string = account ? account[1] : 'guest';
    let entries: PlaybackProgressEntry[] = [];
    try { entries = JSON.parse(AppStorage.get<string>('playbackProgressV1') || '[]') as PlaybackProgressEntry[]; }
    catch (_e) { return -1; }
    if (!Array.isArray(entries)) return -1;
    let best: PlaybackProgressEntry | undefined = undefined;
    for (const entry of entries) {
      if (!entry || typeof entry.key !== 'string') continue;
      const parts: string[] = entry.key.split(':');
      if (parts.length < 3 || parts[0] !== accountPart || Number(parts[parts.length - 1]) !== cid) continue;
      if (best === undefined || (entry.updatedAt ?? 0) >= (best.updatedAt ?? 0)) best = entry;
    }
    if (best === undefined) return -1;
    return PlaybackProgress.resume(best.position, best.duration, best.completed);
  }
}
