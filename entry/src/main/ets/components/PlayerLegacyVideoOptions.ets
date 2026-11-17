export interface PlayerVideoOption {
  key: string;
  label: string;
}

@Component
export struct PlayerLegacyVideoOptions {
  @Prop title: string = '';
  @Prop options: PlayerVideoOption[] = [];
  @Prop selected: string = '';
  @Prop landscape: boolean = false;
  @Prop fullscreen: boolean = false;
  @Prop mirror: boolean = false;
  @Prop instant: boolean = false;
  @Prop scalePanel: boolean = false;
  @Prop selectedColor: ResourceColor = '#FB7299';
  @Prop selectedBackground: ResourceColor = 'rgba(255, 85, 170, 0.15)';
  onClose: () => void = () => {};
  onSelect: (key: string) => void = () => {};

  build() {
    Stack() {
      Column().width(this.landscape ? '60%' : '50%').height('100%')
        .position(this.mirror ? { right: 0, top: 0 } : { left: 0, top: 0 })
        .onClick(() => this.onClose())
      Column() {
        Text(this.title).fontSize(16).fontColor(Color.White)
          .fontWeight(FontWeight.Bold).padding({ left: 4, right: 4, top: 0, bottom: 12 })
          .offset({ x: this.mirror ? 14 : -14, y: -12 })
        ForEach(this.options, (option: PlayerVideoOption, index: number) => {
          Row() {
            Text(option.label).fontSize(15)
              .fontColor(this.selected === option.key ? this.selectedColor : Color.White)
              .fontWeight(this.selected === option.key ? FontWeight.Bold : FontWeight.Normal)
          }
          .height(48).justifyContent(FlexAlign.Center).padding({ left: 36, right: 36 })
          .backgroundColor(this.selected === option.key ? this.selectedBackground : 'rgba(0, 0, 0, 0.35)')
          .border({ width: this.selected === option.key ? 1.5 : 0, color: this.selectedColor })
          .borderRadius(12).margin({ bottom: 12 })
          .onClick(() => this.onSelect(option.key))
          .transition(
            this.instant ? TransitionEffect.IDENTITY :
              TransitionEffect.asymmetric(
                TransitionEffect.translate({ x: (this.mirror ? -1 : 1) * (this.scalePanel ? 60 : 40) })
                  .combine(TransitionEffect.opacity(0))
                  .animation({ duration: this.scalePanel ? 450 : 300,
                    curve: this.scalePanel ? Curve.EaseOut : Curve.EaseIn, delay: index * 100 }),
                TransitionEffect.translate({ x: this.mirror ? -40 : 40 }).combine(TransitionEffect.opacity(0))
                  .animation({ duration: 300, curve: Curve.EaseIn, delay: index * 100 })
              )
          )
          .offset({ x: this.mirror ? 14 : -14 })
        }, (option: PlayerVideoOption) => option.key)
      }
      .width(this.fullscreen && this.landscape ? '24%' : this.landscape ? '30%' : '50%')
      .height('100%')
      .linearGradient({
        direction: this.mirror ? GradientDirection.Left : GradientDirection.Right,
        colors: [['rgba(0,0,0,0)', 0], ['rgba(0,0,0,0)', 0.25],
          [this.scalePanel ? 'rgba(0,0,0,0.95)' : 'rgba(18,18,22,0.88)', 1]]
      })
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 60, left: this.mirror ? 50 : 48, right: this.mirror ? 48 : 50 })
      .position(this.mirror ? { left: 0, top: 0 } : { right: 0, top: 0 })
    }
    .width('100%').height('100%')
    .transition(
      this.instant ? TransitionEffect.IDENTITY :
        TransitionEffect.asymmetric(
          TransitionEffect.translate({ x: this.mirror ? '-100%' : '100%' }).combine(TransitionEffect.opacity(0))
            .animation({ duration: 400, curve: Curve.EaseOut }),
          TransitionEffect.opacity(0).animation({ duration: 700, curve: Curve.EaseIn })
        )
    )
  }
}
