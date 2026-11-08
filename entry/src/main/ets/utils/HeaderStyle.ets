import { LengthMetrics } from '@kit.ArkUI';
import { ScrollEffectType, TitleBarStyleOptions } from '@kit.UIDesignKit';

// Finish the native gradient inside the title instead of extending over body content.
export const HEADER_GRADIENT_EXTRA_HEIGHT: number = 0;

/** HDS navigation pages share the same native gradient blur and title contrast. */
export function gradientTitleBarStyle(dark: boolean): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(20)
    },
    originalStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent, blurRadius: 24, maskExtraHeight: HEADER_GRADIENT_EXTRA_HEIGHT },
      contentStyle: { titleStyle: { mainTitleColor: dark ? '#F2F4F8' : '#18191C' } }
    },
    scrollEffectStyle: {
      backgroundStyle: { backgroundColor: Color.Transparent, blurRadius: 24, maskExtraHeight: HEADER_GRADIENT_EXTRA_HEIGHT },
      contentStyle: { titleStyle: { mainTitleColor: dark ? '#F2F4F8' : '#18191C' } }
    }
  };
}
