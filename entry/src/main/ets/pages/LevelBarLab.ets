import { ExperimentalLevelBar } from '../components/ExperimentalLevelBar';
import { HeaderBackButton } from '../components/HeaderBackButton';

@Entry
@Component
struct LevelBarLab {
  @StorageProp('statusBarHeight') safeTop: number = 40;
  @StorageProp('navIndicatorHeight') safeBottom: number = 0;
  @State private dark: boolean = true;
  @State private active: boolean = true;
  @State private volume: number = 38;
  @State private brightnessPercent: number = 35;

  onPageShow(): void { this.active = true; }
  onPageHide(): void { this.active = false; }


  build() {
    Stack() {
      Image($r('app.media.yulanbizhi')).width('100%').height('100%').objectFit(ImageFit.Cover).blur(42)
      Column().width('100%').height('100%').backgroundColor(this.dark ? '#D1191C2C' : '#B8C9D1E2')
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          HeaderBackButton({ onBack: () => { this.getUIContext().getRouter().back(); } })
          Text('音量与亮度').fontSize(22).fontWeight(FontWeight.Medium).fontColor(this.dark ? '#F1F2F6' : '#242937')
        }.width('100%')
        Text('独立效果预览').fontSize(13).fontColor(this.dark ? '#99B7BED1' : '#80515B70').width('100%').padding({ left: 52 })
        Blank()
        Row({ space: 64 }) {
          Column({ space: 16 }) {
            ExperimentalLevelBar({ kind: 'brightness', initialValue: 0.35, active: this.active,
              onValueChange: (value: number) => { this.brightnessPercent = Math.round(value * 100); } })
            Text(`亮度 ${this.brightnessPercent}%`).id('lab-brightness-value').fontSize(15)
              .fontColor(this.dark ? '#CDD3E2' : '#485267')
          }
          Column({ space: 16 }) {
            ExperimentalLevelBar({ kind: 'volume', initialValue: 0.38, active: this.active,
              onValueChange: (value: number) => { this.volume = Math.round(value * 100); } })
            Text(`音量 ${this.volume}%`).id('lab-volume-value').fontSize(15)
              .fontColor(this.dark ? '#CDD3E2' : '#485267')
          }
        }.width('100%').height(210).justifyContent(FlexAlign.Center)
        Blank()
        Text('上下滑动调节音量与亮度').fontSize(13).fontColor(this.dark ? '#ACB4CA' : '#4F5C74')
        Row({ space: 12 }) {
          Button('深色背景').id('lab-dark').fontSize(14).backgroundColor(this.dark ? '#667D8AAA' : '#303E4A62')
            .onClick(() => { this.dark = true; })
          Button('浅色背景').id('lab-light').fontSize(14).backgroundColor(this.dark ? '#303E4A62' : '#667D8AAA')
            .onClick(() => { this.dark = false; })
        }
        Text('效果预览，不改变系统音量与屏幕亮度').fontSize(11).fontColor(this.dark ? '#78839F' : '#67758D').margin({ top: 8 })
      }.width('100%').height('100%').padding({ top: this.safeTop + 12, bottom: this.safeBottom + 18, left: 24, right: 24 })
    }.width('100%').height('100%')
  }
}
