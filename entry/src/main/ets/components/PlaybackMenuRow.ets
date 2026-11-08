import { NativeGlassCapsule } from './NativeGlassCapsule';
import { PlaybackMenuIcon } from './PlaybackMenuIcon';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';

/** All playback-menu rows use one material; only their trailing controls differ. */
@Component
export struct PlaybackMenuRow {
  @Prop hdrUiRatio: number = 1;
  @Prop rowWidth: number = 300;
  @Prop rowId: string = '';
  @Prop icon: Resource = $r('app.media.ref_ps_settings');
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop isToggle: boolean = false;
  @Prop checked: boolean = false;
  @Prop actionEnabled: boolean = true;
  @StorageLink('isDarkMode') private dark: boolean = true;
  onActivate: () => void = () => {};
  onToggle: (value: boolean) => void = () => {};

  @Builder
  private rowContent() {
    Row({ space: 12 }) {
      PlaybackMenuIcon({ icon: this.icon, iconSize: 20 })
      Text(this.title).fontSize(15).fontColor(this.dark ? '#EEEFF1' : '#18191C').layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      if (this.isToggle) {
        Blank().width(40).hitTestBehavior(HitTestMode.None)
      } else {
        if (this.detail) {
          Text(this.detail).fontSize(12).fontColor(this.dark ? '#B3B4B8' : '#61666D').maxLines(1)
            .hitTestBehavior(HitTestMode.None)
        }
        Image($r('app.media.ref_chevron_right')).width(14).height(14)
          .fillColor(this.dark ? '#EEEFF1' : '#18191C').hitTestBehavior(HitTestMode.None)
      }
    }.width('100%').height('100%').padding({ left: 12, right: 12 })
      .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
      .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: this.rowWidth, capsuleHeight: 52, cornerRadius: 16,
        overlayContent: false,
        // Switches keep their original independent activation target.
        onActivate: () => { if (!this.isToggle) this.onActivate(); } }) {
        this.rowContent()
      }
      if (this.isToggle) {
        Toggle({ type: ToggleType.Switch, isOn: this.checked }).selectedColor('#D34E7E')
          .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
          .width(40).height(24).margin({ right: 12 })
          .id(this.rowId + '-toggle').onChange((value: boolean) => this.onToggle(value))
      }
    }.width(this.rowWidth).height(52).id(this.rowId).enabled(this.actionEnabled)
  }
}
