import { PlaybackControlSurface } from './PlaybackControlSurface';
import { PlaybackGlassAction } from './PlaybackGlassAction';
import type { PlayerVideoOption } from './PlayerReferenceVideoOptions';

@Component
export struct PlayerLandscapeVideoOptions {
  @Prop options: PlayerVideoOption[] = [];
  @Prop selected: string = '';
  @Prop scalePanel: boolean = false;
  @Prop isDarkMode: boolean = false;
  onClose: () => void = () => {};
  onSelect: (key: string) => void = () => {};

  build() {
    Stack() {
      Column().width('77%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => this.onClose())
      if (this.scalePanel) {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.options, (option: PlayerVideoOption) => {
              Row() {
                Text(option.label).fontSize(14).maxLines(1).textAlign(TextAlign.Center).width('100%')
                  .fontColor(this.selected === option.key ? '#D34E7E' : '#FFFFFF')
              }.width('100%').height(52).padding({ left: 8, right: 8 })
                .borderRadius(10).backgroundColor('#202126')
                .onClick(() => this.onSelect(option.key))
            }, (option: PlayerVideoOption) => option.key)
          }.width('100%').padding({ top: 24, bottom: 24 })
        }.width('23%').height('100%').padding({ right: 8 })
          .align(Alignment.Center).scrollBar(BarState.Off).position({ right: 0, top: 0 })
      } else {
        Stack() { PlaybackControlSurface() {
          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.options, (option: PlayerVideoOption) => {
                PlaybackGlassAction({ actionId: `player-bottom-quality-${option.key}`, onActivate: () => this.onSelect(option.key) }) {
                  Text(option.label).fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center).width('100%').padding({ left: 8, right: 8 })
                    .fontColor(this.selected === option.key ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
                }
              }, (option: PlayerVideoOption) => option.key)
            }.width('100%').padding({ top: 24, bottom: 24, left: 8, right: 8 })
          }.width('100%').height('100%').align(Alignment.Center).scrollBar(BarState.Off)
        } }.width('23%').height('100%').position({ right: 0, top: 0 })
      }
    }.width('100%').height('100%').zIndex(30)
  }
}
