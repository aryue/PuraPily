const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/SearchPage.ts';
const ast = ts.createSourceFile(file, fs.readFileSync(file, 'utf8'), ts.ScriptTarget.Latest, true);
const subject = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === 'SearchPage');
const methods = ['handleBackToTopClick', 'setResultOptionsHidden'].map(name =>
  subject.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name).getText(ast));
const context = { exports: {}, Context: { animateTo: (_options, update) => update() },
  Curve: {}, curves: { springMotion: () => 0 }, setTimeout: callback => callback() };
vm.runInNewContext(ts.transpileModule(`export class Subject { ${methods.join('\n')} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
for (const da of [false, true]) {
  for (const activeTab of ['video', 'bili_user', 'media_bangumi']) {
    const page = new context.exports.Subject();
    let scrolls = 0;
    Object.assign(page, { da, activeTab, resultOptionsHidden: true, resultOptionsHeight: 0,
      triggerHaptic() {}, getUIContext: () => ({ animateTo: (_options, update) => update() }),
      scroller: { scrollTo(options) {
        assert.equal(page.resultOptionsHidden, false, 'restore options before initiating programmatic scroll');
        assert.equal(page.resultOptionsHeight, activeTab === 'video' ? 88 : 44);
        assert.equal(options.yOffset, 0);
        assert.equal(options.animation.duration, da ? 0 : 300);
        scrolls++;
      } } });
    page.handleBackToTopClick();
    page.handleBackToTopClick();
    assert.equal(scrolls, 2);
  }
}
console.log('PASS: compiled search back-to-top restores video/user/bangumi options, repeated taps and disabled animations.');
