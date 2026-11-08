import { RectShape } from '@kit.ArkUI';
import { CommentMenuSurface } from './CommentMenuSurface';

/** A stationary native scope shared by the panel, its scroll and real controls. */
@Component
export struct PlaybackControlSurface {
  @Prop viewportInset: number = 0;
  @BuilderParam content: () => void;
  @State private panelWidth: number = 0;
  @State private panelHeight: number = 0;

  build() {
    Stack() {
      if (this.panelWidth > 0 && this.panelHeight > 0) {
        CommentMenuSurface({ surfaceWidth: this.panelWidth, surfaceHeight: this.panelHeight,
          radius: 24, interactive: false, followTouchLight: true }) {
          // Keep this gutter outside Scroll: content padding disappears as the list moves.
          // Only the viewport is clipped; the stationary native glass retains its full frame.
          Stack() { this.content() }
            .width(Math.max(1, this.panelWidth - this.viewportInset * 2))
            .height(Math.max(1, this.panelHeight - this.viewportInset * 2))
            .position({ x: this.viewportInset, y: this.viewportInset })
            .clipShape(new RectShape({ width: '100%', height: '100%', radius: Math.max(0, 24 - this.viewportInset) }))
            .clip(true).id('playback-control-viewport')
        }
      }
    }.width('100%').height('100%').onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 0 && Math.abs(width - this.panelWidth) > 0.5) this.panelWidth = width;
      if (height > 0 && Math.abs(height - this.panelHeight) > 0.5) this.panelHeight = height;
    })
  }
}
