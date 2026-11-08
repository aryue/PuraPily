import { FloatingCommentEntry } from './FloatingCommentEntry';
import { VideoDetail, getCommentDialog } from '../api/BilibiliApi';
import { ObservableComment } from '../model/ObservableComment';
import { CommentItemComponent } from './CommentItemComponent';
import { secondaryTextColor } from '../utils/SurfaceColors';

/** 独立显示服务端对话树，保留背后评论详情的列表位置。 */
@Component
export struct CommentConversationPanel {
  @ObjectLink root: ObservableComment;
  @ObjectLink selected: ObservableComment;
  @Prop videoDetail: VideoDetail | null = null;
  @Prop bottomInset: number = 0;
  @Prop @Watch('refreshConversation') refreshVersion: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State replies: ObservableComment[] = [];
  @State loading: boolean = false;
  @State failed: boolean = false;
  @State errorMessage: string = '';
  @State hasMore: boolean = true;
  private floor: number = 0;
  private requestVersion: number = 0;
  private alive: boolean = false;
  private scroller: Scroller = new Scroller();
  onClose?: () => void;
  onReply?: (root: number, parent: number, name: string) => void;

  aboutToAppear(): void {
    this.alive = true;
    this.loadConversation(true);
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestVersion++;
  }

  private refreshConversation(): void {
    this.loadConversation(true);
  }

  private async loadConversation(reset: boolean = false): Promise<void> {
    if (!reset && (this.loading || !this.hasMore)) return;
    const request = ++this.requestVersion;
    const dialog = this.selected.dialog;
    const cursor = reset ? 0 : this.floor;
    this.loading = true;
    this.failed = false;
    const result = await getCommentDialog(this.videoDetail?.aid || this.root.oid,
      this.root.rpid, dialog, cursor, 20, this.root.type || 1);
    if (!this.alive || request !== this.requestVersion || dialog !== this.selected.dialog) return;
    this.loading = false;
    if (!result.ok) {
      this.failed = true;
      this.errorMessage = result.message;
      return;
    }
    const merged: ObservableComment[] = reset ? [] : this.replies.slice();
    const previousLength = merged.length;
    const seen = new Set<number>(merged.map((reply: ObservableComment) => reply.rpid));
    for (const reply of result.replies) {
      if (!seen.has(reply.rpid)) {
        merged.push(reply.rpid === this.selected.rpid ? this.selected : ObservableComment.from(reply));
        seen.add(reply.rpid);
      }
    }
    this.replies = merged;
    this.floor = result.nextFloor;
    this.hasMore = result.hasMore && result.nextFloor > cursor && merged.length > previousLength;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      Row() {
        Text('对话列表').fontSize(16).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
        Blank()
        Row() {
          Image($r('app.media.ref_close')).width(18).height(18).fillColor('#909399')
        }.width(36).height(40).justifyContent(FlexAlign.End)
          .onClick(() => { this.onClose?.(); })
      }.width('100%').height(40).padding({ left: 12, right: 12 })
      Divider().color(this.isDarkMode ? '#303133' : '#E3E5E7').strokeWidth(0.5)
      List({ scroller: this.scroller }) {
        ForEach(this.replies, (reply: ObservableComment, index: number) => {
          ListItem() {
            CommentItemComponent({ comment: reply, videoDetail: this.videoDetail,
              isLast: index === this.replies.length - 1,
              showReplyPreview: false, fullContent: true, forceReferenceLayout: true,
              onReplyTap: (_root: number, parent: number, name: string) => {
                this.onReply?.(this.root.rpid, parent, name);
              } })
          }
        }, (reply: ObservableComment) => reply.rpid.toString())
        ListItem() {
          Row() {
            if (this.loading) { LoadingProgress().width(18).height(18).margin({ right: 6 }) }
            Text(this.loading ? '加载中…' : (this.failed ? this.errorMessage :
              (this.hasMore ? '点击加载更多对话' : (this.replies.length > 0 ? '没有更多对话了' : '暂无可查看的对话'))))
              .fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
          }.width('100%').height(44).justifyContent(FlexAlign.Center)
            .onClick(() => { if (!this.loading && (this.failed || this.hasMore)) this.loadConversation(this.floor === 0); })
        }
      }.width('100%').layoutWeight(1).constraintSize({ minHeight: 0 }).scrollBar(BarState.Off)
        .contentEndOffset(56 + this.bottomInset)
        .edgeEffect(EdgeEffect.Spring).id('comment_conversation_list')
        .onReachEnd(() => { if (!this.failed) this.loadConversation(); })
    }.width('100%').height('100%')
      FloatingCommentEntry({ placeholder: `回复 @${this.selected.member?.uname ?? ''}`, bottomInset: this.bottomInset,
        onOpen: () => { this.onReply?.(this.root.rpid, this.selected.rpid, this.selected.member?.uname ?? ''); } })
    }.width('100%').height('100%').backgroundColor(this.isDarkMode ? '#17181A' : '#FFFFFF')
      .borderRadius({ topLeft: 12, topRight: 12 }).clip(true)
  }
}
