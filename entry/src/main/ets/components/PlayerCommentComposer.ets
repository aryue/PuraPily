import { CommentImageDraft, CommentInputBar, CommentInputBarCtrl } from './CommentInputBar';
import { NativeComposerSurface } from './NativeComposerSurface';

@Component
export struct PlayerCommentComposer {
  @Prop progress: number = 0;
  @Prop closing: boolean = false;
  @Prop frameWidth: number = 0;
  @Prop frameHeight: number = 0;
  @Prop frameX: number = 0;
  @Prop frameY: number = 0;
  @Prop placeholder: string = '';
  @Prop showImageButton: boolean = true;
  ctrl: CommentInputBarCtrl = new CommentInputBarCtrl();
  onClose: () => void = () => {};
  onReady: () => void = () => {};
  onHeightChange: (height: number) => void = () => {};
  onSend: (content: string, pictures: CommentImageDraft[]) => Promise<boolean> = async () => false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
        .opacity(this.progress).onClick(() => this.onClose())
      Column() {
        NativeComposerSurface({ rounding: 20 - 8 * this.progress, lowerRounding: 20 * (1 - this.progress) }) {
          Scroll() {
            Column() {
              CommentInputBar({
                materialEnabled: false,
                autoFocus: false,
                ctrl: this.ctrl,
                onHeightChange: (height: number) => this.onHeightChange(height),
                placeholder: this.placeholder,
                showImageButton: this.showImageButton,
                onSend: (content: string, pictures: CommentImageDraft[]) => this.onSend(content, pictures)
              })
            }.width('100%').backgroundColor(Color.Transparent)
          }
          .scrollBar(BarState.Off).width('100%').height(this.frameHeight)
          .opacity(Math.max(0, Math.min(1, (this.progress - 0.15) / 0.65)))
          .backgroundColor(Color.Transparent).clip(true).id('comment-composer-scroll')
        }
      }
      .width(this.frameWidth).height(this.frameHeight)
      .borderRadius({ topLeft: 20 - 8 * this.progress, topRight: 20 - 8 * this.progress,
        bottomLeft: 20 * (1 - this.progress), bottomRight: 20 * (1 - this.progress) })
      .clip(true).position({ x: this.frameX, y: this.frameY })
      .enabled(!this.closing).id('comment-composer').onAppear(() => this.onReady())
    }.width('100%').height('100%').zIndex(100)
  }
}
