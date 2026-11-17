import { DanmakuView } from './DanmakuView';
import { DanmakuConfig, DanmakuItem } from '../model/DanmakuItem';

@Component
export struct PlaybackDanmakuLayer {
  @Prop cid: number = 0;
  @Prop aid: number = 0;
  @Prop duration: number = 0;
  @Prop currentTime: number = 0;
  @Prop isPlaying: boolean = false;
  @Prop visible: boolean = false;
  @Prop isFullscreen: boolean = false;
  @Prop canvasWidth: number = 1;
  @Prop canvasHeight: number = 1;
  @Prop trackAreaHeight: number = 0;
  @Prop layerWidth: number = 1;
  @Prop layerHeight: number = 1;
  @Prop layerX: number = 0;
  @Prop layerY: number = 0;
  @Link config: DanmakuConfig;
  @Link selfDanmaku: DanmakuItem[];

  build() {
    Stack() {
      ForEach([this.cid], (cid: number) => {
        // The canvas stays mounted while hidden so it retains measurable bounds.
        DanmakuView({
          cid: cid,
          aid: this.aid,
          duration: this.duration,
          currentTime: this.currentTime,
          isPlaying: this.isPlaying,
          cookie: AppStorage.get<string>('biliCookie') || '',
          canvasWidth: this.canvasWidth,
          canvasHeight: this.canvasHeight,
          trackAreaHeight: this.trackAreaHeight,
          isFullscreen: this.isFullscreen,
          config: $config,
          selfDanmaku: $selfDanmaku,
        })
          .width('100%')
          .height('100%')
          .visibility(this.visible ? Visibility.Visible : Visibility.Hidden)
      }, (cid: number) => cid.toString())
    }
    .width(this.layerWidth)
    .height(this.layerHeight)
    .position({ x: this.layerX, y: this.layerY })
    .clip(true)
  }
}
