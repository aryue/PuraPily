import { ordinaryCardColor } from './SurfaceColors';
import { alphaHexFromPercent } from './ThemeColor';

/** Wallpaper cards preserve opacity settings; neutral pages use the shared solid surface. */
export function cardItemBg(isDark: boolean, transparent: boolean, bgOpacity: number,
  wallpaper: boolean = true): string {
  if (transparent && wallpaper) {
    return isDark ? `rgba(0,0,0,${bgOpacity / 100})` : `rgba(255,255,255,${bgOpacity / 100})`;
  }
  return ordinaryCardColor(isDark);
}

export function cardItemBorder(isDark: boolean, transparent: boolean,
  borderOpacity: number, followTheme: boolean, themeColor: string): string {
  if (!transparent) {
    return 'rgba(0,0,0,0)';
  }
  if (followTheme) {
    // ⚠️ ArkUI 颜色串 alpha 在前
    return '#' + alphaHexFromPercent(borderOpacity) + themeColor.slice(1);
  }
  return isDark ? `rgba(255,255,255,${borderOpacity / 100})` : 'rgba(255,255,255,0.25)';
}
