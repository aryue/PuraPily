import { RecommendItem } from '../model/RecommendItem';
import { PlaybackProgressEntry } from '../utils/PlaybackProgress';
import { BilibiliHistoryApi } from '../api/BilibiliHistoryApi';

interface FeedAccountState {
  account: string;
  nextPage: number;
  visited: string[];
}

/** Separate from playback positions and the home feed's paging/cache. */
export class ContinuousRecommendationState {
  private static syncing: Map<string, Promise<void>> = new Map();
  private static syncedAt: Map<string, number> = new Map();

  static account(): string {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    const mid = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/);
    if (mid) return mid[1];
    const access = AppStorage.get<string>('biliAccessKey') || '';
    if (!access) return 'guest';
    // Do not persist authentication tokens. Isolate App-only sessions as well.
    let hash = 2166136261;
    for (let i = 0; i < access.length; i++) hash = Math.imul(hash ^ access.charCodeAt(i), 16777619);
    return `app${hash >>> 0}`;
  }

  private static all(): FeedAccountState[] {
    try {
      const value = JSON.parse(AppStorage.get<string>('continuousRecommendationsV1') || '[]') as FeedAccountState[];
      return Array.isArray(value) ? value.filter((item: FeedAccountState) =>
        typeof item.account === 'string' && Number.isFinite(item.nextPage) && Array.isArray(item.visited)) : [];
    } catch (_) { return []; }
  }

  private static state(account: string): FeedAccountState {
    return ContinuousRecommendationState.all().find((item: FeedAccountState) => item.account === account) ||
      { account: account, nextPage: 1, visited: [] };
  }

  private static save(state: FeedAccountState): void {
    AppStorage.setOrCreate('continuousRecommendationsV1', JSON.stringify([
      state, ...ContinuousRecommendationState.all().filter((item: FeedAccountState) => item.account !== state.account)
    ].slice(0, 5)));
  }

  static reservePage(account: string): number {
    const state = ContinuousRecommendationState.state(account);
    const page = Math.max(1, Math.floor(state.nextPage));
    state.nextPage = page + 1;
    ContinuousRecommendationState.save(state);
    return page;
  }

  static markVisited(id: string, aid: number = 0, account: string = ContinuousRecommendationState.account()): void {
    ContinuousRecommendationState.markMany([id, aid > 0 ? aid.toString() : ''], account);
  }

  private static markMany(ids: string[], account: string): void {
    const state = ContinuousRecommendationState.state(account);
    const visited = new Set<string>(state.visited);
    for (const id of ids) {
      if (!/^BV[0-9A-Za-z]{10}$/.test(id) && !/^[1-9]\d*$/.test(id)) continue;
      visited.delete(id);
      visited.add(id);
    }
    state.visited = Array.from(visited).slice(-2000);
    ContinuousRecommendationState.save(state);
  }

  static excluded(account: string): Set<string> {
    const result = new Set<string>(ContinuousRecommendationState.state(account).visited);
    // Existing local history covers ordinary playback before this feature was
    // introduced. CID/part and account remain encoded in the progress key.
    try {
      const progress = JSON.parse(AppStorage.get<string>('playbackProgressV1') || '[]') as PlaybackProgressEntry[];
      if (Array.isArray(progress)) for (const entry of progress) {
        if (typeof entry.key !== 'string' || !entry.key.startsWith(`${account}:`)) continue;
        const id = entry.key.split(':')[1];
        if (id?.startsWith('BV') && (entry.completed || entry.position >= 5)) result.add(id);
      }
    } catch (_) {}
    return result;
  }

  static isExcluded(item: RecommendItem, excluded: Set<string>): boolean {
    return excluded.has(item.id) || (item.aid > 0 && excluded.has(item.aid.toString()));
  }

  static async syncRecentHistory(account: string): Promise<void> {
    const cookie = AppStorage.get<string>('biliCookie') || '';
    if (!/(?:^|;\s*)SESSDATA=([^;\s]+)/.test(cookie)) return;
    if (Date.now() - (ContinuousRecommendationState.syncedAt.get(account) || 0) < 300000) return;
    const pending = ContinuousRecommendationState.syncing.get(account);
    if (pending) return pending;
    const job = ContinuousRecommendationState.fetchHistory(account, cookie);
    ContinuousRecommendationState.syncing.set(account, job);
    try { await job; }
    finally { ContinuousRecommendationState.syncing.delete(account); }
  }

  private static async fetchHistory(account: string, cookie: string): Promise<void> {
    try {
      const items = await BilibiliHistoryApi.getInstance().getHistoryList(0, 100, cookie);
      const ids: string[] = [];
      for (const item of items) {
        const business = item.business || item.history?.business || '';
        if ((business && business !== 'archive') || item.bangumi || item.type === 4) continue;
        if (item.bvid) ids.push(item.bvid);
        const aid = item.aid || item.oid || item.kid || 0;
        if (aid > 0) ids.push(aid.toString());
      }
      ContinuousRecommendationState.markMany(ids, account);
      if (items.length > 0) ContinuousRecommendationState.syncedAt.set(account, Date.now());
    } catch (_) { /* Offline history must not prevent recommendations. */ }
  }
}
