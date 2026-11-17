import { uiEffect } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { logWarn } from './Logger';

export class PlaybackHdrHeadroom {
  private displayId: number = -1;
  private subscribed: boolean = false;
  private headroom: number = 1;
  private update: ((headroom: number, sdrNits: number) => void) | null = null;

  private onBrightness = (displayId: number, info: display.BrightnessInfo): void => {
    if (displayId !== this.displayId || !this.update) return;
    // Avoid UI invalidation on every step of a display brightness ramp.
    const headroom = Number.isFinite(info.currentHeadroom) ?
      Math.floor(Math.max(1, Math.min(4, info.currentHeadroom)) * 4) / 4 : 1;
    if (Math.abs(this.headroom - headroom) < 0.01) return;
    this.headroom = headroom;
    this.update(headroom, info.sdrNits);
  };

  start(update: (headroom: number, sdrNits: number) => void): void {
    if (this.subscribed || !deviceInfo.apiAvailable(24)) return;
    try {
      this.update = update;
      this.displayId = display.getDefaultDisplaySync().id;
      this.onBrightness(this.displayId, display.getBrightnessInfo(this.displayId));
      display.on('brightnessInfoChange', this.onBrightness);
      this.subscribed = true;
    } catch (error) {
      this.update = null;
      logWarn('读取 HDR 控件亮度失败', error);
    }
  }

  stop(): void {
    this.update = null;
    if (!this.subscribed) return;
    this.subscribed = false;
    try { display.off('brightnessInfoChange', this.onBrightness); } catch (_) {}
  }
}

/** Keep SDR UI readable beside HDR video without changing the video or its colors. */
export function playbackHdrUiRatio(quality: number, headroom: number): number {
  if ((quality !== 125 && quality !== 126) || !Number.isFinite(headroom)) return 1;
  // Follow available display headroom, with a ceiling to avoid glaring controls.
  return Math.round(Math.max(1, Math.min(4, headroom)) * 100) / 100;
}

let cachedRatio: number = 1;
let cachedFilter: uiEffect.Filter | undefined = undefined;

export function playbackHdrUiFilter(ratio: number): uiEffect.Filter | undefined {
  if (!deviceInfo.apiAvailable(24) || !Number.isFinite(ratio) || ratio <= 1) return undefined;
  if (cachedFilter && cachedRatio === ratio) return cachedFilter;
  try {
    cachedFilter = uiEffect.createFilter().hdrBrightnessRatio(ratio);
    cachedRatio = ratio;
    return cachedFilter;
  } catch (error) {
    console.warn('[PlaybackHdrUi] HDR UI filter unavailable: ' + JSON.stringify(error));
    return undefined;
  }
}
