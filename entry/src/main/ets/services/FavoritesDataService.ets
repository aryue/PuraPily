import { FavFolderItem, FavResourceItem, getCreatedFavFolders, getCollectedFavFolders } from '../api/FavoritesApi';

interface FolderSnapshot { items: FavFolderItem[]; at: number; }
export interface FavoriteResourceSnapshot { items: FavResourceItem[]; hasMore: boolean; }

/** Account-scoped render cache. Navigation never waits for a refresh. */
export class FavoritesDataService {
  private static instance: FavoritesDataService = new FavoritesDataService();
  static getInstance(): FavoritesDataService { return FavoritesDataService.instance; }
  private owner: number = 0;
  private cookie: string = '';
  private revision: number = -1;
  private epoch: number = 0;
  private folders: Map<number, FolderSnapshot> = new Map();
  private pending: Map<number, Promise<FavFolderItem[] | null>> = new Map();
  private resources: Map<number, FavoriteResourceSnapshot> = new Map();

  private scope(mid: number): number {
    const cookie = AppStorage.get<string>('biliCookie') ?? '';
    const revision = AppStorage.get<number>('favoritesDataRevision') ?? 0;
    if (this.owner !== mid || this.cookie !== cookie || this.revision !== revision) {
      this.owner = mid; this.cookie = cookie; this.revision = revision; this.epoch++;
      this.folders.clear(); this.pending.clear(); this.resources.clear();
    }
    return this.epoch;
  }

  peekFolders(mid: number, index: number): FavFolderItem[] | undefined {
    this.scope(mid);
    return this.folders.get(index)?.items;
  }

  loadFolders(mid: number, index: number, refresh: boolean = false): Promise<FavFolderItem[] | null> {
    const epoch = this.scope(mid);
    if (mid <= 0 || !this.cookie.includes('SESSDATA')) return Promise.resolve(null);
    const pending = this.pending.get(index);
    if (pending) return pending;
    const cached = this.folders.get(index);
    if (!refresh && cached && Date.now() - cached.at < 60000) return Promise.resolve(cached.items);
    const request = index === 0 ? getCreatedFavFolders(mid) : getCollectedFavFolders();
    const task = request.then((items: FavFolderItem[] | null) => {
      if (epoch !== this.epoch || this.cookie !== (AppStorage.get<string>('biliCookie') ?? '') ||
        this.revision !== (AppStorage.get<number>('favoritesDataRevision') ?? 0)) return null;
      if (!items) return null;
      const previous = this.folders.get(index)?.items ?? [];
      const merged = items.map((item: FavFolderItem): FavFolderItem => {
        const old = previous.find((entry: FavFolderItem) => entry.id === item.id);
        if (!old) return item;
        return { id: item.id, title: item.title, media_count: item.media_count,
          cover: item.cover || old.cover, covers: item.covers?.length ? item.covers : old.covers };
      });
      this.folders.set(index, { items: merged, at: Date.now() });
      return merged;
    }).finally(() => { if (this.pending.get(index) === task) this.pending.delete(index); });
    this.pending.set(index, task);
    return task;
  }

  rememberFolders(mid: number, index: number, items: FavFolderItem[]): void {
    this.scope(mid);
    this.folders.set(index, { items: items, at: this.folders.get(index)?.at ?? Date.now() });
  }

  warm(mid: number): void {
    if (mid <= 0) return;
    this.loadFolders(mid, 0).catch(() => {});
    this.loadFolders(mid, 1).catch(() => {});
  }

  peekResources(mid: number, folder: number): FavoriteResourceSnapshot | undefined {
    this.scope(mid);
    return this.resources.get(folder);
  }

  rememberResources(mid: number, folder: number, items: FavResourceItem[], hasMore: boolean): void {
    this.scope(mid);
    this.resources.set(folder, { items: items, hasMore: hasMore });
    if (this.resources.size > 12) this.resources.delete(this.resources.keys().next().value);
  }
}
