import { HeaderBackButton } from '../components/HeaderBackButton';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { WallpaperComposition } from '../components/WallpaperComposition';
import { PageWallpaperService } from '../services/PageWallpaperService';
import { LocalWallpaper, WallpaperCrop, cleanWallpaperCrop, wallpaperFrame } from '../utils/WallpaperLayout';
import { WallpaperPicker } from './WallpaperPicker';

@Entry
@Component
struct LocalWallpaperPage {
  @StorageLink('isDarkMode') dark: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('navIndicatorHeight') bottomInset: number = 0;
  @StorageLink('pageWallpaperLocal') activePath: string = '';
  @StorageLink('pageWallpaperSource') activeSource: string = 'none';
  @State private items: LocalWallpaper[] = [];
  @State private editing: boolean = false;
  @State private item: LocalWallpaper = new LocalWallpaper();
  @State private crop: WallpaperCrop = new WallpaperCrop();
  @State private portraitCrop: WallpaperCrop = new WallpaperCrop();
  @State private landscapeCrop: WallpaperCrop = new WallpaperCrop();
  @State private portrait: boolean = true;
  @State private previewWidth: number = 0;
  @State private previewHeight: number = 0;
  @State private screenShort: number = 1600;
  @State private screenLong: number = 2560;
  @StorageLink('pageWallpaperViewportWidth') actualWidth: number = 0;
  @StorageLink('pageWallpaperViewportHeight') actualHeight: number = 0;
  @State private busy: boolean = false;
  private panX: number = 0;
  private panY: number = 0;
  private pinchZoom: number = 1;

  async aboutToAppear(): Promise<void> {
    try {
      const size = display.getDefaultDisplaySync();
      this.screenShort = Math.min(size.width, size.height);
      this.screenLong = Math.max(size.width, size.height);
      await PageWallpaperService.getInstance().open(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.items = PageWallpaperService.getInstance().localWallpapers();
    } catch (_) { this.toast('本地壁纸加载失败，请重试'); }
  }
  aboutToDisappear(): void {
    if (this.editing) PageWallpaperService.getInstance().discardImport(this.item.path);
  }
  onBackPress(): boolean {
    if (this.busy) return true;
    if (this.editing) { this.cancelEdit(); return true; }
    return false;
  }
  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message }); }
  private foreground(): string { return this.dark ? '#F2F4F8' : '#18191C'; }
  private beginEdit(item: LocalWallpaper): void {
    this.item = item;
    this.portraitCrop = cleanWallpaperCrop(item.portrait);
    this.landscapeCrop = cleanWallpaperCrop(item.landscape);
    this.portrait = true;
    this.crop = cleanWallpaperCrop(this.portraitCrop);
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => { this.editing = true; });
  }
  private cancelEdit(): void {
    if (this.busy) return;
    const path = this.item.path;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut,
      onFinish: () => { PageWallpaperService.getInstance().discardImport(path); } }, () => { this.editing = false; });
  }
  private switchOrientation(portrait: boolean): void {
    if (this.portrait) this.portraitCrop = cleanWallpaperCrop(this.crop);
    else this.landscapeCrop = cleanWallpaperCrop(this.crop);
    this.portrait = portrait;
    this.crop = cleanWallpaperCrop(portrait ? this.portraitCrop : this.landscapeCrop);
  }
  private changeZoom(zoom: number): void {
    const next = cleanWallpaperCrop(this.crop); next.zoom = Math.max(1, Math.min(4, zoom)); this.crop = next;
  }
  private async importPhoto(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      await WallpaperPicker.pickAndSetWallpaper(this.getUIContext().getHostContext() as common.UIAbilityContext,
        async (path: string) => { this.beginEdit(await PageWallpaperService.getInstance().describeLocal(path)); });
    } catch (_) { this.toast('无法读取图片，请选择 30 MB 以内的有效图片'); }
    finally { this.busy = false; }
  }
  private async apply(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      this.switchOrientation(this.portrait);
      const edited = new LocalWallpaper();
      edited.path = this.item.path; edited.width = this.item.width; edited.height = this.item.height;
      edited.portrait = cleanWallpaperCrop(this.portraitCrop); edited.landscape = cleanWallpaperCrop(this.landscapeCrop);
      await PageWallpaperService.getInstance().select('local', this.portrait, false, edited.path, edited);
      this.items = PageWallpaperService.getInstance().localWallpapers();
      this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => { this.editing = false; });
      this.toast('已保存到本地壁纸并应用');
    } catch (_) { this.toast('保存失败，已保留原壁纸，请重试'); }
    finally { this.busy = false; }
  }
  private previewRatio(): number {
    if (this.actualWidth > 0 && this.actualHeight > 0) {
      const ratio = this.actualWidth / this.actualHeight;
      return this.portrait === (this.actualHeight >= this.actualWidth) ? ratio : 1 / ratio;
    }
    return this.portrait ? this.screenShort / this.screenLong : this.screenLong / this.screenShort;
  }
  private frameWidth(): number { return Math.min(this.previewWidth, this.previewHeight * this.previewRatio()); }
  private frameHeight(): number { return this.frameWidth() / this.previewRatio(); }
  private drag(event: GestureEvent): void {
    const frame = wallpaperFrame(this.frameWidth(), this.frameHeight(), this.item.width, this.item.height, this.crop);
    const next = cleanWallpaperCrop(this.crop);
    const maxX = Math.max(0, (frame.width - this.frameWidth()) / 2);
    const maxY = Math.max(0, (frame.height - this.frameHeight()) / 2);
    next.x = maxX > 0 ? Math.max(-1, Math.min(1, this.panX + event.offsetX / maxX)) : 0;
    next.y = maxY > 0 ? Math.max(-1, Math.min(1, this.panY + event.offsetY / maxY)) : 0;
    this.crop = next;
  }

  @Builder
  private library() {
    Scroll() {
      Column({ space: 16 }) {
        Button('从设备添加图片').id('wallpaper-add-photo').width('100%').height(44)
          .backgroundColor('#D34E7E').fontColor(Color.White).enabled(!this.busy).onClick(() => this.importPhoto())
        Text('已应用的本地图片会保存在应用内，点选图片可预览、编辑和再次应用。')
          .fontSize(13).fontColor(this.foreground()).width('100%')
        if (this.items.length === 0) {
          Text('暂无保存的本地壁纸').fontSize(16).fontColor(this.foreground()).padding(32)
        }
        Grid() {
          ForEach(this.items, (entry: LocalWallpaper) => {
            GridItem() {
              Column({ space: 6 }) {
                Image('file://' + entry.path).width('100%').aspectRatio(1).objectFit(ImageFit.Cover)
                  .draggable(false).borderRadius(12)
                Text(this.activeSource === 'local' && this.activePath === entry.path ? '当前使用 · 编辑' : '预览与编辑')
                  .fontSize(13).fontColor(this.activeSource === 'local' && this.activePath === entry.path ? '#FF8DB1' : this.foreground())
              }.width('100%').onClick(() => this.beginEdit(entry))
            }.id('local-wallpaper-' + entry.path.split('/').pop())
          }, (entry: LocalWallpaper) => entry.path)
        }.columnsTemplate('1fr 1fr 1fr').columnsGap(12).rowsGap(16).layoutDirection(GridDirection.Row)
          .height(Math.ceil(this.items.length / 3) * (Math.max(1, this.previewWidth - 56) / 3 + 42))
      }.width('100%').padding({ left: 16, right: 16, top: this.statusBarHeight + 68, bottom: 24 + this.bottomInset })
    }.width('100%').height('100%').align(Alignment.TopStart)
      .transition(TransitionEffect.move(TransitionEdge.START))
      .onSizeChange((_old: SizeOptions, size: SizeOptions) => { this.previewWidth = Number(size.width); })
  }

  @Builder
  private editor() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Button('竖屏').id('wallpaper-portrait').backgroundColor(this.portrait ? '#D34E7E' : '#454951')
          .fontColor(Color.White).onClick(() => this.switchOrientation(true))
        Button('横屏').id('wallpaper-landscape').backgroundColor(!this.portrait ? '#D34E7E' : '#454951')
          .fontColor(Color.White).onClick(() => this.switchOrientation(false))
      }.justifyContent(FlexAlign.Center).width('100%')
      Stack() {
        Stack() {
          WallpaperComposition({ path: this.item.path, imageWidth: this.item.width, imageHeight: this.item.height, crop: this.crop })
        }.width(this.frameWidth()).height(this.frameHeight()).clip(true).id('wallpaper-preview')
          .gesture(GestureGroup(GestureMode.Parallel,
            PanGesture({ fingers: 1, distance: 1 }).onActionStart(() => { this.panX = this.crop.x; this.panY = this.crop.y; })
              .onActionUpdate((event: GestureEvent) => this.drag(event)),
            PinchGesture({ fingers: 2 }).onActionStart(() => { this.pinchZoom = this.crop.zoom; })
              .onActionUpdate((event: PinchGestureEvent) => this.changeZoom(this.pinchZoom * event.scale))
          ))
      }.width('100%').layoutWeight(1).backgroundColor('#14161A')
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          this.previewWidth = Number(size.width); this.previewHeight = Number(size.height);
        })
      Text('拖动调整位置 · 双指缩放 · 横竖屏分别保存').fontSize(12).fontColor(this.foreground())
      Row({ space: 12 }) {
        Button('−').id('wallpaper-zoom-out').onClick(() => this.changeZoom(this.crop.zoom - 0.1))
        Slider({ value: this.crop.zoom, min: 1, max: 4, step: 0.01 }).layoutWeight(1)
          .onChange((value: number) => this.changeZoom(value))
        Button('＋').id('wallpaper-zoom-in').onClick(() => this.changeZoom(this.crop.zoom + 0.1))
        Text(Math.round(this.crop.zoom * 100) + '%').fontSize(13).fontColor(this.foreground()).width(48)
      }.width('100%')
      Row({ space: 12 }) {
        Button('重置当前构图').id('wallpaper-reset').layoutWeight(1).onClick(() => { this.crop = new WallpaperCrop(); })
        Button(this.busy ? '保存中…' : '保存并应用').id('wallpaper-apply').layoutWeight(1)
          .backgroundColor('#D34E7E').fontColor(Color.White).enabled(!this.busy).onClick(() => this.apply())
      }.width('100%')
    }.width('100%').height('100%').padding({ left: 16, right: 16, top: this.statusBarHeight + 76, bottom: 12 + this.bottomInset })
      .transition(TransitionEffect.move(TransitionEdge.END))
  }



  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      PageWallpaper()
      Stack() {
        if (this.editing) { this.editor() } else { this.library() }
      }.width('100%').height('100%')
      PageHeader({ withTabs: false }) {
        Row({ space: 8 }) {
          HeaderBackButton({ iconColor: this.foreground(),
            onBack: () => { if (this.busy) return; if (this.editing) this.cancelEdit(); else this.getUIContext().getRouter().back(); } })
          Text(this.editing ? '预览与编辑' : '本地壁纸').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.foreground())
        }.width('100%').height(this.statusBarHeight + 52).padding({ top: this.statusBarHeight, left: 8 })
      }
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
