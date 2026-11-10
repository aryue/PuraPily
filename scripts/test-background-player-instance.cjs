const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8');

// 背景：播放页里点相关推荐会 push 出**另一个** pages/VideoPlayerPage。
// 被覆盖的旧页在 onPageHide 里会为「等 onBackground 确认」而临时暂停，
// 若切后台时只按路由 path 判断「栈顶还是不是我」，旧页会把自己当成栈顶并把视频重新拉起来，
// 和新页的后台播放叠成两条音轨（熄屏/切后台后原视频自己响）。
// 所以判据必须带上实例身份，而不是只有 path。

// 1) 实例编号不能来自模块级自增计数器：
//    真机上同一个页面模块会被重复求值（两页各有一份模块作用域），计数器会重号，
//    判据退化成「永远是我」，修复等于没写（2026-11-10 实测踩过）。
const idFn = source.match(/function newVideoPlayerPageInstanceId\(\): string \{[\s\S]*?\n\}/);
assert.ok(idFn, 'instance id generator must exist');
assert.match(idFn[0], /Date\.now\(\)/, 'instance id must not rely on shared module state');
assert.match(idFn[0], /Math\.random\(\)/, 'instance id must stay unique even if the module is evaluated twice');
assert.ok(source.indexOf('let videoPlayerPageInstanceSeq') < 0, 'module-level counter must not come back');

// 2) onPageShow 时把自己登记为「当前最上层播放页」。
const showAt = source.indexOf('  onPageShow(): void {');
assert.ok(showAt > 0, 'onPageShow must exist');
const showBody = source.slice(showAt, showAt + 900);
assert.match(showBody, /AppStorage\.setOrCreate<string>\(TOP_PLAYER_PAGE_KEY, this\.pageInstanceId_\)/,
  'onPageShow must register this instance as the top player page');

// 3) 切后台确认：path 与实例编号两个判据都要在，且复核必须发生在「pending 标记」之前。
//    否则「旧页被 push 覆盖后暂停 → 切后台」这条路径根本走不到复核。
const bgAt = source.indexOf('  onAppBackgroundConfirmed(): void {');
assert.ok(bgAt > 0, 'onAppBackgroundConfirmed must exist');
const bgBody = source.slice(bgAt, source.indexOf('  private onAppBackgroundFlagChanged(): void {', bgAt));
assert.match(bgBody, /topOnBackground === 'pages\/VideoPlayerPage'/, 'route-path check must stay');
assert.match(bgBody, /!this\.isTopPlayerPageInstance\(\)/, 'background confirm must also compare the page instance');
assert.ok(bgBody.indexOf('coveredByOtherPage') < bgBody.indexOf('if (!this.bgpPausedByPageHide_) return;'),
  'the covered check must not be short-circuited by the pending flag');
assert.match(bgBody, /this\.bgpPausedByPageHide_ = false;[\s\S]*pausePlaybackForCoveredPage\(\)/,
  'a covered page must clear the pending flag and stay paused');

// 4) 被覆盖的旧页不能改写进程级媒体会话（否则新页在通知栏/锁屏显示成已暂停）。
const pauseAt = source.indexOf('  private pausePlaybackForCoveredPage(): void {');
assert.ok(pauseAt > 0);
const pauseBody = source.slice(pauseAt, source.indexOf('  // Native play() and startup seeks', pauseAt));
assert.match(pauseBody, /if \(this\.isTopPlayerPageInstance\(\)\) LiveViewHelper\.updatePlayState\(false\);/,
  'covered page must not write the shared media session state');

// 5) 行为：同路由的另一个实例在上面时，旧实例不算栈顶。
const methods = source.slice(
  source.indexOf('  /** 最后一次 onPageShow 的播放页实例编号'),
  source.indexOf('  /** 播放页已被覆盖时确保没有残留播放'));
assert.ok(methods.includes('isTopPlayerPageInstance'), 'instance helpers must live together');

const state = { topId: '' };
const context = {
  exports: {},
  AppStorage: { get: (key) => (key === 'topVideoPlayerPageId' ? state.topId : undefined) }
};
vm.runInNewContext(ts.transpileModule(`const TOP_PLAYER_PAGE_KEY = 'topVideoPlayerPageId';\nexport class Page { ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();
page.pageInstanceId_ = 'a-1';

state.topId = 'b-2';
assert.equal(page.isTopPlayerPageInstance(), false, 'a page under another player page is not the top instance');
state.topId = 'a-1';
assert.equal(page.isTopPlayerPageInstance(), true, 'the page itself on top owns background playback');
state.topId = '';
assert.equal(page.isTopPlayerPageInstance(), true, 'unregistered key keeps the legacy path-only judgement working');

console.log('PASS: background resume is gated by player page instance, not just by route path');
