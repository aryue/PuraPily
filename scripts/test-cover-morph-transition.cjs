const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const morph = read('entry/src/main/ets/services/HomeCardMorph.ets');
const home = read('entry/src/main/ets/pages/HomePage.ets');
const card = read('entry/src/main/ets/components/VideoCardComponent.ets');
const index = read('entry/src/main/ets/pages/Index.ets');
const page = read('entry/src/main/ets/pages/VideoPlayerPage.ets');
const ability = read('entry/src/main/ets/entryability/EntryAbility.ets');

// ── 1) 不用 sharedTransition，封面矩形必须在布局后自行插值 ─────────────────────
assert.match(morph, /static readonly ID_PREFIX: string = 'home-cover-morph-';/,
  'id 前缀必须固定，两端引用同一个常量');
assert.match(morph, /static cardCoverId\(itemId: string\): string \{\s*\n\s*return 'home-card-cover-' \+ itemId;/,
  '卡片封面节点 id 必须由服务层统一生成');
assert.match(card, /private coverMorphId\(\): string \{\s*\n\s*return HomeCardMorph\.cardCoverId\(this\.item\.id\);/,
  '卡片封面必须带可查询的 id');
assert.match(card, /\.id\(this\.coverMorphId\(\)\)/, '封面节点必须挂上该 id');
assert.match(card, /private coverMorphImageId\(\): string \{\s*\n\s*return `home-card-cover-image-\$\{this\.item\.id\}`;/, 
  '封面 Image 必须有独立 id 供同步快照');
assert.match(card, /\.id\(this\.coverMorphImageId\(\)\)/, 'Image 节点必须挂封面图 id');
assert.ok(!/\.sharedTransition\(/.test(card), '卡片封面不得用 sharedTransition（目标矩形会取到 1x1）');
assert.ok(!/\.sharedTransition\(/.test(page), '播放页不得用 sharedTransition');

// ── 2) 跨页交接：只交封面、矩形与角标，不再交截图底板 ──────────────────────────
assert.match(morph, /static readonly DURATION: number = 380;/, '飞行路径时长必须是 380ms');
assert.match(morph, /static readonly RETURN_DURATION: number = 380;/, '同方向返回可见收缩必须是 380ms');
assert.match(morph, /static readonly RETURN_HOLD_MS: number = 440;/, '退出转场必须覆盖返回收缩与收尾');
assert.match(morph, /static readonly ROTATED_RETURN_MIN_MS: number = 250;/, '换方向返回不得低于平台 250ms 下限');
assert.match(morph, /static readonly ROTATED_RETURN_FALLBACK_MS: number = 250;/, '推拉兜底也必须满足 250ms 下限');
assert.match(morph, /static readonly ASPECT_PROGRESS: number = 0\.42;/, 
  '卡片裁切画幅必须在飞行前 42% 内变成视频真实画幅');
assert.match(morph, /static readonly HANDOFF_SCALE: number = 0\.88;/, 
  '路径终点必须存在（只决定飞向哪里，不决定切换时刻）');
assert.match(morph, /static readonly LIVE_BACKDROP_MS: number = 2500;/, 
  '首页 Exit 必须保留足够长的 live 下层，覆盖封面解码等待');
assert.match(morph, /static enabled\(\): boolean \{\s*\n\s*return AppStorage\.get<boolean>\(HomeCardMorph\.SWITCH_KEY\) === true;/, 
  '开关必须从 AppStorage 实时读取');
assert.match(morph, /static primeExitInstant\(\): boolean \{\s*\n\s*HomeCardMorph\.exitInstant = HomeCardMorph\.enabled\(\);/, 
  '首页转场快照必须在字段初始化时落定');
assert.match(morph, /HomeCardMorph\.armed = true;\s*\n\s*HomeCardMorph\.id = id;/, 
  'arm 必须同时置 armed / id');
assert.ok(!/static enterInstant/.test(morph), '不得保留进程级 enterInstant（会被相关推荐页继承）');
assert.match(morph, /playCount: number, durationSec: number, coverPixel\?: image\.PixelMap\): boolean \{/, 
  'arm 必须接收点击时同步截下的封面快照');
assert.match(morph, /static coverPixel: image\.PixelMap \| undefined = undefined;/, 
  '服务层必须跨页携带封面 PixelMap');
assert.match(morph, /static takeCoverPixel\(\): image\.PixelMap \| undefined/, 
  '播放页必须能取走 PixelMap 所有权');
assert.ok(!/takeBase|dropBase|static base/.test(morph), '服务层不得保留截图底板交接');
assert.match(morph, /HomeCardMorph\.playCount = playCount;\s*\n\s*HomeCardMorph\.durationSec = durationSec;/, 
  '角标数据必须跨页交接');
assert.match(morph, /static windowW: number = 0;/, '必须记录首页可视区宽度');
assert.match(morph, /static armedAt: number = 0;/, 'arm 必须记录时刻，才能作废残留');

// ── 3) 首页：同步取矩形 + 直接跳转，不再等待截图 ─────────────────────────────
assert.match(index, /\.id\('home-morph-root'\)/, '首页根节点必须挂可视区测量 id');
assert.match(home, /getRectangleById\('home-morph-root'\)/, '首页尺寸必须读取真实根节点矩形');
assert.match(home, /getComponentSnapshot\(\)\s*\n?\s*\.getSync\(`home-card-cover-image-\$\{item\.id\}`\)/, 
  '首页点击必须同步快照已渲染的封面图');
assert.ok(!/captureMorphBase|home-morph-snapshot/.test(home), '首页不得再维护整页截图底板');
assert.match(home, /const info = utils\.getRectangleById\(HomeCardMorph\.cardCoverId\(item\.id\)\);/,
  '点击时必须取封面窗口矩形');
assert.match(home, /if \(x > winW - margin \|\| y > winH - margin \|\| x \+ w < margin \|\| y \+ h < margin\) \{/, 
  '卡片矩形必须校验与可视区有交集');
assert.match(home, /const rect: HomeCardMorphRect \| undefined =\s*\n\s*HomeCardMorph\.enabled\(\) \? this\.readCardCoverRect\(item\) : undefined;/, 
  '矩形必须在点击同步段取');
assert.match(home, /this\.armHomeCardMorph\(item, rect, coverPixel\);/, 
  '取到矩形和快照后必须同步登记');
assert.match(home, /this\.openVideoPage\(item\);/, '登记后必须跳转');
assert.ok(!/const timer = setTimeout|const use = \(base/.test(home), '不得保留截图竞态逻辑');
assert.match(home, /private openVideoPage\(item: RecommendItem\)/, '跳转参数与原逻辑必须保留');

// ── 4) 播放页：布局后插值，首帧直接由 live 叠层/飞行封面承接 ────────────────────
assert.ok(!/coverMorphBase|morphBaseScale|HomeCardMorph\.takeBase\(\)/.test(page),
  '播放页不得再维护截图底板');
assert.match(page, /private startCoverMorph\(\): void \{[\s\S]{0,2200}?this\.coverMorphTo = this\.coverMorphHandoffRect\(\);/, 
  '飞行路径终点必须在布局完成后取');
assert.ok(!/coverMorphEnterDone/.test(page),
  '切换不得再等飞行 onFinish（固定飞满 380ms 才切就是用户反馈的「飞那么远」）');
assert.match(page, /private trySwitchCoverMorph\(\): void \{[\s\S]{0,400}?if \(!this\.coverMorphCoverReady \|\| !this\.coverMorphStarted\) return;[\s\S]{0,120}?this\.switchCoverMorphToPlayer\(\);/, 
  '封面就绪后切换：不等首帧、不等飞行跑完');
assert.match(page, /this\.trySwitchCoverMorph\(\);[\s\S]{0,700}?this\.coverMorphProgress = 1;/, 
  '必须先切再起 progress，避免主线程延迟时切换帧取到手递矩形');
assert.match(page, /private switchCoverMorphToPlayer\(\): void \{[\s\S]{0,600}?this\.coverMorphSwitchRect = \{ x: q\.x, y: q\.y, width: q\.width, height: q\.height, radius: q\.radius \};/, 
  '切换帧必须冻结当前封面矩形，播放页几何从这一帧接过');
assert.match(page, /private coverMorphFlyRect\(\): HomeCardMorphRect \{[\s\S]{0,900}?const aspect = Math\.max\(0\.05, cardAspect \+ \(mediaAspect - cardAspect\) \* a\);/, 
  '封面飞行矩形必须按 ASPECT_DURATION 变成视频真实画幅');
assert.match(page, /private coverMorphLayerRect\(\): HomeCardMorphRect \{[\s\S]{0,900}?if \(!this\.coverMorphSwitching\) return this\.coverMorphFlyRect\(\);/, 
  '切换前封面层必须用飞行矩形');
assert.match(page, /private morphWinFrom: HomeCardMorphRect[\s\S]{0,240}?private morphWinTo: HomeCardMorphRect/, 
  '窗口必须有起止矩形');
assert.match(page, /private morphWinW\(\): number \{[\s\S]{0,500}?q\.width \+ \(this\.morphPageW - q\.width\) \* this\.coverMorphReveal/, 
  '进入段窗口宽度必须严格从卡片宽展开到整页宽');
assert.match(page, /private morphWinH\(\): number \{[\s\S]{0,500}?q\.height \+ \(this\.morphPageH - q\.height\) \* this\.coverMorphReveal/, 
  '进入段窗口高度必须严格从卡片高展开到整页高');
assert.match(page, /const s0 = this\.morphHandoffScale\(\);[\s\S]{0,160}?return s0 \+ \(1 - s0\) \* this\.coverMorphReveal;/, 
  '进入段页面缩放必须从切换帧的动态 s0 放大到 1');
assert.match(page, /private morphHandoffScale\(\): number \{[\s\S]{0,300}?Math\.max\(1, q\.width\) \/ Math\.max\(1, this\.morphPageW\)/, 
  '切换帧页面缩放必须让整页宽度与卡片同宽');
assert.match(page, /return this\.coverMorphSwitchRect\.x \* \(1 - this\.coverMorphReveal\);/, 
  '进入段窗口横向原点必须从卡片位置收拢到 0');
assert.match(page, /return this\.coverMorphSwitchRect\.y \* \(1 - this\.coverMorphReveal\);/, 
  '进入段窗口纵向原点必须从卡片位置收拢到 0');
assert.match(page, /private morphContentPosX\(\): number \{[\s\S]{0,400}?this\.morphHandoffWinX\(\) - q\.x/, 
  '内容水平偏移必须按切换帧视频居中量收拢到 0');
assert.match(page, /private morphContentPosY\(\): number \{[\s\S]{0,400}?this\.morphHandoffWinY\(\) - q\.y/, 
  '内容纵向偏移必须按切换帧视频居中量收拢到 0');
assert.match(page, /private coverMorphHandoffRect\(\): HomeCardMorphRect \{/, 
  '必须有手递矩形计算');
assert.match(page, /x: winX \+ media\.x \* s,/, '手递矩形 x 必须按页面缩放后的画面位置');
assert.match(page, /width: Math\.max\(1, media\.width \* s\),/, '手递矩形宽必须 = 最终画面宽 × s0');
assert.match(page, /height: Math\.max\(1, media\.height \* s\),/, '手递矩形高必须 = 最终画面高 × s0');
assert.match(page, /private morphPageW: number = 0;\s*\n\s*private morphPageH: number = 0;/, 
  '内容必须先按整页尺寸排版');
assert.match(page, /if \(this\.cw > 1 && this\.ch > 1 &&\s*\n\s*\(Math\.abs\(this\.cw - this\.morphPageW\) > 1 \|\| Math\.abs\(this\.ch - this\.morphPageH\) > 1\)\) \{/, 
  '布局后必须用 cw/ch 修正整页尺寸');
assert.match(page, /private snapMorphToFullPage\(\): void \{[\s\S]{0,300}?this\.coverMorphProgress = 1;/, 
  '必须有几何归位方法');
assert.match(page, /\.width\(this\.coverMorphActive \? this\.morphWinW\(\) : '100%'\)/, 
  '窗口宽度必须可补间');
assert.match(page, /\.width\(this\.coverMorphActive \? this\.morphPageW : '100%'\)/, 
  '内容宽度必须固定为整页');
assert.match(page, /\.opacity\(this\.morphContentOpacity\(\)\)/, '内容层必须由统一 opacity 控制');
assert.match(page, /private morphContentOpacity\(\): number \{[\s\S]{0,400}?if \(!this\.coverMorphCoverReady\) return 0;[\s\S]{0,200}?return this\.coverMorphSwitching \? 1 : 0;/, 
  '封面未解码/首帧未切前播放页内容必须隐藏；切换帧一次性不透明');
assert.match(page, /@State coverMorphPosterOpacity: number = 0;/, 
  '首帧未到时视频区必须有封面替身，不能露黑板/加载页');
assert.match(page, /this\.coverMorphPosterOpacity = !this\.coverMorphDirectFrame && this\.waitingForFirstFrame \? 1 : 0;/, 
  '快照直出首帧时不得再铺页内 poster');
assert.match(page, /private coverMorphPixel: image\.PixelMap \| undefined = undefined;/, 
  '播放页必须持有点击时快照');
assert.match(page, /this\.coverMorphPixel = HomeCardMorph\.takeCoverPixel\(\);/, 
  '播放页必须取走快照 PixelMap');
assert.match(page, /Image\(this\.coverMorphPixel\)/, '封面层必须优先渲染 PixelMap 快照');
assert.match(page, /if \(this\.coverMorphDirectFrame && this\.waitingForFirstFrame\) \{[\s\S]{0,240}?snapshot holds until first frame/, 
  '首帧未到必须保持快照，不能退回页内封面');
assert.match(page, /if \(this\.coverMorphDirectFrame && this\.coverMorphSwitching\) \{[\s\S]{0,160}?scheduleCoverMorphFirstFrameFade\(\)/, 
  '首帧提前就绪时必须调度快照提前淡出');
assert.match(page, /private scheduleCoverMorphFirstFrameFade\(\): void \{[\s\S]{0,700}?this\.fadeCoverMorphOverlay\(\);/, 
  '首帧可以在窗口移动途中交接，不能等 reveal 完全结束才淡');
assert.ok(!/coverMorphReveal >= 0\.75/.test(page),
  '不得再用 coverMorphReveal >= 0.75 判断展开进度（状态值在动画开始时就是 1）');
assert.match(page, /private finishCoverMorphEnter\(\): void \{[\s\S]{0,500}?if \(!this\.coverMorphRevealDone\)[\s\S]{0,180}?return;[\s\S]{0,500}?this\.coverMorphActive = false;/, 
  '封面可提前淡，但窗口 active 必须等 reveal 真实 onFinish 后才收口');
assert.match(page, /if \(this\.coverMorphPosterOpacity > 0 && this\.coverMorphCover\.length > 0\) \{[\s\S]{0,400}?Image\(this\.coverMorphCover\)/, 
  '播放页视频区必须渲染与飞行封面同源的替身图');
assert.match(page, /this\.coverMorphPosterOpacity <= 0\.01 && !\(this\.coverMorphDirectFrame && this\.coverMorphActive\) &&[\s\S]{0,80}?!this\.err/, 
  '封面替身在场时必须收起「正在加载视频…」加载页');
assert.match(page, /Image\(this\.coverMorphCover\)[\s\S]{0,180}?\.syncLoad\(true\)/, 
  '封面必须同步加载，避免首帧空白');
assert.match(page, /if \(!this\.coverMorphCoverReady\) \{\s*\n\s*this\.coverMorphCoverReady = true;\s*\n\s*logInfo\('\[HomeCardMorph\] cover ready, start flight'\);/, 
  '封面解码完成必须触发飞行');
assert.match(page, /this\.coverMorphCoverPaintable = true;[\s\S]{0,180}?if \(!this\.coverMorphCoverReady\)/, 
  '封面解码完成必须在同一拍打开图片上屏门控');
assert.match(page, /\.onComplete\(\(\) => \{[\s\S]{0,500}?setTimeout\(\(\) => this\.tryStartCoverMorph\(\), 16\);/, 
  '封面必须先上屏一帧，下一帧再切不透明，避免角标先丢失再出现');
assert.match(page, /\.opacity\(this\.coverMorphCoverPaintable \? 1 : 0\.01\)/, 
  '封面 Image 必须与角标共用上屏门控，不能先于角标自己绘制');
assert.match(page, /private tryStartCoverMorph\(\): void \{[\s\S]{0,400}?if \(!this\.coverMorphCoverReady\) return;[\s\S]{0,200}?this\.startCoverMorph\(\);/, 
  '飞行必须等封面就绪再启动');
assert.match(page, /this\.coverMorphStartFallbackTimer = setTimeout\([\s\S]{0,500}?if \(this\.coverMorphCoverReady\) \{[\s\S]{0,200}?this\.tryStartCoverMorph\(\)[\s\S]{0,500}?logWarn\('\[HomeCardMorph\] cover decode timeout, abort morph'\);/, 
  '封面超时必须放弃转场，不能假装 ready 飞一块透明区域');
assert.match(page, /private coverMorphBadgeOpacity\(\): number \{\s*\n\s*return Math\.max\(0, Math\.min\(1, 1 - this\.coverMorphProgress \/ 0\.35\)\);/, 
  '角标必须只保留一次随 progress 的淡出，不能靠整层显隐拖到收尾');
assert.match(page, /\.opacity\(this\.coverMorphCoverPaintable \? this\.coverMorphBadgeOpacity\(\) : 0\)/, 
  '角标必须与封面 Image 同一帧上屏');
assert.match(page, /Image\(\$r\('app\.media\.ref_play'\)\)\.width\(14\)\.height\(14\)\.fillColor\('#FFFFFF'\)/, 
  '封面层必须复刻播放量图标');
assert.match(page, /colors: \[\['#00000000', 0\], \['#99000000', 1\]\]/, 
  '封面层必须复刻底部渐变');
const coverLayer = page.slice(page.indexOf('HomeCoverMorphLayer()'), page.indexOf('@State isBiliLoggedIn'));
assert.match(coverLayer, /coverMorphLayerRect\(\)\.x - this\.morphWinX\(\)/, 
  '封面层位置必须换算成相对裁剪窗口的局部坐标');
assert.match(coverLayer, /\.width\(this\.morphWinW\(\)\)[\s\S]{0,240}?\.clip\(true\)/, 
  '封面层必须裁剪到当前 morph 窗口内，不能盖住窗口外真实首页');

// ── 5) 返回：先 back 让首页 live 激活，再由非零 Exit 撑住收缩 ─────────────────
assert.match(page, /if \(this\.fs \|\| this\.referenceFeed\) return false;/,
  '全屏/连刷不能接管返回；横屏同方向必须允许接管');
assert.ok(!/if \(this\.fs \|\| this\.isLs \|\| this\.referenceFeed\) return false;/.test(page),
  '横屏不得被静态排除');
assert.match(page, /const rotatedReturn = !this\.coverMorphOrientationStable\(\);/,
  '返回前必须区分同方向与中途换方向');
assert.match(page, /private startCoverMorphRotatedReturn\(\): void \{[\s\S]{0,1600}?HomeCardMorph\.homeLayoutReadyGeneration > this\.coverMorphRotatedReadyBefore[\s\S]{0,1200}?const next = this\.readCoverMorphCardRect\(\);/,
  '换方向返回必须先等首页完成新方向布局，再读取同一张卡片的真实落点');
assert.match(page, /private readCoverMorphCardRect\(\): HomeCardMorphRect \| undefined \{[\s\S]{0,500}?HomeCardMorph\.cardElementId/,
  '返回落点必须按首页卡片节点 id 实时读取');
const followBlock = page.slice(page.indexOf('  private startCoverMorphReturnFollow()'),
  page.indexOf('  private beginReturnCoverMorph('));
assert.match(followBlock, /const next = this\.readCoverMorphCardRect\(\);/,
  '首页滑动时返回落点必须逐帧读取卡片');
assert.match(followBlock, /this\.applyCoverMorphReturnTarget\(next\);/,
  '首页滑动时返回落点必须写回同一个目标状态');
assert.match(home, /this\.afterHomeLayout\(\(\) => \{\s*\n\s*HomeCardMorph\.markHomeLayoutReady\(\);/,
  '首页必须在返回布局完成后发出可复用信号');
assert.match(morph, /static markHomeLayoutReady\(\): void \{\s*\n\s*HomeCardMorph\.homeLayoutReadyGeneration\+\+;/,
  '布局完成信号必须使用代数，不能只置布尔量');
assert.match(page, /const dur = this\.da \? 0 : HomeCardMorph\.RETURN_DURATION;/,
  '返回收缩时长口径必须保留');
const returnBlock = page.slice(page.indexOf('  private beginReturnCoverMorph('),
  page.indexOf('  private disposeCoverMorph('));
assert.match(returnBlock, /this\.startCoverMorphRotatedReturn\(\);[\s\S]{0,200}?return;[\s\S]{0,300}?router\.back\([\s\S]{0,180}?this\.startCoverMorphReturnFollow\(\);[\s\S]{0,160}?animateTo\(/,
  '撤回打断后必须恢复先 back、再收缩的路径');
assert.match(returnBlock, /this\.coverMorphProgress = 0;/, '返回只能补间 progress');
assert.match(returnBlock, /const quickReturn = this\.coverMorphActive && measuredP < 0\.999;/, 
  '进入中途返回必须识别为 quick return');
assert.match(returnBlock, /const startP = quickReturn \? measuredP : 1;/, 
  'quick return 必须从实测窗口进度反缩，不能重置到整页');
assert.match(returnBlock, /const firstFrameMissing = this\.waitingForFirstFrame \|\| this\.coverMorphPosterOpacity > 0\.01;/, 
  '返回必须先判断首帧是否未就绪');
assert.match(returnBlock, /this\.coverMorphReturnCoverInstant = firstFrameMissing \|\|/, 
  '首帧未就绪时返回必须让外层封面第一帧就接管');
assert.match(returnBlock, /if \(!firstFrameMissing\) this\.coverMorphPosterOpacity = 0;/, 
  '首帧未就绪时不能提前清掉 poster，否则返回会缩一块空加载页');
assert.match(returnBlock, /this\.coverMorphProgress = startP;/, 
  '返回首帧 progress 必须接当前进入进度');
assert.match(page, /if \(this\.coverMorphReturning && this\.coverMorphQuickReturn\)/, 
  '进入中途返回的封面矩形必须从当前矩形直接缩回卡片');
assert.match(returnBlock, /getRectangleById\('home-morph-window'\)/, 
  'quick return 必须读当前窗口实际渲染宽度反算起始进度');
assert.match(returnBlock, /\(actualWinW - to\.width\) \/ spanW/, 
  '起始进度必须由实际窗口宽在卡片宽与整页宽之间线性反算');
assert.match(page, /\.id\('home-morph-cover'\)/, '封面层必须有稳定 id 供 quick return 取实际矩形');
assert.ok(!/setTimeout\(leave|settleAndLeave|this\.release\(\)\s*;\s*\n\s*if \(backUrl/.test(returnBlock),
  '返回不得再二次 pop 或提前 release');
assert.match(returnBlock, /if \(!this\.coverMorphOwned\) return false;/,
  '返回必须只认本页消费过的转场，不能读全局 enterInstant');
assert.match(page, /private disposeCoverMorph\(\): void \{[\s\S]{0,1400}?HomeCardMorph\.dispose\(\);/, 
  '页面销毁必须清理服务状态');
assert.match(page, /private disposeCoverMorph\(\): void \{[\s\S]{0,2400}?if \(this\.coverMorphOwned\) \{[\s\S]{0,120}?HomeCardMorph\.dispose\(\);/,
  '只有持有本次转场的页面才能清理服务状态');
assert.match(page, /private readonly coverMorphEnterTransition: boolean = HomeCardMorph\.peekArmed\(\);/, 
  'pageTransition 必须使用页面创建期的 armed 快照');
assert.match(page, /@State private coverMorphReturning: boolean = false;/, 
  '返回标志必须是 @State，改变返回分支时才会重建窗口几何');
assert.match(page, /@State private coverMorphQuickReturn: boolean = false;/, 
  'quick return 标志必须是 @State');

// ── 6) 播放页 Enter 瞬时、Exit 非零撑住；首页 Enter 瞬时、Exit 非零保留 live 页面 ──
const phTrans = page.slice(page.indexOf('  pageTransition() {'), page.indexOf('  private xc: XComponentController'));
assert.match(phTrans, /else if \(this\.coverMorphEnterTransition\) \{/, 
  '播放页 morph 转场不得读取全局 enterInstant（相关推荐页会继承）');
assert.match(phTrans, /PageTransitionEnter\(\{ type: RouteType\.None, duration: 0 \}\)\.opacity\(1\)/, 
  '播放页进入必须瞬时到位');
assert.match(phTrans, /PageTransitionExit\(\{ type: RouteType\.None, duration: HomeCardMorph\.RETURN_HOLD_MS, curve: Curve\.Linear \}\)\.opacity\(1\)/,
  '播放页退出必须用非零、无位移的 Exit 撑住收缩');
const idxTrans = index.slice(index.indexOf('  pageTransition() {'));
assert.match(idxTrans, /PageTransitionEnter\(\{ type: RouteType\.None, duration: 0 \}\)\.opacity\(1\)/, 
  '首页进入必须瞬时到位');
assert.match(idxTrans, /PageTransitionExit\(\{ type: RouteType\.None, duration: HomeCardMorph\.LIVE_BACKDROP_MS, curve: Curve\.Linear \}\)\.opacity\(1\)/, 
  '首页退出必须用足够长、无位移的 Exit 保留 live 页面');

// ── 7) 开关持久化（设置页 + EntryAbility 恢复 + --ps 联调）──────────────────────
assert.match(ability, /pref\.getSync\('homeCardMorph', false\)/, 'EntryAbility 必须恢复开关');
assert.match(ability, /\$ps|homeCardMorph/, '开关必须支持 --ps 联调');
assert.match(read('entry/src/main/ets/pages/ProfilePage.ets'), /setting-home-card-morph/, 
  '设置页必须有开关入口');

// ── 8) 帧率门禁：新加补间必须声明高刷 ─────────────────────────────────────────
const startBlock = page.slice(page.indexOf('private startCoverMorph'), page.indexOf('private finishCoverMorph'));
assert.match(startBlock, /expectedFrameRateRange: \{ min: 60, max: 120, expected: 120 \}/, 
  '撤回后 progress/reveal 动画必须继续声明 120Hz');
assert.match(startBlock, /this\.da \? 0 : HomeCardMorph\.DURATION/, '录屏降级(dt)时必须 0ms');
assert.ok(!/coverMorphAspectP(?!rogress)/.test(page), 
  '不得再有独立的画幅 @State 补间（ArkUI 会把同帧多个 animateTo 合并成同一时长）');
const switchBlock = page.slice(page.indexOf('private switchCoverMorphToPlayer'),
  page.indexOf('private finishCoverMorph'));
assert.match(switchBlock, /duration: this\.da \? 0 : 300,[\s\S]{0,1600}?this\.coverMorphReveal = 1;/, 
  '撤回后切换展开仍由 animateTo 补间到整页');
assert.match(switchBlock, /duration: this\.da \? 0 : \(this\.coverMorphDirectFrame \? 160 : 220\),[\s\S]{0,1600}?this\.coverMorphOverlayOpacity = 0;/, 
  '快照直出时首帧淡入必须提前到 160ms');
assert.match(page, /private coverMorphLayerRect\(\): HomeCardMorphRect \{[\s\S]{0,1400}?const f = Math\.max\(0, Math\.min\(1, this\.coverMorphReveal \/ 0\.5\)\);/, 
  '快照矩形必须在前 50% reveal 贴到视频区，不能拖到完全展开');
assert.match(page, /private coverMorphLayerOpacity\(\): number \{[\s\S]{0,650}?const elapsed = 1 - this\.coverMorphProgress;[\s\S]{0,120}?return Math\.max\(0, Math\.min\(1, \(elapsed - 0\.08\) \/ 0\.55\)\);/, 
  '返回必须先与当前画面交叉淡入封面，不能第一帧直接换成封面');
assert.match(page, /private fadeCoverMorphOverlay\(\): void \{[\s\S]{0,700}?duration: this\.da \? 0 : \(this\.coverMorphDirectFrame \? 160 : 220\)[\s\S]{0,500}?this\.coverMorphOverlayOpacity = 0;/, 
  '快照路径必须 160ms 淡到首帧；URL 回退才用 220ms');
assert.match(page, /\.opacity\(this\.coverMorphLayerOpacity\(\)\)/, 
  '封面层显隐必须由交叉淡入/淡出方法控制');
assert.match(returnBlock, /expectedFrameRateRange: \{ min: 60, max: 120, expected: 120 \}/, 
  '返回收缩必须声明 120Hz 帧率范围');
assert.match(returnBlock, /this\.startCoverMorphRotatedReturn\(\);/,
  '换方向返回必须走主路径而不是直接兜底');
assert.match(page, /elapsed >= HomeCardMorph\.ROTATED_RETURN_WAIT_MS[\s\S]{0,500}?rotated target unavailable/,
  '只有在等待新落点超时后才允许退化为推拉');
assert.match(page, /Math\.max\(HomeCardMorph\.ROTATED_RETURN_MIN_MS,[\s\S]{0,120}?Math\.min\(HomeCardMorph\.ROTATED_RETURN_MAX_MS,/,
  '换方向收缩必须先满足 250ms 下限');
assert.match(page, /this\.coverMorphReturnEarlyHide = true;[\s\S]{0,200}?hide shrink early/,
  '卡片滑出视口时必须提前隐藏退出窗口');

// ── 9) 画幅晚到：起飞前等待、飞行中补间、返回重算画幅 ───────────────────────
assert.match(page, /private readonly MORPH_ASPECT_WAIT_MS: number = 300;/,
  '首次进入缺少画幅时必须在卡片位等待真实 ar，不能先按 16:9 展开');
assert.match(page, /private tryStartCoverMorph\(\): void \{[\s\S]{0,500}?if \(!this\.coverMorphStarted && !this\.morphAspectReady\) \{[\s\S]{0,120}?this\.holdMorphForAspect\(\);/,
  '封面就绪但画幅未就绪时必须等待，不能启动飞行');
assert.match(page, /private applyMorphSafeAspect\([^)]*\): boolean \{[\s\S]{0,1200}?expectedFrameRateRange: \{ min: 60, max: 120, expected: 120 \}/,
  '飞行中收到迟到画幅必须用 120Hz 补间，不能一帧改 target');
assert.match(page, /if \(this\.applyMorphSafeAspect\(aspect, cid, true\)\) return;/,
  '详情画幅必须经过 morph 安全入口');
assert.match(page, /if \(this\.applyMorphSafeAspect\(aspect, this\.vi\.cid, false\)\) \{[\s\S]{0,140}?player\.videoScaleType = this\.getVideoScaleType\(\)/,
  '解码画幅必须经过 morph 安全入口并保留 feed 缩放类型');
assert.match(returnBlock, /this\.coverMorphAspectEqual = Math\.abs\(\s*\n\s*to\.width \/ Math\.max\(1, to\.height\) - this\.coverMorphMediaAspect\(\)\) < 0\.02;/,
  '返回必须按当前视频画幅重算 aspectEqual，不能沿用进入时的 16:9 快照');
assert.match(page, /if \(p <= 0\.0001\) \{\s*\n\s*return \{ x: from\.x, y: from\.y, width: from\.width, height: from\.height, radius: from\.radius \};/,
  '返回末帧封面矩形必须严格等于卡片矩形，不能留下 mediaAspect 的高裁切层');

console.log('PASS: cover morph transition (live home under non-zero page exits, no snapshot base).');
