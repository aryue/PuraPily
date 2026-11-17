import { QualityOption } from '../utils/QualityCatalog';

@Component
export struct PlayerCacheQuality {
  @Prop options: QualityOption[] = [];
  @Prop currentQuality: number = 0;
  @Prop selectedColor: ResourceColor = '#FB7299';
  @Prop selectedBackground: ResourceColor = 'rgba(255, 85, 170, 0.15)';
  @Prop optionBackground: ResourceColor = Color.Transparent;
  @Prop sheetBackground: ResourceColor = Color.Transparent;
  onSelect: (quality: number) => void = () => {};

  build() {
    Column() {
      Text('选择缓存画质').fontSize(16).fontColor($r('app.color.color_player_text'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 12, bottom: 4 })
      Column() {
        ForEach(this.options, (option: QualityOption) => {
          Row() {
            Text(option.label).fontSize(15)
              .fontColor(this.currentQuality === option.qn ? this.selectedColor : $r('app.color.color_player_text'))
              .fontWeight(this.currentQuality === option.qn ? FontWeight.Bold : FontWeight.Normal)
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.currentQuality === option.qn ? this.selectedBackground : this.optionBackground)
          .borderRadius(20)
          .margin({ bottom: 10 })
          .onClick(() => this.onSelect(option.qn))
        }, (option: QualityOption) => option.qn.toString())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.sheetBackground)
  }
}
