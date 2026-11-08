import { PageSurface } from '../components/PageSurface';
import { formatMessageTime } from '../utils/MessageData';
// WhisperPage.ets — 私聊会话列表页（消息页）
import { router, mediaquery, display } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { HdsMiniBarButton } from '../components/infra/HdsMiniBarButton';
import { WhisperChatView } from '../components/WhisperChatView';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { ImGrpcService, ImSessionListResult, ImSession, ImUnreadCount } from '../services/ImGrpcService';
import { ChatEmote, ChatTextSegment } from '../utils/ChatEmote';

/** ⚠️ 分栏左栏宽度可调节范围（左右占比 3:7）：最小 = 屏幕宽×30%（左30%右70%），最大 = 屏幕宽×70%（左70%右30%） */
const SPLIT_MIN_RATIO: number = 0.3;
const SPLIT_MAX_RATIO: number = 0.7;
/** 顶部四类通知入口配置 */
interface NoticeEntry {
  title: string;
  type: number;
  icon: string;
}

const NOTICE_ENTRIES: NoticeEntry[] = [
  { title: '回复我的', type: 1, icon: 'message_on_message_fill' },
  { title: '@我', type: 2, icon: 'at_outline' },
  { title: '收到的赞', type: 3, icon: 'ref_like' },
  { title: '系统通知', type: 4, icon: 'notification' }
];

@Component({ freezeWhenInactive: true })
export struct WhisperPage {
  @Prop contentTopInset: number = 0;
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageProp('referenceLayout') referenceLayout: boolean = true;
  /** 会话列表 */
  @State sessions: ImSession[] = [];
  /** 加载中 */
  @State isLoading: boolean = true;
  /** 加载失败 */
  @State loadError: string = '';
  /** 是否有更多 */
  @State hasMore: boolean = false;
  /** 加载更多中 */
  @State isLoadingMore: boolean = false;
  /** 分页 offset */
  private offsetBytes: Uint8Array | null = null;
  private alive: boolean = false;
  private refreshTimer: number = -1;
  private isRefreshing: boolean = false;
  /** 四类通知未读数（回复/@/赞/系统） */
  @State unreadList: number[] = [0, 0, 0, 0];
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  // ⚠️ 卡片样式/圆角设置（与首页/动态页一致）；消息卡片圆角已固定 40vp 不随此设置
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardListMargin') cardListMargin: number = 24;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 15;
  @StorageLink('cardCustomColor') cardCustomColor: string = '#007DFF';
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = true;
  // ⭐ 「消息页 Tab 自动隐藏」开关（关闭 = 消息页保留悬浮底栏，列表需预留底部空间避让）
  @StorageLink('msgTabAutoHide') msgTabAutoHide: boolean = false;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;

  /** 横屏检测（分栏用，与 DynamicsPage 同方案） */
  @State isLandscape: boolean = false;
  /** 表情表是否已加载（加载完成后会话预览中的 [xxx] 文本替换为表情图片） */
  @State emoteReady: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  /** 分栏右侧当前会话 */
  @State chatTalkerId: number = 0;
  @State chatTalkerName: string = '';
  @State chatTalkerFace: string = '';
  /** 分栏左栏宽度（vp，PanGesture 拖动调整） */
  @State leftWidth: number = 400;
  private dragStartWidth: number = 0;
  /** ⭐ 会话列表 scroller（底栏滚动显隐要取"绝对偏移"来算 delta） */
  private listScroller: Scroller = new Scroller();
  /** ⭐ 底栏滚动显隐：上次滚动偏移 + 触发阈值（对齐首页/动态页的 10vp） */
  private lastScrollY: number = 0;
  private readonly SCROLL_THRESHOLD: number = 10;

  /**
   * 会话列表末尾空白占位的高度（避让悬浮底栏）
   * - 用于**列表最后一个 ListItem**（不是 List.padding）⇒ 随信息流一起滑动，
   *   而不是把内容区静态内缩、看着像"列表在底部被截断"
   * - 底栏可见时（「消息页 Tab 自动隐藏」关闭）= 96 + navIndicatorHeight；
   *   横屏消息页为双栏、底栏恒隐藏，返回 0（末项高度 0，无影响）
   */
  private listBottomPadding(): number {
    if (this.msgTabAutoHide || this.isLandscape) {
      return 0;
    }
    return 96 + this.navIndicatorHeight;
  }

  /**
   * ⭐ 会话列表滚动 → 悬浮底栏显隐（与首页 HomePage / 动态页 DynamicsPage 同款规则）：
   * 下滑（内容上移）delta > 10vp 收起底栏；反向上滑展开；滚回顶部 5vp 内复位展开。
   * ⚠️ 守卫：开关打开（消息页底栏本就恒隐藏）或横屏（双栏、底栏恒隐藏）时一律不接管 —
   *    否则会把本该隐藏的底栏"展开"出来。
   */
  private onMsgListScroll(absoluteOffset: number): void {
    if (this.msgTabAutoHide || this.isLandscape) {
      return;
    }
    const delta: number = absoluteOffset - this.lastScrollY;
    if (absoluteOffset < 5) {
      // 回到顶部：复位展开
      this.lastScrollY = 0;
      AppStorage.set('bottomBarHidden', false);
    } else if (delta > this.SCROLL_THRESHOLD) {
      // 下滑（内容上移）：收起
      this.lastScrollY = absoluteOffset;
      AppStorage.set('bottomBarHidden', true);
    } else if (delta < -this.SCROLL_THRESHOLD) {
      // 上滑（内容下移）：展开
      this.lastScrollY = absoluteOffset;
      AppStorage.set('bottomBarHidden', false);
    }
  }

  async aboutToAppear(): Promise<void> {
    this.alive = true;
    this.refreshTimer = setInterval(() => { this.refreshSessions(); }, 5000);
    this.listenOrientationChange();
    // ⭐ 预加载 B站表情表（带重试等待：冷启动 Cookie 恢复竞态下自动重拉；完成后重渲染会话列表）
    ChatEmote.waitForLoaded().then(() => {
      this.emoteReady = true;
    });
    await this.loadLeftWidth();
    await this.loadSessions();
    this.loadUnread();
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (this.refreshTimer !== -1) { clearInterval(this.refreshTimer); this.refreshTimer = -1; }
    if (this.landscapeListener) {
      this.landscapeListener.off('change');
      this.landscapeListener = null;
    }
  }

  /** 注册媒体查询监听（方向变化，与 DynamicsPage/UpSpacePage 相同方案） */
  private listenOrientationChange(): void {
    try {
      const mediaQuery = this.getUIContext().getMediaQuery();
      this.landscapeListener = mediaQuery.matchMediaSync('(orientation: landscape)');
      this.isLandscape = this.landscapeListener.matches;
      this.landscapeListener.on('change', (result: mediaquery.MediaQueryResult) => {
        const newIsLandscape = result.matches;
        if (this.isLandscape !== newIsLandscape) {
          logInfo(`[WhisperPage] 方向变化: ${newIsLandscape ? '横屏' : '竖屏'}`);
          this.isLandscape = newIsLandscape;
        }
      });
    } catch (err) {
      logWarn(`[WhisperPage] 方向监听注册失败: ${errMsg(err)}`);
    }
  }

  /** 读取持久化的分栏左栏宽度（横屏分栏恢复上次调节） */
  private async loadLeftWidth(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        return;
      }
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      const saved = await pref.get('whisperSplitLeftWidth', 400) as number;
      if (saved > 0) {
        this.leftWidth = saved;
      }
    } catch (err) {
      logWarn(`[WhisperPage] 读取分栏宽度失败: ${errMsg(err)}`);
    }
  }

  /** 保存分栏左栏宽度（拖动结束时调用，Persist Preferences） */
  private async saveLeftWidth(): Promise<void> {
    try {
      const context = AppStorage.get<common.UIAbilityContext>('appContext');
      if (!context) {
        return;
      }
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('whisperSplitLeftWidth', this.leftWidth);
      await pref.flush();
    } catch (err) {
      logWarn(`[WhisperPage] 保存分栏宽度失败: ${errMsg(err)}`);
    }
  }

  /**
   * 拉取四类通知未读数
   */
  private async loadUnread(): Promise<void> {
    try {
      const u: ImUnreadCount = await ImGrpcService.fetchTotalUnread();
      this.unreadList = [u.reply, u.at, u.like, u.sysMsg];
    } catch (err) {
      logWarn(`[WhisperPage] 未读数加载失败: ${errMsg(err)}`);
    }
  }

  /**
   * 进入通知列表页
   */
  private openNotice(type: number): void {
    try {
      router.pushUrl({
        url: 'pages/MsgNoticePage',
        params: {
          'type': type
        }
      });
    } catch (err) {
      logError(`[WhisperPage] 跳转通知页失败: ${errMsg(err)}`);
    }
  }

  /**
   * 拉取会话列表
   */
  private async loadSessions(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
    try {
      const result: ImSessionListResult = await ImGrpcService.fetchSessionList(null);
      this.sessions = result.sessions;
      this.hasMore = result.hasMore;
      this.offsetBytes = result.offsetBytes;
      logInfo(`[WhisperPage] 加载 ${this.sessions.length} 个会话`);
      // ⚠️ 首次进入横屏分栏：默认选中列表第一个（最顶上）的对话。
      //    会话列表异步加载，若不在加载完成后设置 chatTalkerId，右栏 WhisperChatView
      //    会用初始值 0 抢先拉取错误对话（日志：fetchSessionMsgs 先于 fetchSessionList）
      if (this.isLandscape && this.chatTalkerId === 0 && this.sessions.length > 0) {
        const first = this.sessions[0];
        this.chatTalkerId = first.talkerUid;
        this.chatTalkerName = first.sessionName;
        this.chatTalkerFace = first.face;
        logInfo(`[WhisperPage] 横屏分栏默认选中: ${first.sessionName}`);
      }
      // ⚠️ 头像补取不阻塞列表渲染：串行请求太慢会卡住 loading，异步后台补齐
      this.fetchFaces();
    } catch (err) {
      logError(`[WhisperPage] 加载失败: ${errMsg(err)}`);
      this.loadError = '加载失败，请检查网络';
    }
    this.isLoading = false;
  }

  /** 保留已加载的分页，同时刷新最近会话的内容和未读数。 */
  private async refreshSessions(): Promise<void> {
    if (!this.alive || this.isLoading || this.isLoadingMore || this.isRefreshing || this.loadError) { return; }
    this.isRefreshing = true;
    try {
      const result = await ImGrpcService.fetchSessionList(null);
      if (!this.alive) { return; }
      const merged = new Map<number, ImSession>();
      for (let i = 0; i < this.sessions.length; i++) { merged.set(this.sessions[i].talkerUid, this.sessions[i]); }
      for (let i = 0; i < result.sessions.length; i++) {
        const session = result.sessions[i];
        const previous = merged.get(session.talkerUid);
        if (previous) {
          session.face = session.face || previous.face;
          session.sessionName = session.sessionName || previous.sessionName;
        }
        merged.set(session.talkerUid, session);
      }
      const sessions: ImSession[] = [];
      merged.forEach((session: ImSession) => { sessions.push(session); });
      this.sessions = sessions.sort((a: ImSession, b: ImSession): number => {
        if (a.isPinned !== b.isPinned) { return a.isPinned ? -1 : 1; }
        return b.timestamp - a.timestamp;
      });
      this.loadUnread();
      this.fetchFaces();
    } catch (err) {
      logWarn(`[WhisperPage] 刷新会话失败: ${errMsg(err)}`);
    } finally {
      this.isRefreshing = false;
    }
  }

  /**
   * 对 face 为空的会话异步补取头像
   * ⚠️ 串行 30 个 REST 请求太慢（每个含 throttle+WBI，45秒+），改为并发限流（每批5个）
   */
  private async fetchFaces(): Promise<void> {
    const uids = this.sessions.filter((session: ImSession) => !session.face || !session.sessionName)
      .map((session: ImSession) => session.talkerUid);
    if (uids.length === 0) { return; }
    try {
      const profiles = await ImGrpcService.fetchUserProfiles(uids);
      if (!this.alive) { return; }
      const next: ImSession[] = [];
      for (let i = 0; i < this.sessions.length; i++) {
        const current = this.sessions[i];
        const profile = profiles.get(current.talkerUid);
        if (profile) {
          current.sessionName = profile.name || current.sessionName;
          current.face = profile.face || current.face;
        }
        next.push(current);
      }
      this.sessions = next;
      const selected = profiles.get(this.chatTalkerId);
      if (selected) {
        this.chatTalkerName = selected.name || this.chatTalkerName;
        this.chatTalkerFace = selected.face || this.chatTalkerFace;
      }
    } catch (err) {
      logWarn(`[WhisperPage] 会话资料加载失败: ${errMsg(err)}`);
    }
  }

  /**
   * 触底加载更多会话
   */
  private async loadMore(): Promise<void> {
    if (this.isLoading || this.isRefreshing || this.isLoadingMore || !this.hasMore || this.offsetBytes === null) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const result: ImSessionListResult = await ImGrpcService.fetchSessionList(this.offsetBytes);
      this.sessions = [...this.sessions, ...result.sessions];
      this.hasMore = result.hasMore;
      this.offsetBytes = result.offsetBytes;
      // ⚠️ 新加载的会话也异步补头像，不阻塞 isLoadingMore 复位
      this.fetchFaces();
    } catch (err) {
      logWarn(`[WhisperPage] 加载更多失败: ${errMsg(err)}`);
    }
    this.isLoadingMore = false;
  }

  /**
   * 进入会话
   */
  private openWhisper(s: ImSession): void {
    try {
      // ⚠️ 横屏分栏：更新右侧聊天会话（@Watch 触发重新加载）；竖屏：整页跳转
      if (this.isLandscape) {
        this.chatTalkerId = s.talkerUid;
        this.chatTalkerName = s.sessionName;
        this.chatTalkerFace = s.face;
      } else {
        router.pushUrl({
          url: 'pages/WhisperDetailPage',
          params: {
            'talkerId': s.talkerUid,
            'name': s.sessionName,
            'face': s.face
          }
        });
      }
    } catch (err) {
      logError(`[WhisperPage] 跳转失败: ${errMsg(err)}`);
    }
  }

  /**
   * 格式化时间
   */
  private formatTime(ts: number): string {
    return formatMessageTime(ts, true);
  }

  private sessionKey(session: ImSession): string {
    return `${session.talkerUid}_${session.sessionName}_${session.face}_${session.timestamp}_${session.lastMsg}_${session.unread}_${session.isPinned}_${session.isMuted}_${this.emoteReady}`;
  }

  /**
   * 会话卡片背景色（跟随卡片样式选项，与 ProfilePage.getCardItemBg 一致）
   */
  private getCardItemBg(): string {
    if (this.cardTransparentStyle) {
      return this.isDarkMode
        ? `rgba(0,0,0,${this.cardBgOpacity / 100})`
        : `rgba(255,255,255,${this.cardBgOpacity / 100})`;
    }
    return this.isDarkMode ? '#2C2C2C' : '#E8E8E8';
  }

  /**
   * 会话卡片边框色
   */
  private getCardItemBorder(): string {
    if (!this.cardTransparentStyle) {
      return 'rgba(0,0,0,0)';
    }
    if (this.cardBorderFollowTheme) {
      return '#' + this.opacityToHexAlpha(this.cardBorderOpacity) + this.customThemeColor.slice(1);
    }
    return this.isDarkMode
      ? `rgba(255,255,255,${this.cardBorderOpacity / 100})`
      : 'rgba(255,255,255,0.25)';
  }

  /**
   * 透明度(0-100) → 两位十六进制（与首页一致）
   */
  private opacityToHexAlpha(opacity: number): string {
    const val = Math.round(opacity / 100 * 255);
    const hex = val.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  /**
   * 会话预览文字 + 表情（Text + Span/ImageSpan 行内混排，自然换行）
   */
  @Builder
  sessionLastMsg(s: ImSession) {
    Text() {
      ForEach(ChatEmote.parse(s.lastMsg || '暂无消息'), (seg: ChatTextSegment, index: number) => {
        if (seg.emoteUrl) {
          ImageSpan(seg.emoteUrl)
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else {
          Span(seg.text)
        }
      }, (seg: ChatTextSegment, index: number) => `slmsg_${index}`)
    }
    .fontSize(13)
    .fontColor(this.isDarkMode ? '#999999' : '#333333')
    // ⚠️ 最新消息预览最多 8 行，超出省略（卡片高度随之收敛）
    .maxLines(this.referenceLayout ? 1 : 8)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .layoutWeight(1)
  }

  @Builder
  sessionRow(s: ImSession) {
    PageSurface({ radius: this.referenceLayout ? 12 : 40 }) {

    Row() {
      // 头像（有图显示真实头像，无图时用首字占位）
      Stack() {
        Circle()
          .width(46).height(46)
          .fill(this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)')
        if (s.face) {
          Image(s.face)
            .width(46).height(46)
            .borderRadius(23)
            .objectFit(ImageFit.Cover)
        } else {
          // 头像未加载成功时显示默认图标
          Image($r('app.media.tx_old'))
            .width(46).height(46)
            .borderRadius(23)
            .objectFit(ImageFit.Cover)
        }
      }
      .width(46).height(46)

      Column() {
        Row() {
          Text(s.sessionName || `用户${s.talkerUid}`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (s.isPinned) {
            Text('置顶')
              .fontSize(10)
              .fontColor('#FF6699')
              .margin({ left: 6 })
          }
          Text(this.formatTime(s.timestamp))
            .fontSize(11)
            .fontColor(this.isDarkMode ? '#999999' : '#333333')
            .margin({ left: 8 })
        }
        .width('100%')

        Row() {
          this.sessionLastMsg(s)
          if (s.unread > 0) {
            Text(s.unread > 99 ? '99+' : `${s.unread}`)
              .fontSize(10)
              .fontColor('#FFFFFF')
              .backgroundColor('#FF4444')
              .borderRadius(9)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .margin({ top: 4 })
        .alignItems(VerticalAlign.Top)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Center)
    // ⚠️ 消息卡片固定 40vp 圆角，不跟随「卡片圆角」设置（消息页统一胶囊风格）
    .borderRadius(this.referenceLayout ? 0 : 40)
    .onClick(() => {
      this.openWhisper(s);
    })

    }
  }

  /**
   * 会话列表主体（透明透出 Index 全局壁纸 + 占位/通知入口/会话列表）
   * ⚠️ 抽为 @Builder：横屏分栏左栏与竖屏单页共用
   */
  @Builder
  sessionListBody() {
    Stack() {
      // ⚠️ 内容层透明：背景直接透出 Index 全局壁纸层（与首页/我的页一致）
      //    不自绘壁纸——避免 Tab 切换动画带着壁纸层位移（背景被拖动），
      //    且全局层统一处理 builtin/custom/default/custom_color 等壁纸类型
      Column() {
        // ── 会话列表（通知入口已内嵌为首个列表项，随列表滑动）──
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color('#FF6699')
          Text('加载中...').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999').margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError) {
        Column() {
          Text(this.loadError).fontSize(14).fontColor('#FF4444')
          Button('重试')
            .fontSize(14)
            .margin({ top: 12 })
            .onClick(() => {
              this.loadSessions();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.sessions.length === 0) {
        Column() {
          Text('暂无私信')
            .fontSize(14)
            .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
          Text('去个人主页点「发消息」开始聊天')
            .fontSize(12)
            .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: Math.max(8, this.cardListMargin), scroller: this.listScroller }) {
          // ⚠️ 顶部空白占位（不带颜色，露出整页自定义背景）：竖屏 50vp / 横屏 20vp
          ListItem() {
            Column()
              .width('100%')
              .height(this.contentTopInset + (this.isLandscape ? 20 : 50))
          }
          // ⚠️ 通知入口作为首个列表项，随会话列表一起滑动
          ListItem() {
            // ⚠️ 竖屏收拢间距：固定列宽 + columnsGap + 外层 Row 居中（Grid 无 justifyContent）；
            //    横屏分栏保持自适应列数原样
            Row() {
              // ⚠️ Grid 自适应列数：左栏宽(≥400vp)单排 4 个，窄(<400vp)双排 2×2，随分割线拖动实时变化
              Grid() {
              ForEach(NOTICE_ENTRIES, (entry: NoticeEntry, index: number) => {
                GridItem() {
                  Column() {
                    Stack() {
                      // ⚠️ 沉浸光感圆形遮罩（与动态页分类按钮一致）
                      HdsMiniBarButton({
                        barWidth: 40,
                        barHeight: 40,
                        contentPadding: 4,
                        materialType: hdsMaterial.MaterialType.IMMERSIVE,
                        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE,
                        barOverlap: true,
                        barPosition: BarPosition.End,
                        // ⚠️ 必须走组件自带 onTabBarClick：HdsTabs 会消费图标区域的点击事件，
                        //    外层 Column.onClick 收不到（表现为点图标无反应、点文字才有反应）
                        onButtonClick: () => {
                          this.openNotice(entry.type);
                        }
                      }) {
                        Image($r('app.media.' + entry.icon))
                          .width(24).height(24)
                          .objectFit(ImageFit.Contain)
                          .fillColor(this.isDarkMode ? '#FFFFFF' : '#000000')
                      }
                      if (this.unreadList[index] > 0) {
                        Text(this.unreadList[index] > 99 ? '99+' : `${this.unreadList[index]}`)
                          .fontSize(10)
                          .fontColor('#FFFFFF')
                          .backgroundColor('#FF4444')
                          .borderRadius(8)
                          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                          .position({ top: -4, right: -6 })
                      }
                    }
                    .width(40).height(40)

                    Text(entry.title)
                      .fontSize(12)
                      .fontColor(this.isDarkMode ? '#AAAAAA' : '#000000')
                      .margin({ top: 6 })
                  }
                  .onClick(() => {
                    this.openNotice(entry.type);
                  })
                }
              }, (entry: NoticeEntry) => `${entry.type}`)
            }
            // ⚠️ 单排时入口间距 = 列宽(leftWidth/4) - 内容宽(≈52vp)；间距 < 5vp 才切双排（leftWidth < 228）
            // ⚠️ 竖屏用 1fr 均分（固定 '56vp' 列宽会退化成一列竖排），配合收窄宽度+columnsGap 缩小间距
            .columnsTemplate(this.isLandscape
              ? (this.leftWidth / 4 - 52 >= 5 ? '1fr 1fr 1fr 1fr' : '1fr 1fr')
              : '1fr 1fr 1fr 1fr')
            .columnsGap(this.isLandscape ? 0 : 8)
            .rowsGap(10)
            .width(this.isLandscape ? '100%' : 248)
            .padding({ top: 14, bottom: 14 })
        }
        .width('100%')
        .justifyContent(this.isLandscape ? FlexAlign.Start : FlexAlign.Center)
      }
          ForEach(this.sessions, (s: ImSession, index: number) => {
            ListItem() {
              this.sessionRow(s)
            }
            // ⚠️ key 必须包含 face：face 异步补取后 key 变化 → 触发重建渲染头像（否则 skip mark dirty 不刷新）
            //    emoteReady：表情表加载完成后强制重建，刷新 [xxx] 预览文字为表情图片
          }, (s: ImSession) => this.sessionKey(s))
          // ⭐ 列表末尾空白占位：**跟随信息流一起滑动**（原先是 List 的 padding bottom = 静态内缩，
          //    观感像"列表在底部被硬截断"）。高度扣掉 List 的 space —— 它会自动补在两项之间。
          ListItem() {
            Column()
              .width('100%')
              .height(Math.max(0, this.listBottomPadding() - this.cardListMargin))
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .padding({ left: Math.max(14, this.cardListMargin), right: Math.max(14, this.cardListMargin) })
        // ⭐ 滑动联动底栏显隐（与首页/动态页同款；用绝对偏移算 delta）
        .onWillScroll((_dx: number, _dy: number) => {
          this.onMsgListScroll(this.listScroller.currentOffset().yOffset);
        })
        .onReachEnd(() => {
          this.loadMore();
        })
      }
      }
      .width('100%')
      .height('100%')
      // ⚠️ 内容层透明，透出 Index 全局壁纸（与首页/我的页一致）
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ReferenceSessions() {
    List({ space: 8, scroller: this.listScroller }) {
      ListItem() {
        Row() {
          ForEach(NOTICE_ENTRIES, (entry: NoticeEntry, index: number) => {
            Column({ space: 8 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                Column() {
                  PageSurface({ radius: 12 }) {
                    Image($r('app.media.' + entry.icon)).width(25).height(25)
                      .fillColor(index === 0 ? '#41B79B' : index === 2 ? '#D34E7E' : '#00A1D6')
                      .padding(12).width(49).height(49)
                  }
                }.width(49).height(49).id(`message-notice-glass-${entry.type}`)
                if (this.unreadList[index] > 0) {
                  Circle().width(7).height(7).fill('#E34D59')
                }
              }
              Text(entry.title).fontSize(12).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
            }.layoutWeight(1).onClick(() => this.openNotice(entry.type))
          }, (entry: NoticeEntry) => entry.type.toString())
        }.width('100%').padding({ top: 16, bottom: 20 })
      }
      if (this.isLoading) {
        ListItem() { LoadingProgress().width(28).height(28).margin({ top: 70 }).color('#D34E7E') }
      } else if (this.loadError) {
        ListItem() {
          Column({ space: 12 }) {
            Text(this.loadError).fontSize(13).fontColor('#A2A7AE')
            Text('重试').fontSize(14).fontColor('#D34E7E').padding(12).onClick(() => this.loadSessions())
          }.width('100%').padding({ top: 70 })
        }
      } else if (this.sessions.length === 0) {
        ListItem() { Text('暂无私信').fontSize(14).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#757A81').width('100%').textAlign(TextAlign.Center).margin({ top: 70 }) }
      } else {
        ForEach(this.sessions, (session: ImSession) => {
          ListItem() {
            this.sessionRow(session)
          }
        }, (session: ImSession) => this.sessionKey(session))
      }
      ListItem() { Row().height(this.navIndicatorHeight + 12) }
    }.width('100%').height('100%').scrollBar(BarState.Off)
      .padding({ left: 14, right: 14 }).contentStartOffset(this.contentTopInset)
      .onReachEnd(() => this.loadMore())
  }

  build() {
    if (this.referenceLayout && !this.isLandscape) {
      this.ReferenceSessions()
    } else {
    // ⚠️ 手动分栏（Navigation 嵌入 HdsTabs Tab 内容不渲染，改用条件布局 + mediaquery 方向监听）
    if (this.isLandscape) {
      // ⚠️ 手动分栏（对齐官方 RowSplit 视觉：左右栏直接相邻，只有一根细线；拖动热区独立放大不占布局）
      Stack() {
        Row() {
          Column() {
            this.sessionListBody()
          }
          .width(this.leftWidth)
          .height('100%')
          WhisperChatView({
            talkerId: this.chatTalkerId,
            talkerName: this.chatTalkerName,
            talkerFace: this.chatTalkerFace
          })
            .layoutWeight(1)
            .height('100%')
        }
        .width('100%')
        .height('100%')
        // 视觉分割线：只有一根 1vp 细线（position 跟随左栏宽度，不占布局→无背景色带）
        Column()
          .width(1)
          .height('100%')
          .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.20)')
          .position({ x: this.leftWidth - 0.5 })
        // 透明触控热区：20vp（position 跟随分割线，不占布局），PanGesture 拖动
        Column()
          .width(20)
          .height('100%')
          .position({ x: this.leftWidth - 10 })
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal, distance: 0 })
              .onActionStart(() => {
                this.dragStartWidth = this.leftWidth;
              })
              .onActionUpdate((event: GestureEvent) => {
                // ⚠️ 左栏可调范围 = 屏幕宽 30%~70%（左30%右70% ↔ 左70%右30%）
                const disp = display.getDefaultDisplaySync();
                const screenW = disp.width / disp.densityPixels;
                const minW = screenW * SPLIT_MIN_RATIO;
                const maxW = screenW * SPLIT_MAX_RATIO;
                const next = Math.min(maxW, Math.max(minW, this.dragStartWidth + event.offsetX));
                if (next !== this.leftWidth) {
                  this.leftWidth = next;
                }
              })
              .onActionEnd(() => {
                // ⚠️ 拖动结束持久化左栏宽度，下次进入恢复
                this.saveLeftWidth();
              })
          )
      }
      .width('100%')
      .height('100%')
      // ⚠️ 透明背景：透出 Index 全局壁纸层（与首页/我的页一致）；右栏 WhisperChatView 自带底色
    } else {
      this.sessionListBody()
    }
    }
  }
}
