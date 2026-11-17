import { FeedAvatarImage } from './FeedAvatarImage';
import { FollowGlassButton } from './FollowGlassButton';
import { getCachedPixelMap } from '../utils/ImageCache';

@Component
export struct PlayerCreatorRow {
  @Prop compact: boolean = false;
  @Prop videoId: string = '';
  @Prop face: string = '';
  @Prop name: string = '';
  @Prop stats: string = '';
  @Prop followed: boolean = false;
  onOpenProfile: () => void = () => {};
  onToggleFollow: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      // In feed mode, leave the blank part of the row to the page's tap gesture.
      // Only the avatar and nickname Text open the creator's profile.
      Row({ space: 10 }) {
        if (this.compact) {
          FeedAvatarImage({ videoId: this.videoId, face: this.face })
            .onClick(() => this.onOpenProfile())
        } else {
          // 详情页简介头部仍按原来的 URL 渲染，不参与连刷的位图交接。
          Image(getCachedPixelMap(this.face) ?? this.face)
            .width(28).height(28).borderRadius(20).objectFit(ImageFit.Cover)
        }
        Column({ space: 3 }) {
          Text(this.name).fontSize(this.compact ? 14 : 13)
            .fontColor(this.compact ? '#FFFFFF' : '#D34E7E').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => this.onOpenProfile())
          if (!this.compact && this.stats) {
            Text(this.stats)
              .fontSize(10).fontColor('#757A81').maxLines(1)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).height(this.compact ? 34 : 28)
        .onClick(() => this.onOpenProfile())
        .hitTestBehavior(this.compact ? HitTestMode.None : HitTestMode.Default)
      FollowGlassButton({ followed: this.followed, buttonWidth: 72, buttonHeight: 26, fontSize: 12,
        accent: this.followed ? '#45494F' : '#D34E7E', fill: this.followed ? '#45494F' : '#D34E7E',
        onActivate: () => this.onToggleFollow() })
    }.width('100%').height(this.compact ? 54 : 62)
  }
}
