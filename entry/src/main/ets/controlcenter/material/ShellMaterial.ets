export class ShellMaterial implements AttributeModifier<CommonAttribute> {
  private captureMode: boolean;
  constructor(captureMode: boolean = false) { this.captureMode = captureMode; }
  applyNormalAttribute(instance: CommonAttribute): void {
    // VOL-AL00 runtime rejects systemMaterial on this standalone component:
    // "Material inactive: out of scope. Use component in navigation title bar or Tabbar."
    // A visible surface must never depend on that capability query.
    // Blur arguments come from firmware; bright tint is calibrated against the device reference.
    instance.backgroundColor('#20FFFFFF')
      .backgroundEffect(this.captureMode ? undefined :
        { radius: 60, policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
          blurOptions: { grayscale: [38, 38] } }, { disableSystemAdaptation: true });
  }
}
