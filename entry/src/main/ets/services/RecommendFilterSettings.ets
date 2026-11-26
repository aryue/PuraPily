import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { logError, logInfo, logWarn } from '../utils/Logger';
import { RecommendFilterConfig, compileKeywordRules, keywordLines } from '../model/RecommendFilterModel';

const PREF_NAME: string = 'my_app_settings';

export const FILTER_KEY_ENABLED: string = 'rcmdFilterEnabled';
export const FILTER_KEY_TITLE: string = 'rcmdFilterTitleKeywords';
export const FILTER_KEY_UP: string = 'rcmdFilterUpKeywords';
export const FILTER_KEY_ZONE: string = 'rcmdFilterZoneKeywords';
export const FILTER_KEY_MIN_DURATION: string = 'rcmdFilterMinDuration';
export const FILTER_KEY_MIN_PLAY: string = 'rcmdFilterMinPlay';
export const FILTER_KEY_MIN_LIKE: string = 'rcmdFilterMinLikeRatio';
export const FILTER_KEY_EXEMPT_FOLLOWED: string = 'rcmdFilterExemptFollowed';
export const FILTER_KEY_RELATED: string = 'rcmdFilterRelated';
export const FILTER_KEY_HOT: string = 'rcmdFilterHot';
export const FILTER_KEY_RANK: string = 'rcmdFilterRank';
export const FILTER_KEY_SEARCH: string = 'rcmdFilterSearch';
export const FILTER_KEY_UNPLAYABLE: string = 'rcmdFilterRemoveUnplayable';
export const FILTER_KEY_WHITELIST: string = 'rcmdFilterWhitelistUsers';
export const FILTER_KEY_BLOCKED_NAMES: string = 'blockedUploaderNames';
export const FILTER_KEY_REVISION: string = 'rcmdFilterRevision';

export class FilterUserEntry {
  mid: string = '';
  name: string = '';

  constructor(mid: string = '', name: string = '') {
    this.mid = mid;
    this.name = name;
  }
}

function parseStringArray(raw: string): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as string[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function parseUserEntries(raw: string): FilterUserEntry[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as FilterUserEntry[];
    if (!Array.isArray(parsed)) return [];
    const result: FilterUserEntry[] = [];
    for (let i = 0; i < parsed.length; i++) {
      const mid = String(parsed[i].mid || '');
      if (mid.length > 0) {
        result.push(new FilterUserEntry(mid, String(parsed[i].name || '')));
      }
    }
    return result;
  } catch (_) {
    return [];
  }
}

function parseNameRecord(raw: string): Record<string, string> {
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, string>;
  } catch (_) {
    return {};
  }
}

function copyNameRecord(source: Record<string, string>): Record<string, string> {
  const next: Record<string, string> = {};
  const keys = Object.keys(source);
  for (let i = 0; i < keys.length; i++) {
    next[keys[i]] = source[keys[i]];
  }
  return next;
}

export class RecommendFilterSettings {
  private static cachedConfig: RecommendFilterConfig | null = null;
  private static cachedRevision: number = -1;

  /** 启动期同步招呼一次，保证首屏请求前规则已经就绪。 */
  static loadSync(context: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(context, { name: PREF_NAME });
      RecommendFilterSettings.applyPreferenceSnapshot(pref);
    } catch (error) {
      logError(`[推荐过滤] 加载设置失败: ${error}`);
    }
  }

  static async load(context: common.Context): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, PREF_NAME);
      RecommendFilterSettings.applyPreferenceSnapshot(pref);
    } catch (error) {
      logError(`[推荐过滤] 加载设置失败: ${error}`);
    }
  }

  private static applyPreferenceSnapshot(pref: preferences.Preferences): void {
    AppStorage.setOrCreate(FILTER_KEY_ENABLED, pref.getSync(FILTER_KEY_ENABLED, true) === true);
    AppStorage.setOrCreate(FILTER_KEY_TITLE, pref.getSync(FILTER_KEY_TITLE, '') as string);
    AppStorage.setOrCreate(FILTER_KEY_UP, pref.getSync(FILTER_KEY_UP, '') as string);
    AppStorage.setOrCreate(FILTER_KEY_ZONE, pref.getSync(FILTER_KEY_ZONE, '') as string);
    AppStorage.setOrCreate(FILTER_KEY_MIN_DURATION, pref.getSync(FILTER_KEY_MIN_DURATION, 0) as number);
    AppStorage.setOrCreate(FILTER_KEY_MIN_PLAY, pref.getSync(FILTER_KEY_MIN_PLAY, 0) as number);
    AppStorage.setOrCreate(FILTER_KEY_MIN_LIKE, pref.getSync(FILTER_KEY_MIN_LIKE, 0) as number);
    AppStorage.setOrCreate(FILTER_KEY_EXEMPT_FOLLOWED, pref.getSync(FILTER_KEY_EXEMPT_FOLLOWED, true) === true);
    AppStorage.setOrCreate(FILTER_KEY_RELATED, pref.getSync(FILTER_KEY_RELATED, true) === true);
    AppStorage.setOrCreate(FILTER_KEY_HOT, pref.getSync(FILTER_KEY_HOT, false) === true);
    AppStorage.setOrCreate(FILTER_KEY_RANK, pref.getSync(FILTER_KEY_RANK, false) === true);
    AppStorage.setOrCreate(FILTER_KEY_SEARCH, pref.getSync(FILTER_KEY_SEARCH, false) === true);
    AppStorage.setOrCreate(FILTER_KEY_UNPLAYABLE, pref.getSync(FILTER_KEY_UNPLAYABLE, false) === true);

    const blockedRaw = pref.getSync('blockedUploaders', '') as string;
    const blocked = new Set<string>(parseStringArray(blockedRaw));
    AppStorage.setOrCreate('blockedUploaders', blocked);
    const namesRaw = pref.getSync(FILTER_KEY_BLOCKED_NAMES, '') as string;
    AppStorage.setOrCreate(FILTER_KEY_BLOCKED_NAMES, parseNameRecord(namesRaw));

    const whitelistRaw = pref.getSync(FILTER_KEY_WHITELIST, '[]') as string;
    AppStorage.setOrCreate(FILTER_KEY_WHITELIST, parseUserEntries(whitelistRaw));

    RecommendFilterSettings.bumpRevision();
    logInfo(`[推荐过滤] 设置已载入：屏蔽 ${blocked.size}，白名单 ` +
      `${AppStorage.get<FilterUserEntry[]>(FILTER_KEY_WHITELIST)?.length ?? 0}`);
  }

  static bumpRevision(): void {
    AppStorage.setOrCreate(FILTER_KEY_REVISION,
      (AppStorage.get<number>(FILTER_KEY_REVISION) ?? 0) + 1);
    RecommendFilterSettings.cachedConfig = null;
    RecommendFilterSettings.cachedRevision = -1;
  }

  static getKeywordText(kind: string): string {
    const key = RecommendFilterSettings.keywordKey(kind);
    const stored = AppStorage.get<string>(key) ?? '';
    // 新格式是 JSON 数组，规避 Preferences 对多行字符串的持久化问题；
    // 旧版本直接存换行文本，继续兼容读取。
    if (!stored.trim().startsWith('[')) return stored;
    try {
      const items = JSON.parse(stored) as string[];
      return Array.isArray(items) ? items.join('\n') : stored;
    } catch (_) {
      return stored;
    }
  }

  static setKeywordText(kind: string, text: string): void {
    const key = RecommendFilterSettings.keywordKey(kind);
    const encoded = JSON.stringify(keywordLines(text));
    AppStorage.setOrCreate(key, encoded);
    RecommendFilterSettings.bumpRevision();
    void RecommendFilterSettings.persist(key, encoded);
  }

  private static keywordKey(kind: string): string {
    if (kind === 'up') return FILTER_KEY_UP;
    if (kind === 'zone') return FILTER_KEY_ZONE;
    return FILTER_KEY_TITLE;
  }

  static getNumber(key: string, fallback: number): number {
    const value = AppStorage.get<number>(key);
    return typeof value === 'number' ? value : fallback;
  }

  static setNumber(key: string, value: number): void {
    AppStorage.setOrCreate(key, value);
    RecommendFilterSettings.bumpRevision();
    void RecommendFilterSettings.persist(key, value);
  }

  static getBoolean(key: string, fallback: boolean): boolean {
    const value = AppStorage.get<boolean>(key);
    return typeof value === 'boolean' ? value : fallback;
  }

  static setBoolean(key: string, value: boolean): void {
    AppStorage.setOrCreate(key, value);
    RecommendFilterSettings.bumpRevision();
    void RecommendFilterSettings.persist(key, value);
  }

  static blockedEntries(): FilterUserEntry[] {
    const blocked = AppStorage.get<Set<string>>('blockedUploaders') ?? new Set<string>();
    const names = AppStorage.get<Record<string, string>>(FILTER_KEY_BLOCKED_NAMES) ?? {};
    const entries: FilterUserEntry[] = [];
    blocked.forEach((mid: string) => {
      const name = names[mid] || `UID:${mid}`;
      entries.push(new FilterUserEntry(mid, name));
    });
    entries.sort((a: FilterUserEntry, b: FilterUserEntry) => a.name.localeCompare(b.name));
    return entries;
  }

  static whitelistEntries(): FilterUserEntry[] {
    const entries = AppStorage.get<FilterUserEntry[]>(FILTER_KEY_WHITELIST) ?? [];
    const copy = entries.slice();
    copy.sort((a: FilterUserEntry, b: FilterUserEntry) => a.name.localeCompare(b.name));
    return copy;
  }

  static addWhitelist(mid: string, name: string): void {
    const entries = RecommendFilterSettings.whitelistEntries();
    const next: FilterUserEntry[] = [];
    let replaced = false;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].mid === mid) {
        next.push(new FilterUserEntry(mid, name || entries[i].name));
        replaced = true;
      } else {
        next.push(entries[i]);
      }
    }
    if (!replaced) next.push(new FilterUserEntry(mid, name || `UID:${mid}`));
    AppStorage.setOrCreate(FILTER_KEY_WHITELIST, next);
    RecommendFilterSettings.bumpRevision();
    void RecommendFilterSettings.persist(FILTER_KEY_WHITELIST, JSON.stringify(next));
  }

  static removeWhitelist(mid: string): void {
    const entries = RecommendFilterSettings.whitelistEntries()
      .filter((entry: FilterUserEntry) => entry.mid !== mid);
    AppStorage.setOrCreate(FILTER_KEY_WHITELIST, entries);
    RecommendFilterSettings.bumpRevision();
    void RecommendFilterSettings.persist(FILTER_KEY_WHITELIST, JSON.stringify(entries));
  }

  static blockedNames(): Record<string, string> {
    return copyNameRecord(
      AppStorage.get<Record<string, string>>(FILTER_KEY_BLOCKED_NAMES) ?? {});
  }

  /** 供 UserBehaviorService 在拉黑/取消拉黑时同步显示名。 */
  static setBlockedName(mid: string, name: string): void {
    if (!mid || !name) return;
    const names = RecommendFilterSettings.blockedNames();
    names[mid] = name;
    AppStorage.setOrCreate(FILTER_KEY_BLOCKED_NAMES, names);
    void RecommendFilterSettings.persist(FILTER_KEY_BLOCKED_NAMES, JSON.stringify(names));
  }

  static removeBlockedName(mid: string): void {
    const names = RecommendFilterSettings.blockedNames();
    if (names[mid] === undefined) return;
    const next: Record<string, string> = {};
    const keys = Object.keys(names);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== mid) next[keys[i]] = names[keys[i]];
    }
    AppStorage.setOrCreate(FILTER_KEY_BLOCKED_NAMES, next);
    void RecommendFilterSettings.persist(FILTER_KEY_BLOCKED_NAMES, JSON.stringify(next));
  }

  /** 规则快照按 revision 缓存，避免每次列表项都重新编译关键词正则。 */
  static config(): RecommendFilterConfig {
    const revision = AppStorage.get<number>(FILTER_KEY_REVISION) ?? 0;
    if (RecommendFilterSettings.cachedConfig !== null &&
      RecommendFilterSettings.cachedRevision === revision) {
      return RecommendFilterSettings.cachedConfig;
    }
    const config = new RecommendFilterConfig();
    config.enabled = RecommendFilterSettings.getBoolean(FILTER_KEY_ENABLED, true);
    config.titleRules = compileKeywordRules(RecommendFilterSettings.getKeywordText('title'));
    config.upNameRules = compileKeywordRules(RecommendFilterSettings.getKeywordText('up'));
    config.zoneRules = compileKeywordRules(RecommendFilterSettings.getKeywordText('zone'));
    config.minDuration = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_DURATION, 0);
    config.minPlay = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_PLAY, 0);
    config.minLikeRatio = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_LIKE, 0);
    config.exemptFollowed = RecommendFilterSettings.getBoolean(FILTER_KEY_EXEMPT_FOLLOWED, true);
    config.applyRelated = RecommendFilterSettings.getBoolean(FILTER_KEY_RELATED, true);
    config.applyHot = RecommendFilterSettings.getBoolean(FILTER_KEY_HOT, false);
    config.applyRank = RecommendFilterSettings.getBoolean(FILTER_KEY_RANK, false);
    config.applySearch = RecommendFilterSettings.getBoolean(FILTER_KEY_SEARCH, false);
    config.removeUnplayable = RecommendFilterSettings.getBoolean(FILTER_KEY_UNPLAYABLE, false);
    config.blockedMids = AppStorage.get<Set<string>>('blockedUploaders') ?? new Set<string>();

    const whitelist = RecommendFilterSettings.whitelistEntries();
    const whitelistMids = new Set<string>();
    for (let i = 0; i < whitelist.length; i++) {
      whitelistMids.add(whitelist[i].mid);
    }
    config.whitelistMids = whitelistMids;

    RecommendFilterSettings.cachedConfig = config;
    RecommendFilterSettings.cachedRevision = revision;
    return config;
  }

  private static async persist(key: string, value: string | number | boolean): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        logWarn(`[推荐过滤] 无法获取 context，${key} 仅本次会话生效`);
        return;
      }
      const pref = await preferences.getPreferences(context, PREF_NAME);
      await pref.put(key, value);
      await pref.flush();
    } catch (error) {
      logError(`[推荐过滤] 保存 ${key} 失败: ${error}`);
    }
  }
}
