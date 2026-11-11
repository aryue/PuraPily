// 播放页状态栏内容色回归：
// 浅色模式下全局状态栏内容色是黑字（Index 首页口径），播放页状态栏压在视频画面上，
// 必须自行强制白字；离开播放页恢复主题口径，否则浅色模式的普通页面变成看不见的白字。
// 对齐原版体验：过场动画开始没几帧就变色 —— 恢复挂在 onPageHide（pop 后路由栈已指向
// 目标页，直传 this.mw 一跳下发），而不是 aboutToDisappear（转场后半段才落地）。
// 同路由多层播放页（相关推荐 push 下层实例）退出时不得把下层恢复成黑字：存活计数门控。
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const read = (p) => fs.readFileSync(path.join(__dirname, p), 'utf8').replace(/\r\n/g, '\n');
const statusBar = read('../entry/src/main/ets/utils/StatusBarUtils.ets');
const player = read('../entry/src/main/ets/pages/VideoPlayerPage.ets');
const live = read('../entry/src/main/ets/pages/LivePlayerPage.ets');

// 1) StatusBarUtils：播放页口径恒白（透明背景），恢复口径跟主题；两者支持直传窗口。
const setPlayerAt = statusBar.indexOf('  static async setPlayerStatusBarContent(');
assert.ok(setPlayerAt > 0, 'StatusBarUtils must expose setPlayerStatusBarContent');
const setPlayerBody = statusBar.slice(setPlayerAt, statusBar.indexOf('}', statusBar.indexOf('setWindowSystemBarProperties', setPlayerAt)));
assert.ok(/statusBarColor:\s*'#00000000'/.test(setPlayerBody), 'player status bar background stays transparent');
assert.ok(/statusBarContentColor:\s*'#FFFFFF'/.test(setPlayerBody),
  'player status bar content must be constant white (over video, theme-independent)');
assert.ok(/win\?:\s*window\.Window/.test(setPlayerBody), 'setPlayerStatusBarContent accepts a direct window');
const restoreAt = statusBar.indexOf('  static async restoreThemeStatusBarContent(');
assert.ok(restoreAt > 0, 'StatusBarUtils must expose restoreThemeStatusBarContent');
const restoreBody = statusBar.slice(restoreAt, statusBar.indexOf('\n  }', restoreAt));
assert.ok(/dark \? '#FFFFFF' : '#000000'/.test(restoreBody),
  'restore must follow the theme (light=black, dark=white)');
assert.ok(/win\?:\s*window\.Window/.test(restoreBody), 'restoreThemeStatusBarContent accepts a direct window');

// 2) VideoPlayerPage：onPageShow 同步强制白字（与 manageSB 同拍，转场启动帧内发出窗口属性，
//    IPC 落地在首帧后 1~3 帧）。initW 与 aboutToAppear 链都跑在转场首帧之前，禁止在那里下发
//    ——首页满屏时就变色；也不能延迟中段下发——avoidArea 重算会顿掉转场一拍。
const onPageShowAt = player.indexOf('  onPageShow(): void {');
const onPageShowSlice = player.slice(onPageShowAt, player.indexOf('aboutToDisappear', onPageShowAt));
assert.ok(/manageSB\(force=true\)[\s\S]{0,600}StatusBarUtils\.setPlayerStatusBarContent\(/.test(onPageShowSlice) &&
  /this\.manageSB\(true\);[\s\S]{0,600}StatusBarUtils\.setPlayerStatusBarContent\(/.test(onPageShowSlice),
  'onPageShow must call setPlayerStatusBarContent synchronously, right after manageSB');
assert.ok(/setPlayerStatusBarContent\([\s\S]{0,200}\);/.test(onPageShowSlice) &&
  !/setTimeout\(\(\) => \{[\s\S]{0,200}setPlayerStatusBarContent\(/.test(onPageShowSlice),
  'onPageShow white-content write must not be deferred into the middle of the transition');
const initWAt = player.indexOf('  async initW() {');
const initWSlice = player.slice(initWAt, initWAt + 1600);
assert.ok(!/setPlayerStatusBarContent\(/.test(initWSlice),
  'initW runs before the transition first frame; it must not write status bar content');

// 3) VideoPlayerPage.onPageHide：转场第一拍就恢复/让位 —— 栈顶是普通页面立即恢复主题口径；
//    栈顶还是播放页（VideoPlayerPage/LivePlayerPage）则不下发，交给对方 onPageShow 白字。
const onPageHideAt = player.indexOf('  onPageHide(): void {');
const onPageHideSlice = player.slice(onPageHideAt, onPageHideAt + 2200);
assert.ok(/topOnHide !== 'pages\/VideoPlayerPage' && topOnHide !== 'pages\/LivePlayerPage'/.test(onPageHideSlice),
  'onPageHide must early-restore theme color only when the revealed page is NOT a player page');
assert.ok(/restoreThemeStatusBarContent\(/.test(onPageHideSlice) &&
  onPageHideSlice.indexOf('restoreThemeStatusBarContent(') < onPageHideSlice.indexOf('if (!this.av)'),
  'early restore must run before the playback early-returns in onPageHide');

// 4) VideoPlayerPage.restoreS：存活计数门控 —— 还有下层播放页活着就回写白字（最后写窗口的是白），
//    归零才恢复主题口径；且先减计数再下发。
const restoreSAt = player.indexOf('  private async restoreS() {');
const restoreSSlice = player.slice(restoreSAt, restoreSAt + 1800);
assert.ok(/immersivePlayerAliveCount/.test(restoreSSlice), 'restoreS must consult the alive-player counter');
const decAt = restoreSSlice.indexOf("AppStorage.setOrCreate('immersivePlayerAliveCount', remaining)");
assert.ok(decAt > 0 &&
  decAt < restoreSSlice.indexOf('setPlayerStatusBarContent(') &&
  decAt < restoreSSlice.indexOf('restoreThemeStatusBarContent('),
  'counter must be decremented before either content write');
assert.ok(/if \(remaining > 0\) \{[\s\S]{0,400}setPlayerStatusBarContent[\s\S]{0,400}\} else \{[\s\S]{0,400}restoreThemeStatusBarContent/,
  'remaining players must re-assert white; zero remaining restores the theme color');

// 5) VideoPlayerPage.aboutToAppear：进入即计数 +1。
const appearAt = player.indexOf('  async aboutToAppear() {');
const appearSlice = player.slice(appearAt, appearAt + 800);
assert.ok(/immersivePlayerAliveCount/.test(appearSlice) && /\+ 1\)/.test(appearSlice),
  'aboutToAppear must increment the alive-player counter');

// 6) LivePlayerPage：applySystemBars 不下发内容色（首次进入经 aboutToAppear 调用，跑在转场
//    首帧之前）；onPageShow 与 applySystemBars 同拍同步下发白字；aboutToDisappear 计数门控；
//    onPageHide 同样提前恢复；aboutToAppear 计数 +1。
const applySBAt = live.indexOf('  private applySystemBars(');
const applySBSlice = live.slice(applySBAt, applySBAt + 900);
assert.ok(!/setPlayerStatusBarContent\(/.test(applySBSlice),
  'applySystemBars is reached from aboutToAppear before the transition first frame; no content write');

const liveShowAt = live.indexOf('  onPageShow(): void {');
const liveShowSlice = live.slice(liveShowAt, liveShowAt + 1600);
assert.ok(/applySystemBars\(\);[\s\S]{0,600}StatusBarUtils\.setPlayerStatusBarContent\(/.test(liveShowSlice),
  'live onPageShow must call setPlayerStatusBarContent synchronously, right after applySystemBars');

const liveDisappearAt = live.indexOf('  aboutToDisappear() {');
const liveDisappearSlice = live.slice(liveDisappearAt, liveDisappearAt + 1800);
assert.ok(/immersivePlayerAliveCount/.test(liveDisappearSlice), 'live aboutToDisappear must gate on the alive counter');
const liveDec = liveDisappearSlice.indexOf("AppStorage.setOrCreate('immersivePlayerAliveCount', remaining)");
assert.ok(liveDec > 0 && liveDec < liveDisappearSlice.indexOf('setPlayerStatusBarContent(') &&
  liveDec < liveDisappearSlice.indexOf('restoreThemeStatusBarContent('),
  'live counter must be decremented before either content write');
assert.ok(/if \(remaining > 0\) \{[\s\S]{0,300}setPlayerStatusBarContent[\s\S]{0,300}\} else \{[\s\S]{0,300}restoreThemeStatusBarContent/,
  'live remaining>0 must re-assert white; zero remaining restores the theme color');

const liveHideAt = live.indexOf('  onPageHide(): void {');
const liveHideSlice = live.slice(liveHideAt, liveHideAt + 1400);
assert.ok(/top !== 'pages\/LivePlayerPage' && top !== 'pages\/VideoPlayerPage'/.test(liveHideSlice) &&
  /restoreThemeStatusBarContent\(/.test(liveHideSlice),
  'live onPageHide must early-restore theme color only when the revealed page is NOT a player page');

const liveAppearAt = live.indexOf('  aboutToAppear() {');
const liveAppearSlice = live.slice(liveAppearAt, liveAppearAt + 800);
assert.ok(/immersivePlayerAliveCount/.test(liveAppearSlice) && /\+ 1\)/.test(liveAppearSlice),
  'live aboutToAppear must increment the alive-player counter');

// 7) 播放页不得再引入按主题切换的旧口径（深浅色都压视频，恒白才对）。
assert.ok(!/updateStatusBarColor\(context,\s*this\.isDarkMode\)/.test(player) ||
  player.indexOf('setPlayerStatusBarContent(') < player.indexOf('updateStatusBarColor(context, this.isDarkMode)'),
  'player pages must not fall back to theme-based content while visible');

console.log('PASS: player status bar content — white over video, first-frame restore on exit, alive-count gate for stacked players');
