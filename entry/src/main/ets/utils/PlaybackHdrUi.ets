import { uiEffect } from '@kit.ArkGraphics2D';
import { deviceInfo } from '@kit.BasicServicesKit';

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
