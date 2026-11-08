import { image } from '@kit.ImageKit';
import { getCachedPixelMap, predecodeImage } from '../utils/ImageCache';

/** Each video owns its Image node; an old node must never render a new video's avatar. */
@Component
export struct FeedAvatarImage {
  @Prop videoId: string = '';
  @Prop face: string = '';

  build() {
    Stack() {
      ForEach([`${this.videoId}|${this.face}`], (_identity: string) => {
        DecodedFeedAvatar({ face: this.face })
      }, (identity: string) => identity)
    }.width(34).height(34)
  }
}

@Component
struct DecodedFeedAvatar {
  @Prop @Watch('loadAvatar') face: string = '';
  @State private bitmap: image.PixelMap | undefined = undefined;
  private alive: boolean = false;
  private generation: number = 0;

  aboutToAppear(): void {
    this.alive = true;
    this.loadAvatar();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
  }

  private loadAvatar(): void {
    const generation = ++this.generation;
    const face = this.face;
    this.bitmap = getCachedPixelMap(face);
    if (!this.alive || !face || this.bitmap) return;
    // Only this still-mounted identity may receive a cold decode result.
    predecodeImage(face).then(() => {
      if (!this.alive || generation !== this.generation || this.face !== face) return;
      this.bitmap = getCachedPixelMap(face);
    });
  }

  build() {
    Stack() {
      if (this.bitmap) {
        // A decoded 48px avatar needs no network or JPEG work on the UI thread.
        Image(this.bitmap).syncLoad(true)
          .width(34).height(34).borderRadius(20).objectFit(ImageFit.Cover)
      }
    }.width(34).height(34)
  }
}
