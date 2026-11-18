import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import type { DanmakuConfig, DanmakuConfigInit } from '../model/DanmakuItem';
import { errMsg, logInfo, logWarn } from '../utils/Logger';

const DM_SETTING_KEY: string = 'danmakuDisplaySettings';

/** Restore display settings before the canvas starts and coalesce slider writes across pages. */
export class DanmakuDisplaySettings {
  private static timer: number = 0;
  private static pending: string = '';
  private applied: string = '';

  async source(ctx: common.Context): Promise<string> {
    const pref = await preferences.getPreferences(ctx, 'my_app_settings');
    return await pref.get('danmakuApiSource', 'grpc') as string;
  }

  async enabled(ctx: common.Context): Promise<boolean> {
    const pref = await preferences.getPreferences(ctx, 'VPS');
    return await pref.get('danmakuEnabled', true) as boolean;
  }

  async saveEnabled(ctx: common.Context, value: () => boolean): Promise<void> {
    const pref = await preferences.getPreferences(ctx, 'VPS');
    await pref.put('danmakuEnabled', value());
    await pref.flush();
  }

  changed(ctx: common.Context, config: DanmakuConfig): void {
    this.applied = serializeDisplaySettings(config);
    DanmakuDisplaySettings.pending = this.applied;
    if (DanmakuDisplaySettings.timer) clearTimeout(DanmakuDisplaySettings.timer);
    DanmakuDisplaySettings.timer = setTimeout(() => this.commit(ctx), 200);
  }

  commit(ctx: common.Context): void {
    if (DanmakuDisplaySettings.timer) {
      clearTimeout(DanmakuDisplaySettings.timer);
      DanmakuDisplaySettings.timer = 0;
    }
    const raw = DanmakuDisplaySettings.pending;
    if (!raw) return;
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: 'VPS' });
      pref.putSync(DM_SETTING_KEY, raw);
      pref.flushSync();
      DanmakuDisplaySettings.pending = '';
    } catch (error) {
      logWarn(`[VideoPlayer] 保存弹幕设置失败: ${errMsg(error)}`);
    }
    this.publish();
  }

  load(ctx: common.Context, config: DanmakuConfig): void {
    try {
      const raw = DanmakuDisplaySettings.pending ||
        preferences.getPreferencesSync(ctx, { name: 'VPS' }).getSync(DM_SETTING_KEY, '') as string;
      if (!raw || raw === this.applied) return;
      applyDisplaySettings(JSON.parse(raw) as DanmakuConfigInit, config);
      this.applied = raw;
      this.publish();
      logInfo('[VideoPlayer] 已恢复弹幕显示设置');
    } catch (error) {
      logWarn(`[VideoPlayer] 读取弹幕设置失败: ${errMsg(error)}`);
    }
  }

  private publish(): void {
    const version = AppStorage.get<number>('danmakuSettingVersion') ?? 0;
    AppStorage.setOrCreate<number>('danmakuSettingVersion', version + 1);
  }
}

function serializeDisplaySettings(c: DanmakuConfig): string {
  // 手动拼串：规避 ArkTS 里 Record<string, Object> 对 boolean/number 装箱的类型限制
  return '{"blockWeight":' + c.blockWeight +
    ',"showScroll":' + c.showScroll +
    ',"showTop":' + c.showTop +
    ',"showBottom":' + c.showBottom +
    ',"showAdvanced":' + c.showAdvanced +
    ',"blockColorful":' + c.blockColorful +
    ',"blockCounted":' + c.blockCounted +
    ',"hideDuplicates":' + c.hideDuplicates +
    ',"keywordFilterEnabled":' + c.keywordFilterEnabled +
    ',"blockKeywords":' + JSON.stringify(c.blockKeywords) +
    ',"displayArea":' + c.displayArea +
    ',"opacity":' + c.opacity +
    ',"fontSize":' + c.fontSize +
    ',"fullScreenFontScale":' + c.fullScreenFontScale +
    ',"lineHeight":' + c.lineHeight +
    ',"fontWeight":' + c.fontWeight +
    ',"borderWidth":' + c.borderWidth +
    ',"scrollDuration":' + c.scrollDuration +
    ',"staticDuration":' + c.staticDuration +
    ',"varyFontSize":' + c.varyFontSize +
    ',"massiveMode":' + c.massiveMode +
    ',"static2Scroll":' + c.static2Scroll +
    ',"scrollFixedVelocity":' + c.scrollFixedVelocity +
    '}'
}

function applyDisplaySettings(o: DanmakuConfigInit, c: DanmakuConfig): void {
  if (o.blockWeight !== undefined) c.blockWeight = Math.round(Math.min(11, Math.max(0, o.blockWeight)))
  if (o.showScroll !== undefined) c.showScroll = !!o.showScroll
  if (o.showTop !== undefined) c.showTop = !!o.showTop
  if (o.showBottom !== undefined) c.showBottom = !!o.showBottom
  if (o.showAdvanced !== undefined) c.showAdvanced = !!o.showAdvanced
  if (o.blockColorful !== undefined) c.blockColorful = !!o.blockColorful
  if (o.blockCounted !== undefined) c.blockCounted = !!o.blockCounted
  if (o.hideDuplicates !== undefined) c.hideDuplicates = !!o.hideDuplicates
  if (o.keywordFilterEnabled !== undefined) c.keywordFilterEnabled = !!o.keywordFilterEnabled
  if (o.blockKeywords !== undefined) c.blockKeywords = o.blockKeywords.filter((word: string) => word.length > 0)
  if (o.displayArea !== undefined) c.displayArea = Math.min(1, Math.max(0.1, o.displayArea))
  if (o.opacity !== undefined) c.opacity = Math.min(1, Math.max(0, o.opacity))
  // ⚠️ 量程必须覆盖默认字号 28：早期版本上限 32 曾把 37 静默钳到 32（Slider 的隐含约束，这里同源）
  if (o.fontSize !== undefined) c.fontSize = Math.min(48, Math.max(12, o.fontSize))
  if (o.fullScreenFontScale !== undefined) c.fullScreenFontScale = Math.min(2, Math.max(1, o.fullScreenFontScale))
  if (o.lineHeight !== undefined) c.lineHeight = Math.min(2.5, Math.max(1, o.lineHeight))
  if (o.fontWeight !== undefined) c.fontWeight = Math.min(900, Math.max(100, Math.round(o.fontWeight / 100) * 100))
  if (o.borderWidth !== undefined) c.borderWidth = Math.min(5, Math.max(0, o.borderWidth))
  if (o.scrollDuration !== undefined) c.scrollDuration = Math.min(20000, Math.max(3000, Math.round(o.scrollDuration)))
  if (o.staticDuration !== undefined) c.staticDuration = Math.min(10000, Math.max(1000, Math.round(o.staticDuration)))
  if (o.varyFontSize !== undefined) c.varyFontSize = !!o.varyFontSize
  if (o.massiveMode !== undefined) c.massiveMode = !!o.massiveMode
  if (o.static2Scroll !== undefined) c.static2Scroll = !!o.static2Scroll
  if (o.scrollFixedVelocity !== undefined) c.scrollFixedVelocity = !!o.scrollFixedVelocity
}
