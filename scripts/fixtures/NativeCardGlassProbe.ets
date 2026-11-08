// Temporary device probe. Copied into the module only by the acceptance script.
import { uiMaterial } from '@kit.ArkUI';
import { VideoCardComponent } from './VideoCardComponent';
import { VideoListItem } from './VideoListItem';
import { RecommendItem } from '../model/RecommendItem';

@Component
export struct NativeCardGlassProbe {
  @State private lit: boolean = false;
  @State private item: RecommendItem = new RecommendItem();
  @State private taps: number = 0;
  aboutToAppear(): void {
    const item = new RecommendItem(); item.title = 'Native glass incident light'; item.ownerName = 'External source only';
    this.item = item;
    AppStorage.setOrCreate('videoCardEdgeLight', true);
  }
  @Builder
  private sourceButton(id: string) {
    Button('L').id(id).width(40).height(40).position({ x: 16, y: 16 })
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN, applyShadow: false,
        interactive: true, lightEffect: { color: Color.White }
      }))
      .onClick(() => { this.lit = !this.lit; AppStorage.setOrCreate('nativeCardLightActive', this.lit); })
  }
  @Builder
  private emitter(id: string) {
    Stack() {
      Navigation() { Column().height(0) }
        .width(72).height(72).position({ x: -16, y: -16 }).mode(NavigationMode.Stack)
        .title({ builder: (): void => { this.sourceButton(id); }, height: 72 }, {
          barStyle: BarStyle.STACK, backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
        })
        .hideBackButton(true).hideToolBar(true).backgroundColor(Color.Transparent).clip(false)
    }.width(40).height(40).clip(false)
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15], (i: number) => {
          Row().width('100%').height(40).backgroundColor(i % 2 === 0 ? '#422C35' : '#123B39')
        })
      }.width('100%').height('100%')
      Column({ space: 40 }) {
        Text('Native glass + independent native source').fontSize(18).fontColor('#FFFFFF')
        Row({ space: 8 }) {
          VideoCardComponent({ item: this.item, onCardClick: () => { this.taps++; } }).id('probe-grid-card').width(250)
          this.emitter('probe-grid-source')
        }.alignItems(VerticalAlign.Bottom)
        Row({ space: 8 }) {
          VideoListItem({ title: 'Native row glass', owner: 'External source only', onActivate: () => { this.taps++; } })
            .id('probe-list-card').width(300)
          this.emitter('probe-list-source')
        }.alignItems(VerticalAlign.Center)
        Text('Taps ' + this.taps + (this.lit ? ' · ON' : ' · OFF')).id('probe-taps').fontSize(14).fontColor('#FFFFFF')
      }.position({ x: 50, y: 60 })
    }.width('100%').height('100%').backgroundColor('#111111')
  }
}
