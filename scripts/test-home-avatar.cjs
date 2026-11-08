const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const base = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/';
const store = new Map();
const cookie = 'SESSDATA=test; DedeUserID=123';
let response = { isLogin: true, uname: 'user', face: 'new-avatar', mid: 123 };
const context = { exports: {}, AppStorage: { get: key => store.get(key), setOrCreate: (key, value) => store.set(key, value) },
  FavoritesDataService: { getInstance: () => ({ warm() {} }) },
  getLoginAccessKey: async () => '', getUserInfo: async () => response,
  logInfo() {}, logWarn() {} };
function load(name, field, methods) {
  const ast = ts.createSourceFile(name, fs.readFileSync(base + name + '.ts', 'utf8'), ts.ScriptTarget.Latest, true);
  const klass = ast.statements.find(n => ts.isClassDeclaration(n) && n.name.text === name);
  const ctor = klass.members.find(ts.isConstructorDeclaration);
  const binding = ctor.body.statements.find(n => n.getText(ast).startsWith(`this.__${field} =`));
  assert.ok(binding.getText(ast).includes('createStorageLink'), 'avatar must use a compiled reactive storage binding');
  const members = klass.members.filter(n =>
    ((ts.isGetAccessor(n) || ts.isSetAccessor(n)) && n.name.getText(ast) === field) ||
    (ts.isMethodDeclaration(n) && methods.includes(n.name.getText(ast))));
  vm.runInNewContext(ts.transpileModule(`export class ${name}_${field} {
    constructor() { ${binding.getText(ast)} }
    createStorageLink(key, value) {
      if (!store.has(key)) store.set(key, value);
      return { get: () => store.get(key), set: value => store.set(key, value) };
    }
    ${members.map(n => n.getText(ast)).join('\n')}
  }`, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText,
  Object.assign(context, { store }));
  return new context.exports[`${name}_${field}`]();
}
(async () => {
  const home = load('Index', 'avatar', []);
  const profile = load('ProfilePage', 'userAvatarUrl', ['onLoginStateChanged', 'restoreCachedProfile']);
  store.set('statusBarHeight', 40);
  const insets = load('ProfilePage', 'statusBarHeight', []);
  assert.equal(insets.statusBarHeight, 40, 'first profile layout must use the measured host inset');
  store.set('statusBarHeight', 24);
  assert.equal(insets.statusBarHeight, 24, 'rotation must update the existing profile inset');
  profile.persistCachedProfile = async () => {};
  profile.clearCachedProfile = async () => {};
  store.set('biliCookie', cookie);
  profile.dataPreferences = { get: async key => ({ userProfileName: 'cached', userProfileFace: 'cached-avatar', userProfileMid: 123 })[key] };
  await profile.restoreCachedProfile();
  assert.equal(home.avatar, 'cached-avatar', 'cold-start cache is shared');
  await profile.onLoginStateChanged();
  assert.equal(home.avatar, 'new-avatar', 'API profile refresh updates existing home');
  assert.equal(store.get('userProfileName'), 'user', 'future first entry uses current profile name');
  response = { ...response, face: 'changed-avatar' };
  await profile.onLoginStateChanged();
  assert.equal(home.avatar, 'changed-avatar', 'subsequent avatar changes update without recreation');
  store.set('biliCookie', '');
  await profile.onLoginStateChanged();
  assert.equal(home.avatar, '', 'logout clears existing home avatar');
  assert.equal(store.get('userProfileName'), '', 'logout clears the name used on first entry');
  store.set('biliCookie', cookie);
  let release;
  profile.dataPreferences = { get: key => key === 'userProfileFace'
    ? new Promise(resolve => { release = resolve; }) : Promise.resolve('cached') };
  const restoring = profile.restoreCachedProfile();
  await new Promise(setImmediate);
  store.set('biliCookie', 'SESSDATA=other');
  release('old-account-avatar');
  await restoring;
  assert.equal(home.avatar, '', 'stale cache cannot restore an avatar after account changes');
  store.set('biliCookie', cookie);
  context.getUserInfo = () => new Promise(resolve => { release = resolve; });
  const refreshing = profile.onLoginStateChanged();
  await new Promise(setImmediate);
  store.set('biliCookie', '');
  release(response);
  await refreshing;
  assert.equal(home.avatar, '', 'stale API responses cannot restore an avatar after logout');
  console.log('PASS: compiled home/profile bindings share cache, refreshed avatars and logout; stale cache/API results are rejected.');
})().catch(error => { console.error(error); process.exitCode = 1; });
