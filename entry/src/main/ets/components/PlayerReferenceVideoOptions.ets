import { PlaybackControlSurface } from './PlaybackControlSurface';
import { PlaybackGlassAction } from './PlaybackGlassAction';

export interface PlayerVideoOption {
  key: string;
  label: string;
}

/** Portrait playback options panel used by the reference player. */
@Component
export struct PlayerReferenceVideoOptions {
  @Prop title: string = '';
  @Prop options: PlayerVideoOption[] = [];
  @Prop selected: string = '';
  @Prop isDarkMode: boolean = false;
  @Prop fullscreen: boolean = false;
  onClose: () => void = () => {};
  onSelect: (key: string) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%').height('100%')
        .backgroundColor('#66000000')
        .onClick(() => this.onClose())

      Column() {
        PlaybackControlSurface() {
          Column({ space: 10 }) {
          Row() {
            Text(this.title)
              .fontSize(16).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#FFFFFF' : '#18191C')
            Blank()
            Text('关闭')
              .fontSize(14)
              .fontColor(this.isDarkMode ? '#CFD3D8' : '#61666D')
              .padding({ left: 12, right: 12 })
              .onClick(() => this.onClose())
          }
          .width('100%').height(44).padding({ left: 18, right: 18 })

          Scroll() {
            Column({ space: 8 }) {
              ForEach(this.options, (option: PlayerVideoOption) => {
                PlaybackGlassAction({
                  actionId: `player-reference-option-${option.key}`,
                  onActivate: () => this.onSelect(option.key)
                }) {
                  Text(option.label)
                    .fontSize(14).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center).width('100%')
                    .fontColor(option.key === this.selected ? '#D34E7E' :
                      (this.isDarkMode ? '#FFFFFF' : '#18191C'))
                }
              }, (option: PlayerVideoOption) => option.key)
            }
            .width('100%').padding({ left: 12, right: 12, bottom: 16 })
          }
          .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        }
          .width('100%').height('100%')
          .padding({ top: 6 })
        }
      }
      .width('100%').height(this.fullscreen ? '58%' : '46%')
      .margin({ bottom: 12 })
    }
    .width('100%').height('100%').zIndex(30)
  }
}
