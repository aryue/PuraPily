/**
 * 把「实际编译产物」的 GlassMaterial 工厂装进各回归脚本的 VM 沙箱。
 * 用真实编译产物而非手写副本，保证测试校验的就是线上配方。
 */
const fs = require('node:fs'), vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/utils/GlassMaterial.ts';
const source = fs.readFileSync(file, 'utf8').replace(/^import .*;\r?\n/gm, '');

module.exports = function installGlassMaterial(c) {
  c.uiMaterial = c.uiMaterial || {};
  c.uiMaterial.ImmersiveStyle = Object.assign(
    { ULTRA_THIN: 0, THIN: 1, REGULAR: 2, THICK: 3, ULTRA_THICK: 4 },
    c.uiMaterial.ImmersiveStyle || {});
  if (!c.uiMaterial.ImmersiveMaterial) {
    c.uiMaterial.ImmersiveMaterial = class { constructor(o) { this.options = o; } };
  }
  if (!c.uiMaterial.isImmersiveMaterialSupported) c.uiMaterial.isImmersiveMaterialSupported = () => true;
  c.Color = Object.assign({ Transparent: 0, White: '#FFFFFF' }, c.Color || {});
  c.BlurStyle = Object.assign(
    { NONE: 0, COMPONENT_ULTRA_THIN: 1, COMPONENT_REGULAR: 2, COMPONENT_THICK: 3, COMPONENT_THIN: 4 },
    c.BlurStyle || {});
  if (!c.deviceInfo) c.deviceInfo = { apiAvailable: () => true };
  if (!c.hdsMaterial) {
    c.hdsMaterial = { MaterialType: { IMMERSIVE: 1, ADAPTIVE: 2 }, MaterialLevel: { ADAPTIVE: 0, EXQUISITE: 1 } };
  }
  const saved = c.exports;
  c.exports = {};
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, c);
  const factory = c.exports.GlassMaterial;
  c.GlassMaterial = factory;
  c.exports = saved;
  return factory;
};
