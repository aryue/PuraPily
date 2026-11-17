import AVCastPicker from '@ohos.multimedia.avCastPicker';
import { HeaderBackButton } from './HeaderBackButton';
import { HeaderGlassControl } from './HeaderGlassControl';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';

@Component
export struct PlayerTopBar {
  @Prop hdrUiRatio: number = 1;
  @Prop landscape: boolean = false;
  @Prop feed: boolean = false;
  @Prop shown: boolean = false;
  @Prop barWidth: number = 0;
  @Prop x: number = 0;
  @Prop top: number = 0;
  onBack: () => void = () => {};
  onHome: () => void = () => {};
  onShare: () => void = () => {};
  onPiP: () => void = () => {};
  onMore: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 16 }) {
        HeaderBackButton({ hdrUiRatio: this.hdrUiRatio, iconColor: '#FFFFFF', onBack: this.onBack })
        if (this.landscape || !this.feed) {
          Column() {
            HeaderGlassControl({ label: '回首页', controlId: 'video-header-home', onActivate: this.onHome }) {
              Image($r('app.media.ref_home')).width(22).height(22).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
            }
          }.width(40).height(40)
        }
        Blank()
        if (!this.landscape && this.feed) {
          Column() {
            HeaderGlassControl({ label: '分享', controlId: 'reference-feed-top-share',
              onActivate: this.onShare }) {
              Image($r('app.media.ref_share')).width(22).height(22).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
            }
          }.width(40).height(40)
        } else if (!this.landscape) {
          Column() {
            HeaderGlassControl({ label: '投屏', controlId: 'video-header-cast' }) {
              Stack() {
                Image($r('app.media.ref_ps_cast')).width(22).height(22).hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
                // Keep the system picker as the actual full-size touch target.
                AVCastPicker({ sessionType: 'video' }).width(40).height(40).opacity(0)
              }.width(40).height(40)
            }
          }.width(40).height(40)
        }
        if (!this.landscape) {
          Column() {
            HeaderGlassControl({ label: '系统小窗', controlId: 'video-header-pip',
              onActivate: this.onPiP }) {
              Image($r('app.media.ref_pip')).width(22).height(22).hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
            }
          }.width(40).height(40)
        }
        Column() {
          HeaderGlassControl({ label: '更多', controlId: 'video-header-more', onActivate: this.onMore }) {
            Image($r('app.media.ref_more')).width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
                .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
          }
        }.width(40).height(40)
      }.width(this.barWidth).height(44).padding({ left: 8, right: 8 })
    }.width(this.barWidth).height(44)
      .id('reference-half-screen-top-bar')
      .position({ x: this.x, y: this.top }).zIndex(8)
      .visibility(this.shown ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(this.shown ? HitTestMode.Default : HitTestMode.None)
  }
}
