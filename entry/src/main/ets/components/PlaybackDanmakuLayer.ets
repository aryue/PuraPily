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
  /** 逻辑视口（几何口径）：横屏分栏下跟着分隔线实时变 */
  @Prop canvasWidth: number = 1;
  @Prop canvasHeight: number = 1;
  @Prop trackAreaHeight: number = 0;
  /** 可见区域（裁剪框）：永远是实时视口 */
  @Prop layerWidth: number = 1;
  @Prop layerHeight: number = 1;
  @Prop layerX: number = 0;
  @Prop layerY: number = 0;
  /**
   * ⭐ 画布（surface）像素尺寸，0 = 与 `layerWidth/layerHeight` 相同（绝大多数场景）。
   *
   * 只有横屏分栏会传非 0，且它是**窗口宽**（常量），不是分栏视口宽：
   * Canvas 元素的尺寸一旦跟着分隔线逐帧变，ArkUI 就会逐帧重建 surface 并清空内容，
   * 观感是整层弹幕闪烁。所以画布尺寸与可见视口解耦 ——
   *   · 画布：恒为窗口宽，拖动期间零重建；
   *   · 可见区域：外层按实时视口 `.clip(true)`；
   *   · 几何：`canvasWidth`（逻辑视口）实时，新弹幕仍从**画面**右缘进场。
   */
  @Prop surfaceWidth: number = 0;
  @Prop surfaceHeight: number = 0;
  @Link config: DanmakuConfig;
  @Link selfDanmaku: DanmakuItem[];

  build() {
    Stack() {
      ForEach([this.cid], (cid: number) => {
        // The canvas stays mounted while hidden so it retains measurable bounds.
        // 尺寸由 DanmakuView 自己按 surfaceWidth/surfaceHeight 定（没传就铺满本层）。
        DanmakuView({
          cid: cid,
          aid: this.aid,
          duration: this.duration,
          currentTime: this.currentTime,
          isPlaying: this.isPlaying,
          cookie: AppStorage.get<string>('biliCookie') || '',
          canvasWidth: this.canvasWidth,
          canvasHeight: this.canvasHeight,
          surfaceWidth: this.surfaceWidth,
          surfaceHeight: this.surfaceHeight,
          trackAreaHeight: this.trackAreaHeight,
          isFullscreen: this.isFullscreen,
          config: $config,
          selfDanmaku: $selfDanmaku,
        })
          .visibility(this.visible ? Visibility.Visible : Visibility.Hidden)
      }, (cid: number) => cid.toString())
    }
    .width(this.layerWidth)
    .height(this.layerHeight)
    // ⚠️ 必须左上对齐：横屏分栏时画布（窗口宽）比本层（视口宽）宽，默认 Center 会把
    //    画布水平居中 → 画布 x=0 与画面左缘错位，弹幕整体右移半个差值，左侧提前被裁掉。
    .alignContent(Alignment.TopStart)
    .position({ x: this.layerX, y: this.layerY })
    .clip(true)
  }
}
