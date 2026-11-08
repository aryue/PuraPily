import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** Match the settings page's native anchored dropdown across video and live playback. */
export function playbackMenuOptions(dark: boolean, onDisappear: () => void): MenuOptions {
  return {
    placement: Placement.BottomRight, enableArrow: false, borderRadius: 24, onDisappear: onDisappear,
    systemMaterial: deviceInfo.apiAvailable('26.0.0') ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: dark ? '#66242628' : '#88F7F8FA',
      interactive: true, applyShadow: true, lightEffect: { color: Color.White }
    }) : undefined
  };
}

/** Native interaction material for sliders and switches inside a fixed playback scope. */
export function playbackControlMaterial(dark: boolean): uiMaterial.ImmersiveMaterial | undefined {
  return deviceInfo.apiAvailable('26.0.0') ? new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN, materialColor: dark ? '#301C2022' : '#30FFFFFF',
    interactive: true, applyShadow: false, lightEffect: { color: Color.White }
  }) : undefined;
}
