import { WallpaperCrop, wallpaperFrame, WallpaperFrame } from '../utils/WallpaperLayout';
import { image } from '@kit.ImageKit';
import { PageWallpaperService } from '../services/PageWallpaperService';

@Component
export struct WallpaperComposition {
  @Prop path: string = '';
  @Prop imageWidth: number = 1;
  @Prop imageHeight: number = 1;
  @Prop crop: WallpaperCrop = new WallpaperCrop();
  // Seed full-page instances before their first layout; embedded previews still measure themselves.
  @Prop initialWidth: number = 0;
  @Prop initialHeight: number = 0;
  @State private viewWidth: number = 0;
  @State private viewHeight: number = 0;
  @StorageLink('pageWallpaperDecodedRevision') decodedRevision: number = 0;

  aboutToAppear(): void {
    this.viewWidth = this.initialWidth;
    this.viewHeight = this.initialHeight;
  }

  private frame(): WallpaperFrame {
    return wallpaperFrame(this.viewWidth, this.viewHeight, this.imageWidth, this.imageHeight, this.crop);
  }
  private paintSource(): string | image.PixelMap {
    const revision = this.decodedRevision;
    return PageWallpaperService.getInstance().paintSource(this.path);
  }

  build() {
    Stack() {
      if (this.viewWidth > 0 && this.viewHeight > 0 && this.path) {
        Image(this.paintSource()).width(this.frame().width).height(this.frame().height)
          .objectFit(ImageFit.Fill).draggable(false)
          .translate({ x: this.frame().x, y: this.frame().y })
      }
    }.width('100%').height('100%').clip(true)
      .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
        this.viewWidth = Number(size.width);
        this.viewHeight = Number(size.height);
      })
  }
}
