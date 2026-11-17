import type { VideoDetail } from '../api/BilibiliApi';
import { CommentDataSource } from '../model/CommentDataSource';
import type { ObservableComment } from '../model/ObservableComment';
import { CommentItemComponent } from './CommentItemComponent';

@Component
export struct PlayerCommentList {
  dataSource: CommentDataSource = new CommentDataSource();
  commentScroller: Scroller = new Scroller();
  fullscreenScroller: Scroller = new Scroller();
  @Prop useFsScroller: boolean = false;
  @Prop hasComments: boolean = false;
  @Prop hasMore: boolean = false;
  @Prop loading: boolean = false;
  @Prop rateLimited: boolean = false;
  @Prop isDarkMode: boolean = false;
  @Prop referenceLayout: boolean = true;
  @Prop accentColor: ResourceColor = 'app.color.color_bilibili_pink';
  @Prop commentSort: number = 2;
  @Prop videoDetail: VideoDetail | null = null;
  @Prop expandedCommentIds: Set<number> = new Set();
  @Prop repliesVersion: number = 0;
  @Prop pictureWidth: number = 0;
  @Prop pictureHeight: number = 0;
  @Prop inRefresh: boolean = false;
  @Prop bottomInset: number = 0;
  @Prop listVisibility: Visibility = Visibility.Visible;
  @Prop listOpacity: number = 1;
  onSort: (sort: number) => void = () => {};
  onRetry: () => void = () => {};
  onOpenThread: (comment: ObservableComment) => void = () => {};
  onCollapse: (rpid: number) => void = () => {};
  onMoreReplies: (comment: ObservableComment) => void = () => {};
  onReply: (root: number, parent: number, name: string) => void = () => {};
  filterFrameOffset: (offset: number) => number = (offset: number) => offset;
  filterScrollOffset: (offset: number, source: ScrollSource) => number = (offset: number) => offset;
  onMore: () => void = () => {};

  @Builder
  commentSortBar() {
    Row() {
      Text(this.commentSort === 2 ? '热门评论' : '最新评论').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
      Blank()
      Text(this.commentSort === 2 ? '☰ 按热度' : '☰ 按时间').fontSize(12).fontColor('#757A81')
        .onClick(() => this.onSort(this.commentSort === 2 ? 1 : 2))
    }.width('100%').height(44).padding({ top: 4, bottom: 4 })
  }

  build() {
    List({ scroller: this.useFsScroller ? this.fullscreenScroller : this.commentScroller }) {
      ListItem() { Column() { this.commentSortBar() }.width('100%').padding({ left: 12, right: 12 }) }
      if (this.hasComments) {
        LazyForEach(this.dataSource, (c: ObservableComment, i: number) => {
          ListItem() {
            Column() {
              CommentItemComponent({
                picBoxW: this.pictureWidth, picBoxH: this.pictureHeight,
                comment: c,
                isLast: i === this.dataSource.totalCount() - 1,
                videoDetail: this.videoDetail,
                isExpanded: this.expandedCommentIds.has(c.rpid),
                repliesVersion: this.repliesVersion,
                onExpandComment: (comment: ObservableComment) => {
                  this.onOpenThread(comment);
                },
                onCollapseComment: (rpid: number) => { this.onCollapse(rpid); },
                onLoadMoreReplies: (comment: ObservableComment) => {
                  this.onMoreReplies(comment);
                },
                onReplyTap: (root: number, parent: number, targetName: string) => {
                  this.onReply(root, parent, targetName);
                }
              })
            }
            .width('100%')
            .padding({ left: this.referenceLayout ? 0 : 12, right: this.referenceLayout ? 0 : 12 })
          }
        }, (c: ObservableComment, i: number) => c.rpid > 0 ? c.rpid.toString() : 'empty_' + i)
        if (this.hasMore) {
          ListItem() {
            Column() {
              Row() {
                if (this.loading) {
                  LoadingProgress().width(16).height(16).color(this.accentColor);
                  Text('加载中...').fontSize(12).fontColor($r('app.color.color_player_text_secondary')).margin({ left: 6 });
                } else {
                  Text('上拉加载更多').fontSize(12).fontColor($r('app.color.color_player_text_secondary'));
                }
              }
              .width('100%').justifyContent(FlexAlign.Center)
              .padding({ top: 12, bottom: 12 })
            }
            .width('100%').padding({ left: 12, right: 12 })
          }
        }
      } else if (this.loading) {
        ListItem() {
          Column() { LoadingProgress().width(20).height(20).color(this.accentColor); }
          .width('100%').height(80).justifyContent(FlexAlign.Center)
        }
      } else if (this.rateLimited) {
        ListItem() {
          Column() {
            Text('评论被限流，请等待片刻')
              .fontSize(13)
              .fontColor($r('app.color.color_player_text_secondary'))
              .margin({ bottom: 16 });
            Button() {
              Row({ space: 4 }) {
                Image($r('app.media.arrow_clockwise'))
                  .width(14)
                  .height(14)
                  .fillColor(this.accentColor)
                Text('点击重试')
                  .fontSize(12)
                  .fontColor(this.accentColor)
              }
              .alignItems(VerticalAlign.Center)
            }
            .backgroundColor('rgba(251, 114, 153, 0.15)')
            .borderRadius(999)
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => this.onRetry())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 40, bottom: 40, left: 12, right: 12 })
        }
      } else {
        ListItem() {
          Column() {
            Text('暂无评论').fontSize(13).fontColor($r('app.color.color_player_text_secondary'))
            Button('重新加载')
              .fontSize(12)
              .fontColor(this.accentColor)
              .backgroundColor('transparent')
              .border({ width: 1, color: this.accentColor, radius: 4 })
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ top: 12 })
              .onClick(() => this.onRetry())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 40 })
          .padding({ left: 12, right: 12 })
        }
      }
      ListItem() { Column().width('100%').height(0) }
    }
    .listDirection(Axis.Vertical)
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .contentEndOffset(this.inRefresh ? 56 + this.bottomInset : 0)
    // 与动态页一致：List 直接作为 Refresh 子节点，由原生建立滚动联动。
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: this.inRefresh })
    .cachedCount(this.inRefresh ? 4 : 1)

    .visibility(this.listVisibility)
    .opacity(this.listOpacity)
    .onScrollFrameBegin((offset: number) => ({ offsetRemain: this.filterFrameOffset(offset) }))
    .onWillScroll((offset: number, _state: ScrollState, source: ScrollSource) =>
      ({ offsetRemain: this.filterScrollOffset(offset, source) }))
    .onReachEnd(() => {
      if (this.hasMore && !this.loading && this.dataSource.totalCount() > 0) this.onMore();
    })
  }
}
