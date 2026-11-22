@Component
export struct HomeChannelCardEntrance {
  @Prop cardKey: string = '';
  @Prop gridId: string = '';
  @Prop channelIndex: number = -1;
  @Prop @Watch('reveal') paneActive: boolean = true;
  @BuilderParam content: () => void;
  revealedCardIds: Set<string> = new Set<string>();
  @StorageProp('homeFeedActive') @Watch('reveal') homeActive: boolean = false;
  @StorageProp('homeChannelIndex') @Watch('reveal') activeChannel: number = -1;
  @State private entranceScale: number = 1;
  @State private centerX: number | string = '50%';
  private visible: boolean = false;

  aboutToAppear(): void {
    this.entranceScale = this.revealedCardIds.has(this.cardKey) ? 1 : 0.58;
  }

  private reveal(): void {
    if (!this.visible || !this.paneActive || !this.homeActive || this.activeChannel !== this.channelIndex ||
      this.entranceScale === 1) return;
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
    ui.animateTo({
      duration: 260,
      curve: Curve.EaseOut,
      expectedFrameRateRange: { min: 60, max: 120, expected: 120 }
    }, () => {
      this.entranceScale = 1;
    });
  }

  private anchorId(): string {
    return `${this.gridId}-entrance-${this.cardKey}`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }.width('100%').height(LayoutPolicy.fixAtIdealSize)
      .scale({ x: this.entranceScale, y: this.entranceScale, centerX: this.centerX, centerY: '50%' })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize)
    .id(this.anchorId())
    .onVisibleAreaChange([0], (visible: boolean) => {
      this.visible = visible;
      this.reveal();
    })
  }
}
