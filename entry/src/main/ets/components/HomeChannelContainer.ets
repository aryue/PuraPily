/**
 * HomeChannelContainer.ets — 首页频道容器（挂在首页 Tab 下）
 *
 * 频道体系（对齐官方 B 站首页）：
 *   直播 | 推荐 | 热门 | 分区 | 番剧 | 影视
 *
 * - 内容 Tabs 承载全部 6 个频道，分区参与横滑
 * - 频道切换入口 = 右上角胶囊标题（Index 持有），此处不再渲染频道 Tab 条
 * - 与 Index 胶囊标题双向同步：胶囊选择频道 ↔ 容器滑动切换
 *   通过 AppStorage key `homeChannelIndex`（0-5）联动
 * - 顶部刷新路由：refreshHomeFlag → 转发到当前频道的刷新信号
 */
import { HomePage } from '../pages/HomePage';
import { DiscoverPage } from '../pages/DiscoverPage';
import { LivePage } from '../pages/LivePage';
import { PgcChannelPage } from '../pages/PgcChannelPage';
import { RegionChannelPage } from '../pages/RegionChannelPage';
import { HOME_CHANNEL_CURVE, HOME_CHANNEL_DURATION } from '../utils/HomeChannelMotion';
import { FrameCallback } from '@ohos.arkui.UIContext';
import { IReusableInfo } from '@kit.ArkUI';

const HIDDEN_RECOMMEND_CARD_LIMIT: number = 8;
const RECOMMEND_POOL_QUIET_MS: number = 1500;
const RECOMMEND_POOL_BATCH_SIZE: number = 3;
const RECOMMEND_POOL_BATCH_INTERVAL_MS: number = 80;
const RECOMMEND_POOL_IDLE_BUDGET_NS: number = 5_000_000;

class ChannelIdleFrame extends FrameCallback {
  private run: (timeLeftInNano: number) => void;

  constructor(run: (timeLeftInNano: number) => void) {
    super();
    this.run = run;
  }

  onIdle(timeLeftInNano: number): void {
    this.run(timeLeftInNano);
  }
}

/** 频道定义（供 Index 胶囊复用） */
export interface ChannelTabDef {
  index: number;
  name: string;
}

/** 首页频道顺序：0=分类 1=直播 2=首页 3=热门 4=番剧 5=影视 */
export const CHANNEL_TABS: ChannelTabDef[] = [
  { index: 1, name: '直播' },
  { index: 2, name: '推荐' },
  { index: 3, name: '热门' },
  { index: 0, name: '分区' },
  { index: 4, name: '番剧' },
  { index: 5, name: '影视' }
];

export function channelPagerIndex(channel: number): number {
  const index = CHANNEL_TABS.findIndex(item => item.index === channel);
  return index >= 0 ? index : 1;
}

export function channelAtPager(index: number): number {
  return CHANNEL_TABS[index]?.index ?? 2;
}

@Component({ freezeWhenInactive: true })
export struct HomeChannelContainer {
  /** 推荐频道 scroller（由 Index 传入，供 HdsNavigation.bindToScrollable） */
  externalScroller: Scroller = new Scroller();
  /** 热门频道 scroller */
  discoverScroller: Scroller = new Scroller();

  /** 当前频道索引，与 Index 胶囊标题双向同步（默认 2=推荐） */
  @StorageLink('homeChannelIndex') @Watch('onChannelIndexChange') channelIndex: number = 2;
  /** 标题展示进度独立于频道选择，拖动时不会反过来驱动内容跳页。 */
  @StorageLink('homeChannelPosition') channelPosition: number = 2;
  private pagerWidth: number = 0;
  private syncingChannel: boolean = false;
  /** 顶部刷新信号：按当前频道路由 */
  @StorageLink('refreshHomeFlag') @Watch('onRefreshHomeFlag') refreshHomeFlag: number = 0;

  /**
   * ⭐ 「首页点击切换分类」开关（默认关闭）
   * - 关闭（默认）：允许左右横滑切频道（原有手感）
   * - 打开：禁用横滑，只能用顶部胶囊/分类按钮点击切频道
   */
  @StorageLink('homeFilterTapOnly') homeFilterTapOnly: boolean = false;

  private tabController: TabsController = new TabsController();
  @State activeChannel: number = 2;
  private channelInitDone: boolean = false;
  private artworkTransition: boolean = false;
  private artworkReleaseTimer: number = -1;
  private recommendReusePool?: IReusableInfo;
  private recommendReuseCapacity: number = 0;
  private recommendTrimTimer: number = -1;
  private recommendTrimRevision: number = 0;
  private channelTouching: boolean = false;

  private setRecommendReusePool(pool?: IReusableInfo): void {
    this.cancelRecommendPoolTrim();
    this.recommendReusePool = pool;
    this.recommendReuseCapacity = pool?.maxCount ?? 0;
    this.scheduleRecommendPoolTrim();
  }

  private cancelRecommendPoolTrim(): void {
    this.recommendTrimRevision++;
    if (this.recommendTrimTimer !== -1) {
      clearTimeout(this.recommendTrimTimer);
      this.recommendTrimTimer = -1;
    }
  }

  private canTrimRecommendPool(): boolean {
    return this.activeChannel !== 2 && this.activeChannel === this.channelIndex &&
      !this.artworkTransition && !this.channelTouching && AppStorage.get<boolean>('homeFeedActive') === true &&
      (this.recommendReusePool?.maxCount ?? 0) > HIDDEN_RECOMMEND_CARD_LIMIT;
  }

  private scheduleRecommendPoolTrim(): void {
    if (this.recommendTrimTimer !== -1 || !this.canTrimRecommendPool()) return;
    this.queueRecommendPoolTrim(++this.recommendTrimRevision, RECOMMEND_POOL_QUIET_MS);
  }

  private queueRecommendPoolTrim(revision: number, delay: number): void {
    this.recommendTrimTimer = setTimeout(() => {
      this.recommendTrimTimer = -1;
      if (!this.canTrimRecommendPool()) return;
      this.getUIContext().postFrameCallback(new ChannelIdleFrame((timeLeftInNano: number) => {
        if (revision !== this.recommendTrimRevision || !this.canTrimRecommendPool()) return;
        const pool = this.recommendReusePool!;
        if (pool.count <= HIDDEN_RECOMMEND_CARD_LIMIT) return;
        if (timeLeftInNano >= RECOMMEND_POOL_IDLE_BUDGET_NS) {
          // 缩池会同步销毁组件。分批处理离屏节点，避免阻塞下一帧。
          pool.maxCount = Math.max(HIDDEN_RECOMMEND_CARD_LIMIT, pool.count - RECOMMEND_POOL_BATCH_SIZE);
        }
        if (pool.count > HIDDEN_RECOMMEND_CARD_LIMIT && this.canTrimRecommendPool()) {
          this.queueRecommendPoolTrim(revision, RECOMMEND_POOL_BATCH_INTERVAL_MS);
        }
      }));
    }, delay);
  }

  private onChannelTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      if (!this.channelTouching) this.cancelRecommendPoolTrim();
      this.channelTouching = true;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.channelTouching = false;
      this.scheduleRecommendPoolTrim();
    }
  }

  private cancelArtworkRelease(): void {
    if (this.artworkReleaseTimer !== -1) {
      clearTimeout(this.artworkReleaseTimer);
      this.artworkReleaseTimer = -1;
    }
  }

  aboutToDisappear(): void {
    this.cancelArtworkRelease();
    this.cancelRecommendPoolTrim();
  }

  private showArtwork(from: number, to: number = from): void {
    const pool = this.recommendReusePool;
    if ((from === 2 || to === 2) && pool && pool.maxCount !== this.recommendReuseCapacity) {
      pool.maxCount = this.recommendReuseCapacity;
    }
    const mask = (1 << from) | (1 << to);
    // 连续横拖的相邻页通常不变，只有可见频道集合变化时才通知封面。
    if (AppStorage.get('homeArtworkMask') !== mask) {
      AppStorage.setOrCreate('homeArtworkMask', mask);
    }
  }

  aboutToAppear() {
    // 从 AppStorage 恢复上次频道（胶囊可能已在其它入口设置）；默认 2=推荐
    const saved: number = AppStorage.get<number>('homeChannelIndex') ?? 2;
    this.activeChannel = saved >= 0 && saved < CHANNEL_TABS.length ? saved : 2;
    this.channelPosition = channelPagerIndex(this.activeChannel) + 1;
    this.showArtwork(this.activeChannel);
    this.channelInitDone = true;
  }

  /** 点击标题只发出切页指令，标题位置由分页进度更新。 */
  private onChannelIndexChange(): void {
    if (!this.channelInitDone || this.syncingChannel) return;
    const target = this.channelIndex;
    if (target < 0 || target >= CHANNEL_TABS.length) return;
    this.cancelRecommendPoolTrim();
    this.cancelArtworkRelease();
    this.showArtwork(this.activeChannel, target);
    this.tabController.changeIndex(channelPagerIndex(target));
    if (target === this.activeChannel) this.channelPosition = channelPagerIndex(target) + 1;
  }

  /** 顶部刷新：路由到当前频道的刷新信号 */
  private onRefreshHomeFlag(): void {
    if (this.channelIndex === 0) return;
    // 推荐/番剧/影视/分类都监听 refreshHomeFlag，无需转发；
    // 热门/直播各有独立信号，需转发
    if (this.activeChannel === 3) {
      const flag = AppStorage.get<number>('refreshDiscoverFlag') ?? 0;
      AppStorage.set('refreshDiscoverFlag', flag + 1);
    } else if (this.activeChannel === 1) {
      const flag = AppStorage.get<number>('refreshLiveFlag') ?? 0;
      AppStorage.set('refreshLiveFlag', flag + 1);
    }
  }

  /** 完成、回弹或中断时，以实际内容页校准频道和标题。 */
  private onTabsChange(index: number): void {
    const changed = this.activeChannel !== index;
    this.activeChannel = index;
    if (!this.artworkTransition) this.showArtwork(index);
    this.channelPosition = channelPagerIndex(index) + 1;
    if (this.channelIndex !== index) {
      this.syncingChannel = true;
      AppStorage.set('homeChannelIndex', index);
      this.syncingChannel = false;
    }
    if (changed && index !== 1) {
      const signal: number = (AppStorage.get('livePanelCollapseSignal') as number) || 0;
      AppStorage.set('livePanelCollapseSignal', signal + 1);
    }
    this.scheduleRecommendPoolTrim();
  }

  private onTabsGestureSwipe(index: number, event: TabsAnimationEvent): void {
    if (this.pagerWidth <= 0) return;
    this.cancelRecommendPoolTrim();
    const neighbor = index - Math.sign(event.currentOffset);
    if (neighbor >= 0 && neighbor < CHANNEL_TABS.length) {
      this.showArtwork(channelAtPager(index), channelAtPager(neighbor));
    }
    this.channelPosition = Math.max(1, Math.min(CHANNEL_TABS.length, index + 1 - event.currentOffset / this.pagerWidth));
  }

  private onTabsAnimationStart(fromIndex: number, toIndex: number): void {
    this.artworkTransition = true;
    this.cancelRecommendPoolTrim();
    this.cancelArtworkRelease();
    const destination = channelAtPager(toIndex - 1);
    this.showArtwork(channelAtPager(fromIndex), destination);
    // At the tail of the native curve the old page has almost left the viewport.
    // Drop its images while the outgoing subtree can still process a render update.
    this.artworkReleaseTimer = setTimeout(() => {
      this.artworkReleaseTimer = -1;
      this.showArtwork(destination);
    }, HOME_CHANNEL_DURATION - 48);
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: HOME_CHANNEL_DURATION, curve: HOME_CHANNEL_CURVE }, () => {
      this.channelPosition = toIndex;
    });
  }

  build() {
    // 原生 Tabs 顺序由 CHANNEL_TABS 与公开频道编号相互映射。
    // ⭐ 统一 30vp 圆角：外层 Stack 裁剪，使所有频道页（含推荐页轮播背景）滑动切换时呈圆角卡片
    Stack() {
      Tabs({ controller: this.tabController, index: channelPagerIndex(this.activeChannel) }) {
        TabContent() {
          LivePage()
        }
        TabContent() {
          HomePage({ externalScroller: this.externalScroller,
            onCardReusePool: (pool?: IReusableInfo) => this.setRecommendReusePool(pool) })
        }
        TabContent() {
          DiscoverPage({ externalScroller: this.discoverScroller })
        }
        TabContent() {
          RegionChannelPage()
        }
        TabContent() {
          PgcChannelPage({ seasonType: 1, channelIndex: 4 })
        }
        TabContent() {
          PgcChannelPage({ seasonType: 2, channelIndex: 5 })
        }
      }
      .barHeight(0)
      .barPosition(BarPosition.End)
      .vertical(false)
      // ⚠️ 「首页点击切换分类」开关（默认关闭）：
      //    关闭（默认）= 允许左右横滑切频道（原手感）；
      //    打开 = 禁用横滑，只能点顶部胶囊/分类按钮切频道
      .scrollable(!this.homeFilterTapOnly)
      .animationDuration(HOME_CHANNEL_DURATION)
      .animationCurve(HOME_CHANNEL_CURVE)
      // ⭐ 关键：内层 Tabs 默认避让系统安全区（顶部状态栏），会把 TabContent 整体下推；
      // 各频道页（HomePage/DiscoverPage/LivePage/Pgc/Region）内部已自行预留 statusBarHeight，
      // 这里必须扩展到安全区，否则顶部会形成「状态栏 + 页面自带偏移」双重间距
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.pagerWidth = Number(newArea.width);
      })
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => this.onTabsGestureSwipe(index, event))
      .onAnimationStart((fromIndex: number, toIndex: number) => this.onTabsAnimationStart(fromIndex, toIndex + 1))
      .onAnimationEnd((index: number) => {
        this.cancelArtworkRelease();
        this.artworkTransition = false;
        this.onTabsChange(channelAtPager(index));
      })
      .onChange((index: number) => this.onTabsChange(channelAtPager(index)))
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .onTouch((event: TouchEvent) => this.onChannelTouch(event))
  }
}
