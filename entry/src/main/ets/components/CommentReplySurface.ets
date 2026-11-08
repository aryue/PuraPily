import { PageSurface } from './PageSurface';

/** Dynamic reply previews own the same measured glass and native rim receiver as their parent card. */
@Component
export struct CommentReplySurface {
  @Prop frosted: boolean = false;
  @BuilderParam content: () => void;
  @StorageLink('isDarkMode') dark: boolean = true;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.frosted) {
        PageSurface({ radius: 8 }) { this.content() }
      } else {
        Column() { this.content() }
          .width('100%').height(LayoutPolicy.fixAtIdealSize).borderRadius(4)
          .backgroundColor(this.dark ? '#0A0B0C' : '#F1F2F3')
      }
    }.width('100%').height(LayoutPolicy.fixAtIdealSize)
      .id(this.frosted ? 'dynamic-reply-frosted-surface' : 'comment-reply-surface')
  }
}
