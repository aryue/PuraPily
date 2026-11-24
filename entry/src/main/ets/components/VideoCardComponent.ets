import { CoverArtwork, CoverFlight, CoverHomeHost } from './HomeCoverNode';
import { ordinaryCardColor } from '../utils/SurfaceColors';
import { NativeCardGlass } from './NativeCardGlass';
import { RecommendItem } from '../model/RecommendItem';
import { fmtCount } from '../utils/NumberFormat';
import { VideoCardMoreButton } from './VideoCardMoreButton';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { resizeImageUrl } from '../utils/ImageUrl';
import { homeArtworkRetained } from '../utils/HomeArtwork';
import { HomeCardMorph } from '../services/HomeCardMorph';

const ENTRANCE_FALLBACK_MS: number = 750;
const ENTRANCE_COMPLETION_MS: number = 520;
const ENTRANCE_SETTLE_RESTORE_MS: number = 16;

@Reusable
@Component
export struct VideoCardComponent {
  @Prop item: RecommendItem = new RecommendItem();
  /** 封面目标像素宽：卡片实际占宽，由页面按列宽换算后传入（避免直接解码原图） */
  @Prop coverWidth: number = 640;
  @Prop entranceCenterX: number = 0;
  revealedCardIds?: Set<string>;
  onCardClick?: (item: RecommendItem, flight?: CoverFlight) => void;
  onLongPress?: (item: RecommendItem) => void;
  @StorageProp('homeArtworkMask') artworkMask: number = 63;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @State private materialWidth: number = 0;
  @State private materialHeight: number = 0;
  @State private entranceScale: number = 0.2;
  private entranceTimer: number = -1;
  private entranceCompletionTimer: number = -1;
  private entranceSettleTimer: number = -1;
  private entranceRevision: number = 0;
  private entranceRunning: boolean = false;
  private openAfterEntrance: boolean = false;
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @StorageLink('cardFeedbackRevision') feedbackRevision: number = 0;

  @StorageProp('homeMorphFlyingCard') flyingCard: string = '';
  @StorageProp('homeCardMorph') liveMorph: boolean = false;
  private liveHost?: CoverHomeHost;

  private coverArtwork(): CoverArtwork {
    return { id: this.item.id, url: resizeImageUrl(this.item.coverUrl, this.coverWidth),
      count: this.item.playCount, duration: this.durationLabel() };
  }

  private hostFor(art: CoverArtwork): CoverHomeHost {
    const host = new CoverHomeHost(art);
    this.liveHost = host;
    return host;
  }

  aboutToAppear(): void {
    this.prepareEntrance();
  }

  aboutToReuse(params: Record<string, Object>): void {
    if (params.item) this.item = params.item as RecommendItem;
    if (params.entranceCenterX !== undefined) this.entranceCenterX = Number(params.entranceCenterX);
    this.prepareEntrance();
  }

  aboutToRecycle(): void {
    this.clearEntranceTimers();
    this.entranceRevision++;
    this.entranceRunning = false;
    this.openAfterEntrance = false;
  }

  aboutToDisappear(): void {
    this.aboutToRecycle();
  }

  private clearEntranceTimers(): void {
    if (this.entranceTimer >= 0) clearTimeout(this.entranceTimer);
    if (this.entranceCompletionTimer >= 0) clearTimeout(this.entranceCompletionTimer);
    if (this.entranceSettleTimer >= 0) clearTimeout(this.entranceSettleTimer);
    this.entranceTimer = -1;
    this.entranceCompletionTimer = -1;
    this.entranceSettleTimer = -1;
  }

  private prepareEntrance(): void {
    this.entranceScale = this.revealedCardIds && !this.revealedCardIds.has(this.item.id) ? 0.2 : 1;
    if (this.entranceScale === 1) return;
    // A recycled node may keep its previous visible ratio and miss the new item's callback.
    this.entranceTimer = setTimeout(() => {
      this.entranceTimer = -1;
      this.revealEntrance();
    }, ENTRANCE_FALLBACK_MS);
  }

  private revealEntrance(): void {
    const revealed = this.revealedCardIds;
    if (this.entranceScale === 1 || !revealed) return;
    this.clearEntranceTimers();
    if (revealed.has(this.item.id)) {
      this.entranceScale = 1;
      return;
    }
    revealed.add(this.item.id);
    const revision = ++this.entranceRevision;
    this.entranceRunning = true;
    this.getUIContext().animateToImmediately({
      duration: 450,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        this.completeEntrance(revision);
      }
    }, () => {
      this.entranceScale = 1;
    });
    // ArkUI can cancel the tween while a lazy row is being rebuilt. Completion must still be final.
    this.entranceCompletionTimer = setTimeout(() => {
      this.entranceCompletionTimer = -1;
      this.completeEntrance(revision, true);
    }, ENTRANCE_COMPLETION_MS);
  }

  private completeEntrance(revision: number, forceSettle: boolean = false): void {
    if (revision !== this.entranceRevision) return;
    this.clearEntranceTimers();
    if (forceSettle) {
      // The state target is already 1 during the tween. Change it once to invalidate a frozen frame.
      this.entranceScale = 1.0001;
      this.entranceSettleTimer = setTimeout(() => {
        this.entranceSettleTimer = -1;
        if (revision === this.entranceRevision) this.entranceScale = 1;
      }, ENTRANCE_SETTLE_RESTORE_MS);
    } else {
      this.entranceScale = 1;
    }
    this.entranceRunning = false;
    if (this.openAfterEntrance) {
      this.openAfterEntrance = false;
      this.onCardClick?.(this.item, this.liveHost?.flight(this.item.id));
    }
  }

  private openCard(): void {
    // 一镜到底读取已落位的封面矩形。
    this.revealEntrance();
    if (this.entranceRunning) {
      this.openAfterEntrance = true;
      return;
    }
    this.onCardClick?.(this.item, this.liveHost?.flight(this.item.id));
  }

  /** 转场取矩形用：封面节点稳定 id */
  private coverMorphId(): string {
    return HomeCardMorph.cardCoverId(this.item.id);
  }

  /** 快照只截封面图本身，角标/遮罩仍由播放页 overlay 单独画。 */
  private coverMorphImageId(): string {
    return `home-card-cover-image-${this.item.id}`;
  }

  private durationLabel(): string {
    const seconds = Math.max(0, Math.floor(this.item.duration));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private secondaryColor(): string {
    return this.isDarkMode ? (this.videoCardEdgeLight ? '#D0D4DA' : '#A6ADB7') :
      (this.videoCardEdgeLight ? '#363B43' : '#61666D');
  }

  @Builder
  cardSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.videoCardEdgeLight) {
        NativeCardGlass({ surfaceWidth: this.materialWidth, surfaceHeight: this.materialHeight })
          .position({ x: 0, y: 0 })
      }
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.liveMorph && homeArtworkRetained(this.artworkMask, 2)) {
          ForEach([this.coverArtwork()], (art: CoverArtwork) => {
            NodeContainer(this.hostFor(art)).width('100%').height('100%')
          }, (art: CoverArtwork) => JSON.stringify(art))
        } else {
          if (homeArtworkRetained(this.artworkMask, 2)) {
            Image(resizeImageUrl(this.item.coverUrl, this.coverWidth)).width('100%').height('100%').objectFit(ImageFit.Cover)
              .autoResize(true)
              .draggable(false)
              .id(this.coverMorphImageId())
          }
          Column().width('100%').height(36)
            .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#99000000', 1]] })
          Row({ space: 8 }) {
            VideoCoverStat({ icon: $r('app.media.ref_play'), count: this.item.playCount })
            Blank()
            Text(this.durationLabel()).fontSize(10).fontColor('#FFFFFF')
          }.width('100%').padding({ left: 6, right: 6, bottom: 6 })
        }
      }
      .width('100%').aspectRatio(16 / 9)
      .clip(true)
      // 封面是转场动画的起点：点击时按这个 id 取窗口矩形，播放页再按实际视频区插值过来。
      // ⚠️ 不用 sharedTransition —— 播放页的目标矩形依赖布局/画幅，页面创建时还是 1x1。
      .id(this.coverMorphId())
      .visibility(this.flyingCard === this.coverMorphId() ? Visibility.Hidden : Visibility.Visible)
      .backgroundColor(this.isDarkMode ? '#242628' : '#E3E5E7')
      Column({ space: 8 }) {
        Text(this.item.title).fontSize(14).lineHeight(20).maxLines(2).height(40)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C').width('100%')
        Row({ space: 4 }) {
          Image($r('app.media.ref_up')).width(14).height(14).fillColor(this.secondaryColor())
          Text(this.item.ownerName).fontSize(11).fontColor(this.secondaryColor()).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          VideoCardMoreButton({ title: this.item.title,
            videoId: this.item.pgcSeasonId > 0 ? '' : this.item.id, ownerMid: this.item.ownerMid })
        // No uploader/menu still reserves the normal 24vp metadata row.
        }.width('100%').constraintSize({ minHeight: 24 })
      }.width('100%').padding(8).alignItems(HorizontalAlign.Start)
    }
    .width('100%').height(LayoutPolicy.fixAtIdealSize)
    .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
      const width = Number(size.width);
      const height = Number(size.height);
      if (width > 0 && Math.abs(width - this.materialWidth) > 0.5) this.materialWidth = width;
      if (height > 0 && Math.abs(height - this.materialHeight) > 0.5) this.materialHeight = height;
    })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize).borderRadius(HomeCardMorph.CARD_RADIUS).clip(true)
    .backgroundColor(this.videoCardEdgeLight ? Color.Transparent : ordinaryCardColor(this.isDarkMode))
    .clickEffect({ level: 0, scale: 0.9 })
    .onClick(() => this.openCard())
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      if (this.onLongPress) this.onLongPress(this.item);
    }))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.cardSurface()
      }.width('100%').height(LayoutPolicy.fixAtIdealSize)
      .scale({ x: this.entranceScale, y: this.entranceScale, centerX: this.entranceCenterX, centerY: '50%' })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize)
    .visibility(this.feedbackRevision >= 0 && VideoCardFeedback.isDismissed(this.item.id, this.item.ownerMid) ? Visibility.None : Visibility.Visible)
    .onVisibleAreaChange([0], (visible: boolean) => {
      if (visible) this.revealEntrance();
    })
  }
}

@Component
struct VideoCoverStat {
  @Prop icon: Resource = $r('app.media.ref_play');
  @Prop count: number = 0;

  build() {
    Row({ space: 3 }) {
      Image(this.icon).width(14).height(14).fillColor('#FFFFFF')
      Text(fmtCount(this.count)).fontSize(10).fontColor('#FFFFFF')
    }
  }
}
