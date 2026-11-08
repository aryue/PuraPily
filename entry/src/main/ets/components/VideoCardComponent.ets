import { ordinaryCardColor } from '../utils/SurfaceColors';
import { NativeCardGlass } from './NativeCardGlass';
import { RecommendItem } from '../model/RecommendItem';
import { fmtCount } from '../utils/NumberFormat';
import { VideoCardMoreButton } from './VideoCardMoreButton';
import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { resizeImageUrl } from '../utils/ImageUrl';

@Reusable
@Component
export struct VideoCardComponent {
  @Prop item: RecommendItem = new RecommendItem();
  /** 封面目标像素宽：卡片实际占宽，由页面按列宽换算后传入（避免直接解码原图） */
  @Prop coverWidth: number = 640;
  onCardClick?: (item: RecommendItem) => void;
  onLongPress?: (item: RecommendItem) => void;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @State private materialWidth: number = 0;
  @State private materialHeight: number = 0;
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @StorageLink('cardFeedbackRevision') feedbackRevision: number = 0;

  aboutToReuse(params: Record<string, Object>): void {
    if (params.item) this.item = params.item as RecommendItem;
  }

  private durationLabel(): string {
    const seconds = Math.max(0, Math.floor(this.item.duration));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private secondaryColor(): string {
    return this.isDarkMode ? (this.videoCardEdgeLight ? '#D0D4DA' : '#A6ADB7') :
      (this.videoCardEdgeLight ? '#363B43' : '#61666D');
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.videoCardEdgeLight) {
        NativeCardGlass({ surfaceWidth: this.materialWidth, surfaceHeight: this.materialHeight })
          .position({ x: 0, y: 0 })
      }
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(resizeImageUrl(this.item.coverUrl, this.coverWidth)).width('100%').height('100%').objectFit(ImageFit.Cover)
          .draggable(false)
        Column().width('100%').height(36)
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#99000000', 1]] })
        Row({ space: 8 }) {
          VideoCoverStat({ icon: $r('app.media.ref_play'), count: this.item.playCount })
          Blank()
          Text(this.durationLabel()).fontSize(10).fontColor('#FFFFFF')
        }.width('100%').padding({ left: 6, right: 6, bottom: 6 })
      }
      .width('100%').aspectRatio(16 / 9)
      .clip(true)
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
    }.width('100%').height(LayoutPolicy.fixAtIdealSize).borderRadius(4).clip(true)
    .visibility(this.feedbackRevision >= 0 && VideoCardFeedback.isDismissed(this.item.id, this.item.ownerMid) ? Visibility.None : Visibility.Visible)
    .backgroundColor(this.videoCardEdgeLight ? Color.Transparent : ordinaryCardColor(this.isDarkMode))
    .clickEffect({ level: 0, scale: 0.9 })
    .onClick(() => { if (this.onCardClick) this.onCardClick(this.item); })
    .gesture(LongPressGesture({ repeat: false }).onAction(() => {
      if (this.onLongPress) this.onLongPress(this.item);
    }))
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
