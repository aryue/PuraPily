import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';
import { logError } from '../utils/Logger';

@Component
export struct PlayerCacheHint {
  @Prop done: boolean = false;
  @Prop paused: boolean = false;
  @Prop windowWidth: number = 0;
  @Prop maxBottom: number = 592;
  @Prop hdrRatio: number = 1;
  @StorageLink('cacheHintLeft') private left: number = 16;
  @StorageLink('cacheHintBottom') private bottom: number = 96;
  onClose: () => void = () => {};
  onOpen: () => void = () => {};
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private closeClicked: boolean = false;

  private async savePosition(left: number, bottom: number): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'my_app_settings');
      await pref.put('cacheHintLeft', left);
      await pref.put('cacheHintBottom', bottom);
      await pref.flush();
    } catch (error) {
      logError('保存缓存提示条位置失败', error);
    }
  }

  build() {
    Row() {
      if (this.done) {
        Image($r('app.media.checkmark_circle_fill')).width(18).height(18).fillColor('#34C759')
      } else if (this.paused) {
        Image($r('app.media.pause_circle_fill')).width(18).height(18).fillColor('#FFD60A')
      } else {
        LoadingProgress().width(18).height(18).color('#FFFFFF')
      }
      Text(this.done ? '缓存完成·点击查看' : (this.paused ? '已暂停·点击查看' : '正在缓存·点击查看'))
        .fontSize(13).fontColor(Color.White).margin({ left: 8 })
      Column() {
        Image($r('app.media.xmark_circle_fill')).width(18).height(18).fillColor('#FF453A')
      }
      .id('player-cache-hint-close')
      .width(24).height(24)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ left: 10 })
      .onClick(() => {
        this.closeClicked = true;
        this.onClose();
      })
    }
    .id('player-cache-hint')
    .padding({ left: 16, right: 12, top: 8, bottom: 8 })
    .backgroundColor('rgba(0,0,0,0.7)')
    .borderRadius(20)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.closeClicked) {
        this.closeClicked = false;
        return;
      }
      this.onOpen();
    })
    .position({ bottom: this.bottom, left: this.left })
    .foregroundFilter(playbackHdrUiFilter(this.hdrRatio))
    .zIndex(20)
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: 5 })
        .onActionStart(() => {
          this.dragStartX = this.left;
          this.dragStartY = this.bottom;
        })
        .onActionUpdate((event: GestureEvent) => {
          const maxLeft = Math.max(8, this.windowWidth - 220 - 8);
          this.left = Math.max(8, Math.min(maxLeft, this.dragStartX + Math.round(event.offsetX)));
          this.bottom = Math.max(20, Math.min(this.maxBottom, this.dragStartY - Math.round(event.offsetY)));
        })
        .onActionEnd(() => {
          this.savePosition(this.left, this.bottom);
        })
    )
  }
}
