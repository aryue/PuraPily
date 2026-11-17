import type { QualityOption } from '../utils/QualityCatalog';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';

@Component
export struct PlayerBottomPlaybackMenu {
  @Prop kind: string = '';
  @Prop dark: boolean = true;
  @Prop hdrUiRatio: number = 1;
  @Prop playbackRate: number = 1;
  @Prop qualities: QualityOption[] = [];
  @Prop quality: number = 0;
  @Prop isSubtitleEnabled: boolean = false;
  @Prop subtitleTracks: string[] = [];
  @Prop subtitleIndex: number = -1;
  @Prop subtitleLarge: boolean = false;
  @Prop subtitleLoading: boolean = false;
  @Prop subtitleFailed: boolean = false;
  onClose: () => void = () => {};
  onRate: (rate: number) => void = () => {};
  onQuality: (quality: number) => void = () => {};
  onSubtitle: (index: number) => void = () => {};
  onSubtitlePrepare: () => void = () => {};
  onSubtitleLarge: (large: boolean) => void = () => {};

  private check(selected: boolean): Resource | undefined {
    return selected ? (this.dark ? $r('app.media.settings_menu_check_dark') :
      $r('app.media.settings_menu_check_light')) : undefined;
  }

  build() {
    Menu() {
      if (this.kind === 'rate') {
        ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], (rate: number) => {
          MenuItem({ content: `${rate}x`, endIcon: this.check(Math.abs(this.playbackRate - rate) < 0.01) })
            .height(52).id(`player-bottom-rate-${rate}`)
            .onClick(() => { this.onRate(rate); this.onClose(); })
        }, (rate: number) => `${rate}`)
      } else if (this.kind === 'quality') {
        ForEach(this.qualities, (quality: QualityOption) => {
          MenuItem({ content: quality.label, endIcon: this.check(this.quality === quality.qn) })
            .height(52).id(`player-bottom-quality-${quality.qn}`)
            .onClick(() => { this.onQuality(quality.qn); this.onClose(); })
        }, (quality: QualityOption) => `${quality.qn}`)
        if (this.qualities.length === 0) { MenuItem({ content: '暂无可用画质' }).enabled(false) }
      } else {
        MenuItem({ content: '关闭字幕', endIcon: this.check(!this.isSubtitleEnabled) })
          .height(52).id('player-bottom-subtitle-off')
          .onClick(() => { this.onSubtitle(-1); this.onClose(); })
        ForEach(this.subtitleTracks, (label: string, index: number) => {
          MenuItem({ content: label, endIcon: this.check(this.isSubtitleEnabled && this.subtitleIndex === index) })
            .height(52).id(`player-bottom-subtitle-${index}`)
            .onClick(() => { this.onSubtitle(index); this.onClose(); })
        }, (label: string, index: number) => `${index}:${label}`)
        if (this.subtitleLoading) { MenuItem({ content: '正在加载字幕…' }).enabled(false) }
        else if (this.subtitleFailed) {
          MenuItem({ content: '加载失败，点击重试' }).onClick(() => this.onSubtitlePrepare())
        } else if (this.subtitleTracks.length === 0) { MenuItem({ content: '当前视频暂无可用字幕' }).enabled(false) }
        MenuItem({ content: '字幕大字号', endIcon: this.check(this.subtitleLarge) })
          .height(52).id('player-bottom-subtitle-large')
          .onClick(() => { this.onSubtitleLarge(!this.subtitleLarge); this.onClose(); })
      }
    }.width(224).radius(24).font({ size: 16 })
      .fontColor(this.dark ? '#EEEFF1' : '#18191C')
      .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
  }
}
