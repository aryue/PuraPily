const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/';
let calls = [], props;
const context = { exports: {}, FlexAlign: { Center: 1 }, HitTestMode: { None: 0 },
  HomeRefreshIndicator: class { constructor(_, values) { props = values; } }, ViewPU: { create() {} } };
for (const name of ['Column', 'Row', 'Text', 'LoadingProgress', 'If']) {
  context[name] = new Proxy({}, { get: (_, key) => (...args) => calls.push([name, key, ...args]) });
}
function evaluate(code) {
  vm.runInNewContext(ts.transpileModule(code, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, context);
}
function subject(file, methods) {
  const source = fs.readFileSync(base + file + '.ts', 'utf8');
  const ast = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true);
  const cls = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === file.split('/').pop());
  const selected = methods.map(name => {
    const member = cls.members.find(n => ts.isMethodDeclaration(n) && n.name.getText(ast) === name);
    assert.ok(member, `${file}.${name} must survive CompileArkTS`);
    return member.getText(ast);
  });
  const name = file.split('/').pop() + 'Subject';
  evaluate(`export class ${name} { ${selected.join('\n')} }`);
  return Object.assign(new context.exports[name](), {
    observeComponentCreation2: fn => fn(1, true),
    ifElseBranchUpdateFunction: (_, fn) => fn()
  });
}
evaluate(fs.readFileSync(base + 'utils/HomeHeaderLayout.ts', 'utf8'));
Object.assign(context, context.exports);
const refresh = subject('components/HomeRefreshIndicator', ['headerHeight', 'initialRender']);
const initial = subject('components/HomeInitialLoading', ['initialRender']);
const dynamic = subject('pages/DynamicsPage', ['customRefreshComponent']);
for (const status of [0, 24, 40, 48]) {
  for (const hidden of [false, true]) {
    for (const searchHeight of [0, 11, 22, 33, 44]) {
      Object.assign(refresh, { statusBarHeight: status, hideStatusBar: hidden,
        homeSearchRowHeight: searchHeight, topInset: -1, refreshing: true });
      calls = [];
      refresh.initialRender();
      const top = calls.find(c => c[0] === 'Column' && c[1] === 'translate')[2].y;
      assert.equal(top, (hidden ? 0 : status) + 40 + searchHeight,
        'refresh indicator must track the animated header and current status inset');
      Object.assign(initial, { topInset: top, color: '#FB7299' });
      calls = [];
      initial.initialRender();
      assert.equal(calls.find(c => c[0] === 'Column' && c[1] === 'padding')[2].top, top);
      assert.equal(calls.find(c => c[0] === 'Row' && c[1] === 'height')[2], 200);
    }
  }
  for (const tab of [0, 1]) {
    for (const index of [0, 1]) {
      Object.assign(dynamic, { statusBarHeight: status, lastTabsIndex: tab, isRefreshing: true, refreshReady: true });
      dynamic.customRefreshComponent(index);
      assert.equal(props.refreshing, index === tab);
      assert.equal(props.ready, index === tab);
      Object.assign(refresh, props);
      assert.equal(refresh.headerHeight(), status + 56, 'dynamic feed must clear its own header independently of home');
    }
  }
}
for (const refreshing of [false, true]) {
  calls = [];
  initial.refreshing = refreshing;
  initial.initialRender();
  assert.equal(calls.filter(c => c[0] === 'LoadingProgress' && c[1] === 'create').length,
    refreshing ? 0 : 1, 'only one indicator may own the loading state');
  assert.equal(calls.find(c => c[0] === 'Row' && c[1] === 'height')[2], 200,
    'handoff must retain the initial loading placeholder');
}
for (const page of ['HomePage', 'LivePage', 'DiscoverPage', 'PgcChannelPage', 'RegionChannelPage']) {
  const source = fs.readFileSync(base + 'pages/' + page + '.ts', 'utf8');
  const ast = ts.createSourceFile(page, source, ts.ScriptTarget.Latest, true);
  let args;
  function visit(node) {
    if (!args && ts.isNewExpression(node) && node.expression.getText(ast) === 'HomeInitialLoading') args = node.arguments[1];
    ts.forEachChild(node, visit);
  }
  visit(ast);
  assert.ok(args, `${page} must use the shared initial indicator`);
  evaluate(`export function loadingProps() { return ${args.getText(ast)}; }`);
  for (const [refreshing, ready] of [[false, false], [true, false], [false, true]]) {
    const values = context.exports.loadingProps.call({ isRefreshing: refreshing, refreshReady: ready,
      customThemeColor: '#FB7299', getThemeColor: () => '#FB7299', statusBarHeight: 40,
      hideStatusBar: false, homeSearchRowHeight: 44 });
    assert.equal(values.refreshing, refreshing || ready, `${page} must hand off during both drag and refresh`);
  }
}

async function checkInitialRequests() {
  let complete;
  context.fetchPgcSeasonsByParams = () => new Promise(resolve => { complete = resolve; });
  context.getPopularVideos = context.fetchPgcSeasonsByParams;
  context.UserBehaviorService = { filterBlockedUploadersOnly: items => items };
  const pgc = subject('pages/PgcChannelPage', ['loadData']);
  const popular = subject('pages/DiscoverPage', ['loadData']);
  for (const page of [pgc, popular]) {
    for (const count of [0, 10]) {
      Object.assign(page, { isLoadingData: false, isRefreshing: false, isLoading: count === 0,
        dataSource: { totalCount: () => count } });
      const pending = page.loadData(true);
      assert.equal(page.isRefreshing, count > 0,
        'cold entry must use only the initial indicator; refreshing existing content uses the refresh indicator');
      complete([]);
      await pending;
      assert.equal(page.isRefreshing, false);
    }
  }
}
checkInitialRequests().then(() => console.log('PASS: compiled loading geometry, indicator handoff in every channel, cold-entry/refresh request states and dynamic isolation.'))
  .catch(error => { console.error(error); process.exitCode = 1; });
