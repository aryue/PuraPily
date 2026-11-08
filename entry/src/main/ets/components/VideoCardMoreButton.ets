import { VideoCardFeedback } from '../services/VideoCardFeedback';
import { VideoCardMenu } from '../services/VideoCardMenu';

/** One icon, touch target and event boundary for every video-card layout. */
@Component
export struct VideoCardMoreButton {
  @Prop title: string = '';
  @Prop actionText: string = '';
  @Prop videoId: string = '';
  @Prop ownerMid: string = '';
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  onActivate?: () => void;
  onMore?: () => void;

  private async openMenu(): Promise<void> {
    await VideoCardMenu.show(this.getUIContext(), this.title, this.videoId, this.ownerMid, this.isDarkMode);
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.ref_more')).width(12).height(16)
        .fillColor(this.isDarkMode ? '#C5CBD3' : '#50565F')
    }.width(28).height(24).padding(0).backgroundColor(Color.Transparent)
      .visibility(VideoCardFeedback.actions(this.videoId, this.ownerMid).length > 0 ? Visibility.Visible : Visibility.None)
      .id('video-card-more').accessibilityText('更多操作')
      .onClick(() => {
        void this.openMenu();
      })
  }
}
