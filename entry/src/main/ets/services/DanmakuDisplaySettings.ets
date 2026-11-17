import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import type { DanmakuConfig, DanmakuConfigInit } from '../model/DanmakuItem';
import { errMsg, logInfo, logWarn } from '../utils/Logger';

const DM_SETTING_KEY: string = 'danmakuDisplaySettings';

/** Coalesce slider changes and keep an in-flight preference read from replacing them. */
export class DanmakuDisplaySettings {
  private timer: number = 0;
  private version: number = 0;
  private touched: boolean = false;

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
    this.touched = true;
    if (this.timer) clearTimeout(this.timer);
    // Sliders can emit many times per second. Reflow and persist once after they settle.
    this.timer = setTimeout(() => {
      this.timer = 0;
      this.publish();
      this.save(ctx, config);
    }, 200);
  }

  async save(ctx: common.Context, config: DanmakuConfig): Promise<void> {
    try {
      await writeDanmakuDisplaySettings(ctx, config);
    } catch (error) {
      logWarn(`[VideoPlayer] 保存弹幕设置失败: ${errMsg(error)}`);
    }
  }

  async load(ctx: common.Context, config: DanmakuConfig): Promise<void> {
    try {
      if (!await readDanmakuDisplaySettings(ctx, config, () => !this.touched)) return;
      // The renderer may already have measured its canvas with defaults.
      this.publish();
      logInfo('[VideoPlayer] 已恢复弹幕显示设置');
    } catch (error) {
      logWarn(`[VideoPlayer] 读取弹幕设置失败: ${errMsg(error)}`);
    }
  }

  private publish(): void {
    AppStorage.setOrCreate<number>('danmakuSettingVersion', ++this.version);
  }
}

export async function writeDanmakuDisplaySettings(ctx: common.Context, c: DanmakuConfig): Promise<void> {
  // 手动拼串：规避 ArkTS 里 Record<string, Object> 对 boolean/number 装箱的类型限制
  const json = '{"blockWeight":' + c.blockWeight +
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
  const pref = await preferences.getPreferences(ctx, 'VPS');
  await pref.put(DM_SETTING_KEY, json);
  await pref.flush();
}

export async function readDanmakuDisplaySettings(ctx: common.Context, c: DanmakuConfig,
  canApply: () => boolean): Promise<boolean> {
  const pref = await preferences.getPreferences(ctx, 'VPS');
  const raw = await pref.get(DM_SETTING_KEY, '') as string;
  if (!raw || raw.length < 2) return false;
  const o = JSON.parse(raw) as DanmakuConfigInit;
  if (!canApply()) return false;
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
  if (o.fontSize !== undefined) c.fontSize = Math.round(Math.min(48, Math.max(12, o.fontSize)))
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
  return true;
}
