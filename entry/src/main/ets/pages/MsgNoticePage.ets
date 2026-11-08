import { HeaderBackButton } from '../components/HeaderBackButton';
import { PageSurface } from '../components/PageSurface';
import { pageBackgroundColor } from '../utils/SurfaceColors';
import { PageHeader } from '../components/PageHeader';
import { PageWallpaper } from '../components/PageWallpaper';
import { formatMessageTime } from '../utils/MessageData';
// MsgNoticePage.ets — 消息中心四类通知列表页（回复我的/@我/收到的赞/系统通知）
import { router } from '@kit.ArkUI';
import { logInfo, logWarn, logError, errMsg } from '../utils/Logger';
import { MsgFeedApi, MsgFeedItem, MsgFeedListResult } from '../api/MsgFeedApi';
import { prefetchVideoPlayback } from '../api/BilibiliApi';

/** 类型配置（标题 + 类型号） */
interface NoticeTypeConfig {
  title: string;
  type: number;
}

const NOTICE_CONFIGS: NoticeTypeConfig[] = [
  { title: '回复我的', type: 1 },
  { title: '@我', type: 2 },
  { title: '收到的赞', type: 3 },
  { title: '系统通知', type: 4 }
];

@Entry
@Component({ freezeWhenInactive: true })
struct MsgNoticePage {
  @StorageLink('pageWallpaperEnabled') pageWallpaperEnabled: boolean = false;
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false;
  @StorageLink('statusBarHeight') statusBarHeight: number = 0;
  @StorageLink('wallpaper') wallpaper: string = 'default';
  @StorageLink('customWallpaper') customWallpaper: string = '';
  @StorageLink('wallpaperBlur') wallpaperBlur: number = 0;
  @StorageLink('wallpaperDarkness') wallpaperDarkness: number = 50;
  /** 当前类型 */
  @State currentType: number = 1;
  /** 标题 */
  @State title: string = '消息';
  /** 列表数据 */
  @State items: MsgFeedItem[] = [];
  /** 加载中 */
  @State isLoading: boolean = true;
  /** 加载失败 */
  @State loadError: string = '';
  /** 是否有更多 */
  @State hasMore: boolean = true;
  /** 加载更多中 */
  @State isLoadingMore: boolean = false;
  /** 游标 */
  private cursor: string = '0';
  private cursorTime: number = 0;

  async aboutToAppear(): Promise<void> {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      const type = (params['type'] as number) || 1;
      this.currentType = type;
      const conf = NOTICE_CONFIGS.find((c: NoticeTypeConfig) => c.type === type);
      if (conf) {
        this.title = conf.title;
      }
    }
    await this.loadList();
  }

  /**
   * 拉取列表（首页）
   */
  private async loadList(): Promise<void> {
    this.isLoading = true;
    this.loadError = '';
    this.cursor = '0';
    this.cursorTime = 0;
    try {
      const result: MsgFeedListResult = await MsgFeedApi.fetchList(this.currentType, 0, 0);
      this.items = result.items;
      this.cursor = result.cursor;
      this.cursorTime = result.cursorTime;
      this.hasMore = !result.isEnd;
      logInfo(`[MsgNoticePage] ${this.title} 加载 ${this.items.length} 条`);
    } catch (err) {
      logError(`[MsgNoticePage] 加载失败: ${errMsg(err)}`);
      this.loadError = '加载失败，请检查网络';
    }
    this.isLoading = false;
  }

  /**
   * 触底加载更多
   */
  private async loadMore(): Promise<void> {
    if (this.isLoading || this.isLoadingMore || !this.hasMore) {
      return;
    }
    this.isLoadingMore = true;
    try {
      const previousCursor = this.cursor;
      const previousTime = this.cursorTime;
      const result = await MsgFeedApi.fetchList(this.currentType, previousCursor, previousTime);
      const unique = new Map<number, MsgFeedItem>();
      for (let i = 0; i < this.items.length; i++) { unique.set(this.items[i].id, this.items[i]); }
      for (let i = 0; i < result.items.length; i++) { unique.set(result.items[i].id, result.items[i]); }
      const items: MsgFeedItem[] = [];
      unique.forEach((item: MsgFeedItem) => { items.push(item); });
      this.items = items;
      this.cursor = result.cursor;
      this.cursorTime = result.cursorTime;
      this.hasMore = !result.isEnd && result.items.length > 0 && (this.cursor !== previousCursor || this.cursorTime !== previousTime);
    } catch (err) {
      logWarn(`[MsgNoticePage] 加载更多失败: ${errMsg(err)}`);
    }
    this.isLoadingMore = false;
  }

  /**
   * 格式化时间
   */
  private formatTime(ts: number): string {
    return formatMessageTime(ts, false);
  }

  @Builder
  noticeRow(item: MsgFeedItem) {
    PageSurface({ radius: 12 }) {

    Row() {
      // 头像（无图时首字占位）
      if (this.currentType !== 4) {
        Stack() {
          Circle()
            .width(42).height(42)
            .fill(this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)')
          if (item.avatar) {
            Image(item.avatar)
              .width(42).height(42)
              .borderRadius(21)
          } else {
            Text(item.uname.length > 0 ? item.uname.substring(0, 1) : '?')
              .fontSize(16)
              .fontColor('#FF6699')
          }
        }
        .width(42).height(42)
      }

      Column() {
        Row() {
          Text(this.currentType === 4 ? item.title : (item.uname || '用户'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.formatTime(item.time))
            .fontSize(11)
            .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
            .margin({ left: 8 })
        }
        .width('100%')

        Text(item.content || '（无内容）')
          .fontSize(13)
          .fontColor(this.currentType === 4 ? (this.isDarkMode ? '#D6D6D6' : '#333333') : '#999999')
          .maxLines(this.currentType === 4 ? 1000 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.currentType === 4 ? 0 : 12 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (item.commentRootId > 0 && (item.bvid || item.aid)) {
        router.pushUrl({
          url: 'pages/CommentDetailPage',
          params: {
            aid: item.aid || 0,
            bvid: item.bvid || '',
            rootId: item.commentRootId,
            secondaryId: item.commentSecondaryId || 0
          }
        }).catch((err: Error) => {
          logError('跳转评论详情失败', err.message);
        });
      } else if (item.bvid || item.aid) {
        prefetchVideoPlayback(item.bvid || String(item.aid), 0,
          AppStorage.get<number>('defaultVideoQn') ?? 116);
        router.pushUrl({
          url: 'pages/VideoPlayerPage',
          params: {
            bvid: item.bvid || '',
            aid: item.aid || 0,
            title: item.videoTitle || item.content || '',
            coverUrl: item.videoCover
          }
        }).catch((err: Error) => {
          logError('跳转视频播放失败', err.message);
        });
      }
    })

    }
  }

  @Builder
  wallpaperDarknessLayer() {
    if (this.wallpaperDarkness < 50) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(`rgba(0, 0, 0, ${(50 - this.wallpaperDarkness) / 50})`)
    } else if (this.wallpaperDarkness > 50) {
      Column()
        .width('100%').height('100%')
        .backgroundColor(`rgba(255, 255, 255, ${(this.wallpaperDarkness - 50) / 50})`)
    }
  }



  build() {
    Stack() {
      PageWallpaper()
    Stack() {
      if (this.pageWallpaperEnabled) {
      // Shared non-player wallpaper is rendered beneath the page.
    } else if (this.wallpaper === 'builtin') {
        Stack() {
          Image(this.isDarkMode ? $r('app.media.wallpaper_shen') : $r('app.media.wallpaper_qian'))
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      } else if (this.wallpaper === 'custom' && this.customWallpaper) {
        Stack() {
          Image('file://' + this.customWallpaper)
            .width('100%').height('100%')
            .objectFit(ImageFit.Cover)
            .blur(this.wallpaperBlur)
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      } else {
        Stack() {
          Column()
            .width('100%').height('100%')
            .backgroundColor(this.pageWallpaperEnabled ? Color.Transparent : pageBackgroundColor(this.isDarkMode))
          this.wallpaperDarknessLayer()
        }
        .width('100%').height('100%')
      }

    Stack({ alignContent: Alignment.TopStart }) {
      // ── 顶部标题栏 ──

      // ── 列表 ──
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(32).height(32).color('#FF6699')
          Text('加载中...').fontSize(13).fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999').margin({ top: 8 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError) {
        Column() {
          Text(this.loadError).fontSize(14).fontColor('#FF4444')
          Button('重试')
            .fontSize(14)
            .margin({ top: 12 })
            .onClick(() => {
              this.loadList();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.items.length === 0) {
        Column() {
          Text('暂无通知')
            .fontSize(14)
            .fontColor(this.pageWallpaperEnabled ? (this.isDarkMode ? '#C9CDD3' : '#50545A') : '#999999')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.items, (item: MsgFeedItem) => {
            ListItem() {
              this.noticeRow(item)
            }
          }, (item: MsgFeedItem) => `${item.id}`)
        }

        .width('100%')
        .height('100%')
        .padding({ left: 14, right: 14 })
        .contentStartOffset(this.hideStatusBar ? 44 : this.statusBarHeight + 44)
        .scrollBar(BarState.Off)
        .onReachEnd(() => {
          this.loadMore();
        })
      }

      Column() {
      PageHeader({ withTabs: false }) {
        Row() {
          HeaderBackButton({ onBack: () => router.back() }).margin({ right: 8 })
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#FFFFFF' : '#000000')
          Blank()
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: this.hideStatusBar ? 12 : (this.statusBarHeight + 8), bottom: 12 })
      }
      }.width('100%').position({ x: 0, y: 0 }).zIndex(3)
    }
    .width('100%')
    .height('100%')
    }
    .width('100%')
    .height('100%')
    }.width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
