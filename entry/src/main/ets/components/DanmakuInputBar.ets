import { NativeComposerSurface } from './NativeComposerSurface';
import { NativeGlassInput } from './NativeGlassInput';
import { CommentInputBarCtrl } from './CommentInputBar';

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
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseInOut }, () => {
      this.settings = open;
      this.onSettingsChange(open);
    });
  }

  private colorHex(value: number): string {
    return '#' + value.toString(16).padStart(6, '0');
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

  @Builder
  option(label: string, selected: boolean, action: () => void) {
    Button(label).fontSize(14).height(34).padding({ left: 12, right: 12 })
      .fontColor(selected ? '#FB7299' : '#92969D')
      .backgroundColor(Color.Transparent).borderRadius(6)
      .border({ width: 1, color: selected ? '#FB7299' : '#646970' })
      .onClick(action)
  }

  build() {
    NativeComposerSurface({ active: this.materialEnabled }) {
    Column() {
      Row({ space: 10 }) {
        Text('A').fontSize(25).decoration({ type: TextDecorationType.Underline })
          .fontColor(this.settings ? '#FB7299' : '#92969D')
          .width(30).height(44).textAlign(TextAlign.Center)
          .accessibilityText('弹幕样式').id('danmaku-style-toggle')
          .onClick(() => { this.setSettings(!this.settings); })
        Row() {
          NativeGlassInput({ inputHeight: 36, cornerRadius: 8 }) {
            TextInput({ text: this.text, placeholder: '发个友善的弹幕见证当下' })
              .width('100%').height(36).fontSize(14)
              .fontColor(this.isDarkMode ? '#F1F2F3' : '#18191C').placeholderColor('#797D84')
              .backgroundColor(Color.Transparent)
              .borderRadius(8)
              .caretColor('#FB7299').maxLength(100).showCounter(false)
              .id('danmaku_text_input').defaultFocus(this.autoFocus)
              .enableKeyboardOnFocus(true)
              .enterKeyType(EnterKeyType.Send)
              .onChange((value: string) => { this.text = value; })
              .onFocus(() => { if (this.settings) this.setSettings(false); })
              .onSubmit(() => { this.send(); })
          }
        }.layoutWeight(1)
        Button() {
          Image($r('app.media.send_out')).width(24).height(24)
            .fillColor(this.text.trim() ? '#FB7299' : '#646970')
        }.width(32).height(40).padding(4).backgroundColor(Color.Transparent)
          .enabled(!this.sending && this.text.trim().length > 0)
          .accessibilityText('发送弹幕').onClick(() => { this.send(); })
      }.width('100%').height(52)
      Column({ space: 22 }) {
        Row({ space: 18 }) {
          Text('字体大小').width(64).fontSize(13).fontColor('#92969D')
          this.option('A 默认', this.fontSize === 25, () => { this.fontSize = 25; })
          this.option('A 较小', this.fontSize === 18, () => { this.fontSize = 18; })
        }.width('100%')
        Row({ space: 18 }) {
          Text('弹幕位置').width(64).fontSize(13).fontColor('#92969D')
          ForEach([1, 5, 4], (mode: number) => {
            this.option(mode === 1 ? '滚动' : mode === 5 ? '顶部' : '底部', this.mode === mode,
              () => { this.mode = mode; })
          })
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
