import { NativeGlassCapsule } from './NativeGlassCapsule';

@Component
export struct PlaybackGlassAction {
  @Prop actionHeight: number = 52;
  @Prop radius: number = 12;
  @Prop actionId: string = '';
  onActivate: () => void = () => {};
  @BuilderParam content: () => void;
  @State private actionWidth: number = 0;

  build() {
    Stack() {
      if (this.actionWidth > 0) {
        NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true,
          nativePressFeedback: true, capsuleWidth: this.actionWidth, capsuleHeight: this.actionHeight,
          cornerRadius: this.radius, onActivate: () => this.onActivate() }) {
          Stack() { this.content() }.width('100%').height('100%').hitTestBehavior(HitTestMode.None)
        }
      }
    }.width('100%').height(this.actionHeight).id(this.actionId)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.actionWidth) > 0.5) this.actionWidth = width;
      })
  }
}
