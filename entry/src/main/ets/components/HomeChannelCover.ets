import { homeArtworkRetained } from '../utils/HomeArtwork';

@Component
export struct HomeChannelCover {
  @Prop channel: number = -1;
  @Prop source: string = '';
  @Prop aspect: number = 1;
  @Prop placeholder: ResourceColor = Color.Transparent;
  @StorageProp('homeArtworkMask') artworkMask: number = 63;

  build() {
    Stack() {
      if (homeArtworkRetained(this.artworkMask, this.channel)) {
        Image(this.source).width('100%').height('100%')
          .autoResize(true).objectFit(ImageFit.Cover).draggable(false)
      }
    }.width('100%').aspectRatio(this.aspect).backgroundColor(this.placeholder)
  }
}
