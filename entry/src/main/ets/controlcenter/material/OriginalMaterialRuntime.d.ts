export interface OriginalMaterialCapabilities {
  Material: string;
  ScenarioType: string;
  DarkMode: string;
  pointLight: string;
  edgeLight: string;
  liquidMaterial: string;
  effectMask: string;
  pixelMapMask: string;
  brightness?: number;
  brightnessEC?: number;
  brightnessECSub?: number;
  generalECSub?: number;
}
export function inspectOriginalMaterial(attribute: Object): OriginalMaterialCapabilities;
export function applyOriginalFill(attribute: Object, chosen: boolean, light: boolean): void;
export function applyOriginalPointSource(attribute: Object, enabled: boolean, x: number, y: number, intensity: number, z?: number): void;

export function applyOriginalProgressBlend(attribute: Object): void;

export function originalProgressBlendAvailable(): boolean;
