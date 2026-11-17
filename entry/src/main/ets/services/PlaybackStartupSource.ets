import { media } from '@kit.MediaKit';
import { startupPlaybackStrategy } from './PlayerStartupPolicy';
import { getPgcPlayUrl, getVideoPlayUrl, PlayUrlResult } from '../api/BilibiliApi';
import { PlaybackDeadline } from '../utils/PlaybackDeadline';
import { selectDecodablePlayUrl } from './PlaybackCodecSupport';
import { PlaybackWarmPlayer, WarmPlayback } from './PlaybackWarmPlayer';
import type { PlaybackPlayer } from './PlaybackPlayer';
import { DashPlayerBridge } from './DashPlayerBridge';
import type { PlaybackSpan } from '../utils/PlaybackStartup';
import { errMsg, logWarn } from '../utils/Logger';
import type { IjkWarmTake } from './IjkWarmPool';
import type { FeedPlaybackHandles } from './FeedPlaybackSession';
import type { PlaybackResources } from './PlaybackResources';

export async function releaseUnattachedPlayback(handles: FeedPlaybackHandles | null): Promise<void> {
  if (!handles) return;
  const pending: Promise<void>[] = [handles.video.release().catch(() => {})];
  if (handles.audioPlayer) pending.push(handles.audioPlayer.release().catch(() => {}));
  if (handles.bridge) pending.push(handles.bridge.stopIfRunning().catch(() => {}));
  await Promise.all(pending);
}

/** Keep the startup slot occupied until the cancelled attempt finishes cleanup. */
export class PlaybackStartupSlot {
  private active: PlaybackDeadline | null = null;

  get busy(): boolean { return this.active !== null; }

  begin(): PlaybackDeadline | null {
    if (this.active) return null;
    const deadline = new PlaybackDeadline();
    this.active = deadline;
    return deadline;
  }

  cancel(): void {
    this.active?.cancel();
  }

  finish(deadline: PlaybackDeadline): void {
    if (this.active === deadline) this.active = null;
  }

  /** Wait for cleanup, checking that the requesting transition still owns the page. */
  async waitForIdle(current: () => boolean, intervalMs: number, maxChecks: number = Infinity): Promise<boolean> {
    for (let i = 0; i < maxChecks && this.busy; i++) {
      if (!current()) return false;
      await new Promise<void>((resolve) => setTimeout(resolve, intervalMs));
    }
    return current() && !this.busy;
  }
}

/** A route can start allocation before its detail request resolves the CID. */
export class StartupCidGate {
  private ready: (() => void) | null = null;

  publish(cid: number): void {
    if (cid > 0) this.ready?.();
  }

  async wait(deadline: PlaybackDeadline): Promise<void> {
    let timer: number = -1;
    let notify: () => void = () => {};
    const pending = new Promise<void>((resolve, reject) => {
      notify = resolve;
      this.ready = resolve;
      timer = setTimeout(() => reject(new Error('获取视频CID超时，请重试')), 5000);
    });
    try {
      await deadline.wait(pending, '获取视频CID');
    } finally {
      clearTimeout(timer);
      if (this.ready === notify) this.ready = null;
    }
  }
}

export async function waitForStartupSurface(getSurface: () => string, current: () => boolean): Promise<string> {
  if (!current()) return '';
  let surface = getSurface();
  for (let i = 0; i < 20 && !surface; i++) {
    await new Promise<void>((resolve) => setTimeout(() => resolve(), 50));
    if (!current()) return '';
    surface = getSurface();
  }
  if (!surface) throw new Error('IJK 预热实例改绑失败');
  return surface;
}

export function rebindWarmSurface(player: PlaybackPlayer, surface: string): void {
  try {
    if (player.surfaceId !== surface) player.surfaceId = surface;
  } catch (error) {
    logWarn('[VideoPlayer] IJK 预热实例改绑 surface 失败: ' + errMsg(error));
  }
}

/** A paused decoder needs a frame to wake its render thread after rebinding. */
export function wakeWarmSurface(player: PlaybackPlayer): void {
  try {
    player.seek(0, media.SeekMode.SEEK_CLOSEST);
  } catch (error) {
    logWarn('[VideoPlayer] 预热实例 seek 失败: ' + errMsg(error));
  }
}

/** Owns an allocation while startup waits for the source, bridge, or native player. */
export class StartupPlayerAllocation {
  private task: Promise<PlaybackPlayer | null> | null = null;

  start(task: Promise<PlaybackPlayer | null>): void {
    this.task = task;
  }

  wait(deadline: PlaybackDeadline, create: () => Promise<PlaybackPlayer>): Promise<PlaybackPlayer | null> {
    if (!this.task) this.start(create());
    return deadline.wait(this.task!, '创建播放器');
  }

  transfer(): void {
    this.task = null;
  }

  release(): void {
    const unused = this.task;
    this.task = null;
    unused?.then((player: PlaybackPlayer | null) => player?.release()).catch(() => {});
  }
}

/** Owns DASH probing until the page has installed the bridge with its player. */
export class StartupDashSource {
  private bridge: DashPlayerBridge | null = null;
  private address: Promise<string | null> | null = null;

  start(source: PlayUrlResult, profile: PlaybackSpan | null, headers: Record<string, string>,
    cookie: string, resumeMs: number): void {
    if (!source.dash) return;
    const bridge = new DashPlayerBridge(profile);
    this.bridge = bridge;
    this.address = bridge.buildAndStart(source.dash, headers['Referer'] || '', headers['User-Agent'],
      cookie, resumeMs).catch(() => null);
  }

  wait(deadline: PlaybackDeadline): Promise<string | null> | null {
    return this.address ? deadline.wait(this.address, '准备媒体索引') : null;
  }

  take(): DashPlayerBridge | null {
    const bridge = this.bridge;
    this.bridge = null;
    this.address = null;
    return bridge;
  }

  release(): void {
    this.take()?.stopIfRunning().catch(() => {});
  }
}

/** Transfer only after creation settles within the current startup. */
export async function adoptStartupPlayer(deadline: PlaybackDeadline, current: () => boolean,
  adopt: (player: PlaybackPlayer) => void): Promise<PlaybackPlayer | null> {
  if (!current() || deadline.isCancelled()) return null;
  const allocation = new StartupPlayerAllocation();
  try {
    const player = await allocation.wait(deadline, () => media.createAVPlayer());
    if (!player || !current() || deadline.isCancelled()) return null;
    adopt(player);
    allocation.transfer();
    return player;
  } finally {
    allocation.release();
  }
}

/** Attach separate audio only while the video from the same startup is still owned. */
export async function startDetachedAudio(resources: PlaybackResources, video: PlaybackPlayer, url: string,
  headers: Record<string, string>, deadline: PlaybackDeadline, current: () => boolean,
  observe: () => void): Promise<void> {
  const currentVideo = (): boolean => current() && resources.video === video;
  const audio = await adoptStartupPlayer(deadline, currentVideo, (player: PlaybackPlayer) => {
    resources.audio = player;
  });
  if (!audio || !currentVideo() || resources.audio !== audio) return;
  observe();
  const source = media.createMediaSourceWithUrl(url, headers);
  await deadline.wait(audio.setMediaSource(source), '设置音频源');
}

export interface OfflineStartup {
  videoPath: string;
  audioPath: string;
  current: () => boolean;
  observeVideo: () => void;
  observeAudio: () => void;
}

export async function startOfflinePlayback(resources: PlaybackResources, deadline: PlaybackDeadline,
  request: OfflineStartup): Promise<void> {
  const video = await adoptStartupPlayer(deadline, request.current, (player: PlaybackPlayer) => {
    resources.video = player;
  });
  const currentVideo = (): boolean => request.current() && resources.video === video;
  if (!video || !currentVideo()) return;
  request.observeVideo();
  resources.bindOfflineSource(video, request.videoPath, true);
  if (!request.audioPath) return;
  const audio = await adoptStartupPlayer(deadline, currentVideo, (player: PlaybackPlayer) => {
    resources.audio = player;
  });
  if (!audio || !currentVideo() || resources.audio !== audio) return;
  request.observeAudio();
  resources.bindOfflineSource(audio, request.audioPath, false);
}

interface PreparedStartupVideo {
  player: PlaybackPlayer;
  url: string;
  localDash: boolean;
}

/** Assets remain owned by this attempt until explicitly transferred to the page. */
export class PlaybackStartupResources {
  readonly allocation: StartupPlayerAllocation = new StartupPlayerAllocation();
  readonly dash: StartupDashSource = new StartupDashSource();
  warm: WarmPlayback | null = null;
  ijkWarm: IjkWarmTake | null = null;

  async prepareVideo(url: string, deadline: PlaybackDeadline, current: () => boolean,
    create: () => Promise<PlaybackPlayer>): Promise<PreparedStartupVideo | null> {
    if (!current()) return null;
    const player = this.ijkWarm?.handles.video ?? await this.allocation.wait(deadline, create);
    if (!current()) return null;
    if (!player) throw new Error('no player');
    const dashAddress = this.dash.wait(deadline);
    const address = dashAddress ? await dashAddress : url;
    if (!current()) return null;
    if (!address) throw new Error('DASH 转播站启动失败');
    return { player, url: address, localDash: dashAddress !== null };
  }

  transferVideo(): void {
    if (this.ijkWarm) {
      this.ijkWarm = null;
      this.allocation.release();
    } else {
      this.allocation.transfer();
    }
  }

  transferWarm(): void { this.warm = null; }

  release(): void {
    const warm = this.warm;
    const ijkWarm = this.ijkWarm;
    this.warm = null;
    this.ijkWarm = null;
    warm?.release();
    this.dash.release();
    this.allocation.release();
    if (ijkWarm) releaseUnattachedPlayback(ijkWarm.handles).catch(() => {});
  }
}

export async function bindStartupMediaSource(player: PlaybackPlayer, url: string, headers: Record<string, string>,
  dash: boolean, deadline: PlaybackDeadline, profile: PlaybackSpan | null): Promise<void> {
  const source = media.createMediaSourceWithUrl(url, headers);
  profile?.mark('set-source-call');
  if (dash) {
    const strategy = startupPlaybackStrategy();
    profile?.mark('startup-buffer-ms', Math.round((strategy.preferredBufferDurationForPlaying ?? -1) * 1000));
    await deadline.wait(player.setMediaSource(source, strategy), '设置播放源');
  } else {
    await deadline.wait(player.setMediaSource(source), '设置播放源');
  }
  profile?.mark('set-source-return');
}

export interface PlaybackStartupIdentity {
  bvid: string;
  cid: number;
  preferredQn: number;
  pgc: boolean;
  episodeId: number;
  seasonId: number;
}

export async function fetchPlaybackStartupSource(identity: PlaybackStartupIdentity,
  deadline: PlaybackDeadline): Promise<PlayUrlResult> {
  const request = identity.pgc
    ? getPgcPlayUrl(identity.episodeId, identity.cid, identity.preferredQn, identity.seasonId)
    : getVideoPlayUrl(identity.bvid, identity.cid, identity.preferredQn);
  return selectDecodablePlayUrl(await deadline.wait(request, '获取播放地址'));
}

/** Take a compatible native prewarm. The caller owns any returned player. */
export async function takeStartupWarmPlayer(cid: number, source: PlayUrlResult): Promise<WarmPlayback | null> {
  if (!source.dash) return null;
  const pool = PlaybackWarmPlayer.get();
  const quality = pool.peekQuality(cid);
  if (quality !== 0 && quality !== source.dash.quality) {
    pool.abort();
    return null;
  }
  const warm = await pool.take(cid, 1500);
  if (warm && warm.quality !== source.dash.quality) {
    warm.release();
    return null;
  }
  return warm;
}
