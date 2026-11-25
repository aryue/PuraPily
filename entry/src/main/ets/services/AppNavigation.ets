import { FloatingVideoTransition } from './FloatingVideoTransition';
import { HomeCardMorph } from './HomeCardMorph';
import { logWarn } from '../utils/Logger';

/** Navigation destination name for every in-app page (without the `pages/` prefix). */
export class AppRoutes {
  static readonly INDEX: string = 'Index';
  static readonly VIDEO_PLAYER: string = 'VideoPlayerPage';
  static readonly LIVE_PLAYER: string = 'LivePlayerPage';
}

export interface AppRouteOptions {
  url: string;
  params?: ESObject;
}

export interface AppPopOptions {
  url?: string;
}

interface PendingRoute {
  url: string;
  params?: ESObject;
  replace: boolean;
}

export interface AppRouteState {
  path: string;
  name: string;
}

export interface SettingsSectionRouteParams {
  section: string;
}

export type AppRouteListener = (path: string) => void;

export const EMPTY_ROUTE_PARAMS: Record<string, Object> = {};

type NavShownCallback = () => void;
type NavBackCallback = () => boolean | void;

/**
 * Per-destination lifecycle bridge.
 *
 * Pages keep their existing onPageShow / onPageHide / onBackPress methods so the
 * same component can be hosted by a NavDestination without duplicating logic.
 */
export class NavPageHost {
  private shownCallback: NavShownCallback | null = null;
  private hiddenCallback: NavShownCallback | null = null;
  private backCallback: NavBackCallback | null = null;
  private shownPending: boolean = false;
  private visible: boolean = false;

  attach(shown: NavShownCallback, hidden: NavShownCallback, back: NavBackCallback | null): void {
    this.shownCallback = shown;
    this.hiddenCallback = hidden;
    this.backCallback = back;
    if (this.shownPending) {
      this.shownPending = false;
      this.notifyShown();
    }
  }

  detach(): void {
    this.shownCallback = null;
    this.hiddenCallback = null;
    this.backCallback = null;
    this.shownPending = false;
    this.visible = false;
  }

  notifyShown(): void {
    if (!this.shownCallback) {
      this.shownPending = true;
      return;
    }
    if (this.visible) return;
    this.visible = true;
    this.shownCallback();
  }

  notifyHidden(): void {
    if (!this.visible) return;
    this.visible = false;
    if (this.hiddenCallback) this.hiddenCallback();
  }

  notifyBack(): boolean {
    if (!this.backCallback) return false;
    return this.backCallback() === true;
  }
}

class AppNavigationService {
  private stack: NavPathStack | null = null;
  private indexVisible: boolean = false;
  private appInBackground: boolean = false;
  private pendingRoutes: PendingRoute[] = [];
  private topListeners: AppRouteListener[] = [];
  private visibleHosts: NavPageHost[] = [];
  private popHoldArmed: boolean = false;
  private popProxy: NavigationTransitionProxy | null = null;
  private instantPushArmed: boolean = false;

  bind(stack: NavPathStack): void {
    this.stack = stack;
    this.indexVisible = false;
    this.appInBackground = false;
    this.visibleHosts = [];
    this.popProxy = null;
    this.popHoldArmed = false;
    this.instantPushArmed = false;
    this.syncDepth();
  }

  markIndexVisible(visible: boolean): void {
    this.indexVisible = visible;
    if (visible) {
      this.flushPending();
      this.emitTopChanged();
    }
  }

  notifyAppBackground(): void {
    this.appInBackground = true;
    const host = this.topHost();
    if (host) host.notifyHidden();
  }

  notifyAppForeground(): void {
    if (!this.appInBackground) return;
    this.appInBackground = false;
    const host = this.topHost();
    if (host) host.notifyShown();
  }

  registerHost(host: NavPageHost): void {
    if (!this.visibleHosts.includes(host)) this.visibleHosts.push(host);
  }

  unregisterHost(host: NavPageHost): void {
    const index = this.visibleHosts.indexOf(host);
    if (index >= 0) this.visibleHosts.splice(index, 1);
    host.detach();
  }

  hostShown(host: NavPageHost): void {
    this.registerHost(host);
    host.notifyShown();
  }

  hostHidden(host: NavPageHost): void {
    host.notifyHidden();
    // Keep the host registered until its destination is destroyed. App background can
    // hide the top destination without a navigation event; foreground must still find it.
  }

  subscribeTopChanged(listener: AppRouteListener): void {
    if (!this.topListeners.includes(listener)) this.topListeners.push(listener);
  }

  unsubscribeTopChanged(listener: AppRouteListener): void {
    const index = this.topListeners.indexOf(listener);
    if (index >= 0) this.topListeners.splice(index, 1);
  }

  emitTopChanged(): void {
    const path = this.currentPath();
    this.syncDepth();
    for (const listener of this.topListeners) listener(path);
  }

  pushUrl(options: AppRouteOptions): Promise<void> {
    if (!this.stack || !this.indexVisible) {
      this.pendingRoutes.push({ url: options.url, params: options.params, replace: false });
      return Promise.resolve();
    }
    const name = this.normalize(options.url);
    if (name === AppRoutes.INDEX) {
      this.stack.clear(true);
      this.emitTopChanged();
      return Promise.resolve();
    }
    if (name === AppRoutes.VIDEO_PLAYER) {
      this.instantPushArmed = HomeCardMorph.peekArmed() || FloatingVideoTransition.active();
    }
    this.stack.pushPathByName(name, options.params ?? EMPTY_ROUTE_PARAMS, true);
    this.emitTopChanged();
    this.schedulePopHoldCleanup();
    setTimeout((): void => { this.instantPushArmed = false; }, 200);
    return Promise.resolve();
  }

  replaceUrl(options: AppRouteOptions): Promise<void> {
    if (!this.stack || !this.indexVisible) {
      this.pendingRoutes.push({ url: options.url, params: options.params, replace: true });
      return Promise.resolve();
    }
    const name = this.normalize(options.url);
    if (name === AppRoutes.INDEX) {
      this.stack.clear(true);
    } else {
      this.stack.replacePathByName(name, options.params ?? EMPTY_ROUTE_PARAMS, true);
    }
    this.emitTopChanged();
    this.schedulePopHoldCleanup();
    return Promise.resolve();
  }

  back(options?: AppPopOptions): Promise<void> {
    if (!this.stack) return Promise.resolve();
    const size = this.stack.size();
    if (size <= 0) return Promise.resolve();
    const target = options?.url ? this.normalize(options.url) : '';
    if (target.length > 0) {
      if (target === AppRoutes.INDEX) {
        this.stack.clear(true);
        this.emitTopChanged();
        this.schedulePopHoldCleanup();
        return Promise.resolve();
      }
      const indexes = this.stack.getIndexByName(target);
      if (indexes.length > 0) {
        this.stack.popToIndex(indexes[indexes.length - 1], true);
        this.emitTopChanged();
        this.schedulePopHoldCleanup();
        return Promise.resolve();
      }
    }
    this.stack.pop(true);
    this.emitTopChanged();
    this.schedulePopHoldCleanup();
    return Promise.resolve();
  }

  getParams(): Record<string, Object> | undefined {
    if (!this.stack) return undefined;
    const size = this.stack.size();
    if (size <= 0) return undefined;
    const param: Object | undefined = this.stack.getParamByIndex(size - 1) as Object | undefined;
    return param as Record<string, Object> | undefined;
  }

  getState(): AppRouteState {
    const name = this.topName();
    return { path: 'pages/', name: name.length > 0 ? name : AppRoutes.INDEX };
  }

  currentPath(): string {
    const name = this.topName();
    return 'pages/' + (name.length > 0 ? name : AppRoutes.INDEX);
  }

  requestPopHold(): void {
    this.popHoldArmed = true;
  }

  finishPopHold(): void {
    this.popHoldArmed = false;
    const proxy = this.popProxy;
    this.popProxy = null;
    if (proxy) proxy.finishTransition();
  }

  /**
   * Navigation custom transition protocol.
   *
   * - Home-card player push is instant: the player itself runs the cover morph.
   * - Player minimize/restore pops/pushes are instant: the floating window owns motion.
   * - Player return with the shared-element shrink keeps the destination alive until the
   *   page has finished collapsing, so the live home/source page stays visible underneath.
   * - Everything else returns undefined, keeping the platform transition.
   */
  navTransition(from: NavContentInfo, to: NavContentInfo, operation: NavigationOperation): NavigationAnimatedTransition | undefined {
    if (operation === NavigationOperation.PUSH) {
      if (to.name === AppRoutes.VIDEO_PLAYER && this.instantPushArmed) {
        this.instantPushArmed = false;
        return {
          timeout: 1,
          transition: (proxy: NavigationTransitionProxy): void => { proxy.finishTransition(); }
        };
      }
      return undefined;
    }
    if (operation !== NavigationOperation.POP || from.name !== AppRoutes.VIDEO_PLAYER) return undefined;
    if (FloatingVideoTransition.active()) {
      return {
        timeout: 1,
        transition: (proxy: NavigationTransitionProxy): void => { proxy.finishTransition(); }
      };
    }
    if (this.popHoldArmed) {
      this.popHoldArmed = false;
      return {
        timeout: 1000,
        transition: (proxy: NavigationTransitionProxy): void => {
          this.popProxy = proxy;
        },
        onTransitionEnd: (_success: boolean): void => {
          this.popProxy = null;
        }
      };
    }
    return undefined;
  }

  private flushPending(): void {
    if (!this.stack || this.pendingRoutes.length === 0) return;
    const pending = this.pendingRoutes;
    this.pendingRoutes = [];
    for (const route of pending) {
      const name = this.normalize(route.url);
      if (name === AppRoutes.INDEX) continue;
      if (route.replace) {
        this.stack.replacePathByName(name, route.params ?? EMPTY_ROUTE_PARAMS, false);
      } else {
        this.stack.pushPathByName(name, route.params ?? EMPTY_ROUTE_PARAMS, false);
      }
    }
    this.emitTopChanged();
  }

  private schedulePopHoldCleanup(): void {
    setTimeout((): void => {
      if (this.popHoldArmed && this.popProxy === null) this.popHoldArmed = false;
    }, 100);
  }

  private topHost(): NavPageHost | null {
    if (this.visibleHosts.length === 0) return null;
    return this.visibleHosts[this.visibleHosts.length - 1];
  }

  private topName(): string {
    if (!this.stack || this.stack.size() <= 0) return '';
    const names = this.stack.getAllPathName();
    return names.length > 0 ? names[names.length - 1] : '';
  }

  private syncDepth(): void {
    AppStorage.setOrCreate('navStackDepth', this.stack ? this.stack.size() : 0);
  }

  private normalize(url: string): string {
    let name = url.trim();
    if (name.startsWith('/')) name = name.substring(1);
    if (name.startsWith('pages/')) name = name.substring(6);
    name = name.replace(/\.(ets|js|ts)$/, '');
    if (name.length === 0) logWarn('[AppNavigation] empty route url');
    return name;
  }
}

export const AppNavigation = new AppNavigationService();
