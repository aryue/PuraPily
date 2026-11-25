import { preferences } from '@kit.ArkData';
import { AppNavigation } from '../services/AppNavigation';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageHeader } from '../components/PageHeader';
import { PageSurface } from '../components/PageSurface';
import { PageWallpaper } from '../components/PageWallpaper';
import { pageBackgroundColor, secondaryTextColor } from '../utils/SurfaceColors';
import { logError } from '../utils/Logger';
import { GlassMaterial } from '../utils/GlassMaterial';
import {
  SKIP_CATEGORIES,
  SKIP_MODE_OPTIONS,
  SkipCategoryMeta,
  SkipMode,
  SkipModeOption
} from '../model/SkipSegment';
import { SponsorBlockPrefs } from '../utils/SponsorBlockPrefs';

/**
 * 空降助手设置。
 *
 * - 社区片段开关与分类跳过方式：对应 SponsorBlock 的 category 列表；
 * - 番剧片头/片尾：playurl clip_info_list 的独立开关，默认跳过一次；
 * - 所有值写入 AppStorage 立即生效，并落盘到 my_app_settings。
 */
@Component
export struct SponsorBlockPage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = true;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('navIndicatorHeight') navIndicatorHeight: number = 0;
  @StorageLink('sponsorBlockEnabled') sbEnabled: boolean = false;
  @StorageLink('sponsorBlockPgcMode') pgcMode: string = SkipMode.Once;
  @StorageLink('sponsorBlockToast') toastEnabled: boolean = true;
  @StorageLink('sponsorBlockSeekInto') seekInto: boolean = false;
  @StorageLink('sponsorBlockModes') modesRaw: string = SponsorBlockPrefs.DEFAULT_MODES;

  private async persistBoolean(key: string, value: boolean): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(
        this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'my_app_settings' });
      pref.putSync(key, value);
      pref.flushSync();
    } catch (error) {
      logError('保存空降助手设置失败', error);
    }
  }

  private async persistString(key: string, value: string): Promise<void> {
    try {
      const pref = preferences.getPreferencesSync(
        this.getUIContext().getHostContext() as common.UIAbilityContext, { name: 'my_app_settings' });
      pref.putSync(key, value);
      pref.flushSync();
    } catch (error) {
      logError('保存空降助手设置失败', error);
    }
  }

  private modeLabel(mode: SkipMode): string {
    for (const option of SKIP_MODE_OPTIONS) {
      if (option.mode === mode) return option.label;
    }
    return '';
  }

  private categoryMode(index: number): SkipMode {
    const raw = this.modesRaw.length > 0 ? this.modesRaw : SponsorBlockPrefs.DEFAULT_MODES;
    const char = index < raw.length ? raw.charAt(index) : '1';
    const value = parseInt(char, 10);
    return SponsorBlockPrefs.modeFromIndex(Number.isFinite(value) ? value : 1);
  }

  private selectPgcMode(mode: SkipMode): void {
    this.pgcMode = mode;
    this.persistString('sponsorBlockPgcMode', mode);
  }

  private selectCategoryMode(index: number, mode: SkipMode): void {
    const next = SponsorBlockPrefs.setCategoryMode(index, mode);
    this.modesRaw = next;
    this.persistString('sponsorBlockModes', next);
  }

  private menuOptions(): MenuOptions {
    return {
      placement: Placement.BottomRight,
      enableArrow: false,
      borderRadius: 24,
      systemMaterial: deviceInfo.apiAvailable('26.0.0')
        ? GlassMaterial.create('menu', this.isDarkMode) : undefined
    };
  }

  @Builder
  SectionTitle(title: string) {
    Text(title).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(this.isDarkMode ? '#C9CDD3' : '#606773').width('100%')
      .padding({ left: 8, bottom: 2 })
  }

  @Builder
  PgcModeMenu() {
    Menu() {
      ForEach(SKIP_MODE_OPTIONS, (option: SkipModeOption) => {
        MenuItem({
          content: option.label,
          endIcon: SponsorBlockPrefs.modeFromName(this.pgcMode) === option.mode
            ? (this.isDarkMode ? $r('app.media.settings_menu_check_dark')
              : $r('app.media.settings_menu_check_light')) : undefined
        })
          .contentFontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          .height(52).id('sponsor-block-pgc-option-' + option.mode)
          .onClick(() => this.selectPgcMode(option.mode))
      }, (option: SkipModeOption) => option.mode)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({
        strokeWidth: LengthMetrics.vp(0.5),
        color: this.isDarkMode ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16),
        endMargin: LengthMetrics.vp(16)
      })
  }

  @Builder
  CategoryModeMenu(index: number) {
    Menu() {
      ForEach(SKIP_MODE_OPTIONS, (option: SkipModeOption) => {
        MenuItem({
          content: option.label,
          endIcon: this.categoryMode(index) === option.mode
            ? (this.isDarkMode ? $r('app.media.settings_menu_check_dark')
              : $r('app.media.settings_menu_check_light')) : undefined
        })
          .contentFontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          .height(52).id('sponsor-block-category-option-' + index + '-' + option.mode)
          .onClick(() => this.selectCategoryMode(index, option.mode))
      }, (option: SkipModeOption) => option.mode)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({
        strokeWidth: LengthMetrics.vp(0.5),
        color: this.isDarkMode ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16),
        endMargin: LengthMetrics.vp(16)
      })
  }

  @Builder
  ToggleRow(title: string, subtitle: string, value: boolean, onChange: (value: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
        Text(subtitle).fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor('#D34E7E')
        .onChange((next: boolean) => onChange(next))
    }.width('100%').constraintSize({ minHeight: 64 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    Stack() {
      PageWallpaper()
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column({ space: 6 }) {
            this.SectionTitle('空降助手')
            PageSurface() {
              Column() {
                this.ToggleRow('启用社区片段', '从 SponsorBlock 获取赞助、片头、片尾等标记', this.sbEnabled,
                  (value: boolean) => {
                    this.sbEnabled = value;
                    this.persistBoolean('sponsorBlockEnabled', value);
                  })
                Row() {
                  Column({ space: 4 }) {
                    Text('番剧片头/片尾').fontSize(15)
                      .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                    Text('来自 B 站 playurl 的官方 OP/ED 片段').fontSize(12)
                      .fontColor(secondaryTextColor(this.isDarkMode))
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Text(this.modeLabel(SponsorBlockPrefs.modeFromName(this.pgcMode)) + ' ›')
                    .fontSize(13).fontColor(secondaryTextColor(this.isDarkMode))
                }.width('100%').height(64).padding({ left: 16, right: 16 })
                  .id('sponsor-block-pgc-mode')
                  .bindMenu(this.PgcModeMenu(), this.menuOptions())
                this.ToggleRow('跳过提示', '跳过时在播放器内弹出 Toast', this.toastEnabled,
                  (value: boolean) => {
                    this.toastEnabled = value;
                    this.persistBoolean('sponsorBlockToast', value);
                  })
                this.ToggleRow('拖入片段中间也跳过', '默认只在刚进入片段的前 1 秒内自动跳过', this.seekInto,
                  (value: boolean) => {
                    this.seekInto = value;
                    this.persistBoolean('sponsorBlockSeekInto', value);
                  })
              }.width('100%').padding({ top: 4, bottom: 4 })
            }

            this.SectionTitle('分类跳过方式')
            PageSurface() {
              Column() {
                ForEach(SKIP_CATEGORIES, (meta: SkipCategoryMeta, index: number) => {
                  Row({ space: 10 }) {
                    Circle({ width: 10, height: 10 }).fill(meta.color)
                    Column({ space: 3 }) {
                      Text(meta.title).fontSize(15)
                        .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(this.modeLabel(this.categoryMode(index)) + ' ›')
                      .fontSize(13).fontColor(secondaryTextColor(this.isDarkMode))
                  }.width('100%').height(52).padding({ left: 16, right: 16 })
                    .id('sponsor-block-category-' + index)
                    .bindMenu(this.CategoryModeMenu(index), this.menuOptions())
                }, (meta: SkipCategoryMeta) => meta.key)
              }.width('100%').padding({ top: 4, bottom: 4 })
            }

            Text('社区片段来自 SponsorBlock 兼容服务器；启用后会把当前 bvid/cid 发给该服务器，不上传账号 Cookie。')
              .fontSize(12).fontColor(secondaryTextColor(this.isDarkMode))
              .width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
          }.width('100%').constraintSize({ maxWidth: 760 })
            .padding({
              left: 16,
              right: 16,
              top: this.statusBarHeight + 60,
              bottom: 32 + this.navIndicatorHeight
            })
        }.width('100%').height('100%').scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))

        PageHeader({ withTabs: false }) {
          Row({ space: 10 }) {
            HeaderBackButton({ onBack: () => { AppNavigation.back(); } })
            Text('空降助手').fontSize(18).fontWeight(FontWeight.Medium)
              .fontColor(this.isDarkMode ? '#E7E9EB' : '#18191C')
          }.height(44).width('100%').padding({ left: 8, top: this.statusBarHeight })
            .height(44 + this.statusBarHeight)
        }
      }.width('100%').height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
