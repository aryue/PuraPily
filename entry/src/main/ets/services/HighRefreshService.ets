import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import highRefresh from 'libhigh_refresh.so';
import { logError, logInfo } from '../utils/Logger';

const RATE_KEY: string = 'highRefreshRate';

export class HighRefreshService {
  private static instance: HighRefreshService = new HighRefreshService();
  private pref: preferences.Preferences | null = null;
  private mainWindow: window.Window | null = null;
  private foreground: boolean = false;
  private listening: boolean = false;
  private selected: number = 0;
  private applied: number = 0;
  /** 正在播放的播放器实例：跟随系统时由它们把面板撑在最高可用档。 */
  private playing: Set<number> = new Set();
  private displayChanged: (id: number) => void = (_id: number): void => {
    if (this.foreground) this.setForeground(true);
  };

  static getInstance(): HighRefreshService { return HighRefreshService.instance; }

  initialize(context: common.UIAbilityContext): void {
    try {
      this.pref = preferences.getPreferencesSync(context, { name: 'my_app_settings' });
      const saved = this.pref.getSync(RATE_KEY, 0) as number;
      this.selected = [90, 120, 144].includes(saved) ? saved : 0;
    } catch (error) { logError('读取高刷设置失败', error); }
    AppStorage.setOrCreate(RATE_KEY, this.selected);
    try {
      display.on('change', this.displayChanged);
      this.listening = true;
    } catch (error) { logError('监听屏幕刷新率变化失败', error); }
  }

  setMainWindow(mainWindow: window.Window): void {
    this.mainWindow = mainWindow;
    if (this.foreground) this.setForeground(true);
  }

  supportedRates(): number[] {
    try {
      const screen = this.mainWindow
        ? display.getDisplayByIdSync(this.mainWindow.getWindowProperties().displayId)
        : display.getDefaultDisplaySync();
      // Never infer hardware support from the current rate or the maximum alone.
      const supported = screen.supportedRefreshRates ?? [];
      const rates = [90, 120, 144].filter((rate: number) => supported.includes(rate));
      AppStorage.setOrCreate('highRefreshSupportedRates', rates);
      return rates;
    } catch (error) {
      logError('查询设备高刷档位失败', error);
      AppStorage.setOrCreate('highRefreshSupportedRates', [] as number[]);
      return [];
    }
  }

  choose(rate: number): void {
    if (rate !== 0 && !this.supportedRates().includes(rate)) throw new Error('设备不支持此刷新率');
    if (!this.pref) throw new Error('设置尚未准备好');
    const previous = this.selected;
    this.selected = rate;
    try {
      this.apply();
      this.pref.putSync(RATE_KEY, rate);
      this.pref.flushSync();
      AppStorage.setOrCreate(RATE_KEY, rate);
    } catch (error) {
      this.selected = previous;
      this.apply();
      this.pref.putSync(RATE_KEY, previous);
      throw new Error('无法应用或保存高刷设置');
    }
  }

  setForeground(value: boolean): void {
    this.foreground = value;
    try { this.apply(); } catch (error) { logError('应用高刷请求失败', error); }
  }

  /**
   * 播放器登记「正在播放」。跟随系统时系统会在无触摸时把面板降回 60Hz，
   * 所以播放期间必须由应用自己撑住最高可用档；用户手动选了 90/120/144 时档位已常驻，不参与合并。
   * owner 为播放器实例号：连刷/预览多实例各自登记，退出只移除自己那条。
   */
  setPlaybackActive(active: boolean, owner: number): void {
    const wasActive = this.playing.has(owner);
    if (active) this.playing.add(owner); else this.playing.delete(owner);
    // Feed previews start/stop constantly; only a real change is worth a line.
    if (wasActive !== active) {
      logInfo(`[HighRefresh] playback active=${active}, owners=${this.playing.size}`);
    }
    try { this.apply(); } catch (error) { logError('应用播放高刷失败', error); }
  }

  private apply(): void {
    const supported = this.foreground ? this.supportedRates() : [];
    // 跟随系统（0）且正在播放 → 自己请求最高可用档，避免无触摸时掉回 60Hz。
    const content = this.selected === 0 && this.playing.size > 0 && supported.length > 0
      ? supported[supported.length - 1] : 0;
    const wanted = Math.max(this.selected, content);
    const rate = this.foreground && supported.includes(wanted) ? wanted : 0;
    AppStorage.setOrCreate('highRefreshAvailable', this.selected === 0 || supported.includes(this.selected));
    if (rate === this.applied) return;
    logInfo(`[HighRefresh] apply selected=${this.selected} playing=${this.playing.size} supported=[${supported.join(',')}] rate=${rate}`);
    const result = highRefresh.setRate(rate);
    // Native failures release the connection; do not retain stale applied state.
    this.applied = result === 0 ? rate : 0;
    if (result !== 0) throw new Error(`NativeVSync 请求失败：${result}`);
    logInfo(`[HighRefresh] foreground=${this.foreground}, requested=${rate} Hz`);
  }

  destroy(): void {
    this.setForeground(false);
    this.playing.clear();
    if (this.listening) {
      try { display.off('change', this.displayChanged); }
      catch (error) { logError('移除屏幕刷新率监听失败', error); }
      this.listening = false;
    }
    this.mainWindow = null;
    this.pref = null;
  }
}
