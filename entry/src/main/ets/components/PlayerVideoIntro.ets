import type { VideoIntroTag } from '../api/BilibiliApi';
import { ReferenceIntroStat } from './PlayerEngagementControls';

@Component
export struct PlayerVideoIntro {
  @Prop title: string = '';
  @Prop dark: boolean = false;
  @Prop expanded: boolean = false;
  @Prop viewCount: string = '';
  @Prop danmakuCount: string = '';
  @Prop publishTime: string = '';
  @Prop notice: string = '';
  @Prop videoId: string = '';
  @Prop noReprint: boolean = false;
  @Prop description: string = '';
  @Prop creatorCredit: string = '';
  onToggle: () => void = () => {};
  onSelectDescription: (description: string) => void = () => {};

  build() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text(this.title).fontSize(16).lineHeight(22)
          .fontColor(this.dark ? '#E7E9EB' : '#18191C')
          .maxLines(this.expanded ? 10 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Image($r('app.media.ref_chevron_up')).width(18).height(18).fillColor('#757A81')
          .rotate({ angle: this.expanded ? 0 : 180 })
      }.width('100%').onClick(() => { this.onToggle(); })
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        Row() { ReferenceIntroStat({ icon: $r('app.media.ref_play'), value: this.viewCount }) }.margin({ right: 8 })
        Row() { ReferenceIntroStat({ icon: $r('app.media.ref_danmaku'), value: this.danmakuCount }) }.margin({ right: 8 })
        Text(this.publishTime).fontSize(10).fontColor('#757A81').maxLines(1)
      }.width('100%')
      if (this.notice) {
        Row({ space: 4 }) {
          Text('ⓘ').fontSize(13).fontColor('#757A81')
          Text(this.notice).fontSize(11).fontColor('#757A81')
        }.width('100%')
      }
      if (this.expanded) {
        Row({ space: 8 }) {
          Text(this.videoId).fontSize(10).fontColor('#757A81')
          if (this.noReprint) {
            Text('⊘ 未经作者授权禁止转载').fontSize(10).fontColor('#757A81')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          }
        }.width('100%')
        Text(this.description).fontSize(12).lineHeight(19).fontColor('#757A81').width('100%')
          .gesture(LongPressGesture().onAction(() => {
            this.onSelectDescription(this.description);
          }))
        if (this.creatorCredit) {
          Text(this.creatorCredit).fontSize(12).lineHeight(19).fontColor('#757A81').width('100%')
        }
      }
    }.width('100%').padding({ top: 10, bottom: 12 })
  }
}

@Component
export struct PlayerVideoIntroTags {
  @Prop tags: VideoIntroTag[] = [];
  @Prop expanded: boolean = false;
  @Prop dark: boolean = false;
  onSelect: (name: string) => void = () => {};

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.expanded ? this.tags : this.tags.slice(0, 1), (tag: VideoIntroTag) => {
        Row({ space: 6 }) {
          Text('#').fontSize(14).fontColor('#A2A7AE')
          Text(tag.tag_name).fontSize(11).fontColor('#757A81').maxLines(1)
          Image($r('app.media.ref_chevron_right')).width(12).height(12).fillColor('#757A81')
        }.height(26).padding({ left: 10, right: 8 }).borderRadius(16)
          .backgroundColor(this.dark ? '#202224' : '#F1F2F3').margin({ right: 8, bottom: 8 })
          .onClick(() => { this.onSelect(tag.tag_name); })
      }, (tag: VideoIntroTag) => tag.tag_id.toString())
    }.width('100%').margin({ bottom: 2 })
  }
}
