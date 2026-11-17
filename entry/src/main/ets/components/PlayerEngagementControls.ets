// 独立组件的 @Prop 随详情异步返回和连刷切片更新，避免 Builder 值参数保留初始值。
@Component
export struct ReferenceIntroStat {
  @Prop icon: Resource = $r('app.media.ref_play');
  @Prop value: string = '—';

  build() {
    Row({ space: 3 }) {
      Image(this.icon).width(13).height(13).fillColor('#757A81')
      Text(this.value).fontSize(10).fontColor('#757A81').maxLines(1)
    }
  }
}

@Component
export struct ReferencePlayerAction {
  @Prop icon: Resource = $r('app.media.ref_like');
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop light: boolean = false;
  @Prop intro: boolean = false;
  onAction: () => void = () => {};

  /**
   * 图标光学尺寸。四个按钮的图标都来自同族单色 SVG（墨迹占视图框 85%~91%），同框即可等大；
   * 之前混用 APK 的 story 位图（PNG 墨迹只占 74%，且点赞走 23vp 分支），才会一大一小、
   * 还因 Column 内容高度不同把四个数字基线错开约 5vp。
   * 简介统计行（intro，5 个入口）保持 22vp。
   */
  private actionIconSize(): number {
    return this.intro ? 22 : 32;
  }

  build() {
    Column({ space: this.intro ? 8 : 6 }) {
      // Contain：评论气泡是 38×37 的非正方形视图框，Cover 会裁掉一条边。
      Image(this.icon).width(this.actionIconSize()).height(this.actionIconSize())
        .objectFit(ImageFit.Contain)
        .fillColor(this.selected ? '#D34E7E' : (this.light ? '#FFFFFF' : '#A2A7AE'))
      Text(this.label).fontSize(10).fontColor(this.selected ? '#D34E7E' : (this.light ? '#FFFFFF' : '#A2A7AE')).maxLines(1)
    }.layoutWeight(1).height(this.intro ? 54 : 58).justifyContent(FlexAlign.Center).onClick(this.onAction)
  }
}
