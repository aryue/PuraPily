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

  private apply(): void {
    const supported = this.foreground ? this.supportedRates() : [];
    const rate = this.foreground && supported.includes(this.selected) ? this.selected : 0;
    AppStorage.setOrCreate('highRefreshAvailable', this.selected === 0 || supported.includes(this.selected));
    if (rate === this.applied) return;
    const result = highRefresh.setRate(rate);
    // Native failures release the connection; do not retain stale applied state.
    this.applied = result === 0 ? rate : 0;
    if (result !== 0) throw new Error(`NativeVSync 请求失败：${result}`);
    logInfo(`[HighRefresh] foreground=${this.foreground}, requested=${rate} Hz`);
  }

  destroy(): void {
    this.setForeground(false);
    if (this.listening) {
      try { display.off('change', this.displayChanged); }
      catch (error) { logError('移除屏幕刷新率监听失败', error); }
      this.listening = false;
    }
    this.mainWindow = null;
    this.pref = null;
  }
}
