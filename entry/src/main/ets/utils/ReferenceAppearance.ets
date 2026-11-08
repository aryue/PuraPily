import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { preferences } from '@kit.ArkData';
import { initializeLoginCredentials } from './CredentialStore';
import { logWarn } from './Logger';

/** Loads existing functional preferences, then applies the replacement visual system. */
export async function initializeReferenceAppearance(context: common.UIAbilityContext): Promise<void> {
  const pref = await preferences.getPreferences(context, 'my_app_settings');
  AppStorage.setOrCreate('videoCardEdgeLight', await pref.get('videoCardEdgeLight', false) as boolean);
  AppStorage.setOrCreate('videoCardGlassTint', await pref.get('videoCardGlassTint', true) as boolean);
  const thickness = await pref.get('videoCardGlassThickness', 'thin') as string;
  AppStorage.setOrCreate('videoCardGlassThickness', ['ultra-thin', 'thin', 'regular', 'thick', 'ultra-thick'].includes(thickness) ? thickness : 'thin');
  AppStorage.setOrCreate('otherCardGlassEnabled', await pref.get('otherCardGlassEnabled', true) as boolean);
  AppStorage.setOrCreate('otherCardGlassTint', await pref.get('otherCardGlassTint', true) as boolean);
  const otherThickness = await pref.get('otherCardGlassThickness', 'thick') as string;
  AppStorage.setOrCreate('otherCardGlassThickness', ['ultra-thin', 'thin', 'regular', 'thick', 'ultra-thick'].includes(otherThickness) ? otherThickness : 'thick');
  AppStorage.setOrCreate('floatingBottomBar', await pref.get('floatingBottomBar', true) as boolean);
  AppStorage.setOrCreate('bottomBarSmartGrip', await pref.get('bottomBarSmartGrip', false) as boolean);
  AppStorage.setOrCreate('wallpaper', await pref.get('wallpaper', 'builtin') as string);
  AppStorage.setOrCreate('customWallpaper', await pref.get('customWallpaper', '') as string);
  AppStorage.setOrCreate('wallpaperColor', await pref.get('wallpaperColor', '#007DFF') as string);
  AppStorage.setOrCreate('wallpaperBlur', await pref.get('wallpaperBlur', 0) as number);
  AppStorage.setOrCreate('wallpaperDarkness', await pref.get('wallpaperDarkness', 50) as number);
  AppStorage.setOrCreate('cardTransparentStyle', await pref.get('cardTransparentStyle', true) as boolean);
  AppStorage.setOrCreate('cardBorderFollowTheme', await pref.get('cardBorderFollowTheme', true) as boolean);
  AppStorage.setOrCreate('cardBorderFollowPlayCount', await pref.get('cardBorderFollowPlayCount', false) as boolean);
  AppStorage.setOrCreate('cardBorderOpacity', await pref.get('cardBorderOpacity', 25) as number);
  AppStorage.setOrCreate('cardBgOpacity', await pref.get('cardBgOpacity', 70) as number);
  AppStorage.setOrCreate('cardBorderWidth', await pref.get('cardBorderWidth', 1) as number);
  AppStorage.setOrCreate('cardCustomColor', await pref.get('cardCustomColor', '') as string);
  AppStorage.setOrCreate('cardCapsuleFollowTheme', await pref.get('cardCapsuleFollowTheme', false) as boolean);
  AppStorage.setOrCreate('cardCapsuleShow', await pref.get('cardCapsuleShow', true) as boolean);
  AppStorage.setOrCreate('cardCapsuleSize', await pref.get('cardCapsuleSize', 12) as number);
  AppStorage.setOrCreate('cardCapsuleRadius', await pref.get('cardCapsuleRadius', 7) as number);
  AppStorage.setOrCreate('cardCapsuleColor', await pref.get('cardCapsuleColor', '') as string);
  AppStorage.setOrCreate('cardPlayCountShow', await pref.get('cardPlayCountShow', true) as boolean);
  AppStorage.setOrCreate('cardPlayCountUnit', await pref.get('cardPlayCountUnit', 'wanYi') as string);
  AppStorage.setOrCreate('cardPlayCountSize', await pref.get('cardPlayCountSize', 12) as number);
  AppStorage.setOrCreate('cardPlayCountColorMode', await pref.get('cardPlayCountColorMode', 'level') as string);
  AppStorage.setOrCreate('cardPlayCountColor', await pref.get('cardPlayCountColor', '') as string);
  AppStorage.setOrCreate('cardPlayCountIcon', await pref.get('cardPlayCountIcon', true) as boolean);
  AppStorage.setOrCreate('cardStylePerMode', await pref.get('cardStylePerMode', true) as boolean);
  AppStorage.setOrCreate('playerFollowTheme', await pref.get('playerFollowTheme', true) as boolean);
  AppStorage.setOrCreate('cardBgBlurAmount', await pref.get('cardBgBlurAmount', 24) as number);
  AppStorage.setOrCreate('cardBgDarkness', await pref.get('cardBgDarkness', 50) as number);
  AppStorage.setOrCreate('cardTransparentStyleVideo', await pref.get('cardTransparentStyleVideo', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoDetail', await pref.get('cardStyleVideoDetail', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoCommentSection', await pref.get('cardStyleVideoCommentSection', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoCommentBubble', await pref.get('cardStyleVideoCommentBubble', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoDescription', await pref.get('cardStyleVideoDescription', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoSegmentBtn', await pref.get('cardStyleVideoSegmentBtn', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoInteractBtns', await pref.get('cardStyleVideoInteractBtns', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoNavBtns', await pref.get('cardStyleVideoNavBtns', true) as boolean);
  AppStorage.setOrCreate('cardStyleVideoCommentAlign', await pref.get('cardStyleVideoCommentAlign', 'center') as string);
  AppStorage.setOrCreate('videoBgMode', await pref.get('videoBgMode', 'cover') as string);
  AppStorage.setOrCreate('videoBgColor', await pref.get('videoBgColor', '#007DFF') as string);
  AppStorage.setOrCreate('videoBgCustomWallpaper', await pref.get('videoBgCustomWallpaper', '') as string);
  AppStorage.setOrCreate('videoBgCustomWallpaperBlur', await pref.get('videoBgCustomWallpaperBlur', 0) as number);
  AppStorage.setOrCreate('videoBgCustomWallpaperDarkness', await pref.get('videoBgCustomWallpaperDarkness', 50) as number);
  AppStorage.setOrCreate('cardStyleSearchSuggest', await pref.get('cardStyleSearchSuggest', true) as boolean);
  AppStorage.setOrCreate('cardStyleLiveCategory', await pref.get('cardStyleLiveCategory', true) as boolean);
  AppStorage.setOrCreate('cardStyleLiveQuality', await pref.get('cardStyleLiveQuality', true) as boolean);
  AppStorage.setOrCreate('cardBorderRadius', await pref.get('cardBorderRadius', 30) as number);
  AppStorage.setOrCreate('cardMargin', await pref.get('cardMargin', 12) as number);
  AppStorage.setOrCreate('cardListBorderRadius', await pref.get('cardListBorderRadius', 12) as number);
  AppStorage.setOrCreate('cardListMargin', await pref.get('cardListMargin', 12) as number);
  AppStorage.setOrCreate('capsuleColorIcons', await pref.get('capsuleColorIcons', true) as boolean);
  AppStorage.setOrCreate('smartGripEnabled', await pref.get('smartGripEnabled', true) as boolean);
  AppStorage.setOrCreate('floatBtnFollowTheme', await pref.get('floatBtnFollowTheme', true) as boolean);
  AppStorage.setOrCreate('floatBtnRotationSpeed', await pref.get('floatBtnRotationSpeed', 8) as number);
  AppStorage.setOrCreate('pageEnterAnim', await pref.get('pageEnterAnim', 'scaleFade') as string);
  AppStorage.setOrCreate('fsAnimOn', await pref.get('fsAnimOn', true) as boolean);
  try { await initializeLoginCredentials(context); } catch (error) {
    AppStorage.setOrCreate('biliCookie', '');
    AppStorage.setOrCreate('biliAccessKey', '');
    logWarn(`安全凭据暂不可读取，请解锁设备后重试: ${error}`);
  }
  AppStorage.setOrCreate('hideStatusBar', await pref.get('hideStatusBar', false) as boolean);
  AppStorage.setOrCreate('shrinkVideoOnScroll', await pref.get('shrinkVideoOnScroll', false) as boolean);
  AppStorage.setOrCreate('msgTabAutoHide', await pref.get('msgTabAutoHide', false) as boolean);
  AppStorage.setOrCreate('dynFilterTapOnly', await pref.get('dynFilterTapOnly', true) as boolean);
  AppStorage.setOrCreate('homeFilterTapOnly', await pref.get('homeFilterTapOnly', false) as boolean);
  AppStorage.setOrCreate('shrinkWindowStyle', await pref.get('shrinkWindowStyle', 'circle') as string);
  AppStorage.setOrCreate('shrinkPauseOnMinimize', await pref.get('shrinkPauseOnMinimize', false) as boolean);
  AppStorage.setOrCreate('shrinkWindowSize', await pref.get('shrinkWindowSize', 120) as number);
  AppStorage.setOrCreate('showRefreshSeparator', await pref.get('showRefreshSeparator', true) as boolean);
  AppStorage.setOrCreate('showHomeCarouselPortrait', await pref.get('showHomeCarouselPortrait', true) as boolean);
  AppStorage.setOrCreate('showHomeCarouselLandscape', await pref.get('showHomeCarouselLandscape', true) as boolean);
  AppStorage.setOrCreate('showCarouselBgPortrait', await pref.get('showCarouselBgPortrait', true) as boolean);
  AppStorage.setOrCreate('showCarouselBgLandscape', await pref.get('showCarouselBgLandscape', true) as boolean);
  AppStorage.setOrCreate('carouselBgRadius', await pref.get('carouselBgRadius', 30) as number);
  AppStorage.setOrCreate('carouselTitleFontSize', await pref.get('carouselTitleFontSize', 15) as number);
  AppStorage.setOrCreate('carouselTitleFontWeight', await pref.get('carouselTitleFontWeight', 'medium') as string);
  AppStorage.setOrCreate('carouselTitleCapsuleWidth', await pref.get('carouselTitleCapsuleWidth', 85) as number);
  AppStorage.setOrCreate('carouselTitleCapsuleHeight', await pref.get('carouselTitleCapsuleHeight', 36) as number);
  AppStorage.setOrCreate('carouselTitleLetterSpacing', await pref.get('carouselTitleLetterSpacing', 1) as number);
  AppStorage.setOrCreate('searchFloatBtnSide', await pref.get('searchFloatBtnSide', 'right') as string);
  AppStorage.setOrCreate('searchFloatBtnY', await pref.get('searchFloatBtnY', 120) as number);
  AppStorage.setOrCreate('watchHistoryFloatBtnSide', await pref.get('watchHistoryFloatBtnSide', 'right') as string);
  AppStorage.setOrCreate('watchHistoryFloatBtnY', await pref.get('watchHistoryFloatBtnY', 120) as number);
  AppStorage.setOrCreate('dynDetailFloatBtnSide', await pref.get('dynDetailFloatBtnSide', 'right') as string);
  AppStorage.setOrCreate('dynDetailFloatBtnY', await pref.get('dynDetailFloatBtnY', 120) as number);
  AppStorage.setOrCreate('videoShrinkBtnSide', await pref.get('videoShrinkBtnSide', 'right') as string);
  AppStorage.setOrCreate('videoShrinkBtnY', await pref.get('videoShrinkBtnY', 120) as number);
  AppStorage.setOrCreate('videoLightBtnSide', await pref.get('videoLightBtnSide', 'right') as string);
  AppStorage.setOrCreate('videoLightBtnY', await pref.get('videoLightBtnY', 120) as number);
  AppStorage.setOrCreate('cacheHintLeft', await pref.get('cacheHintLeft', 16) as number);
  AppStorage.setOrCreate('cacheHintBottom', await pref.get('cacheHintBottom', 96) as number);
  const migrated = await pref.get('referenceAppearanceVersion', 0) as number;
  if (migrated < 1) {
    await pref.put('isDarkMode', true);
    await pref.put('referenceAppearanceVersion', 1);
    await pref.flush();
  }
  const legacyDark = await pref.get('isDarkMode', true) as boolean;
  const storedTheme = await pref.get('themeMode', legacyDark ? 'dark' : 'light') as string;
  applyThemeMode(context, ['system', 'light', 'dark'].includes(storedTheme) ? storedTheme : 'system');
  AppStorage.setOrCreate('referenceLayout', true);
  AppStorage.setOrCreate('customThemeColor', '#D34E7E');
  AppStorage.setOrCreate('wallpaper', 'default');
  AppStorage.setOrCreate('cardTransparentStyle', false);
  AppStorage.setOrCreate('cardTransparentStyleVideo', false);
  AppStorage.setOrCreate('cardBorderWidth', 0);
  AppStorage.setOrCreate('cardBorderFollowTheme', false);
  AppStorage.setOrCreate('cardBorderFollowPlayCount', false);
  AppStorage.setOrCreate('cardCapsuleShow', false);
  AppStorage.setOrCreate('cardPlayCountColorMode', 'default');
  AppStorage.setOrCreate('cardMargin', 0);
  AppStorage.setOrCreate('cardBorderRadius', 12);
  AppStorage.setOrCreate('cardListMargin', 6);
  AppStorage.setOrCreate('cardListBorderRadius', 4);
  AppStorage.setOrCreate('showHomeCarouselPortrait', false);
  AppStorage.setOrCreate('showHomeCarouselLandscape', false);
  AppStorage.setOrCreate('showCarouselBgPortrait', false);
  AppStorage.setOrCreate('showCarouselBgLandscape', false);
  AppStorage.setOrCreate('showRefreshSeparator', false);
  AppStorage.setOrCreate('shrinkVideoOnScroll', true);
  AppStorage.setOrCreate('smartGripEnabled', false);
  AppStorage.setOrCreate('videoBgMode', 'solid');
  AppStorage.setOrCreate('videoBgColor', '#000000');
  AppStorage.setOrCreate('pageEnterAnim', 'fade');
  if (!AppStorage.has('homeBarsHidden')) AppStorage.setOrCreate('homeBarsHidden', false);
  if (!AppStorage.has('homeChannelIndex')) AppStorage.setOrCreate('homeChannelIndex', 2);
}

/** Keep the preference distinct from the effective colors used by existing pages. */
export function applyThemeMode(context: common.UIAbilityContext, mode: string): void {
  AppStorage.setOrCreate('themeMode', mode);
  context.getApplicationContext().setColorMode(mode === 'system' ? ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET :
    mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
  let dark = mode === 'dark';
  if (mode === 'system') {
    dark = resourceManager.getSystemResourceManager().getConfigurationSync().colorMode === resourceManager.ColorMode.DARK;
  }
  AppStorage.setOrCreate('isDarkMode', dark);
}

export function syncThemeConfiguration(colorMode: number | undefined): void {
  if (AppStorage.get<string>('themeMode') !== 'system') return;
  if (colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_DARK &&
    colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT) return;
  AppStorage.setOrCreate('isDarkMode', colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
}
