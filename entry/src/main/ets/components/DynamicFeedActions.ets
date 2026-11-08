import { ObservableDynLike } from '../model/ObservableDynLike';
import { fmtCount } from '../utils/NumberFormat';
import { secondaryTextColor } from '../utils/SurfaceColors';

/** 动态信息流操作栏：转发、评论、点赞三等分，点击区域独立。 */
@Component
export struct DynamicFeedActions {
  @ObjectLink like: ObservableDynLike;
  @Prop fullCounts: boolean = false;
  @Prop forwardCount: number = 0;
  @Prop commentCount: number = 0;
  onToggleLike?: () => void;
  @Prop actionId: string = '';
  onComment?: () => void;
  onForward?: () => void;
  // 操作栏原先写死 #9499A0，深色玻璃里发灰、浅色白底上只有约 2.8:1。
  @StorageLink('isDarkMode') isDarkMode: boolean = true;

  private countText(count: number): string {
    return this.fullCounts && count < 10000 ? count.toString() : fmtCount(count);
  }

  private actionColor(): string {
    return secondaryTextColor(this.isDarkMode);
  }

  build() {
    Row() {
      Row({ space: 6 }) {
        Image($r('app.media.ref_share')).width(22).height(22).fillColor(this.actionColor())
        Text(this.forwardCount > 0 ? this.countText(this.forwardCount) : '转发')
          .fontSize(13).fontColor(this.actionColor())
      }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
        .id(`dynamic-forward-${this.actionId}`)
        .onClick(() => { if (this.onForward) this.onForward(); })
      Row({ space: 6 }) {
        Image($r('app.media.comment_reply')).width(22).height(22).fillColor(this.actionColor())
        Text(this.commentCount > 0 ? this.countText(this.commentCount) : '评论')
          .fontSize(13).fontColor(this.actionColor())
      }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
        .id(`dynamic-comment-${this.actionId}`)
        .onClick(() => { if (this.onComment) this.onComment(); })
      Row({ space: 6 }) {
        Image($r('app.media.ref_like'))
          .width(22).height(22)
          .fillColor(this.like.liked ? '#D34E7E' : this.actionColor())
        Text(this.like.count > 0 ? this.countText(this.like.count) : '赞')
          .fontSize(13).fontColor(this.like.liked ? '#D34E7E' : this.actionColor())
      }.layoutWeight(1).height(48).justifyContent(FlexAlign.Center)
        .id(`dynamic-like-${this.actionId}`)
        .onClick(() => { if (this.onToggleLike) this.onToggleLike(); })
    }.width('100%').margin({ top: 8 })
  }
}
