import { LocalWallpaper, WallpaperCrop, cleanWallpaperCrop } from '../utils/WallpaperLayout';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export function clampWallpaperScrim(value: number): number {
  return Number.isFinite(value) ? Math.max(0, Math.min(60, Math.round(value))) : 0;
}

export function wallpaperEndpoint(source: string, portrait: boolean): string {
  if (source === 'picsum') return portrait ? 'https://picsum.photos/1080/1920' : 'https://picsum.photos/1920/1080';
  if (source === 'pipw') return portrait ? 'https://img-api.pipw.top/?phone=true' : 'https://img-api.pipw.top';
  return '';
}

// One owner for all non-player pages. Orientation slots never overwrite one another.
export class PageWallpaperService {
  private static instance: PageWallpaperService = new PageWallpaperService();
  static getInstance(): PageWallpaperService { return PageWallpaperService.instance; }
  private pref: preferences.Preferences | undefined = undefined;
  private context: common.UIAbilityContext | undefined = undefined;
  private opening: Promise<void> | undefined = undefined;
  private pending: Map<string, Promise<string>> = new Map();
  private loaded: Map<string, string> = new Map();
  private busy: boolean = false;
  private library: LocalWallpaper[] = [];
  private decoded: Map<string, image.PixelMap> = new Map();
  private decoding: Map<string, Promise<void>> = new Map();

  paintSource(path: string): string | image.PixelMap {
    return this.decoded.get(path) ?? ('file://' + path);
  }

  prepareImage(path: string): Promise<void> {
    if (!path || this.decoded.has(path)) return Promise.resolve();
    const pending = this.decoding.get(path);
    if (pending) return pending;
    const task = this.decodeImage(path).catch(() => {}).finally(() => { this.decoding.delete(path); });
    this.decoding.set(path, task);
    return task;
  }

  private async decodeImage(path: string): Promise<void> {
    const file = fileIo.openSync(path.split('?')[0], fileIo.OpenMode.READ_ONLY);
    try {
      const source = image.createImageSource(file.fd);
      try {
        const info = await source.getImageInfo();
        const scale = Math.min(1, 2560 / Math.max(info.size.width, info.size.height));
        const bitmap = await source.createPixelMap({ editable: false, desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        } });
        this.decoded.set(path, bitmap);
        // Retain current/previous orientation resources, without releasing maps still used by an exiting page.
        if (this.decoded.size > 3) this.decoded.delete(this.decoded.keys().next().value);
        AppStorage.setOrCreate('pageWallpaperDecodedRevision',
          (AppStorage.get<number>('pageWallpaperDecodedRevision') ?? 0) + 1);
      } finally { await source.release(); }
    } finally { fileIo.closeSync(file); }
  }

  open(context: common.UIAbilityContext): Promise<void> {
    if (!this.opening) this.opening = this.initialize(context).catch((error: Error) => { this.opening = undefined; throw error; });
    return this.opening;
  }
  private async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.pref = await preferences.getPreferences(context, 'page_wallpaper');
    const source = await this.pref.get('source', 'none') as string;
    const local = await this.pref.get('local', '') as string;
    try {
      const saved = JSON.parse(await this.pref.get('library', '[]') as string) as LocalWallpaper[];
      this.library = Array.isArray(saved) ? saved.filter(item => this.ownsLocal(item.path) && item.width > 0 && item.height > 0) : [];
      this.library = this.library.filter(item => { try { return fileIo.statSync(item.path).size > 0; } catch (_) { return false; } });
      this.library.forEach(item => {
        item.portrait = cleanWallpaperCrop(item.portrait);
        item.landscape = cleanWallpaperCrop(item.landscape);
      });
    } catch (_) { this.library = []; }
    // Migrate the previous private local copy even when an online source is active.
    if (local && this.ownsLocal(local) && !this.library.some(item => item.path === local)) {
      try {
        const item = await this.describeLocal(local);
        this.library.push(item);
        await this.pref.put('library', JSON.stringify(this.library));
        await this.pref.flush();
      } catch (_) {}
    }
    this.publishLibrary();
    this.publishLocal(this.library.find(item => item.path === local));
    AppStorage.setOrCreate('pageWallpaperLocal', local);
    AppStorage.setOrCreate('pageWallpaperSource', ['pipw', 'picsum', 'local'].includes(source) ? source : 'none');
    const opacity = await this.pref.get('opacity', 0.7) as number;
    AppStorage.setOrCreate('pageWallpaperOpacity', Number.isFinite(opacity) ? Math.max(0.2, Math.min(1, opacity)) : 0.7);
    const scrim = await this.pref.get('scrim', 0) as number;
    AppStorage.setOrCreate('pageWallpaperScrim', clampWallpaperScrim(scrim));
    AppStorage.setOrCreate('pageWallpaperEnabled', false);
    if (source === 'local') {
      try { fileIo.statSync(local); await this.prepareImage(local); this.publish('local', local, local); } catch (_) {}
    }
  }
  private publish(source: string, portrait: string, landscape: string): void {
    AppStorage.setOrCreate('pageWallpaperPortrait', portrait);
    AppStorage.setOrCreate('pageWallpaperLandscape', landscape);
    AppStorage.setOrCreate('pageWallpaperSource', source);
    AppStorage.setOrCreate('pageWallpaperEnabled', source !== 'none' && !!(portrait || landscape));
  }
  async ensure(portrait: boolean): Promise<void> {
    const source = AppStorage.get<string>('pageWallpaperSource') ?? 'none';
    if (!['pipw', 'picsum'].includes(source)) return;
    const path = await this.download(source, portrait);
    if (source !== AppStorage.get<string>('pageWallpaperSource')) return;
    await this.prepareImage(path);
    if (source !== AppStorage.get<string>('pageWallpaperSource')) return;
    AppStorage.setOrCreate(portrait ? 'pageWallpaperPortrait' : 'pageWallpaperLandscape', path);
    AppStorage.setOrCreate('pageWallpaperEnabled', true);
  }
  async select(source: string, portrait: boolean, refresh: boolean = false, local: string = '', edited?: LocalWallpaper): Promise<void> {
    if (this.busy || !this.pref) throw new Error('壁纸正在处理中，请稍后重试');
    this.busy = true;
    AppStorage.setOrCreate('pageWallpaperBusy', true);
    try {
      let path = '';
      let selected: LocalWallpaper | undefined = undefined;
      let nextLibrary = this.library;
      if (source === 'local') {
        if (!this.ownsLocal(local)) throw new Error('请选择应用内的本地壁纸');
        selected = await this.describeLocal(local);
        const previous = edited ?? this.library.find(item => item.path === local);
        selected.portrait = cleanWallpaperCrop(previous?.portrait ?? new WallpaperCrop());
        selected.landscape = cleanWallpaperCrop(previous?.landscape ?? new WallpaperCrop());
        nextLibrary = [selected, ...this.library.filter(item => item.path !== local)];
        path = local;
      }
      else if (source !== 'none') { path = await this.download(source, portrait, refresh); }
      await this.prepareImage(path);
      await this.pref.put('source', source);
      if (source === 'local') {
        await this.pref.put('local', local);
        await this.pref.put('library', JSON.stringify(nextLibrary));
      }
      await this.pref.flush();
      if (source === 'local') {
        this.library = nextLibrary;
        this.publishLibrary();
        this.publishLocal(selected);
        AppStorage.setOrCreate('pageWallpaperLocal', local);
      }
      const other = this.loaded.get(source + (portrait ? '_landscape' : '_portrait')) ?? '';
      this.publish(source, source === 'local' || portrait ? path : other, source === 'local' || !portrait ? path : other);
    } finally { this.busy = false; AppStorage.setOrCreate('pageWallpaperBusy', false); }
  }
  async setOpacity(value: number): Promise<void> {
    if (!this.pref) return;
    await this.pref.put('opacity', value); await this.pref.flush();
    AppStorage.setOrCreate('pageWallpaperOpacity', value);
  }
  /** 壁纸遮罩强度（0–60），深浅色共用；持久化在 page_wallpaper 的 scrim 键。 */
  async setScrim(value: number): Promise<void> {
    const scrim = clampWallpaperScrim(value);
    AppStorage.setOrCreate('pageWallpaperScrim', scrim);
    if (!this.pref) return;
    await this.pref.put('scrim', scrim); await this.pref.flush();
  }
  localWallpapers(): LocalWallpaper[] { return this.library.slice(); }
  private ownsLocal(path: string): boolean {
    return !!this.context && typeof path === 'string' && path.startsWith(this.context.filesDir + '/') &&
      !path.slice(this.context.filesDir.length + 1).includes('/');
  }
  discardImport(path: string): void {
    if (!this.ownsLocal(path) || this.library.some(item => item.path === path) ||
      path === AppStorage.get<string>('pageWallpaperLocal')) return;
    if (!path.startsWith(this.context!.filesDir + '/page_wallpaper_local_')) return;
    try { fileIo.unlinkSync(path); } catch (_) {}
  }
  private publishLibrary(): void {
    AppStorage.setOrCreate('pageWallpaperLibraryRevision', Date.now());
  }
  private publishLocal(item?: LocalWallpaper): void {
    AppStorage.setOrCreate('pageWallpaperLocalComposition', JSON.stringify(item ?? new LocalWallpaper()));
  }
  async describeLocal(path: string): Promise<LocalWallpaper> {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const decoder = image.createImageSource(file.fd);
      try {
        const info = await decoder.getImageInfo();
        if (info.size.width <= 0 || info.size.height <= 0 || info.size.width * info.size.height > 40000000) throw new Error('图片尺寸不受支持');
        const item = new LocalWallpaper();
        item.path = path; item.width = info.size.width; item.height = info.size.height;
        return item;
      } finally { await decoder.release(); }
    } finally { fileIo.closeSync(file); }
  }
  async validateFile(path: string): Promise<void> { await this.describeLocal(path); }
  private download(source: string, portrait: boolean, refresh: boolean = false): Promise<string> {
    const key = source + (portrait ? '_portrait' : '_landscape');
    const existing = this.pending.get(key);
    if (existing) return existing;
    const task = this.fetch(source, portrait, key, refresh);
    this.pending.set(key, task);
    task.finally(() => this.pending.delete(key)).catch(() => {});
    return task;
  }
  private async fetch(source: string, portrait: boolean, key: string, refresh: boolean): Promise<string> {
    if (!this.context || !wallpaperEndpoint(source, portrait)) throw new Error('未知壁纸源');
    const path = this.context.filesDir + '/page_wallpaper_' + key + '.img';
    let cached = '';
    try {
      const stat = fileIo.statSync(path);
      if (stat.size > 0) {
        cached = path + '?v=' + stat.mtime;
        if (!refresh && Date.now() - stat.mtime * 1000 < 86400000) {
          const available = this.loaded.get(key) ?? cached;
          this.loaded.set(key, available); return available;
        }
      }
    } catch (_) {}
    const request = http.createHttp();
    const temporary = path + '.tmp';
    try {
      const endpoint = wallpaperEndpoint(source, portrait);
      const response = await request.request(endpoint + (endpoint.includes('?') ? '&' : '?') + 't=' + Date.now(), {
        method: http.RequestMethod.GET, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false, connectTimeout: 15000, readTimeout: 30000, maxLimit: 15 * 1024 * 1024
      });
      if (response.responseCode !== 200 || !(response.result instanceof ArrayBuffer) || !response.result.byteLength) throw new Error('壁纸源未返回图片');
      const file = fileIo.openSync(temporary, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        if (fileIo.writeSync(file.fd, response.result) !== response.result.byteLength) throw new Error('图片写入不完整');
      } finally { fileIo.closeSync(file); }
      await this.validateFile(temporary);
      fileIo.renameSync(temporary, path);
      const result = path + '?v=' + Date.now();
      this.loaded.set(key, result); return result;
    } catch (error) {
      if (!refresh && cached) { this.loaded.set(key, cached); return cached; }
      throw error as Error;
    } finally {
      request.destroy();
      try { fileIo.unlinkSync(temporary); } catch (_) {}
    }
  }
}
