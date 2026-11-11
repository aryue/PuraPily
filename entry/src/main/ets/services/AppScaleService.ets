/**
 * AppScaleService.ets
 * 应用比例调节：界面显示密度 + 全局字体大小。
 *
 * 实现依据：
 * - ApplicationContext.setFontSizeScale(scale)（API 13）：设置应用级字体缩放。
 *   ⚠️ 一旦调用，应用就不再跟随系统字体大小（`configuration.json` 的 fontSizeScale=followSystem
 *   是引擎默认，只在从未调用过本接口时生效），且该缩放**不跨进程持久**，每次冷启动都要重新下发。
 * - WindowStage.setCustomDensity(density, applyToSubWindow)（API 15/20）：主窗口自定义显示密度，
 *   density 与 display.densityPixels 同单位（px/vp），-1.0 表示恢复系统显示大小缩放。
 *
 * 「跟随系统」的两条路径（撤回不了 setFontSizeScale，只能这样等价实现）：
 * - 冷启动：命中 follow 就不调用 setFontSizeScale，由引擎默认真正跟随系统；
 * - 运行中从自定义切回：下发「冷启动时抓到的系统倍率」把字号立刻拉回系统值，并在 API 24+
 *   用 ApplicationContext.onSystemConfigurationUpdated 继续跟踪系统字号变化后重新下发。
 *   若设备低于 API 24，运行中切换只能对齐「切换这一刻」的系统值，重启后恢复真正跟随。
 */
import { common, systemConfiguration } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import { logInfo, logError } from '../utils/Logger';

/** 应用比例模式：跟随系统 */
export const SCALE_MODE_SYSTEM: string = 'system';
/** 应用比例模式：自定义 */
export const SCALE_MODE_CUSTOM: string = 'custom';

/** 界面缩放滑杆范围（倍率，1 = 与当前系统显示大小一致） */
export const UI_SCALE_MIN: number = 0.75;
export const UI_SCALE_MAX: number = 1.5;
/** 文字大小合法范围（倍率，1 = 标准字号） */
export const FONT_SCALE_MIN: number = 0.8;
export const FONT_SCALE_MAX: number = 2.5;
/** 字号滑条步长（倍率）：0.05 一档，0.8~2.5 共 35 档，比预设更细但不会细到点不准。 */
export const FONT_SCALE_STEP: number = 0.05;
/** 标准字号。 */
export const FONT_SCALE_DEFAULT: number = 1;

/** 自定义密度合法范围（与 setCustomDensity 参数一致，-1.0 为恢复系统） */
const DENSITY_MIN: number = 0.5;
const DENSITY_MAX: number = 4.0;

export interface AppScaleConfig {
  mode: string;
  uiScale: number;
  fontScale: number;
}

/**
 * 字体大小设置。followSystem=true 时 scale 是「上次自定义的倍率」（仅作记录）；
 * 切回自定义不用它，而是用当前生效的系统倍率，见 entryCustomScale()。
 */
export interface FontSizeSetting {
  followSystem: boolean;
  scale: number;
}

export class AppScaleService {
  static readonly KEY_MODE: string = 'appScaleMode';
  static readonly KEY_UI_SCALE: string = 'appUiScale';
  static readonly KEY_FONT_SCALE: string = 'appFontScale';
  static readonly KEY_FONT_MODE: string = 'fontSizeMode';
  private static readonly PREFS_NAME: string = 'my_app_settings';

  /**
   * 冷启动抓到的系统字体倍率。setFontSizeScale 之后 context.config.fontSizeScale
   * 会被应用自己的倍率覆盖，所以系统值只能在这里留一份。
   */
  private static systemFontScale: number = 1;
  /** 运行中「跟随系统」是否靠我们持续下发维持（自定义模式与冷启动原生跟随均为 false）。 */
  private static followByEmulation: boolean = false;
  /** 系统配置监听需要持有引用，避免被回收。 */
  private static fontWatcher: systemConfiguration.UpdatedCallback | null = null;
  /** 本次进程是否已下发过应用级字号：下发之后 context.config.fontSizeScale 就是应用自己的值。 */
  private static fontOverridden: boolean = false;

  /** 当前系统字体倍率（运行中切回「跟随系统」时用它把字号拉回系统值）。 */
  static currentSystemScale(): number {
    return AppScaleService.systemFontScale;
  }

  /** 抓取系统字体倍率：必须赶在本次进程第一次 setFontSizeScale 之前调用。 */
  static captureSystemScale(context: common.UIAbilityContext): void {
    try {
      const scale = context.config.fontSizeScale;
      if (typeof scale === 'number' && scale > 0) {
        AppScaleService.systemFontScale = scale;
      }
      logInfo(`AppScaleService 系统字体倍率=${AppScaleService.systemFontScale}`);
    } catch (e) {
      logError(`AppScaleService 读取系统字体倍率失败: ${JSON.stringify(e)}`);
    }
  }

  /**
   * 运行中刷新系统倍率：仅在**从未下发过应用级字号**（引擎原生跟随）时有效。
   * 用户在系统设置里改完字号再回到应用设置页，靠它把「切自定义」的初值对齐到最新系统倍率；
   * 已经下发过应用字号时 context.config 读到的是应用自己的倍率，不能当系统值用。
   */
  static refreshSystemScale(context: common.UIAbilityContext): void {
    if (AppScaleService.fontOverridden) return;
    AppScaleService.captureSystemScale(context);
  }

  /**
   * 跟踪系统字体大小变化（API 24+）：跟随系统时重新下发，自定义模式只刷新缓存值。
   * 低版本没有该接口，运行中切换的字号会停在切换那一刻的系统值，重启后自然恢复跟随。
   */
  static watchSystemFontScale(context: common.UIAbilityContext): void {
    // onSystemConfigurationUpdated 自 API 24 才有；低版本直接跳过（运行中切换仍对齐当刻系统值）。
    if (deviceInfo.sdkApiVersion < 24) {
      logInfo(`AppScaleService 系统配置监听需 API 24，当前 API ${deviceInfo.sdkApiVersion} 跳过`);
      return;
    }
    try {
      const callback: systemConfiguration.UpdatedCallback = {
        onFontSizeScaleUpdated: (fontSizeScale: number) => {
          if (!(fontSizeScale > 0)) return;
          AppScaleService.systemFontScale = fontSizeScale;
          if (AppScaleService.followByEmulation) {
            AppScaleService.applyFontScale(context, fontSizeScale);
          }
        }
      };
      const appCtx = context.getApplicationContext() as common.ApplicationContext;
      appCtx.onSystemConfigurationUpdated(callback);
      AppScaleService.fontWatcher = callback;
      logInfo('AppScaleService 已监听系统字体大小变化');
    } catch (e) {
      logError(`AppScaleService 注册系统字体监听失败: ${JSON.stringify(e)}`);
    }
  }

  /** 读取字体大小设置（缺失时按跟随系统、标准字号处理）。 */
  static async loadFontSetting(context: common.UIAbilityContext): Promise<FontSizeSetting> {
    try {
      const pref = await preferences.getPreferences(context, AppScaleService.PREFS_NAME);
      const mode = await pref.get(AppScaleService.KEY_FONT_MODE, SCALE_MODE_SYSTEM) as string;
      const scale = await pref.get(AppScaleService.KEY_FONT_SCALE, 1) as number;
      return {
        followSystem: mode !== SCALE_MODE_CUSTOM,
        scale: AppScaleService.normalizeUserFontScale(scale)
      };
    } catch (e) {
      logError(`AppScaleService 读取字体大小失败: ${JSON.stringify(e)}`);
      return { followSystem: true, scale: 1 };
    }
  }

  /** 落盘字体大小设置（跟随系统时仍保留上次的自定义倍率）。 */
  static async saveFontSetting(context: common.UIAbilityContext, followSystem: boolean,
    scale: number): Promise<boolean> {
    try {
      const pref = await preferences.getPreferences(context, AppScaleService.PREFS_NAME);
      await pref.put(AppScaleService.KEY_FONT_MODE, followSystem ? SCALE_MODE_SYSTEM : SCALE_MODE_CUSTOM);
      await pref.put(AppScaleService.KEY_FONT_SCALE, AppScaleService.normalizeUserFontScale(scale));
      await pref.flush();
      return true;
    } catch (e) {
      logError(`AppScaleService 保存字体大小失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /** 倍率 → 设置页展示文案（140%）。 */
  static formatFontScale(scale: number): string {
    return `${Math.round(scale * 100)}%`;
  }

  /**
   * 进入自定义模式时的起始倍率。
   * 跟随系统时实际生效的是**系统倍率**，不是上次保存的自定义值——不同步过来的话，
   * 滑条会停在一个和画面字号对不上的位置（且此时不重新下发，画面不会跟着变）。
   */
  static entryCustomScale(fromSystem: boolean, current: number): number {
    return AppScaleService.normalizeUserFontScale(fromSystem ? AppScaleService.systemFontScale : current);
  }

  /**
   * 下发字体倍率：followSystem 时下发系统倍率并开始自跟踪，否则按自定义倍率下发。
   * 只应在「用户刚改设置」与「系统字号变化」两处调用；冷启动的 follow 走引擎默认，不调这里。
   */
  static applyFontSetting(context: common.UIAbilityContext, followSystem: boolean, scale: number): boolean {
    AppScaleService.followByEmulation = followSystem;
    const target = followSystem ? AppScaleService.systemFontScale : scale;
    return AppScaleService.applyFontScale(context, target);
  }

  /**
   * 直接下发应用级字体缩放（调用后应用不再跟随系统）。
   * ⚠️ 这里不夹到预设区间：跟随系统时下发的就是系统倍率（可达 3.2），
   * 夹住会让「切回跟随系统」比冷启动原生跟随更小。用户可设范围由 normalizeUserFontScale 负责。
   */
  static applyFontScale(context: common.UIAbilityContext, scale: number): boolean {
    if (!(scale > 0)) return false;
    const target = Math.round(scale * 100) / 100;
    try {
      const appCtx = context.getApplicationContext() as common.ApplicationContext;
      appCtx.setFontSizeScale(target);
      AppScaleService.fontOverridden = true;
      logInfo(`AppScaleService 已下发字体倍率=${target}`);
      return true;
    } catch (e) {
      logError(`AppScaleService 设置字体缩放失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /** 应用自定义比例：先设字体缩放，再设主窗口密度。任一失败返回 false。 */
  static applyCustom(context: common.UIAbilityContext, windowStage: window.WindowStage | null,
    uiScale: number, fontScale: number): boolean {
    let ok = AppScaleService.applyFontScale(context, fontScale);
    if (!AppScaleService.applyDensity(windowStage, uiScale)) ok = false;
    return ok;
  }

  /** 主窗口密度（显示大小）：uiScale 为相对当前系统密度的倍率。 */
  static applyDensity(windowStage: window.WindowStage | null, uiScale: number): boolean {
    try {
      if (!windowStage) {
        logInfo('AppScaleService 未找到 windowStage，跳过界面缩放设置');
        return true;
      }
      // density 与 display.densityPixels 同单位：按当前系统显示密度 × 用户倍率算出绝对密度
      const sysDensity = display.getDefaultDisplaySync().densityPixels;
      const density = Math.round(AppScaleService.clamp(sysDensity * uiScale, DENSITY_MIN, DENSITY_MAX) * 100) / 100;
      // 第二个参数 applyToSubWindow=true：已创建的子窗同步新密度，避免弹窗/底部页不一致
      windowStage.setCustomDensity(density, true);
      return true;
    } catch (e) {
      logError(`AppScaleService 设置界面缩放失败: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /**
   * 冷启动下发字号：跟随系统时完全不碰 setFontSizeScale（保住引擎默认的跟随），
   * 自定义时在首帧之前下发，避免「先按标准字号排一遍再跳档」。
   */
  static async applyFontAtStartup(context: common.UIAbilityContext): Promise<void> {
    // 先留底系统倍率，再决定要不要下发应用级缩放（下发后就再也读不回系统值了）
    AppScaleService.captureSystemScale(context);
    const setting = await AppScaleService.loadFontSetting(context);
    if (setting.followSystem) {
      AppScaleService.followByEmulation = false;
      logInfo('AppScaleService 启动：字体大小跟随系统');
      return;
    }
    AppScaleService.followByEmulation = false;
    AppScaleService.applyFontScale(context, setting.scale);
  }

  /** 冷启动恢复自定义显示密度（跟随系统时不动，交给系统）。 */
  static async applyDensityAtStartup(context: common.UIAbilityContext, windowStage: window.WindowStage | null): Promise<void> {
    const cfg = await AppScaleService.loadFromPrefs(context);
    if (cfg.mode === SCALE_MODE_CUSTOM) {
      AppScaleService.applyDensity(windowStage, cfg.uiScale);
      logInfo(`AppScaleService 启动已应用自定义显示密度: ${cfg.uiScale}`);
    } else {
      logInfo('AppScaleService 启动：跟随系统（无自定义显示密度）');
    }
  }

  /** 启动时调用：字体大小与（可选的）自定义显示密度各自独立恢复。 */
  static async applyFromPrefsAtStartup(context: common.UIAbilityContext, windowStage: window.WindowStage): Promise<void> {
    try {
      await AppScaleService.applyFontAtStartup(context);
      await AppScaleService.applyDensityAtStartup(context, windowStage);
    } catch (e) {
      logError(`AppScaleService 启动应用失败: ${JSON.stringify(e)}`);
    }
  }

  /** 从偏好读取显示密度配置（缺失时默认跟随系统、比例 100%） */
  static async loadFromPrefs(context: common.UIAbilityContext): Promise<AppScaleConfig> {
    const pref = await preferences.getPreferences(context, AppScaleService.PREFS_NAME);
    const mode = await pref.get(AppScaleService.KEY_MODE, SCALE_MODE_SYSTEM) as string;
    const uiScale = await pref.get(AppScaleService.KEY_UI_SCALE, 1) as number;
    const fontScale = await pref.get(AppScaleService.KEY_FONT_SCALE, 1) as number;
    return {
      mode: mode === SCALE_MODE_CUSTOM ? SCALE_MODE_CUSTOM : SCALE_MODE_SYSTEM,
      uiScale: AppScaleService.clamp(uiScale, UI_SCALE_MIN, UI_SCALE_MAX),
      fontScale: AppScaleService.normalizeUserFontScale(fontScale)
    };
  }

  /** 用户可设倍率：夹到 0.8~2.5 并吸附到 0.05 步长（滑条同源，避免浮点尾数让滑条偏移一档）。 */
  static normalizeUserFontScale(scale: number): number {
    const clamped = AppScaleService.clamp(scale, FONT_SCALE_MIN, FONT_SCALE_MAX);
    const snapped = Math.round(clamped / FONT_SCALE_STEP) * FONT_SCALE_STEP;
    return Math.round(snapped * 100) / 100;
  }

  private static clamp(v: number, min: number, max: number): number {
    return Math.min(max, Math.max(min, v));
  }
}
