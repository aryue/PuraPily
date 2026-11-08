import { ordinaryCardColor } from '../utils/SurfaceColors';
import { NativeCardGlass } from './NativeCardGlass';

/** Measured content surface: independent non-video glass settings control the measured native material. */
@Component
export struct PageSurface {
  @Prop radius: number = 20;
  @Prop active: boolean = true;
  @Prop forceGlass: boolean = false;
  @Prop fullHeight: boolean = false;
  @BuilderParam content: () => void;
  @StorageLink('pageWallpaperEnabled') wallpaper: boolean = false;
  @StorageLink('isDarkMode') dark: boolean = true;
  @StorageLink('otherCardGlassEnabled') glassEnabled: boolean = true;
  @State private surfaceWidth: number = 0;
  @State private surfaceHeight: number = 0;

  private ordinaryBackground(): ResourceColor {
    // Shared with the cards on ProfilePage, including wallpaper translucency.
    return this.wallpaper ? (this.dark ? '#D9202228' : '#E6FFFFFF') : ordinaryCardColor(this.dark);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.active && (this.glassEnabled || this.forceGlass) && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        NativeCardGlass({ surfaceWidth: this.surfaceWidth, surfaceHeight: this.surfaceHeight, radius: this.radius,
          otherCards: true })
          .position({ x: 0, y: 0 })
      }
      Column() {
        this.content()
      }.width('100%').height(this.fullHeight ? '100%' : LayoutPolicy.fixAtIdealSize).borderRadius(this.radius)
        .backgroundColor(!this.active || this.glassEnabled || this.forceGlass ? Color.Transparent : this.ordinaryBackground())
        .onSizeChange((_previous: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width);
          const height = Number(size.height);
          if (width > 0 && Math.abs(width - this.surfaceWidth) > 0.5) this.surfaceWidth = width;
          if (height > 0 && Math.abs(height - this.surfaceHeight) > 0.5) this.surfaceHeight = height;
        })
    }.width('100%').height(this.fullHeight ? '100%' : LayoutPolicy.fixAtIdealSize).borderRadius(this.radius)
  }
}
