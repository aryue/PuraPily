export interface ReferenceFeedGestureOptions {
  active: boolean;
  distance: number;
  onDoubleTap: (event: GestureEvent) => void;
  onStart: (event: GestureEvent) => void;
  onUpdate: (event: GestureEvent) => void;
  onEnd: (event: GestureEvent) => void;
  onCancel: () => void;
}

// 评论/简介页不挂连刷识别器，而不是等识别成功才在 judge 中拒绝。
// 后者仍会参与惯性期间新触摸的竞争，导致原生 List 的第二次拖动停住。
export class ReferenceFeedGestures implements GestureModifier {
  private options: ReferenceFeedGestureOptions;

  constructor(options: ReferenceFeedGestureOptions) {
    this.options = options;
  }

  applyGesture(event: UIGestureEvent): void {
    event.clearGestures();
    if (!this.options.active) return;
    event.addParallelGesture(new TapGestureHandler({ count: 2 }).onAction(this.options.onDoubleTap));
    event.addGesture(new PanGestureHandler({ direction: PanDirection.Vertical, distance: this.options.distance })
      .tag('reference-feed-pan')
      .onActionStart(this.options.onStart)
      .onActionUpdate(this.options.onUpdate)
      .onActionEnd(this.options.onEnd)
      .onActionCancel(this.options.onCancel), GesturePriority.PRIORITY);
  }
}
