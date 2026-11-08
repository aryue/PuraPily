import { CommentActionMenu } from './CommentActionMenu';
import { CommentReplySurface } from './CommentReplySurface';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
﻿import { ObservableComment } from '../model/ObservableComment';
import { VideoDetail, setCommentLike, setCommentDislike } from '../api/BilibiliApi';
import { componentUtils, LevelMode, ImmersiveMode } from '@kit.ArkUI';
import { ReplyItemComponent } from './ReplyItemComponent';
import { CommentContentRenderer } from './CommentContentRenderer';
import { TextSelectionDialog } from './TextSelectionDialog';
import { getCachedPixelMap } from '../utils/ImageCache';
import { measureTextLines } from '../utils/TextMeasure';
import { logWarn } from '../utils/Logger';
import { MaterialUtil } from '../utils/MaterialUtil';
import { VibrateUtils } from '../utils/VibrateUtils';
import { fmtCount } from '../utils/NumberFormat';

/**
 * Bilibili CDN 图片缩放辅助：在 URL 后追加 `@Ww` 参数缩放到指定宽度
 */
function avatarUrlResize(url: string, width: number): string {
  if (!url || !url.includes('hdslb.com')) {
    return url;
  }
  // ⚠️ 原实现 `!url.includes('@')`：URL 已带后缀时**整段跳过压缩** → 原图整张解码
  const at: number = url.indexOf('@');
  const base: string = (at > url.lastIndexOf('/') && url.indexOf('?') < 0) ? url.substring(0, at) : url;
  return base + `@${width}w`;
}

/**
 * 评论项组件 - 气泡式展开风格
 * 特点：
 * 1. 点击主评论展开回复
 * 2. 回复以气泡形式显示
 * 3. 气泡有圆角背景和缩进
 * 4. 连接线显示层级关系
 */
@Component
export struct CommentItemComponent {
  /** ⭐ 透传给 CommentContentRenderer 的单图适配框（内容宽 / 高度上限）；只有播放页评论区传非 0 */
  @Prop picBoxW: number = 0;
  @Prop picBoxH: number = 0;
  @ObjectLink comment: ObservableComment;
  @Prop isLast: boolean = false;
  @Prop videoDetail: VideoDetail | null = null;
  @Prop isExpanded: boolean = false;
  @Prop showReplyPreview: boolean = true;
  @Prop fullContent: boolean = false;
  @Prop forceReferenceLayout: boolean = false;
  @Prop frostedReplyPreview: boolean = false;
  @Prop replyPreviewDirectReply: boolean = false;
  @Prop allowViewConversation: boolean = false;
  /**
   * 二级回复版本号 —— 这是回复列表**唯一的刷新通道**。
   * ⚠️ 血泪：原先 `@Watch('onRepliesVersionChange')` 挂在了 `isDarkMode` 上，而那个方法**根本不存在**，
   *    所以列表刷新一直只靠"ForEach 的 key 里拼版本号"（key 变 ⇒ 整列重建 ⇒ 头像重新解码会闪）。
   *    2026-09-18 把 key 改成稳定的 rpid 后刷新通道就断了：**数据加载了 3 页、20→40→56，界面纹丝不动**
   *    （用户："点击后还是没有展开更多回复"）。
   *    现在把 @Watch 挂到真正会变的 repliesVersion 上，回调里把数组**浅拷贝换引用**给 @State `replies_`，
   *    ForEach 仍用 rpid 做 key ⇒ **只创建新增项、已有项复用**：既刷新、又不闪。
   */
  @Prop @Watch('onRepliesVersionChange') repliesVersion: number = 0;
  /**
   * 条目左右外边距（vp）。
   * ⭐ 为什么要参数化：组件根节点是 `width('100%')` + 自带 margin，**只有当父容器是 List 时**
   *    交叉轴才会把 margin 算进去（播放页评论区就是 List）。
   *    在 `Scroll + Column` 里用（动态详情页）时，100% 宽 + margin 会超出父容器右侧被裁 ⇒ 左右不对称。
   *    ⇒ Scroll 场景请传 0，由外层容器给左右内边距（**两个只能给一处**）。
   */
  @Prop cardMarginVp: number = 12;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardTransparentStyleVideo') cardTransparentStyleVideo: boolean = false;
  @StorageLink('cardStyleVideoCommentBubble') cardStyleVideoCommentBubble: boolean = true;
  @StorageLink('cardStyleVideoCommentAlign') commentTextAlign: string = 'center';
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('playerFollowTheme') playerFollowTheme: boolean = false;
  /** 二级回复列表的本地数据源（由 onRepliesVersionChange 换引用驱动，见 repliesVersion 注释） */
  @State replies_: ObservableComment[] = [];
  @State isTextExpanded: boolean = false;
  @State reactionPending: boolean = false;
  private shareController: systemShare.ShareController | null = null;
  // ⭐ 长按文本选取弹窗：openCustomDialog 返回的对话框 id
  private commentSelDialogId_: number = -1
  /** ⭐ 评论文本实际容器宽度（vp，onAreaChange 实测；各布局宽度不同） */
  @State contentW: number = 0;
  @State topReplyAvatar: string = '';
  @State topReplyUname: string = '';
  @State topReplyMessage: string = '';
  @State hasTopReply: boolean = false;

  onExpandComment?: (comment: ObservableComment) => void;
  onCollapseComment?: (rpid: number) => void;
  onLoadMoreReplies?: (comment: ObservableComment) => void;
  onReplyTap?: (root: number, parent: number, targetName: string) => void;
  onViewConversation?: (reply: ObservableComment) => void;

  // ⚠️ 不使用 @Reusable（多次尝试后弃用）：本机 SDK 复用池中 @ObjectLink 绑定链无法可靠重建，
  //   嵌套子组件全部标记 @Reusable + aboutToReuse 后仍会间歇性显示上一条评论的配图/文本
  //   （2026-08-31 实测：滚动回收后配图与评论错位）。宁可销毁重建，不可复用出脏数据。

  aboutToAppear(): void {
    this.replies_ = this.comment.replies ? this.comment.replies.slice() : [];
    this.updateTopReply();
  }

  /**
   * 当 repliesVersion 变化时刷新（展开第一页 / 加载更多 / 点赞都会 ++repliesVersion）。
   *
   * ⭐ 两件事：① 换一次 `replies_` 的引用 —— 它是回复列表的数据源，ForEach 用 rpid 做 key，
   *    所以**只有新增项会被创建、已有项（含头像）原样复用**（既不"纹丝不动"、也不"整列重建闪头像"）；
   *    ② 重算"点赞最高的回复"预览。
   * ⚠️ 这段逻辑原先只挂在 `isDarkMode` 上（@Watch 挂错了变量）—— 所以回复列表的刷新一直靠
   *    ForEach 的 key 里拼版本号（整列重建）。2026-09-18 把 key 改稳定后列表就彻底不刷新了。
   */
  private onRepliesVersionChange(): void {
    this.replies_ = this.comment.replies ? this.comment.replies.slice() : [];
    this.updateTopReply();
  }

  /**
   * 点赞/取消点赞评论（乐观更新，失败回滚）
   */
  private async toggleCommentLike(): Promise<void> {
    if (this.reactionPending) return;
    this.reactionPending = true;
    const like = this.comment.action !== 1;
    const prevLike = this.comment.like;
    const prevAction = this.comment.action;
    this.comment.like = like ? this.comment.like + 1 : Math.max(0, this.comment.like - 1);
    this.comment.action = like ? 1 : 0;
    try { VibrateUtils.vibrateTime(10); } catch (_e) { /* ignore */ }
    const res = await setCommentLike(this.comment.oid, this.comment.rpid, like, this.comment.type || 1);
    this.reactionPending = false;
    if (res.ok) return;
    // ⭐ 失败回滚，保持展示与服务器一致
    this.comment.like = prevLike;
    this.comment.action = prevAction;
    this.getUIContext().getPromptAction().showToast({
      message: res.code === -101 ? '请先登录' : (res.message || '操作失败，请重试')
    });
  }

  /** 点击头像/昵称 → 打开评论用户的空间页 */
  private openUserSpace(): void {
    this.openCommenterSpace(this.comment);
  }

  private openCommenterSpace(target: ObservableComment): void {
    const mid = parseInt(target.member?.mid ?? '', 10);
    if (!mid || isNaN(mid)) return;
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/UpSpacePage',
      params: {
        mid: mid,
        upName: target.member?.uname ?? '',
        upFace: target.member?.avatar ?? ''
      }
    }).catch((err: Error) => {
      logWarn(`[CommentItem] 打开空间失败: ${err}`);
    });
  }

  // 从 replies 中找出点赞最高的回复，缓存到 topReplyData
  private updateTopReply(): void {
    if (!this.comment.replies || this.comment.replies.length === 0) {
      this.hasTopReply = false;
      return;
    }
    const best = this.comment.replies.reduce((best, r) => (r.like ?? 0) > ((best?.like ?? 0)) ? r : best, this.comment.replies[0]);
    if (best) {
      this.topReplyAvatar = best.member?.avatar ?? '';
      this.topReplyUname = best.member?.uname ?? '';
      this.topReplyMessage = best.content?.message ?? '';
      this.hasTopReply = true;
    } else {
      this.hasTopReply = false;
    }
  }

  /**
   * 判断是否需要"展开全文"按钮：按实测容器宽度测量真实行数，
   * 不同布局（竖屏/竖屏横看/横屏右栏）宽度不同，固定字符估算会误报
   */
  private shouldShowExpandButton(): boolean {
    const msg = this.comment.content?.message ?? '';
    if (!msg) return false;
    // ⭐ 容器宽度未就绪时保守不显示（宁可漏不错，避免"内容完整却有展开按钮"）
    if (this.contentW <= 0) return false;
    return measureTextLines(this.getUIContext(), msg, this.contentW, 13) > 8;
  }

  private async toggleCommentDislike(): Promise<void> {
    if (this.reactionPending) return;
    this.reactionPending = true;
    const previousAction = this.comment.action;
    const previousLike = this.comment.like;
    const dislike = previousAction !== 2;
    this.comment.action = dislike ? 2 : 0;
    if (dislike && previousAction === 1) this.comment.like = Math.max(0, previousLike - 1);
    const result = await setCommentDislike(this.comment.oid, this.comment.rpid, dislike, this.comment.type || 1);
    this.reactionPending = false;
    if (!result.ok) {
      this.comment.action = previousAction;
      this.comment.like = previousLike;
      this.getUIContext().getPromptAction().showToast({ message: result.code === -101 ? '请先登录' : result.message });
    }
  }

  private async shareComment(): Promise<void> {
    const url = `https://www.bilibili.com/video/av${this.comment.oid}/#reply${this.comment.rpid}`;
    this.shareController = new systemShare.ShareController(new systemShare.SharedData({
      utd: 'general.plain-text', content: `${this.comment.member?.uname ?? ''}：${this.comment.content?.message ?? ''}\n${url}`
    }));
    try {
      await this.shareController.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {});
    } catch (error) { logWarn('打开评论分享失败', error); }
  }

  private commentMenuDialogId: number = -1;
  private commentMenuOpening: boolean = false;

  @Builder
  private commentActionMenu() {
    CommentActionMenu({ comment: this.comment,
      onReply: () => this.replyToComment(),
      onClose: () => {
        if (this.commentMenuDialogId >= 0) this.getUIContext().getPromptAction().closeCustomDialog(this.commentMenuDialogId);
        this.commentMenuDialogId = -1;
      } })
  }

  private showCommentMenu(): void {
    if (this.commentMenuOpening || this.commentMenuDialogId >= 0) return;
    this.commentMenuOpening = true;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => { this.commentActionMenu(); },
      alignment: DialogAlignment.Bottom, offset: { dx: 0, dy: 0 }, width: '100%', height: '100%',
      backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE,
      cornerRadius: 0, autoCancel: true, maskColor: '#55000000',
      levelMode: LevelMode.EMBEDDED, immersiveMode: ImmersiveMode.EXTEND,
      onDidDisappear: () => { this.commentMenuDialogId = -1; this.commentMenuOpening = false; }
    }).then((id: number) => {
      this.commentMenuDialogId = id;
      this.commentMenuOpening = false;
    }).catch(() => { this.commentMenuOpening = false; });
  }

  private replyToComment(): void {
    this.onReplyTap?.(this.comment.rpid, this.comment.rpid, this.comment.member?.uname ?? '');
  }

  private formatCommentDate(timestamp: number): string {
    const date = new Date(timestamp * 1000);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  private formatTimeAgo(timestamp: number): string {
    const now = Date.now() / 1000;
    const diff = now - timestamp;

    if (diff < 60) return '刚刚';
    if (diff < 3600) return `${Math.floor(diff / 60)}分钟前`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}小时前`;
    if (diff < 2592000) return `${Math.floor(diff / 86400)}天前`;
    if (diff < 31536000) return `${Math.floor(diff / 2592000)}个月前`;
    return `${Math.floor(diff / 31536000)}年前`;
  }

  private getLevelBgColor(level: number): string {
    if (level >= 6) return '#FFD700'; // 金色 - 最高等级
    if (level >= 4) return '#4169E1'; // 皇家蓝 - 高等级
    if (level >= 2) return '#32CD32'; // 酸橙绿 - 中等
    return '#A9A9A9'; // 深灰色 - 低等级
  }

  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }


  // ⭐ 评论长按文本选取弹窗（可选中 → 复制/搜索）
  @Builder
  textSelectDialog(title: string, text: string) {
    TextSelectionDialog({
      title: title,
      text: text,
      onSearchText: (keyword: string) => {
        if (this.commentSelDialogId_ >= 0) {
          this.getUIContext().getPromptAction().closeCustomDialog(this.commentSelDialogId_);
          this.commentSelDialogId_ = -1;
        }
        this.getUIContext().getRouter().pushUrl({
          url: 'pages/SearchPage',
          params: { keyword: keyword }
        }).catch((err: Error) => {
          logWarn(`[评论] 搜索页跳转失败: ${err}`);
        });
      }
    })
  }

  private showTextSelection(title: string, text: string) {
    if (!text || text.length === 0) return;
    this.getUIContext().getPromptAction().openCustomDialog({
      builder: () => {
        this.textSelectDialog(title, text);
      },
      autoCancel: true,
      // ⭐ 沉浸光感（官方"对话框通道"）：THICK 玻璃 + 无光效（复用面板材质配置）
      backgroundColor: Color.Transparent,
      systemMaterial: MaterialUtil.sheetMaterial()
    }).then((id: number) => {
      this.commentSelDialogId_ = id;
    }).catch((err: Error) => {
      logWarn(`[评论] 文本弹窗打开失败: ${err}`);
    });
  }

  private canViewConversation(): boolean {
    return this.allowViewConversation && this.comment.dialog > 0 && this.comment.dialog !== this.comment.rpid;
  }

  private openReplyPreview(): void {
    if (!this.comment.loadingReplies) this.onExpandComment?.(this.comment);
  }

  private tapPreviewReply(reply: ObservableComment): void {
    if (this.replyPreviewDirectReply) {
      this.onReplyTap?.(this.comment.rpid, reply.rpid, reply.member?.uname ?? '');
    } else {
      this.openReplyPreview();
    }
  }

  private referenceReplyCount(): number {
    return Math.max(this.comment.rcount, this.replies_.length);
  }

  private referenceVisibleReplies(): ObservableComment[] {
    return this.isExpanded ? this.replies_ : this.replies_.slice(0, 2);
  }

  private referenceHasHiddenReplies(): boolean {
    return this.referenceReplyCount() > this.referenceVisibleReplies().length;
  }

  private isUploader(comment: ObservableComment): boolean {
    const ownerMid = this.videoDetail?.owner.mid ?? 0;
    return ownerMid > 0 && (String(comment.mid) === String(ownerMid) || comment.member?.mid === String(ownerMid));
  }

  private referenceHasUploaderReply(): boolean {
    return this.replies_.some((reply: ObservableComment) => this.isUploader(reply));
  }

  @Builder
  ReferenceComment() {
    Column() {
    Row({ space: 12 }) {
      Image(avatarUrlResize(this.comment.member?.avatar ?? '', 96)).width(32).height(32).borderRadius(16)
        .objectFit(ImageFit.Cover).onClick(() => this.openUserSpace())
      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(this.comment.member?.uname ?? '').fontSize(12).fontColor(this.isDarkMode ? '#D6D9DF' : '#61666D').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1).onClick(() => this.openUserSpace())
          Text(`LV${this.comment.member?.level_info?.current_level ?? 0}`).fontSize(8).fontColor('#FFFFFF')
            .backgroundColor('#FF6666').padding({ left: 2, right: 2 }).borderRadius(1)
          if (this.isUploader(this.comment)) {
            Image($r('app.media.comment_up_badge')).width(18).height(12).objectFit(ImageFit.Contain).flexShrink(0)
          }
        }.width('100%')
        Text(this.formatCommentDate(this.comment.ctime) + (this.comment.ipLocation ? `  IP属地：${this.comment.ipLocation}` : ''))
          .fontSize(10).fontColor('#757A81')
        CommentContentRenderer({ content: this.comment.content, fontSize: 14,
          textColor: this.isDarkMode ? '#E7E9EB' : '#18191C', maxLines: this.fullContent || this.isTextExpanded ? 999 : 8,
          isCenter: false, thumbIdPrefix: String(this.comment.rpid), picBoxW: this.picBoxW, picBoxH: this.picBoxH, onTextTap: () => this.replyToComment(),
          onTextLongPress: () => { this.showTextSelection('评论', this.comment.content?.message ?? ''); } })
          .width('100%')
        if (!this.fullContent && (this.comment.content?.message.length ?? 0) > 180) {
          Text(this.isTextExpanded ? '收起' : '展开全文').fontSize(12).fontColor('#00A1D6')
            .width('100%').constraintSize({ minHeight: 28 }).textAlign(TextAlign.Start)
            .onClick(() => { this.isTextExpanded = !this.isTextExpanded; })
        }
        Row() {
          Row({ space: 4 }) {
            Image(this.comment.action === 1 ? $r('app.media.comment_liked') : $r('app.media.comment_like_outline'))
              .width(16).height(16).objectFit(ImageFit.Contain).flexShrink(0)
              // Align the palm/body optically; the thumb is an ascender, not the visual centre.
              .translate({ y: -1.5 })
              .fillColor(this.comment.action === 1 ? '#D34E7E' : '#757A81')
            Text(fmtCount(this.comment.like)).fontSize(11).fontColor('#757A81')
              .maxLines(1).flexShrink(0)
          // Intrinsic count width keeps the next gap anchored to its last digit,
          // including count changes and compact formats such as 1.2万.
          // 8vp trailing space + the next 32vp cell's 8vp inset = 16vp gap.
          }.height(28).padding({ right: 8 })
            .alignItems(VerticalAlign.Center).flexShrink(0)
            .onClick(() => { this.toggleCommentLike(); })
          Row() {
            Image(this.comment.action === 2 ? $r('app.media.comment_disliked') : $r('app.media.comment_dislike_outline'))
              .width(16).height(16).objectFit(ImageFit.Contain)
              .translate({ y: 1.5 })
              .fillColor(this.comment.action === 2 ? '#D34E7E' : '#757A81')
          }.width(32).height(28).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center).flexShrink(0)
            .onClick(() => { this.toggleCommentDislike(); })
          Row() {
            Image($r('app.media.comment_share')).width(16).height(16).objectFit(ImageFit.Contain).fillColor('#757A81')
              .translate({ y: 0.5 })
          }.width(32).height(28).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center).flexShrink(0)
            .onClick(() => { this.shareComment(); })
          Row() {
            Image($r('app.media.comment_reply')).width(16).height(16).objectFit(ImageFit.Contain).fillColor('#757A81')
              .translate({ y: 0.75 })
          }.width(32).height(28).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.Center).flexShrink(0)
            .onClick(() => { this.replyToComment(); })
          if (this.canViewConversation()) {
            Text('查看对话').fontSize(11).fontColor('#757A81').height(28)
              .padding({ left: 4, right: 8 })
              .onClick(() => { this.onViewConversation?.(this.comment); })
          }
          Blank()
          Row() {
            Image($r('app.media.comment_more')).width(16).height(16).objectFit(ImageFit.Contain).fillColor('#757A81')
          }.width(24).height(28).alignItems(VerticalAlign.Center).justifyContent(FlexAlign.End).flexShrink(0)
            .id('comment-more').accessibilityText('评论更多操作')
            .onClick(() => { this.showCommentMenu(); })
        }.width('100%').height(28).alignItems(VerticalAlign.Center).margin({ top: 2 })
        if (this.showReplyPreview && (this.comment.replies.length > 0 || this.comment.rcount > 0)) {
          CommentReplySurface({ frosted: this.frostedReplyPreview }) {
          Column() {
            ForEach(this.referenceVisibleReplies(), (reply: ObservableComment) => {
              Row() {
                CommentContentRenderer({
                  content: reply.content, fontSize: 13,
                  textColor: this.isDarkMode ? '#E7E9EB' : '#18191C',
                  maxLines: this.isExpanded || this.referenceReplyCount() <= 2 ? 999 : 3,
                  textPrefix: reply.member?.uname ?? '', textPrefixSuffix: '：', showPictures: false,
                  prefixIsUp: this.isUploader(reply),
                  onPrefixTap: () => { this.openCommenterSpace(reply); },
                  onTextTap: () => { this.tapPreviewReply(reply); }
                })
              }.width('100%').padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .id(`comment-preview-reply-${reply.rpid}`)
                .onClick(() => { this.tapPreviewReply(reply); })
            }, (reply: ObservableComment) => reply.rpid.toString())
            if (!this.isExpanded && this.referenceHasHiddenReplies()) {
              Row() {
                if (this.referenceHasUploaderReply()) {
                  Text('UP主等人').fontSize(12).fontColor('#757A81').margin({ right: 4 })
                }
                Text(this.comment.loadingReplies ? '加载中…' : `共${this.referenceReplyCount()}条回复 ›`)
                  .fontSize(12).fontColor('#00A1D6')
              }.width('100%').constraintSize({ minHeight: 28 }).padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .onClick(() => { this.openReplyPreview(); })
            } else if (this.isExpanded && this.referenceReplyCount() > 2) {
              Row() {
                Text('收起').fontSize(12).fontColor('#00A1D6')
              }.width('100%').constraintSize({ minHeight: 28 }).padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .onClick(() => { this.onCollapseComment?.(this.comment.rpid); })
              if (this.comment.hasMoreReplies) {
                Row() {
                  Text(this.comment.loadingReplies ? '加载中…' : '更多回复').fontSize(12).fontColor('#00A1D6')
                }.width('100%').constraintSize({ minHeight: 28 }).padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .onClick(() => { if (!this.comment.loadingReplies) this.onLoadMoreReplies?.(this.comment); })
              }
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 6, bottom: 6 })
            .onClick(() => { this.openReplyPreview(); })
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 12, right: 12, top: 14, bottom: 14 }).alignItems(VerticalAlign.Top)
    if (!this.isLast) {
      Divider().color(this.isDarkMode ? '#101214' : '#E3E5E7').strokeWidth(0.5)
    }
    }.width('100%')
  }

  build() {
    this.ReferenceComment()
  }
}
