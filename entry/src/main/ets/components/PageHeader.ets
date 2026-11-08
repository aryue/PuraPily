import { NativeHeaderGlass } from './NativeHeaderGlass';
import { HistoryHeaderBlur } from './HistoryHeaderBlur';

/** Shared title surface. Measure controls; material never determines title height. */
@Component
export struct PageHeader {
  @Prop showSurface: boolean = true;
  @Prop withTabs: boolean = false;
  @Prop hideBottomEdge: boolean = false;
  @Prop scopeId: string = 'page-header-native-scope';
  @Prop materialHeight: number = 0;
  // Recreate only the backdrop after a cached pager finishes moving its sampling source.
  @Prop surfaceRevision: number = 0;
  @BuilderParam content: () => void;
  @StorageLink('isDarkMode') dark: boolean = true;
  @State private surfaceWidth: number = 0;
  @State private surfaceHeight: number = 0;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.showSurface && this.surfaceWidth > 0 && this.surfaceHeight > 0) {
        if (this.withTabs) {
          // A normal layout child preserves the native Navigation material scope.
          Stack({ alignContent: Alignment.TopStart }) {
            ForEach([this.surfaceRevision], (_revision: number) => {
              NativeHeaderGlass({ surfaceWidth: this.surfaceWidth,
                surfaceHeight: this.materialHeight > 0 ? this.materialHeight : this.surfaceHeight,
                scopeId: this.scopeId, hideBottomEdge: this.hideBottomEdge })
            }, (revision: number) => revision.toString())
          }.width(this.surfaceWidth).height(this.surfaceHeight).clip(true).position({ x: 0, y: 0 })
        } else {
          HistoryHeaderBlur({ surfaceWidth: this.surfaceWidth, surfaceHeight: this.surfaceHeight })
            .position({ x: 0, y: 0 })
        }
      }
      Column() { this.content() }.width('100%')
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => {
          const width = Number(size.width);
          const height = Number(size.height);
          if (Math.abs(width - this.surfaceWidth) > 0.5) this.surfaceWidth = width;
          if (Math.abs(height - this.surfaceHeight) > 0.5) this.surfaceHeight = height;
        })
    }.width('100%')
  }
}
