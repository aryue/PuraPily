import { VideoPageItem } from '../api/BilibiliApi';
import { GenericDataSource } from '../model/GenericDataSource';

@Component
struct EpisodePlayingBars {
  @Prop @Watch('updatePulse') playing: boolean = true;
  @State private pulse: boolean = false;
  private inViewport: boolean = false;

  private updatePulse(): void {
    this.pulse = this.playing && this.inViewport;
  }

  @Builder
  bar(rest: number, peak: number, duration: number, delay: number) {
    Column().width(2).height(14).borderRadius(1).backgroundColor('#D34E7E')
      .scale({ x: 1, y: this.pulse ? peak : rest })
      .animation({ duration: this.pulse ? duration : 0, delay: this.pulse ? delay : 0,
        curve: Curve.EaseInOut, iterations: this.pulse ? -1 : 1, playMode: PlayMode.Alternate })
  }

  build() {
    Row({ space: 2 }) {
      this.bar(0.4, 1, 340, 0)
      this.bar(1, 0.3, 460, 100)
      this.bar(0.5, 0.95, 390, 210)
    }.width(10).height(16).hitTestBehavior(HitTestMode.None)
      .onAppear(() => { this.inViewport = true; this.updatePulse(); })
      .onVisibleAreaChange([0], (visible: boolean) => { this.inViewport = visible; this.updatePulse(); })
      .onDisAppear(() => { this.inViewport = false; this.updatePulse(); })
  }
}

/** 分P/番剧选集，与 ugc_season 合集独立。选中变化不重新装载条目。 */
@Component
export struct ReferenceEpisodeStrip {
  @Prop @Watch('syncPages') pages: VideoPageItem[] = [];
  @Prop selectedIndex: number = 0;
  @Prop playing: boolean = true;
  @Prop isDarkMode: boolean = true;
  onSelect: (index: number) => void = () => {};
  onShowAll: () => void = () => {};
  private items: GenericDataSource<VideoPageItem> = new GenericDataSource<VideoPageItem>();
  private scroller: ListScroller = new ListScroller();
  @State availableWidth: number = 360;

  aboutToAppear(): void {
    this.syncPages();
  }

  private syncPages(): void {
    const old = this.items.getRawItems();
    if (old.length === this.pages.length && old.every((item: VideoPageItem, i: number) =>
      item.cid === this.pages[i].cid && item.page === this.pages[i].page && item.part === this.pages[i].part)) return;
    this.items.reloadItems(this.pages.slice());
  }

  private itemWidth(): number {
    return Math.max(104, (this.availableWidth - 28 - 24) / 3);
  }

  build() {
    Row({ space: 8 }) {
      List({ space: 8, scroller: this.scroller, initialIndex: Math.max(0, this.selectedIndex - 1) }) {
        LazyForEach(this.items, (page: VideoPageItem, index: number) => {
          ListItem() {
            Row({ space: 8 }) {
              if (index === this.selectedIndex) {
                Row() {
                  EpisodePlayingBars({ playing: this.playing })
                }.height(16).id(`reference-episode-playing-${index}`)
              }
              Text(page.part || `P${page.page}`).fontSize(14)
                .fontColor(index === this.selectedIndex ? '#D34E7E' : (this.isDarkMode ? '#E7E9EB' : '#18191C'))
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            }.width(this.itemWidth()).height(56).padding({ left: 12, right: 12 }).borderRadius(8)
              .backgroundColor(this.isDarkMode ? '#202224' : '#F1F2F3')
              .id(`reference-episode-${index}`)
              .accessibilityText(`${page.part || `P${page.page}`}${index === this.selectedIndex ? '，正在播放' : ''}`)
              .onClick(() => { this.onSelect(index); })
          }
        }, (page: VideoPageItem) => `${page.cid}:${page.page}`)
      }.listDirection(Axis.Horizontal).layoutWeight(1).height(56).scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring).cachedCount(3).id('reference-intro-episode-strip')
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ref_chevron_right')).width(20).height(20).fillColor('#757A81')
      }.width(28).height(56).padding(0).backgroundColor(Color.Transparent)
        .id('reference-intro-episodes').accessibilityText('全部选集')
        .onClick(() => { this.onShowAll(); })
    }.width('100%').height(56)
      .onAreaChange((_old: Area, area: Area) => { this.availableWidth = Number(area.width); })
  }
}
