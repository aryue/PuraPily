const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const codeOnly = (source) => source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
const pagesDir = path.join(root, 'entry/src/main/ets/pages');
const pageFiles = fs.readdirSync(pagesDir).filter((name) => name.endsWith('.ets'));
const routes = [
  'AboutPage', 'AudioOutputLab', 'BilibiliLoginPage', 'CommentDetailPage', 'DashPocPage',
  'DynamicDetailPage', 'FavoritesPage', 'HotRankingPage', 'IjkLab', 'LevelBarLab',
  'LivePlayerPage', 'LocalWallpaperPage', 'MessagesPage', 'MsgNoticePage', 'OfflineCachePage',
  'QrCodeLoginPage', 'RecommendDetectionPage', 'SearchPage', 'SettingsPage', 'SettingsSectionPage',
  'SponsorBlockPage', 'SurfaceRebindLab', 'UpSpacePage', 'VideoPlayerPage', 'WatchHistoryPage',
  'WhisperDetailPage'
];

const mainPages = JSON.parse(read('entry/src/main/resources/base/profile/main_pages.json'));
assert.deepEqual(mainPages.src, ['pages/Index'], 'only Index may be registered as a router page');

const entryPages = pageFiles.filter((name) => /@Entry\b/.test(read(`entry/src/main/ets/pages/${name}`)));
assert.deepEqual(entryPages, ['Index.ets'], 'only Index may keep @Entry inside pages');

for (const file of [...pageFiles.map((name) => `entry/src/main/ets/pages/${name}`),
  'entry/src/main/ets/entryability/EntryAbility.ets']) {
  const source = read(file);
  const code = codeOnly(source);
  assert.ok(!/@ohos\.router/.test(code), `${file}: must not import @ohos.router`);
  assert.ok(!/getRouter\(\)/.test(code), `${file}: must not use UIContext.getRouter()`);
  assert.ok(!/\brouter\.(pushUrl|replaceUrl|back|getParams|getState)\b/.test(code),
    `${file}: must not call the legacy router API`);
}

const index = read('entry/src/main/ets/pages/Index.ets');
assert.match(index, /private readonly pageStack: NavPathStack = new NavPathStack\(\)/,
  'Index must own the single navigation stack');
assert.match(index, /Navigation\(this\.pageStack\)/, 'Index must bind that stack to Navigation');
assert.match(index, /\.navDestination\(this\.PageMap\)/, 'Index must install the destination builder');
assert.match(index, /\.customNavContentTransition\(/, 'Index must own navigation transitions');
assert.match(index, /NavRouteShell\(\{ routeName: name, routeParam:/, 'PageMap must delegate to NavRouteShell');
assert.match(index, /pageStack\.setInterception\(\{[\s\S]{0,300}?didShow:/,
  'Index must synchronize stack state after system pops');
assert.match(index, /navStackDepth === 0/, 'floating chrome must be gated by stack depth');
assert.ok(!/pageTransition\(\)/.test(index), 'Index must not keep PageTransition');
assert.match(index, /homeEntranceSettleRevision/,
  'returning to a visible home surface must publish an entrance-settle revision');
assert.match(index, /homeSurfaceInitialized && surfaceActive && !this\.homeSurfaceActive/,
  'settle revision must trigger on every home re-activation, not only the first launch');
const homeCard = read('entry/src/main/ets/components/VideoCardComponent.ets');
const channelCard = read('entry/src/main/ets/components/HomeChannelCardEntrance.ets');
for (const source of [homeCard, channelCard]) {
  assert.match(source, /homeEntranceSettleRevision/, 'card entrance must listen for the settle revision');
  assert.match(source, /private settleEntrance\(\): void \{[\s\S]{0,400}?this\.entranceScale = 1;/,
    'settle must force the card back to full size without state-ordering guards');
}

const nav = read('entry/src/main/ets/services/AppNavigation.ets');
assert.ok(!/@ohos\.router/.test(nav), 'AppNavigation must be stack-only');
assert.match(nav, /pushPathByName\(/, 'push must go through NavPathStack');
assert.match(nav, /replacePathByName\(/, 'replace must go through NavPathStack');
assert.match(nav, /this\.stack\.pop\(true\)/, 'back must pop the navigation stack');
assert.match(nav, /this\.stack\.clear\(true\)/, 'back to Index must clear the stack');
assert.match(nav, /requestPopHold\(\)/, 'player returns must be able to hold the exiting destination');
assert.match(nav, /finishTransition\(\)/, 'held player returns must finish the navigation transition');
assert.match(nav, /HomeCardMorph\.peekArmed\(\) \|\| FloatingVideoTransition\.active\(\)/,
  'cover morph and floating restore pushes must stay instant');
assert.match(nav, /NavigationOperation\.POP/, 'player return hold must be scoped to POP');
assert.match(nav, /subscribeTopChanged\(/, 'continuation must subscribe to stack changes');

const shell = read('entry/src/main/ets/components/NavRouteShell.ets');
assert.match(shell, /NavDestination\(\) \{/, 'every route must render a NavDestination');
assert.match(shell, /\.hideTitleBar\(true\)/, 'pages own their chrome, so the destination title bar is hidden');
assert.match(shell, /NavPageHost/, 'page lifecycle must be bridged to the destination lifecycle');
for (const route of routes) {
  assert.match(shell, new RegExp(`this\\.routeName === '${route}'`), `${route} must be in the route map`);
  const page = read(`entry/src/main/ets/pages/${route}.ets`);
  assert.match(page, new RegExp(`export struct ${route}\\b`), `${route} must be exported for Navigation`);
  assert.ok(!/@Entry\b/.test(page), `${route} must not retain @Entry`);
}

for (const [route, lifecycle] of Object.entries({
  AudioOutputLab: 'onPageShow', DynamicDetailPage: 'onPageHide', FavoritesPage: 'onBackPress',
  LevelBarLab: 'onPageShow', LivePlayerPage: 'onPageShow', LocalWallpaperPage: 'onBackPress',
  SearchPage: 'onBackPress', UpSpacePage: 'onBackPress', VideoPlayerPage: 'onPageShow',
  WatchHistoryPage: 'onPageShow'
})) {
  const page = read(`entry/src/main/ets/pages/${route}.ets`);
  assert.match(page, new RegExp(`navHost: NavPageHost`), `${route} must declare a lifecycle bridge`);
  assert.match(page, new RegExp(`this\\.navHost\\.attach\\(`), `${route} must attach ${lifecycle}`);
  assert.match(page, new RegExp(`this\\.${lifecycle}\\(`), `${route} must keep its ${lifecycle} behavior`);
}

for (const route of ['CommentDetailPage', 'DynamicDetailPage', 'HotRankingPage', 'LivePlayerPage',
  'MsgNoticePage', 'QrCodeLoginPage', 'SearchPage', 'SettingsSectionPage', 'SurfaceRebindLab',
  'UpSpacePage', 'VideoPlayerPage', 'WhisperDetailPage']) {
  const page = read(`entry/src/main/ets/pages/${route}.ets`);
  assert.match(page, /navParams:/, `${route} must consume destination params`);
  assert.ok(!/router\.getParams\(\)/.test(page), `${route} must not read router params`);
}

const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
assert.match(ability, /AppNavigation\.pushUrl\(/, 'deep links must enter the navigation stack');
assert.match(ability, /AppNavigation\.subscribeTopChanged\(/, 'continuation must follow navigation changes');
assert.match(ability, /AppNavigation\.currentPath\(\)/, 'background/continuation snapshots must read the navigation stack');

for (const file of pageFiles) {
  const source = read(`entry/src/main/ets/pages/${file}`);
  assert.ok(!/^\s*pageTransition\(\)/m.test(source), `${file}: PageTransition is replaced by navigation transitions`);
}

console.log('PASS: full Navigation routing — single root stack, no legacy router, all pages registered, lifecycle bridged, player pop held.');
