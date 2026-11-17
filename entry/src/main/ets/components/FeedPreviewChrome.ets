import { FeedAvatarImage } from './FeedAvatarImage';
import { FollowGlassButton } from './FollowGlassButton';
import { NativeGlassInput } from './NativeGlassInput';
import { ReferencePlayerAction } from './PlayerEngagementControls';

// Keep the preview and active controls aligned across the page switch.
export const FEED_ACTION_ITEM_W: number = 54;
export const FEED_DANMAKU_MAX_W: number = 360;

export interface FeedChromeInfo {
  id: string
  face: string
  name: string
  title: string
  duration: number
  like: number
  coin: number
  favorite: number
  reply: number
}

@Component
export struct FeedPreviewChrome {
  @Prop chrome: FeedChromeInfo | null = null;
  @Prop showFullscreenHint: boolean = false;
  @Prop fullscreenHintTop: number = 0;
  @Prop bottomInset: number = 0;
  @Prop top: number = 0;
  formatCount: (count: number) => string = (count: number): string => count.toString();
  formatDuration: (seconds: number) => string = (seconds: number): string => seconds.toString();

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showFullscreenHint) {
        Row() {
          Row({ space: 4 }) {
            Image($r('app.media.ref_fullscreen')).width(12).height(12).fillColor('#FFFFFF')
            Text('全屏播放').fontSize(12).fontColor('#FFFFFF')
          }.padding(8).borderRadius(18).backgroundColor('#AA17181A')
        }.width('100%').justifyContent(FlexAlign.Center)
          .position({ x: 0, y: this.fullscreenHintTop })
      }
      // The page supplies a snapshot only when it belongs to the incoming card.
      if (this.chrome) {
        Column({ space: 6 }) {
          Row({ space: 10 }) {
            FeedAvatarImage({ videoId: this.chrome!.id, face: this.chrome!.face })
            Text(this.chrome!.name).fontSize(14).fontColor('#FFFFFF')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            FollowGlassButton({ buttonWidth: 72, buttonHeight: 26, fontSize: 12,
              accent: '#D34E7E', fill: '#D34E7E' })
          }.width('100%').padding({ top: 10, bottom: 10 })
          Row() {
            Text(this.chrome!.title).fontSize(14).fontColor('#FFFFFF').maxLines(2).layoutWeight(1)
            Stack() { Image($r('app.media.ref_chevron_up')).width(16).height(16).fillColor('#FFFFFF') }
              .width(30).height(30).borderRadius(15).backgroundColor('#CC252525')
          }.width('100%')
          Row() {
            Stack({ alignContent: Alignment.Center }) {
              Image($r('app.media.ref_pause')).width(22).height(22).fillColor('#FFFFFF')
            }.width(40).height(40)
            Text(`00:00 / ${this.formatDuration(this.chrome!.duration)}`)
              .fontSize(12).fontColor('#EEEEEE').maxLines(1)
          }.width('100%').height(40)
          Stack({ alignContent: Alignment.Start }) {
            Rect().width('100%').height(2).fill('#45494F')
            Circle().width(5).height(5).fill('#D34E7E')
          }.width('100%').height(20)
          Row() {
            Row() {
              // 连刷预览浮层的弹幕输入入口：与评论页输入胶囊同款 capsule 材质、全圆角。
              NativeGlassInput({ inputHeight: 34 }) {
                Row({ space: 10 }) {
                  Image($r('app.media.ref_danmaku_checked')).width(23).height(23)
                  Rect().width(0.5).height(13).fill('#888888')
                  Text('发弹幕').fontSize(13).fontColor('#E7E9EB')
                }.width('100%').height('100%').padding({ left: 12, right: 12 })
              }
            }.layoutWeight(1).constraintSize({ maxWidth: FEED_DANMAKU_MAX_W })
            // 与当前页操作行同一口径：按钮组固定宽度靠右，翻页交接时图标位置不会跳。
            Row() {
              ReferencePlayerAction({ icon: $r('app.media.ref_like'), label: this.formatCount(this.chrome!.like), light: true })
              ReferencePlayerAction({ icon: $r('app.media.ref_coin'), label: this.formatCount(this.chrome!.coin), light: true })
              ReferencePlayerAction({ icon: $r('app.media.ref_favorite'), label: this.formatCount(this.chrome!.favorite), light: true })
              ReferencePlayerAction({ icon: $r('app.media.ref_comment_fill'), label: this.formatCount(this.chrome!.reply), light: true })
            }.width(FEED_ACTION_ITEM_W * 4)
          }.width('100%').justifyContent(FlexAlign.SpaceBetween)
        }.width('100%').height(244 + this.bottomInset).justifyContent(FlexAlign.End)
          .padding({ left: 8, right: 8, bottom: this.bottomInset })
          .position({ x: 0, y: this.top })
          .linearGradient({ angle: 180, colors: [['#00000000', 0], ['#CC000000', 0.5], ['#FF000000', 1]] })
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }
}
