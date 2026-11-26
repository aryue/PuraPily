import { common } from '@kit.AbilityKit';
import { PageSurface } from '../components/PageSurface';
import { secondaryTextColor } from '../utils/SurfaceColors';
import { logError } from '../utils/Logger';
import { invalidKeywordLineCount, keywordLines } from '../model/RecommendFilterModel';
import {
  FILTER_KEY_ENABLED,
  FILTER_KEY_EXEMPT_FOLLOWED,
  FILTER_KEY_HOT,
  FILTER_KEY_MIN_DURATION,
  FILTER_KEY_MIN_LIKE,
  FILTER_KEY_MIN_PLAY,
  FILTER_KEY_RANK,
  FILTER_KEY_RELATED,
  FILTER_KEY_SEARCH,
  FILTER_KEY_UNPLAYABLE,
  FilterUserEntry,
  RecommendFilterSettings
} from '../services/RecommendFilterSettings';
import { UserBehaviorService } from '../services/UserBehaviorService';

const DURATION_VALUES: number[] = [0, 30, 60, 90, 120];
const PLAY_VALUES: number[] = [0, 50, 100, 500, 1000];
const LIKE_VALUES: number[] = [0, 1, 2, 3, 4];

@Component
export struct ContentFilterPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @State refreshTick: number = 0;
  @State blockedCount: number = 0;
  @State whitelistCount: number = 0;
  @State titleKeywordCount: number = 0;
  @State upKeywordCount: number = 0;
  @State zoneKeywordCount: number = 0;
  @State editorKind: string = '';
  @State editorText: string = '';
  @State editorInvalid: number = 0;
  @State userEditorKind: string = '';
  @State userEntries: FilterUserEntry[] = [];
  @State newUserMid: string = '';
  @State newUserName: string = '';
  @State filterEnabled: boolean = true;
  @State minDuration: number = 0;
  @State minPlay: number = 0;
  @State minLikeRatio: number = 0;
  @State exemptFollowed: boolean = true;
  @State applyRelated: boolean = true;
  @State applyHot: boolean = false;
  @State applyRank: boolean = false;
  @State applySearch: boolean = false;
  @State removeUnplayable: boolean = false;

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.Context;
    RecommendFilterSettings.load(context).then(() => {
      this.refreshCounts();
    }).catch((error: Error) => {
      logError('[推荐过滤] 设置页加载失败', error);
      this.refreshCounts();
    });
  }

  private refreshCounts(): void {
    this.blockedCount = RecommendFilterSettings.blockedEntries().length;
    this.whitelistCount = RecommendFilterSettings.whitelistEntries().length;
    this.titleKeywordCount = keywordLines(RecommendFilterSettings.getKeywordText('title')).length;
    this.upKeywordCount = keywordLines(RecommendFilterSettings.getKeywordText('up')).length;
    this.zoneKeywordCount = keywordLines(RecommendFilterSettings.getKeywordText('zone')).length;
    this.filterEnabled = RecommendFilterSettings.getBoolean(FILTER_KEY_ENABLED, true);
    this.minDuration = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_DURATION, 0);
    this.minPlay = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_PLAY, 0);
    this.minLikeRatio = RecommendFilterSettings.getNumber(FILTER_KEY_MIN_LIKE, 0);
    this.exemptFollowed = RecommendFilterSettings.getBoolean(FILTER_KEY_EXEMPT_FOLLOWED, true);
    this.applyRelated = RecommendFilterSettings.getBoolean(FILTER_KEY_RELATED, true);
    this.applyHot = RecommendFilterSettings.getBoolean(FILTER_KEY_HOT, false);
    this.applyRank = RecommendFilterSettings.getBoolean(FILTER_KEY_RANK, false);
    this.applySearch = RecommendFilterSettings.getBoolean(FILTER_KEY_SEARCH, false);
    this.removeUnplayable = RecommendFilterSettings.getBoolean(FILTER_KEY_UNPLAYABLE, false);
    this.refreshTick++;
  }

  private textColor(): string {
    return this.isDarkMode ? '#E7E9EB' : '#18191C';
  }

  private subColor(): string {
    return this.pageWallpaperEnabled ? secondaryTextColor(this.isDarkMode) : '#757A81';
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
  }

  private numberValues(key: string): number[] {
    if (key === FILTER_KEY_MIN_DURATION) return DURATION_VALUES;
    if (key === FILTER_KEY_MIN_PLAY) return PLAY_VALUES;
    return LIKE_VALUES;
  }

  private numberLabels(key: string): string[] {
    if (key === FILTER_KEY_MIN_DURATION) return ['关闭', '30 秒', '60 秒', '90 秒', '120 秒'];
    if (key === FILTER_KEY_MIN_PLAY) return ['关闭', '50', '100', '500', '1000'];
    return ['关闭', '1%', '2%', '3%', '4%'];
  }

  private currentNumberValue(key: string): number {
    if (key === FILTER_KEY_MIN_DURATION) return this.minDuration;
    if (key === FILTER_KEY_MIN_PLAY) return this.minPlay;
    return this.minLikeRatio;
  }

  private currentNumberLabel(key: string): string {
    const values = this.numberValues(key);
    const labels = this.numberLabels(key);
    const index = values.indexOf(this.currentNumberValue(key));
    return labels[index >= 0 ? index : 0];
  }

  private chooseNumber(key: string, index: number): void {
    const values = this.numberValues(key);
    if (index < 0 || index >= values.length) return;
    RecommendFilterSettings.setNumber(key, values[index]);
    this.applyNumberState(key, values[index]);
    this.refreshTick++;
  }

  private applyNumberState(key: string, value: number): void {
    if (key === FILTER_KEY_MIN_DURATION) this.minDuration = value;
    else if (key === FILTER_KEY_MIN_PLAY) this.minPlay = value;
    else this.minLikeRatio = value;
  }

  private currentSwitchValue(key: string, fallback: boolean): boolean {
    if (key === FILTER_KEY_ENABLED) return this.filterEnabled;
    if (key === FILTER_KEY_EXEMPT_FOLLOWED) return this.exemptFollowed;
    if (key === FILTER_KEY_RELATED) return this.applyRelated;
    if (key === FILTER_KEY_HOT) return this.applyHot;
    if (key === FILTER_KEY_RANK) return this.applyRank;
    if (key === FILTER_KEY_SEARCH) return this.applySearch;
    if (key === FILTER_KEY_UNPLAYABLE) return this.removeUnplayable;
    return fallback;
  }

  private applyBooleanState(key: string, value: boolean): void {
    if (key === FILTER_KEY_ENABLED) this.filterEnabled = value;
    else if (key === FILTER_KEY_EXEMPT_FOLLOWED) this.exemptFollowed = value;
    else if (key === FILTER_KEY_RELATED) this.applyRelated = value;
    else if (key === FILTER_KEY_HOT) this.applyHot = value;
    else if (key === FILTER_KEY_RANK) this.applyRank = value;
    else if (key === FILTER_KEY_SEARCH) this.applySearch = value;
    else if (key === FILTER_KEY_UNPLAYABLE) this.removeUnplayable = value;
  }

  private keywordCount(kind: string): number {
    if (kind === 'up') return this.upKeywordCount;
    if (kind === 'zone') return this.zoneKeywordCount;
    return this.titleKeywordCount;
  }

  private toggleBoolean(key: string, value: boolean, fallback: boolean): void {
    RecommendFilterSettings.setBoolean(key, value);
    this.applyBooleanState(key, value);
    this.refreshTick++;
  }

  private openKeywordEditor(kind: string): void {
    this.editorKind = kind;
    this.editorText = RecommendFilterSettings.getKeywordText(kind);
    this.editorInvalid = invalidKeywordLineCount(this.editorText);
  }

  private closeKeywordEditor(): void {
    this.editorKind = '';
    this.editorText = '';
    this.editorInvalid = 0;
  }

  private saveKeywordEditor(): void {
    this.editorInvalid = invalidKeywordLineCount(this.editorText);
    RecommendFilterSettings.setKeywordText(this.editorKind, this.editorText);
    if (this.editorInvalid > 0) {
      this.toast(`已保存；${this.editorInvalid} 行正则无效，将在过滤时跳过`);
    } else {
      this.toast('关键词已保存');
    }
    this.closeKeywordEditor();
    this.refreshCounts();
  }

  private keywordTitle(kind: string): string {
    if (kind === 'up') return 'UP 名称关键词';
    if (kind === 'zone') return '分区关键词';
    return '标题关键词';
  }

  private openUserEditor(kind: string): void {
    this.userEditorKind = kind;
    this.userEntries = kind === 'blocked'
      ? RecommendFilterSettings.blockedEntries()
      : RecommendFilterSettings.whitelistEntries();
    this.newUserMid = '';
    this.newUserName = '';
  }

  private closeUserEditor(): void {
    this.userEditorKind = '';
    this.userEntries = [];
    this.newUserMid = '';
    this.newUserName = '';
  }

  private reloadUserEntries(): void {
    this.userEntries = this.userEditorKind === 'blocked'
      ? RecommendFilterSettings.blockedEntries()
      : RecommendFilterSettings.whitelistEntries();
    this.refreshCounts();
  }

  private addUser(): void {
    const mid = this.newUserMid.trim();
    if (!/^[1-9][0-9]*$/.test(mid)) {
      this.toast('请输入有效的数字 UID');
      return;
    }
    const name = this.newUserName.trim();
    if (this.userEditorKind === 'blocked') {
      UserBehaviorService.addBlockedUploader(mid, name);
    } else {
      RecommendFilterSettings.addWhitelist(mid, name);
    }
    this.newUserMid = '';
    this.newUserName = '';
    this.reloadUserEntries();
    this.toast(this.userEditorKind === 'blocked' ? '已加入推荐屏蔽' : '已加入白名单');
  }

  private removeUser(mid: string): void {
    if (this.userEditorKind === 'blocked') {
      UserBehaviorService.removeBlockedUploader(mid);
    } else {
      RecommendFilterSettings.removeWhitelist(mid);
    }
    this.reloadUserEntries();
  }

  @Builder
  SectionTitle(title: string) {
    Text(title).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(this.isDarkMode ? '#C9CDD3' : '#606773').width('100%')
      .padding({ left: 8 })
  }

  @Builder
  SwitchRow(key: string, title: string, subtitle: string, fallback: boolean) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.textColor())
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(12).fontColor(this.subColor())
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.currentSwitchValue(key, fallback) })
        .selectedColor('#D34E7E')
        .onChange((value: boolean) => this.toggleBoolean(key, value, fallback))
    }.width('100%').constraintSize({ minHeight: subtitle.length > 0 ? 72 : 56 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  @Builder
  NumberRow(key: string, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.textColor())
        Text(subtitle).fontSize(12).fontColor(this.subColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.currentNumberLabel(key) + ' ›').fontSize(13).fontColor(this.subColor())
    }.width('100%').constraintSize({ minHeight: 72 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .id('rcmd-filter-' + key)
      .bindMenu(this.NumberMenu(key), this.menuOptions())
  }

  @Builder
  NumberMenu(key: string) {
    Menu() {
      ForEach(this.numberLabels(key), (label: string, index: number) => {
        MenuItem({ content: label + (this.currentNumberLabel(key) === label ? '  ✓' : '') })
          .contentFontColor(this.textColor())
          .height(48)
          .onClick(() => { this.chooseNumber(key, index); })
      }, (label: string) => key + label)
    }.width(208).radius(20).font({ size: 15 })
  }

  private menuOptions(): MenuOptions {
    return {
      placement: Placement.BottomRight,
      enableArrow: false,
      borderRadius: 20
    };
  }

  @Builder
  KeywordRow(kind: string, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.textColor())
        Text(subtitle).fontSize(12).fontColor(this.subColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(`${this.keywordCount(kind)} 条 ›`)
        .fontSize(13).fontColor(this.subColor())
    }.width('100%').constraintSize({ minHeight: 72 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .id('rcmd-filter-keyword-' + kind)
      .onClick(() => this.openKeywordEditor(kind))
  }

  @Builder
  UserRow(kind: string, title: string, subtitle: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.textColor())
        Text(subtitle).fontSize(12).fontColor(this.subColor())
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(`${kind === 'blocked' ? this.blockedCount : this.whitelistCount} 人 ›`)
        .fontSize(13).fontColor(this.subColor())
    }.width('100%').constraintSize({ minHeight: 72 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .id('rcmd-filter-user-' + kind)
      .onClick(() => this.openUserEditor(kind))
  }

  @Builder
  KeywordEditor() {
    Stack({ alignContent: Alignment.Top }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
      Column({ space: 12 }) {
        Row() {
          Text(this.keywordTitle(this.editorKind)).fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.textColor()).layoutWeight(1)
          Text('每行一条正则 · 大小写不敏感').fontSize(12).fontColor(this.subColor())
        }.width('100%')
        TextArea({
          text: this.editorText,
          placeholder: '例如：影视解说\\n标题.*片段'
        })
          .width('100%').height(150)
          .padding(12)
          .backgroundColor(this.isDarkMode ? '#25272B' : '#F4F5F7')
          .fontColor(this.textColor())
          .fontSize(14)
          .onChange((value: string) => {
            this.editorText = value;
            this.editorInvalid = invalidKeywordLineCount(value);
          })
        if (this.editorInvalid > 0) {
          Text(`有 ${this.editorInvalid} 行正则无效，保存后仅跳过这些行`)
            .fontSize(12).fontColor('#E64545').width('100%')
        }
        Row({ space: 10 }) {
          Button('清空')
            .layoutWeight(1).height(42)
            .backgroundColor(this.isDarkMode ? '#2A2D30' : '#ECEEF1')
            .fontColor('#D34E7E')
            .onClick(() => {
              this.editorText = '';
              this.editorInvalid = 0;
            })
          Button('取消')
            .layoutWeight(1).height(42)
            .backgroundColor(this.isDarkMode ? '#2A2D30' : '#ECEEF1')
            .fontColor(this.textColor())
            .onClick(() => this.closeKeywordEditor())
          Button('保存')
            .layoutWeight(1).height(42)
            .backgroundColor('#D34E7E').fontColor(Color.White)
            .onClick(() => this.saveKeywordEditor())
        }.width('100%')
      }
      .width('90%').constraintSize({ maxWidth: 600 })
      .margin({ top: this.statusBarHeight + 36 })
      .padding(20).borderRadius(24)
      .backgroundColor(this.isDarkMode ? '#1B1D21' : '#FFFFFF')
    }.width('100%').height('100%').zIndex(30)
  }

  @Builder
  UserEditor() {
    Stack({ alignContent: Alignment.Top }) {
      Column().width('100%').height('100%').backgroundColor('#66000000')
      Column({ space: 12 }) {
        Row() {
          Text(this.userEditorKind === 'blocked' ? '推荐屏蔽用户' : '白名单用户')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.textColor()).layoutWeight(1)
          Text('屏蔽优先于白名单').fontSize(12).fontColor(this.subColor())
        }.width('100%')
        Scroll() {
          Column() {
            if (this.userEntries.length === 0) {
              Text('暂无用户').fontSize(13).fontColor(this.subColor())
                .width('100%').padding({ top: 24, bottom: 24 }).textAlign(TextAlign.Center)
            }
            ForEach(this.userEntries, (entry: FilterUserEntry) => {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(entry.name || `UID:${entry.mid}`).fontSize(14).fontColor(this.textColor())
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(entry.mid).fontSize(11).fontColor(this.subColor())
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button('移除')
                  .height(32).fontSize(12)
                  .backgroundColor(this.isDarkMode ? '#3A2328' : '#FCEAF0')
                  .fontColor('#D34E7E')
                  .onClick(() => this.removeUser(entry.mid))
              }.width('100%').height(52)
                .border({ width: { bottom: 0.5 }, color: this.isDarkMode ? '#2A2D30' : '#EEEEEE' })
            }, (entry: FilterUserEntry) => entry.mid)
          }.width('100%')
        }.width('100%').height(130).scrollBar(BarState.Off)

        Row({ space: 8 }) {
          TextInput({ text: this.newUserMid, placeholder: 'UID' })
            .type(InputType.Number)
            .layoutWeight(1).height(42)
            .fontColor(this.textColor())
            .backgroundColor(this.isDarkMode ? '#25272B' : '#F4F5F7')
            .onChange((value: string) => { this.newUserMid = value; })
          TextInput({ text: this.newUserName, placeholder: '备注名（可选）' })
            .layoutWeight(1).height(42)
            .fontColor(this.textColor())
            .backgroundColor(this.isDarkMode ? '#25272B' : '#F4F5F7')
            .onChange((value: string) => { this.newUserName = value; })
        }.width('100%')

        Row({ space: 10 }) {
          Button('关闭')
            .layoutWeight(1).height(42)
            .backgroundColor(this.isDarkMode ? '#2A2D30' : '#ECEEF1')
            .fontColor(this.textColor())
            .onClick(() => this.closeUserEditor())
          Button('添加')
            .layoutWeight(1).height(42)
            .backgroundColor('#D34E7E').fontColor(Color.White)
            .onClick(() => this.addUser())
        }.width('100%')
      }
      .width('92%').constraintSize({ maxWidth: 620 })
      .margin({ top: this.statusBarHeight + 36 })
      .padding(20).borderRadius(24)
      .backgroundColor(this.isDarkMode ? '#1B1D21' : '#FFFFFF')
    }.width('100%').height('100%').zIndex(30)
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 6 }) {
          this.SectionTitle('推荐过滤')
          Column() {
            PageSurface() {
              Column() {
                this.SwitchRow(FILTER_KEY_ENABLED, '启用本地推荐过滤',
                  '只影响推荐、相关、热门、排行与搜索，不影响手动打开的视频', true)
                this.NumberRow(FILTER_KEY_MIN_LIKE, '点赞率下限',
                  '低于该比例的推荐会被移除；需要接口返回点赞数')
                this.NumberRow(FILTER_KEY_MIN_DURATION, '视频时长下限',
                  '只过滤已知时长；短视频片段与预告更容易被命中')
                this.NumberRow(FILTER_KEY_MIN_PLAY, '播放量下限',
                  '只过滤已知播放量；首页 App 端按封面播放数解析')
                this.SwitchRow(FILTER_KEY_EXEMPT_FOLLOWED, '已关注 UP 豁免',
                  '首页推荐中已关注 UP 的内容不会被常规规则过滤', true)
                this.SwitchRow(FILTER_KEY_UNPLAYABLE, '屏蔽无权查看视频',
                  '仅对 App 端首页推荐生效，如充电专属视频', false)
              }.width('100%').padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%').margin({ bottom: 18 })

          this.SectionTitle('应用到其它场景')
          Column() {
            PageSurface() {
              Column() {
                this.SwitchRow(FILTER_KEY_RELATED, '详情页相关视频',
                  '与推荐流共用关键词、用户、时长和互动数据规则', true)
                this.SwitchRow(FILTER_KEY_HOT, '热门视频',
                  '开启后应用完整规则；分区关键词始终生效', false)
                this.SwitchRow(FILTER_KEY_RANK, '分区排行',
                  'UGC 应用完整规则，番剧/影视仅过滤标题关键词', false)
                this.SwitchRow(FILTER_KEY_SEARCH, '搜索结果',
                  '仅过滤标题关键词与推荐屏蔽用户，不改动搜索排序', false)
              }.width('100%').padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%').margin({ bottom: 18 })

          this.SectionTitle('关键词')
          Column() {
            PageSurface() {
              Column() {
                this.KeywordRow('title', '标题关键词', '每行一条独立正则，命中任一即过滤')
                this.KeywordRow('up', 'UP 名称关键词', '按 UP 主昵称匹配，避免误伤同名标题')
                this.KeywordRow('zone', '分区关键词', '仅 App 推荐、热门和 UGC 排行可用')
              }.width('100%').padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%').margin({ bottom: 18 })

          this.SectionTitle('用户')
          Column() {
            PageSurface() {
              Column() {
                this.UserRow('blocked', '推荐屏蔽用户', '优先级最高，命中后直接移除，不被白名单或已关注豁免')
                this.UserRow('whitelist', '白名单用户', '跳过关键词、时长、播放量与点赞率规则')
              }.width('100%').padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%').margin({ bottom: 18 })

          Column() {
            PageSurface() {
              Column({ space: 8 }) {
                Text('规则说明').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.textColor())
                Text('· 过滤器在接口返回后、进入列表前执行，不会修改账号在 B 站的推荐偏好。')
                  .fontSize(12).fontColor(this.subColor())
                Text('· 正则逐行独立编译；非法行会被跳过，不会拖垮其它关键词。')
                  .fontSize(12).fontColor(this.subColor())
                Text('· 条件过严会让首屏变稀；首页会在请求后继续补取，其它列表需要继续下滑。')
                  .fontSize(12).fontColor(this.subColor())
              }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
            }
          }.width('100%').margin({ bottom: 18 })
        }
        .width('100%').constraintSize({ maxWidth: 760 })
        .padding({
          left: 16,
          right: 16,
          top: this.statusBarHeight + 60,
          bottom: 32 + this.navIndicatorHeight
        })
      }
      .width('100%').height('100%').scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      if (this.editorKind.length > 0) {
        this.KeywordEditor()
      }
      if (this.userEditorKind.length > 0) {
        this.UserEditor()
      }
    }
    .width('100%').height('100%')
    .id('content-filter-' + this.refreshTick)
  }
}
