const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('D:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const geometry = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync('entry/src/main/ets/utils/SplitPaneGeometry.ets', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, geometry);
const source = fs.readFileSync('entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/pages/LivePlayerPage.ts', 'utf8');
// Builder 的视觉口径直接读源码：编译产物会改写 builder 结构，但字符串与修饰符仍在
const etsSource = fs.readFileSync('entry/src/main/ets/pages/LivePlayerPage.ets', 'utf8');
assert.ok(!etsSource.includes(".backgroundColor(this.liveFullscreen ? '#80202430' : '#4D202430')"),
  'landscape bottom controls have no opaque shade plate');
assert.ok(etsSource.includes("this.liveFullscreen ? '#66000000' : '#00000000'"),
  'split top bar has no gradient shade while fullscreen keeps it');
assert.ok(etsSource.includes("@StorageLink('cardMargin') cardMargin"),
  'split margin reads the shared cardMargin setting');
const splitLayout = fs.readFileSync('entry/src/main/ets/components/SplitPaneLayout.ets', 'utf8');
assert.ok(etsSource.includes('SplitPaneLayout({') && splitLayout.includes('.id(this.handleId)'),
  'live uses the shared resize handle with its own id');
assert.ok(splitLayout.includes('.translate({ x: this.swapped ? -2 : 2 })') &&
  splitLayout.includes('justifyContent(FlexAlign.Center)'),
  'the shared visible grip sits on the detail side of a centred touch target');
assert.ok(!etsSource.includes('if (this.landscapeResizeActive && this.landscapeResizePanelWidth > 0) return'),
  'panel container width must never be frozen during a drag');
assert.ok(!etsSource.includes('landscapePanelTabWidth(') && !etsSource.includes('landscapeResizeActive'),
  'no per-tab numeric width and no frozen tab: both tabs follow the container live');
const swiperSource = etsSource.slice(etsSource.indexOf('Swiper(this.livePanelSwiper)'),
  etsSource.indexOf('.index(this.livePanelTab)'));
assert.ok(swiperSource.length > 0 && swiperSource.includes("}.width('100%').height('100%')"),
  'swiper pages fill the container so intro and comments resize together');
assert.ok(etsSource.includes("availableWidth: this.landscapePanelContentWidth()"),
  'intro cards receive a live panel width during a drag');
assert.ok(etsSource.includes("import { VideoListItem }") && etsSource.includes('VideoListItem({'),
  'intro recommendations reuse the normal intro page video card component');
assert.ok(!etsSource.includes('LiveIntroRoomCard(') && !etsSource.includes('recommendCoverWidth('),
  'hand-rolled fixed-height live card is gone');
assert.ok(etsSource.includes("detailText: `${formatOnlineCount(room.online)}人气`"),
  'room online count maps into the shared card detail line');
assert.ok(etsSource.includes("videoId: '', ownerMid: ''"),
  'empty video id hides the video feedback more button on live cards');
assert.ok(etsSource.includes('this.LiveInfoHeader(this.liveFullscreen)'),
  'split landscape drops the anchor capsule from the player top bar');
assert.ok(etsSource.includes('this.LiveInfoHeader(true)'),
  'portrait overlay keeps its anchor capsule');
assert.ok(etsSource.includes('if (showAnchor)'),
  'header capsule is conditional');
assert.ok((etsSource.match(/this\.informationVisible = this\.defaultInformationVisible\(\);/g) || []).length >= 2,
  'page entry and orientation change both use the shared default visibility');
assert.ok(!etsSource.includes('this.settleInformation(!enabled)'),
  'leaving fullscreen back to split also starts with controls hidden');
assert.ok(etsSource.includes("this.PanelTab('简介', 0)") && etsSource.includes("this.PanelTab('评论', 1)"),
  'tabs are renamed to intro and comments');
assert.ok(etsSource.includes('this.LandscapeIntroTab()') && etsSource.includes('this.LandscapeCommentTab()'),
  'intro and comment builders are wired into the swiper');
assert.ok(etsSource.includes('fetchRecommendedLiveRooms(page, 30)'),
  'intro recommendations use the portrait live feed algorithm');
assert.ok(etsSource.includes('getVideoIntroCard(anchorUid)'),
  'follower count comes from the same user-card API as the normal intro page');
assert.ok(etsSource.includes('粉丝  ${formatOnlineCount(this.online)}人气'),
  'video count is replaced by online count while fans stay');
assert.ok(etsSource.includes('ForEach(this.liveChatMessages, (message: LiveChatMessage)'),
  'comment tab renders full chat history, not a height-clipped slice');
assert.ok(etsSource.includes('private readonly LIVE_CHAT_LIMIT: number = 200'),
  'chat history has an explicit upper bound');
assert.ok(etsSource.includes('scrollEdge(Edge.Bottom)'),
  'comment list follows the newest message while pinned to the bottom');
assert.ok((etsSource.match(/\}\.width\('100%'\)\.alignItems\(HorizontalAlign\.Start\)/g) || []).length >= 2,
  'comment bubbles and status hint are wrapped in a full-width start-aligned column');
assert.ok(etsSource.includes('Text(`房间号 ${this.roomId}`).fontSize(10).fontColor(\'#757A81\').maxLines(1).width(\'100%\')'),
  'room id line fills the intro column width instead of being centred');
assert.ok(etsSource.includes("List({ scroller: this.landscapeChatScroller })"),
  'comment tab uses a scrollable list bound to its own scroller');
assert.ok(!etsSource.includes('liveLandscapePlayerRatio'),
  'split ratio is no longer persisted to preferences');
assert.ok(etsSource.includes('this.landscapeRatio = this.initialLandscapeRatio(params)'),
  'page entry resolves the ratio from instance-scoped defaults/inheritance');
const areaChangeSource = etsSource.slice(etsSource.indexOf('.onAreaChange('), etsSource.indexOf('.onTouch(this.onVT)'));
assert.ok(areaChangeSource.length > 0 && !areaChangeSource.includes('landscapeRatio ='),
  'a plain portrait/landscape rotation keeps the current split ratio');
assert.ok(etsSource.includes('private liveFullscreenLocked: boolean = false'),
  'fullscreen landscape lock is an explicit page state');
assert.ok((etsSource.match(/this\.lockFullscreenLandscape\(\)/g) || []).length >= 3,
  'top button, drag-to-fullscreen and portrait entry all lock the window landscape');
assert.ok(etsSource.includes('this.mw.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE)'),
  'fullscreen uses AUTO_ROTATION_LANDSCAPE so both landscape directions still work');
assert.ok(etsSource.includes('if (!this.liveFullscreenLocked) this.applyRotationMode();'),
  'async window init must not override an active fullscreen landscape lock');
assert.ok(areaChangeSource.includes('if (this.liveFullscreenLocked && !this.pendingLandscapeFullscreen)'),
  'physical rotation does not reset the fullscreen page while locked');
assert.ok(etsSource.includes('void this.unlockFullscreenLandscape();'),
  'leaving fullscreen hands orientation back to the global setting');
function section(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  assert.ok(a >= 0 && b > a);
  return source.slice(a, b);
}
const ctx = { ...geometry.exports, exports: {}, clearTimeout, setTimeout, getLiveRoomInfo: async () => null, logInfo() {}, Curve: { EaseOut: 0 }, fetchLiveRoomsByArea: async () => [{ roomId: 3 }, { roomId: 2 }],
  fetchRecommendedLiveRooms: async () => [{ roomId: 1 }, { roomId: 2 }, { roomId: 3 }, { roomId: 3 }],
  AppStorage: { setOrCreate(key, value) { ctx.isFullscreenFlag = value; }, set() {}, get: () => undefined },
  window: { Orientation: { AUTO_ROTATION_LANDSCAPE: 1, PORTRAIT: 2, AUTO_ROTATION_RESTRICTED: 3, AUTO_ROTATION: 4 },
    getLastWindow: async () => ({ setWindowBrightness() {} }) },
  StatusBarUtils: { setSystemBars() {} } };
const methods = section('  private portraitRoom()', '  private async setPortraitScale(') +
  section('  private landscapeLayout()', '  private initialLandscapeRatio(') +
  section('  private initialLandscapeRatio(', '  private screenWv(): number {') +
  section('  private applySystemBars(', '  private openLiveMenu(') +
  section('  private goBack(', '  private toggleBackgroundPlayback(') +
  section('  private introRooms(', '  private async switchRoom(') +
  section('  private async switchRoom(', '  private resetLive(') +
  section('  private applyStreamQuality(', '  private async startPlay(') +
  section('  private onTM(', '  private LiveAction(');
vm.runInNewContext(ts.transpileModule(`export class Page { constructor() { this.startLiveChat = () => {}; this.finishLevelGesture = () => {}; this.previewRelease = Promise.resolve(); this.previewTask = Promise.resolve(); this.previewGeneration = 0; this.activeSlot = 0; this.previewRoomId = 0; this.touchActive = true; } ${methods} }`, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, ctx);
async function main() {
  const p = new ctx.exports.Page();
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800, sourceWidth: 1080, sourceHeight: 1920,
    portraitScale: 'auto', portraitScaleScope: 'standard', safeTop: 24, statusBarHeight: 0,
    cardMargin: 0, landscapeExpand: 0, liveFullscreen: false, landscapeRatio: 2 / 3, landscapePlaybackSide: 'left',
    getUIContext: () => ({ animateTo: (options, action) => { action(); options.onFinish?.(); },
      vp2px: (v) => v, px2vp: (v) => v, getHostContext: () => ({}),
      getRouter: () => ({ pushUrl: (args) => { ctx.lastPush = args; return Promise.resolve(); } }) }),
    applyRotationMode: async () => {} });
  assert.equal(p.videoW(), 400);
  assert.equal(p.videoH(), 400 * 16 / 9);
  p.portraitScale = 'fill';
  assert.equal(p.videoW(), 450);
  assert.equal(p.videoH(), 800);
  p.sourceWidth = 600; p.sourceHeight = 800;
  assert.equal(p.videoW(), 400, 'standard scope must not crop a 3:4 stream');
  p.portraitScaleScope = 'all';
  assert.equal(p.videoW(), 600, 'all portrait scope crops other portrait ratios');
  p.portraitScaleScope = 'standard';
  p.sourceWidth = 1920; p.sourceHeight = 1080;
  assert.equal(p.videoW(), 400);
  assert.equal(p.videoH(), 225);
  const top = p.videoTop();
  p.informationVisible = false;
  assert.equal(p.videoTop(), top, 'clearing information must not move video');
  const near = (a, b, message) => assert.ok(Math.abs(a - b) < 0.01, `${message}: ${a} != ${b}`);
  // 横屏分栏：播放区占 2/3，画面完整显示在播放区里（不再套用竖屏直播的裁切铺满）
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, sourceWidth: 1080, sourceHeight: 1920 });
  assert.equal(p.landscapeLayout(), true);
  near(p.landscapePlayerWidth(), 800 * 2 / 3, 'landscape player keeps the 2:3 split');
  near(p.videoH(), 400 - p.landscapeAreaTop(), 'landscape media reaches the window bottom like the normal player');
  near(p.videoLeft(), p.landscapePlayerX() + (p.landscapePlayerWidth() - p.videoW()) / 2, 'video centred in the left player area');
  assert.ok(p.videoW() < p.landscapePlayerWidth(), 'portrait stream is letterboxed, not cropped');
  // 同一设置项（横屏默认播放区域 = 右侧）只换边，几何不变
  p.landscapePlaybackSide = 'right';
  near(p.landscapePlayerX(), 800 - p.landscapePlayerWidth() - p.landscapeInset(), 'right-hand side follows the shared setting');
  near(p.videoLeft(), p.landscapePlayerX() + (p.landscapePlayerWidth() - p.videoW()) / 2, 'video follows the swapped area');
  p.landscapePlaybackSide = 'left';
  // 分界限位：播放区至少 280，信息区至少 220
  near(geometry.exports.clampSplitWidth(800, 10), 280, 'minimum player width');
  near(geometry.exports.clampSplitWidth(800, 790), 800 - 220, 'panel keeps its minimum width');
  near(geometry.exports.clampSplitWidth(400, 10), 160, 'the minimum adapts to a narrow window');
  const customResize = geometry.exports.splitResize(800, 750, 200, 150);
  near(customResize.ratio, 650 / 800, 'resize respects custom minimum widths');
  near(customResize.expand, 100 / 150, 'expansion starts at the custom limit');
  near(geometry.exports.splitPrimaryWidth(800, customResize.ratio, customResize.expand, 200, 150),
    750, 'the custom width and expansion produce the dragged size');
  near(geometry.exports.splitSecondaryWidth(800, customResize.ratio, 10, 200, 150),
    130, 'the secondary pane retains its resting width while expanding');
  near(geometry.exports.splitHandleX(500, 300, false, 40), 480, 'custom handle width stays centered');
  // 全屏：连续展开量驱动几何（liveFullscreen 只是逻辑标志，不再瞬变）
  Object.assign(p, { liveFullscreen: true, landscapeExpand: 1 });
  near(p.landscapePlayerX(), 0, 'fullscreen player starts at the window edge');
  near(p.landscapePlayerWidth(), 800, 'fullscreen player fills the window');
  near(p.videoH(), 400, 'fullscreen media uses the whole height');
  near(p.videoLeft(), (800 - p.videoW()) / 2, 'fullscreen media centred');
  // 面板保持 resting 宽度，只靠 x 整块平移推出屏幕（普通页 ReferencePortrait 口径）
  assert.ok(Math.abs(p.landscapePanelWidth() - (800 - 800 * 2 / 3 - 2 * p.landscapeInset())) <= 1,
    'fullscreen panel keeps its resting width instead of collapsing');
  assert.ok(p.landscapePanelX() >= 800, 'fullscreen panel is translated off-screen (edge on the zero-margin layout)');
  // 面板宽度按整像素对齐，允许 1vp 误差
  assert.ok(Math.abs(p.landscapeMenuDockWidth() - (800 - 800 * 2 / 3 - 2 * p.landscapeInset())) <= 1,
    'menu keeps the resting panel width in fullscreen');
  near(p.landscapeDockPanelX(), 800 * 2 / 3 + p.landscapeInset(), 'menu stays on the panel side in fullscreen');
  p.landscapePlaybackSide = 'right';
  near(p.landscapeDockPanelX(), p.landscapeInset(), 'menu dock follows the swapped side');
  p.landscapePlaybackSide = 'left';
  Object.assign(p, { liveFullscreen: false, landscapeExpand: 0 });
  near(p.landscapeDockPanelX(), p.landscapePanelX(), 'split landscape keeps the live panel position');
  // 分栏菜单贴播放区右下（三点按钮也在播放区），全屏沿用收起态面板 dock
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, liveFullscreen: false,
    landscapeRatio: 2 / 3, landscapeExpand: 0, landscapePlaybackSide: 'left' });
  assert.ok(p.landscapeMenuDockWidth() <= 360, 'split menu is capped at 360vp');
  near(p.landscapeMenuDockX() + p.landscapeMenuDockWidth(),
    p.landscapePlayerX() + p.landscapePlayerWidth() - p.landscapeInset(), 'split menu docks to the player area right edge');
  p.liveFullscreen = true;
  near(p.landscapeMenuDockX(), p.landscapeDockPanelX(), 'fullscreen menu keeps the resting panel dock');
  p.liveFullscreen = false;
  // 参考外观 cardMargin=0：播放区、详情区、屏幕三者无缝，详情区贴窗口底边
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, cardMargin: 0,
    statusBarHeight: 28, realStatusBarHeight: 0, landscapeExpand: 0,
    landscapeRatio: 2 / 3, landscapePlaybackSide: 'left', landscapeResizeActive: false,
    landscapeResizePanelWidth: 0 });
  near(p.landscapeInset(), 0, 'reference appearance has no split margin');
  near(p.landscapePlayerX(), 0, 'player area hugs the left screen edge');
  near(p.landscapePanelX(), p.landscapePlayerWidth(), 'detail panel starts exactly where the player ends');
  assert.ok(Math.abs(p.landscapePanelX() + p.landscapePanelWidth() - 800) <= 1,
    'detail panel hugs the right screen edge (panel width is pixel-aligned)');
  near(p.landscapePanelTop() + p.landscapePanelHeight(), 400, 'detail panel reaches the window bottom');
  near(p.landscapeAreaTop() + p.landscapeAreaHeight(), 400, 'player area reaches the window bottom');
  // 拖动柄：32vp 触控区整体落在详情面板内，左右布局都成立
  near(geometry.exports.splitHandleX(p.landscapePanelX(), p.landscapePanelWidth(), false), p.landscapePanelX() - 16, 'resize handle touch target straddles the divider');
  p.landscapePlaybackSide = 'right';
  near(geometry.exports.splitHandleX(p.landscapePanelX(), p.landscapePanelWidth(), true),
    p.landscapePanelX() + p.landscapePanelWidth() - 16,
    'swapped handle touch target straddles the divider');
  p.landscapePlaybackSide = 'left';
  // 设置项仍生效：cardMargin 非零时两侧同步留边（普通页 safeCM 同口径）
  p.cardMargin = 12;
  near(p.landscapePlayerX(), 12, 'non-zero cardMargin still drives both sides');
  assert.ok(Math.abs(p.landscapePanelX() + p.landscapePanelWidth() - 788) <= 1,
    'panel right edge follows cardMargin');
  p.cardMargin = 0;
  // 拖动调节：容器宽度实时联动，面板右缘始终贴屏幕边（冻结容器会在右侧露一条大黑边）
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, cardMargin: 0,
    landscapeRatio: 0.6, landscapeExpand: 0, liveFullscreen: false, livePanelTab: 0 });
  const panelBefore = p.landscapePanelWidth();
  p.beginLandscapeResize();
  p.landscapeResize(60);
  near(p.landscapePanelX() + p.landscapePanelWidth(), 800,
    'dragging keeps the detail panel glued to the right screen edge');
  assert.ok(p.landscapePanelWidth() < panelBefore,
    'panel container shrinks as the player grows instead of staying frozen');
  near(p.landscapePanelContentWidth(), p.landscapePanelWidth() - 24,
    'intro card width follows the live container width');
  // 两个 tab 共用同一容器：拖动中切 tab 前后内容宽度完全一致，不会有比例突变
  p.livePanelTab = 1;
  near(p.landscapePanelContentWidth(), p.landscapePanelWidth() - 24,
    'switching to comments shows no width jump during a drag');
  p.livePanelTab = 0;
  Object.assign(p, { landscapeRatio: 2 / 3, landscapeExpand: 0 });
  // 进入分栏默认隐藏控件（纯净观看），竖屏信息层仍默认显示
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400 });
  assert.equal(p.defaultInformationVisible(), false, 'split landscape starts with player controls hidden');
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800 });
  assert.equal(p.defaultInformationVisible(), true, 'portrait keeps the information layer visible');
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400 });
  // 推荐 tab 只列其它直播间
  Object.assign(p, { rooms: [{ roomId: 1 }, { roomId: 2 }, { roomId: 3 }], roomId: 1 });
  assert.deepEqual(Array.from(p.recommendedRooms(), (r) => r.roomId), [2, 3],
    'recommend tab excludes the room currently playing');
  // 简介 tab 的直播推荐：竖屏直播那套取数，去重并排除当前房间
  Object.assign(p, { liveIntroRooms: [], liveIntroLoading: false, liveIntroHasMore: true,
    liveIntroPage: 1, liveIntroRoomIds: new Set(), areaId: 0, roomId: 1, disposed: false });
  assert.equal(typeof p.loadLiveIntroRooms, 'function', 'compiled intro loader is available');
  await p.loadLiveIntroRooms(true);
  assert.deepEqual(Array.from(p.introRooms(), (r) => r.roomId), [2, 3],
    'intro recommendations dedupe and exclude the current room');
  assert.equal(p.liveIntroPage, 2, 'intro feed advances its page');
  // 播放页跳转：推荐卡片 push 出新直播页，并继承当前分栏比例（普通页 onRelatedVideoClick 口径）
  Object.assign(p, { roomIds: [1, 2, 3], rooms: [{ roomId: 1 }, { roomId: 2 }, { roomId: 3 }],
    roomId: 1, areaId: 7, roomPage: 2, landscapeRatio: 0.6, disposed: false });
  p.selectRecommendedRoom({ roomId: 2 });
  assert.equal(ctx.lastPush.url, 'pages/LivePlayerPage', 'recommend card pushes a new player page');
  assert.equal(ctx.lastPush.params.roomId, 2);
  near(ctx.lastPush.params.landscapePlayerRatio, 0.6, 'new page inherits the current split ratio');
  assert.deepEqual(ctx.lastPush.params.roomIds, [1, 2, 3]);
  // 信息面板配色/圆角/指示器：深浅两套与 tab 动效插值
  Object.assign(p, { livePanelTabWidths: [28, 28], livePanelTabProgress: 0.5, isDarkMode: true });
  assert.equal(p.panelBgColor(), '#17181A');
  assert.equal(p.panelPrimaryColor(), '#E7E9EB');
  p.isDarkMode = false;
  assert.equal(p.panelBgColor(), '#FFFFFF', 'light theme uses the same white panel as the normal player');
  assert.equal(p.panelPrimaryColor(), '#18191C');
  near(p.panelTabIndicatorTravel(), 14 + 20 + 14, 'tab indicator follows the swiper progress');
  // 竖屏全屏按钮：请求横屏并标记旋转后落到横屏全屏
  delete p.applyRotationMode;
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800, landscapeExpand: 0, liveFullscreen: false,
    pendingLandscapeFullscreen: false, fullscreenExitTimer: -1, rotationMode: 'auto',
    fullscreenDeviceOrientation: { start() {}, stop() {}, returnLandscape: () => true },
    settleInformation() {} });
  const portraitOrientations = [];
  p.mw = { enableLandscapeMultiWindow: () => Promise.resolve(),
    disableLandscapeMultiWindow: () => Promise.resolve(),
    setPreferredOrientation: (o) => { portraitOrientations.push(o); return Promise.resolve(); } };
  p.enterPortraitFullscreen();
  assert.equal(p.pendingLandscapeFullscreen, true, 'portrait fullscreen waits for the rotation');
  assert.deepEqual(portraitOrientations, [1], 'portrait fullscreen requests landscape orientation');
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, landscapeExpand: 1, liveFullscreen: true });
  p.toggleLandscapeFullscreen();
  await new Promise(setImmediate);
  assert.deepEqual(portraitOrientations, [1, 4], 'portrait entry can return directly to landscape split');
  p.fullscreenDeviceOrientation.returnLandscape = () => false;
  Object.assign(p, { landscapeExpand: 1, liveFullscreen: true, liveFullscreenLocked: true });
  p.toggleLandscapeFullscreen();
  assert.equal(p.liveFullscreen, true, 'keep fullscreen until the portrait viewport arrives');
  await new Promise(setImmediate);
  assert.deepEqual(portraitOrientations, [1, 4, 4], 'portrait return also restores only the automatic policy');
  p.finishFullscreenExit();
  p.fullscreenDeviceOrientation.returnLandscape = () => true;
  // 全屏横向锁定：横屏分栏进全屏锁横屏，退出交还全局设置。
  let orientations = [];
  let rotationRestores = 0;
  p.mw = { enableLandscapeMultiWindow: () => Promise.resolve(),
    disableLandscapeMultiWindow: () => Promise.resolve(),
    setPreferredOrientation: (o) => { orientations.push(o); return Promise.resolve(); } };
  p.applyRotationMode = async () => { rotationRestores++; };
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, liveFullscreen: false,
    landscapeExpand: 0, pendingLandscapeFullscreen: false,
    liveFullscreenLocked: false, settleInformation() {} });
  p.toggleLandscapeFullscreen();
  assert.equal(p.liveFullscreenLocked, true, 'split-origin fullscreen locks the window landscape');
  assert.deepEqual(orientations, [1], 'entering fullscreen requests AUTO_ROTATION_LANDSCAPE');
  assert.equal(p.liveFullscreen, true, 'fullscreen flag settles after the expand animation');
  p.toggleLandscapeFullscreen();
  assert.equal(p.liveFullscreenLocked, false, 'leaving fullscreen releases the landscape lock');
  await new Promise(setImmediate);
  assert.equal(rotationRestores, 1, 'leaving fullscreen restores the global rotation setting');
  // 拖柄甩入全屏走同一把锁
  orientations = [];
  Object.assign(p, { liveFullscreen: false, landscapeExpand: 0, landscapeRatio: 2 / 3,
    liveFullscreenLocked: false });
  p.beginLandscapeResize();
  p.finishLandscapeResize(400);
  assert.equal(p.liveFullscreenLocked, true, 'drag-to-fullscreen also locks landscape');
  assert.deepEqual(orientations, [1], 'drag-to-fullscreen requests AUTO_ROTATION_LANDSCAPE');
  Object.assign(p, { liveFullscreen: false, landscapeExpand: 0, landscapeRatio: 2 / 3,
    liveFullscreenLocked: false });
  delete p.settleInformation;
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400 });
  // 分栏时顶部让整个系统状态栏（普通页 referenceSafeTop 口径），底部只留 12vp，全屏上下归零
  p.statusBarHeight = 28;
  near(p.landscapeAreaTop(), 28, 'split landscape clears the system status bar');
  near(p.landscapeBottomInset(), p.landscapeInset(), 'panel bottom inset follows cardMargin, not a status-bar-sized cut');
  near(p.landscapeAreaHeight(), 400 - 28, 'video surface reaches the window bottom');
  near(p.landscapePanelTop(), 28, 'panel starts right below the status bar');
  near(p.landscapePanelHeight(), 400 - 28 - p.landscapeInset(), 'panel reaches the window bottom when cardMargin is zero');
  p.realStatusBarHeight = 40;
  near(p.landscapeAreaTop(), 40, 'real status bar height wins over the landscape measurement');
  Object.assign(p, { liveFullscreen: true, landscapeExpand: 1 });
  near(p.landscapeAreaTop(), 0, 'fullscreen collapses the status bar inset');
  near(p.landscapeAreaHeight(), 400, 'fullscreen video owns the whole height');
  near(p.landscapeBottomInset(), p.landscapeInset(), 'panel bottom inset stays fixed across fullscreen');
  Object.assign(p, { liveFullscreen: false, landscapeExpand: 0 });
  p.realStatusBarHeight = 0;
  p.statusBarHeight = 0;
  // 分栏比例只属于页面实例：无参数重新进入重置 2/3，不同分栏页跳转通过路由参数继承
  near(p.initialLandscapeRatio(undefined), 2 / 3, 're-entering split layout resets to the default ratio');
  near(p.initialLandscapeRatio({}), 2 / 3, 'a fresh page without ratio params starts at 2/3');
  near(p.initialLandscapeRatio({ landscapePlayerRatio: 0.55 }), 0.55,
    'a jump between split pages inherits the current ratio');
  near(p.initialLandscapeRatio({ landscapePlayerRatio: 1.2 }), 2 / 3,
    'an out-of-range inherited ratio falls back to the default');
  near(p.initialLandscapeRatio({ landscapePlayerRatio: Number.NaN }), 2 / 3,
    'a non-numeric inherited ratio falls back to the default');
  // 分界柄：跟手改比例，拖过剩余距离的 62% 松手进入全屏
  Object.assign(p, { landscapeRatio: 2 / 3, landscapeExpand: 0, settleInformation() {} });
  p.beginLandscapeResize();
  p.landscapeResize(40);
  // 拖动位移会按整像素对齐，允许 1vp 误差
  assert.ok(Math.abs(p.landscapePlayerWidth() - (800 * 2 / 3 + 40)) <= 1, 'drag follows the divider');
  assert.equal(p.liveFullscreen, false, 'a short drag stays split');
  p.finishLandscapeResize(400);
  assert.equal(p.liveFullscreen, true, 'dragging past the threshold enters fullscreen');
  near(p.landscapePlayerWidth(), 800, 'fullscreen owns the geometry after release');
  p.liveFullscreen = false;
  Object.assign(p, { landscapeRatio: 2 / 3, landscapeExpand: 0, landscapePlaybackSide: 'right' });
  p.beginLandscapeResize();
  p.landscapeResize(-40);
  assert.ok(Math.abs(p.landscapePlayerWidth() - (800 * 2 / 3 + 40)) <= 1,
    'drag grows the player in the opposite direction when swapped');
  p.finishLandscapeResize(0, true);
  near(p.landscapeRatio, 2 / 3, 'cancelling a swapped drag restores the original ratio');
  near(p.landscapeExpand, 0, 'cancelling clears the expansion');
  p.landscapePlaybackSide = 'left';
  // 去掉上面的桩，后面要继续验真实的信息显隐
  delete p.settleInformation;
  // 控件全部搬到播放区：分栏与全屏的单击都切控件显隐，侧栏面板是常驻结构
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, liveFullscreen: false,
    informationVisible: true, informationProgress: 0, gm_: '', ml_: false, touchActive: true });
  p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, false, 'split landscape toggles player controls too');
  p.gm_ = ''; p.ml_ = false; p.touchActive = true; p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, true, 'another tap brings the player controls back');
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, liveFullscreen: true, informationVisible: true,
    informationProgress: 0, gm_: '', ml_: false, touchActive: true });
  p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, false, 'fullscreen landscape still toggles the overlay');
  p.liveFullscreen = false;
  // 返回键：先收菜单，再退全屏，最后才离开直播间（对齐普通横屏播放页）
  let leftRoom = false;
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, liveFullscreen: true, showPlaybackSettings: true,
    goBack() { leftRoom = true; } });
  assert.equal(p.onBackPress(), true, 'back closes the playback menu first');
  assert.equal(p.showPlaybackSettings, false);
  assert.equal(leftRoom, false);
  assert.equal(p.onBackPress(), true, 'back exits fullscreen before leaving the room');
  assert.equal(p.liveFullscreen, false, 'fullscreen back returns to the split landscape player');
  assert.equal(ctx.isFullscreenFlag, false, 'exiting fullscreen restores the system status bar immediately');
  assert.equal(p.onBackPress(), false, 'back leaves the room from the split layout');
  // 顶栏返回同一个口径：全屏先退回分栏，再返回才退出
  p.liveFullscreen = true;
  p.handleHeaderBack();
  assert.equal(p.liveFullscreen, false, 'header back leaves fullscreen first');
  assert.equal(leftRoom, false);
  p.handleHeaderBack();
  assert.equal(leftRoom, true, 'header back exits the room from the split layout');
  // 系统栏口径：横屏分栏显示系统状态栏（标志复位），全屏隐藏（置位，EntryAbility 回前台恢复读它）
  p.applySystemBars();
  assert.equal(ctx.isFullscreenFlag, false, 'split landscape shows the system status bar');
  p.liveFullscreen = true;
  p.applySystemBars();
  assert.equal(ctx.isFullscreenFlag, true, 'fullscreen hides the system status bar');
  p.liveFullscreen = false;
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800 });
  p.applySystemBars();
  assert.equal(ctx.isFullscreenFlag, true, 'portrait keeps the bars hidden');
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400 });
  Object.assign(p, { roomIds: [1, 2], rooms: [], roomId: 1, roomPage: 1, playGeneration: 0, roomOffset: 0,
    releasePlayer() {}, initPlayback: async () => {}, showBottomHintTemporarily() {} });
  await p.switchRoom(-1); assert.equal(p.roomId, 1);
  await p.switchRoom(1); assert.equal(p.roomId, 2);
  await p.switchRoom(1); assert.equal(p.roomId, 3);
  assert.deepEqual(Array.from(p.roomIds), [1, 2, 3]);
  assert.equal(p.roomPage, 2);
  await p.switchRoom(-1); assert.equal(p.roomId, 2);
  let finish;
  const viewport = new ctx.exports.Page();
  Object.assign(viewport, { viewportHeight: 800, roomOffset: -120, roomIds: [1, 2], rooms: [], roomId: 1,
    playGeneration: 0, releasePlayer() {}, initPlayback: async () => {},
    getUIContext: () => ({ animateTo: (options, action) => { action(); finish = options.onFinish; } }) });
  const switching = viewport.switchRoom(1);
  assert.equal(viewport.roomId, 1, 'keep outgoing room until its slide completes');
  assert.equal(viewport.roomOffset, -800);
  assert.equal(viewport.roomAnimating, true);
  finish(); await switching;
  assert.equal(viewport.roomId, 2);
  assert.equal(viewport.roomOffset, 0);
  Object.assign(p, { availableQualities: [{ qn: 30000, label: '杜比' }, { qn: 250, label: '超清' }] });
  ctx.getLiveQualityLabel = qn => `画质${qn}`;
  p.applyStreamQuality({ currentQn: 250, acceptQuality: [250, 80, 250] });
  assert.equal(p.currentQn, 250, 'show actual returned quality after server downgrade');
  assert.deepEqual(Array.from(p.availableQualities, q => q.qn), [250, 80]);
  assert.equal(p.availableQualities[0].label, '超清');
  // 横屏分栏：音量/亮度分界线取播放视口中线（800×400、比例 2/3 ⇒ 中线 ≈266.7），
  // 不是屏幕中线 400。播放区换到右侧时中线 ≈533.3。
  Object.assign(p, { viewportWidth: 800, viewportHeight: 400, screenW: 800, cardMargin: 0,
    landscapeExpand: 0, landscapeRatio: 2 / 3, landscapePlaybackSide: 'left',
    sx_: 300, sy_: 300, gm_: '', lt_: -1, la_: false, dtp_: false, lastDy: 0,
    vol: .5, bri: .5, setSystemVolume() {}, sampleLevelInput() {}, sGH() {}, fireHaptic() {} });
  p.onTM({ touches: [{ windowX: 300, windowY: 180 }] });
  assert.equal(p.gm_, 'volume', 'split boundary follows the playback viewport center');
  Object.assign(p, { landscapePlaybackSide: 'right', sx_: 450, sy_: 300, gm_: '', la_: false, dtp_: false });
  p.onTM({ touches: [{ windowX: 450, windowY: 180 }] });
  assert.equal(p.gm_, 'brightness');
  Object.assign(p, { viewportWidth: 400, viewportHeight: 800, sx_: 200, sy_: 400,
    gm_: '', lt_: -1, la_: false, dtp_: false, informationVisible: true,
    informationProgress: 0, informationDragStart: 0 });
  p.onTM({ touches: [{ windowX: 300, windowY: 405 }] });
  assert.equal(p.gm_, 'horizontal');
  assert.equal(p.informationProgress, 0, 'horizontal drag must not move or hide information');
  p.touchActive = true; p.onTU({});
  assert.equal(p.informationVisible, true);
  p.gm_ = ''; p.ml_ = false; p.touchActive = true; p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, false, 'single tap hides the entire information layer');
  assert.equal(p.informationProgress, 1);
  p.gm_ = ''; p.ml_ = false; p.touchActive = true; p.onTU({});
  await new Promise(resolve => setTimeout(resolve, 280));
  assert.equal(p.informationVisible, true, 'single tap restores information');
  assert.equal(p.informationProgress, 0);
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 280 }] });
  assert.equal(p.gm_, 'room');
  assert.equal(p.roomOffset, -120, 'room viewport follows the vertical drag');
  let direction;
  p.switchRoom = d => { direction = d; };
  p.touchActive = true; p.onTU({}); assert.equal(direction, 1);
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 435 }] });
  direction = undefined; p.touchActive = true; p.onTU({});
  assert.equal(direction, undefined, 'short motion must not change room');
  assert.equal(p.roomOffset, 0, 'short motion must spring back');
  p.gm_ = ''; p.ml_ = false;
  p.onTM({ touches: [{ windowX: 202, windowY: 280 }] });
  assert.equal(p.roomOffset, -120);
  p.onTC();
  assert.equal(p.roomOffset, 0, 'cancelled room swipe must spring back');
  console.log('Live player geometry, directional gestures, boundaries and list pagination passed');
}
main().catch(e => { console.error(e); process.exitCode = 1; });
// Exercise subscription order on the actual compiled mask predicate: the initial
// render has no player, but must still read the observed first-frame property.
const maskStart = source.indexOf('    private slotHasCurrentFrame(');
const maskEnd = source.indexOf('    private LiveVideoSlot(', maskStart);
assert.ok(maskStart >= 0 && maskEnd > maskStart);
const maskCtx = { exports: {} };
vm.runInNewContext(ts.transpileModule(`export class Mask { ${source.slice(maskStart, maskEnd)} }`, {}).outputText, maskCtx);
const mask = new maskCtx.exports.Mask();
let readyReads = 0, ready = false;
Object.assign(mask, { activeSlot: 0, av: null, previewAV: null, previewRoomId: 2, roomId: 1, roomIds: [1,2], roomSlideDirection: 1 });
Object.defineProperty(mask, 'activeFrameReady', { get() { readyReads++; return ready; } });
Object.defineProperty(mask, 'previewReady', { get() { readyReads++; return ready; } });
assert.equal(mask.slotHasCurrentFrame(0), false);
assert.equal(mask.slotHasCurrentFrame(1), false);
assert.equal(readyReads, 2, 'both initial masks must subscribe before players exist');
ready = true; mask.av = {}; mask.previewAV = {};
assert.equal(mask.slotHasCurrentFrame(0), true);
assert.equal(mask.slotHasCurrentFrame(1), true);
mask.previewRoomId = 3;
assert.equal(mask.slotHasCurrentFrame(1), false, 'a stale adjacent frame stays masked');
console.log('PASS: compiled live masks subscribe on initial render and only reveal the matching room frame.');
