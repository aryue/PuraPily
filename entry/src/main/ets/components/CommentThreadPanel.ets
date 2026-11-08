import { FloatingCommentEntry } from './FloatingCommentEntry';
import { VideoDetail, getCommentDetail } from '../api/BilibiliApi';
import { ObservableComment } from '../model/ObservableComment';
import { CommentItemComponent } from './CommentItemComponent';
import { sortCommentReplies } from '../utils/CommentReplySort';
import { secondaryTextColor } from '../utils/SurfaceColors';

/** 播放区域下方的评论详情；独立滚动，不重建背后的评论列表。 */
@Component
export struct CommentThreadPanel {
  @ObjectLink comment: ObservableComment;
  @Prop videoDetail: VideoDetail | null = null;
  @Prop bottomInset: number = 0;
  @Prop @Watch('refreshReplies') refreshVersion: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State replies: ObservableComment[] = [];
  @State total: number = 0;
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State hasMore: boolean = true;
  @State private sortByHeat: boolean = false;
  private page: number = 0;
  private requestVersion: number = 0;
  private alive: boolean = false;
  private scroller: Scroller = new Scroller();
  onClose?: () => void;
  onViewConversation?: (reply: ObservableComment) => void;
  onReply?: (root: number, parent: number, name: string) => void;

  aboutToAppear(): void {
    this.alive = true;
    this.total = this.comment.rcount;
    this.loadReplies(true);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestVersion++;
  }

  private refreshReplies(): void {
    this.loadReplies(true);
  }

  private async loadReplies(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.hasMore)) return;
    const request = ++this.requestVersion;
    const nextPage = reset ? 1 : this.page + 1;
    const root = this.comment.rpid;
    const aid = this.videoDetail?.aid || this.comment.oid;
    this.loading = true;
    this.failed = false;
    const result = await getCommentDetail(aid, root, nextPage, 20);
    if (!this.alive || request !== this.requestVersion || root !== this.comment.rpid) return;
    this.loading = false;
    if (!result) {
      this.failed = true;
      return;
    }
    const merged: ObservableComment[] = reset ? [] : this.replies.slice();
    const seen = new Set<number>(merged.map((reply: ObservableComment) => reply.rpid));
    for (const reply of result.replies) {
      if (!seen.has(reply.rpid)) {
        merged.push(ObservableComment.from(reply));
        seen.add(reply.rpid);
      }
    }
    this.replies = sortCommentReplies(merged, this.sortByHeat);
    this.page = nextPage;
    this.total = Math.max(result.totalCount, merged.length);
    this.comment.rcount = this.total;
    this.hasMore = result.replies.length >= 20 && merged.length < this.total;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      Row() {
        Text('评论详情').fontSize(16).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
        Blank()
        Row() {
          Image($r('app.media.ref_close')).width(18).height(18).fillColor('#909399')
        }.width(36).height(40).justifyContent(FlexAlign.End)
          .onClick(() => { this.onClose?.(); })
      }.width('100%').height(40).padding({ left: 12, right: 12 })
      Divider().color(this.isDarkMode ? '#303133' : '#E3E5E7').strokeWidth(0.5)
      List({ scroller: this.scroller }) {
        ListItem() {
          CommentItemComponent({ comment: this.comment, videoDetail: this.videoDetail,
            isLast: true, showReplyPreview: false, fullContent: true, forceReferenceLayout: true,
            onReplyTap: (_root: number, parent: number, name: string) => {
              this.onReply?.(this.comment.rpid, parent, name);
            } })
        }
        ListItem() {
          Column().width('100%').height(8)
        }
        ListItem() {
          Row() {
            Text(`相关回复共${this.total}条`).fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
            Blank()
            Row({ space: 4 }) {
              Image($r('app.media.ref_menu')).width(16).height(16).fillColor(secondaryTextColor(this.isDarkMode))
              Text(this.sortByHeat ? '按热度' : '按时间').fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
            }.height(40).padding({ left: 8 }).id('comment-thread-sort')
              .onClick(() => {
                this.sortByHeat = !this.sortByHeat;
                this.replies = sortCommentReplies(this.replies, this.sortByHeat);
              })
          }.width('100%').height(40).padding({ left: 12, right: 12 })
        }
        ForEach(this.replies, (reply: ObservableComment, index: number) => {
          ListItem() {
            CommentItemComponent({ comment: reply, videoDetail: this.videoDetail,
              isLast: index === this.replies.length - 1,
              showReplyPreview: false, fullContent: true, forceReferenceLayout: true,
              allowViewConversation: true,
              onViewConversation: (target: ObservableComment) => { this.onViewConversation?.(target); },
              onReplyTap: (_root: number, parent: number, name: string) => {
                this.onReply?.(this.comment.rpid, parent, name);
              } })
          }
        }, (reply: ObservableComment) => reply.rpid.toString())
        ListItem() {
          Row() {
            if (this.loading) {
              LoadingProgress().width(18).height(18).margin({ right: 6 })
            }
            Text(this.loading ? '加载中…' : (this.failed ? '加载失败，点击重试' :
              (this.hasMore ? '点击加载更多回复' : (this.replies.length > 0 ? '没有更多回复了' : '暂无回复'))))
              .fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
          }.width('100%').height(44).justifyContent(FlexAlign.Center)
            .onClick(() => { if (!this.loading && (this.failed || this.hasMore)) this.loadReplies(this.page === 0); })
        }
      }.width('100%').layoutWeight(1).constraintSize({ minHeight: 0 }).scrollBar(BarState.Off)
        .contentEndOffset(56 + this.bottomInset)
        .edgeEffect(EdgeEffect.Spring).id('comment_thread_list')
        .onReachEnd(() => { if (!this.failed) this.loadReplies(); })
    }.width('100%').height('100%')
      FloatingCommentEntry({ bottomInset: this.bottomInset,
        onOpen: () => { this.onReply?.(this.comment.rpid, this.comment.rpid, this.comment.member?.uname ?? ''); } })
    }.width('100%').height('100%').backgroundColor(this.isDarkMode ? '#17181A' : '#FFFFFF')
      .borderRadius({ topLeft: 12, topRight: 12 }).clip(true)
  }
}
