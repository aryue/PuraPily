import { GlassKind, GlassMaterial, GlassOverrides } from '../utils/GlassMaterial';

/**
 * 统一的玻璃材质面：Navigation 标题栏作用域里那一层材质与它的降级都收敛在这里。
 * 调用方只保留自己的外壳尺寸、id 与业务内容；配方一律由 GlassMaterial 提供。
 * 两套内容卡片与音量/亮度条体系不使用本组件。
 */
@Component
export struct NativeGlassSurface {
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 0;
  @Prop radius: number = 0;
  @Prop kind: string = 'control';
  @Prop dark: boolean = true;
  @Prop supported: boolean = false;
  @Prop useTint: boolean = false;
  @Prop tintColor: ResourceColor = Color.Transparent;
  @Prop useLight: boolean = false;
  @Prop lightColor: ResourceColor = Color.White;
  @Prop interactiveOverride: number = -1;
  @Prop surfaceId: string = '';
  @Prop centerContent: boolean = true;
  @Prop attachPress: boolean = false;
  @Prop insetX: number = 0;
  @Prop insetY: number = 0;
  @BuilderParam content: () => void;
  onActivate: () => void = () => {};

  private glassKind(): GlassKind {
    return this.kind as GlassKind;
  }

  private overrides(): GlassOverrides {
    const options: GlassOverrides = {};
    if (this.useTint) options.tint = this.tintColor;
    if (this.useLight) options.light = this.lightColor;
    if (this.interactiveOverride >= 0) options.interactive = this.interactiveOverride === 1;
    return options;
  }

  private press(): void {
    if (this.attachPress) this.onActivate();
  }

  build() {
    if (this.supported) {
      Stack({ alignContent: this.centerContent ? Alignment.Center : Alignment.TopStart }) { this.content() }
        .width(this.surfaceWidth).height(this.surfaceHeight).borderRadius(this.radius)
        .position({ x: this.insetX, y: this.insetY })
        .systemMaterial(GlassMaterial.create(this.glassKind(), this.dark, this.overrides()))
        .id(this.surfaceId).onTouch((_event: TouchEvent) => {})
        .onClick(() => this.press())
    } else {
      Stack({ alignContent: this.centerContent ? Alignment.Center : Alignment.TopStart }) { this.content() }
        .width(this.surfaceWidth).height(this.surfaceHeight).borderRadius(this.radius)
        .position({ x: this.insetX, y: this.insetY })
        .backgroundBlurStyle(GlassMaterial.fallbackBlur(this.glassKind()))
        .backgroundColor(GlassMaterial.fallbackColor(this.glassKind(), this.dark))
        .id(this.surfaceId).onTouch((_event: TouchEvent) => {})
        .onClick(() => this.press())
    }
  }
}
