import { SkipMode, SKIP_CATEGORIES } from '../model/SkipSegment';

/**
 * 空降助手设置读取。
 *
 * 设置页负责把值写进 Preferences + AppStorage；这里只做带默认值的读取，
 * 播放页每条路径都能直接调用，不依赖设置页是否已打开。
 */
export class SponsorBlockPrefs {
  static readonly DEFAULT_SERVER: string = 'https://www.bsbsb.top';
  static readonly DEFAULT_MODES: string = '111111111111';

  static enabled(): boolean {
    return AppStorage.get<boolean>('sponsorBlockEnabled') ?? false;
  }

  static toastEnabled(): boolean {
    return AppStorage.get<boolean>('sponsorBlockToast') ?? true;
  }

  static seekIntoEnabled(): boolean {
    return AppStorage.get<boolean>('sponsorBlockSeekInto') ?? false;
  }

  static minSegmentMs(): number {
    const value = AppStorage.get<number>('sponsorBlockLimitMs') ?? 0;
    return Math.max(0, value);
  }

  static server(): string {
    const value = AppStorage.get<string>('sponsorBlockServer') ?? SponsorBlockPrefs.DEFAULT_SERVER;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed.replace(/\/+$/, '') : SponsorBlockPrefs.DEFAULT_SERVER;
  }

  static modesRaw(): string {
    const raw = AppStorage.get<string>('sponsorBlockModes') ?? SponsorBlockPrefs.DEFAULT_MODES;
    return SponsorBlockPrefs.normalizeModes(raw);
  }

  static setModesRaw(raw: string): void {
    AppStorage.setOrCreate('sponsorBlockModes', SponsorBlockPrefs.normalizeModes(raw));
  }

  static categoryMode(index: number): SkipMode {
    const raw = SponsorBlockPrefs.modesRaw();
    const char = index >= 0 && index < raw.length ? raw.charAt(index) : '1';
    const value = parseInt(char, 10);
    return SponsorBlockPrefs.modeFromIndex(Number.isFinite(value) ? value : 1);
  }

  static setCategoryMode(index: number, mode: SkipMode): string {
    if (index < 0 || index >= SKIP_CATEGORIES.length) return SponsorBlockPrefs.modesRaw();
    const current = SponsorBlockPrefs.modesRaw();
    const chars: string[] = [];
    for (let i = 0; i < SKIP_CATEGORIES.length; i++) {
      chars.push(i === index ? SponsorBlockPrefs.modeIndex(mode).toString() : current.charAt(i));
    }
    const next = chars.join('');
    SponsorBlockPrefs.setModesRaw(next);
    return next;
  }

  static pgcMode(): SkipMode {
    const raw = AppStorage.get<string>('sponsorBlockPgcMode') ?? SkipMode.Once;
    return SponsorBlockPrefs.modeFromName(raw);
  }

  static modeIndex(mode: SkipMode): number {
    switch (mode) {
      case SkipMode.Always:
        return 0;
      case SkipMode.Manual:
        return 2;
      case SkipMode.Show:
        return 3;
      case SkipMode.Disable:
        return 4;
      default:
        return 1;
    }
  }

  static modeFromIndex(index: number): SkipMode {
    switch (index) {
      case 0:
        return SkipMode.Always;
      case 2:
        return SkipMode.Manual;
      case 3:
        return SkipMode.Show;
      case 4:
        return SkipMode.Disable;
      default:
        return SkipMode.Once;
    }
  }

  static modeFromName(name: string): SkipMode {
    switch (name) {
      case SkipMode.Always:
        return SkipMode.Always;
      case SkipMode.Manual:
        return SkipMode.Manual;
      case SkipMode.Show:
        return SkipMode.Show;
      case SkipMode.Disable:
        return SkipMode.Disable;
      default:
        return SkipMode.Once;
    }
  }

  private static normalizeModes(raw: string): string {
    const chars: string[] = [];
    for (let i = 0; i < SKIP_CATEGORIES.length; i++) {
      const char = i < raw.length ? raw.charAt(i) : '1';
      chars.push(char >= '0' && char <= '4' ? char : '1');
    }
    return chars.join('');
  }
}
