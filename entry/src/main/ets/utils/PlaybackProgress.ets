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
}
