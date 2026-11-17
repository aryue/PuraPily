import { PlaybackControlSurface } from './PlaybackControlSurface';
import { PlaybackGlassAction } from './PlaybackGlassAction';
import { PlaybackMenuRow } from './PlaybackMenuRow';

@Component
export struct PlayerSubtitlePanel {
  @Prop isDarkMode: boolean = false;
  @Prop windowWidth: number = 0;
  @Prop selected: number = -1;
  @Prop subtitlesEnabled: boolean = false;
  @Prop options: string[] = [];
  @Prop large: boolean = false;
  onClose: () => void = () => {};
  onSelect: (index: number) => void = () => {};
  onLarge: (value: boolean) => void = () => {};

  build() {
    Stack() {
      Column().width('58%').height('100%').position({ left: 0, top: 0 })
        .onClick(() => this.onClose())
      Stack() { PlaybackControlSurface() {
        Scroll() {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Text('字幕').fontSize(16).fontColor(this.isDarkMode ? '#FFFFFF' : '#18191C')
                .fontWeight(FontWeight.Medium).layoutWeight(1)
              Stack() { PlaybackGlassAction({ actionHeight: 36, radius: 18, actionId: 'player-bottom-subtitle-done',
                onActivate: () => this.onClose() }) {
                Text('完成').fontSize(14).fontColor('#D34E7E')
              } }.width(72)
            }.width('100%').height(48)
            Column({ space: 8 }) {
              PlaybackGlassAction({ actionHeight: 48, actionId: 'player-bottom-subtitle-off',
                onActivate: () => this.onSelect(-1) }) {
                Text('关闭字幕').fontSize(14).width('100%').padding({ left: 14, right: 14 })
                  .fontColor(!this.subtitlesEnabled ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
              }
              ForEach(this.options, (label: string, index: number) => {
                PlaybackGlassAction({ actionHeight: 48, actionId: `player-bottom-subtitle-${index}`,
                  onActivate: () => this.onSelect(index) }) {
                  Row() {
                    Text(label).fontSize(14).layoutWeight(1)
                      .fontColor(this.selected === index ? '#D34E7E' : this.isDarkMode ? '#FFFFFF' : '#18191C')
                    if (this.selected === index) Image($r('app.media.ref_check')).width(18).height(18)
                  }.width('100%').padding({ left: 14, right: 14 })
                }
              }, (label: string, index: number) => `${index}:${label}`)
              if (this.options.length === 0) {
                Text('当前视频暂无可用字幕轨道').fontSize(12).fontColor(this.isDarkMode ? '#96999F' : '#61666D')
                  .width('100%').padding({ left: 14, top: 12, bottom: 12 })
              }
            }.width('100%')
            PlaybackMenuRow({ rowWidth: Math.max(0, this.windowWidth * 0.42 - 36), rowId: 'player-bottom-subtitle-large',
              icon: $r('app.media.ref_ps_subtitle'), title: '字幕大字号', isToggle: true, checked: this.large,
              onToggle: (value: boolean) => { this.onLarge(value); } })
          }.width('100%').padding({ left: 18, right: 18, top: 24, bottom: 24 })
        }.width('100%').height('100%').scrollBar(BarState.Off)
      } }.width('42%').height('100%').position({ right: 0, top: 0 })
    }.width('100%').height('100%').zIndex(30)
  }

}