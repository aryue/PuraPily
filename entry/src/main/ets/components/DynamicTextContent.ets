import { DynTextSegment } from '../api/BilibiliApi';

/**
 * 动态正文渲染（文字 / B站表情图 / #话题#胶囊 / @某人 混排）
 *
 * 动态流与详情共用富文本排版；动态流收起长文，详情展示完整内容。
 *    本工程历史上 `dynTextSegmentsBuilder` 在多个页面各有一份副本，
 *    改一处忘一处导致"同一条动态在两个页面表现不一致"，所以这里只保留一份实现。
 *
 * 交互（与动态流一致）：
 *   - `#话题#` / `@某人` 点击：走统一的路由入口（搜索页关键词 / UP 空间），组件内部自带，不需要调用方传回调。
 */
@Component
export struct DynamicTextContent {
  /** 正文分段（由 BilibiliApi 解析：含 emoji 的 emoteUrl、话题 kind='topic'、@ kind='at'） */
  @Prop segments: DynTextSegment[] = [];
  /** 信息流限制四行，详情页展示全文。 */
  @Prop collapsed: boolean = false;
  onOpenFull?: () => void;
  @State overflowed: boolean = false;
  @Prop bottomMargin: number = 0;
  /** 正文字号：详情页可以更大 */
  @Prop fontSize: number = 14;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;

  /**
   * ⭐ 话题 / @ / 全文 的链接蓝：**固定 B 站风格，不跟随自定义主题色**（2026-11-11 用户拍板，
   *    主题色是粉色时话题曾跟着变粉）。深色用淡蓝保证对比度，浅色用 B 站评论链接蓝。
   */
  private linkBlue(): string {
    return this.isDarkMode ? '#4FA9DD' : '#008AC5';
  }

  /** ⭐ 点击正文里的 #话题#：本工程没有话题详情页，带关键词进搜索页（与"长按选词→搜索"同一入口） */
  private openTopicTag(topicText: string): void {
    let kw: string = topicText;
    if (kw.startsWith('#')) kw = kw.substring(1);
    if (kw.endsWith('#')) kw = kw.substring(0, kw.length - 1);
    kw = kw.trim();
    if (!kw) return;
    this.getUIContext().getRouter().pushUrl({ url: 'pages/SearchPage', params: { keyword: kw } }).catch(() => {});
  }

  /** ⭐ 点击正文里的 @某人：进 TA 的空间（mid 来自富文本节点 rid，缺失就提示而不是静默无反应） */
  private openMentionedUp(seg: DynTextSegment): void {
    const mid: number = seg.mid ?? 0;
    if (mid <= 0) {
      this.getUIContext().getPromptAction().showToast({ message: '无法打开该用户主页', duration: 1500 });
      return;
    }
    let name: string = seg.text ?? '';
    if (name.startsWith('@')) name = name.substring(1);
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/UpSpacePage',
      params: { mid: mid, upName: name, upFace: '' }
    }).catch(() => {});
  }

  private updateOverflow(width: number): void {
    if (!this.collapsed || width <= 0) {
      this.overflowed = false;
      return;
    }
    const size = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: this.segments.map((seg: DynTextSegment) => seg.emoteUrl ? '　' : seg.text).join(''),
      fontSize: this.fontSize,
      lineHeight: this.fontSize + 6,
      constraintWidth: width
    });
    this.overflowed = this.getUIContext().px2vp(Number(size.height)) > (this.fontSize + 6) * 4 + 1;
  }

  build() {
    Column({ space: 4 }) {
      Text() {
        ForEach(this.segments, (seg: DynTextSegment, index: number) => {
          if (seg.emoteUrl) {
            ImageSpan(seg.emoteUrl)
              .width(20).height(20).verticalAlign(ImageSpanAlignment.CENTER)
          } else if (seg.kind === 'topic') {
            Span(seg.text).fontColor(this.linkBlue())
              .onClick(() => { this.openTopicTag(seg.text); })
          } else if (seg.kind === 'at') {
            Span(seg.text).fontColor(this.linkBlue())
              .onClick(() => { this.openMentionedUp(seg); })
          } else {
            Span(seg.text)
          }
        }, (seg: DynTextSegment, index: number) => 'dseg_' + index)
      }
      .width('100%')
      .fontSize(this.fontSize)
      .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
      .lineHeight(this.fontSize + 6)
      .textAlign(TextAlign.Start)
      .maxLines(this.collapsed ? 4 : undefined)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onAreaChange((_old: Area, area: Area) => { this.updateOverflow(Number(area.width)); })
      if (this.collapsed && this.overflowed) {
        Text('全文').fontSize(this.fontSize).fontColor(this.linkBlue())
          .id('dynamic-open-full')
          .onClick(() => { this.onOpenFull?.(); })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: this.bottomMargin })
  }
}
