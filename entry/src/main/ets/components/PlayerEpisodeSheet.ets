import { GenericDataSource } from '../model/GenericDataSource';

export interface PlayerEpisodeRow {
  key: string;
  number: string;
  title: string;
  duration: string;
  cover: string;
  selected: boolean;
}

@Component
export struct PlayerEpisodeSheet {
  @Prop title: string = '';
  @Prop sections: string[] = [];
  @Prop sectionIndex: number = 0;
  @Prop @Watch('updateRows') rows: PlayerEpisodeRow[] = [];
  @Prop initialIndex: number = 0;
  @Prop sheetHeight: number = 400;
  @Prop sheetBackground: ResourceColor = Color.Transparent;
  @Prop selectedColor: ResourceColor = 'app.color.color_bilibili_pink';
  @Prop listId: string = '';
  onSection: (index: number) => void = () => {};
  onEpisode: (index: number) => void = () => {};
  private scroller: Scroller = new Scroller();
  private rowSource: GenericDataSource<PlayerEpisodeRow> = new GenericDataSource<PlayerEpisodeRow>();
  private rowRevision: number = 0;

  aboutToAppear(): void {
    this.rowSource.setRawItems(this.rows);
  }

  private updateRows(): void {
    // A replacement can change the selected row or move an episode between indices.
    this.rowRevision++;
    this.rowSource.reloadItems(this.rows);
  }

  build() {
    Column() {
      Column().width('100%').height(8)
      if (this.title) {
        Text(this.title).fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.color_player_text')).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 16, right: 16, bottom: 12 })
      }
      Row() {
        if (this.sections.length > 1) {
          List({ space: 6, initialIndex: this.sectionIndex }) {
            ForEach(this.sections, (label: string, index: number) => {
              ListItem() {
                Text(label).fontSize(11)
                  .fontWeight(this.sectionIndex === index ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.sectionIndex === index ? this.selectedColor : $r('app.color.color_player_text_secondary'))
                  .padding({ left: 8, right: 8, top: 7, bottom: 7 })
                  .backgroundColor(this.sectionIndex === index ? $r('app.color.color_comment_selected') : Color.Transparent)
                  .borderRadius(14)
                  .onClick(() => {
                    this.onSection(index);
                    this.scroller.scrollToIndex(0, false);
                  })
              }
            }, (_label: string, index: number) => index.toString())
          }
          .padding({ top: 8, bottom: 8 })
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .width(64).height('100%')
        }
        if (this.rows.length > 0) {
          List({ scroller: this.scroller, initialIndex: this.initialIndex }) {
            LazyForEach(this.rowSource, (row: PlayerEpisodeRow, index: number) => {
              ListItem() {
                Row() {
                  if (row.cover) {
                    Image(row.cover).width(72).height(44).objectFit(ImageFit.Cover)
                      .borderRadius(6).backgroundColor('#E8E8E8').margin({ right: 8 })
                  }
                  Text(row.number).fontSize(14).width(36)
                    .fontColor(row.selected ? this.selectedColor : $r('app.color.color_player_text_secondary'))
                  Text(row.title).fontSize(14)
                    .fontColor(row.selected ? this.selectedColor : $r('app.color.color_player_text'))
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).margin({ left: 4 })
                  Text(row.duration).fontSize(12)
                    .fontColor($r('app.color.color_player_text_secondary')).margin({ left: 8 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor(row.selected ? $r('app.color.color_comment_selected') : Color.Transparent)
                .borderRadius(20)
                .onClick(() => { if (!row.selected) this.onEpisode(index); })
              }
            }, (row: PlayerEpisodeRow, index: number) => `${this.rowRevision}-${index}-${row.key}`)
          }
          .layoutWeight(1).padding({ left: 8, right: 8 }).height('100%')
          .scrollBar(BarState.Off).id(this.listId)
        }
      }
      .layoutWeight(1).width('100%')
      Column().width('100%').height(8)
    }
    .width('100%')
    .height(this.sheetHeight)
    .backgroundColor(this.sheetBackground)
  }
}
