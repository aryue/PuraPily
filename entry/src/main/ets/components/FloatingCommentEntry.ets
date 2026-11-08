import { NativeGlassCapsule } from './NativeGlassCapsule';

/** Overlay only the capsule; the surrounding area remains available to the list. */
@Component
export struct FloatingCommentEntry {
  @Prop placeholder: string = '发条评论吧';
  @Prop bottomInset: number = 0;
  // A host that knows its width keeps the touch surface and content in the same
  // layout pass while resizing, rather than waiting for a measurement callback.
  @Prop entryWidth: number = 0;
  @State private capsuleWidth: number = 0;
  onOpen?: () => void;

  private resolvedWidth(): number {
    return this.entryWidth > 0 ? this.entryWidth : this.capsuleWidth;
  }

  build() {
    Row() {
      if (this.resolvedWidth() > 0) {
        NativeGlassCapsule({ capsuleWidth: this.resolvedWidth(), capsuleHeight: 40, overlayContent: true,
          onActivate: () => this.onOpen?.() }) {
          Row() {
            Text(this.placeholder).fontSize(13).fontColor($r('app.color.color_player_text_secondary'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Image($r('app.media.ref_apk_emoji')).width(20).height(20)
              .flexShrink(0).id('floating-comment-entry-emoji')
              .fillColor($r('app.color.color_player_text_secondary'))
          }.width('100%').height('100%').padding({ left: 14, right: 12 })
            .hitTestBehavior(HitTestMode.None)
            .id('floating-comment-entry')
        }
      }
    }.width(this.entryWidth > 0 ? this.entryWidth : '94%').height(40).margin({ bottom: 8 + this.bottomInset })
      .onAreaChange((_old: Area, area: Area) => {
        if (this.entryWidth > 0) return;
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.capsuleWidth) > 0.5) this.capsuleWidth = width;
      })
  }
}
