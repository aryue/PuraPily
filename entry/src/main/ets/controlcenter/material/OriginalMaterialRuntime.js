// Read-only runtime export inspection. No constructor or light API is invoked.
export function inspectOriginalMaterial(attribute) {
  // These are the same modules already imported by the ArkTS material/effect
  // code. Use the runtime module object for inspection: the public HDS namespace
  // declaration cannot be passed across ArkTS/JS as an ordinary object.
  const materialModule = globalThis.requireNapi('hds.hdsMaterial');
  const hdsMaterial = materialModule.hdsMaterial ?? materialModule;
  const uiEffect = globalThis.requireNapi('graphics.uiEffect');
  const scenarios = hdsMaterial.ScenarioType;
  const effect = uiEffect.createEffect();
  return {
    Material: typeof hdsMaterial.Material,
    ScenarioType: typeof scenarios,
    DarkMode: typeof hdsMaterial.DarkMode,
    pointLight: typeof attribute.pointLight,
    edgeLight: typeof attribute.edgeLight,
    liquidMaterial: typeof effect.liquidMaterial,
    effectMask: typeof uiEffect.Mask?.createUseEffectMask,
    pixelMapMask: typeof uiEffect.Mask?.createPixelMapMask,
    brightness: scenarios?.CONTROL_CENTER_BRIGHTNESS,
    brightnessEC: scenarios?.CONTROL_CENTER_BRIGHTNESS_EC,
    brightnessECSub: scenarios?.CONTROL_CENTER_BRIGHTNESS_EC_SUB,
    generalECSub: scenarios?.CONTROL_CENTER_GENERAL_EC_SUB
  };
}

export function applyOriginalFill(attribute, chosen, light) {
  const module = globalThis.requireNapi('hds.hdsMaterial');
  const hds = module.hdsMaterial ?? module;
  const material = new hds.Material({ backgroundMaterial: {
    type: hds.MaterialType.ADAPTIVE,
    level: hds.MaterialLevel.ADAPTIVE,
    scenario: chosen ? 49 : hds.ScenarioType.CONTROL_CENTER_GENERAL_EC_SUB,
    materialColor: undefined, applyShadow: false,
    darkMode: hds.DarkMode.ALWAYS_DARK, params: undefined
  }});
  attribute.backgroundColor(undefined).backgroundEffect(undefined).systemMaterial(material);
  attribute.pointLight({ illuminated: light ? 3 : 0 });
}

export function applyOriginalPointSource(attribute, enabled, x, y, intensity, z = 110) {
  if (!enabled) { attribute.pointLight(undefined); return; }
  attribute.pointLight({ lightSource: {
    positionX: x, positionY: y, positionZ: z, intensity
  }, illuminated: 3 });
}

// Firmware AdvanceBlendModeUtils, a5=true (progress layers).
let progressBlender;
let progressBlendChecked = false;
export function originalProgressBlendAvailable() {
  if (progressBlendChecked) return progressBlender !== undefined;
  progressBlendChecked = true;
  try {
    const uiEffect = globalThis.requireNapi('graphics.uiEffect');
    progressBlender = uiEffect.createBrightnessBlender({
      cubicRate: 0, quadraticRate: 0, linearRate: 0.8, degree: 0.7939,
      saturation: 2, positiveCoefficient: [0.5, 1.5, 3],
      negativeCoefficient: [1.5, 2.5, 2], fraction: 0
    });
  } catch (error) { console.warn(`CCLab original progress blender unavailable: ${error}`); }
  return progressBlender !== undefined;
}
export function applyOriginalProgressBlend(attribute) {
  if (!originalProgressBlendAvailable()) throw new Error('Original progress blender unavailable');
  attribute.advancedBlendMode(progressBlender);
}
