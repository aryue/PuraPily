import { AppNavigation, NavPageHost, SettingsSectionRouteParams } from '../services/AppNavigation';
import { AboutPage } from '../pages/AboutPage';
import { AudioOutputLab } from '../pages/AudioOutputLab';
import { BilibiliLoginPage } from '../pages/BilibiliLoginPage';
import { CommentDetailPage } from '../pages/CommentDetailPage';
import { DashPocPage } from '../pages/DashPocPage';
import { DynamicDetailPage } from '../pages/DynamicDetailPage';
import { FavoritesPage } from '../pages/FavoritesPage';
import { HotRankingPage } from '../pages/HotRankingPage';
import { IjkLab } from '../pages/IjkLab';
import { LevelBarLab } from '../pages/LevelBarLab';
import { LivePlayerPage } from '../pages/LivePlayerPage';
import { LocalWallpaperPage } from '../pages/LocalWallpaperPage';
import { MessagesPage } from '../pages/MessagesPage';
import { MsgNoticePage } from '../pages/MsgNoticePage';
import { OfflineCachePage } from '../pages/OfflineCachePage';
import { QrCodeLoginParams, QrCodeLoginPage } from '../pages/QrCodeLoginPage';
import { RecommendDetectionPage } from '../pages/RecommendDetectionPage';
import { SearchPage } from '../pages/SearchPage';
import { SettingsPage } from '../pages/SettingsPage';
import { SettingsSectionPage } from '../pages/SettingsSectionPage';
import { SponsorBlockPage } from '../pages/SponsorBlockPage';
import { SurfaceRebindLab } from '../pages/SurfaceRebindLab';
import { UpSpacePage } from '../pages/UpSpacePage';
import { VideoPlayerPage } from '../pages/VideoPlayerPage';
import { WatchHistoryPage } from '../pages/WatchHistoryPage';
import { WhisperDetailPage } from '../pages/WhisperDetailPage';

/**
 * Hosts a page component inside the single root Navigation.
 *
 * Every destination keeps one root NavDestination and owns a NavPageHost so pages can
 * continue to use their existing onPageShow / onPageHide / onBackPress methods.
 */
@Component
export struct NavRouteShell {
  routeName: string = '';
  routeParam: Object | null = null;
  private host: NavPageHost = new NavPageHost();

  aboutToDisappear(): void {
    AppNavigation.unregisterHost(this.host);
  }

  @Builder
  RouteContent() {
    if (this.routeName === 'AboutPage') {
      AboutPage()
    } else if (this.routeName === 'AudioOutputLab') {
      AudioOutputLab({ navHost: this.host })
    } else if (this.routeName === 'BilibiliLoginPage') {
      BilibiliLoginPage()
    } else if (this.routeName === 'CommentDetailPage') {
      CommentDetailPage({ navParams: this.routeParam as Record<string, Object> | null })
    } else if (this.routeName === 'DashPocPage') {
      DashPocPage()
    } else if (this.routeName === 'DynamicDetailPage') {
      DynamicDetailPage({
        navHost: this.host,
        navParams: this.routeParam as Record<string, Object> | null
      })
    } else if (this.routeName === 'FavoritesPage') {
      FavoritesPage({ navHost: this.host })
    } else if (this.routeName === 'HotRankingPage') {
      HotRankingPage({ navParams: this.routeParam as Record<string, Object> | null })
    } else if (this.routeName === 'IjkLab') {
      IjkLab()
    } else if (this.routeName === 'LevelBarLab') {
      LevelBarLab({ navHost: this.host })
    } else if (this.routeName === 'LivePlayerPage') {
      LivePlayerPage({
        navHost: this.host,
        navParams: this.routeParam as Record<string, Object> | null
      })
    } else if (this.routeName === 'LocalWallpaperPage') {
      LocalWallpaperPage({ navHost: this.host })
    } else if (this.routeName === 'MessagesPage') {
      MessagesPage()
    } else if (this.routeName === 'MsgNoticePage') {
      MsgNoticePage({ navParams: this.routeParam as Record<string, Object> | null })
    } else if (this.routeName === 'OfflineCachePage') {
      OfflineCachePage()
    } else if (this.routeName === 'QrCodeLoginPage') {
      QrCodeLoginPage({ navParams: this.routeParam as QrCodeLoginParams | null })
    } else if (this.routeName === 'RecommendDetectionPage') {
      RecommendDetectionPage()
    } else if (this.routeName === 'SearchPage') {
      SearchPage({
        navHost: this.host,
        navParams: this.routeParam as Record<string, Object> | null
      })
    } else if (this.routeName === 'SettingsPage') {
      SettingsPage()
    } else if (this.routeName === 'SettingsSectionPage') {
      SettingsSectionPage({ navParams: this.routeParam as SettingsSectionRouteParams | null })
    } else if (this.routeName === 'SponsorBlockPage') {
      SponsorBlockPage()
    } else if (this.routeName === 'SurfaceRebindLab') {
      SurfaceRebindLab({ navParams: this.routeParam as Record<string, string> | null })
    } else if (this.routeName === 'UpSpacePage') {
      UpSpacePage({
        navHost: this.host,
        navParams: this.routeParam as Record<string, Object> | null
      })
    } else if (this.routeName === 'VideoPlayerPage') {
      VideoPlayerPage({
        navHost: this.host,
        navParams: this.routeParam as Record<string, Object> | null
      })
    } else if (this.routeName === 'WatchHistoryPage') {
      WatchHistoryPage({ navHost: this.host })
    } else if (this.routeName === 'WhisperDetailPage') {
      WhisperDetailPage({ navParams: this.routeParam as Record<string, Object> | null })
    }
  }

  build() {
    NavDestination() {
      this.RouteContent()
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Transparent)
    .onShown(() => {
      AppNavigation.hostShown(this.host);
      AppNavigation.emitTopChanged();
    })
    .onHidden(() => {
      AppNavigation.hostHidden(this.host);
      AppNavigation.emitTopChanged();
    })
    .onBackPressed(() => this.host.notifyBack())
  }
}
