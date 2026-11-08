import { LocalWallpaper } from '../utils/WallpaperLayout';
import { WallpaperComposition } from './WallpaperComposition';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { PageWallpaperService } from '../services/PageWallpaperService';

@Component
export struct PageWallpaper {
  @Prop @Watch('reload') orientation: string = 'auto';
  @Prop embedded: boolean = false;
  @StorageLink('pageWallpaperPortrait') @Watch('warmImage') portraitImage: string = '';
  @StorageLink('pageWallpaperLandscape') @Watch('warmImage') landscapeImage: string = '';
  @StorageLink('pageWallpaperDecodedRevision') decodedRevision: number = 0;
  @StorageLink('pageWallpaperSource') @Watch('reload') source: string = 'none';
  @StorageLink('pageWallpaperLocalComposition') localComposition: string = '{}';
  @StorageLink('pageWallpaperOpacity') imageOpacity: number = 0.7;
  @StorageLink('pageWallpaperScrim') scrim: number = 0;
  @StorageLink('isDarkMode') dark: boolean = true;
  @State portrait: boolean = (AppStorage.get<number>('pageWallpaperViewportHeight') ?? 1) >=
    (AppStorage.get<number>('pageWallpaperViewportWidth') ?? 1);
  private ready: boolean = false;

  async aboutToAppear(): Promise<void> {
    try {
      await PageWallpaperService.getInstance().open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.ready = true;
      this.warmImage();
      this.reload();
    } catch (_) {}
  }
  private reload(): void {
    if (this.ready) PageWallpaperService.getInstance().ensure(this.portraitSlot()).catch(() => {});
  }
  private warmImage(): void {
    PageWallpaperService.getInstance().prepareImage(this.currentImage()).catch(() => {});
  }
  private paintSource(): string | image.PixelMap {
    const revision = this.decodedRevision;
    return PageWallpaperService.getInstance().paintSource(this.currentImage());
  }
  private portraitSlot(): boolean {
    return this.orientation === 'portrait' ? true : this.orientation === 'landscape' ? false : this.portrait;
  }
  private currentImage(): string {
    return this.portraitSlot() ? (this.portraitImage || this.landscapeImage) : (this.landscapeImage || this.portraitImage);
  }
  private local(): LocalWallpaper {
    try { return JSON.parse(this.localComposition) as LocalWallpaper; } catch (_) { return new LocalWallpaper(); }
  }
  /** 遮罩强度 0–60（%）：深色压黑、浅色提白，共用设置里同一条滑块。 */
  private scrimColor(): string {
    const alpha = (Math.max(0, Math.min(60, this.scrim)) / 100).toFixed(3);
    return this.dark ? `rgba(0, 0, 0, ${alpha})` : `rgba(255, 255, 255, ${alpha})`;
  }
  build() {
    Stack() {
      if (this.source !== 'none' && this.currentImage()) {
        if (this.source === 'local' && this.local().width > 0) {
          WallpaperComposition({ path: this.currentImage(), imageWidth: this.local().width, imageHeight: this.local().height,
            crop: this.portraitSlot() ? this.local().portrait : this.local().landscape,
            initialWidth: this.embedded ? 0 : (AppStorage.get<number>('pageWallpaperViewportWidth') ?? 0),
            initialHeight: this.embedded ? 0 : (AppStorage.get<number>('pageWallpaperViewportHeight') ?? 0) }).opacity(this.imageOpacity)
        } else {
          Image(this.paintSource()).width('100%').height('100%')
            .objectFit(ImageFit.Cover).draggable(false).opacity(this.imageOpacity)
        }
        // 两种模式共用一条可调节的壁纸遮罩；深浅由 scrimColor 决定方向。
        if (this.scrim > 0) {
          Column().width('100%').height('100%').backgroundColor(this.scrimColor())
        }
      }
    }.width('100%').height('100%')
      .backgroundColor(pageBackgroundColor(this.dark))
      .expandSafeArea([SafeAreaType.SYSTEM], this.embedded ? [] : [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onAreaChange((_previous: Area, area: Area) => {
        if (!this.embedded) {
          AppStorage.setOrCreate('pageWallpaperViewportWidth', Number(area.width));
          AppStorage.setOrCreate('pageWallpaperViewportHeight', Number(area.height));
        }
        const portrait = Number(area.height) >= Number(area.width);
        if (this.portrait !== portrait) { this.portrait = portrait; this.reload(); }
      })
  }
}
