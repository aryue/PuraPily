import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { GlassMaterial } from './GlassMaterial';

/** Match the settings page's native anchored dropdown across video and live playback. */
export function playbackMenuOptions(dark: boolean, onDisappear: () => void): MenuOptions {
  return {
    placement: Placement.BottomRight, enableArrow: false, borderRadius: 24, onDisappear: onDisappear,
    systemMaterial: deviceInfo.apiAvailable('26.0.0') ? GlassMaterial.create('menu', dark) : undefined
  };
}

/** Native interaction material for sliders and switches inside a fixed playback scope. */
export function playbackControlMaterial(dark: boolean): uiMaterial.ImmersiveMaterial | undefined {
  return deviceInfo.apiAvailable('26.0.0') ? GlassMaterial.create('control', dark) : undefined;
}
