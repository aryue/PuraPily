import { ordinaryCardColor } from '../utils/SurfaceColors';
import { NativeCardGlass } from './NativeCardGlass';
import { fmtRelativeTime } from '../utils/TimeFormat';
import { VideoCardMoreButton } from './VideoCardMoreButton';
import { VideoCardFeedback } from '../services/VideoCardFeedback';

/** Shared formatting for horizontal video lists. Missing values stay hidden. */
export function videoListCount(value: number): string {
  if (value >= 100000000) return (value / 100000000).toFixed(1) + '亿';
  if (value >= 10000) return (value / 10000).toFixed(1) + '万';
  return Math.max(0, value).toString();
}

export function videoListPublished(ts: number): string {
  if (ts <= 0) return '';
  const date = new Date(ts * 1000);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const yesterday = new Date(today.getTime());
  yesterday.setDate(yesterday.getDate() - 1);
  if (date.getTime() >= yesterday.getTime() && date.getTime() < today.getTime()) {
    return `昨天 ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }
  return fmtRelativeTime(ts);
}

export function videoListDuration(duration: number): string {
  const seconds = Math.max(0, Math.floor(duration));
  const minutes = Math.floor(seconds / 60);
  const tail = (seconds % 60).toString().padStart(2, '0');
  return minutes >= 60
    ? `${Math.floor(minutes / 60)}:${(minutes % 60).toString().padStart(2, '0')}:${tail}`
    : `${minutes}:${tail}`;
}

/** Layout only: pages own loading, pagination, navigation and item actions. */
@Component
export struct VideoListItem {
  // Hosts with known geometry can avoid a second layout after measuring each row.
  @Prop availableWidth: number = 0;
  @Prop title: string = '';
  @Prop cover: string = '';
  @Prop duration: number = 0;
  @Prop owner: string = '';
  @Prop playCount: number = -1;
  @Prop dateText: string = '';
  @Prop tag: string = '';
  @Prop detailText: string = '';
  @Prop progress: number = -1;
  @Prop selectable: boolean = false;
  @Prop selected: boolean = false;
  @Prop loading: boolean = false;
  @Prop showDivider: boolean = false;
  @Prop customFooter: boolean = false;
  @Prop primaryActionText: string = '播放视频';
  @Prop videoId: string = '';
  @Prop ownerMid: string = '';
  @StorageLink('cardFeedbackRevision') feedbackRevision: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('cardListMargin') cardListMargin: number = 12;
  @State private materialWidth: number = 0;
  @State private materialHeight: number = 0;
  @StorageProp('videoCardEdgeLight') videoCardEdgeLight: boolean = false;
  @State private itemWidth: number = 360;
  onActivate?: () => void;
  onMore?: () => void;
  onHold?: () => void;
  @BuilderParam footer: () => void = this.emptyFooter;

  @Builder
  emptyFooter() {}

  private coverWidth(): number {
    return Math.min(200, Math.max(0, (this.availableWidth > 0 ? this.availableWidth : this.itemWidth) - (this.selectable ? 32 : 0)) * 0.4);
  }

  private rowHeight(): number {
    // Reserve the tag line for every item so mixed tagged/untagged rows stay aligned.
    return Math.max(this.coverWidth() * 9 / 16,
      this.customFooter ? 116 : 98);
  }

  private statsText(): string {
    const play = this.playCount >= 0 ? videoListCount(this.playCount) + '播放' : '';
    return play + (play && this.dateText ? ' · ' : '') + this.dateText;
  }

  private isDismissed(): boolean {
    return this.feedbackRevision >= 0 && VideoCardFeedback.isDismissed(this.videoId, this.ownerMid);
  }

  private secondaryColor(): string {
    return this.isDarkMode ? (this.videoCardEdgeLight ? '#D0D4DA' : '#A6ADB7') :
      (this.videoCardEdgeLight ? '#363B43' : '#61666D');
  }

  @Builder
  skeleton() {
    Row({ space: 10 }) {
      Column().width(this.coverWidth()).height(this.rowHeight())
        .backgroundColor(this.isDarkMode ? '#303234' : '#E3E5E7').borderRadius(4)
      Column({ space: 8 }) {
        Column().width('100%').height(14).backgroundColor(this.isDarkMode ? '#303234' : '#E3E5E7')
        Column().width('70%').height(14).backgroundColor(this.isDarkMode ? '#303234' : '#E3E5E7')
        Blank()
        Column().width('55%').height(12).backgroundColor(this.isDarkMode ? '#303234' : '#E3E5E7')
      }.layoutWeight(1).height(this.rowHeight()).alignItems(HorizontalAlign.Start)
    }.width('100%').height(this.rowHeight()).opacity(0.5)
  }


  build() {
    Column() {
      if (this.loading) {
        this.skeleton()
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.videoCardEdgeLight) {
            NativeCardGlass({ surfaceWidth: this.availableWidth > 0 ? this.availableWidth : this.materialWidth,
              surfaceHeight: this.availableWidth > 0 ? this.rowHeight() : this.materialHeight })
              .position({ x: 0, y: 0 })
          }
        Row({ space: 10 }) {
          if (this.selectable) {
            Stack() {
              if (this.selected) {
                Image($r('app.media.ref_check')).width(16).height(16).fillColor('#FFFFFF')
              }
            }.width(22).height(22).borderRadius(11)
              .border({ width: 1, color: this.selected ? '#FB7299' : '#757A81' })
              .backgroundColor(this.selected ? '#FB7299' : Color.Transparent)
          }
          Stack({ alignContent: Alignment.BottomEnd }) {
            if (this.cover) {
              Image(this.cover).width('100%').height('100%').objectFit(ImageFit.Cover).draggable(false)
            }
            if (this.duration > 0) {
              Text(videoListDuration(this.duration)).fontSize(10).maxFontScale(1).fontColor('#FFFFFF')
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .backgroundColor('#66000000').borderRadius(2).margin(4)
            }
          }.width(this.coverWidth()).height(this.rowHeight()).flexShrink(0)
            .borderRadius(4).clip(true).backgroundColor(this.isDarkMode ? '#242628' : '#E3E5E7')
          Column() {
            Text(this.title).fontSize(16).maxFontScale(1).lineHeight(21).maxLines(2).flexShrink(0)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontColor(this.isDarkMode ? '#F2F4F8' : '#18191C').width('100%')
            Blank()
            if (this.tag) {
              Text(this.tag).fontSize(10).maxFontScale(1).fontColor(this.isDarkMode ? '#FFC2A6' : '#923914').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .border({ width: 0.5, color: '#A65336', radius: 2 }).margin({ bottom: 3 })
            }
            if (this.owner) {
              Row({ space: 4 }) {
                Image($r('app.media.ref_up')).width(14).height(14).fillColor(this.secondaryColor())
                Text(this.owner).fontSize(12).maxFontScale(1).fontColor(this.secondaryColor()).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              }.width('100%').height(17)
            }
            if (this.customFooter) {
              Row({ space: 4 }) {
                Column() { this.footer() }.layoutWeight(1)
                VideoCardMoreButton({ title: this.title, videoId: this.videoId, ownerMid: this.ownerMid, actionText: this.primaryActionText, onActivate: this.onActivate, onMore: this.onMore })
              }.width('100%')
            } else {
              Row({ space: 4 }) {
                if (this.playCount >= 0) {
                  Image($r('app.media.ref_play')).width(14).height(14).fillColor(this.secondaryColor())
                }
                Text(this.detailText || this.statsText()).fontSize(12).maxFontScale(1).fontColor(this.secondaryColor())
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                if (this.progress >= 0) {
                  Stack() {
                    Progress({ value: Math.max(0, Math.min(100, this.progress)), total: 100, type: ProgressType.Ring })
                      .width(22).height(22).color('#FB7299').style({ strokeWidth: 2 })
                    Text(Math.round(Math.max(0, Math.min(100, this.progress))).toString())
                      .fontSize(8).maxFontScale(1).fontColor(this.secondaryColor())
                  }.width(22).height(22)
                }
                VideoCardMoreButton({ title: this.title, videoId: this.videoId, ownerMid: this.ownerMid, actionText: this.primaryActionText, onActivate: this.onActivate, onMore: this.onMore })
              }.width('100%').height(24)
            }
          }.layoutWeight(1).height(this.rowHeight()).alignItems(HorizontalAlign.Start)
        }.width('100%').height(this.rowHeight())
        }.width('100%').height(this.rowHeight())
          .borderRadius(4)
          .backgroundColor(this.videoCardEdgeLight ? Color.Transparent : ordinaryCardColor(this.isDarkMode))
          .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
            if (this.availableWidth > 0 || !this.videoCardEdgeLight) return;
            const width = Number(size.width);
            const height = Number(size.height);
            if (width > 0 && Math.abs(width - this.materialWidth) > 0.5) this.materialWidth = width;
            if (height > 0 && Math.abs(height - this.materialHeight) > 0.5) this.materialHeight = height;
          })
      }
      if (this.showDivider) {
        Divider().strokeWidth(0.5).color(this.isDarkMode ? '#303234' : '#E3E5E7')
          .margin({ top: Math.max(0, this.cardListMargin / 2 - 0.5) })
      }
    }.width('100%').padding({ top: this.cardListMargin / 2, bottom: this.showDivider ? 0 : this.cardListMargin / 2 })
      .visibility(this.isDismissed() ? Visibility.None : Visibility.Visible)
      // Spacing belongs to the page; only the content Stack owns the card surface.
      .backgroundColor(Color.Transparent)
      .onAreaChange((_old: Area, area: Area) => {
        if (this.availableWidth > 0) return;
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.itemWidth) > 0.5) this.itemWidth = width;
      })
      .onClick(() => { if (!this.loading && this.onActivate) this.onActivate(); })
      .gesture(LongPressGesture({ repeat: false }).onAction(() => {
        if (!this.loading && this.onHold) this.onHold();
      }))
  }
}
