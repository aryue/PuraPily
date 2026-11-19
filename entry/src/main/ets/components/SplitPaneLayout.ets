import { SPLIT_HANDLE_HEIGHT, SPLIT_HANDLE_WIDTH, splitHandleX } from '../utils/SplitPaneGeometry';

/**
 * Controlled split layout. The caller owns the ratio and release animation.
 * Slots stay mounted as bounds change. Omit primary bounds for a layer using window coordinates.
 */
@Component
export struct SplitPaneLayout {
  @BuilderParam primary: () => void;
  @BuilderParam secondary: () => void;
  @Prop primaryWidth: Length = '100%';
  @Prop primaryHeight: Length = '100%';
  @Prop primaryX: number = 0;
  @Prop primaryY: number = 0;
  @Prop secondaryWidth: number = 1;
  @Prop secondaryHeight: number = 1;
  @Prop secondaryX: number = 0;
  @Prop secondaryY: number = 0;
  @Prop showHandle: boolean = true;
  @Prop swapped: boolean = false;
  /**
   * 退全屏到分栏期间，把整个副栏（含分发线）沿副栏方向推出窗口的距离。
   *
   * 全屏态下副栏本来就被全屏底板盖住、停在静止位置；退出时若直接撤底板，
   * 副栏会「原地啪一下出现」，视频再单独缩 200ms —— 两件事各走各的。
   * 这里由调用方按同一条插值进度把它推回窗口外再滑回来，
   * 于是「视频缩小」和「分栏推入」是同一个动作。其余时刻恒 0。
   */
  @Prop secondaryShiftX: number = 0;
  /** 分发线透明度：滑入起点它还在窗口边缘外，先淡出避免边缘闪一条。 */
  @Prop handleOpacity: number = 1;
  @Prop dividerTop: number = 0;
  @Prop dividerHeight: number = 0;
  @Prop handleWidth: number = SPLIT_HANDLE_WIDTH;
  @Prop handleHeight: number = SPLIT_HANDLE_HEIGHT;
  @Prop handleId: string = '';
  @Prop handleLabel: string = '拖动调节分栏大小';
  onResizeStart: () => void = () => {};
  onResizeUpdate: (offset: number) => void = () => {};
  onResizeEnd: (offset: number, cancelled: boolean) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.secondary()
      }.width(this.secondaryWidth).height(this.secondaryHeight)
        .position({ x: this.secondaryX + this.secondaryShiftX, y: this.secondaryY })
        .hitTestBehavior(HitTestMode.None)

      Stack({ alignContent: Alignment.TopStart }) {
        this.primary()
      }.width(this.primaryWidth).height(this.primaryHeight)
        .position({ x: this.primaryX, y: this.primaryY })
        .hitTestBehavior(HitTestMode.None)

      if (this.showHandle) {
        Row() {
          Row().width(4).height(42).borderRadius(2).backgroundColor('#45494F')
            .translate({ x: this.swapped ? -2 : 2 })
        }.width(this.handleWidth).height(this.handleHeight).justifyContent(FlexAlign.Center)
          .id(this.handleId)
          .accessibilityText(this.handleLabel)
          .position({ x: splitHandleX(this.secondaryX + this.secondaryShiftX, this.secondaryWidth, this.swapped, this.handleWidth),
            y: this.dividerTop + (this.dividerHeight - this.handleHeight) / 2 })
          .opacity(this.handleOpacity)
          .gesture(PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
            .onActionStart(() => this.onResizeStart())
            .onActionUpdate((event: GestureEvent) => this.onResizeUpdate(event.offsetX))
            .onActionEnd((event: GestureEvent) => this.onResizeEnd(event.offsetX, false))
            .onActionCancel(() => this.onResizeEnd(0, true)))
      }
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
  }
}
