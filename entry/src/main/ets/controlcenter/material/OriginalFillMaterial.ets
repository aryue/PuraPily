import { applyOriginalFill, applyOriginalPointSource, applyOriginalProgressBlend, originalProgressBlendAvailable } from './OriginalMaterialRuntime';

export class OriginalShellMaterial implements AttributeModifier<CommonAttribute> {
  private chosen: boolean;
  private light: boolean;
  private static seen: number = 0;
  constructor(chosen: boolean, light: boolean) { this.chosen = chosen; this.light = light; }
  applyNormalAttribute(instance: CommonAttribute): void {
    try {
      applyOriginalFill(instance, this.chosen, this.light);
      const bit: number = this.chosen ? 2 : 1;
      if ((OriginalShellMaterial.seen & bit) === 0) {
        OriginalShellMaterial.seen |= bit;
        console.info(`CCLab original shell material applied chosen=${this.chosen}, selectedScenario=49, illuminated=3`);
      }
    } catch (error) {
      console.warn(`CCLab original shell material rejected: ${error}`);
      instance.backgroundColor('#30FFFFFF');
    }
  }
}

export class OriginalPointSource implements AttributeModifier<CommonAttribute> {
  private enabled: boolean;
  private x: number;
  private y: number;
  private intensity: number;
  private z: number;
  constructor(enabled: boolean, x: number, y: number, intensity: number, z: number = 110) {
    this.enabled = enabled; this.x = x; this.y = y; this.intensity = intensity;
    this.z = z;
  }
  applyNormalAttribute(instance: CommonAttribute): void {
    try { applyOriginalPointSource(instance, this.enabled, this.x, this.y, this.intensity, this.z); }
    catch (error) { if (this.enabled) { console.warn(`CCLab original point source rejected: ${error}`); } }
  }
}

export class OriginalProgressBlend implements AttributeModifier<CommonAttribute> {
  static available(): boolean { return originalProgressBlendAvailable(); }
  applyNormalAttribute(instance: CommonAttribute): void {
    try { applyOriginalProgressBlend(instance); }
    catch (error) { console.warn(`CCLab original progress blend rejected: ${error}`); }
  }
}
