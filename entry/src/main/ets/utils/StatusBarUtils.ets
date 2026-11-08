// StatusBarUtils.ets - 状态栏颜色管理工具 + 隐藏/显示控制
import { window } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from './Logger';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

export class StatusBarUtils {
  private static systemBarQueue: Promise<void> = Promise.resolve();

  /** Retain the measured inset when the indicator is hidden or a fullscreen page reports zero. */
  static updateNavigationInset(measured: number = 0): void {
    if (measured > 0 && !(AppStorage.get<boolean>('hideNavigationIndicator') ?? false)) {
      AppStorage.setOrCreate('realNavIndicatorHeight', measured);
    }
    const actual = AppStorage.get<number>('realNavIndicatorHeight') ?? measured;
    const hidden = AppStorage.get<boolean>('hideNavigationIndicator') ?? false;
    AppStorage.setOrCreate('navIndicatorHeight', hidden ? Math.max(0, actual - 12) : actual);
  }

  /** 隐藏/旋转期间返回的 0 是当前可见区域，不是设备的状态栏高度。 */
  static statusBarInset(win: window.Window): number {
    const measured = win.getUIContext().px2vp(win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height);
    if (measured > 0) {
      AppStorage.setOrCreate('realStatusBarHeight', measured);
      return measured;
    }
    return Math.max(1, AppStorage.get<number>('realStatusBarHeight') || AppStorage.get<number>('statusBarHeight') || 40);
  }

  /** 所有播放器显隐请求串行落地，旧页面的迟到请求不能覆盖新页面。 */
  static setSystemBars(win: window.Window, status: boolean, navigation: boolean = true): Promise<void> {
    const apply = async (): Promise<void> => {
      if (status) AppStorage.setOrCreate('statusBarHeight', StatusBarUtils.statusBarInset(win));
      const showIndicator = navigation && !(AppStorage.get<boolean>('hideNavigationIndicator') ?? false);
      // 按栏分别设置，避免整体恢复系统栏时先把手势提示条打开。
      if (!showIndicator) await win.setSpecificSystemBarEnabled('navigationIndicator', false, false);
      await win.setSpecificSystemBarEnabled('status', status, false);
      await win.setSpecificSystemBarEnabled('navigation', navigation, false);
      if (showIndicator) await win.setSpecificSystemBarEnabled('navigationIndicator', true, false);
      if (status) AppStorage.setOrCreate('statusBarHeight', StatusBarUtils.statusBarInset(win));
    };
    StatusBarUtils.systemBarQueue = StatusBarUtils.systemBarQueue.then(apply).catch((error: Error) => {
      logWarn(`设置系统栏失败: ${error.message}`);
    });
    return StatusBarUtils.systemBarQueue;
  }
  /**
   * 更新状态栏文字颜色（背景透明）
   * @param context UIAbilityContext
   * @param isDarkMode true=深色模式(白字), false=浅色模式(黑字)
   */
  static async updateStatusBarColor(context: common.UIAbilityContext, isDarkMode: boolean) {
    try {
      const windowClass: window.Window = await window.getLastWindow(context);
      // 确保沉浸式布局开启（EntryAbility 已设置，此处作为二次保障）
      await windowClass.setWindowLayoutFullScreen(true);
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',               // 状态栏完全透明
        statusBarContentColor: isDarkMode ? '#FFFFFF' : '#000000',
        navigationBarColor: '#00000000',            // 导航栏完全透明，消除底部白边/黑边
      };
      await windowClass.setWindowSystemBarProperties(sysBarProps);
      logInfo(`状态栏已更新: ${isDarkMode ? '深色模式(白字)' : '浅色模式(黑字)'}`);
    } catch (error) {
      let err = error as BusinessError;
      logError(`更新状态栏失败: ${err.code} - ${err.message}`);
    }
  }

  /**
   * 隐藏或显示状态栏
   * 始终保持全屏布局模式，让窗口内容延伸到系统栏后方，消除白边
   * @param context UIAbilityContext
   * @param hide true=隐藏状态栏，false=显示状态栏
   */
  static async setStatusBarHidden(context: common.UIAbilityContext, hide: boolean) {
    try {
      const windowClass: window.Window = await window.getLastWindow(context);
      
      // 始终保持全屏布局，让内容延伸到状态栏/导航栏后方，避免出现白边
      await windowClass.setWindowLayoutFullScreen(true);
      
      // ★ 无论显隐状态，强制设置状态栏/导航栏背景透明
      // 防止用户下滑呼出通知面板时状态栏区域出现白色背景
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
      };
      await windowClass.setWindowSystemBarProperties(sysBarProps);
      
      // 只切换状态栏内容的显隐
      await StatusBarUtils.setSystemBars(windowClass, !hide, true);
      
      logInfo(`状态栏已${hide ? '隐藏' : '显示'}（全屏布局保持开启）`);
    } catch (error) {
      let err = error as BusinessError;
      logError(`设置状态栏隐藏/显示失败: ${err.code} - ${err.message}`);
    }
  }
}
