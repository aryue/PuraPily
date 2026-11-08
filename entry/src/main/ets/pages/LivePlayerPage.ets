import { AdjustmentMotion } from '../controlcenter/model/AdjustmentMotion';
import { PlaybackAudioOutputMonitor } from '../utils/PlaybackAudioOutput';
import { PlayerLevelBar } from '../components/PlayerLevelBar';
import { ImmersiveLightWrapper } from '../components/ImmersiveLightWrapper';
import { PlaybackMenuIcon } from '../components/PlaybackMenuIcon';
import { PlaybackMenuRow } from '../components/PlaybackMenuRow';
import { NativeGlassCapsule } from '../components/NativeGlassCapsule';
import { CommentMenuSurface } from '../components/CommentMenuSurface';
import { playbackMenuOptions } from '../utils/PlaybackMenuStyle';
import { StatusBarUtils } from '../utils/StatusBarUtils';
import { HeaderGlassControl } from '../components/HeaderGlassControl';
import { HeaderBackButton } from '../components/HeaderBackButton';
import { AppContinuation, ContinuationPage } from '../services/AppContinuation';
﻿// LivePlayerPage.ets — 直播播放页（使用 Video 组件）
import { window, display, LengthMetrics } from '@kit.ArkUI';
import { logInfo, logWarn, logError } from '../utils/Logger';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { media } from '@kit.MediaKit';
import { getLiveRoomInfo, getLiveStreamUrl, getLiveQualityLabel, invalidateCachedStreamUrl, getRoomPlayInfo, QualityDescription, LiveStreamUrlResult, LiveRoomInfo } from '../api/LiveApi';
import { LiveFeedRoom, fetchLiveRoomsByArea, formatOnlineCount } from '../api/LiveFeedApi';
import { LiveViewHelper } from '../services/LiveViewHelper';
import { systemShare } from '@kit.ShareKit';
import { getLiveChatHistory, LiveChatMessage } from '../api/LiveApi';
import { LiveChatReceiver } from '../services/LiveChatReceiver';
import { BusinessError } from '@kit.BasicServicesKit';
import { VibrateUtils } from '../utils/VibrateUtils';

interface QualityOption {
  qn: number;
  label: string;
}

@Entry
@Component
struct LivePlayerPage {
  // ========== 直播状态 ==========
  @State roomId: number = 0;
  @State title: string = '';
  @State online: number = 0;
  @State uname: string = '';
  @State roomCover: string = ''; // 直播间封面（实况窗/通知中心媒体封面）
  @State loading: boolean = true;
  @State errorMsg: string = '';
  @State retryCount: number = 0;
  @State currentQn: number = 0;  // 0=未设置，从API获取后选择最高画质
  @State showQualityPicker: boolean = false;

  // ========== Video 组件状态 ==========
  @State videoSrc: string = '';
  @State videoSrcVersion: number = 0;  // 强制重建 Video 用
  private av: media.AVPlayer | null = null; // AVPlayer 播放器（支持后台续播）
  private xc: XComponentController = new XComponentController(); // 视频渲染表面
  private surfaceId_: string = '';
  private spareXc: XComponentController = new XComponentController();
  @State activeSlot: number = 0;
  @State activeFrameReady: boolean = false;
  private previewAV: media.AVPlayer | null = null;
  @State previewRoomId: number = 0;
  @State previewReady: boolean = false;
  @State previewWidth: number = 16;
  @State previewHeight: number = 9;
  private previewInfo: LiveRoomInfo | null = null;
  private previewStream: LiveStreamUrlResult | null = null;
  private previewQualities: QualityOption[] = [];
  private previewGeneration: number = 0;
  private previewRelease: Promise<void> = Promise.resolve();
  private previewTask: Promise<void> = Promise.resolve();
  private userPaused: boolean = false;
  private pageHidden: boolean = false;
  private touchActive: boolean = false;
  @State sourceWidth: number = 16;
  @State sourceHeight: number = 9;
  @State viewportWidth: number = 0;
  @State viewportHeight: number = 0;
  @State informationVisible: boolean = true;
  @State informationProgress: number = 0;
  @State liveMenuPanel: string = 'share';
  @State private liveMenuHeight: number = 0;
  @State private liveChoice: string = '';
  @State private liveDropdown: boolean = false;
  private liveShareController: systemShare.ShareController | null = null;
  @State showPlaybackSettings: boolean = false;
  @State portraitScale: string = 'fill';
  @State portraitScaleScope: string = 'standard';
  @State anchorFace: string = '';
  @State roomOffset: number = 0;
  @State roomSlideDirection: number = 1;
  @State roomAnimating: boolean = false;
  private roomIds: number[] = [];
  private rooms: LiveFeedRoom[] = [];
  private areaId: number = 0;
  private roomPage: number = 0;
  private switchingRoom: boolean = false;
  private disposed: boolean = false;
  private playGeneration: number = 0;
  private lastDx: number = 0;
  private lastDy: number = 0;

  // ========== 动态画质列表（从API获取，只显示此直播间有的画质） ==========
  @State availableQualities: QualityOption[] = [];

  // ========== VideoControls 绑定状态 ==========
  @State isPlaying: boolean = false;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isControlsVisible: boolean = true;
  @State isFullscreen: boolean = true;
  @State isMuted: boolean = false;
  @State playbackRate: number = 1.0;
  @State showGestureHint: boolean = false;
  @State private gestureHintActive: boolean = false;
  @State private outputUsesHeadphones: boolean = false;
  @State private outputHeadphoneIcon: string = 'headphones_fill';
  private audioOutputMonitor: PlaybackAudioOutputMonitor = new PlaybackAudioOutputMonitor((headphones: boolean, icon: string) => {
    this.outputUsesHeadphones = headphones;
    this.outputHeadphoneIcon = icon;
  }, () => this.getUIContext().getHostContext() as common.UIAbilityContext);
  @State gestureHintMainText: string = '';
  @State gestureHintProgress: number = 0;
  @State gestureHintType: string = '';
  @State showBottomHint: boolean = false;
  @State bottomHintImage: ResourceStr | undefined = undefined;
  @State bottomHintText: string = '';
  @State liveChatMessages: LiveChatMessage[] = [];
  @State liveChatStatus: string = '正在加载弹幕…';
  private liveChatTimer: number = -1;
  private liveChatGeneration: number = 0;
  private liveChatConnected: boolean = false;
  private liveChatReceiver: LiveChatReceiver = new LiveChatReceiver((message: LiveChatMessage) => {
    if (this.disposed || this.pageHidden) return;
    this.liveChatMessages = this.liveChatMessages.concat([message]).slice(-6);
  }, (status: string) => {
    if (this.disposed || this.pageHidden) return;
    this.liveChatConnected = status === '';
    this.liveChatStatus = status;
  });
  @State isBackgroundPlayback: boolean = false;
  // 亮度/音量起始值
  @State sv: number = 1; // start volume (0-1)
  @State sb: number = 1; // start brightness (0-1)
  @State vol: number = 1;
  @State bri: number = 1;
  // 安全区域
  @State safeTop: number = 28;
  @State safeBottom: number = 24;

  private maxRetries: number = 8;
  private controlsTimer: number = -1;
  private retryTimer: number = -1;
  private screenW: number = 720;
  private screenH_: number = 0;  // 屏幕高度(vp)，用于手势灵敏度
  /** ⭐ 设备媒体音量最大档位（readSystemVolume 时刷新） */
  private maxVol_: number = 15
  /** ⭐ AudioVolumeManager 实例（供 streamVolumeChange 监听/注销） */
  private volMgr_: audio.AudioVolumeManager | null = null
  /** ⭐ 是否已注册系统音量变化监听 */
  private volListening_: boolean = false
  private mw: window.Window | undefined = undefined;  // 主窗口，用于控制系统栏

  // 记录播放开始时间，用于过滤启动时的非致命错误（如 live-stream loop 801）
  private playbackStartMs: number = 0;

  // ========== 屏幕旋转 ==========
  @State rotationMode: string = 'system';  // 'system' | 'auto' | 'portrait' | 'landscape'
  private rotationFreeMode: string = 'system';

  // ========== 卡片样式 ==========
  @StorageLink('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('customThemeColor') customThemeColor: string = '#007DFF';
  @StorageLink('cardTransparentStyle') cardTransparentStyle: boolean = false;
  @StorageLink('cardBorderFollowTheme') cardBorderFollowTheme: boolean = false;
  @StorageLink('cardBorderOpacity') cardBorderOpacity: number = 40;
  @StorageLink('cardBgOpacity') cardBgOpacity: number = 30;
  @StorageLink('cardBorderWidth') cardBorderWidth: number = 1.5;
  @StorageLink('cardCustomColor') cardCustomColor: string = '';
  @StorageLink('cardStyleLiveQuality') cardStyleLiveQuality: boolean = true;
  @StorageLink('bgp') bgp: boolean = false; // 后台播放开关（与普通播放器共用持久化 key）

  /** 当前窗口是否为横屏（基于窗口尺寸，非物理屏幕） */
  private isWindowLandscape(): boolean {
    if (this.mw) {
      try {
        const wp = this.mw.getWindowProperties();
        return wp.windowRect.width > wp.windowRect.height;
      } catch (_e) {}
    }
    try {
      const d = display.getDefaultDisplaySync();
      return d.width > d.height;
    } catch (_e) {
      return false;
    }
  }

  // ========== 手势状态（onVT 风格） ==========
  private sx_: number = 0; private sy_: number = 0;
  private gm_: string = '';         // 手势模式: '' | 'volume' | 'brightness'
  private ml_: boolean = false;     // 是否已移动（区分点击）
  private la_: boolean = false;     // 长按激活（直播无长按，保留占位）
  private dt_: number = -1;        // 双击定时器
  private dtp_: boolean = false;    // 是否双击
  private lt_: number = -1;        // 长按定时器
  private gt_: number = -1;        // 手势提示隐藏定时器
  private lastHapticPct_: number = -1;

  // ==================== 画面比例 + 重置直播 ====================

  private screenWv(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.width / d.densityPixels;
    } catch (_e) { return 720; }
  }

  private screenHv(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.height / d.densityPixels;
    } catch (_e) { return 405; }
  }

  private portraitRoom(): boolean {
    return this.sourceHeight > this.sourceWidth;
  }

  private portraitWindow(): boolean {
    return (this.viewportHeight || this.screenHv()) > (this.viewportWidth || this.screenWv());
  }

  private videoW(): number {
    const sw = this.viewportWidth || this.screenWv();
    const sh = this.viewportHeight || this.screenHv();
    const r = this.sourceWidth / this.sourceHeight;
    const fill = this.portraitRoom() && this.portraitWindow() && this.portraitScale === 'fill'
      && (this.portraitScaleScope === 'all' || Math.abs(r / (9 / 16) - 1) <= 0.001);
    return fill ? Math.max(sw, sh * r) : Math.min(sw, sh * r);
  }

  private videoH(): number {
    const r = this.sourceWidth / this.sourceHeight;
    return this.videoW() / r;
  }

  private videoTop(): number {
    const sh = this.viewportHeight || this.screenHv();
    // 横向直播在竖屏中上部播放，为下方信息留出空间；清屏时位置不变。
    return this.portraitWindow() && !this.portraitRoom()
      ? Math.max(this.safeTop + 86, sh * 0.237) : (sh - this.videoH()) / 2;
  }

  private settleInformation(visible: boolean): void {
    this.informationVisible = visible;
    this.getUIContext().animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
      this.informationProgress = visible ? 0 : 1;
    });
  }

  private openLiveMenu(): void {
    this.liveMenuPanel = 'share';
    this.showPlaybackSettings = true;
  }

  private async shareLiveRoom(): Promise<void> {
    const url = `https://live.bilibili.com/${this.roomId}`;
    try {
      const data = new systemShare.SharedData({ utd: 'general.hyperlink', content: url, title: this.title });
      this.liveShareController = new systemShare.ShareController(data);
      await this.liveShareController.show(this.getUIContext().getHostContext() as common.UIAbilityContext, {});
    } catch (_e) { this.showBottomHintTemporarily('未能打开系统分享'); }
  }

  private stopLiveChat(): void {
    this.liveChatGeneration++;
    clearTimeout(this.liveChatTimer);
    this.liveChatTimer = -1;
    this.liveChatReceiver.stop();
    this.liveChatConnected = false;
  }

  private startLiveChat(clear: boolean = false): void {
    this.stopLiveChat();
    if (clear) {
      this.liveChatMessages = [];
      this.liveChatStatus = '正在加载弹幕…';
    }
    if (this.disposed || this.pageHidden || this.roomId <= 0) return;
    this.liveChatReceiver.start(this.roomId);
    void this.refreshLiveChat(this.roomId, this.liveChatGeneration);
  }

  private async refreshLiveChat(roomId: number, generation: number): Promise<void> {
    let delay = 3000;
    try {
      const messages = await getLiveChatHistory(roomId);
      if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.roomId !== roomId) return;
      if (this.liveChatConnected) return;
      const merged = new Map<string, LiveChatMessage>();
      this.liveChatMessages.forEach(message => merged.set(message.id, message));
      messages.forEach(message => merged.set(message.id, message));
      this.liveChatMessages = Array.from(merged.values())
        .sort((a, b) => a.timeline.localeCompare(b.timeline)).slice(-6);
      if (!this.liveChatConnected && this.liveChatMessages.length) this.liveChatStatus = '';
    } catch (_) {
      if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.roomId !== roomId) return;
      if (!this.liveChatConnected) this.liveChatStatus = '弹幕暂不可用，正在重试…';
      delay = 10000;
    }
    if (generation !== this.liveChatGeneration || this.disposed || this.pageHidden || this.liveChatConnected) return;
    this.liveChatTimer = setTimeout(() => { void this.refreshLiveChat(roomId, generation); }, delay);
  }

  private unavailableLiveAction(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  private async setPortraitScale(mode: string): Promise<void> {
    this.portraitScale = mode;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const pref = await preferences.getPreferences(ctx, 'my_app_settings');
      await pref.put('livePortraitScale', mode);
      await pref.flush();
    } catch (_e) { logWarn('[LivePlayer] 直播比例保存失败'); }
  }

  private async setPortraitScaleScope(scope: string): Promise<void> {
    this.portraitScaleScope = scope;
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(ctx, 'my_app_settings');
      await pref.put('livePortraitScaleScope', scope);
      await pref.flush();
    } catch (_e) { logWarn('[LivePlayer] 直播比例生效范围保存失败'); }
  }

  private async switchRoom(direction: number): Promise<void> {
    if (this.switchingRoom || this.disposed) return;
    this.switchingRoom = true;
    try {
      let index = this.roomIds.indexOf(this.roomId);
      if (direction < 0 && index <= 0) {
        this.showBottomHintTemporarily('已经是第一个直播间');
        return;
      }
      if (index + direction >= this.roomIds.length) {
        const rooms = await fetchLiveRoomsByArea(this.areaId, this.roomPage + 1, 30);
        if (this.disposed) return;
        if (rooms.length > 0) this.roomPage++;
        rooms.forEach(room => {
          if (room.roomId > 0 && !this.roomIds.includes(room.roomId)) {
            this.roomIds.push(room.roomId);
            this.rooms.push(room);
          }
        });
        index = this.roomIds.indexOf(this.roomId);
      }
      const next = this.roomIds[index + direction];
      if (!next) { this.showBottomHintTemporarily('暂无更多直播间，请稍后重试'); return; }
      this.roomSlideDirection = direction;
      this.prepareAdjacentRoom(direction, true);
      await this.animateRoomOffset(-direction * (this.viewportHeight || this.screenHv()));
      if (this.disposed) return;
      this.playGeneration++;
      clearTimeout(this.retryTimer);
      const incoming = this.previewRoomId === next ? this.previewAV : null;
      const stream = incoming ? this.previewStream : null;
      const info = incoming ? this.previewInfo : null;
      const qualities = incoming ? this.previewQualities : [];
      const ready = incoming !== null && this.previewReady;
      const width = this.previewWidth;
      const height = this.previewHeight;
      const outgoing = this.av;
      // 先关闭旧声音，再启用新声音；固定 Surface 只交换角色，不重建。
      try { outgoing?.setVolume(0); } catch (_) {}
      this.av = incoming;
      if (incoming) this.audioOutputMonitor.bind(incoming, audio.StreamUsage.STREAM_USAGE_MOVIE);
      this.previewAV = null;
      this.clearPreview();
      this.activeSlot = 1 - this.activeSlot;
      this.activeFrameReady = ready;
      this.userPaused = false;
      this.videoSrc = '';
      this.roomId = next;
      this.startLiveChat(true);
      this.title = '';
      this.uname = '';
      this.anchorFace = '';
      this.roomCover = '';
      this.online = 0;
      this.sourceWidth = 16;
      this.sourceHeight = 9;
      this.availableQualities = [];
      this.currentQn = 0;
      this.retryCount = 0;
      this.errorMsg = '';
      this.loading = true;
      this.roomOffset = 0;
      if (incoming && stream) {
        this.videoSrc = stream.url;
        this.sourceWidth = width;
        this.sourceHeight = height;
        this.availableQualities = qualities;
        this.applyStreamQuality(stream);
        const card = this.rooms.find(room => room.roomId === next);
        this.title = info?.title || card?.title || '';
        this.uname = info?.uname || card?.uname || '';
        this.anchorFace = card?.face || info?.face || '';
        this.roomCover = info?.keyframe || info?.face || '';
        this.online = info?.online || 0;
        if (incoming.state === 'playing' || incoming.state === 'paused' || incoming.state === 'prepared') {
          incoming.setVolume(this.isMuted ? 0 : 1);
          if (incoming.state === 'playing') this.onVideoStart();
          else if (!this.pageHidden || this.bgp) void incoming.play();
        }
        this.loading = !ready;
        this.setupLiveView_();
      }
      // 等旧解码器释放完再预热，始终最多两个播放器。
      await this.disposePlayer(outgoing);
      if (!incoming) await this.initPlayback();
    } finally {
      this.switchingRoom = false;
      if (!this.disposed && this.roomOffset !== 0) void this.animateRoomOffset(0);
      if (!this.disposed && !this.pageHidden && this.av) this.prepareAdjacentRoom(1);
    }
  }

  private clearPreview(): void {
    this.previewGeneration++;
    const player = this.previewAV;
    this.previewAV = null;
    this.previewRoomId = 0;
    this.previewReady = false;
    this.previewInfo = null;
    this.previewStream = null;
    this.previewQualities = [];
    this.previewRelease = this.previewRelease.then(() => this.disposePlayer(player));
  }

  private async disposePlayer(player: media.AVPlayer | null): Promise<void> {
    if (!player) return;
    try {
      player.off('stateChange');
      player.off('error');
      player.off('videoSizeChange');
      player.off('startRenderFrame');
      if (player.state !== 'released') await player.release();
    } catch (_) {}
  }

  private prepareAdjacentRoom(direction: number, committing: boolean = false): void {
    const next = this.roomIds[this.roomIds.indexOf(this.roomId) + direction];
    if (!next || this.disposed || this.pageHidden || this.switchingRoom && !committing) return;
    if (next === this.previewRoomId) return;
    this.clearPreview();
    this.previewRoomId = next;
    const generation = this.previewGeneration;
    this.previewTask = this.previewTask.then(() => this.preparePreview(next, generation));
  }

  private async preparePreview(roomId: number, generation: number): Promise<void> {
    let player: media.AVPlayer | null = null;
    try {
      await this.previewRelease;
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) return;
      const info = await getLiveRoomInfo(roomId);
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) return;
      if (info?.liveStatus !== 1) return;
      const quality = await getRoomPlayInfo(roomId);
      const stream = await getLiveStreamUrl(roomId, quality?.qualities[0]?.qn || 250);
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden || !stream?.url) return;
      player = await media.createAVPlayer();
      if (generation !== this.previewGeneration || this.disposed || this.pageHidden) {
        await this.disposePlayer(player);
        return;
      }
      this.previewAV = player;
      this.previewInfo = info;
      this.previewStream = stream;
      this.previewQualities = quality?.qualities.map(option => ({ qn: option.qn, label: option.desc }) as QualityOption) || [];
      this.previewWidth = stream.videoWidth || 16;
      this.previewHeight = stream.videoHeight || 9;
      this.bindPlayer(player, 1 - this.activeSlot);
      await player.setMediaSource(this.liveMediaSource(stream.url));
    } catch (_) {
      if (player && this.av === player) this.handlePlayError();
      else if (generation === this.previewGeneration) this.clearPreview();
    }
  }

  private animateRoomOffset(offset: number): Promise<void> {
    this.roomAnimating = true;
    return new Promise<void>(resolve => {
      this.getUIContext().animateTo({ duration: 340, curve: Curve.EaseOut, onFinish: () => {
        this.roomAnimating = false;
        resolve();
      } }, () => { this.roomOffset = offset; });
    });
  }

  /** ⭐ 重置直播：释放播放器并强制重新拉流 */
  private resetLive(): void {
    this.showBottomHintTemporarily('已重置直播');
    this.releasePlayer();
    this.showControlsTemporarily();
    this.startPlay(true);
  }

  /** ⭐ 播放/暂停切换 */
  private togglePlayPause(): void {
    if (!this.av || this.switchingRoom || this.roomAnimating) return;
    try {
      if (this.av) {
        if (this.av.state === 'playing') {
          this.userPaused = true;
          this.av.pause();
        } else if (this.av.state === 'paused' || this.av.state === 'prepared') {
          this.userPaused = false;
          this.av.play();
        }
      }
    } catch (_e) {}
  }

  private registerContinuation(): void {
    AppContinuation.register(this, 'pages/LivePlayerPage', (): ContinuationPage | null => {
      if (this.roomId <= 0) return null;
      const params: Record<string, string | number | boolean> = { 'roomId': this.roomId, 'areaId': this.areaId };
      const destination: ContinuationPage = { page: 'pages/LivePlayerPage', params: params };
      return destination;
    });
  }

  aboutToAppear() {
    this.registerContinuation();
    // ⭐ 注册系统音量变化监听（音量键调节时同步 app 内滑块/手势起点）
    this.registerVolumeListener();
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>;
    if (params && params['roomId']) {
      this.roomId = params['roomId'] as number;
      this.roomIds = (params['roomIds'] as number[] || []).filter(id => id > 0);
      this.rooms = params['rooms'] as LiveFeedRoom[] || [];
      if (!this.roomIds.includes(this.roomId)) this.roomIds.unshift(this.roomId);
      this.areaId = params['areaId'] as number || 0;
      this.roomPage = params['roomPage'] as number || 0;
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      preferences.getPreferences(ctx, 'my_app_settings').then(pref => {
        if (!this.disposed) {
          this.portraitScale = pref.getSync('livePortraitScale', 'fill') === 'auto' ? 'auto' : 'fill';
          this.portraitScaleScope = pref.getSync('livePortraitScaleScope', 'standard') === 'all' ? 'all' : 'standard';
        }
      });
      this.initSwipeControl();
      this.getSafeArea();
      this.initPlayback();
      this.startLiveChat(true);
    } else {
      this.errorMsg = '缺少房间号';
      this.loading = false;
    }
  }

  /**
   * 初始化播放：先获取画质信息选最高画质，再开始播放
   */
  private async initPlayback(): Promise<void> {
    await this.fetchQualityInfo();
    if (!this.disposed) await this.startPlay();
  }

  private getSafeArea(): void {
    try {
      window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((w: window.Window) => {
        this.mw = w;
        // ⭐ 窗口就绪后按当前播放状态补设屏幕常亮：
        //    startPlay 是异步的（先取画质再拉流），可能早于这里拿到窗口，
        //    而 onVideoStart 里那次调用会因 mw 还是 undefined 而被静默丢弃。
        this.updateKeepScreen();
        // 初始化时尊重全局旋转设置。
        const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
        this.rotationFreeMode = lock === '自动旋转' ? 'auto' : 'system';
        this.rotationMode = lock === '锁定竖屏' ? 'portrait' : lock === '锁定横屏' ? 'landscape' : this.rotationFreeMode;
        this.applyRotationMode();
        const top = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        if (top.topRect.height > 0) {
          this.safeTop = this.getUIContext().px2vp(top.topRect.height);
        }
        const bottom = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
        if (bottom.bottomRect.height > 0) {
          this.safeBottom = this.getUIContext().px2vp(bottom.bottomRect.height);
        }
        // 进入直播间立即隐藏导航小白条
        try {
          StatusBarUtils.setSystemBars(w, false, false);
        } catch (_e2) {}
      });
    } catch (_e) {
      // 使用默认值
    }
  }

  /**
   * 从API获取直播间可用画质列表，替换默认列表（只显示此直播间有的画质）
   */
  private async fetchQualityInfo(): Promise<void> {
    const roomId = this.roomId;
    try {
      const info = await getRoomPlayInfo(roomId);
      if (this.disposed || this.roomId !== roomId) return;
      if (info && info.qualities.length > 0) {
        // B站返回的画质排序：从高到低
        const sorted: QualityOption[] = info.qualities.map((q: QualityDescription) => ({
          qn: q.qn,
          label: q.desc
        }) as QualityOption);
        // 替换为API返回的列表（只显示此直播间有的画质）
        this.availableQualities = sorted;
        // 自动选择最高画质（列表第一项）
        if (sorted[0].qn !== this.currentQn) {
          this.currentQn = sorted[0].qn;
          logInfo(`[LivePlayer] 动态获取画质列表: ${JSON.stringify(sorted)}, 自动选择最高画质: ${sorted[0].label}(${sorted[0].qn})`);
        }
      } else {
        logWarn('[LivePlayer] API返回的画质列表为空，使用用户手动选择');
      }
    } catch (_e) {
      logWarn(`[LivePlayer] 获取画质列表失败，将由startPlay使用默认兜底画质: ${_e}`);
    }
  }

  aboutToDisappear() {
    AppContinuation.unregister(this);
    this.disposed = true;
    this.stopLiveChat();
    this.playGeneration++;
    // ⭐ 注销系统音量变化监听
    this.unregisterVolumeListener();
    this.audioOutputMonitor.dispose();
    // ⭐ 结束后台媒体会话（返回即停；切后台续播由 onPageHide 处理）
    LiveViewHelper.end();
    this.releasePlayer();
    clearTimeout(this.controlsTimer);
    clearTimeout(this.retryTimer);
    clearTimeout(this.gt_);
    clearTimeout(this.dt_);
    clearTimeout(this.lt_);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((w: window.Window) => {
        w.setWindowBrightness(-1);
        // ⭐ 离开直播间：释放屏幕常亮（防止"页面已销毁但常亮没关"导致一直不熄屏）
        w.setWindowKeepScreenOn(false).catch(() => {});
        // 离开时恢复导航小白条（横屏时保持状态栏隐藏）
        const isLandscape: boolean = AppStorage.get<boolean>('isLandscape') ?? false;
        const hideSb: boolean = AppStorage.get<boolean>('hideStatusBar') ?? false;
        StatusBarUtils.setSystemBars(w, !isLandscape && !hideSb, true);
        // 离开直播恢复全局设置，避免临时锁定覆盖系统旋转策略。
        const lock = AppStorage.get<string>('screenOrientationLock') ?? '跟随系统';
        const orientation = lock === '锁定竖屏' ? window.Orientation.PORTRAIT
          : lock === '锁定横屏' ? window.Orientation.AUTO_ROTATION_LANDSCAPE
          : lock === '自动旋转' ? window.Orientation.AUTO_ROTATION : window.Orientation.AUTO_ROTATION_RESTRICTED;
        w.setPreferredOrientation(orientation).catch(() => {});
      });
    } catch (_e) {}
  }

  /** ⭐ 页面隐藏（切后台/跳转）：后台播放开启则保持播放，否则暂停 */
  onPageHide(): void {
    this.pageHidden = true;
    this.stopLiveChat();
    this.finishLevelGesture();
    this.clearPreview();
    this.cancelPendingTap();
    // ⭐ 页面隐藏即释放屏幕常亮（切后台/跳页时屏幕应能正常锁屏）
    //    ⚠️ 必须放在下面的 return 之前，否则"播放器还没建好"时提前返回会漏掉释放
    this.mw?.setWindowKeepScreenOn(false).catch(() => {});
    if (!this.av) { return; }
    if (this.bgp) {
      logInfo('[LivePlayer] onPageHide → 后台播放模式，保持播放');
      if (!LiveViewHelper.active) { this.setupLiveView_(); }
      return;
    }
    try { this.av.pause(); } catch (_) {}
    LiveViewHelper.updatePlayState(false);
  }

  /** 回前台仅恢复系统暂停，保留用户主动暂停。 */
  onPageShow(): void {
    this.pageHidden = false;
    this.startLiveChat();
    this.registerContinuation();
    try {
      if (!this.userPaused && this.av && this.av.state === 'paused') { this.av.play(); }
    } catch (_) {}
    // ⭐ 回到直播间：恢复屏幕常亮。
    //    这里必须显式补设 —— onPageHide 已经把常亮关掉了，而"后台播放"模式下
    //    播放从未中断，也就不会有 stateChange('playing') 去触发 onVideoStart。
    this.updateKeepScreen();
  }

  // ==================== 播放器逻辑（基于 media.AVPlayer） ====================

  private applyStreamQuality(result: LiveStreamUrlResult): void {
    const supported = result.acceptQuality.filter((qn, index, all) => qn > 0 && all.indexOf(qn) === index);
    if (result.currentQn > 0 && !supported.includes(result.currentQn)) supported.push(result.currentQn);
    this.availableQualities = supported.sort((a, b) => b - a).map(qn => ({
      qn, label: this.availableQualities.find(option => option.qn === qn)?.label || getLiveQualityLabel(qn)
    }) as QualityOption);
    this.currentQn = result.currentQn;
    logInfo(`[LivePlayer] 实际画质=${this.currentQn}, 当前流支持=${supported.join(',')}`);
  }

  private async startPlay(forceRefresh: boolean = false): Promise<void> {
    const generation = ++this.playGeneration;
    try {
      // 读取当前系统音量，确保手势滑块从真实音量开始
      this.readSystemVolume();
      this.isMuted = AppStorage.get<boolean>('globalMuted') ?? false;
      // 如果currentQn未设置（API获取失败等情况），使用超清兜底
      if (this.currentQn <= 0) {
        this.currentQn = 250;
      }

      const info = await getLiveRoomInfo(this.roomId);
      if (this.disposed || generation !== this.playGeneration) return;
      if (info) {
        const card = this.rooms.find(room => room.roomId === this.roomId);
        this.anchorFace = card?.face || info.face;
        this.title = info.title;
        this.online = info.online;
        this.uname = info.uname || card?.uname || '';
        this.roomCover = info.face || info.keyframe || ''; // 封面优先 user_cover，其次 keyframe
        if (info.liveStatus !== 1) {
          this.errorMsg = '主播未开播';
          this.loading = false;
          return;
        }
      }

      const streamResult = await getLiveStreamUrl(this.roomId, this.currentQn, forceRefresh);
      if (this.disposed || generation !== this.playGeneration) return;
      if (!streamResult || !streamResult.url) {
        this.errorMsg = '获取直播流地址失败';
        this.loading = false;
        return;
      }

      this.loading = true;
      this.errorMsg = '';
      this.playbackStartMs = Date.now();
      this.applyStreamQuality(streamResult);
      this.sourceWidth = streamResult.videoWidth || 16;
      this.sourceHeight = streamResult.videoHeight || 9;
      this.videoSrc = streamResult.url;
      this.videoSrcVersion++;
      await this.setupAVPlayer(streamResult.url, generation);
    } catch (e) {
      logError(`[LivePlayer] startPlay异常: ${e}`);
      if (!this.disposed && generation === this.playGeneration) this.handlePlayError();
    }
  }

  private onVideoPrepared(): void {
    this.errorMsg = '';
    this.retryCount = 0;
    // AVPlayer 音量随系统媒体音量
  }

  /**
   * ⭐ 屏幕常亮：播放中保持屏幕不自动休眠（AVPlayer 不会自动阻止系统休眠，必须显式调用）
   *    之前直播间漏了这一步 → 播放中会跟随系统"休眠时间"自动熄屏锁屏。
   *    play=true 时开启；暂停 / 页面隐藏 / 离开页面时释放。
   *    ⚠️ this.mw 是**异步**拿到的（getSafeArea），播放状态可能先于窗口就绪 →
   *       窗口就绪后必须补调一次（见 getSafeArea），否则首次进入直播间不生效。
   */
  private updateKeepScreen(): void {
    this.mw?.setWindowKeepScreenOn(this.isPlaying && !this.pageHidden).catch(() => {});
  }

  private onVideoStart(): void {
    this.retryCount = 0;
    this.isPlaying = true;
    // ⭐ 开播 → 屏幕常亮
    this.updateKeepScreen();
    this.playbackStartMs = Date.now();
    // 初始保持控制栏可见，等用户第一次点击后再进入自动隐藏模式
    if (this.controlsTimer !== -1) {
      clearTimeout(this.controlsTimer);
      this.controlsTimer = -1;
    }
    // ⭐ 同步媒体会话播放状态（通知/实况窗）：否则状态停在初始"播放中"，
    //    用户点暂停实际是让已暂停的播放器再 pause（invalid operation），控制无效
    LiveViewHelper.updatePlayState(true);
    this.prepareAdjacentRoom(1);
  }

  private onVideoPause(): void {
    this.isPlaying = false;
    // ⭐ 暂停 → 释放屏幕常亮（用户主动暂停后允许系统正常熄屏）
    this.updateKeepScreen();
    // ⭐ 同步媒体会话播放状态为暂停
    LiveViewHelper.updatePlayState(false);
  }

  private onVideoError(): void {
    const elapsed: number = Date.now() - this.playbackStartMs;
    // 播放启动后 3s 内的 onError 通常是直播流不支持循环设置(errorCode=801)，
    // 这是非致命警告，播放器实际仍在正常渲染画面。忽略它避免 stop→retry 死循环。
    if (elapsed < 3000) {
      logWarn(`[LivePlayer] 忽略启动后${elapsed}ms内的非致命错误（直播流 loop 设置不支持）`);
      return;
    }
    logError(`[LivePlayer] AVPlayer 错误（播放${elapsed}ms后）`);
    this.releasePlayer();
    this.handlePlayError();
  }

  private handlePlayError(): void {
    if (this.retryCount < this.maxRetries) {
      this.retryCount++;
      this.loading = true;
      this.errorMsg = '';
      const shouldRefresh: boolean = this.retryCount > 2;
      if (shouldRefresh) {
        invalidateCachedStreamUrl(this.roomId);
      }
      // 重试超过 3 次后尝试降画质
      if (this.retryCount >= 3 && this.availableQualities.length > 0) {
        this.downgradeQuality();
      }
      if (this.retryTimer !== -1) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => {
        this.retryTimer = -1;
        this.startPlay(shouldRefresh);
      }, 1000);
    } else {
      this.retryCount = 0;
      this.loading = true;
      this.errorMsg = '';
      invalidateCachedStreamUrl(this.roomId);
      // 最大重试后降画质，防止死循环
      this.downgradeQuality();
      if (this.retryTimer !== -1) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => {
        this.retryTimer = -1;
        this.startPlay(true);
      }, 2000);
    }
  }

  /** 降画质：从当前画质降到下一个更低画质 */
  private downgradeQuality(): void {
    if (this.availableQualities.length === 0) {
      return;
    }
    const currentIdx: number = this.availableQualities.findIndex((q: QualityOption) => q.qn === this.currentQn);
    if (currentIdx < this.availableQualities.length - 1) {
      const nextQn: number = this.availableQualities[currentIdx + 1].qn;
      logInfo(`[LivePlayer] 降画质: ${getLiveQualityLabel(this.currentQn)}(${this.currentQn}) → ${getLiveQualityLabel(nextQn)}(${nextQn})`);
      this.currentQn = nextQn;
      invalidateCachedStreamUrl(this.roomId);
    } else {
      logInfo(`[LivePlayer] 已是最低画质，不再降级`);
    }
  }

  /** 释放播放器资源 */
  private releasePlayer(): void {
    this.clearPreview();
    this.releaseAVPlayer();
    this.videoSrc = '';
  }

  private async releaseAVPlayer(): Promise<void> {
    const av = this.av;
    this.av = null;
    this.activeFrameReady = false;
    if (!av) { return; }
    try {
      av.off('stateChange');
      av.off('error');
      av.off('videoSizeChange');
      av.off('startRenderFrame');
      if (av.state !== 'released') { await av.release(); }
    } catch (_e) {}
  }

  /** ⭐ 创建 AVPlayer（HLS 主流；极端 FLV 可能不支持，交由错误重试链处理） */
  private async setupAVPlayer(url: string, generation: number): Promise<void> {
    if (this.av) { await this.releaseAVPlayer(); }
    if (url.toLowerCase().includes('.flv')) {
      logWarn('[LivePlayer] 该直播流为 FLV，AVPlayer 可能不支持，仅尝试播放');
    }
    const av: media.AVPlayer = await media.createAVPlayer();
    if (this.disposed || generation !== this.playGeneration) { await av.release(); return; }
    this.av = av;
    this.audioOutputMonitor.bind(av, audio.StreamUsage.STREAM_USAGE_MOVIE);
    this.bindPlayer(av, this.activeSlot);
    await av.setMediaSource(this.liveMediaSource(url));
  }

  private liveMediaSource(url: string): media.MediaSource {
    return media.createMediaSourceWithUrl(url, {
      'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.bilibili.com/'
    });
  }

  private ownsPlayer(player: media.AVPlayer): boolean {
    return !this.disposed && (this.av === player || this.previewAV === player);
  }

  private bindPlayer(player: media.AVPlayer, slot: number): void {
    player.on('startRenderFrame', () => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player) {
        this.activeFrameReady = true;
        this.loading = false;
      }
      else this.previewReady = true;
    });
    player.on('videoSizeChange', (width: number, height: number) => {
      if (!this.ownsPlayer(player) || width <= 0 || height <= 0) return;
      if (this.av === player) { this.sourceWidth = width; this.sourceHeight = height; }
      else { this.previewWidth = width; this.previewHeight = height; }
    });
    player.on('error', (err: BusinessError) => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player) {
        logError(`[LivePlayer] AVPlayer error: ${err.message}`);
        this.onVideoError();
      } else this.clearPreview();
    });
    player.on('stateChange', async (state: string) => {
      if (!this.ownsPlayer(player)) return;
      if (this.av === player && (state === 'prepared' || state === 'playing')) {
        this.audioOutputMonitor.bind(player, audio.StreamUsage.STREAM_USAGE_MOVIE);
      }
      try {
        if (state === 'initialized') {
          const surface = await this.ensureSurfaceId_(slot);
          if (!this.ownsPlayer(player)) return;
          if (!surface) throw new Error('直播 Surface 尚未就绪');
          player.surfaceId = surface;
          await player.prepare();
        } else if (state === 'prepared') {
          // SHARE_MODE 允许同应用两个直播并播，待切房仅音量为零。
          player.audioInterruptMode = audio.InterruptMode.SHARE_MODE;
          player.setVolume(this.av === player && !this.isMuted ? 1 : 0);
          if (this.av === player) this.onVideoPrepared();
          if (this.av === player && (this.userPaused || this.pageHidden && !this.bgp)) return;
          await player.play();
          if (this.av === player && this.ownsPlayer(player)) this.setupLiveView_();
        } else if (state === 'playing') {
          if (this.av === player) this.onVideoStart();
        } else if ((state === 'paused' || state === 'stopped' || state === 'completed' || state === 'error') && this.av === player) this.onVideoPause();
      } catch (error) {
        if (!this.ownsPlayer(player)) return;
        logWarn(`[LivePlayer] state=${state}: ${error}`);
        if (this.av === player) this.handlePlayError();
        else this.clearPreview();
      }
    });
  }

  private async ensureSurfaceId_(slot: number = this.activeSlot): Promise<string> {
    const controller = slot === 0 ? this.xc : this.spareXc;
    for (let i = 0; i < 10; i++) {
      const sid = controller.getXComponentSurfaceId();
      if (sid) return sid;
      await new Promise<void>(resolve => setTimeout(resolve, 30));
    }
    return '';
  }

  /** ⭐ 建立媒体会话 + 后台长时任务（通知栏/锁屏控制卡） */
  private setupLiveView_(): void {
    LiveViewHelper.setControlHandlers({
      play: () => {
        this.userPaused = false;
        try {
          const av = this.av;
          if (av && av.state !== 'playing') { av.play(); }
        } catch (_) {}
      },
      pause: () => {
        this.userPaused = true;
        try {
          const av = this.av;
          if (av && av.state !== 'paused') { av.pause(); }
        } catch (_) {}
      },
      seek: (_t: number) => { /* 直播无进度，忽略 */ }
    });
    try {
      const ctx = this.getUIContext().getHostContext() as common.Context;
      void LiveViewHelper.create(ctx, this.title, this.roomCover, String(this.roomId), 0, this.uname);
    } catch (_) {}
  }

  /** 切换画质 */
  private switchQuality(qn: number): void {
    if (!this.availableQualities.some(option => option.qn === qn)) return;
    this.currentQn = qn;
    this.loading = true;
    this.errorMsg = '';
    this.showQualityPicker = false;
    this.retryCount = 0;
    this.releasePlayer();
    invalidateCachedStreamUrl(this.roomId);
    this.startPlay(true);
  }

  private goBack(): void {
    this.disposed = true;
    this.playGeneration++;
    this.releasePlayer();
    this.getUIContext().getRouter().back();
  }

  /** 后台播放开关：持久化设置并同步媒体会话。 */
  private toggleBackgroundPlayback(): void {
    this.bgp = !this.bgp;
    AppStorage.set<boolean>('bgp', this.bgp);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      preferences.getPreferences(ctx, 'my_app_settings').then((pref) => {
        pref.put('bgp', this.bgp);
        pref.flush();
      });
    } catch (e) {
      logError('[LivePlayer] bgp 持久化保存失败', e);
    }
    // ⭐ 接入媒体会话：开启→建会话（在播时）；关闭→结束会话并暂停（若在后台）
    if (this.bgp) {
      if (this.av && (this.av.state === 'playing' || this.av.state === 'prepared')) {
        this.setupLiveView_();
      }
    } else {
      LiveViewHelper.end();
      const appBg: boolean = AppStorage.get<boolean>('appInBackground') ?? false;
      if (appBg && this.av && this.av.state === 'playing') {
        try { this.av.pause(); } catch (_) {}
      }
    }
  }

  private showControlsTemporarily(): void {
    this.isControlsVisible = true;
    if (this.controlsTimer !== -1) clearTimeout(this.controlsTimer);
    this.controlsTimer = setTimeout(() => {
      if (!this.showQualityPicker) {
        this.isControlsVisible = false;
      }
    }, 4000);
  }

  private showBottomHintTemporarily(txt: string, img?: ResourceStr): void {
    this.bottomHintText = txt;
    this.bottomHintImage = img;
    this.showBottomHint = true;
    setTimeout(() => { this.showBottomHint = false; }, 2000);
  }

  private setSystemVolume(vol: number): void {
    // 设置系统媒体音量：档位范围动态获取，不硬编码 15（设备档位不同会导致实际音量偏小）
    try {
      const v: number = Math.round(vol * this.maxVol_);
      audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, v);
    } catch (_e) {}
  }

  private async readSystemVolume(): Promise<void> {
    try {
      const mgr = audio.getAudioManager().getVolumeManager();
      const maxVol: number = mgr.getMaxVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.maxVol_ = maxVol > 0 ? maxVol : 15;
      const sysVol: number = mgr.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC);
      this.vol = maxVol > 0 ? Math.min(1, Math.max(0, sysVol / maxVol)) : 0.7;
      this.sv = this.vol;
      AppStorage.setOrCreate('globalVolume', this.vol);
    } catch (_e) {
      this.vol = AppStorage.get<number>('globalVolume') ?? 0.7;
    }
  }

  /** ⭐ 注册系统音量变化监听（音量键调节时同步 app 内滑块/手势起点） */
  private registerVolumeListener(): void {
    try {
      const mgr = audio.getAudioManager().getVolumeManager();
      this.volMgr_ = mgr;
      if (this.volListening_) return;
      // 注：本机 SDK 中 streamVolumeChange 的签名与官方文档示例不一致，改用编译确认存在的 volumeChange
      mgr.on('volumeChange', (ev: audio.VolumeEvent) => {
        // 不依赖事件字段（避免版本差异），直接重读系统音量同步 UI
        try {
          if (this.maxVol_ > 0 && this.gm_ !== 'volume') {
            // ⭐ 音量滑动手势进行中不重读/重置基准 sv：否则每次 move 都用总位移 dy 从已调整的基准叠加，
            //    越滑越快（轻滑即满/0）。手势由 onTM 的 sv+dy 全权控制；手势外（音量键/结束）才同步
            const sysVol: number = this.volMgr_?.getVolumeByStream(audio.StreamUsage.STREAM_USAGE_MUSIC) ?? 0;
            this.vol = Math.min(1, Math.max(0, sysVol / this.maxVol_));
            this.sv = this.vol;
            AppStorage.setOrCreate('globalVolume', this.vol);
          }
        } catch (_e2) {}
      });
      this.volListening_ = true;
    } catch (_e) {}
  }

  /** ⭐ 注销系统音量变化监听 */
  private unregisterVolumeListener(): void {
    try {
      if (this.volMgr_ && this.volListening_) {
        this.volMgr_.off('volumeChange');
        this.volListening_ = false;
      }
    } catch (_e) {}
  }

  private initSwipeControl(): void {
    try {
      const d = display.getDefaultDisplaySync();
      this.screenW = this.getUIContext().px2vp(d.width);
      this.screenH_ = this.getUIContext().px2vp(d.height);
    } catch (_e) {
      this.screenW = 360;
      this.screenH_ = 720;
    }
  }

  // ==================== 手势系统（onVT 风格） ====================

  // ── 卡片样式辅助 ──
  private opacityToHexAlpha(opacity: number): string {
    const clamped = Math.max(0, Math.min(100, opacity));
    const hex = Math.round(clamped / 100 * 255).toString(16).toUpperCase();
    return hex.length < 2 ? '0' + hex : hex;
  }

  @State private gestureHintMotion: AdjustmentMotion = { sequence: 0, delta: 0, velocity: 0 };
  private levelInputTotal: number = 0;
  private levelInputAt: number = 0;

  private sampleLevelInput(total: number): void {
    const now: number = Date.now();
    const delta: number = this.gestureHintActive ? total - this.levelInputTotal : total;
    const elapsed: number = this.gestureHintActive ? Math.max(16, now - this.levelInputAt) : 16;
    this.levelInputTotal = total;
    this.levelInputAt = now;
    this.gestureHintMotion = { sequence: this.gestureHintMotion.sequence + 1,
      delta: delta, velocity: delta * 1000 / elapsed };
  }

  private sGH(txt: string, progress: number = -1, type: string = ''): void {
    this.gestureHintMainText = txt;
    this.showGestureHint = true;
    this.gestureHintProgress = progress;
    this.gestureHintType = type;
    this.gestureHintActive = true;
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = -1;
  }

  private finishLevelGesture(): void {
    this.gestureHintActive = false;
    if (!this.showGestureHint) return;
    if (this.gt_ !== -1) clearTimeout(this.gt_);
    this.gt_ = setTimeout(() => {
      this.showGestureHint = false;
      this.gt_ = -1;
    }, 900);
  }

  private triggerHaptic(): void {
    VibrateUtils.vibratePreset('haptic.notification.trigger');
  }

  private fireHaptic(duration: number): void {
    VibrateUtils.vibrateTime(duration);
  }

  private onVT = (e: TouchEvent) => {
    switch (e.type) {
      case TouchType.Down:
        this.onTD(e);
        break;
      case TouchType.Move:
        this.onTM(e);
        break;
      case TouchType.Up:
        this.onTU(e);
        break;
      case TouchType.Cancel:
        this.onTC();
        break;
    }
  }

  private onTD(e: TouchEvent): void {
    if (e.touches.length === 0 || this.showPlaybackSettings || this.showQualityPicker || this.switchingRoom || this.roomAnimating) return;
    this.touchActive = true;
    this.lastDx = 0;
    this.lastDy = 0;
    this.gm_ = '';
    logInfo(`[LivePlayer] onTD: type=${e.type} pos=(${e.touches[0].windowX.toFixed(0)},${e.touches[0].windowY.toFixed(0)})`);
    const t = e.touches[0];
    this.sx_ = t.windowX;
    this.sy_ = t.windowY;
    this.sv = this.vol;
    this.sb = this.bri;
    this.ml_ = false;
    this.la_ = false;
    this.dtp_ = false;

    if (this.dt_ !== -1) {
      this.cancelPendingTap();
      this.dtp_ = true;
    }

    // 长按定时器
    this.lt_ = setTimeout(() => {
      if (!this.ml_) {
        this.la_ = true;
      }
    }, 500);
  }

  private onTM(e: TouchEvent): void {
    if (e.touches.length === 0 || this.showPlaybackSettings || this.showQualityPicker || this.switchingRoom || this.roomAnimating) return;
    const t = e.touches[0];
    const dx = t.windowX - this.sx_;
    const dy = this.sy_ - t.windowY;
    this.lastDx = dx;
    this.lastDy = dy;
    const adx = Math.abs(dx);
    const ady = Math.abs(dy);
    if (adx > 10 || ady > 10) {
      this.ml_ = true;
      this.cancelPendingTap();
      this.dtp_ = false;
      if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    }
    if (this.la_) return;
    if (this.gm_ === '') {
      if (adx > 25 || ady > 25) {
        if (adx > ady * 1.2) {
          this.gm_ = 'horizontal';
        } else if (ady > adx * 1.2 && this.portraitWindow()) {
          this.gm_ = 'room';
        } else if (ady > adx * 1.2) {
          // 垂直滑动：左30% = 亮度，右70% = 音量
          const centerX = this.screenW / 2;
          if (t.windowX < centerX) {
            this.gm_ = 'brightness';
          } else {
            this.gm_ = 'volume';
          }
        }
      }
    }
    if (this.gm_ === 'room') {
      this.roomSlideDirection = dy >= 0 ? 1 : -1;
      this.prepareAdjacentRoom(this.roomSlideDirection);
      const height = this.viewportHeight || this.screenHv();
      const atStart = this.roomIds.indexOf(this.roomId) <= 0 && dy < 0;
      this.roomOffset = Math.max(-height, Math.min(height, -dy / (atStart ? 4 : 1)));
    } else if (this.gm_ === 'volume') {
      const volSensitivity: number = 400;
      let v = this.sv + dy / volSensitivity;
      v = Math.min(1, Math.max(0, v));
      this.vol = v;
      AppStorage.setOrCreate('globalVolume', v);
      this.setSystemVolume(v);
      this.sampleLevelInput(dy / volSensitivity);
      this.sGH(`${Math.round(v * 100)}%`, v, 'volume');
      const volPct = Math.round(v * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(volPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = volPct;
      }
    } else if (this.gm_ === 'brightness') {
      const briSensitivity: number = 400;
      let b = this.sb + dy / briSensitivity;
      b = Math.min(1, Math.max(0, b));
      this.bri = b;
      window.getLastWindow(this.getUIContext().getHostContext() as common.UIAbilityContext).then((w: window.Window) => {
        w.setWindowBrightness(b);
      });
      this.sampleLevelInput(dy / briSensitivity);
      this.sGH(`${Math.round(b * 100)}%`, b, 'brightness');
      const briPct = Math.round(b * 100);
      if (this.lastHapticPct_ === -1 || Math.abs(briPct - this.lastHapticPct_) >= 10) {
        this.fireHaptic(12);
        this.lastHapticPct_ = briPct;
      }
    }
  }

  private onTU(e: TouchEvent): void {
    if (!this.touchActive) return;
    this.touchActive = false;
    this.finishLevelGesture();
    const wasLongPress = this.la_;
    const wasMoved = this.ml_;

    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    this.la_ = false;

    if (this.showPlaybackSettings || this.showQualityPicker) { this.onTC(); return; }
    if (this.gm_ === 'room' && Math.abs(this.lastDy) >= 80) {
      void this.switchRoom(this.lastDy > 0 ? 1 : -1);
    } else if (this.gm_ === 'room') {
      void this.animateRoomOffset(0);
    }
    if (!wasMoved && !wasLongPress && !this.switchingRoom && !this.roomAnimating) {
      if (this.dtp_) {
        this.togglePlayPause();
      } else {
        this.dt_ = setTimeout(() => {
          this.dt_ = -1;
          if (!this.disposed && !this.pageHidden && !this.showPlaybackSettings && !this.showQualityPicker) {
            this.settleInformation(!this.informationVisible);
          }
        }, 250);
      }
    }
    this.gm_ = '';
    this.ml_ = false;
  }

  private cancelPendingTap(): void {
    clearTimeout(this.dt_);
    this.dt_ = -1;
  }

  private onTC(): void {
    this.touchActive = false;
    this.finishLevelGesture();
    this.cancelPendingTap();
    this.dtp_ = false;
    if (this.gm_ === 'room' && !this.switchingRoom) void this.animateRoomOffset(0);
    if (this.lt_ !== -1) { clearTimeout(this.lt_); this.lt_ = -1; }
    this.la_ = false;
    this.gm_ = '';
    this.ml_ = false;
  }

  // ==================== 屏幕旋转控制 ====================

  /** 应用当前旋转模式到窗口 */
  private async applyRotationMode(): Promise<void> {
    if (!this.mw) return;
    try {
      let orientation: window.Orientation;
      if (this.rotationMode === 'system') {
        orientation = window.Orientation.AUTO_ROTATION_RESTRICTED;
      } else if (this.rotationMode === 'auto') {
        orientation = window.Orientation.AUTO_ROTATION;
      } else if (this.rotationMode === 'portrait') {
        orientation = window.Orientation.PORTRAIT;
      } else {
        orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
      }
      await this.mw.setPreferredOrientation(orientation);
    } catch (_e) {
      logError(`[LivePlayer] 旋转模式应用失败: ${_e}`);
    }
  }

  @Builder
  private LiveAction(icon: Resource, action: () => void) {
    Image(icon).width(24).height(24).fillColor('#FFFFFF')
      .padding(9).width(42).height(42).borderRadius(21)
      .backgroundColor('#503A3B43').onClick(action)
      .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
  }

  @Builder
  private AnchorIdentity(details: boolean) {
    Row({ space: 8 }) {
      if (this.anchorFace) { Image(this.anchorFace).width(36).height(36).borderRadius(18) }
      Column({ space: 3 }) {
        Text(this.uname || '直播间').fontSize(14).fontColor('#FFFFFF').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (details) { Text(`${formatOnlineCount(this.online)} 人气`).fontSize(10).fontColor('#CCCCCC') }
      }.alignItems(HorizontalAlign.Start).constraintSize({ maxWidth: this.portraitWindow() ? 150 : 260 })
    }.padding({ left: 5, right: 14, top: 5, bottom: 5 })
    .backgroundColor('#66282A33').borderRadius(24)
  }

  private visibleLiveChatMessages(): LiveChatMessage[] {
    const height = (this.viewportHeight || this.screenHv()) * 0.32;
    const count = Math.max(1, Math.min(6, Math.floor((height - (this.liveChatStatus ? 32 : 0)) / 48)));
    return this.liveChatMessages.slice(-count);
  }

  @Builder
  private LiveChatInformation() {
    Column({ space: 5 }) {
      ForEach(this.visibleLiveChatMessages(), (message: LiveChatMessage) => {
        Text() {
          Span(`${message.nickname}：`).fontColor(message.nameColor)
          Span(message.text).fontColor('#FFFFFF')
        }.fontSize(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor('#6630323A').borderRadius(15)
        .constraintSize({ maxWidth: '100%' })
      }, (message: LiveChatMessage) => message.id)
      if (this.liveChatStatus) {
        Text(this.liveChatStatus).fontSize(12).fontColor('#D2D3D8')
          .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor('#6630323A').borderRadius(15)
      }
    }.alignItems(HorizontalAlign.Start)
    .width(this.portraitWindow() ? '86%' : '55%')
    .constraintSize({ maxHeight: Math.max(40, (this.viewportHeight || this.screenHv()) * 0.32) })
    .clip(true).align(Alignment.BottomStart)
    .margin({ left: 16, bottom: 12 }).alignSelf(ItemAlign.Start)
    .id('live-chat-information').hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private RoomInformation() {
    Stack() {
      Column() {
        Row({ space: 10 }) {
          HeaderBackButton({ iconColor: '#FFFFFF', onBack: () => this.goBack() })
          this.AnchorIdentity(true)
          Blank()
          Column() {
            HeaderGlassControl({ label: '更多', controlId: 'live-header-more', onActivate: () => this.openLiveMenu() }) {
              Image($r('app.media.ref_more')).width(24).height(24).fillColor('#FFFFFF').hitTestBehavior(HitTestMode.None)
            }
          }.width(40).height(40)
        }.width('100%').padding({ left: 16, right: 12, top: this.safeTop + 8 })
        .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
        Blank()
        this.LiveChatInformation()
        Column({ space: 10 }) {
          Text(this.title).fontSize(16).fontColor('#FFFFFF').fontWeight(FontWeight.Medium).maxLines(2).width('100%')
          Text(`房间号 ${this.roomId}`).fontSize(12).fontColor('#BFC0C9').width('100%')
          Row({ space: 14 }) {
            Image(this.isPlaying ? $r('app.media.ic_public_pause') : $r('app.media.ic_public_play'))
              .width(24).height(24).fillColor('#FFFFFF').padding(9).width(42).height(42)
              .borderRadius(21).backgroundColor('#503A3B43').id('live-play-pause')
              .accessibilityText(this.isPlaying ? '暂停' : '播放')
              .onClick(() => this.togglePlayPause())
              .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
            this.LiveAction($r('app.media.reset_70'), () => this.resetLive())
            Text(this.availableQualities.find(q => q.qn === this.currentQn)?.label || getLiveQualityLabel(this.currentQn))
              .fontSize(13).fontColor('#FFFFFF').onClick(() => { this.showQualityPicker = true; })
              .id('live-quality-anchor')
              .bindMenu(this.showQualityPicker, this.LiveOptions('quality'),
                playbackMenuOptions(this.isDarkMode, () => { this.showQualityPicker = false; }))
            Blank()
          }.width('100%')
          .onTouch((event: TouchEvent) => { this.cancelPendingTap(); event.stopPropagation(); })
        }.padding({ left: 20, right: 20, bottom: this.safeBottom + 12, top: 24 }).backgroundColor('#40202430')
      }.width('100%').height('100%')
      .id('live-information-layer')
      .opacity(1 - this.informationProgress)
      .hitTestBehavior(this.informationVisible ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
    }.width('100%').height('100%')
  }

  private menuTextColor(): string { return this.isDarkMode ? '#EEEFF1' : '#18191C'; }

  private liveRowWidth(): number { return Math.max(0, (this.viewportWidth || this.screenWv()) - 28); }

  private liveOptionLabels(kind: string): string[] {
    if (kind === 'quality') return this.availableQualities.map((item: QualityOption) => item.label);
    if (kind === 'scale') return ['完整显示', '裁切铺满'];
    return ['仅 9:16 竖屏直播', '所有竖屏直播'];
  }

  private liveSelectedLabel(kind: string): string {
    if (kind === 'quality') return this.availableQualities.find((item: QualityOption) => item.qn === this.currentQn)?.label || getLiveQualityLabel(this.currentQn);
    if (kind === 'scale') return this.portraitScale === 'fill' ? '裁切铺满' : '完整显示';
    return this.portraitScaleScope === 'all' ? '所有竖屏直播' : '仅 9:16 竖屏直播';
  }

  private chooseLiveOption(kind: string, index: number): void {
    this.liveDropdown = false;
    this.showQualityPicker = false;
    if (kind === 'quality') {
      const quality = this.availableQualities[index];
      if (quality && quality.qn !== this.currentQn) this.switchQuality(quality.qn);
    } else if (kind === 'scale') { void this.setPortraitScale(index === 0 ? 'auto' : 'fill'); }
    else { void this.setPortraitScaleScope(index === 0 ? 'standard' : 'all'); }
  }

  private liveDropdownOptions(): MenuOptions {
    return playbackMenuOptions(this.isDarkMode, () => { this.liveDropdown = false; });
  }

  @Builder
  private LiveOptions(kind: string) {
    Menu() {
      ForEach(this.liveOptionLabels(kind), (label: string, index: number) => {
        MenuItem({ content: label, endIcon: this.liveSelectedLabel(kind) === label ?
          (this.isDarkMode ? $r('app.media.settings_menu_check_dark') : $r('app.media.settings_menu_check_light')) : undefined })
          .contentFontColor(this.menuTextColor()).height(52).id(`live-menu-option-${kind}-${index}`)
          .onClick(() => this.chooseLiveOption(kind, index))
      }, (label: string) => label)
    }.width(224).radius(24).font({ size: 16 })
      .menuItemDivider({ strokeWidth: LengthMetrics.vp(0.5), color: this.isDarkMode ? '#24FFFFFF' : '#18000000',
        startMargin: LengthMetrics.vp(16), endMargin: LengthMetrics.vp(16) })
  }

  @Builder
  private LiveChoiceRow(icon: Resource, title: string, kind: string) {
    PlaybackMenuRow({ rowWidth: this.liveRowWidth(), rowId: `live-menu-${kind}`, icon: icon, title: title,
      detail: this.liveSelectedLabel(kind),
      onActivate: () => { this.liveChoice = kind; this.liveDropdown = true; }
    }).bindMenu(this.liveDropdown && this.liveChoice === kind, this.LiveOptions(kind), this.liveDropdownOptions())
  }

  @Builder
  private ShareChannel() {
    Column({ space: 10 }) {
      NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true,
        capsuleWidth: 42, capsuleHeight: 42, onActivate: () => { void this.shareLiveRoom(); } }) {
        Image($r('app.media.ref_share')).width(24).height(24).fillColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
      }
      Text('系统分享').fontSize(11).fontColor(this.menuTextColor()).maxLines(1)
    }.layoutWeight(1).id('live-system-share')
  }

  @Builder
  private MenuShortcut(icon: Resource, label: string, action: () => void) {
    Column({ space: 10 }) {
      NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: 42, capsuleHeight: 42, onActivate: action }) {
        PlaybackMenuIcon({ icon: icon, iconSize: 26 })
      }
      Text(label).fontSize(11).fontColor(this.menuTextColor()).maxLines(1)
    }.layoutWeight(1).id('live-menu-shortcut-' + label)
  }

  @Builder
  private PlaybackSettingsContent() {
    Column({ space: 0 }) {
      if (this.liveMenuPanel === 'share') {
        Row() {
          this.ShareChannel()
          this.MenuShortcut($r('app.media.ref_ps_settings'), '播放设置', () => { this.liveMenuPanel = 'playback'; })
          this.MenuShortcut($r('app.media.live_menu_consumption'), '消费管理', () => this.unavailableLiveAction('当前客户端暂不支持直播消费管理'))
          this.MenuShortcut($r('app.media.live_menu_effects'), '隐藏特效', () => this.unavailableLiveAction('当前播放器未展示礼物特效'))
          this.MenuShortcut($r('app.media.ref_ps_cast'), '投屏', () => this.unavailableLiveAction('当前客户端暂不支持直播投屏'))
          this.MenuShortcut($r('app.media.ref_ps_report'), '举报', () => this.unavailableLiveAction('请在哔哩哔哩官方直播间内提交举报'))
        }.width('100%').padding({ left: 8, right: 8, top: 20, bottom: 14 })
      } else {
        Row({ space: 12 }) {
          Row() {
          NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true,
            capsuleWidth: 40, capsuleHeight: 40, onActivate: () => { this.liveMenuPanel = 'share'; } }) {
            Image($r('app.media.ref_back')).width(22).height(22).fillColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
          }
          }.id('live-menu-back')
          Text('播放设置').fontSize(16).fontColor(this.menuTextColor()).fontWeight(FontWeight.Medium).layoutWeight(1)
          NativeGlassCapsule({ withinMaterialScope: true, allowAncestorGestures: true, nativePressFeedback: true, capsuleWidth: 64, capsuleHeight: 36, onActivate: () => { this.showPlaybackSettings = false; } }) {
            Text('完成').fontSize(14).fontColor(this.menuTextColor()).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%').padding({ left: 14, right: 14, top: 14, bottom: 16 })
        if (this.portraitRoom()) {
          Column({ space: 8 }) {
            this.LiveChoiceRow($r('app.media.ref_ps_settings'), '竖屏直播画面', 'scale')
            this.LiveChoiceRow($r('app.media.ref_ps_settings'), '生效范围', 'scope')
          }.width('100%').margin({ bottom: 16 })
        }
        Column() {
          PlaybackMenuRow({ rowWidth: this.liveRowWidth(), rowId: 'live-menu-background', icon: $r('app.media.ref_ps_headphones'),
            title: '后台播放', isToggle: true, checked: this.bgp,
            onToggle: (enabled: boolean) => { if (enabled !== this.bgp) this.toggleBackgroundPlayback(); } })
        }.width('100%').margin({ bottom: 14 })
      }
    }.width('100%').padding({ bottom: this.safeBottom + 12 })
      .onAreaChange((_old: Area, area: Area) => {
        const height = Number(area.height);
        if (height > 0 && Math.abs(height - this.liveMenuHeight) > 0.5) this.liveMenuHeight = height;
      })
  }

  @Builder
  private PlaybackSettings() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.liveMenuHeight > 0) {
        CommentMenuSurface({ surfaceWidth: this.viewportWidth || this.screenWv(), surfaceHeight: this.liveMenuHeight,
          radius: 24, interactive: false, followTouchLight: true }) {
          this.PlaybackSettingsContent()
        }
      } else {
        this.PlaybackSettingsContent()
      }
    }.width('100%').position({ bottom: 0 }).zIndex(25)
      .transition(TransitionEffect.move(TransitionEdge.BOTTOM).animation({ duration: 240, curve: Curve.EaseOut }))
  }

  // ==================== build ====================

  @Builder
  private LiveRoomViewport() {
    Stack() {
      // 加载中
      if (this.loading) {
        Column() {
          LoadingProgress().width(48).height(48).color('#FFFFFF')
          Text('加载直播...').fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0C0E17')
      }

      // 错误提示（仅当无视频源时显示）
      if (this.errorMsg && !this.videoSrc) {
        Column() {
          Text('⚠️').fontSize(48).fontColor('#FF6600')
          Text(this.errorMsg).fontSize(14).fontColor('#CCCCCC').margin({ top: 16 })
          Text('点击返回').fontSize(14).fontColor('#007DFF').margin({ top: 24 })
            .onClick(() => this.goBack())
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0C0E17')
      }

      this.RoomInformation()
    }.width('100%').height('100%').clip(true)
  }

  private slotWidth(slot: number): number {
    if (slot === this.activeSlot) return this.videoW();
    const sw = this.viewportWidth || this.screenWv();
    const sh = this.viewportHeight || this.screenHv();
    const ratio = this.previewWidth / this.previewHeight;
    const fill = ratio < 1 && this.portraitWindow() && this.portraitScale === 'fill'
      && (this.portraitScaleScope === 'all' || Math.abs(ratio / (9 / 16) - 1) <= 0.001);
    return fill ? Math.max(sw, sh * ratio) : Math.min(sw, sh * ratio);
  }

  private slotHeight(slot: number): number {
    return slot === this.activeSlot ? this.videoH() : this.slotWidth(slot) * this.previewHeight / this.previewWidth;
  }

  private slotTop(slot: number): number {
    if (slot === this.activeSlot) return this.videoTop();
    const sh = this.viewportHeight || this.screenHv();
    return this.portraitWindow() && this.previewWidth >= this.previewHeight
      ? Math.max(this.safeTop + 86, sh * 0.237) : (sh - this.slotHeight(slot)) / 2;
  }

  private slotHasCurrentFrame(slot: number): boolean {
    // Read observed readiness before the plain player reference. On the first build
    // av is null; short-circuiting there leaves the opaque mask unsubscribed forever.
    if (slot === this.activeSlot) return this.activeFrameReady && this.av !== null;
    const adjacentRoom = this.roomIds[this.roomIds.indexOf(this.roomId) + this.roomSlideDirection];
    return this.previewReady && this.previewAV !== null && this.previewRoomId === adjacentRoom;
  }

  @Builder
  private LiveVideoSlot(slot: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      // 两个 Surface 始终位于同一节点；交换角色不更换控制器、不重建组件。
      XComponent({ id: slot === 0 ? 'live_video_xc' : 'live_video_spare',
        type: XComponentType.SURFACE, controller: slot === 0 ? this.xc : this.spareXc })
        .width(this.slotWidth(slot)).height(this.slotHeight(slot))
        .position({ x: ((this.viewportWidth || this.screenWv()) - this.slotWidth(slot)) / 2, y: this.slotTop(slot) })
        .hitTestBehavior(HitTestMode.None)
      // Surface 复用后仍可能持有旧房间末帧；只有对应播放器的首帧能解除实色遮挡。
      if (!this.slotHasCurrentFrame(slot)) {
        Column().width('100%').height('100%').backgroundColor('#0C0E17')
          .hitTestBehavior(HitTestMode.None)
      }
      if (slot === this.activeSlot) {
        this.LiveRoomViewport()
      } else if (!this.slotHasCurrentFrame(slot)) {
        Column({ space: 14 }) {
          LoadingProgress().width(36).height(36).color('#FFFFFF')
          Text('加载直播…').fontSize(14).fontColor('#CCCCCC')
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#0C0E17')
      }
    }.width('100%').height('100%').backgroundColor('#0C0E17').clip(true)
    .translate({ y: slot === this.activeSlot ? this.roomOffset
      : this.roomOffset + this.roomSlideDirection * (this.viewportHeight || this.screenHv()) })
    .hitTestBehavior(slot === this.activeSlot ? HitTestMode.Default : HitTestMode.None)
  }



  build() {
    Stack() {
      this.LiveVideoSlot(0)
      this.LiveVideoSlot(1)

      if (this.showBottomHint) {
        Text(this.bottomHintText).fontSize(14).fontColor('#FFFFFF')
          .padding(12).backgroundColor('#CC24242B').borderRadius(12)
          .position({ bottom: this.safeBottom + 84 }).zIndex(40)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.showPlaybackSettings) {
        Column().width('100%').height('100%').backgroundColor('#44000000')
          .onClick(() => { this.showPlaybackSettings = false; })
        this.PlaybackSettings()
      }

      // 与视频播放共用液面/光点，左右均落在手指反侧。
      if (this.showGestureHint) {
        Column() {
          PlayerLevelBar({ progress: this.gestureHintProgress, kind: this.gestureHintType,
            adjusting: this.gestureHintActive, adjustmentMotion: this.gestureHintMotion, headphones: this.outputUsesHeadphones,
            headphoneIcon: this.outputHeadphoneIcon })
        }
        .position({
          x: this.gestureHintType === 'volume' ? 28 : Math.max(28, this.viewportWidth - 92),
          y: Math.max(0, (this.viewportHeight - 144) / 2)
        })
        .transition(TransitionEffect.OPACITY)
        .hitTestBehavior(HitTestMode.None)
        .zIndex(10)
      }


    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0C0E17')
    .clip(true)
    .onAreaChange((_old, area) => {
      this.viewportWidth = Number(area.width);
      this.viewportHeight = Number(area.height);
    })
    .onTouch(this.onVT)
  }
}
