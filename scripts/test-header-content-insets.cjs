const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const context = { exports: {}, LengthMetrics: { vp: x => x },
  Color: { Transparent: 0 }, ScrollEffectType: { GRADIENT_BLUR: 2 } };
function evaluate(source) {
  vm.runInNewContext(ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
}
evaluate(fs.readFileSync(base + 'utils/HeaderStyle.ts', 'utf8').replace(/^import .*;\r?\n/gm, ''));
const { gradientTitleBarStyle } = context.exports;
let calls = [];
const component = name => new Proxy({}, { get: (_, key) => (...args) => calls.push([name, key, ...args]) });
for (const name of ['Column', 'WaterFlow', 'If', 'ForEach', 'FlowItem', 'Text', 'Refresh']) context[name] = component(name);
Object.assign(context, { ClickEffectLevel: { LIGHT: 0 }, BarState: { Off: 0 }, EdgeEffect: { Spring: 0 } });
const source = fs.readFileSync(base + 'pages/FavoritesPage.ts', 'utf8');
const ast = ts.createSourceFile('FavoritesPage.ts', source, ts.ScriptTarget.Latest, true);
const page = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'FavoritesPage');
const detail = page.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === 'FolderDetailView');
evaluate(`export class Subject { ${detail.getText(ast)} }`);
for (const status of [0, 24, 40, 48]) {
  const mask = gradientTitleBarStyle(true).originalStyle.backgroundStyle;
  const nativeBottom = status + 56 + mask.maskExtraHeight;
  for (const columns of [1, 2]) {
    for (const state of ['loading', 'loaded', 'empty']) {
      calls = [];
      const subject = new context.exports.Subject();
      Object.assign(subject, { globalStatusBarHeight: status, columnCount: columns,
        isLoadingResources: state === 'loading', resourceList: state === 'empty' ? [] : [{ id: 1 }],
        resourceHasMore: false, isDarkMode: true,
        observeComponentCreation2: fn => fn(1, true),
        ifElseBranchUpdateFunction: (_, fn) => fn(),
        forEachUpdateFunction: (_, items, fn) => items.forEach(fn),
        SkeletonVideoCard() {}, VideoCard() {} });
      subject.FolderDetailView();
      const offset = state === 'empty'
        ? calls.find(c => c[0] === 'Text' && c[1] === 'margin')[2].top
        : calls.find(c => c[0] === 'WaterFlow' && c[1] === 'contentStartOffset')[2] +
          calls.find(c => c[0] === 'WaterFlow' && c[1] === 'padding')[2].top;
      assert.ok(offset >= nativeBottom, `${state}, ${columns} columns, status=${status}: content overlaps native mask`);
      if (state !== 'empty') {
        assert.ok(!calls.some(c => c[0] === 'Column' && c[1] === 'padding'),
          'the scrolling viewport must remain full height for native header underlap');
      }
    }
  }

}
assert.equal(gradientTitleBarStyle(true).originalStyle.backgroundStyle.maskExtraHeight, 0);
console.log('PASS: compiled favorites loading/content/empty states, one/two columns, visible/hidden status bar, and native gradient clearance.');
