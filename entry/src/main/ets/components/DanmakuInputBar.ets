import { NativeComposerSurface } from './NativeComposerSurface';
import { NativeGlassInput } from './NativeGlassInput';
import { CommentInputBarCtrl } from './CommentInputBar';

/**
 * 样式选项必须走独立组件 + @Prop。
 * 用 @Builder 的普通值参数传 selected 时，@State 变化不会让 Builder 重新求值，
 * 点击有回调但选中态（文字/边框色）不刷新，表现成「选不了」（2026-11-09 实测）。
 */
@Component
struct DanmakuOption {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  action: () => void = () => {};

  build() {
    Button(this.label).fontSize(14).height(34).padding({ left: 12, right: 12 })
      .fontColor(this.selected ? '#FB7299' : '#92969D')
      .backgroundColor(Color.Transparent).borderRadius(6)
      .border({ width: 1, color: this.selected ? '#FB7299' : '#646970' })
      .accessibilityText(this.label + (this.selected ? ' 已选中' : ' 未选中'))
      .onClick(() => this.action())
  }
}

/** 弹幕输入与样式选择共用一份草稿，切换键盘不会重建输入框。 */
@Component
export struct DanmakuInputBar {
  ctrl: CommentInputBarCtrl = new CommentInputBarCtrl();
  @Prop autoFocus: boolean = true;
  @Prop materialEnabled: boolean = true;
  @Prop bottomInset: number = 0;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @State text: string = '';
  @State settings: boolean = false;
  @State mode: number = 1;
  @State fontSize: number = 25;
  @State color: number = 0xFFFFFF;
  @State sending: boolean = false;
  onSettingsChange: (open: boolean) => void = () => {};
  onSend: (text: string, mode: number, color: number, fontSize: number) => Promise<boolean> = async () => false;
  private colors: number[] = [0xFFFFFF, 0xFF0000, 0xFFFF00, 0x00A650, 0x00AEEF,
    0xFF0088, 0xA8D500, 0x0054A6, 0xFFB62C, 0x703F86, 0x80C7D2, 0x9B853D];

  aboutToAppear(): void {
    this.ctrl.bindImpl((): boolean => {
      if (!this.settings) return false;
      this.setSettings(false);
      return true;
    });
  }

  aboutToDisappear(): void {
    this.ctrl.unbind();
    this.onSettingsChange(false);
  }

  private setSettings(open: boolean): void {
    if (open) this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().animateTo({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 240, curve: Curve.EaseInOut }, () => {
      this.settings = open;
      this.onSettingsChange(open);
    });
  }

  private colorHex(value: number): string {
    return '#' + value.toString(16).padStart(6, '0');
  }

  /** 样式入口沿用评论页输入胶囊的次级前景色，展开时用品牌色提示当前状态。 */
  private styleToggleColor(): ResourceColor {
    return this.settings ? '#FB7299' : $r('app.color.color_player_text_secondary');
  }

  private async send(): Promise<void> {
    if (!this.text.trim() || this.sending) return;
    this.sending = true;
    try {
      if (await this.onSend(this.text.trim(), this.mode, this.color, this.fontSize)) this.text = '';
    } finally {
      this.sending = false;
    }
  }

  build() {
    // 组件被独立复用时仍可挂原生玻璃底板；播放页由宿主提供，传 materialEnabled:false。
    // 收起态不挂，避免胶囊外面多一层框。
    NativeComposerSurface({ active: this.materialEnabled && this.settings }) {
    Column() {
      // 与评论页「发条评论吧」输入胶囊同款：单层 capsule 原生玻璃、40vp 全圆角，
      // 文字在左、弹幕样式「A」在右。不再放独立发送按钮，发送交给键盘 EnterKeyType.Send。
      Row() {
        NativeGlassInput({ inputHeight: 40 }) {
          Row() {
            TextInput({ text: this.text, placeholder: '发个友善的弹幕见证当下' })
              .layoutWeight(1).height(40).fontSize(13)
              .fontColor(this.isDarkMode ? '#F1F2F3' : '#18191C')
              .placeholderColor($r('app.color.color_player_text_secondary'))
              .backgroundColor(Color.Transparent)
              .padding({ left: 14, right: 4 })
              .caretColor('#FB7299').maxLength(100).showCounter(false)
              .id('danmaku_text_input').defaultFocus(this.autoFocus)
              .enableKeyboardOnFocus(true)
              .enterKeyType(EnterKeyType.Send)
              .onChange((value: string) => { this.text = value; })
              .onFocus(() => { if (this.settings) this.setSettings(false); })
              .onSubmit(() => { this.send(); })
            Text('A').fontSize(20).decoration({ type: TextDecorationType.Underline })
              .fontColor(this.styleToggleColor())
              .width(32).height(40).textAlign(TextAlign.Center).flexShrink(0)
              .margin({ right: 12 })
              .accessibilityText('弹幕样式').id('danmaku-style-toggle')
              .onClick(() => { this.setSettings(!this.settings); })
          }.width('100%').height('100%')
        }
      }.width('100%').height(52)
      Column({ space: 22 }) {
        Row({ space: 18 }) {
          Text('字体大小').width(64).fontSize(13).fontColor('#92969D')
          DanmakuOption({ label: 'A 默认', selected: this.fontSize === 25,
            action: () => { this.fontSize = 25; } })
          DanmakuOption({ label: 'A 较小', selected: this.fontSize === 18,
            action: () => { this.fontSize = 18; } })
        }.width('100%')
        Row({ space: 18 }) {
          Text('弹幕位置').width(64).fontSize(13).fontColor('#92969D')
          ForEach([1, 5, 4], (mode: number) => {
            DanmakuOption({ label: mode === 1 ? '滚动' : mode === 5 ? '顶部' : '底部',
              selected: this.mode === mode, action: () => { this.mode = mode; } })
          }, (mode: number) => mode.toString())
        }.width('100%')
        Row({ space: 18 }) {
          Text('弹幕颜色').width(64).fontSize(13).fontColor('#92969D')
          Grid() {
            ForEach(this.colors, (value: number) => {
              GridItem() {
                Stack({ alignContent: Alignment.BottomEnd }) {
                  Column().width(24).height(24).backgroundColor(this.colorHex(value)).borderRadius(4)
                    .border({ width: 1, color: '#60646B' })
                  if (this.color === value) {
                    Text('✓').fontSize(10).fontColor(Color.White).textAlign(TextAlign.Center)
                      .width(13).height(13).backgroundColor('#FB7299').borderRadius(7)
                      .translate({ x: 5, y: 5 })
                  }
                }.width(28).height(28).onClick(() => { this.color = value; })
                  .accessibilityText('弹幕颜色 ' + this.colorHex(value))
              }
            }, (value: number) => value.toString())
          }.columnsTemplate('repeat(6, 1fr)').rowsTemplate('repeat(2, 36)')
            .columnsGap(12).rowsGap(12).layoutWeight(1).constraintSize({ maxWidth: 260 }).height(84)
        }.width('100%').alignItems(VerticalAlign.Top)
      }.width('100%').height(this.settings ? 230 : 0).clip(true)
        .padding({ top: this.settings ? 20 : 0, bottom: this.settings ? 14 : 0 })
    }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomInset })
    }
  }
}
