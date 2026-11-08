import { curves } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { ObservableComment } from '../model/ObservableComment';
import { blacklistUploader, reportComment } from '../api/BilibiliApi';
import { CommentMenuSurface } from './CommentMenuSurface';

/** Shared by comments, replies and conversation rows. Only the handle row drags the panel. */
@Component
export struct CommentActionMenu {
  @ObjectLink comment: ObservableComment;
  onReply: () => void = () => {};
  onClose: () => void = () => {};
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private panelWidth: number = 0;
  @State private actionRowHeight: number = 86;
  @State private offsetY: number = 280;
  @State private pressed: string = '';
  private closing: boolean = false;
  private alive: boolean = true;

  aboutToAppear(): void {
    this.alive = true;
    try {
      const size = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: '加入黑名单', fontSize: 12 });
      this.actionRowHeight = Math.max(86, 66 + this.getUIContext().px2vp(Number(size.height)));
    } catch (_) { this.actionRowHeight = 86; }
    setTimeout(() => {
      if (this.alive && !this.closing) {
        this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => { this.offsetY = 0; });
      }
    }, 32);
  }

  aboutToDisappear(): void { this.alive = false; }

  private close(action: string = ''): void {
    if (this.closing) return;
    this.closing = true;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseIn, onFinish: () => {
      if (!this.alive) return;
      // Capture target data before the host closes the dialog.
      const target = this.comment;
      const reply = this.onReply;
      const context = this.getUIContext();
      this.onClose();
      if (action === 'reply') reply();
      else if (action === 'copy') {
        pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
          target.content?.message ?? '')).then(() => {
          context.getPromptAction().showToast({ message: '已复制' });
        }).catch(() => { context.getPromptAction().showToast({ message: '复制失败，请重试' }); });
      } else if (action === 'blacklist') {
        const mid = Number(target.member?.mid || target.mid);
        if (!Number.isSafeInteger(mid) || mid <= 0) {
          context.getPromptAction().showToast({ message: '无法获取该用户信息' });
          return;
        }
        blacklistUploader(mid).then((ok: boolean) => {
          context.getPromptAction().showToast({ message: ok ? '已加入黑名单' : '加入黑名单失败，请检查登录状态' });
        }).catch(() => { context.getPromptAction().showToast({ message: '加入黑名单失败，请重试' }); });
      } else if (action === 'report') {
        context.getPromptAction().showActionMenu({ title: '举报原因', buttons: [
          { text: '垃圾广告', color: '#D34E7E' }, { text: '人身攻击', color: '#D34E7E' },
          { text: '引战', color: '#D34E7E' }, { text: '剧透', color: '#D34E7E' }, { text: '其他违规内容', color: '#D34E7E' }
        ] }).then(async (result) => {
          const reasons = [1, 7, 4, 5, 0];
          if (result.index < 0 || result.index >= reasons.length) return;
          const message = await reportComment(target.oid, target.rpid, target.type || 1, reasons[result.index]);
          context.getPromptAction().showToast({ message: message });
        }).catch(() => {});
      }
    } }, () => { this.offsetY = 280; });
  }

  private settle(offset: number, velocity: number): void {
    if (offset > 88 || (offset > 16 && velocity > 900)) { this.close(); return; }
    this.getUIContext().animateTo({ duration: 300, curve: curves.springMotion(0.32, 0.86) }, () => { this.offsetY = 0; });
  }

  private actionWidth(label: string): number {
    try {
      const size = this.getUIContext().getMeasureUtils().measureTextSize({ textContent: label, fontSize: 12 });
      return Math.max(64, Math.ceil(this.getUIContext().px2vp(Number(size.width))) + 16);
    } catch (_) { return Math.max(64, label.length * 16 + 16); }
  }

  private panelHeight(): number { return 122 + this.actionRowHeight; }

  @Builder
  private actionButton(label: string, icon: Resource, action: string) {
    Column({ space: 10 }) {
      CommentMenuSurface({ surfaceWidth: 48, surfaceHeight: 48, radius: 24 }) {
        Stack() {
          Image(icon).width(25).height(25).fillColor(this.dark ? '#F2F3F4' : '#25282C')
        }.width('100%').height('100%').borderRadius(24)
          .backgroundColor(this.pressed === action ? (this.dark ? '#24FFFFFF' : '#14000000') : Color.Transparent)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) this.pressed = action;
            else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.pressed = '';
          })
      }
      Text(label).fontSize(12).fontColor(this.dark ? '#F2F3F4' : '#25282C').maxLines(1)
        .width('100%').textAlign(TextAlign.Center).flexShrink(0)
    }.width(this.actionWidth(label)).height(this.actionRowHeight).alignItems(HorizontalAlign.Center).flexShrink(0)
      .id(`comment-menu-${action}`).accessibilityText(label)
      .onClick(() => this.close(action))
  }

  @Builder
  private panelContent() {
    Column() {
      Row() {
        Column().width(34).height(4).borderRadius(2).backgroundColor(this.dark ? '#80FFFFFF' : '#60000000')
      }.width('100%').height(32).justifyContent(FlexAlign.Center)
        .id('comment-menu-drag-handle').accessibilityText('下拉关闭菜单')
        .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.closing) this.offsetY = event.offsetY >= 0 ? event.offsetY : -Math.min(24, -event.offsetY * 0.18);
          })
          .onActionEnd((event: GestureEvent) => this.settle(event.offsetY, event.velocityY))
          .onActionCancel(() => this.settle(0, 0)))
      Scroll() {
        Row({ space: 8 }) {
          this.actionButton('回复', $r('app.media.comment_menu_reply'), 'reply')
          this.actionButton('复制', $r('app.media.comment_menu_copy'), 'copy')
          this.actionButton('举报', $r('app.media.comment_menu_report'), 'report')
          this.actionButton('加入黑名单', $r('app.media.comment_menu_blacklist'), 'blacklist')
        }.padding({ left: 16, right: 16 })
      }.width('100%').height(this.actionRowHeight).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
        .margin({ bottom: 24 }).id('comment-menu-actions')
      CommentMenuSurface({ surfaceWidth: Math.max(0, this.panelWidth - 32), surfaceHeight: 48, radius: 24 }) {
        Button('取消').width('100%').height('100%').fontSize(16)
          .fontColor(this.dark ? '#F2F3F4' : '#25282C').backgroundColor(Color.Transparent)
          .id('comment-menu-cancel').onClick(() => this.close())
      }
    }.width('100%').padding({ bottom: 18 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // A full-window host leaves room above the sheet for the upward rebound.
      Column().width('100%').height('100%').onClick(() => this.close())
        .id('comment-menu-dismiss-area')
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.panelWidth > 0) {
          CommentMenuSurface({ surfaceWidth: this.panelWidth, surfaceHeight: this.panelHeight(),
            bottomExtension: 160, radius: 28, interactive: false }) {
            this.panelContent()
          }
        }
      }.width('100%').height(this.panelHeight() + 160).position({ bottom: -160 }).clip(false)
        .id('comment-menu-sheet').translate({ y: this.offsetY })
    }.width('100%').height('100%').clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.panelWidth) > 0.5) this.panelWidth = width;
      })
  }
}
