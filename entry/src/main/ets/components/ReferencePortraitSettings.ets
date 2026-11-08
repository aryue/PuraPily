import { PlaybackMenuIcon } from './PlaybackMenuIcon';
import { playbackHdrUiFilter } from '../utils/PlaybackHdrUi';
import { LengthMetrics } from '@kit.ArkUI';
import { PlaybackMenuRow } from './PlaybackMenuRow';
import { playbackMenuOptions } from '../utils/PlaybackMenuStyle';
import { CommentMenuSurface } from './CommentMenuSurface';
import { NativeGlassCapsule } from './NativeGlassCapsule';
import { NativeComposerSurface } from './NativeComposerSurface';
import AVCastPicker from '@ohos.multimedia.avCastPicker';
export interface PortraitQuality { qn: number; label: string }

@Component
export struct ReferencePortraitSettings {
  @Prop @Watch('onOpenChanged') open: boolean = true;
  @Prop hdrUiRatio: number = 1;
  @Link rate: number
  @Link mode: string
  @Link scaleMode: string
  @Link feedPortraitScaleMode: string
  @Link feedPortraitScaleScope: string
  @Link backgroundEnabled: boolean
  @Link mirror: boolean
  @Link subtitle: boolean
  @Prop subtitleTracks: string[] = [];
  @Prop subtitleIndex: number = -1;
  @Prop subtitleLarge: boolean = false;
  @Prop subtitleLoading: boolean = false;
  @Prop subtitleFailed: boolean = false;
  onSubtitlePrepare: () => void = () => {};
  onSubtitle: (index: number) => void = () => {};
  onSubtitleLarge: (large: boolean) => void = () => {};
  @Prop bottomQualityAvailable: boolean = false;
  @Prop bottomPlaybackSettingsAvailable: boolean = false;
  @Prop quality: string = ''
  @Prop qualitySwitching: boolean = false
  @Prop qualities: PortraitQuality[] = []
  @Link sleepMinutes: number
  @Link stopAtEnd: boolean
  @Prop bottomInset: number = 0
  onAction: (action: string) => void = () => {}
  onRate: (rate: number) => void = () => {}
  onMode: (mode: string) => void = () => {}
  onToggle: (key: string, value: boolean) => void = () => {}
  onSleep: (minutes: number) => void = () => {}
  onQuality: (quality: number) => void = () => {}
  @Prop pgc: boolean = false
  @StorageLink('isDarkMode') private dark: boolean = true
  @State private panelWidth: number = 0
  @State private panelHeight: number = 0
  @State private choiceKind: string = ''
  @State private choiceMenuVisible: boolean = false
  @State private settingsPage: boolean = false
  @State private customSleep: boolean = false
  @State private customMinutes: string = ''


  private textColor(): string { return this.dark ? '#EEEFF1' : '#18191C'; }

  private onOpenChanged(): void {
    this.choiceMenuVisible = false;
    if (this.open) {
      this.settingsPage = false;
      this.customSleep = false;
    }
  }

  private optionLabels(kind: string): string[] {
    if (kind === 'quality') return this.qualities.map((item: PortraitQuality) => item.label);
    if (kind === 'sleep') return ['不开启', '播完当前视频', '15分钟', '30分钟', '60分钟', '90分钟', '自定义'];
    if (kind === 'rate') return ['0.5', '0.75', '1', '1.25', '1.5', '2'];
    if (kind === 'mode') return this.pgc ? ['单集循环', '播完暂停'] : ['列表循环', '单集循环', '播完暂停'];
    if (kind === 'playback') return ['自动', '拉伸', '填充', '等高', '等宽'];
    if (kind === 'feedScale') return ['完整显示', '裁切铺满'];
    return ['仅 9:16 竖片', '所有竖片'];
  }

  private currentOption(kind: string): string {
    if (kind === 'subtitle') return this.subtitle ? (this.subtitleTracks[this.subtitleIndex] || '已开启') : '关闭字幕';
    if (kind === 'quality') return this.quality;
    if (kind === 'sleep') return this.stopAtEnd ? '播完当前视频' : this.sleepMinutes > 0 ? `${this.sleepMinutes}分钟` : '不开启';
    if (kind === 'rate') return `${this.rate}`;
    if (kind === 'mode') return this.mode === 'loop' ? '单集循环' : this.mode === 'single' ? '播完暂停' : '列表循环';
    if (kind === 'playback') return ['自动', '拉伸', '填充', '等高', '等宽'][['auto', 'stretch', 'fill', 'fitHeight', 'fitWidth'].indexOf(this.scaleMode)];
    if (kind === 'feedScale') return this.feedPortraitScaleMode === 'fill' ? '裁切铺满' : '完整显示';
    return this.feedPortraitScaleScope === 'all' ? '所有竖片' : '仅 9:16 竖片';
  }

  private selectOption(kind: string, index: number): void {
    this.choiceMenuVisible = false;
    const value = this.optionLabels(kind)[index];
    if (kind === 'quality') {
      const item = this.qualities[index];
      if (item) this.onQuality(item.qn);
    } else if (kind === 'rate') this.onRate(Number(value));
    else if (kind === 'mode') this.onMode(value === '单集循环' ? 'loop' : value === '播完暂停' ? 'single' : 'continuous');
    else if (kind === 'sleep') {
      this.customSleep = value === '自定义';
      if (!this.customSleep) {
        this.onToggle('stopAtEnd', value === '播完当前视频');
        this.onSleep(value.endsWith('分钟') ? Number(value.replace('分钟', '')) : 0);
      }
    } else if (kind === 'playback') this.onAction(`scale:${value}`);
    else if (kind === 'feedScale') this.onAction(value === '完整显示' ? 'feedScale:auto' : 'feedScale:fill');
    else this.onAction(value === '所有竖片' ? 'feedScope:all' : 'feedScope:standard');
  }

  private menuOptions(): MenuOptions {
    return playbackMenuOptions(this.dark, () => { this.choiceMenuVisible = false; });
  }

  @Builder
  Options(kind: string) {
    Menu() {
      if (kind === 'subtitle') {
        MenuItem({ content: '关闭字幕', endIcon: !this.subtitle ?
          (this.dark ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.textColor()).height(52).id('player-menu-subtitle-off')
          .onClick(() => { this.choiceMenuVisible = false; this.onSubtitle(-1); })
        ForEach(this.subtitleTracks, (label: string, index: number) => {
          MenuItem({ content: label, endIcon: this.subtitle && this.subtitleIndex === index ?
            (this.dark ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
            .contentFontColor(this.textColor()).height(52).id(`player-menu-subtitle-track-${index}`)
            .onClick(() => { this.choiceMenuVisible = false; this.onSubtitle(index); })
        }, (label: string, index: number) => `${index}:${label}`)
        if (this.subtitleLoading) { MenuItem({ content: '正在加载字幕…' }).enabled(false) }
        else if (this.subtitleFailed) {
          MenuItem({ content: '加载失败，点击重试' }).onClick(() => this.onSubtitlePrepare())
        } else if (this.subtitleTracks.length === 0) { MenuItem({ content: '当前视频暂无可用字幕' }).enabled(false) }
        MenuItem({ content: '字幕大字号', endIcon: this.subtitleLarge ?
          (this.dark ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.textColor()).height(52).id('player-menu-subtitle-large')
          .onClick(() => { this.choiceMenuVisible = false; this.onSubtitleLarge(!this.subtitleLarge); })
      } else {
      ForEach(this.optionLabels(kind), (label: string, index: number) => {
        MenuItem({ content: label, endIcon: this.currentOption(kind) === label ?
          (this.dark ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.textColor()).height(52).id(`player-menu-option-${kind}-${index}`)
          .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
          .onClick(() => this.selectOption(kind, index))
      }, (label: string) => label)
      }
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: this.dark ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  @Builder
  Choice(icon: Resource, title: string, kind: string) {
    PlaybackMenuRow({ hdrUiRatio: this.hdrUiRatio, rowWidth: Math.max(0, this.panelWidth - 28), rowId: `player-menu-${kind}`, icon: icon, title: title,
      detail: kind === 'quality' && this.qualitySwitching ? '切换中…' :
        kind === 'quality' && this.qualities.length === 0 ? '暂无可用画质' : this.currentOption(kind),
      actionEnabled: kind !== 'quality' || this.qualities.length > 0,
      onActivate: () => {
        this.choiceKind = kind; this.choiceMenuVisible = true;
        if (kind === 'subtitle') this.onSubtitlePrepare();
      }
    }).bindMenu(this.choiceMenuVisible && this.choiceKind === kind, this.Options(kind), this.menuOptions())
  }

  @Builder
  Line(icon: Resource, title: string, action: string) {
    PlaybackMenuRow({ hdrUiRatio: this.hdrUiRatio, rowWidth: Math.max(0, this.panelWidth - 28), rowId: `player-menu-${action}`, icon: icon, title: title,
      onActivate: () => this.onAction(action) })
  }

  @Builder
  SwitchLine(icon: Resource, title: string, key: string, value: boolean) {
    PlaybackMenuRow({ hdrUiRatio: this.hdrUiRatio, rowWidth: Math.max(0, this.panelWidth - 28), rowId: `player-menu-${key}`, icon: icon, title: title,
      isToggle: true, checked: value, onToggle: (checked: boolean) => this.onToggle(key, checked) })
  }

  @Builder
  Shortcut(icon: Resource, title: string, action: string) {
    Column({ space: 10 }) {
      Stack() {
        NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: 46, capsuleHeight: 46,
          onActivate: () => { if (action !== 'cast') this.onAction(action); } }) {
          PlaybackMenuIcon({ icon: icon, iconSize: action === 'watchlater' || action === 'cache' ? 32 : 24 })
            .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
        }
        if (action === 'cast') { AVCastPicker({ sessionType: 'video' }).width(46).height(46).opacity(0) }
      }.width(46).height(46)
      Text(title).fontSize(11).fontColor(this.textColor()).maxLines(1)
        .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
    }.width(68).id(`player-menu-${action}`)
  }

  private showSettings(show: boolean): void {
    this.choiceMenuVisible = false;
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => { this.settingsPage = show; });
  }

  @Builder
  private mainPage() {
    Scroll() {
      Column({ space: 12 }) {
        Scroll() {
          Row({ space: 8 }) {
            this.Shortcut($r('app.media.ref_apk_ps_watchlater'), '稍后再看', 'watchlater')
            this.Shortcut($r('app.media.ref_apk_ps_cache'), '缓存', 'cache')
            this.Shortcut($r('app.media.ref_ps_pip'), '小窗播放', 'pip')
            this.Shortcut($r('app.media.ref_ps_cast'), '投屏', 'cast')
          }.padding({ left: 14, right: 14 })
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Column({ space: 8 }) {
          PlaybackMenuRow({ hdrUiRatio: this.hdrUiRatio, rowWidth: Math.max(0, this.panelWidth - 28), rowId: 'player-menu-settings',
            icon: $r('app.media.ref_apk_ps_settings'), title: '播放设置', onActivate: () => this.showSettings(true) })
          if (!this.bottomQualityAvailable) {
            this.Choice($r('app.media.ref_ps_quality'), '清晰度', 'quality')
          }
          if (!this.bottomPlaybackSettingsAvailable) {
            this.Choice($r('app.media.ref_apk_ps_speed'), '倍速播放', 'rate')
          }
          this.Choice($r('app.media.ref_ps_loop'), '播放模式', 'mode')
          this.Choice($r('app.media.ref_ps_timer'), '定时关闭', 'sleep')
          if (this.customSleep) {
            NativeComposerSurface({ allCorners: true }) {
              Row({ space: 8 }) {
                TextInput({ text: this.customMinutes, placeholder: '1–180 分钟' }).type(InputType.Number)
                  .layoutWeight(1).height(40).backgroundColor(Color.Transparent)
                  .onChange((value: string) => { this.customMinutes = value; })
                Button('确定').onClick(() => {
                  const minutes = Number(this.customMinutes);
                  if (Number.isInteger(minutes) && minutes >= 1 && minutes <= 180) {
                    this.onToggle('stopAtEnd', false); this.onSleep(minutes); this.customSleep = false;
                  }
                })
              }.width('100%')
            }
          }
          this.SwitchLine($r('app.media.ref_ps_headphones'), '后台听视频', 'background', this.backgroundEnabled)
          if (!this.bottomPlaybackSettingsAvailable) {
            this.Choice($r('app.media.ref_ps_subtitle'), '字幕', 'subtitle')
            this.Line($r('app.media.ref_ps_danmaku'), '弹幕设置', 'danmaku')
          }
          this.SwitchLine($r('app.media.ref_ps_mirror'), '镜像翻转', 'mirror', this.mirror)
          this.Line($r('app.media.ref_ps_dislike'), '我不想看', 'dislike')
          this.Line($r('app.media.ref_apk_ps_report'), '举报', 'report')
          this.Line($r('app.media.ref_ps_feedback'), '播放反馈', 'feedback')
        }.width('100%').padding({ left: 14, right: 14 })
      }.width('100%').padding({ bottom: this.bottomInset + 20 })
    }.width(this.panelWidth).height('100%').align(Alignment.Top)
      .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
      .hitTestBehavior(this.settingsPage ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default)
  }

  @Builder
  private playbackPage() {
    Column() {
      Row({ space: 12 }) {
        Row() {
          NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true,
            capsuleWidth: 40, capsuleHeight: 40, onActivate: () => this.showSettings(false) }) {
            Image($r('app.media.ref_back')).width(22).height(22).fillColor(this.textColor()).hitTestBehavior(HitTestMode.None)
              .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
          }
        }.id('player-menu-settings-back')
        Text('播放设置').fontSize(16).fontColor(this.textColor()).layoutWeight(1)
          .foregroundFilter(playbackHdrUiFilter(this.hdrUiRatio))
      }.width('100%').height(48).padding({ left: 14, right: 14 }).margin({ bottom: 8 })
      Scroll() {
        Column({ space: 8 }) {
          this.Choice($r('app.media.ref_apk_ps_settings'), '画面尺寸', 'playback')
          this.Choice($r('app.media.ref_apk_ps_settings'), '连刷竖片画面', 'feedScale')
          this.Choice($r('app.media.ref_apk_ps_settings'), '适用范围', 'feedScope')
        }.width('100%').padding({ left: 14, right: 14, bottom: this.bottomInset + 20 })
      }.layoutWeight(1).width('100%').align(Alignment.Top)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
    }.width(this.panelWidth).height('100%')
      .hitTestBehavior(this.settingsPage ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
  }

  @Builder
  panelContent() {
    Column() {
      Row() { Rect().width(30).height(3).fill(this.dark ? '#808388' : '#909399').borderRadius(2) }
        .width('100%').height(24).justifyContent(FlexAlign.Center)
        .gesture(PanGesture({ direction: PanDirection.Down }).onActionEnd((event: GestureEvent) => {
          if (event.offsetY > 30) this.onAction('close');
        }))
      Stack({ alignContent: Alignment.Start }) {
        Row({ space: 0 }) {
          this.mainPage()
          this.playbackPage()
        }.width(this.panelWidth * 2).height('100%')
          .translate({ x: this.settingsPage ? -this.panelWidth : 0 })
      }.width('100%').layoutWeight(1).clip(true)
    }.width('100%').height('100%')
  }

  build() {
    Stack() {
      if (this.panelWidth > 0 && this.panelHeight > 0) {
        CommentMenuSurface({ surfaceWidth: this.panelWidth, surfaceHeight: this.panelHeight, radius: 24,
          interactive: false, followTouchLight: true }) {
          this.panelContent()
        }
      }
    }.width('100%').height('100%').onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width > 0 && Math.abs(width - this.panelWidth) > 0.5) this.panelWidth = width;
      if (height > 0 && Math.abs(height - this.panelHeight) > 0.5) this.panelHeight = height;
    })
  }
}
