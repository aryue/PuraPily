import { NativeCardGlass } from './NativeCardGlass';

export const CHANNEL_CARD_RADIUS: number = 8;

/** Each card measures its own content so the material follows grid resizing. */
@Component
export struct ChannelCardSurface {
  @Prop radius: number = CHANNEL_CARD_RADIUS;
  @BuilderParam content: () => void;
  @StorageProp('videoCardEdgeLight') glassEnabled: boolean = false;
  @State private surfaceWidth: number = 0;
  @State private surfaceHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.glassEnabled) {
        NativeCardGlass({ surfaceWidth: this.surfaceWidth, surfaceHeight: this.surfaceHeight, radius: this.radius })
          .position({ x: 0, y: 0 })
      }
      Column() {
        this.content()
      }.width('100%').height(LayoutPolicy.fixAtIdealSize)
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width);
          const height = Number(size.height);
          if (width > 0 && Math.abs(width - this.surfaceWidth) > 0.5) this.surfaceWidth = width;
          if (height > 0 && Math.abs(height - this.surfaceHeight) > 0.5) this.surfaceHeight = height;
        })
    }.width('100%').height(LayoutPolicy.fixAtIdealSize).borderRadius(this.radius).clip(true)
  }
}
