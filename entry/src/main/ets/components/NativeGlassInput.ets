import { NativeGlassCapsule } from './NativeGlassCapsule';

/** Measured capsule for flexible input fields and their existing controls. */
@Component
export struct NativeGlassInput {
  @Prop inputHeight: number = 36;
  @Prop cornerRadius: number = -1;
  @Prop refractive: boolean = true;
  @BuilderParam content: () => void;
  @State private inputWidth: number = 0;

  build() {
    Row() {
      if (!this.refractive) {
        Row() { this.content() }
          .width('100%').height(this.inputHeight)
          .borderRadius(this.cornerRadius >= 0 ? this.cornerRadius : this.inputHeight / 2)
          .backgroundColor('#4D000000')
          .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      } else if (this.inputWidth > 0) {
        NativeGlassCapsule({ capsuleWidth: this.inputWidth, capsuleHeight: this.inputHeight, cornerRadius: this.cornerRadius }) {
          this.content()
        }
      }
    }.width('100%').height(this.inputHeight)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.inputWidth) > 0.5) this.inputWidth = width;
      })
  }
}
