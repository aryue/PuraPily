const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const read = (rel) => fs.readFileSync(path.join(root, rel), 'utf8');

const model = read('entry/src/main/ets/model/SkipSegment.ets');
const prefs = read('entry/src/main/ets/utils/SponsorBlockPrefs.ets');
const service = read('entry/src/main/ets/services/SponsorBlockService.ets');
const engine = read('entry/src/main/ets/services/SkipSegmentEngine.ets');
const page = read('entry/src/main/ets/pages/VideoPlayerPage.ets');
const controls = read('entry/src/main/ets/components/VideoControls.ets');
const api = read('entry/src/main/ets/api/BilibiliApi.ets');
const settings = read('entry/src/main/ets/pages/SponsorBlockPage.ets');
const profile = read('entry/src/main/ets/pages/ProfilePage.ets');
const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');
const routes = read('entry/src/main/resources/base/profile/main_pages.json');
const navShell = read('entry/src/main/ets/components/NavRouteShell.ets');

// 1) 分类与跳过方式：12 类、5 种模式；零长度片段是时间点标记。
for (const key of ['sponsor', 'selfpromo', 'exclusive_access', 'interaction', 'poi_highlight',
  'intro', 'outro', 'preview', 'padding', 'filler', 'music_offtopic', 'jumpscare']) {
  assert.ok(model.includes(`'${key}'`), `missing category ${key}`);
}
for (const mode of ['alwaysSkip', 'skipOnce', 'skipManual', 'showOnly', 'disable']) {
  assert.ok(model.includes(mode), `missing skip mode ${mode}`);
}
assert.match(model, /get isPoint\(\): boolean \{\s*return this\.startMs === this\.endMs;/,
  'zero-length segments must be treated as point markers');
assert.ok(model.includes('interface ClipInfoItem'), 'playurl clip_info_list type must exist');
assert.ok(model.includes('interface SponsorBlockItem'), 'SponsorBlock response type must exist');

// 2) 默认值与持久化键：总开关默认关、分类默认跳过一次、番剧默认跳过一次。
assert.ok(prefs.includes("DEFAULT_MODES: string = '111111111111'"), 'default modes must be all skip-once');
assert.ok(prefs.includes('https://www.bsbsb.top'), 'default SponsorBlock server missing');
assert.ok(prefs.includes("'sponsorBlockEnabled'") && prefs.includes("'sponsorBlockPgcMode'"),
  'settings keys must be read from AppStorage');
assert.ok(ability.includes("pref.getSync('sponsorBlockEnabled', false)") &&
  ability.includes("pref.getSync('sponsorBlockModes', '111111111111')") &&
  ability.includes("pref.getSync('sponsorBlockSeekInto', false)"),
  'EntryAbility must restore SponsorBlock settings on launch');

// 3) API：秒→毫秒、404 静默、无 B 站 Cookie 外泄。
assert.ok(service.includes('/api/skipSegments?videoID=') && service.includes('&cid=${cid}'),
  'skipSegments request must carry bvid + cid');
assert.ok(service.includes('Math.round(rawStart * 1000)') &&
  service.includes('Math.round(rawEnd * 1000)'),
  'API segments must be normalized from seconds to milliseconds');
assert.ok(service.includes('private static clone(list: SkipSegment[])') &&
  service.includes('return SponsorBlockService.clone(cached.segments);'),
  'cached segments must be cloned so skip state cannot leak across videos');
assert.match(service, /response\.responseCode === 404\) return \[\];/,
  '404 must be treated as no data');
assert.ok(!/['"]Cookie['"]\s*:/.test(service), 'SponsorBlock requests must not send Bilibili cookies');
assert.ok(service.includes("item.clipType === 'CLIP_TYPE_OP'") &&
  service.includes("item.clipType === 'CLIP_TYPE_ED'"),
  'Pgc clip_info_list must map OP/ED to intro/outro');

// 4) 执行器：前 1 秒规则、忽略区间、一次性/手动/总是、点标记不跳。
assert.ok(engine.includes('positionMs - this.lastCheckMs < 100'),
  'position checks must be throttled');
assert.ok(engine.includes('!seekInto && !startupCatchUp && positionMs - segment.startMs >= 1000'),
  'default behavior must only auto-skip within the first second of a segment');
assert.ok(engine.includes('segment.startMs === 0 && positionMs <= 5000'),
  'segments loaded just after start must still catch up a zero-start intro');
assert.ok(engine.includes('segment.endMs + 350'),
  'post-seek guard must extend past the segment end');
assert.ok(engine.includes('if (segment.isPoint) continue;'),
  'zero-length markers must never auto-skip');
assert.ok(engine.includes('case SkipMode.Always:') && engine.includes('case SkipMode.Once:') &&
  engine.includes('case SkipMode.Manual:'),
  'all three actionable skip modes must be handled');
assert.ok(engine.includes('promptedKey') && engine.includes('callbacks.prompt(segment)'),
  'manual mode must emit exactly one prompt per entry');

// 5) 播放页接入：身份切换重置、playurl 后灌入、timeUpdate 执行、拖动期间让位。
assert.match(page, /if \(cidChanged\) this\.resetSkipSegments_\(\);/,
  'cid changes must clear skip segments');
assert.ok(page.includes('this.applySkipSegments_(result, initGeneration);'),
  'playurl result must feed official + remote segments');
assert.ok(page.includes('this.evaluateSkipSegments_(t);'),
  'timeUpdate clock must drive the skip engine');
assert.ok(page.includes('!this.sk_ && !this.sliderDragging_ && !this.seekBarTouch_'),
  'skip engine must stand down while the user is seeking');
assert.ok(page.includes('skipMarksJson: $skipMarksJson_'),
  'VideoControls must receive progress-bar marks');
assert.ok(page.includes("this.skipPromptText_ = `跳过: ${SponsorBlockService.segmentLabel(segment)}`"),
  'manual skip prompt must show the category label');
assert.ok(page.includes('this.skipSegments_.skip(segment, this.skipCallbacks_());'),
  'tapping the manual prompt must skip the segment');

// 6) 进度条标记：Canvas 覆盖轨道中线、不拦截触摸。
assert.ok(controls.includes('@Link skipMarksJson: string;'),
  'VideoControls must link mark data as a string');
assert.match(controls, /Row\(\)[\s\S]{0,400}\.linearGradient\(this\.skipGradient\(\)\)[\s\S]{0,200}hitTestBehavior\(HitTestMode\.None\)/,
  'skip marks must never intercept slider touches');
assert.ok(controls.includes('const stops: Array<[string, number]>') &&
  controls.includes('this.markColor(token)') && controls.includes('skipGradient()'),
  'skip categories must be merged into one ordered gradient bar');

// 7) playurl 解析：UGC/PGC 两条路径都保留 clip_info_list。
assert.ok(api.includes('clip_info_list?: Array<ClipInfoItem>'), 'playurl data must type clip_info_list');
assert.ok(api.includes('clipInfoList?: Array<ClipInfoItem>'), 'PlayUrlResult must carry clipInfoList');
assert.ok((api.match(/clipInfoList: clipInfoList/g) || []).length >= 3,
  'all playurl branches must copy clipInfoList');

// 8) 设置入口与路由。
assert.ok(navShell.includes("this.routeName === 'SponsorBlockPage'"), 'SponsorBlockPage route missing');
assert.ok(!routes.includes('pages/SponsorBlockPage'), 'SponsorBlockPage must be a NavDestination, not a router page');
assert.ok(profile.includes("'setting-entry-sponsor-block'") &&
  profile.includes("url: 'pages/SponsorBlockPage'"),
  'playback settings must link to SponsorBlockPage');
assert.ok(settings.includes('启用社区片段') && settings.includes('分类跳过方式') &&
  settings.includes('番剧片头/片尾'),
  'settings page must expose global / pgc / per-category controls');
assert.ok(settings.includes("this.persistBoolean('sponsorBlockEnabled', value)") &&
  settings.includes("this.persistString('sponsorBlockModes', next)"),
  'settings page must persist changes');
assert.ok(settings.includes("GlassMaterial.create('menu', this.isDarkMode)") &&
  settings.includes('systemMaterial:'),
  'dropdown menus must use the same system material as the settings page');
assert.ok(settings.includes('.width(224).radius(24).font({ size: 16 })') &&
  settings.includes('menuItemDivider') && settings.includes('settings_menu_check_dark'),
  'dropdown menus must match settings geometry, divider and selected check');

console.log('PASS sponsor-block: 12 categories, 5 modes, API normalization, skip engine, playback wiring, progress marks and settings persistence.');
