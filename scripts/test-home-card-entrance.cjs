const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const source = fs.readFileSync(compiled + 'components/VideoCardComponent.ts', 'utf8');
const ast = ts.createSourceFile('VideoCardComponent.ts', source, ts.ScriptTarget.Latest, true);
const component = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === 'VideoCardComponent');
const methods = ['aboutToAppear', 'aboutToReuse', 'aboutToRecycle', 'resetEntrance', 'revealInViewport', 'openCard'].map(name => {
  const member = component.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(ast) === name);
  assert.ok(member, `Compiled card should contain ${name}`);
  return member.getText(ast);
});
const output = ts.transpileModule(`class Card { ${methods.join('\n')} }; Card;`, {
  compilerOptions: { target: ts.ScriptTarget.ES2020 }
}).outputText;
const Card = vm.runInNewContext(output, { Curve: { EaseOut: 0 } });
const revealedCardIds = new Set();
const animations = [];
const getUIContext = () => ({ animateTo: (options, update) => { animations.push(options); update(); } });
const opened = [];
const card = Object.assign(new Card(), { item: { id: 'first' }, revealedCardIds, getUIContext,
  entranceRevision: 0, onCardClick: item => opened.push(item.id) });

card.aboutToAppear();
assert.equal(card.entranceScale, 0.58, 'new cards start compact');
card.revealInViewport(false);
assert.equal(animations.length, 0, 'cache creation does not run an animation');
card.revealInViewport(true);
assert.equal(card.entranceScale, 1);
card.openCard();
assert.deepEqual(opened, [], 'wait for the resting cover rectangle when clicked mid-animation');
animations[0].onFinish();
assert.deepEqual(opened, ['first']);
card.revealInViewport(false);
card.revealInViewport(true);
assert.equal(animations.length, 1, 'returning to the viewport does not replay');

card.aboutToRecycle();
card.aboutToReuse({ item: { id: 'second' }, entranceCenterX: -6 });
assert.equal(card.entranceScale, 0.58, 'a recycled card starts compact for the new video');
assert.equal(card.entranceCenterX, -6, 'a recycled card takes its new column pivot');
card.revealInViewport(true);
assert.equal(animations.length, 2);
card.openCard();
card.aboutToRecycle();
card.aboutToReuse({ item: { id: 'first' } });
animations[1].onFinish();
assert.deepEqual(opened, ['first'], 'a recycled cell clears any queued click');
assert.equal(card.entranceScale, 1, 'recreated item objects share the video’s shown state');
card.revealInViewport(true);
assert.equal(animations.length, 2);
assert.match(source, /Stack\.scale\(\{ x: this\.entranceScale, y: this\.entranceScale, centerX: this\.entranceCenterX/);
assert.match(source, /Stack\.onVisibleAreaChange\(\[0\], \(visible: boolean\) => this\.revealInViewport\(visible\)\)/);
const home = fs.readFileSync(compiled + 'pages/HomePage.ts', 'utf8');
assert.match(home, /revealedCardIds: this\.revealedCardIds/);
assert.match(home, /entranceCenterX: this\.cardEntranceCenterX\(index\)/);
console.log('PASS home card entrance scale, pivot and reuse');
