import { NativeGlassCapsule } from './NativeGlassCapsule';
import { ObservableDynLike } from '../model/ObservableDynLike';
import { fmtCount } from '../utils/NumberFormat';

/** Separate native interactive capsules, with the real controls inside their title scopes. */
@Component
export struct DynamicDetailDock {
  @Prop dockWidth: number = 328;
  @Prop splitLayout: boolean = false;
  @ObjectLink like: ObservableDynLike;
  @Prop forwardCount: number = 0;
  @Prop commentCount: number = 0;
  @StorageLink('isDarkMode') dark: boolean = true;
  onWrite: () => void = () => {};
  onLike: () => void = () => {};
  onForward: () => void = () => {};
  onComments: () => void = () => {};

  build() {
    Row({ space: 24 }) {
      NativeGlassCapsule({ capsuleWidth: (this.dockWidth - 12) * (this.splitLayout ? 0.58 : 0.5) - 12, capsuleHeight: 42 }) {
        Row({ space: 8 }) {
          Image($r('app.media.comment_reply')).width(21).height(21)
            .fillColor(this.dark ? '#F2F4F8' : '#333333')
          Text('写评论').fontSize(14).maxLines(1).fontColor(this.dark ? '#F2F4F8' : '#333333')
        }.width('100%').height('100%').padding({ left: 16, right: 8 })
          .id('dynamic-comment-entry').onClick(() => this.onWrite())
      }
      NativeGlassCapsule({ capsuleWidth: (this.dockWidth - 12) * (this.splitLayout ? 0.42 : 0.5) - 12, capsuleHeight: 42 }) {
        Row() {
          Column({ space: 0 }) {
            Image(this.like.liked ? $r('app.media.comment_liked') : $r('app.media.comment_like_outline')).width(20).height(20)
              .fillColor(this.like.liked ? '#D34E7E' : (this.dark ? '#F2F4F8' : '#333333'))
            Text(this.like.count > 0 ? fmtCount(this.like.count) : '赞').fontSize(10).maxLines(1)
              .fontColor(this.like.liked ? '#D34E7E' : (this.dark ? '#C9CDD3' : '#606773'))
          }.layoutWeight(1).height(40).justifyContent(FlexAlign.Center)
            .id('dynamic-detail-like').onClick(() => this.onLike())
          Column({ space: 0 }) {
            Image($r('app.media.ref_share')).width(20).height(20)
              .fillColor(this.dark ? '#F2F4F8' : '#333333')
            Text(this.forwardCount > 0 ? fmtCount(this.forwardCount) : '转发').fontSize(10).maxLines(1)
              .fontColor(this.dark ? '#C9CDD3' : '#606773')
          }.layoutWeight(1).height(40).justifyContent(FlexAlign.Center)
            .id('dynamic-detail-forward').onClick(() => this.onForward())
          Column({ space: 0 }) {
            Image($r('app.media.comment_reply')).width(20).height(20)
              .fillColor(this.dark ? '#F2F4F8' : '#333333')
            Text(this.commentCount > 0 ? fmtCount(this.commentCount) : '回复').fontSize(10).maxLines(1)
              .fontColor(this.dark ? '#C9CDD3' : '#606773')
          }.layoutWeight(1).height(40).justifyContent(FlexAlign.Center)
            .id('dynamic-detail-comments').onClick(() => this.onComments())
        }.width('100%').height('100%').padding({ left: 6, right: 6 })
      }
    }.width(this.dockWidth).height(42).padding({ left: 6, right: 6 }).id('dynamic-detail-dock')
  }
}
