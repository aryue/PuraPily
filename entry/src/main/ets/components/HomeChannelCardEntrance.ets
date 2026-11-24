const ENTRANCE_FALLBACK_MS: number = 750;
const ENTRANCE_COMPLETION_MS: number = 520;
const ENTRANCE_SETTLE_RESTORE_MS: number = 16;

@Component
export struct HomeChannelCardEntrance {
  @Prop cardKey: string = '';
  @Prop gridId: string = '';
  @Prop channelIndex: number = -1;
  @Prop @Watch('updateEntrance') paneActive: boolean = true;
  @BuilderParam content: () => void;
  revealedCardIds: Set<string> = new Set<string>();
  @StorageProp('homeFeedActive') @Watch('updateEntrance') homeActive: boolean = false;
  @StorageProp('homeChannelIndex') @Watch('updateEntrance') activeChannel: number = -1;
  @State private entranceScale: number = 0.2;
  @State private centerX: number | string = '50%';
  @State private entranceLayer: boolean = false;
  private visible: boolean = false;
  private entranceTimer: number = -1;
  private entranceCompletionTimer: number = -1;
  private entranceSettleTimer: number = -1;
  private entranceRevision: number = 0;

  aboutToAppear(): void {
    this.entranceScale = this.revealedCardIds.has(this.cardKey) ? 1 : 0.2;
    this.updateEntrance();
  }

  aboutToDisappear(): void {
    this.clearEntranceTimers();
  }

  private clearEntranceTimers(): void {
    if (this.entranceTimer >= 0) clearTimeout(this.entranceTimer);
    if (this.entranceCompletionTimer >= 0) clearTimeout(this.entranceCompletionTimer);
    if (this.entranceSettleTimer >= 0) clearTimeout(this.entranceSettleTimer);
    this.entranceTimer = -1;
    this.entranceCompletionTimer = -1;
    this.entranceSettleTimer = -1;
  }

  private clearEntranceFallback(): void {
    if (this.entranceTimer >= 0) clearTimeout(this.entranceTimer);
    this.entranceTimer = -1;
  }

  private updateEntrance(): void {
    if (this.entranceScale === 1 || !this.paneActive || !this.homeActive || this.activeChannel !== this.channelIndex) {
      this.clearEntranceFallback();
    } else if (this.visible) {
      this.reveal();
    } else if (this.entranceTimer < 0) {
      // Bound the time spent at the initial scale if the visibility callback is missed.
      this.entranceTimer = setTimeout(() => {
        this.entranceTimer = -1;
        this.reveal();
      }, ENTRANCE_FALLBACK_MS);
    }
  }

  private reveal(): void {
    this.clearEntranceTimers();
    if (this.revealedCardIds.has(this.cardKey)) {
      this.entranceScale = 1;
      return;
    }
    const ui = this.getUIContext();
    const utils = ui.getComponentUtils();
    const grid = utils.getRectangleById(this.gridId);
    const card = utils.getRectangleById(this.anchorId());
    if (Number(grid?.size.width) > 0 && Number(card?.size.width) > 0) {
      this.centerX = ui.px2vp(grid.windowOffset.x + Number(grid.size.width) / 2 - card.windowOffset.x);
    }
    this.revealedCardIds.add(this.cardKey);
    this.entranceLayer = true;
    const revision = ++this.entranceRevision;
    ui.animateToImmediately({
      duration: 450,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 },
      onFinish: () => {
        this.completeEntrance(revision);
      }
    }, () => {
      this.entranceScale = 1;
    });
    this.entranceCompletionTimer = setTimeout(() => {
      this.entranceCompletionTimer = -1;
      this.completeEntrance(revision, true);
    }, ENTRANCE_COMPLETION_MS);
  }

  private completeEntrance(revision: number, forceSettle: boolean = false): void {
    if (revision !== this.entranceRevision) return;
    this.clearEntranceTimers();
    if (forceSettle) {
      // The state target is already 1 during the tween. Change it once to invalidate a frozen frame.
      this.entranceScale = 1.0001;
      this.entranceSettleTimer = setTimeout(() => {
        this.entranceSettleTimer = -1;
        if (revision === this.entranceRevision) this.entranceScale = 1;
      }, ENTRANCE_SETTLE_RESTORE_MS);
    } else {
      this.entranceScale = 1;
    }
    this.entranceLayer = false;
  }

  private anchorId(): string {
    return `${this.gridId}-entrance-${this.cardKey}`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }.width('100%').height(LayoutPolicy.fixAtIdealSize)
      // 入场时合成整张卡片，避免为同一个字形缓存多档缩放结果。
      .renderGroup(this.entranceLayer)
      .scale({ x: this.entranceScale, y: this.entranceScale, centerX: this.centerX, centerY: '50%' })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize)
    .id(this.anchorId())
    .onVisibleAreaChange([0], (visible: boolean) => {
      this.visible = visible;
      this.updateEntrance();
    })
  }
}
