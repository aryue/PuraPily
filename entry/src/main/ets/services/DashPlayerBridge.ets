/**
 * DashPlayerBridge —— DASH 转播站播放链路组装器
 *
 * 把「探测 → MPD 生成 → 起本地转播站 → 输出 playerUrl」封装为可复用类。
 * 供 VideoPlayerPage（DASH 双流场景）替代「双 AVPlayer」链路：
 *    AVPlayer 直连 http://127.0.0.1:PORT/manifest.mpd（单播放器，音画引擎内同步）。
 *
 * 生命周期：
 *   - buildAndStart()  组装并启动（页面初始化/切画质时调用）
 *   - stopIfRunning()  停止服务（页面退出/切换画质时调用）
 *   - 页面最小化转移 PlayerService 时，服务一并移交（服务器不停止，
 *     浮窗继续消费；恢复页面时 takeDashServer 接回）。
 */
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';
import { selectDashVideo } from '../utils/DashQuality';
import type { DashFullInfo, DashVideoItem, DashAudioItem } from '../api/BilibiliApi';
import { probeM4sInitSegment, InitSegmentInfo, SegmentEntry } from './DashProbe';
import { buildSegmentTemplateMpd, DashMpdParams, DashVideoStream, DashAudioStream,
         askSegmentCount, safeSegmentTemplateTicks } from './DashMpdBuilder';
import { DashMediaServer, DashServerConfig, SegmentRange } from './DashMediaServer';
import { DashServerHandle } from './PlayerService';
import { DashCdnRoute } from './DashCdnRoute';

const TAG = '[DashBridge]';

export class DashPlayerBridge implements DashServerHandle {
  private server: DashMediaServer | null = null;
  private active: boolean = false;
  private generation: number = 0;

  private diagnosticRoot: PlaybackSpan | null;

  constructor(diagnosticRoot: PlaybackSpan | null = PlaybackStartup.current()) {
    this.diagnosticRoot = diagnosticRoot;
  }

  isActive(): boolean {
    return this.active;
  }

  getServer(): DashMediaServer | null {
    return this.server;
  }

  /**
   * ⭐ 停服（DashServerHandle 契约；PlayerService.release 与页面释放调用）。
   */
  async stop(): Promise<void> {
    await this.stopIfRunning();
  }

  /**
   * 组装并启动转播站。
   * @param startTimeMs 起播时间（毫秒）。> 0 时额外预取覆盖该时刻的分段 ——
   *        续播 seek / 切画质回到原位置都需要冷拉那段，实测是首帧前最大的一块等待。
   * @returns playerUrl（http://127.0.0.1:PORT/manifest.mpd）；失败返回 null
   */
  async buildAndStart(dash: DashFullInfo, referer: string, ua: string, cookie: string,
                      startTimeMs: number = 0): Promise<string | null> {
    const profile = PlaybackStartup.span('dash-bridge', this.diagnosticRoot);
    // ⭐ 0. 校验时长（MPD duration; 若为 0 说明取流层丢了 timelength）
    if (!dash.timelength || dash.timelength <= 0) {
      console.error(`${TAG} dash.timelength=0，MPD 将生成 0 时长清单无法拉流`);
      return null;
    }
    // The bridge must consume the same rendition reported by the playurl layer.
    const videoItem: DashVideoItem | null = selectDashVideo(dash.videoStreams, dash.quality);
    const audioItem: DashAudioItem | null = pickAudioItem(dash.audioStreams);
    if (!videoItem || !audioItem) {
      console.error(`${TAG} 缺少流: video=${!!videoItem} audio=${!!audioItem}`);
      return null;
    }
    profile?.mark('selected-quality', videoItem.id);
    console.info(`${TAG} 视频流 qn=${videoItem.id} fps=${videoItem.frameRate || '?'} codecid=${videoItem.codecid} ${videoItem.width || '?'}x${videoItem.height || '?'} bps=${videoItem.bandwidth || 0} dur=${dash.timelength}ms`);

    // ⭐ 2. 双轨探测并行（各自独立冷连接，串行时两段 RTT 叠加 ~300ms）；
    //    旧转播站关闭与探测并发（切画质场景免串行等待）
    const stopProfile = PlaybackStartup.span('old-server-stop');
    const stopOld = this.stopIfRunning().finally(() => stopProfile?.end());
    const generation = this.generation;
    const videoProbe = PlaybackStartup.span('probe-video');
    const audioProbe = PlaybackStartup.span('probe-audio');
    const infos = await Promise.all([
      probeWithBackup(videoItem.baseUrl, videoItem.backupUrl, referer, ua).then((info: ProbedStream | null) => { videoProbe?.end(info ? 0 : 1); return info; }),
      probeWithBackup(audioItem.baseUrl, audioItem.backupUrl, referer, ua).then((info: ProbedStream | null) => { audioProbe?.end(info ? 0 : 1); return info; }),
    ]);
    const vInfo: InitSegmentInfo | null = infos[0]?.info || null;
    const aInfo: InitSegmentInfo | null = infos[1]?.info || null;
    await stopOld;
    if (generation !== this.generation) { profile?.end(1); return null; }
    if (!vInfo) {
      console.error(`${TAG} 视频轨探测失败`);
      return null;
    }
    if (!aInfo) {
      console.error(`${TAG} 音频轨探测失败`);
      return null;
    }
    console.info(`${TAG} video timescale=${vInfo.timescale} segs=${vInfo.segments.length} | audio timescale=${aInfo.timescale} segs=${aInfo.segments.length}`);

    // Use every sidx duration in SegmentTimeline. Fixed-duration calculations below
    // are only a fallback for incomplete legacy metadata, not the playback timeline.
    // Historical reason for retaining the fixed-duration fallback:
    //    MPD 用 SegmentTemplate + **固定** duration = 首段时长，而清单时长 mediaPresentationDuration
    //    取接口给的 dash.timelength。播放器据此推算要拉多少段：请求段数 = ceil(清单时长 / 首段时长)。
    //    **当 清单时长 > sidx段数 × 首段时长 时就会多算出一段**（实测 BV1hb411c7RQ：75007ms vs
    //    15×5000ms=75000ms ⇒ 算出 16 段），结尾去请求不存在的 video_seg_16.m4s，转播站回 404
    //    ⇒ 该轨拿不到尾部数据（画面停在最后一帧），AVPlayer 还会抛 5411007 IO Resource Not Found
    //    直接进入 error 态；而另一轨与进度条（timeUpdate）继续走。
    //    修法见 DashMpdBuilder.safeSegmentTemplateTicks()：把 @duration 抬到「刚好不会多算一段」的下限。
    const trackSumMs = (segs: Array<SegmentEntry>, ts: number): number => {
      let acc = 0;
      for (let i = 0; i < segs.length; i++) {
        const d: number = segs[i].duration ?? 0;
        acc += d > 0 ? d : ts * 5;
      }
      return ts > 0 ? Math.round(acc / ts * 1000) : 0;
    };
    const vTrackMs: number = trackSumMs(vInfo.segments, vInfo.timescale);
    const aTrackMs: number = trackSumMs(aInfo.segments, aInfo.timescale);
    const vFirstMs: number = vInfo.segments.length > 0 && vInfo.timescale > 0
      ? Math.round((vInfo.segments[0].duration ?? 0) / vInfo.timescale * 1000) : 0;
    const aFirstMs: number = aInfo.segments.length > 0 && aInfo.timescale > 0
      ? Math.round((aInfo.segments[0].duration ?? 0) / aInfo.timescale * 1000) : 0;
    // 收敛后的 SegmentTemplate @duration（单位 = 该轨 timescale）
    const vDurTicks: number = safeSegmentTemplateTicks(dash.timelength, vInfo.segments.length,
      vInfo.segments.length > 0 ? (vInfo.segments[0].duration ?? 0) : 0, vInfo.timescale);
    const aDurTicks: number = safeSegmentTemplateTicks(dash.timelength, aInfo.segments.length,
      aInfo.segments.length > 0 ? (aInfo.segments[0].duration ?? 0) : 0, aInfo.timescale);
    const vDurMs: number = vInfo.timescale > 0 ? Math.round(vDurTicks / vInfo.timescale * 1000) : 0;
    const aDurMs: number = aInfo.timescale > 0 ? Math.round(aDurTicks / aInfo.timescale * 1000) : 0;
    const vRawAsk: number = vFirstMs > 0 ? Math.ceil(dash.timelength / vFirstMs) : 0;
    const aRawAsk: number = aFirstMs > 0 ? Math.ceil(dash.timelength / aFirstMs) : 0;
    const vAsk: number = askSegmentCount(dash.timelength, vInfo.timescale, vDurTicks);
    const aAsk: number = askSegmentCount(dash.timelength, aInfo.timescale, aDurTicks);
    console.info(`${TAG} 段数核对: MPD时长=${dash.timelength}ms 实际视频轨=${vTrackMs}ms/音频轨=${aTrackMs}ms`);
    console.info(`${TAG} 段数核对: video list=${vInfo.segments.length} 首段=${vFirstMs}ms ⇒ 按首段播放器将请求=${vRawAsk} 段 | audio list=${aInfo.segments.length} 首段=${aFirstMs}ms ⇒ 将请求=${aRawAsk} 段`);
    if (vRawAsk > vInfo.segments.length || aRawAsk > aInfo.segments.length) {
      // ⚠️ 别删：这是「结尾静止/报错」的唯一显性线索（404 分支本身不再致命，见 DashMediaServer）
      console.warn(`${TAG} ⚠️ 按首段时长会越界，已收敛 @duration: video ${vFirstMs}→${vDurMs}ms ⇒ ${vAsk} 段 | audio ${aFirstMs}→${aDurMs}ms ⇒ ${aAsk} 段`);
    } else {
      console.info(`${TAG} 段数核对 OK: video ⇒ ${vAsk} 段(sidx=${vInfo.segments.length}) | audio ⇒ ${aAsk} 段(sidx=${aInfo.segments.length})`);
    }

    // ⭐ 3. 组装 MPD
    const vStream: DashVideoStream = {
      id: videoItem.id,
      baseUrl: infos[0]!.url,
      backupUrl: (videoItem.backupUrl && videoItem.backupUrl.length > 0) ? videoItem.backupUrl[0] : videoItem.baseUrl,
      codecid: videoItem.codecid,
      bandwidth: videoItem.bandwidth || 0,
      width: videoItem.width || 0,
      height: videoItem.height || 0,
      frameRate: videoItem.frameRate || '0',
      sar: videoItem.sar || '1:1',
      startWithSap: videoItem.startWithSap || 0,
      contentLength: videoItem.contentLength || 0
    };
    const aStream: DashAudioStream = {
      id: audioItem.id,
      baseUrl: infos[1]!.url,
      backupUrl: (audioItem.backupUrl && audioItem.backupUrl.length > 0) ? audioItem.backupUrl[0] : audioItem.baseUrl,
      bandwidth: audioItem.bandwidth || 0,
      contentLength: audioItem.contentLength || 0
    };
    const mpdParams: DashMpdParams = {
      durationMs: dash.timelength,
      videoStreams: [vStream],
      audioStreams: [aStream],
      videoInitRange: vInfo.initRange,
      videoIndexRange: vInfo.indexRange,
      audioInitRange: aInfo.initRange,
      audioIndexRange: aInfo.indexRange,
      videoTimescale: vInfo.timescale,
      audioTimescale: aInfo.timescale,
      // Fixed-duration fields are used only if the exact timeline is unavailable.
      videoSegmentDuration: vDurTicks,
      audioSegmentDuration: aDurTicks,
      videoSegmentDurations: vInfo.segments.map((segment: SegmentEntry) => segment.duration),
      audioSegmentDurations: aInfo.segments.map((segment: SegmentEntry) => segment.duration),
      videoStartTime: vInfo.segments.length > 0 ? vInfo.segments[0].startTime : 0,
      audioStartTime: aInfo.segments.length > 0 ? aInfo.segments[0].startTime : 0
    };
    profile?.mark('video-index-ms', vTrackMs, vInfo.segments.length);
    profile?.mark('audio-index-ms', aTrackMs, aInfo.segments.length);
    profile?.mark('media-duration-ms', dash.timelength);
    const mpdProfile = PlaybackStartup.span('mpd-build');
    const mpdXml = buildSegmentTemplateMpd(mpdParams);
    mpdProfile?.end();

    // ⭐ 4. 起转播站
    // ⭐ 把 sidx 的逐段 duration 一起带过去：只有它能让转播站把「第 N 秒」换算成分段下标
    //    （分段时长不均匀，用 总时长/段数 均分会定位到错的那一段）
    const segRanges = (segs: Array<SegmentEntry>): Array<SegmentRange> => {
      const list: Array<SegmentRange> = [];
      for (let i = 0; i < segs.length; i++) {
        const se = segs[i];
        const r: SegmentRange = { fileOffset: se.fileOffset, size: se.size, duration: se.duration };
        list.push(r);
      }
      return list;
    };
    const initEndIdx = vInfo.initRange.indexOf('-');
    const videoInitSize = initEndIdx >= 0 ? parseInt(vInfo.initRange.substring(initEndIdx + 1), 10) + 1 : 0;
    const aInitEndIdx = aInfo.initRange.indexOf('-');
    const audioInitSize = aInitEndIdx >= 0 ? parseInt(aInfo.initRange.substring(aInitEndIdx + 1), 10) + 1 : 0;

    const serverConfig: DashServerConfig = {
      mpdXml: mpdXml,
      videoUrl: infos[0]!.url,
      audioUrl: infos[1]!.url,
      referer: referer,
      userAgent: ua,
      cookie: '',
      videoSegments: segRanges(vInfo.segments),
      audioSegments: segRanges(aInfo.segments),
      videoInitSize: videoInitSize,
      audioInitSize: audioInitSize,
      videoFileSize: vInfo.contentLength,
      audioFileSize: aInfo.contentLength,
      videoRoute: new DashCdnRoute(infos[0]!.url, [videoItem.baseUrl].concat(videoItem.backupUrl || []),
        vInfo.headBuffer, vInfo.contentLength, referer, ua, this.diagnosticRoot,
        vInfo.indexRange ? parseInt(vInfo.indexRange.split('-')[1], 10) + 1 : videoInitSize),
      audioRoute: new DashCdnRoute(infos[1]!.url, [audioItem.baseUrl].concat(audioItem.backupUrl || []),
        aInfo.headBuffer, aInfo.contentLength, referer, ua, this.diagnosticRoot,
        aInfo.indexRange ? parseInt(aInfo.indexRange.split('-')[1], 10) + 1 : audioInitSize),
      // ⭐ 探测已下载的头部（完整覆盖 initRange），init 请求命中时零回源
      videoInitBuffer: vInfo.headBuffer,
      audioInitBuffer: aInfo.headBuffer,
      // ⭐ 按时间预取要用它把「秒」换算成分段下标
      videoTimescale: vInfo.timescale,
      audioTimescale: aInfo.timescale
    };

    // 旧服务已在探测期间停止
    const server = new DashMediaServer(this.diagnosticRoot);
    server.setConfig(serverConfig);
    // Own the preparing server too, so cancellation aborts pending audio downloads.
    this.server = server;
    // ⭐ 首分片预取：sidx 表已就绪，先把首段拉入转播站缓存（与 AVPlayer 创建/prepare 并行）
    const retainVideo = server.canRetainStartupSegments(startTimeMs, true);
    // Cold starts can overlap native preparation with the video tail download.
    // Resume/quality seeks retain complete ranges: prefix-only readiness with
    // native setPlaybackRange regressed sustained progress in device checks.
    // This controls byte availability, not the native playback waterline.
    const videoPrefixBytes = startTimeMs > 0 && retainVideo ? 0 : 256 * 1024;
    const videoReady = server.prefetchSegment(true, 0, videoPrefixBytes);
    const audioReady = server.prefetchSegment(false, 0);
    let resumeVideoReady: Promise<boolean> = Promise.resolve(true);
    let resumeAudioReady: Promise<boolean> = Promise.resolve(true);
    // ⭐ 起播位预取：续播/切画质会 seek 到 startTimeMs，覆盖该时刻的分段是首帧前的最大等待，
    //    在这里先拉掉（与 AVPlayer 创建/prepare 并行），seek 发起时命中缓存。
    //    ⚠️ 起点为 0 时不必调（首分片预取已覆盖）。
    if (startTimeMs > 0) {
      resumeVideoReady = server.prefetchSegmentAtTime(true, startTimeMs, videoPrefixBytes);
      resumeAudioReady = server.prefetchSegmentAtTime(false, startTimeMs);
    }
    const listenProfile = PlaybackStartup.span('server-listen');
    await server.start();
    if (generation !== this.generation) { await server.stop(); profile?.end(1); return null; }
    listenProfile?.end();
    // Avoid giving native DASH a video-ready/audio-starved startup. The same
    // validated transfer is then served from cache; video remains streamed.
    profile?.mark('audio-startup-wait');
    profile?.mark('video-prefix-wait', videoPrefixBytes);
    const ready = await Promise.all([audioReady, resumeAudioReady, videoReady, resumeVideoReady]
      .map((task: Promise<boolean>) => task.then((value: boolean) => {
        if (!value) throw new Error('startup media unavailable');
        return true;
      }))).catch(() => [false]);
    if (generation !== this.generation || ready.some((value: boolean) => !value)) {
      profile?.mark('audio-startup-unavailable');
      await server.stop();
      if (this.server === server) this.server = null;
      profile?.end(1);
      return null;
    }
    profile?.mark('audio-startup-ready');
    profile?.mark('video-prefix-ready', videoPrefixBytes);
    profile?.end();
    this.server = server;
    this.active = true;
    const port = server.getPort();
    console.info(`${TAG} 转播站已启动 127.0.0.1:${port}，MPD=${mpdXml.length}B init=${videoInitSize}/${audioInitSize}`);
    return `http://127.0.0.1:${port}/manifest.mpd`;
  }

  /**
   * 接管已被预热的转播站后，补做「起播位分段预取」。
   * 预热时不知道续播点，只能先拉首段；页面带着进度进来时在这里补齐，
   * 否则 seek 会去冷拉覆盖该时刻的分段。
   */
  async prefetchResume(positionMs: number, videoPrefixBytes: number = 256 * 1024): Promise<void> {
    const server = this.server;
    if (!this.active || server === null || positionMs <= 0) {
      return;
    }
    server.canRetainStartupSegments(positionMs, true);
    await Promise.all([
      server.prefetchSegmentAtTime(true, positionMs, videoPrefixBytes),
      server.prefetchSegmentAtTime(false, positionMs)
    ]);
  }

  /** 停止服务（页面释放/切画质时调用） */
  prefetchForPlayback(positionMs: number, rate: number = 1): void {
    if (this.active) this.server?.refillForPlayback(positionMs, rate);
  }

  async stopIfRunning(): Promise<void> {
    this.generation++;
    const server = this.server;
    this.server = null;
    this.active = false;
    if (server) {
      try {
        await server.stop();
      } catch (e) {
        console.error(`${TAG} stop error: ${e}`);
      }
    }
  }
}

interface ProbedStream {
  info: InitSegmentInfo;
  url: string;
}

async function probeWithBackup(url: string, backups: string[] | undefined, referer: string,
  ua: string): Promise<ProbedStream | null> {
  const primary = await probeM4sInitSegment(url, referer, ua, '');
  if (primary) return { info: primary, url: url };
  const backup = backups?.find((candidate: string) => !!candidate && candidate !== url);
  const info = backup ? await probeM4sInitSegment(backup, referer, ua, '') : null;
  return info && backup ? { info: info, url: backup } : null;
}

/** 挑音频流：按 id 降序（高音质优先） */
function pickAudioItem(list: Array<DashAudioItem>): DashAudioItem | null {
  if (!list || list.length === 0) {
    return null;
  }
  const sorted = list.slice().sort((a: DashAudioItem, b: DashAudioItem) => b.id - a.id);
  return sorted.length > 0 ? sorted[0] : null;
}
