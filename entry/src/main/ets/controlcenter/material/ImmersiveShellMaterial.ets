import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { ShellMaterial } from './ShellMaterial';
import { OriginalMaterialProbe } from './OriginalMaterialProbe';

// Used inside Navigation's custom title so the public immersive material is in
// its documented scope. The caller controls whether to use this experiment.
export class ImmersiveShellMaterial implements AttributeModifier<CommonAttribute> {
  private enabled: boolean;
  private style: number;
  private light: boolean;
  private captureMode: boolean;
  private fallback: boolean;

  constructor(enabled: boolean, style: number, light: boolean, captureMode: boolean, fallback: boolean = true) {
    this.enabled = enabled;
    this.style = style;
    this.light = light;
    this.captureMode = captureMode;
    this.fallback = fallback;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    OriginalMaterialProbe.inspect(instance);
    if (deviceInfo.sdkApiVersion < 26) {
      if (this.fallback) { new ShellMaterial(this.captureMode).applyNormalAttribute(instance); }
      return;
    }
    if (!this.enabled) {
      instance.systemMaterial(uiMaterial.Material.empty);
      if (this.fallback) { new ShellMaterial(this.captureMode).applyNormalAttribute(instance); }
      else { instance.backgroundColor(Color.Transparent).backgroundEffect(undefined); }
      return;
    }
    const styles: uiMaterial.ImmersiveStyle[] = [uiMaterial.ImmersiveStyle.ULTRA_THIN,
      uiMaterial.ImmersiveStyle.THIN, uiMaterial.ImmersiveStyle.REGULAR,
      uiMaterial.ImmersiveStyle.THICK, uiMaterial.ImmersiveStyle.ULTRA_THICK];
    const style: uiMaterial.ImmersiveStyle = styles[Math.max(0, Math.min(4, this.style))];
    instance.backgroundColor(Color.Transparent).backgroundEffect(undefined)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: style, materialColor: Color.Transparent, applyShadow: false,
        colorInvert: false, interactive: false, lightEffect: this.light ? {} : null
      }));
  }
}
