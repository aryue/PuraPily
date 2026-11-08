import { FollowGlassButton } from '../components/FollowGlassButton';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageSurface } from '../components/PageSurface';
import { PageWallpaper } from '../components/PageWallpaper';
import { gradientTitleBarStyle } from '../utils/HeaderStyle';
import { promptAction, LengthMetrics, display, window, curves, mediaquery, KeyboardAvoidMode } from '@kit.ArkUI';
import { HdsNavigation, TitleSize, DividerShowType, HdsNavigationTitleMode, ScrollEffectType } from '@kit.UIDesignKit';
import { hdsMaterial } from '@hms.hds.hdsMaterial';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { motion } from '@kit.MultimodalAwarenessKit';
import { VibrateUtils } from '../utils/VibrateUtils';
import { DynamicBackToTopButton } from '../components/DynamicBackToTopButton';
import { logInfo, logWarn, logError } from '../utils/Logger';
import {
  getDynamicDetail, getDynComments, getDynCommentReplies, addDynComment, setDynCommentLike, setDynamicLike, repostDynamic,
  getFollowStatus, modifyFollow, uploadCommentImage,
  SpaceDynamicItem, CommentItem, CommentLikeResult, AddCommentResult
} from '../api/BilibiliApi';
import { ObservableComment } from '../model/ObservableComment';
import { ObservableDynLike } from '../model/ObservableDynLike';
import { DynamicCardBody } from '../components/DynamicCardBody';
import { DynamicDetailDock } from '../components/DynamicDetailDock';
import { Animator, AnimatorResult } from '@kit.ArkUI';
import { NativeComposerSurface } from '../components/NativeComposerSurface';
import { CommentItemComponent } from '../components/CommentItemComponent';
import { CommentInputBar, CommentImageDraft, CommentInputBarCtrl } from '../components/CommentInputBar';
import { FullImagePreview } from '../components/FullImagePreview';
import { fmtCount } from '../utils/NumberFormat';
import { fmtRelativeTime } from '../utils/TimeFormat';
import { resizeImageUrl } from '../utils/ImageUrl';
import { themeHexAlpha } from '../utils/ThemeColor';

/**
 * HdsNavigation（MINI 模式）标题栏高度（vp）。
 *
 * ⚠️ 实测（2026-09-18，uitest dumpLayout）：`TitleBar` 与 `NavBarContent` 的 top **完全相同**
 *    （本机均为 y=117px，标题栏自身高 143px = 56vp）—— 即**框架不会为标题栏让位**，
 *    内容区是从标题栏底边那一行开始画的，第一屏会被毛玻璃标题栏盖住 56vp。
 *    ⇒ 用 HdsNavigation 承载内容的页面，必须自己给滚动内容留出这段高度；
 *      滚动后内容从标题栏底下滑过（毛玻璃）才是预期效果。
 */
const TITLE_BAR_H_VP: number = 56;

/**
 * ⚠️ 为什么留白还要再加一次"状态栏高度"（2026-09-18 实测，`uitest dumpLayout` 定量）：
 *   `HdsNavigation` 的内容区（`NavBarContent`）在 `expandSafeArea` 下**按窗口坐标布局**，
 *   而它的可见起点是 y=117px（状态栏下沿）⇒ 内容被整体**上移了正好一个状态栏高度**。
 *   实测：作者行 top=221px，而标题栏下沿在 260px ⇒ 首屏被毛玻璃标题栏压住；
 *   同时"打开时信息流突然向上位移"也是这一下（首帧按正确坐标画，随后被这个偏移推上去）。
 *   排查旁证：`Scroller.currentOffset()` 全程为 0（我加的偏移日志一次都没打），所以**不是滚动偏移**。
 *   ⇒ 留白 = 标题栏 56 + 状态栏高度（运行时取 avoidArea）+ 8 呼吸，两端才对得上。
 */
const TOP_EXTRA_GAP_VP: number = 8;

// Native gradient now finishes inside the title. Keep only normal title spacing.
const CONTENT_TOP_TARGET_VP: number = TITLE_BAR_H_VP + TOP_EXTRA_GAP_VP;


/** 二级回复每页条数。
 *  ⚠️ 必须是 **20**：实测请求 `ps=30` 服务端只返回 20（`[getCommentReplies] 返回20条`），
 *     若按 30 推算页码会算错 —— `已加载20 / 30 = 0` ⇒ 又去请求第 1 页，去重后零新增，
 *     用户看到的就是"点了展开更多回复没反应"。 */
const REPLY_PAGE_SIZE: number = 20;

/**
 * 滚动偏移超过该值（vp）才显示"回到顶部"按钮（与搜索页 / 观看历史页同一阈值，三页观感一致）。
 * ⚠️ 回调里只在**值真的变了**时才写 `showBackToTop`：onWillScroll 每帧都会调，
 *    无条件写状态会让整页每帧都标记脏（本页是长列表 + 毛玻璃标题栏，白白丢帧）。
 */
const BACK_TO_TOP_THRESHOLD_VP: number = 300;

/**
 * 动态详情页
 *
 * 版式：
 *   内容卡（作者行 + 关注 + 正文 + 图片 + 媒体条 + 统计行）
 *   → 评论头（数量 + 排序切换）→ 评论列表（复用播放页的 CommentItemComponent）
 *   → 加载更多 → 底部悬浮输入胶囊（无遮罩、不自动弹键盘）
 *
 * ⚠️ 卡片外观一律走 components/DynamicCardBody（与动态页同一份），不要在本页另写一套；
 *
 * 数据：`getDynamicDetail` + `getDynComments`；
 *  ⚠️ 评论区定位必须用 item 的 `commentType`/`commentIdStr`（视频类动态的评论挂在稿件上，
 *     直接用 17 + 动态 id 会 -404）；列表页已拿到 item 时会通过路由 preload 先渲染，避免白屏。
 */
interface DynamicCommentCache {
  items: ObservableComment[];
  cursor: number;
  hasMore: boolean;
}

@Entry
@Component({ freezeWhenInactive: true })
struct DynamicDetailPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('hideNavigationIndicator') hideNavigationIndicator: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('biliCookie') biliCookie: string = '';
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardListBorderRadius') cardListBorderRadius: number = 12;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 15;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = true;

  /** 状态栏高度（vp，运行时取 avoidArea）：顶部留白要把它补回来，见 TOP_EXTRA_GAP_VP 注释 */
  @State statusBarVp_: number = 0;
  /**
   * 顶部留白（vp）。**由实测坐标自适应修正**，不靠公式猜：
   * 框架在 `HdsNavigation` 内容区里会把内容整体上移约一个状态栏高度（实测恒定 114px），
   * 且这个量在不同设备/版本上未必一致 ⇒ 渲染后用 `getRectangleById` 量出内容卡实际位置，
   * 不够就往里加（见 correctTopGap）。
   */
  @State topGap_: number = TITLE_BAR_H_VP + TOP_EXTRA_GAP_VP;
  @State item: SpaceDynamicItem | null = null;
  @State loading: boolean = true;
  @State err: string = '';

  // ── 评论 ──
  @State comments: ObservableComment[] = [];
  @State commentsCursor: number = 0;
  @State commentsHasMore: boolean = false;
  @State commentsLoading: boolean = false;
  @State commentsLoaded: boolean = false;
  @State commentsError: boolean = false;
  private commentFailures: Set<number> = new Set();
  private commentCaches: Map<number, DynamicCommentCache> = new Map();
  private commentRequests: Map<number, number> = new Map();
  private commentRequestSeq: number = 0;
  /** 排序：3=按热度(默认) / 2=按时间 —— 对应评论接口的 mode */
  @State commentsSort: number = 3;
  /** 二级回复版本：气泡组件靠 @Prop 变化重算"展开 N 条"文案 */
  @State repliesVersion: number = 0;

  // ── 回复输入 ──
  /** 当前回复目标，根评论入口打开时清空。 */
  @State replyRoot: number = 0;
  @State replyParent: number = 0;
  @State replyTargetName: string = '';

  // ── 关注 ──
  @State following: boolean = false;
  @State followLoaded: boolean = false;
  private followBusy_: boolean = false;

  // ── 图片预览 ──
  @State @Watch('onPreviewToggle') showPreview: boolean = false;
  @State previewUrls: string[] = [];
  @State previewIndex: number = 0;
  @State previewOriginX: number = 0;
  @State previewOriginY: number = 0;
  @State previewOriginW: number = 0;
  @State previewOriginH: number = 0;

  /**
   * ⭐ 点赞状态必须是**状态变量**才能传给子组件的 @ObjectLink（编译器会拒绝普通私有字段）；
   *    改字段只通知绑定它的组件，页面其余部分不重建。
   */
  @State likeState_: ObservableDynLike = new ObservableDynLike(false, 0);
  private liking_: boolean = false;
  private dynId_: string = '';
  private scroller: Scroller = new Scroller();
  private bodyScroller: Scroller = new Scroller();
  private portraitScrollY: number = 0;
  private splitBodyScrollY: number = 0;
  private splitCommentsScrollY: number = 0;
  private restoreScrollPending: boolean = false;
  private commentsScroller: Scroller = new Scroller();
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  private topLayoutRevision: number = 0;
  private topLayoutTimer: number = -1;
  private layoutActive: boolean = false;
  private screenW: number = 0;
  private screenH: number = 0;

  // 编辑面板只在点击评论入口或回复后显示。
  @State @Watch('onCommentEntryChanged') entrySheetOn: boolean = false;
  @State entryKeyboardHeight: number = 0;
  @State entryEditorHeight: number = 184;
  @State entryProgress: number = 0;
  @State entryClosing: boolean = false;
  private entryOrigin: number[] = [16, 0, 160, 42];
  private entryAnimator: AnimatorResult | null = null;
  private entryKeyboardAnimator: AnimatorResult | null = null;
  private entryStartTimer: number = -1;
  private entryAvoidMode: KeyboardAvoidMode | null = null;
  private entryWindow: window.Window | undefined = undefined;
  private onEntryKeyboardHeight = (height: number): void => {
    const target = Math.max(0, this.getUIContext().px2vp(height));
    if (!this.entrySheetOn) return;
    this.entryKeyboardAnimator?.cancel();
    const from = this.entryKeyboardHeight;
    const animation = Animator.create({ duration: 260, easing: 'cubic-bezier(0.2, 0, 0, 1)',
      delay: 0, direction: 'normal', iterations: 1, fill: 'forwards', begin: 0, end: 1 });
    this.entryKeyboardAnimator = animation;
    animation.onframe = (progress: number) => { this.entryKeyboardHeight = from + (target - from) * progress; };
    animation.onfinish = () => {
      this.entryKeyboardHeight = target;
      this.entryKeyboardAnimator = null;
    };
    if (target > 0 && this.entryProgress === 0 && !this.entryClosing && !this.entryAnimator) {
      if (this.entryStartTimer >= 0) clearTimeout(this.entryStartTimer);
      this.entryStartTimer = -1;
      this.animateEntryComposer(1);
    }
    animation.play();
  };

  private onCommentEntryChanged(): void {
    if (this.entrySheetOn) {
      this.captureEntryOrigin();
      this.entryProgress = 0;
      this.entryClosing = false;
      if (this.entryAvoidMode === null) {
        this.entryAvoidMode = this.getUIContext().getKeyboardAvoidMode();
        this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
        this.entryWindow = (this.getUIContext().getHostContext() as common.UIAbilityContext).windowStage.getMainWindowSync();
        this.entryWindow?.on('keyboardHeightChange', this.onEntryKeyboardHeight);
      }
      // A hardware keyboard may not emit a height event; still expand the editor.
      this.entryStartTimer = setTimeout(() => {
        this.entryStartTimer = -1;
        if (this.entrySheetOn && !this.entryClosing && !this.entryAnimator && this.entryProgress === 0) {
          this.animateEntryComposer(1);
        }
      }, 320);
    } else {
      this.releaseEntryKeyboard();
    }
  }

  private releaseEntryKeyboard(): void {
    if (this.entryStartTimer >= 0) clearTimeout(this.entryStartTimer);
    this.entryStartTimer = -1;
    this.entryAnimator?.cancel();
    this.entryAnimator = null;
    this.entryKeyboardAnimator?.cancel();
    this.entryKeyboardAnimator = null;
    this.entryWindow?.off('keyboardHeightChange', this.onEntryKeyboardHeight);
    this.entryWindow = undefined;
    this.entryKeyboardHeight = 0;
    this.entryProgress = 0;
    this.entryClosing = false;
    if (this.entryAvoidMode !== null) {
      this.getUIContext().setKeyboardAvoidMode(this.entryAvoidMode);
      this.entryAvoidMode = null;
    }
  }

  private entryAvailableHeight(): number {
    let available = this.viewportHeight;
    let hostTop = 0;
    try {
      const host = this.getUIContext().getComponentUtils().getRectangleById('dynamic-detail-root');
      hostTop = this.getUIContext().px2vp(host.windowOffset.y);
      available = this.getUIContext().px2vp(host.size.height);
    } catch (_) {}
    if (this.entryWindow) {
      const height = this.getUIContext().px2vp(this.entryWindow.getWindowProperties().windowRect.height);
      // All positions are relative to the actual host, including its system-safe-area expansion.
      available = Math.min(available, height - hostTop - this.entryKeyboardHeight);
    }
    return Math.max(0, available);
  }

  private entryTargetHeight(): number {
    return Math.min(this.entryEditorHeight, Math.max(100, this.entryAvailableHeight() - 64));
  }

  private entryEditorTop(): number {
    return Math.max(0, this.entryAvailableHeight() - this.entryTargetHeight());
  }

  private captureEntryOrigin(): void {
    this.entryOrigin = [16, this.viewportHeight - (this.hideNavigationIndicator ? 50 : 54), Math.max(120, this.viewportWidth / 2 - 28), 42];
    try {
      const utils = this.getUIContext().getComponentUtils();
      const source = utils.getRectangleById('dynamic-comment-entry');
      const host = utils.getRectangleById('dynamic-detail-root');
      const w = this.getUIContext().px2vp(source.size.width);
      const h = this.getUIContext().px2vp(source.size.height);
      if (w > 0 && h > 0) this.entryOrigin = [
        this.getUIContext().px2vp(source.windowOffset.x - host.windowOffset.x),
        this.getUIContext().px2vp(source.windowOffset.y - host.windowOffset.y), w, h];
    } catch (_) {}
  }

  private entryFrameWidth(): number {
    return this.entryOrigin[2] + (this.viewportWidth - this.entryOrigin[2]) * this.entryProgress;
  }

  private entryFrameHeight(): number {
    return this.entryOrigin[3] + (this.entryTargetHeight() - this.entryOrigin[3]) * this.entryProgress;
  }

  private animateEntryComposer(target: number): void {
    this.entryAnimator?.cancel();
    const from = this.entryProgress;
    const animation = Animator.create({ duration: target === 1 ? 300 : 240,
      easing: target === 1 ? 'cubic-bezier(0.2, 0, 0, 1)' : 'cubic-bezier(0.4, 0, 0.2, 1)',
      delay: 0, direction: 'normal', iterations: 1, fill: 'forwards', begin: 0, end: 1 });
    this.entryAnimator = animation;
    animation.onframe = (progress: number) => { this.entryProgress = from + (target - from) * progress; };
    animation.onfinish = () => {
      this.entryProgress = target;
      this.entryAnimator = null;
      if (target === 0 && this.entryClosing) this.entrySheetOn = false;
    };
    animation.play();
  }
  @State repostVisible: boolean = false;
  @State repostText: string = '';
  @State repostSending: boolean = false;
  @State forwardCount: number = 0;
  @State commentCount: number = 0;
  /** 返回时先收起编辑器中的表情面板。 */
  private entryEmoteCtrl: CommentInputBarCtrl = new CommentInputBarCtrl();

  // ══════ 回到顶部悬浮按钮（形态与交互复刻搜索页，位置独立持久化） ══════
  @StorageLink('smartGripEnabled') smartGripEnabled: boolean = true;
  @StorageLink('floatBtnFollowTheme') floatBtnFollowTheme: boolean = true;
  @StorageLink('da') da: boolean = false;
  /** 按钮距屏幕底的距离（vp）；拖动可越出放置区，松手回弹后才落盘。 */
  @StorageLink('dynDetailFloatBtnY') dynDetailFloatBtnY: number = 120;
  /** 单按钮形态下吸附在哪一侧：'left' / 'right' */
  @StorageLink('dynDetailFloatBtnSide') dynDetailFloatBtnSide: string = 'right';
  /** 滚动是否超过阈值（决定按钮显示；见 BACK_TO_TOP_THRESHOLD_VP） */
  @State showBackToTop: boolean = false;
  /** 点击时"缩一下再弹回"的缩放系数 */
  @State private btnScale: number = 1;
  /** 拖动中（此时要关掉 position 上的过渡动画，否则按钮追不上手指） */
  @State private isDragging: boolean = false;
  @State private dragStartY: number = 0;
  private dragStartX: number = 0;
  @State private dragOffsetX: number = 0;
  /** 松手后的放置区上限；不用于限制拖动过程。 */
  @State private maxFloatBtnBottom: number = 592;
  /** 智感握姿：1=左手 2=右手 16=未知（motion.HoldingHandStatus） */
  @State private hand: number = 16;
  @State private smartGripLeft: number = -1;
  @State private smartGripRight: number = 32;
  @State isLandscape: boolean = false;
  private gripSafeAreaLeft: number = 24;
  private gripSafeAreaRight: number = 24;
  private gripListenersInitialized: boolean = false;
  /** 握持回调的引用：`motion.off` 只摘自己这一个，不用裸 off（那会连带删掉其它页面的监听） */
  private gripCallback_: ((data: number) => void) | null = null;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  private touchStartWX: number = 0;
  private touchStartWY: number = 0;
  private touchMoved: boolean = false;

  aboutToAppear(): void {
    this.layoutActive = true;
    try {
      const d = display.getDefaultDisplaySync();
      this.screenW = this.getUIContext().px2vp(d.width);
      this.screenH = this.getUIContext().px2vp(d.height);
    } catch (_e) {
      this.screenW = 360;
      this.screenH = 780;
    }
    this.viewportWidth = this.screenW;
    this.viewportHeight = this.screenH;
    // 状态栏高度（px → vp）：NavBarContent 会少算这一段，留白里补回来
    try {
      const mw = (this.getUIContext().getHostContext() as common.UIAbilityContext).windowStage.getMainWindowSync();
      if (mw) {
        const area: window.AvoidArea = mw.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusBarVp_ = this.getUIContext().px2vp(area.topRect.height);
      }
    } catch (_e) {
      this.statusBarVp_ = 0;
    }
    this.topGap_ = AppStorage.get<number>(this.topGapCacheKey()) ??
      (TITLE_BAR_H_VP + this.statusBarVp_ + TOP_EXTRA_GAP_VP);
    // 回到顶部按钮：智感握姿（决定按钮贴哪一侧）+ 横竖屏（决定按钮形态与可拖范围）
    this.initSmartGrip();
    this.initOrientation();
    // 入口 sheet 盖在页面之上 ⇒ 回顶按钮下限抬高；历史落盘的位置可能低于新下限，这里夹一次
    this.dynDetailFloatBtnY = Math.max(this.floatBtnMinBottom(),
      Math.min(this.floatBtnMaxBottom(), this.dynDetailFloatBtnY));
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    if (!params) {
      this.err = '参数缺失';
      this.loading = false;
      return;
    }
    const idParam = params['dynIdStr'];
    this.dynId_ = typeof idParam === 'string' ? idParam : '';
    const preload = params['preload'] as SpaceDynamicItem | undefined;
    if (preload) {
      this.applyItem(preload);
      this.loading = false;
      this.loadFollowStatus();
    }
    if (!this.dynId_) {
      this.err = '动态 id 缺失';
      this.loading = false;
      return;
    }
    this.loadDetail();
    this.loadComments(true);
    // Preloaded body renders immediately. Geometry checks never gate visibility.
    this.queueTopGapCorrection();
  }


  aboutToDisappear(): void {
    this.releaseEntryKeyboard();
    this.layoutActive = false;
    this.commentRequests.clear();
    this.topLayoutRevision++;
    if (this.topLayoutTimer >= 0) clearTimeout(this.topLayoutTimer);
    this.topLayoutTimer = -1;
    // ⭐ 精确摘掉自己注册的握持监听：`motion.off(type, callback)` 只删这一个回调。
    //    ⚠️ 不要用不带 callback 的 `motion.off(type)` —— 那会把**其它页面**注册的监听一起删掉，
    //       而它们的 `gripListenersInitialized` 已是 true，不会再补注册 ⇒ 那些页面的智感握姿静默失效。
    if (this.gripCallback_) {
      try { motion.off('holdingHandChanged', this.gripCallback_); } catch (_e) { }
      this.gripCallback_ = null;
    }
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  private closeCommentEntry(): void {
    if (!this.entrySheetOn || this.entryClosing) return;
    this.entryClosing = true;
    if (this.entryStartTimer >= 0) clearTimeout(this.entryStartTimer);
    this.entryStartTimer = -1;
    this.getUIContext().getFocusController().clearFocus();
    this.animateEntryComposer(0);
  }

  onPageHide(): void {
    this.entrySheetOn = false;
  }

  onBackPress(): boolean {
    if (!this.entrySheetOn) return false;
    if (this.entryClosing) return true;
    if (this.entryKeyboardHeight > 0) {
      this.getUIContext().getFocusController().clearFocus();
      return true;
    }
    if (!this.entryEmoteCtrl.collapseEmote()) this.closeCommentEntry();
    return true;
  }

  onPreviewToggle(): void {
    if (this.showPreview) this.entrySheetOn = false;
  }

  /** 回顶按钮避开底部评论入口。 */
  private floatBtnMinBottom(): number {
    return 88;
  }

  private floatBtnMaxBottom(): number {
    return Math.max(this.floatBtnMinBottom(), Math.min(this.maxFloatBtnBottom,
      this.viewportHeight - 48 - this.statusBarVp_ - TITLE_BAR_H_VP));
  }

  private floatBtnAnchorX(): number {
    if (this.smartGripEnabled && !this.isLandscape) {
      return this.hand === 1 ? this.smartGripLeft : this.viewportWidth - this.smartGripRight - 48;
    }
    return this.dynDetailFloatBtnSide === 'left' ? 32 : this.viewportWidth - 80;
  }

  private floatBtnX(): number {
    return Math.max(0, Math.min(this.viewportWidth - 48,
      this.isDragging ? this.dragStartX + this.dragOffsetX : this.floatBtnAnchorX()));
  }

  private floatBtnY(): number {
    return Math.max(0, this.viewportHeight - 48 - this.dynDetailFloatBtnY);
  }

  // ═══════════════════════════════════════════
  // 回到顶部悬浮按钮（复刻搜索页：沉浸光感 + 智感握姿 + 拖动改位置 + 落盘记忆）
  // ═══════════════════════════════════════════

  /** 统一触觉反馈（15ms 短震，受"触感反馈"总开关控制，与搜索页一致） */
  private triggerHaptic(): void {
    VibrateUtils.vibrateTime(15);
  }

  /**
   * 智感握姿：左手握持 → 按钮贴左边缘，右手/未知 → 贴右边缘。
   * ⚠️ 两个 side 的值**任何时候都要有效**：position 从"有值→无值"会触发一次平移动画
   *    （表现为按钮从屏幕中间横着飞过去），所以这里两边一起算。
   */
  private recalcSmartGripPosition(): void {
    this.smartGripLeft = this.gripSafeAreaLeft + 16;
    this.smartGripRight = this.gripSafeAreaRight + 8;
  }

  /**
   * 注册智感握姿监听（只能注册一次；失败静默 —— 部分机型/模拟器不支持该能力）。
   * ⚠️ 回调里必须判断"值真的变了"，否则握持状态每次上报都会写 @State（整页重排）。
   */
  private initSmartGrip(): void {
    if (this.gripListenersInitialized) return;
    try {
      const cb = (data: number): void => {
        if (data !== this.hand && (data === 1 || data === 2)) {
          this.hand = data;
          this.recalcSmartGripPosition();
        }
      };
      this.gripCallback_ = cb;
      motion.on('holdingHandChanged', cb);
      this.gripListenersInitialized = true;
    } catch (e) {
      logWarn('[DynamicDetail] 初始化智感握姿失败:', e);
    }
  }

  /**
   * 横竖屏监听：竖屏 + 智感握姿开 ⇒ 左右两个按钮；否则（关/横屏）⇒ 单个可换边按钮。
   * 同时维护可拖范围上限（横屏窗口矮，沿用搜索页的 392/592）。
   */
  private initOrientation(): void {
    try {
      const mq = this.getUIContext().getMediaQuery();
      this.landscapeListener = mq.matchMediaSync('(orientation: landscape)');
      this.isLandscape = this.landscapeListener.matches;
      this.maxFloatBtnBottom = this.isLandscape ? 392 : 592;
      this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.isLandscape = result.matches;
        this.queueTopGapCorrection();
        this.maxFloatBtnBottom = result.matches ? 392 : 592;
      });
    } catch (e) {
      logWarn('[DynamicDetail] 初始化方向监听失败:', e);
    }
  }

  /** 点击回到顶部：触觉反馈 + 缩一下再弹回（与搜索页同一套曲线）+ 列表回顶 */
  private handleBackToTopClick(): void {
    this.triggerHaptic();
    animateTo({ duration: 100, curve: Curve.FastOutLinearIn }, () => {
      this.btnScale = 0.8;
    });
    setTimeout(() => {
      animateTo({ duration: 300, curve: curves.springMotion(0.4, 0.8) }, () => {
        this.btnScale = 1;
      });
    }, 100);
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
    if (this.useSplitLayout()) {
      this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0,
        animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
      this.commentsScroller.scrollTo({ xOffset: 0, yOffset: 0,
        animation: { duration: this.da ? 0 : 300, curve: Curve.EaseOut } });
    }
  }

  /**
   * Drag within the full screen, then spring back into the placement region.
   * @param snapSide Single-button mode selects the nearest side on release;
   * smart grip returns to its hand-selected side after dragging in either direction.
   *
   * windowX/windowY 已是 vp，直接按位移更新；位置不参与显隐的隐式动画。
   *    `bottom` 是"距屏幕底"⇒ 手指上移（windowY 变小）时要**增大** bottom，故取 −offY。
   */
  private handleFloatBtnTouch(event: TouchEvent, snapSide: boolean): void {
    if ((event.type === TouchType.Down || event.type === TouchType.Move) && event.touches.length === 0) return;
    if (event.type === TouchType.Down) {
      this.touchStartWX = event.touches[0].windowX;
      this.touchStartWY = event.touches[0].windowY;
      this.dragStartY = this.dynDetailFloatBtnY;
      this.dragStartX = this.floatBtnX();
      this.dragOffsetX = 0;
      this.touchMoved = false;
      this.isDragging = true;
    } else if (event.type === TouchType.Move) {
      const offYVp: number = event.touches[0].windowY - this.touchStartWY;
      const offXVp: number = event.touches[0].windowX - this.touchStartWX;
      if (Math.abs(offYVp) > 5 || Math.abs(offXVp) > 5) {
        this.touchMoved = true;
      }
      // The screen is the drag region; placement restrictions apply only after release.
      this.dynDetailFloatBtnY = Math.max(0,
        Math.min(Math.max(0, this.viewportHeight - 48), this.dragStartY - offYVp));
      this.dragOffsetX = offXVp;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.touchMoved) {
        const newSide = this.floatBtnX() + 24 < this.viewportWidth / 2 ? 'left' : 'right';
        const bottom = Math.max(this.floatBtnMinBottom(), Math.min(this.floatBtnMaxBottom(),
          event.type === TouchType.Cancel ? this.dragStartY : this.dynDetailFloatBtnY));
        animateTo({ duration: this.da ? 0 : 360, curve: curves.springMotion(0.35, 0.8) }, () => {
          this.dynDetailFloatBtnY = bottom;
          if (snapSide && event.type !== TouchType.Cancel) this.dynDetailFloatBtnSide = newSide;
          this.isDragging = false;
          this.dragOffsetX = 0;
        });
        // @StorageLink 已经是双向同步，这里只需落盘（下次冷启动由 Index 读回 AppStorage）
        this.saveFloatBtnPrefs();
      } else {
        this.isDragging = false;
        this.dragOffsetX = 0;
        if (event.type === TouchType.Up) {
          this.handleBackToTopClick();
        }
      }
    }
  }

  /** 把按钮位置落盘（与搜索页/历史页共用同一个 preferences 文件、各自的 key） */
  private async saveFloatBtnPrefs(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('dynDetailFloatBtnSide', this.dynDetailFloatBtnSide);
      await pref.put('dynDetailFloatBtnY', this.dynDetailFloatBtnY);
      await pref.flush();
    } catch (e) {
      logError('保存动态详情页悬浮按钮位置失败', e);
    }
  }

  // ────────────── 数据 ──────────────

  /**
   * 用实测坐标校正正文与标题栏之间的正常间距。
   * ⚠️ 为什么要自适应而不是写死公式：框架对 `HdsNavigation` 内容区的那次上移（实测 114px ≈ 状态栏高度）
   *    是**未文档化的行为**，写死数字在别的设备/版本上就会偏；这里量出实际位置再补差额，一次到位。
   */
  private topGapCacheKey(): string {
    return 'dynamicDetailTopGap_' + Math.round(this.viewportWidth) + '_' + Math.round(this.statusBarVp_);
  }

  private queueTopGapCorrection(): void {
    if (!this.layoutActive) return;
    const revision = ++this.topLayoutRevision;
    if (this.topLayoutTimer >= 0) clearTimeout(this.topLayoutTimer);
    this.topLayoutTimer = setTimeout(() => this.recheckTopLayout(revision, 0), 16);
  }

  private recheckTopLayout(revision: number, attempt: number): void {
    if (!this.layoutActive || revision !== this.topLayoutRevision) return;
    this.topLayoutTimer = -1;
    this.restoreLayoutScroll();
    const bodyOffset = this.useSplitLayout() ? this.bodyScroller.currentOffset().yOffset : this.scroller.currentOffset().yOffset;
    if (this.item && Math.abs(bodyOffset) < 1) {
      this.correctTopGap('布局落定');
    }
    // Native title layout can settle after the viewport callback or before the new pane mounts.
    // Area callbacks restart this short check with a new revision; old orientation checks expire.
    if (attempt < 3) {
      this.topLayoutTimer = setTimeout(() => this.recheckTopLayout(revision, attempt + 1), 48);
    }
  }

  private correctTopGap(tag: string): void {
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById('dd_card');
      const cardTop: number = this.getUIContext().px2vp(info.windowOffset.y);
      const header = this.getUIContext().getComponentUtils().getRectangleById('dynamic-detail-header');
      const want: number = this.getUIContext().px2vp(header.windowOffset.y + header.size.height) + TOP_EXTRA_GAP_VP;
      const delta: number = want - cardTop;
      if (Math.abs(delta) > 1) {
        this.topGap_ = Math.max(0, this.topGap_ + delta);
        logInfo(`[DynamicDetail] ${tag} 内容顶=${cardTop.toFixed(1)}vp 目标=${want.toFixed(1)}vp → 留白调到 ${this.topGap_.toFixed(1)}vp`);
        AppStorage.setOrCreate(this.topGapCacheKey(), this.topGap_);
      }
    } catch (_e) {
      // 取不到矩形就保持当前留白
    }
  }

  /** 落地一条动态：同步点赞状态（@ObjectLink 需要长期同一个实例，所以只改字段不换对象） */
  private applyItem(it: SpaceDynamicItem): void {
    this.item = it;
    this.queueTopGapCorrection();
    this.forwardCount = it.forwardCount;
    this.commentCount = it.commentCount;
    this.likeState_.liked = it.liked;
    this.likeState_.count = it.likeCount;

  }

  private async loadDetail(): Promise<void> {
    const it: SpaceDynamicItem | null = await getDynamicDetail(this.dynId_);
    if (it) {
      this.applyItem(it);
      this.err = '';
      this.loadFollowStatus();
    } else if (!this.item) {
      this.err = '加载失败，请返回重试';
    }
    this.loading = false;
  }

  private async loadFollowStatus(): Promise<void> {
    const it = this.item;
    if (!it || it.authorMid <= 0 || this.followLoaded) return;
    try {
      this.following = await getFollowStatus(it.authorMid);
      this.followLoaded = true;
    } catch (e) {
      logWarn(`[DynamicDetail] 关注状态查询失败: ${e}`);
    }
  }

  // ────────────── 评论 ──────────────

  private async loadComments(reset: boolean, mode: number = this.commentsSort, prefetch: boolean = false): Promise<void> {
    if (this.commentRequests.has(mode) && !reset) return;
    const cached = this.commentCaches.get(mode);
    if (!reset && !(cached?.hasMore ?? this.commentsHasMore)) return;
    const it = this.item;
    const oid: string = it ? it.commentIdStr : this.dynId_;
    const ctype: number = it ? it.commentType : 17;
    if (!oid) return;
    const request = ++this.commentRequestSeq;
    this.commentRequests.set(mode, request);
    this.commentFailures.delete(mode);
    if (mode === this.commentsSort) this.commentsError = false;
    const deadline = setTimeout(() => {
      if (this.commentRequests.get(mode) !== request) return;
      this.commentRequests.delete(mode);
      this.failComments(mode);
    }, 15000);
    if (!prefetch && mode === this.commentsSort) this.commentsLoading = true;
    try {
      const cursor = reset ? 0 : (cached?.cursor ?? this.commentsCursor);
      const res = await getDynComments(oid, cursor, 20, mode, ctype,
        () => this.commentRequests.get(mode) === request);
      if (this.commentRequests.get(mode) !== request) return;
      if (!res) { this.failComments(mode); return; }
      const list: ObservableComment[] = [];
      for (const c of res.comments) list.push(ObservableComment.from(c));
      const state: DynamicCommentCache = {
        items: reset ? list : [...(cached?.items ?? this.comments), ...list],
        cursor: res.nextCursor, hasMore: !res.isEnd && res.nextCursor > 0
      };
      this.commentCaches.set(mode, state);
      if (mode === this.commentsSort) {
        this.restoreCommentCache(state);
        this.repliesVersion++;
      }
      // Fetch the other ordering before the user switches; never clear the visible list.
      const other = mode === 3 ? 2 : 3;
      if (!prefetch && !this.commentCaches.has(other) && !this.commentRequests.has(other)) {
        this.loadComments(true, other, true);
      }
    } catch (e) {
      logError(`[DynamicDetail] loadComments 异常: ${e}`);
      if (this.commentRequests.get(mode) === request) this.failComments(mode);
    } finally {
      clearTimeout(deadline);
      if (this.commentRequests.get(mode) === request) {
        this.commentRequests.delete(mode);
        if (mode === this.commentsSort) {
          this.commentsLoading = false;
          this.commentsLoaded = true;
        }
      }
    }
  }

  private failComments(mode: number): void {
    this.commentFailures.add(mode);
    if (mode === this.commentsSort) {
      this.commentsError = true;
      this.commentsLoading = false;
      this.commentsLoaded = true;
    }
  }

  private restoreCommentCache(state: DynamicCommentCache): void {
    this.commentsError = false;
    this.comments = state.items;
    this.commentsCursor = state.cursor;
    this.commentsHasMore = state.hasMore;
    this.commentsLoaded = true;
  }

  private switchSort(mode: number): void {
    if (this.commentsSort === mode) return;
    this.commentsSort = mode;
    this.commentsError = this.commentFailures.has(mode);
    const cached = this.commentCaches.get(mode);
    this.commentsLoading = false;
    if (cached) {
      this.restoreCommentCache(cached);
    } else {
      // Keep the current content while an uncached ordering finishes.
      this.commentsHasMore = false;
      if (!this.commentRequests.has(mode)) this.loadComments(true, mode);
    }
  }

  /**
   * 判断二级回复是否还有下一页（三条终止条件，任一命中即"没有了"）：
   *  1. **本页不满**（received < 页大小）⇒ 到底了（分页通用规则）；
   *  2. **本页没有任何新增**（added ≤ 0）⇒ 到底了
   *     ⚠️ 服务端偶尔会返回与前面重复的条目（置顶/热门重合），去重后可能零新增，
   *        只按"满页"判断就会让按钮赖着不走（用户："怎么点击无法展开了？"——其实早加载完了）；
   *  3. **已达总数**（rcount > 0 且已加载 ≥ rcount）⇒ 到底了。
   * ⚠️ 第 3 条只在 rcount 可信时生效：B 站的 rcount 有时偏大（含已删/折叠），
   *    所以不能反过来"只信 rcount"，要靠下面两个条件兜住。
   */
  private hasMoreReplies(c: ObservableComment, received: number, added: number): boolean {
    if (received < REPLY_PAGE_SIZE) return false;
    if (added <= 0) return false;
    if (c.rcount > 0 && c.replies.length >= c.rcount) return false;
    return true;
  }

  /**
   * 展开/收起二级回复。
   *
   * ⚠️ 展开时**必须总是请求第一页**，不能因为"评论列表自带了几条回复"就直接展开 ——
   *    列表接口只带前 2 条，直接展开的话用户只看到 2 条，而且 `rcount(7) > 已加载(2)` 会让
   *    "展开更多回复"一直挂着（用户反馈："展开后还是会显示展开更多回复，和视频页评论区不一样"）。
   *    视频页评论区就是"点开即拉第一页"，这里对齐它。
   */
  private async toggleReplies(c: ObservableComment): Promise<void> {
    if (c.expanded) {
      c.expanded = false;
      this.repliesVersion++;
      return;
    }
    c.loadingReplies = true;
    this.repliesVersion++;
    try {
      const it = this.item;
      const oid: string = it ? it.commentIdStr : this.dynId_;
      const ctype: number = it ? it.commentType : 17;
      const replies: CommentItem[] | null = await getDynCommentReplies(oid, c.rpid, 1, REPLY_PAGE_SIZE, ctype);
      const got: number = replies ? replies.length : 0;
      const before: number = c.replies.length;
      if (got > 0) {
        // 以服务端第一页为准（列表自带的那几条会被去重合并进来）
        c.updateReplies(replies ?? []);
      }
      const added: number = c.replies.length - before;
      logInfo(`[DynamicDetail] 展开回复: root=${c.rpid} 返回=${got} 新增=${added} 已加载=${c.replies.length} 总数=${c.rcount}`);
      c.replyPage = 1;
      c.hasMoreReplies = this.hasMoreReplies(c, got, added);
      c.expanded = true;
    } catch (e) {
      logWarn(`[DynamicDetail] toggleReplies 异常: ${e}`);
      c.expanded = true;   // 接口异常也让用户看到列表自带的那几条，不要"点了没反应"
    } finally {
      c.loadingReplies = false;
      this.repliesVersion++;
    }
  }

  /**
   * 加载更多二级回复（点开评论展开区里的「展开更多回复」）
   * ⚠️ 本页原先**没有传 onLoadMoreReplies** ⇒ 该按钮点了完全没反应（2026-09-18 用户报"展开更多回复无法展开"）。
   *    展开逻辑与第一页加载同源：都用 item 的 commentType/commentIdStr。
   */
  private async loadMoreReplies(c: ObservableComment): Promise<void> {
    if (c.loadingReplies) return;
    c.loadingReplies = true;
    this.repliesVersion++;
    try {
      const it = this.item;
      const oid: string = it ? it.commentIdStr : this.dynId_;
      const ctype: number = it ? it.commentType : 17;
      // 页码由 `replyPage` 推进：展开时（toggleReplies）总是先请求第 1 页并把 replyPage 置 1，
      // 所以这里 +1 就是真正的"下一页"。
      // ⚠️ 别再按"已加载条数 / 页大小"算：接口的页大小可能被服务端改写（实测 ps=30 只回 20），
      //    一算错就会去重请求同一页 ⇒ 现象是"点了没反应"（2026-09-18 连续踩两次）。
      const nextPage: number = (c.replyPage > 0 ? c.replyPage : 0) + 1;
      logInfo(`[DynamicDetail] 展开更多回复: oid=${oid} type=${ctype} root=${c.rpid} pn=${nextPage} 已加载=${c.replies.length} 总数=${c.rcount}`);
      const more: CommentItem[] | null = await getDynCommentReplies(oid, c.rpid, nextPage, REPLY_PAGE_SIZE, ctype);
      const list: CommentItem[] = more ?? [];
      const before: number = c.replies.length;
      if (list.length > 0) {
        // updateReplies 是"新 + 旧 去重合并"，正好用来追加下一页
        c.updateReplies(list);
        c.replyPage = nextPage;
      }
      const added: number = c.replies.length - before;
      logInfo(`[DynamicDetail] 加载下一页回复: pn=${nextPage} 返回=${list.length} 新增=${added} 已加载=${c.replies.length} 总数=${c.rcount}`);
      c.hasMoreReplies = this.hasMoreReplies(c, list.length, added);
    } catch (e) {
      logWarn(`[DynamicDetail] loadMoreReplies 异常: ${e}`);
    } finally {
      c.loadingReplies = false;
      this.repliesVersion++;
    }
  }

  /** 评论点赞（乐观更新 + 失败回滚） */
  private async likeComment(c: ObservableComment): Promise<void> {
    if (!this.hasLogin()) {
      promptAction.showToast({ message: '登录后才能点赞', duration: 1500 });
      this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
      return;
    }
    const it = this.item;
    const oid: string = it ? it.commentIdStr : this.dynId_;
    const ctype: number = it ? it.commentType : 17;
    const target: boolean = c.action !== 1;
    const prevAction: number = c.action;
    const prevLike: number = c.like;
    c.action = target ? 1 : 0;
    c.like = Math.max(0, prevLike + (target ? 1 : -1));
    this.repliesVersion++;
    try {
      const res: CommentLikeResult = await setDynCommentLike(oid, c.rpid, target, ctype);
      if (!res.ok) {
        c.action = prevAction;
        c.like = prevLike;
        this.repliesVersion++;
        promptAction.showToast({ message: res.message, duration: 1800 });
      }
    } catch (e) {
      c.action = prevAction;
      c.like = prevLike;
      this.repliesVersion++;
      logWarn(`[DynamicDetail] likeComment 异常: ${e}`);
    }
  }

  /** 设置输入条目标（点击某条评论的「回复」） */
  private setReplyTarget(c: ObservableComment, rootRpid: number): void {
    this.replyRoot = rootRpid;
    this.replyParent = c.rpid;
    this.replyTargetName = c.member?.uname ?? '';
    this.entrySheetOn = true;
  }

  /** 发评论 / 回复（输入条回调）；返回 true 表示成功（输入条自行清空） */
  private async submitComment(content: string, pictures: CommentImageDraft[]): Promise<boolean> {
    if (!this.hasLogin()) {
      promptAction.showToast({ message: '登录后才能发评论', duration: 1500 });
      this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
      return false;
    }
    const it = this.item;
    const oid: string = it ? it.commentIdStr : this.dynId_;
    const ctype: number = it ? it.commentType : 17;
    const text: string = content.trim();
    if (!text && pictures.length === 0) {
      promptAction.showToast({ message: '说点什么吧', duration: 1500 });
      return false;
    }
    // 图片：与视频评论一致，先上传换成 pictures json（沿用现有上传接口）
    let picturesJson: string | undefined = undefined;
    if (pictures.length > 0) {
      try {
        picturesJson = await this.uploadPictures(pictures);
        if (!picturesJson) {
          promptAction.showToast({ message: '图片上传失败', duration: 1800 });
          return false;
        }
      } catch (e) {
        logWarn(`[DynamicDetail] 图片上传异常: ${e}`);
        promptAction.showToast({ message: '图片上传失败', duration: 1800 });
        return false;
      }
    }
    try {
      const res: AddCommentResult = await addDynComment(oid, text, this.replyRoot, this.replyParent, picturesJson, ctype);
      if (!res.ok) {
        promptAction.showToast({ message: res.message || '发送失败，请稍后再试', duration: 2000 });
        return false;
      }
      promptAction.showToast({ message: this.replyRoot > 0 ? '回复成功' : '评论成功' });
      this.commentCount++;
      if (this.item) this.item.commentCount = this.commentCount;
      this.replyRoot = 0;
      this.replyParent = 0;
      this.replyTargetName = '';
      this.closeCommentEntry();
      // 重新拉第一页（保证新评论的 rpid/楼层与服务端一致）
      this.commentCaches.clear();
      this.commentRequests.clear();
      this.loadComments(true);
      return true;
    } catch (e) {
      logError(`[DynamicDetail] addDynComment 异常: ${e}`);
      promptAction.showToast({ message: '发送失败，请稍后再试', duration: 2000 });
      return false;
    }
  }

  /** 上传评论图片：与视频评论走同一套（逐张上传换 URL，再拼 pictures json） */
  private async uploadPictures(drafts: CommentImageDraft[]): Promise<string> {
    const imgs: string[] = [];
    for (const d of drafts) {
      const up = await uploadCommentImage(d.path, d.mime, d.ext);
      if (!up || !up.url) return '';
      imgs.push(JSON.stringify({ img_src: up.url, img_width: up.width, img_height: up.height }));
    }
    return '[' + imgs.join(',') + ']';
  }

  // ────────────── 互动 ──────────────

  private hasLogin(): boolean {
    return (this.biliCookie ?? '').includes('SESSDATA');
  }

  private async toggleLike(): Promise<void> {
    const it = this.item;
    if (!it) return;
    if (!this.hasLogin()) {
      promptAction.showToast({ message: '登录后才能点赞', duration: 1500 });
      this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
      return;
    }
    if (this.liking_) return;
    this.liking_ = true;
    const st = this.likeState_;
    const target: boolean = !st.liked;
    const prevLiked: boolean = st.liked;
    const prevCount: number = st.count;
    st.liked = target;
    st.count = Math.max(0, prevCount + (target ? 1 : -1));
    try {
      const res: CommentLikeResult = await setDynamicLike(it.idStr, target);
      if (!res.ok) {
        st.liked = prevLiked;
        st.count = prevCount;
        promptAction.showToast({ message: res.message, duration: 1800 });
      } else {
        it.liked = target;
        it.likeCount = st.count;
      }
    } catch (e) {
      st.liked = prevLiked;
      st.count = prevCount;
      promptAction.showToast({ message: '点赞失败，请稍后重试', duration: 1800 });
    } finally {
      this.liking_ = false;
    }
  }

  private openCommentEntry(): void {
    this.replyRoot = 0;
    this.replyParent = 0;
    this.replyTargetName = '';
    this.entrySheetOn = true;
  }

  private scrollToComments(): void {
    if (this.useSplitLayout()) {
      this.openCommentEntry();
      return;
    }
    try {
      const utils = this.getUIContext().getComponentUtils();
      const section = utils.getRectangleById('dynamic-detail-comments-section');
      const header = utils.getRectangleById('dynamic-detail-header');
      const delta = this.getUIContext().px2vp(section.windowOffset.y - header.windowOffset.y - header.size.height);
      if (delta <= TOP_EXTRA_GAP_VP + 8) {
        this.openCommentEntry();
        return;
      }
      this.scroller.scrollTo({ xOffset: 0,
        yOffset: Math.max(0, this.scroller.currentOffset().yOffset + delta - TOP_EXTRA_GAP_VP), animation: true });
    } catch (_) { this.openCommentEntry(); }
  }

  private openForward(): void {
    if (!this.item || this.repostSending) return;
    if (!this.hasLogin()) {
      promptAction.showToast({ message: '登录后才能转发', duration: 1500 });
      this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
      return;
    }
    this.repostVisible = true;
  }

  private async submitForward(): Promise<void> {
    const item = this.item;
    if (!item || this.repostSending) return;
    this.repostSending = true;
    try {
      const result = await repostDynamic(item.idStr, this.repostText);
      if (!result.ok) {
        promptAction.showToast({ message: result.message, duration: 1800 });
        return;
      }
      this.forwardCount++;
      item.forwardCount = this.forwardCount;
      this.repostVisible = false;
      this.repostText = '';
      promptAction.showToast({ message: '转发成功', duration: 1500 });
    } catch (_) {
      promptAction.showToast({ message: '转发失败，请稍后重试', duration: 1800 });
    } finally { this.repostSending = false; }
  }

  @Builder
  RepostComposer() {
    NativeComposerSurface() {
      Column({ space: 16 }) {
        Row() {
          Text('取消').fontSize(16).fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
            .onClick(() => { if (!this.repostSending) this.repostVisible = false; })
          Blank()
          Text('转发动态').fontSize(18).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          Blank()
          Button(this.repostSending ? '发送中' : '转发').id('dynamic-repost-submit')
            .backgroundColor('#D34E7E').enabled(!this.repostSending)
            .onClick(() => { this.submitForward(); })
        }.width('100%')
        TextArea({ text: this.repostText, placeholder: '说点什么吧（选填）' })
          .id('dynamic-repost-editor').width('100%').height(120).maxLength(1000)
          .backgroundColor(Color.Transparent).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          .enabled(!this.repostSending).onChange((value: string) => { this.repostText = value; })
        Text(`@${this.item?.authorName ?? ''}：${this.item?.text || this.item?.video?.title || '动态'}`)
          .width('100%').maxLines(3).fontSize(14).fontColor(this.isDarkMode ? '#C9CDD3' : '#606773')
      }.width('100%').padding(20)
    }
  }

  private async toggleFollow(): Promise<void> {
    const it = this.item;
    if (!it || it.authorMid <= 0) return;
    if (!this.hasLogin()) {
      promptAction.showToast({ message: '登录后才能关注', duration: 1500 });
      this.getUIContext().getRouter().pushUrl({ url: 'pages/QrCodeLoginPage' }).catch(() => {});
      return;
    }
    if (this.followBusy_) return;
    this.followBusy_ = true;
    const target: boolean = !this.following;
    this.following = target;
    try {
      const ok: boolean = await modifyFollow(it.authorMid, target ? 1 : 2);
      if (!ok) {
        this.following = !target;
        promptAction.showToast({ message: '操作失败，请稍后再试', duration: 1800 });
      } else {
        promptAction.showToast({ message: target ? '已关注' : '已取消关注' });
      }
    } catch (e) {
      this.following = !target;
      logWarn(`[DynamicDetail] toggleFollow 异常: ${e}`);
    } finally {
      this.followBusy_ = false;
    }
  }

  // ────────────── 跳转 ──────────────

  private openUpSpace(): void {
    const it = this.item;
    if (!it || !it.authorName) return;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/UpSpacePage',
      params: { mid: it.authorMid, upName: it.authorName, upFace: it.authorFace }
    }).catch(() => {});
  }

  // ────────────── UI ──────────────

  private useSplitLayout(): boolean {
    return this.viewportWidth >= 600 && this.viewportWidth > this.viewportHeight;
  }

  private restoreLayoutScroll(): void {
    if (!this.restoreScrollPending || !this.item) return;
    this.restoreScrollPending = false;
    if (this.useSplitLayout()) {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
      this.bodyScroller.scrollTo({ xOffset: 0, yOffset: this.splitBodyScrollY });
      this.commentsScroller.scrollTo({ xOffset: 0, yOffset: this.splitCommentsScrollY });
    } else {
      this.bodyScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      this.commentsScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      this.scroller.scrollTo({ xOffset: 0, yOffset: this.portraitScrollY });
    }
  }

  private updateScrollIndicator(): void {
    const offset = this.useSplitLayout()
      ? Math.max(Math.abs(this.bodyScroller.currentOffset().yOffset), Math.abs(this.commentsScroller.currentOffset().yOffset))
      : Math.abs(this.scroller.currentOffset().yOffset);
    const want = offset > BACK_TO_TOP_THRESHOLD_VP;
    if (want !== this.showBackToTop) this.showBackToTop = want;
  }

  /** 作者行（头像 + 昵称 + 时间 + 关注） */
  @Builder
  authorRow(it: SpaceDynamicItem) {
    Row() {
      Image(resizeImageUrl(it.authorFace, 120))
        .width(32).height(32)
        .borderRadius(16)
        .objectFit(ImageFit.Cover)
        .backgroundColor('#E8E8E8')
        .onClick(() => { this.openUpSpace(); })
      Column() {
        Text(it.authorName)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          .maxLines(1)
        Text(fmtRelativeTime(it.pubTs))
          .fontSize(11)
          .fontColor(this.isDarkMode ? '#999999' : '#888888')
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 9 })
      .onClick(() => { this.openUpSpace(); })

      if (it.authorMid > 0 && this.followLoaded) {
        FollowGlassButton({ followed: this.following, buttonWidth: 76, buttonHeight: 30, fontSize: 12,
          accent: this.following ? (this.isDarkMode ? '#CCCCCC' : '#666666') : this.customThemeColor,
          textColor: this.following ? (this.isDarkMode ? '#CCCCCC' : '#666666') : this.customThemeColor,
          fill: this.following ? Color.Transparent : themeHexAlpha(this.customThemeColor, 10),
          onActivate: () => this.toggleFollow() })
      } else if (it.authorMid > 0) {
        Row().width(76).height(30)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 内容卡：作者行 + 共用卡片主体（正文/图片/视频/番剧外观与动态页完全一致） */
  @Builder
  contentCard(it: SpaceDynamicItem) {
    Column() {
    PageSurface({ radius: 20 }) {
    Column() {
      this.authorRow(it)
      DynamicCardBody({
        item: it,
        showActions: false,
        like: this.likeState_,
        onToggleLike: () => { this.toggleLike(); },
        // 详情页不传 onTapSelf：卡片本体点了不做事（这里就是详情页）
        onPreview: (urls: string[], thumbIds: string[], index: number,
          ox: number, oy: number, ow: number, oh: number) => {
          this.previewUrls = urls;
          this.previewIndex = index;
          this.previewOriginX = ox;
          this.previewOriginY = oy;
          this.previewOriginW = ow;
          this.previewOriginH = oh;
          this.showPreview = true;
        }
      })
        .margin({ top: 12 })

    }
    .width('100%')
    .padding(12)
    }
    }.width('100%')
  }

  @Builder
  commentsSurface(it: SpaceDynamicItem) {
    PageSurface({ radius: 20 }) {
      Column() {
        Column() { this.commentsHeader(it) }
          .width('100%').padding({ left: 12, right: 12 })
        this.commentsArea(it)
      }.width('100%')
    }
  }

  /** 评论头：数量 + 排序切换 */
  @Builder
  commentsHeader(it: SpaceDynamicItem) {
    Row({ space: 8 }) {
      Text(`评论 ${fmtCount(this.commentCount)}`)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
      Blank()
      Text('按热度')
        .fontSize(12)
        .fontColor(this.commentsSort === 3 ? this.customThemeColor : (this.isDarkMode ? '#999999' : '#888888'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(this.commentsSort === 3 ? themeHexAlpha(this.customThemeColor, 12) : Color.Transparent)
        .onClick(() => { this.switchSort(3); })
      Text('按时间')
        .fontSize(12)
        .fontColor(this.commentsSort === 2 ? this.customThemeColor : (this.isDarkMode ? '#999999' : '#888888'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(12)
        .backgroundColor(this.commentsSort === 2 ? themeHexAlpha(this.customThemeColor, 12) : Color.Transparent)
        .onClick(() => { this.switchSort(2); })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 18, bottom: 4 })
  }

  /** 评论区：气泡列表 + 二级回复缩进 + 加载更多 */
  @Builder
  commentsArea(it: SpaceDynamicItem) {
    Column() {
      if (this.comments.length === 0) {
        Column() {
          if (this.commentsLoading || !this.commentsLoaded) {
            LoadingProgress().width(24).height(24).color(this.customThemeColor)
          } else if (this.commentsError) {
            Text('评论加载失败，点击重试').fontSize(13).fontColor(this.customThemeColor)
              .id('dynamic-comments-retry').onClick(() => { this.loadComments(true); })
          } else {
            Text('还没有评论，来说点什么吧')
              .fontSize(13)
              .fontColor(this.isDarkMode ? '#888888' : '#999999')
          }
        }
        .width('100%')
        .padding({ top: 28, bottom: 28 })
        .alignItems(HorizontalAlign.Center)
      } else {
        // ⚠️ 左右边距只能给一处：本容器 12 内边距 + 组件自带 margin 传 0。
        //    若两边都给（组件 width('100%') + 自带 margin 12），总宽会超出容器 24 ⇒ 右侧被裁
        //    （"评论左右边距不一样"的坑，2026-09-18 两次踩到）
        Column() {
          ForEach(this.comments, (c: ObservableComment) => {
            Column() {
              CommentItemComponent({
                comment: c,
                isLast: false,
                videoDetail: null,
                isExpanded: c.expanded,
                repliesVersion: this.repliesVersion,
                cardMarginVp: 0,
                forceReferenceLayout: true,
                frostedReplyPreview: true,
                replyPreviewDirectReply: true,
                onExpandComment: (target: ObservableComment) => { this.toggleReplies(target); },
                onCollapseComment: () => { this.toggleReplies(c); },
                onLoadMoreReplies: (target: ObservableComment) => { this.loadMoreReplies(target); },
                onReplyTap: (root: number, parent: number, name: string) => {
                  this.replyRoot = root;
                  this.replyParent = parent;
                  this.replyTargetName = name;
                  this.entrySheetOn = true;
                }
              })
            }
            .width('100%')
            // ⭐ key 用稳定的 rpid：回复列表/展开状态由 @ObjectLink（@Track 字段）自己刷新，
            //    把 repliesVersion 拼进 key 会让每次"展开/点赞"都销毁重建整条评论 ⇒ 头像闪
          }, (c: ObservableComment) => `${c.rpid}`)
        }
        .width('100%')
        .padding({ left: 0, right: 0 })
      }

      if (this.comments.length > 0 && this.commentsError) {
        Text('评论加载失败，点击重试').fontSize(13).fontColor(this.customThemeColor)
          .width('100%').textAlign(TextAlign.Center).padding({ top: 14, bottom: 20 })
          .id('dynamic-comments-retry').onClick(() => { this.loadComments(!this.commentCaches.has(this.commentsSort)); })
      } else if (this.comments.length > 0 && (this.commentsHasMore || this.commentsLoading) && this.commentCaches.has(this.commentsSort)) {
        Row() {
          if (this.commentsLoading) {
            LoadingProgress().width(18).height(18).color(this.customThemeColor)
          } else {
            Text('加载更多评论')
              .fontSize(13)
              .fontColor(this.customThemeColor)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 14, bottom: 20 })
        .onClick(() => { this.loadComments(false); })
      } else if (this.comments.length > 0 && !this.commentsLoading && this.commentCaches.has(this.commentsSort)) {
        Text('没有更多评论了')
          .fontSize(12)
          .fontColor(this.isDarkMode ? '#777777' : '#AAAAAA')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 20 })
      }
    }
    .width('100%')
  }

  /** Keep the complete editor above the keyboard using actual available viewport bounds. */
  @Builder
  commentEntryInner() {
    Column() {
      CommentInputBar({
        materialEnabled: false,
        ctrl: this.entryEmoteCtrl,
        onHeightChange: (height: number): void => {
          if (height > 0 && Math.abs(height - this.entryEditorHeight) > 0.5) this.entryEditorHeight = height;
        },
        placeholder: this.replyRoot > 0 ? `回复 @${this.replyTargetName}：` : '说点什么…',
        showImageButton: this.replyRoot === 0,
        autoFocus: true,
        onSend: (content: string, pictures: CommentImageDraft[]) => {
          return this.submitComment(content, pictures);
        }
      })
    }
    .width('100%')
    .height(LayoutPolicy.fixAtIdealSize)
    .backgroundColor(Color.Transparent)
  }

  /** One stationary native scope; material, touch target and icon share the same host coordinates. */
  @Builder
  backToTopButton() {
    DynamicBackToTopButton({
      color: this.floatBtnFollowTheme ? this.customThemeColor : (this.isDarkMode ? Color.White : Color.Black),
      hostWidth: this.viewportWidth, hostHeight: this.viewportHeight,
      buttonX: this.floatBtnX(), buttonY: this.floatBtnY(),
      shown: this.showBackToTop && !this.showPreview,
      buttonScale: this.btnScale,
      onButtonTouch: (event: TouchEvent) =>
        this.handleFloatBtnTouch(event, !this.smartGripEnabled || this.isLandscape)
    })
  }

  @Builder
  HeaderBackControl() {
    Row() {
      HeaderBackButton({ onBack: () => this.getUIContext().getRouter().back() })
    }.width('100%').height(TITLE_BAR_H_VP).padding({ left: 16 }).id('dynamic-detail-header')
      .onAreaChange(() => this.queueTopGapCorrection())
      .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      PageWallpaper()
    Stack() {
      // ── 内容 ──
      HdsNavigation() {
        Scroll(this.scroller) {
          Column() {
            if (this.item) {
              // Orientation changes layout properties only. Keep both cards and every Image mounted.
              Flex({ direction: this.useSplitLayout() ? FlexDirection.Row : FlexDirection.Column,
                alignItems: ItemAlign.Start }) {
                Scroll(this.bodyScroller) {
                  Column() {
                    Column() { this.contentCard(this.item) }
                      .width('100%').id('dd_card')
                      .onAreaChange(() => this.queueTopGapCorrection())
                  }.width('100%')
                    .padding({ top: this.topGap_, bottom: this.useSplitLayout() ? 76 : 0 })
                }
                .width(this.useSplitLayout() ? (this.viewportWidth - 44) * 0.58 : '100%')
                .height(this.useSplitLayout() ? '100%' : LayoutPolicy.fixAtIdealSize)
                .flexShrink(0).id('dynamic-detail-body-pane')
                .enableScrollInteraction(this.useSplitLayout())
                .align(Alignment.TopStart).scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
                .onWillScroll(() => this.updateScrollIndicator())
                Scroll(this.commentsScroller) {
                  Column() {
                    Column() { this.commentsSurface(this.item) }
                      .width('100%').id('dynamic-detail-comments-section')
                  }.width('100%')
                    .padding({ top: this.useSplitLayout() ? this.topGap_ : 0, bottom: 76 })
                }
                .width(this.useSplitLayout() ? (this.viewportWidth - 44) * 0.42 : '100%')
                .height(this.useSplitLayout() ? '100%' : LayoutPolicy.fixAtIdealSize)
                .flexShrink(0).id('dynamic-detail-comments-pane')
                .margin({ left: this.useSplitLayout() ? 12 : 0, top: this.useSplitLayout() ? 0 : 12 })
                .enableScrollInteraction(this.useSplitLayout())
                .align(Alignment.TopStart).scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
                .onWillScroll(() => this.updateScrollIndicator())
              }
              .width('100%').height(this.useSplitLayout() ? '100%' : LayoutPolicy.fixAtIdealSize)
              .padding({ left: this.useSplitLayout() ? 16 : 12, right: this.useSplitLayout() ? 16 : 12 })
            } else if (this.err) {
              Column({ space: 10 }) {
                Text(this.err).fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
                Text('点击重试').fontSize(13).fontColor(this.customThemeColor)
                  .onClick(() => { this.loading = true; this.loadDetail(); this.loadComments(true); })
              }.width('100%').padding({ top: this.topGap_ + 60 })
            } else if (!this.item) {
              Column({ space: 10 }) {
                LoadingProgress().width(28).height(28).color(this.customThemeColor)
                Text('加载中...').fontSize(13).fontColor(this.isDarkMode ? '#C9CDD3' : '#50545A')
              }.width('100%').padding({ top: this.topGap_ + 60 })
            }
          }.width('100%').height(this.useSplitLayout() ? '100%' : LayoutPolicy.fixAtIdealSize)
        }
        .width('100%').height('100%').id('dynamic-detail-page-scroll')
        .enableScrollInteraction(!this.useSplitLayout())
        .align(Alignment.TopStart).scrollBar(BarState.Off)
        .edgeEffect(this.useSplitLayout() ? EdgeEffect.None : EdgeEffect.Spring, { alwaysEnabled: true })
        .onWillScroll(() => this.updateScrollIndicator())
      }
      // ★ 顶栏毛玻璃（与聊天页同款）：标题栏自身避开安全区 + 常驻系统材质模糊
      .titleBar({
        avoidLayoutSafeArea: true,
        padding: { start: LengthMetrics.vp(64), end: LengthMetrics.vp(16) },
        style: gradientTitleBarStyle(this.isDarkMode),
        content: {
          stackBuilder: () => { this.HeaderBackControl(); },
          divider: { showType: DividerShowType.OFF },
          title: {
            mainTitle: '动态详情',
            mainTitleSize: TitleSize.TITLE_S
          }
        }
      })
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(true)
      .mode(NavigationMode.Stack)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')

      Column() {
        Blank()
        if (!this.showPreview && this.item) {
          DynamicDetailDock({
            dockWidth: Math.max(280, this.viewportWidth - 32),
            splitLayout: this.useSplitLayout(),
            like: this.likeState_, forwardCount: this.forwardCount, commentCount: this.commentCount,
            onWrite: () => this.openCommentEntry(),
            onLike: () => { this.toggleLike(); },
            onForward: () => this.openForward(),
            onComments: () => this.scrollToComments()
          })
        }
      }
      .padding({ left: 16, right: 16, bottom: this.hideNavigationIndicator ? 8 : 12 })
      .width('100%').height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)


      // ── 回到顶部悬浮按钮（上滑超过阈值才出现，见 BACK_TO_TOP_THRESHOLD_VP）──
      //    ⚠️ 入口走 sheet 时按钮**盖不过它**（sheet 在页面内容之上）⇒ 已把按钮的距底下限
      //       抬到 floatBtnMinBottom()，禁止拖进入口区域。
      this.backToTopButton()

      if (this.entrySheetOn) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column().width('100%').height('100%').backgroundColor('#66000000')
            .opacity(this.entryProgress)
            .onClick(() => this.closeCommentEntry())
          Column() {
            NativeComposerSurface({ rounding: 20 - 8 * this.entryProgress,
              lowerRounding: 20 * (1 - this.entryProgress) }) {
              Scroll() { this.commentEntryInner() }
                .width('100%').height(this.entryFrameHeight()).scrollBar(BarState.Off)
                .opacity(Math.max(0, Math.min(1, (this.entryProgress - 0.15) / 0.65)))
                .backgroundColor(Color.Transparent).clip(true).id('dynamic-comment-composer-scroll')
            }
          }.width(this.entryFrameWidth()).height(this.entryFrameHeight())
            .borderRadius({ topLeft: 20 - 8 * this.entryProgress, topRight: 20 - 8 * this.entryProgress,
              bottomLeft: 20 * (1 - this.entryProgress), bottomRight: 20 * (1 - this.entryProgress) }).clip(true)
            .position({ x: this.entryOrigin[0] * (1 - this.entryProgress),
              y: this.entryOrigin[1] + (this.entryEditorTop() - this.entryOrigin[1]) * this.entryProgress })
            .enabled(!this.entryClosing).id('dynamic-comment-composer-frame')
        }.width('100%').height('100%').zIndex(50).id('dynamic-comment-composer')
      }

      // 图片预览（起点矩形传 0 → 组件内部退化为中心缩放）
      FullImagePreview({
        isShow: $showPreview,
        previewUrls: this.previewUrls,
        thumbIds: [],
        initialIndex: this.previewIndex,
        originX: $previewOriginX,
        originY: $previewOriginY,
        originW: $previewOriginW,
        originH: $previewOriginH,
        immersiveMode: false
      })
    }
    .width('100%')
    .height('100%')
    }.width('100%').height('100%').id('dynamic-detail-root')
      .bindSheet($$this.repostVisible, this.RepostComposer(), {
        backgroundColor: Color.Transparent, height: SheetSize.FIT_CONTENT,
        preferType: SheetType.BOTTOM, showClose: false,
        shouldDismiss: (action: SheetDismiss) => { if (!this.repostSending) action.dismiss(); }
      })
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        const height = Number(area.height);
        if (Math.abs(width - this.viewportWidth) > 1 || Math.abs(height - this.viewportHeight) > 1) {
          const previousSplit = this.useSplitLayout();
          const nextSplit = width >= 600 && width > height;
          if (previousSplit !== nextSplit) {
            if (previousSplit) {
              this.splitBodyScrollY = this.bodyScroller.currentOffset().yOffset;
              this.splitCommentsScrollY = this.commentsScroller.currentOffset().yOffset;
            } else {
              this.portraitScrollY = this.scroller.currentOffset().yOffset;
            }
            this.restoreScrollPending = true;
          }
          this.viewportWidth = width;
          this.viewportHeight = height;
          this.isDragging = false;
          this.dragOffsetX = 0;
          this.dynDetailFloatBtnY = Math.max(this.floatBtnMinBottom(),
            Math.min(this.floatBtnMaxBottom(), this.dynDetailFloatBtnY));
          this.queueTopGapCorrection();
        }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
