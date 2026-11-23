const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');

const compiled = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
const timers = new Map();
let nextTimer = 1;
function setTimer(callback, delay) {
  assert.equal(delay, 750);
  const id = nextTimer++;
  timers.set(id, callback);
  return id;
}
function runTimer(id) {
  const callback = timers.get(id);
  assert.ok(callback, 'fallback is scheduled');
  timers.delete(id);
  callback();
}
function loadCard(componentName, methodNames) {
  const source = fs.readFileSync(compiled + 'components/' + componentName + '.ts', 'utf8');
  const ast = ts.createSourceFile(componentName + '.ts', source, ts.ScriptTarget.Latest, true);
  const component = ast.statements.find(node => ts.isClassDeclaration(node) && node.name.text === componentName);
  const methods = methodNames.map(name => {
    const member = component.members.find(node => ts.isMethodDeclaration(node) && node.name.getText(ast) === name);
    assert.ok(member, `Compiled ${componentName} should contain ${name}`);
    return member.getText(ast);
  });
  const fallback = ast.statements.find(node => ts.isVariableStatement(node) &&
    node.declarationList.declarations.some(decl => decl.name.getText(ast) === 'ENTRANCE_FALLBACK_MS'));
  assert.ok(fallback);
  const output = ts.transpileModule(`${fallback.getText(ast)}\nclass Card { ${methods.join('\n')} }; Card;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020 }
  }).outputText;
  const Card = vm.runInNewContext(output, {
    Curve: { EaseOut: 0 }, setTimeout: setTimer, clearTimeout: id => timers.delete(id)
  });
  return { source, Card };
}

const { source, Card } = loadCard('VideoCardComponent',
  ['aboutToAppear', 'aboutToReuse', 'aboutToRecycle', 'aboutToDisappear', 'prepareEntrance',
    'clearEntranceTimer', 'revealEntrance', 'openCard']);
const revealedCardIds = new Set();
const animations = [];
const animateTo = (options, update) => {
  assert.deepEqual({ ...options.expectedFrameRateRange }, { min: 60, max: 120, expected: 120 });
  assert.equal(options.duration, 450);
  assert.equal(options.curve, 0);
  animations.push(options);
  update();
};
const getUIContext = () => ({ animateTo });
const opened = [];
const card = Object.assign(new Card(), { item: { id: 'first' }, revealedCardIds, getUIContext,
  entranceScale: 1, entranceRevision: 0, entranceTimer: -1, onCardClick: item => opened.push(item.id) });
const duplicate = Object.assign(new Card(), { item: { id: 'first' }, revealedCardIds, getUIContext,
  entranceScale: 1, entranceRevision: 0, entranceTimer: -1 });

card.aboutToAppear();
duplicate.aboutToAppear();
const firstTimer = card.entranceTimer;
assert.equal(animations.length, 0, 'creation does not immediately animate a cached card');
assert.equal(card.entranceScale, 0.2, 'the first rendered size is compact');
card.revealEntrance();
assert.equal(card.entranceScale, 1);
assert.equal(timers.has(firstTimer), false);
card.openCard();
assert.deepEqual(opened, [], 'wait for the resting cover rectangle when clicked mid-animation');
animations[0].onFinish();
assert.deepEqual(opened, ['first']);
duplicate.revealEntrance();
assert.equal(duplicate.entranceScale, 1, 'an existing compact duplicate still reaches full size');
card.revealEntrance();
assert.equal(animations.length, 1, 'returning to the viewport does not replay');

card.aboutToRecycle();
card.aboutToReuse({ item: { id: 'second' }, entranceCenterX: -6 });
assert.equal(card.entranceScale, 0.2, 'a reused card never starts with a full-size flash');
assert.equal(card.entranceCenterX, -6, 'a recycled card takes its new column pivot');
runTimer(card.entranceTimer);
assert.equal(animations.length, 2);
assert.equal(card.entranceScale, 1, 'a missed visibility edge still reaches full size');
card.openCard();
card.aboutToRecycle();
card.aboutToReuse({ item: { id: 'third' } });
animations[1].onFinish();
assert.deepEqual(opened, ['first'], 'a recycled cell clears any queued click');
assert.equal(card.entranceScale, 0.2, 'a late finish cannot overwrite a reused card');
const thirdTimer = card.entranceTimer;
card.aboutToDisappear();
assert.equal(timers.has(thirdTimer), false);
assert.equal(animations.length, 2);
assert.match(source, /Stack\.scale\(\{ x: this\.entranceScale, y: this\.entranceScale, centerX: this\.entranceCenterX/);
assert.match(source, /Stack\.onVisibleAreaChange\(\[0\], \(visible: boolean\) => \{\s*if \(visible\)\s*this\.revealEntrance\(\)/);
const home = fs.readFileSync(compiled + 'pages/HomePage.ts', 'utf8');
assert.match(home, /revealedCardIds: this\.revealedCardIds/);
assert.match(home, /entranceCenterX: this\.cardEntranceCenterX\(index\)/);

const { Card: ChannelCard } = loadCard('HomeChannelCardEntrance',
  ['aboutToAppear', 'aboutToDisappear', 'clearEntranceTimer', 'updateEntrance', 'reveal', 'anchorId']);
const channelCard = Object.assign(new ChannelCard(), {
  cardKey: 'channel-card', gridId: 'grid', channelIndex: 3, activeChannel: 2, paneActive: true,
  homeActive: true, visible: false, entranceScale: 1, entranceTimer: -1, revealedCardIds: new Set(),
  getUIContext: () => ({ animateTo, getComponentUtils: () => ({ getRectangleById: () => null }) })
});
channelCard.aboutToAppear();
assert.equal(channelCard.entranceScale, 0.2, 'a card waiting for its channel starts compact');
assert.equal(channelCard.entranceTimer, -1);
channelCard.activeChannel = 3;
channelCard.updateEntrance();
const inactiveTimer = channelCard.entranceTimer;
assert.ok(timers.has(inactiveTimer));
channelCard.activeChannel = 2;
channelCard.updateEntrance();
assert.equal(timers.has(inactiveTimer), false);
channelCard.activeChannel = 3;
channelCard.updateEntrance();
runTimer(channelCard.entranceTimer);
assert.equal(animations.length, 3);
assert.equal(channelCard.entranceScale, 1, 'the channel fallback animates a missed visibility edge');
assert.equal(channelCard.entranceLayer, true);
animations[2].onFinish();
assert.equal(channelCard.entranceLayer, false);
channelCard.visible = true;
channelCard.updateEntrance();
assert.equal(animations.length, 3);
assert.equal(timers.size, 0);
console.log('PASS home card first frame, visibility fallback, pivot and reuse');
