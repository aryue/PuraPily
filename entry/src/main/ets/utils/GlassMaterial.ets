import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 第三类玻璃控件（顶栏、按钮、胶囊、菜单、设置项、输入框、弹层）的统一配方。
 *
 * 边界：
 * - 两套内容卡片（NativeCardGlass）有自己的开关/厚度/染色，不接入这里；
 * - 音量条 / 亮度条体系（controlcenter、PlayerLevelBar、ExperimentalLevelBar）完全不接入，保持原样；
 * - 反色按类别决策，见 invertedFor()；改观感只改本文件。
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
  /** 是否开启原生反色。默认 false，只有前景使用 sys.color.font_primary 的控件才该开。 */
  inverted?: boolean;
}

export class GlassMaterial {
  /**
   * 原生反色按类别决策（2026-11-08 深浅色对比度回归修复）。
   *
   * SDK 语义（@ohos.arkui.uiMaterial.d.ts → ImmersiveMaterialOptions.colorInvert）：
   * - 让材质节点子树自适应「背景互补色」，只在 THIN / ULTRA_THIN 薄档、
   *   且中高算力设备上生效；模拟器常不生效、真机才显现，默认值为 false。
   * - 前景的自动反色只对 sys.color.font_primary 这类特殊系统资源生效，
   *   硬编码 hex 的 fontColor / fillColor 完全不会跟着反色。
   *
   * 本工程只有 FloatingBottomBar 的未选中项使用 $r('sys.color.font_primary')，
   * 与基线 6a0ec38 里仅有的两处 colorInvert:true（底栏 + NativeGlassCapsule，
   * 二者都走 capsule 配方）配套。8f9f952 把 11 类配方统一写死 true 后，
   * 顶栏 / 胶囊 / 菜单 / 输入 / 播放控件的薄档材质在真机上被翻成背景互补色，
   * 而其中的文字仍按 isDarkMode 硬编码黑白，两套主题都会错位：
   * 深色下底板提亮吃掉浅灰次级字（动态页「浅层」几乎看不清），
   * 浅色下底板变深压住黑字（几乎所有页面看不清）。
   *
   * 因此恢复按类别决策：仅 capsule 保留 true，其余回到 SDK 默认 false。
   * 若以后要给别的控件开启反色，必须同时把它的前景换成特殊系统资源。
   */
  static invertedFor(kind: GlassKind): boolean {
    return kind === 'capsule';
  }

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
      colorInvert: recipe.inverted ?? false,
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
      light: GlassMaterial.lightFor(kind, overrides?.light ?? Color.White),
      inverted: GlassMaterial.invertedFor(kind)
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
