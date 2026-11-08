/** Tint both raster and vector menu glyphs consistently, preserving their alpha. */
@Component
export struct PlaybackMenuIcon {
  @Prop icon: Resource = $r('app.media.ref_ps_settings');
  @Prop iconSize: number = 20;
  @StorageLink('isDarkMode') private dark: boolean = true;

  private iconFilter(): ColorFilter {
    // ArkUI multiplies the bias column by 255. Byte-valued biases exceed SDR
    // white and can bloom in HDR; keep the tint normalized and alpha unchanged.
    return new ColorFilter([
      0, 0, 0, 0, (this.dark ? 238 : 24) / 255,
      0, 0, 0, 0, (this.dark ? 239 : 25) / 255,
      0, 0, 0, 0, (this.dark ? 241 : 28) / 255,
      0, 0, 0, 1, 0
    ]);
  }

  build() {
    Image(this.icon).width(this.iconSize).height(this.iconSize).colorFilter(this.iconFilter())
      .hitTestBehavior(HitTestMode.None)
  }
}
