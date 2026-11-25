import { CoverFlight } from '../components/HomeCoverNode';
/**
 * HomeCardMorph — 首页卡片 ↔ 播放页 的封面一镜到底（几何插值 + 双页 live 叠层）。
 *
 * 为什么不是 `sharedTransition`：它的目标矩形在**页面创建时**读取，那一刻 `cw=0`、
 * 画幅也还没定，只能拿到 1x1；布局完成后真实矩形才出现（竖版视频还是居中窄条），
 * 于是封面会先飞到错误尺寸再回弹。官方「视频展开一镜到底」用 NodeController +
 * 自定义转场，也正是为了在布局后自己算几何。
 *
 * 本服务负责跨页交接封面 URL、卡片封面矩形（起点）与本次是否走 morph。
 * 播放页 push 由 Navigation 瞬时到位，首页作为基础层保持 live；
 * 返回时播放页申请 Navigation 的 POP hold，自己完成收缩后再释放转场。
 * 这样两侧露出的都是真实页面，不需要 componentSnapshot，也不会出现截图与
 * 实时首页不一致的接缝。
 *
 * ⚠️ 开关与 armed 都是「本次 push」的时间点快照：
 *   · 首页 `aboutToAppear` 调 `primeExitInstant()` 落开关快照；
 *   · AppNavigation 在 push 前用 `peekArmed()` 判断本次是否瞬时；
 *   · 返回动画由页面自己消费到的 `coverMorphOwned` 决定，不读全局 enterInstant。
 *   代价：开关切换后需重启一次才全量生效。
 */
import { logInfo, logWarn } from '../utils/Logger';
import { image } from '@kit.ImageKit';

/** 视频画面矩形（vp）；只用于播放页把自己那端占位放到正确位置，几何飞行由框架完成。 */
export interface HomeCardMorphRect {
  x: number;
  y: number;
  width: number;
  height: number;
  radius: number;
}

interface ReturnCurve {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export class HomeCardMorph {
  /** 开关键（AppStorage / my_app_settings 同名） */
  static readonly SWITCH_KEY: string = 'homeCardMorph';
  /** 封面飞行时长上限：只决定飞行路径，不决定切换时刻（切换看封面/首帧谁先就绪） */
  static readonly DURATION: number = 380;
  /**
   * 返回可见收缩时长。平台动效规范要求不少于 250ms；这里取 350ms，
   * 与进入路径同长，返回不至于比打开更快、显得急停。
   */
  static readonly RETURN_DURATION: number = 350;
  /**
   * 历史 Router Exit 的持有预算，现由 AppNavigation 的 POP hold 接管；
   * 保留该常量作为「等重排 + 250ms 收缩 + 收尾」的回归下限。
   */
  static readonly RETURN_HOLD_MS: number = 410;
  /** 换方向返回：收缩不得低于平台下限。 */
  static readonly ROTATED_RETURN_MIN_MS: number = 250;
  /** 换方向返回：收缩上限，避免比同方向返回更拖沓。 */
  static readonly ROTATED_RETURN_MAX_MS: number = 360;
  /** 换方向返回：pop 后可用于「等待重排 + 收缩」的预算。 */
  static readonly ROTATED_RETURN_BUDGET_MS: number = 380;
  /** 换方向返回：等首页新落点的最长时间；超时才允许推拉兜底。 */
  static readonly ROTATED_RETURN_WAIT_MS: number = 140;
  /** 换方向返回：真正拿不到落点时的兜底横移时长，同样不低于 250ms。 */
  static readonly ROTATED_RETURN_FALLBACK_MS: number = 250;
  /**
   * 画幅变换占飞行进度的比例（≈160ms / 380ms）：封面飞行矩形在这一段内从
   * 卡片 16:9 裁切变成视频真实画幅，返回收缩时也按同一比例回到卡片画幅。
   */
  static readonly ASPECT_PROGRESS: number = 0.42;
  /** 返回时已走过的位移比例（0 < progress < 1）。到这里裁剪窗口贴合封面。 */
  static readonly RETURN_JOIN_PROGRESS: number = 0.8;
  static readonly CLIP_JOIN_PROGRESS: number = 1 - HomeCardMorph.RETURN_JOIN_PROGRESS;
  /** 返回大部分时间接近匀速，起步和落位轻缓。 */
  static readonly RETURN_CURVE: ReturnCurve = { x1: 0.08, y1: 0, x2: 0.92, y2: 1 };
  static readonly CARD_RADIUS: number = 8;
  /**
   * 飞行路径终点：最终视频画面矩形 × 该比例（绕中心缩放）。
   * ⚠️ 它只是路径终点，**不是切换时刻**：切换在封面画幅就绪 / 首帧就绪时动态发生，
   *    通常远早于到达这里。提前切的那一帧会把页面几何对齐到当前封面矩形。
   */
  static readonly HANDOFF_SCALE: number = 0.88;
  /** 历史 Router Exit 的 live 下层预算；Navigation 基础层本身常驻，不再依赖该时长。 */
  static readonly LIVE_BACKDROP_MS: number = 2500;
  /** 共享元素 id 前缀（两端必须完全一致） */
  static readonly ID_PREFIX: string = 'home-cover-morph-';

  /** 本次跳转是否已登记封面（首页 arm 后置 true，播放页 consume 后置 false） */
  static liveCover?: CoverFlight;
  static armed: boolean = false;
  /** 首页 pageTransition 用的开关快照 */
  static exitInstant: boolean = false;
  /** 本次共享元素 id（首页与播放页共用） */
  static id: string = '';
  /** 首页卡片封面节点 id（返回收缩期间按它实时取最新窗口矩形） */
  static cardElementId: string = '';
  static cover: string = '';
  /** 点击时截取的卡片封面 PixelMap；播放页直接上屏，不再等网络图 decode。 */
  static coverPixel: image.PixelMap | undefined = undefined;
  /** 卡片封面在窗口坐标系里的矩形（vp），播放页据此插值到视频区 */
  static from: HomeCardMorphRect | undefined = undefined;
  /** 卡片角标数据：返回时封面层要自己把播放量/时长画出来，否则落位后才蹦出 */
  static playCount: number = 0;
  static durationSec: number = 0;
  /** 首页可视区（vp）：用来校验卡片矩形没被读到屏幕外，越界就不接管 */
  static windowW: number = 0;
  static windowH: number = 0;
  /** 点击发生时首页是否为横屏；返回前必须与播放页当前方向一致，否则几何不可复用。 */
  static fromLandscape: boolean = false;
  /** 首页在 pop 后完成一次布局的代数；播放页旋转返回时据此确认卡片落点已不是旧方向。 */
  static homeLayoutReadyGeneration: number = 0;
  /** arm 时刻：残留过久说明这次跳转没真正发生，consume 时作废 */
  static armedAt: number = 0;
  static generation: number = 0;

  static enabled(): boolean {
    return AppStorage.get<boolean>(HomeCardMorph.SWITCH_KEY) === true;
  }

  /**
   * push 前快照：这次 push 是否真的登记过封面。
   * 不能直接读 armed（播放页 aboutToAppear 会 consume）；也不能沿用进程级的
   * 「上一次卡片跳转」标记 —— 相关推荐 push 出的第二个播放页会误走 morph 转场。
   * 所以只认当前这次 armed 的时间窗。
   */
  static peekArmed(): boolean {
    return HomeCardMorph.armed && Date.now() - HomeCardMorph.armedAt <= 2500;
  }

  static sharedId(itemId: string): string {
    return HomeCardMorph.ID_PREFIX + itemId;
  }

  /** 首页卡片封面节点的稳定 id（两端都按 item.id 拼，返回时用于复查落点）。 */
  static cardCoverId(itemId: string): string {
    return 'home-card-cover-' + itemId;
  }

  /** 首页 onPageShow 完成方向重排后调用；播放页只认本次 pop 之后的新代数。 */
  static markHomeLayoutReady(): void {
    HomeCardMorph.homeLayoutReadyGeneration++;
  }

  /** 首页组件字段初始化时调用（早于 aboutToAppear / pageTransition）。 */
  static primeExitInstant(): boolean {
    HomeCardMorph.exitInstant = HomeCardMorph.enabled();
    logInfo(`[HomeCardMorph] prime exitInstant=${HomeCardMorph.exitInstant}`);
    return HomeCardMorph.exitInstant;
  }

  /** 首页在 push 前调用。 */
  static arm(id: string, cover: string, from: HomeCardMorphRect,
    playCount: number, durationSec: number, coverPixel?: image.PixelMap): boolean {
    if (!HomeCardMorph.enabled() || !HomeCardMorph.exitInstant) {
      logInfo(`[HomeCardMorph] skip enabled=${HomeCardMorph.enabled()} exitInstant=${HomeCardMorph.exitInstant}`);
      return false;
    }
    if (id.length === 0 || cover.length === 0) {
      logWarn('[HomeCardMorph] skip empty id/cover');
      return false;
    }
    HomeCardMorph.liveCover = undefined;
    HomeCardMorph.releaseCoverPixel();
    HomeCardMorph.armed = true;
    HomeCardMorph.id = id;
    HomeCardMorph.cardElementId = '';
    HomeCardMorph.cover = cover;
    HomeCardMorph.coverPixel = coverPixel;
    HomeCardMorph.from = from;
    HomeCardMorph.playCount = playCount;
    HomeCardMorph.durationSec = durationSec;
    HomeCardMorph.armedAt = Date.now();
    HomeCardMorph.fromLandscape = HomeCardMorph.windowW > HomeCardMorph.windowH;
    HomeCardMorph.generation++;
    logInfo(`[HomeCardMorph] arm id=${id} ` +
      `from=(${from.x.toFixed(1)},${from.y.toFixed(1)}) ${from.width.toFixed(1)}x${from.height.toFixed(1)}`);
    return true;
  }

  /**
   * 播放页 aboutToAppear：只消费 armed。
   * 超过 2.5s 的残留（路由失败 / 上一次点击没真正跳转）一律作废：否则会拿旧卡片矩形
   * 去飞，落点就飘到屏幕上不相干的位置。
   */
  static consume(): boolean {
    const stale = HomeCardMorph.armed && Date.now() - HomeCardMorph.armedAt > 2500;
    const hit = HomeCardMorph.armed && !stale;
    HomeCardMorph.armed = false;
    if (stale) {
      logWarn('[HomeCardMorph] stale arm dropped');
      HomeCardMorph.from = undefined;
      HomeCardMorph.id = '';
      HomeCardMorph.cardElementId = '';
      HomeCardMorph.cover = '';
      HomeCardMorph.liveCover = undefined;
      HomeCardMorph.releaseCoverPixel();
    }
    return hit;
  }

  static clear(): void {
    HomeCardMorph.armed = false;
  }

  /** 播放页取走 PixelMap 的所有权；之后由页面 dispose 时释放。 */
  static takeCoverPixel(): image.PixelMap | undefined {
    const pixel = HomeCardMorph.coverPixel;
    HomeCardMorph.coverPixel = undefined;
    return pixel;
  }

  static releaseCoverPixel(): void {
    const pixel = HomeCardMorph.coverPixel;
    HomeCardMorph.coverPixel = undefined;
    if (pixel) {
      try { pixel.release().catch(() => {}); } catch (_e) { }
    }
  }

  static dispose(): void {
    HomeCardMorph.armed = false;
    HomeCardMorph.id = '';
    HomeCardMorph.cardElementId = '';
    HomeCardMorph.cover = '';
    HomeCardMorph.liveCover = undefined;
    HomeCardMorph.releaseCoverPixel();
    HomeCardMorph.from = undefined;
    HomeCardMorph.playCount = 0;
    HomeCardMorph.durationSec = 0;
  }
}
