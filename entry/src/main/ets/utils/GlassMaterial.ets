import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 第三类玻璃控件（顶栏、按钮、胶囊、菜单、设置项、输入框、弹层）的统一配方。
 *
 * 边界：
 * - 两套内容卡片（NativeCardGlass）有自己的开关/厚度/染色，不接入这里；
 * - 音量条 / 亮度条体系（controlcenter、PlayerLevelBar、ExperimentalLevelBar）完全不接入，保持原样；
 * - 反色一律写死开启，暂不提供设置项。改观感只改本文件。
 *
 * 每个调用点必须新建独立实例：材质实例与挂载表面绑定，跨表面复用会让整组弹窗不显示。
 */
export type GlassKind = 'sheet' | 'panel' | 'menu' | 'control' | 'staticControl' | 'capsule' |
  'header' | 'headerRegular' | 'hint' | 'touch' | 'accent';

export interface GlassOverrides {
  tint?: ResourceColor;
  light?: ResourceColor;
  interactive?: boolean;
}

export interface GlassRecipe {
  style: uiMaterial.ImmersiveStyle;
  tint?: ResourceColor;
  interactive?: boolean;
  shadow?: boolean;
  light?: uiMaterial.LightEffectOptions | null;
}

export class GlassMaterial {
  /** 统一反色：写死开启，暂不提供设置项。 */
  static readonly INVERTED: boolean = true;

  static supported(): boolean {
    try {
      return deviceInfo.apiAvailable('26.0.0') && uiMaterial.isImmersiveMaterialSupported();
    } catch (_) {
      return false;
    }
  }

  /** 通用入口：自定义档位/染色的控件也走这里，保证反色与参数口径一致。 */
  static createWithStyle(recipe: GlassRecipe): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: recipe.style,
      materialColor: recipe.tint ?? Color.Transparent,
      colorInvert: GlassMaterial.INVERTED,
      applyShadow: recipe.shadow ?? false,
      interactive: recipe.interactive ?? false,
      lightEffect: recipe.light === undefined ? null : recipe.light
    });
  }

  /** 按类别取统一配方；多数控件用这个。 */
  static create(kind: GlassKind, dark: boolean, overrides?: GlassOverrides): uiMaterial.ImmersiveMaterial {
    const recipe: GlassRecipe = {
      style: GlassMaterial.styleFor(kind),
      tint: overrides?.tint ?? GlassMaterial.tintFor(kind, dark),
      interactive: overrides?.interactive ?? GlassMaterial.interactiveFor(kind),
      shadow: GlassMaterial.shadowFor(kind),
      light: GlassMaterial.lightFor(kind, overrides?.light ?? Color.White)
    };
    return GlassMaterial.createWithStyle(recipe);
  }

  /** 不支持沉浸材质时的系统磨砂档位。 */
  static fallbackBlur(kind: GlassKind): BlurStyle {
    if (kind === 'control' || kind === 'staticControl' || kind === 'capsule' || kind === 'touch' || kind === 'accent') {
      return BlurStyle.COMPONENT_ULTRA_THIN;
    }
    if (kind === 'headerRegular') return BlurStyle.COMPONENT_REGULAR;
    return BlurStyle.COMPONENT_THICK;
  }

  /** 不支持沉浸材质时的底板色（控件沿用各自原有深浅配方）。 */
  static fallbackColor(kind: GlassKind, dark: boolean): ResourceColor {
    if (kind === 'panel') return dark ? '#E6202528' : '#E6F2F3F5';
    if (kind === 'header' || kind === 'headerRegular') return dark ? '#80202228' : '#80FFFFFF';
    if (kind === 'sheet' || kind === 'menu' || kind === 'hint') return dark ? '#171A1D' : '#FFFFFF';
    return dark ? '#80202528' : '#80FFFFFF';
  }

  /** HdsTabs 浮动条通道：系统自绘材质，没有 colorInvert 参数，深浅由系统主题决定。 */
  static hdsType(): hdsMaterial.MaterialType {
    return hdsMaterial.MaterialType.IMMERSIVE;
  }

  static hdsLevel(exquisite: boolean = false): hdsMaterial.MaterialLevel {
    return exquisite ? hdsMaterial.MaterialLevel.EXQUISITE : hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  private static styleFor(kind: GlassKind): uiMaterial.ImmersiveStyle {
    if (kind === 'sheet' || kind === 'panel' || kind === 'header') return uiMaterial.ImmersiveStyle.THICK;
    if (kind === 'menu' || kind === 'hint' || kind === 'headerRegular') return uiMaterial.ImmersiveStyle.REGULAR;
    return uiMaterial.ImmersiveStyle.ULTRA_THIN;
  }

  private static lightFor(kind: GlassKind, color: ResourceColor): uiMaterial.LightEffectOptions | null {
    if (kind === 'sheet' || kind === 'panel' || kind === 'header' || kind === 'headerRegular') return null;
    if (kind === 'hint') return { color: undefined };
    return { color: color };
  }

  private static tintFor(kind: GlassKind, dark: boolean): ResourceColor {
    if (kind === 'panel') return dark ? '#661C2022' : '#88F2F3F5';
    if (kind === 'menu') return dark ? '#66242628' : '#88F7F8FA';
    if (kind === 'header' || kind === 'headerRegular') return dark ? '#10000000' : '#10FFFFFF';
    if (kind === 'hint') return '#66000000';
    if (kind === 'control' || kind === 'staticControl') return dark ? '#301C2022' : '#30FFFFFF';
    return Color.Transparent;
  }

  private static interactiveFor(kind: GlassKind): boolean {
    return kind === 'menu' || kind === 'control' || kind === 'capsule' || kind === 'hint' || kind === 'accent';
  }

  private static shadowFor(kind: GlassKind): boolean {
    return kind === 'menu' || kind === 'capsule' || kind === 'hint';
  }
}
