import { preferences } from '@kit.ArkData';
import type { common } from '@kit.AbilityKit';
import { errMsg, logWarn } from '../utils/Logger';

const BACKGROUND_PLAYBACK_KEY: string = 'bgp';

export function restoreBackgroundPlayback(ctx: common.Context): void {
  try {
    const pref = preferences.getPreferencesSync(ctx, { name: 'my_app_settings' });
    const saved = pref.getSync(BACKGROUND_PLAYBACK_KEY, '');
    if (typeof saved === 'boolean') {
      AppStorage.setOrCreate<boolean>(BACKGROUND_PLAYBACK_KEY, saved);
      return;
    }
    // Older versions also saved the switch through PersistentStorage.
    PersistentStorage.persistProp(BACKGROUND_PLAYBACK_KEY, false);
    const legacy = AppStorage.get<boolean>(BACKGROUND_PLAYBACK_KEY) ?? false;
    pref.putSync(BACKGROUND_PLAYBACK_KEY, legacy);
    pref.flushSync();
    PersistentStorage.deleteProp(BACKGROUND_PLAYBACK_KEY);
    AppStorage.setOrCreate<boolean>(BACKGROUND_PLAYBACK_KEY, legacy);
  } catch (error) {
    logWarn(`[bgp] 读取后台播放设置失败: ${errMsg(error)}`);
  }
}

export function setBackgroundPlayback(ctx: common.Context, enabled: boolean): void {
  AppStorage.setOrCreate<boolean>(BACKGROUND_PLAYBACK_KEY, enabled);
  try {
    const pref = preferences.getPreferencesSync(ctx, { name: 'my_app_settings' });
    pref.putSync(BACKGROUND_PLAYBACK_KEY, enabled);
    pref.flushSync();
  } catch (error) {
    logWarn(`[bgp] 保存后台播放设置失败: ${errMsg(error)}`);
  }
}
