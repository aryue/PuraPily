import { PlaybackControlSurface } from './PlaybackControlSurface';
import { PlaybackGlassAction } from './PlaybackGlassAction';
import { playbackControlMaterial } from '../utils/PlaybackMenuStyle';
import { NativeComposerSurface } from './NativeComposerSurface';
import { DanmakuConfig } from '../model/DanmakuItem'

@Component
struct ReferenceDmSlider {
  @StorageLink('isDarkMode') private dark: boolean = true;
  @Prop title: string = ''
  @Prop value: number = 0
  @Prop min: number = 0
  @Prop max: number = 100
  @Prop step: number = 1
  @Prop label: string = ''
  @Prop labelWidth: number = 34
  @Prop ticks: boolean = false
  onChange: (value: number) => void = () => {}
  build() {
    Row({ space: 6 }) {
      Text(this.title).fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').width(68)
      Slider({ value: this.value, min: this.min, max: this.max, step: this.step, style: SliderStyle.OutSet })
        .layoutWeight(1).height(40).trackThickness(4).blockSize({ width: 14, height: 14 })
        .systemMaterial(playbackControlMaterial(this.dark))
        .blockColor('#FF6699').selectedColor('#FF6699').trackColor('#737477')
        .showSteps(this.ticks).stepColor('#FFFFFF').stepSize(4)
        .onChange((next: number) => { this.onChange(next) })
      Text(this.label).fontSize(12).fontColor(this.dark ? '#A3A6AD' : '#61666D').width(this.labelWidth).textAlign(TextAlign.End)
    }.width('100%').height(56).padding({ left: 16, right: 16 })
  }
}

@Component
struct ReferenceDmTypeButton {
  @Prop label: string = ''
  @Prop blocked: boolean = false
  onIcon: Resource = $r('app.media.ref_dm_fixed_on')
  offIcon: Resource = $r('app.media.ref_dm_fixed_off')
  onToggle: () => void = () => {}
  private whiteFilter: ColorFilter = new ColorFilter([0.965, 0, 0, 0, 0, 0.969, 0, 0, 0, 0, 0.973, 0, 0, 0, 0, 0, 0, 0, 1, 0])
  private darkFilter: ColorFilter = new ColorFilter([0.095, 0, 0, 0, 0, 0.098, 0, 0, 0, 0, 0.11, 0, 0, 0, 0, 0, 0, 0, 1, 0])
  private pinkFilter: ColorFilter = new ColorFilter([1, 0, 0, 0, 0, 0.4, 0, 0, 0, 0, 0.6, 0, 0, 0, 0, 0, 0, 0, 1, 0])
  @StorageLink('isDarkMode') private dark: boolean = true;
  @State private buttonWidth: number = 0;
  build() {
    Column({ space: 8 }) {
      Stack() { PlaybackGlassAction({ actionHeight: Math.max(1, this.buttonWidth),
        actionId: `player-danmaku-type-${this.label}`, onActivate: () => this.onToggle() }) {
        Image(this.blocked ? this.offIcon : this.onIcon).width(34).height(34)
          .colorFilter(this.blocked ? this.pinkFilter : this.dark ? this.whiteFilter : this.darkFilter)
      } }.width('100%').aspectRatio(1).onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width);
        if (width > 0 && Math.abs(width - this.buttonWidth) > 0.5) this.buttonWidth = width;
      })
      Text(this.label).fontSize(12).fontColor(this.dark ? '#F6F7F8' : '#18191C')
    }.width('100%')
  }
}

@Component
struct ReferenceDmSwitch {
  @StorageLink('isDarkMode') private dark: boolean = true;
  @Prop title: string = ''
  @Prop desc: string = ''
  @Prop value: boolean = false
  onChange: (value: boolean) => void = () => {}
  build() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(this.title).fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').width('100%')
        Text(this.desc).fontSize(12).fontColor(this.dark ? '#A3A6AD' : '#61666D').width('100%')
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.value }).width(38).height(22)
        .systemMaterial(playbackControlMaterial(this.dark))
        .selectedColor('#D34E7E').onChange((next: boolean) => { this.onChange(next) })
    }.width('100%').height(78).padding({ left: 16, right: 18 })
  }
}

/** 横竖屏共享原生材质作用域；写回配置，不替换控制器已持有的对象。 */
@Component
export struct ReferenceDanmakuSettings {
  @StorageLink('isDarkMode') private dark: boolean = true;
  @Link config: DanmakuConfig
  onChanged: () => void = () => {}
  // ⭐ 画布几何（由 DanmakuController 在尺寸/设置变更后写入）：
  //   用来把「显示区域 10%」翻译成实际行数，拖动时即时预览。
  //   行数 = floor(画布高 × 区域% ÷ 轨道高)，轨道高 = 字号 × 行高；不足一行按一行兜底。
  @StorageProp('danmakuCanvasHeight') private canvasHeight: number = 0
  @StorageProp('danmakuTrackHeight') private trackHeight: number = 0
  @State areaPercent: number = 100
  @State areaStep: number = 4
  @State opacityPercent: number = 100
  @State fontPercent: number = 100
  @State speedIndex: number = 2
  @State fixedBlocked: boolean = false
  @State scrollBlocked: boolean = false
  @State colorBlocked: boolean = false
  @State advancedBlocked: boolean = false
  @State countBlocked: boolean = false
  @State duplicatesHidden: boolean = false
  @State bottomHidden: boolean = false
  @State keywordsEnabled: boolean = true
  @State keywordEditor: boolean = false
  @State keyword: string = ''
  @State keywords: string[] = []
  private durations: number[] = [14000, 10000, 7000, 5000, 3000]
  private areaPercents: number[] = [10, 25, 50, 75, 100]
  private speedLabels: string[] = ['极慢', '较慢', '标准', '较快', '极快']

  aboutToAppear(): void {
    this.areaPercent = Math.max(10, Math.min(100, Math.round(this.config.displayArea * 100)))
    // Keep existing intermediate percentages until the user selects one of the five stops.
    const upper = this.areaPercents.findIndex((value: number) => value >= this.areaPercent)
    this.areaStep = upper <= 0 ? 0 : upper - 1 +
      (this.areaPercent - this.areaPercents[upper - 1]) / (this.areaPercents[upper] - this.areaPercents[upper - 1])
    this.opacityPercent = Math.round(this.config.opacity * 100)
    this.fontPercent = Math.round(this.config.fontSize / 28 * 100)
    this.speedIndex = this.durations.reduce((best: number, duration: number, index: number) =>
      Math.abs(duration - this.config.scrollDuration) < Math.abs(this.durations[best] - this.config.scrollDuration) ? index : best, 0)
    this.fixedBlocked = !this.config.showTop
    this.scrollBlocked = !this.config.showScroll
    this.colorBlocked = this.config.blockColorful
    this.advancedBlocked = !this.config.showAdvanced
    this.countBlocked = this.config.blockCounted
    this.duplicatesHidden = this.config.hideDuplicates
    this.bottomHidden = !this.config.showBottom
    this.keywordsEnabled = this.config.keywordFilterEnabled
    this.keywords = this.config.blockKeywords.slice()
  }

  private changed(): void { this.onChanged() }

  /**
   * 当前几何下「区域 percent%」能排几行（与 TrackManager 完全同口径）：
   *   floor(画布高 × percent / 100 ÷ 轨道高)，至少 1 行（只要还有一条轨道就显示）。
   * 画布还没量出来时返回 0，标签只显示百分比。
   */
  private previewRows(percent: number): number {
    if (this.canvasHeight <= 0 || this.trackHeight <= 0) {
      return 0
    }
    return Math.max(1, Math.floor(this.canvasHeight * (percent / 100) / this.trackHeight))
  }

  private areaLabel(): string {
    const rows = this.previewRows(this.areaPercent)
    return rows > 0 ? `${this.areaPercent}% · ${rows}行` : `${this.areaPercent}%`
  }

  @Builder
  divider() {
    Row().width('100%').height(0.5).backgroundColor(this.dark ? '#14FFFFFF' : '#14000000')
  }

  @Builder
  heading(text: string) {
    Text(text).fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').width('100%')
      .margin({ top: 28, bottom: 12 })
  }

  private addKeyword(): void {
    const value = this.keyword.trim()
    if (value.length === 0) return
    if (!this.keywords.includes(value)) this.keywords = this.keywords.concat([value])
    this.config.blockKeywords = this.keywords.slice()
    this.keyword = ''
    this.changed()
  }

  build() {
    Stack() { PlaybackControlSurface({ viewportInset: 12 }) {
    Scroll() {
      Column() {
        Text('弹幕设置').fontSize(16).fontColor(this.dark ? '#F6F7F8' : '#18191C').width('100%').margin({ bottom: 14 })
        Column() {
          ReferenceDmSlider({ title: '显示区域', value: this.areaStep, min: 0, max: 4, step: 1,
            label: this.areaLabel(), labelWidth: 76, ticks: true, onChange: (value: number) => {
            this.areaStep = Math.max(0, Math.min(4, Math.round(value)))
            this.areaPercent = this.areaPercents[this.areaStep]
            this.config.displayArea = this.areaPercent / 100; this.changed()
          } })
          // 行划分口径（用户问过"间距是怎么划分的"）：区域只决定用几行，不改变单行高度
          Text('行数 = 画面高 × 显示区域 ÷ 行高，不足一行按一行显示；行高随字号与横屏放大变化')
            .fontSize(11).fontColor(this.dark ? '#8A8D94' : '#9296A0').width('100%')
            .padding({ left: 16, right: 16, bottom: 10 })
          this.divider()
          ReferenceDmSlider({ title: '不透明度', value: this.opacityPercent, min: 0, max: 100, step: 5,
            label: `${this.opacityPercent}%`, onChange: (value: number) => {
            this.opacityPercent = Math.round(value); this.config.opacity = this.opacityPercent / 100; this.changed()
          } })
          this.divider()
          ReferenceDmSlider({ title: '字体大小', value: this.fontPercent, min: 50, max: 170, step: 5,
            label: `${this.fontPercent}%`, onChange: (value: number) => {
            this.fontPercent = Math.round(value); this.config.fontSize = 28 * this.fontPercent / 100; this.changed()
          } })
          this.divider()
          ReferenceDmSlider({ title: '弹幕速度', value: this.speedIndex, min: 0, max: 4, step: 1,
            label: this.speedLabels[this.speedIndex], ticks: true, onChange: (value: number) => {
            this.speedIndex = Math.round(value); this.config.scrollDuration = this.durations[this.speedIndex]; this.changed()
          } })
        }.width('100%').borderRadius(12)

        this.heading('画面防挡')
        Column() {
          Text('按弹幕类型屏蔽').fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').width('100%')
            .padding({ left: 16, right: 16, top: 18, bottom: 16 })
          Row({ space: 5 }) {
            ReferenceDmTypeButton({ label: '固定', blocked: this.fixedBlocked,
              onIcon: $r('app.media.ref_dm_fixed_on'), offIcon: $r('app.media.ref_dm_fixed_off'), onToggle: () => {
              this.fixedBlocked = !this.fixedBlocked
              this.config.showTop = !this.fixedBlocked; this.config.showBottom = !this.fixedBlocked
              this.bottomHidden = this.fixedBlocked; this.changed()
            } }).layoutWeight(1)
            ReferenceDmTypeButton({ label: '滚动', blocked: this.scrollBlocked,
              onIcon: $r('app.media.ref_dm_scroll_on'), offIcon: $r('app.media.ref_dm_scroll_off'), onToggle: () => {
              this.scrollBlocked = !this.scrollBlocked; this.config.showScroll = !this.scrollBlocked; this.changed()
            } }).layoutWeight(1)
            ReferenceDmTypeButton({ label: '彩色', blocked: this.colorBlocked,
              onIcon: $r('app.media.ref_dm_color_on'), offIcon: $r('app.media.ref_dm_color_off'), onToggle: () => {
              this.colorBlocked = !this.colorBlocked; this.config.blockColorful = this.colorBlocked; this.changed()
            } }).layoutWeight(1)
            ReferenceDmTypeButton({ label: '高级', blocked: this.advancedBlocked,
              onIcon: $r('app.media.ref_dm_advanced_on'), offIcon: $r('app.media.ref_dm_advanced_off'), onToggle: () => {
              this.advancedBlocked = !this.advancedBlocked; this.config.showAdvanced = !this.advancedBlocked; this.changed()
            } }).layoutWeight(1)
            ReferenceDmTypeButton({ label: '计数', blocked: this.countBlocked,
              onIcon: $r('app.media.ref_dm_count_on'), offIcon: $r('app.media.ref_dm_count_off'), onToggle: () => {
              this.countBlocked = !this.countBlocked; this.config.blockCounted = this.countBlocked; this.changed()
            } }).layoutWeight(1)
          }.width('100%').padding({ left: 16, right: 16, bottom: 18 })
          this.divider()
          ReferenceDmSwitch({ title: '重复弹幕隐藏', desc: '大量内容相同的弹幕会被隐藏', value: this.duplicatesHidden, onChange: (value: boolean) => {
            this.duplicatesHidden = value; this.config.hideDuplicates = value; this.changed()
          } })
          this.divider()
          ReferenceDmSwitch({ title: '字幕防挡', desc: '底部弹幕会被隐藏', value: this.bottomHidden, onChange: (value: boolean) => {
            this.bottomHidden = value; this.config.showBottom = !value; this.changed()
          } })
          this.divider()
          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text('人像防挡').fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').width('100%')
              Text('当前播放器暂无人像蒙版数据').fontSize(12).fontColor(this.dark ? '#A3A6AD' : '#61666D').width('100%')
            }.layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: false }).width(38).height(22).enabled(false)
          }.width('100%').height(78).padding({ left: 16, right: 18 })
        }.width('100%').borderRadius(12)

        this.heading('更多工具')
        Column() {
          ReferenceDmSwitch({ title: '弹幕观看屏蔽词', desc: '仅对我不展示特定弹幕', value: this.keywordsEnabled, onChange: (value: boolean) => {
            this.keywordsEnabled = value; this.config.keywordFilterEnabled = value; this.changed()
          } })
          PlaybackGlassAction({ actionHeight: 40, actionId: 'player-danmaku-keyword-editor',
            onActivate: () => { this.keywordEditor = !this.keywordEditor } }) {
          Row() {
            Text('添加屏蔽词').fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').layoutWeight(1)
            Image($r('app.media.ref_chevron_right')).width(16).height(16).fillColor(this.dark ? '#F6F7F8' : '#18191C')
          }.width('100%').height(40).padding({ left: 16, right: 16 }).borderRadius(10)
            }
          if (this.keywordEditor) {
            Row({ space: 8 }) {
              Row() {
                NativeComposerSurface({ allCorners: true }) {
                  TextInput({ text: this.keyword, placeholder: '输入屏蔽词' }).width('100%').height(36).fontSize(14)
                    .id('danmaku-keyword-input').placeholderFont({ size: 14 }).placeholderColor('#81848B')
                    .fontColor(this.dark ? '#F6F7F8' : '#18191C').backgroundColor(Color.Transparent)
                    .onChange((value: string) => { this.keyword = value })
                    .onSubmit(() => { this.addKeyword() })
                }
              }.layoutWeight(1)
              Stack() { PlaybackGlassAction({ actionHeight: 36, onActivate: () => this.addKeyword() }) {
                Text('添加').fontSize(14).fontColor('#FF6699')
              } }.width(56)
            }.width('100%').margin({ top: 12 })
            ForEach(this.keywords, (word: string) => {
              Row() {
                Text(word).fontSize(14).fontColor(this.dark ? '#F6F7F8' : '#18191C').layoutWeight(1)
                Stack() { PlaybackGlassAction({ actionHeight: 32, onActivate: () => {
                  this.keywords = this.keywords.filter((item: string) => item !== word)
                  this.config.blockKeywords = this.keywords.slice(); this.changed()
                } }) { Text('删除').fontSize(12).fontColor('#FF6699') } }.width(52)
              }.width('100%').height(40)
            }, (word: string) => word)
          }
        }.width('100%').padding({ left: 16, right: 16, bottom: 16 }).borderRadius(12)

      }.width('100%').padding({ left: 4, right: 4, top: 12, bottom: 12 })
    }.width('100%').height('100%').scrollBar(BarState.Off).clip(true).id('player-danmaku-scroll')
    } }.width('100%').height('100%')
  }
}
