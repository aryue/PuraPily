import { window } from '@kit.ArkUI';
import type { common } from '@kit.AbilityKit';
import { StatusBarUtils } from '../utils/StatusBarUtils';

export class PlaybackWindow {
  private originalBrightness: number = -1;
  private barsKey: string = '';
  private refreshTimer: number = -1;
  private transitionTimer: number = -1;
  private transitionDone: ((finished: boolean) => void) | null = null;
  private landscapeExitPending: boolean = false;

  waitForTransition(duration: number): Promise<boolean> {
    this.cancelTransitionWait();
    return new Promise<boolean>(resolve => {
      this.transitionDone = resolve;
      this.transitionTimer = setTimeout(() => {
        this.transitionTimer = -1;
        this.transitionDone = null;
        resolve(true);
      }, duration);
    });
  }

  cancelTransitionWait(): void {
    if (this.transitionTimer !== -1) clearTimeout(this.transitionTimer);
    const done = this.transitionDone;
    this.transitionTimer = -1;
    this.transitionDone = null;
    done?.(false);
  }

  scheduleBarsRefresh(refresh: () => void): void {
    this.cancelBarsRefresh();
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1;
      refresh();
    }, 1000);
  }

  cancelBarsRefresh(): void {
    if (this.refreshTimer === -1) return;
    clearTimeout(this.refreshTimer);
    this.refreshTimer = -1;
  }

  async restoreAfterExit(win: window.Window | null, host: () => common.UIAbilityContext): Promise<void> {
    const remaining = Math.max(0, (AppStorage.get<number>('immersivePlayerAliveCount') ?? 1) - 1);
    AppStorage.setOrCreate('immersivePlayerAliveCount', remaining);
    if (!win) return;
    try {
      if (this.landscapeExitPending) await this.finishDeferredLandscapeExit(win);
      const context = host();
      if (remaining > 0) {
        await StatusBarUtils.setPlayerStatusBarContent(context, win);
      } else {
        await StatusBarUtils.restoreThemeStatusBarContent(context, win);
      }
      const hideStatusBar = AppStorage.get<boolean>('hideStatusBar') ?? false;
      await StatusBarUtils.setSystemBars(win, !hideStatusBar, true);
      await win.setPreferredOrientation(this.preferredOrientation());
    } catch (_) {}
  }

  async restoreAfterFullscreen(win: window.Window, getOrigin: () => window.Orientation | undefined,
    onPortraitLock: () => void, deferLandscapeMode: boolean = false): Promise<void> {
    this.landscapeExitPending = deferLandscapeMode;
    try {
      const origin = getOrigin();
      const orientation = origin ?? this.preferredOrientation();
      if (origin === undefined && orientation === window.Orientation.PORTRAIT) onPortraitLock();
      // Start the rotation first; the landscape-multiwindow teardown may reflow the window and
      // used to run before setPreferredOrientation, leaving a visible dead wait before rotation.
      const disableLandscape = deferLandscapeMode ? null : win.disableLandscapeMultiWindow().catch(() => {});
      await win.setPreferredOrientation(orientation);
      if (disableLandscape) await disableLandscape;
    } catch (_) {}
  }

  async finishDeferredLandscapeExit(win: window.Window): Promise<void> {
    if (!this.landscapeExitPending) return;
    this.landscapeExitPending = false;
    await win.disableLandscapeMultiWindow().catch(() => {});
  }

  async prepareFullscreen(win: window.Window, landscape: () => boolean): Promise<void> {
    const enableLandscape = win.enableLandscapeMultiWindow().catch(() => {});
    await win.setPreferredOrientation(landscape()
      ? window.Orientation.AUTO_ROTATION_LANDSCAPE : window.Orientation.AUTO_ROTATION_PORTRAIT);
    await enableLandscape;
  }

  async waitForStableViewport(matches: () => boolean, current: () => boolean): Promise<boolean> {
    let stableSince = -1;
    for (let attempt = 0; attempt < 100 && current(); attempt++) {
      if (matches()) {
        const now = Date.now();
        if (stableSince < 0) stableSince = now;
        if (now - stableSince >= 80) return true;
      } else {
        stableSince = -1;
      }
      await new Promise<void>(resolve => setTimeout(resolve, 20));
    }
    return false;
  }

  async waitForRotationEnd(rotating: () => boolean, current: () => boolean): Promise<void> {
    if (this.preferredOrientation() === window.Orientation.AUTO_ROTATION_LANDSCAPE) return;
    for (let attempt = 0; attempt < 15 && current() && rotating(); attempt++) {
      await new Promise<void>(resolve => setTimeout(resolve, 100));
    }
  }

  private preferredOrientation(): window.Orientation {
    switch (AppStorage.get<string>('screenOrientationLock') ?? '跟随系统') {
      case '跟随系统':
        return window.Orientation.AUTO_ROTATION_RESTRICTED;
      case '锁定竖屏':
        return window.Orientation.PORTRAIT;
      case '锁定横屏':
        return window.Orientation.AUTO_ROTATION_LANDSCAPE;
      default:
        return window.Orientation.AUTO_ROTATION;
    }
  }

  captureBrightness(win: window.Window): number {
    this.originalBrightness = win.getWindowProperties().brightness;
    return this.originalBrightness;
  }

  restoreBrightness(win: window.Window | null): void {
    win?.setWindowBrightness(this.originalBrightness);
  }

  keepScreenOn(win: window.Window | null, enabled: boolean): void {
    win?.setWindowKeepScreenOn(enabled).catch(() => {});
  }

  applyBars(win: window.Window, visible: boolean, navigation: boolean, force: boolean): void {
    // Repeating the same window request can trigger avoid-area relayout.
    const key = `${visible}|${navigation}`;
    if (!force && this.barsKey === key) return;
    this.barsKey = key;
    StatusBarUtils.setSystemBars(win, visible, navigation);
  }
}
