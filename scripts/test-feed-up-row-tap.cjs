const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.ARK_TYPESCRIPT || 'D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/pages/VideoPlayerPage.ets'), 'utf8').replace(/\r\n/g, '\n');

const start = source.indexOf('  private referenceOpenUpSpace(');
const builderAt = source.indexOf('  @Builder\n  ReferenceUpRow(');
assert.ok(start > 0 && builderAt > start, 'referenceOpenUpSpace must sit right before ReferenceUpRow');
const snippet = source.slice(start, builderAt);
const context = { exports: {}, router: { pushes: [], pushUrl(opts) { this.pushes.push(opts); } } };
vm.runInNewContext(ts.transpileModule(`export class Page { ${snippet} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, context);
const page = new context.exports.Page();

// 1) 空间跳转收敛在 referenceOpenUpSpace：带 mid 才跳，参数齐全。
page.vd = { owner: { mid: 42, name: 'UP 主', face: 'face.url' } };
page.referenceOpenUpSpace();
assert.equal(context.router.pushes.length, 1);
assert.equal(context.router.pushes[0].url, 'pages/UpSpacePage');
assert.equal(context.router.pushes[0].params.mid, 42);
page.vd = { owner: { mid: 0, name: 'x', face: '' } };
page.referenceOpenUpSpace();
assert.equal(context.router.pushes.length, 1, 'missing mid must not navigate');
page.vd = undefined;
page.referenceOpenUpSpace();
assert.equal(context.router.pushes.length, 1, 'undefined detail must not navigate');

// 2) 连刷信息层（compact）：入口行自身必须退出触摸测试（留白透传给页面级单击显隐），
//    主页触点收窄为头像与昵称本身。
const upRow = source.slice(builderAt, source.indexOf('  @Builder\n  ReferenceIntro('));
assert.ok(/\.hitTestBehavior\(compact \? HitTestMode\.None : HitTestMode\.Default\)/.test(upRow),
  'entry row must opt out of hit testing in compact mode only');
assert.ok(/FeedAvatarImage\(\{[\s\S]*?\}\)\s*\n\s*\.onClick\(\(\) => this\.referenceOpenUpSpace\(\)\)/.test(upRow),
  'compact avatar must be its own space entry');
// 昵称触点必须挂在 Text 本身：昵称 Column 是 layoutWeight(1) 的拉伸框，命中框铺满留白，
// 挂在 Column 上会让「点留白进空间还是透传」变成概率行为（真机踩过）。
assert.ok(/\.textOverflow\(\{ overflow: TextOverflow\.Ellipsis \}\)\s*\n\s*\.onClick\(\(\) => this\.referenceOpenUpSpace\(\)\)/.test(upRow),
  'nickname Text must be its own space entry');
assert.ok(/\.layoutWeight\(1\)\.alignItems\(HorizontalAlign\.Start\)\s*\n\s*\}/.test(upRow),
  'name column must not carry an onClick (its frame covers the blank area)');

// 3) ReferenceUpRow 里不得再内联 router.pushUrl（跳转必须走 referenceOpenUpSpace）。
assert.ok(!upRow.includes('router.pushUrl'), 'ReferenceUpRow must not inline router.pushUrl');

// 4) 详情页（非 compact）整行进空间的旧口径保持：入口行仍挂 onClick。
assert.ok(/\.height\(compact \? 34 : 28\)\s*\n\s*\.onClick\(\(\) => this\.referenceOpenUpSpace\(\)\)/.test(upRow),
  'non-compact keeps the whole-row space entry');

console.log('PASS: feed up-row blank area no longer enters up space (falls through to info toggle); avatar/name stay clickable; detail page unchanged');
