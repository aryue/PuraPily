// Runs the actual model/filter/controller methods, with platform dependencies stubbed.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const modules = new Map();
function load(relative) {
  if (modules.has(relative)) return modules.get(relative);
  const file = path.join(root, relative + '.ets');
  const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const output = { exports: {} };
  vm.runInNewContext(compiled, {
    exports: output.exports, module: output, console,
    require: (name) => {
      if (name.includes('Logger')) return { logInfo() {}, logWarn() {}, logError() {} };
      const target = path.posix.normalize(path.posix.join(path.posix.dirname(relative), name));
      if (target === 'model/DanmakuItem' || target === 'services/DanmakuFilter') return load(target);
      return {};
    }
  }, { filename: file });
  modules.set(relative, output.exports);
  return output.exports;
}
const { DanmakuConfig, DanmakuItem, DanmakuType } = load('model/DanmakuItem');
const { DanmakuFilter } = load('services/DanmakuFilter');
const { DanmakuController } = load('services/DanmakuController');
const config = new DanmakuConfig();
const filter = new DanmakuFilter(config);
const controller = Object.create(DanmakuController.prototype);
controller.filter = filter;
controller.timeBuckets = new Map();
function item(time, text, type = DanmakuType.ROLL) {
  return new DanmakuItem({ time, content: text, type });
}
// Counted comments and repeats are independently reversible without reloading media.
const merged = controller.preprocessItems([item(100, '相同'), item(200, '相同'), item(2500, '相同'), item(15000, '相同')]);
assert.equal(merged.length, 3);
assert.equal(merged[0].count, 2);
controller.allDanmaku = [merged[2], merged[1], merged[0]];
controller.rebuildBuckets();
assert.equal(merged[0].repeatedInWindow, false);
assert.equal(merged[1].repeatedInWindow, true);
assert.equal(merged[2].repeatedInWindow, false);
config.hideDuplicates = true;
assert.equal(filter.shouldFilterRuntime(merged[1]), true);
assert.equal(filter.shouldFilterRuntime(merged[0]), false);
config.hideDuplicates = false;
assert.equal(filter.shouldFilterRuntime(merged[1]), false);
config.blockCounted = true;
assert.equal(filter.shouldFilterRuntime(merged[0]), true);
assert.equal(filter.shouldFilterRuntime(merged[1]), false);
config.blockCounted = false;
// Keyword settings must not discard data at load time; removal/disable restores it.
config.blockKeywords = ['相同'];
filter.updateConfig(config);
assert.equal(filter.shouldFilter(merged[0]), false);
assert.equal(filter.shouldFilterRuntime(merged[0]), true);
config.keywordFilterEnabled = false;
assert.equal(filter.shouldFilterRuntime(merged[0]), false);
config.keywordFilterEnabled = true;
config.blockKeywords = [];
assert.equal(filter.shouldFilterRuntime(merged[0]), false);
// Fixed/top, bottom/subtitle, scrolling, colorful and advanced remain independent.
config.showBottom = false;
assert.equal(filter.shouldFilterRuntime(item(0, '底部', DanmakuType.BOTTOM)), true);
assert.equal(filter.shouldFilterRuntime(item(0, '顶部', DanmakuType.TOP)), false);
config.showBottom = true;
config.showScroll = false;
assert.equal(filter.shouldFilterRuntime(item(0, '滚动')), true);
config.showScroll = true;
config.blockColorful = true;
const color = item(0, '彩色'); color.color = 0xFF6699;
assert.equal(filter.shouldFilterRuntime(color), true);
assert.equal(filter.shouldFilterRuntime(item(0, '白色')), false);
config.blockColorful = false;
config.showAdvanced = false;
assert.equal(filter.shouldFilterRuntime(item(0, '高级', DanmakuType.ADVANCED)), true);
console.log('PASS: counted/repeated comments, time-window boundaries, reversible keywords and type filters');
