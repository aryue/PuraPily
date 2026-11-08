/**
 * DashMediaServer —— 方案① 本地 HTTP 转播站
 *
 * 在 App 内起一个 127.0.0.1 TCP 服务，把 B 站 DASH 双流伪装成真实 HTTP 资源：
 *   GET /manifest.mpd   → 合成 SegmentTemplate MPD（AVPlayer 直连 DASH 已验证可播）
 *   GET /video/init     → 视频轨 ftyp+moov（真实 m4s 0-initSize）
 *   GET /video/seg/:n   → 视频轨第 n 个 moof/mdat（sidx 字节范围）
 *   GET /audio/init     → 音频轨 init
 *   GET /audio/seg/:n   → 音频轨第 n 段
 *
 * AVPlayer 用 createMediaSourceWithUrl("http://127.0.0.1:PORT/manifest.mpd")
 * 直连播放（不挂 MediaSourceLoader — 已实测 loader 模式不走 DASH 解析）。
 *
 * 协议：HTTP/1.1，支持 Range（AVPlayer 会用 byte-range 拉取），
 *       全部二进制回源 B 站真实 m4s URL，Referer 由本服务注入；媒体请求不携带登录 Cookie。
 */
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';
import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DashRangeTransfer } from './DashRangeTransfer';
import type { DashCdnRoute } from './DashCdnRoute';

const TAG = '[DashMediaServer]';

/** 转播站配置（由 PoC 页探测后注入） */
export interface DashServerConfig {
  mpdXml: string;
  videoUrl: string;
  audioUrl: string;
  referer: string;
  userAgent: string;
  cookie: string;
  /** 各子段字节范围（sidx 解析结果） */
  videoSegments: Array<SegmentRange>;
  audioSegments: Array<SegmentRange>;
  videoInitSize: number;
  audioInitSize: number;
  /** ⭐ 文件总大小（探测 contentLength）：越界 Range 返回 416，必须先夹紧 */
  videoFileSize: number;
  audioFileSize: number;
  videoRoute?: DashCdnRoute;
  audioRoute?: DashCdnRoute;
  /** ⭐ 探测已下载的头部字节（覆盖 initRange=0-moovEnd）：init 请求命中时零回源 */
  videoInitBuffer?: ArrayBuffer;
  audioInitBuffer?: ArrayBuffer;
  /**
   * ⭐ 时间轴刻度（sidx 的 timescale）。
   * 只有 `prefetchSegmentAtTime()` 做「时间 → 分段下标」换算时才需要它；
   * 不填的调用方（如 DashPocPage）不受影响，只是用不了按时间预取。
   */
  videoTimescale?: number;
  audioTimescale?: number;
}

export interface SegmentRange {
  fileOffset: number;
  size: number;
  /**
   * ⭐ 该子段的时长（sidx 的 subsegment_duration，单位 = timescale）。
   * 供 `prefetchSegmentAtTime()` 累加定位「第 N 秒落在哪一段」——
   * 分段时长并不均匀，不能用 总时长/段数 平均估算，所以必须把 sidx 的真实值带过来。
   * 老调用方不填也能跑（缺失时按 5 秒兜底估算，只影响预取精度）。
   */
  duration?: number;
}

/** 单个客户端连接 */
class Client {
  conn: socket.TCPSocketConnection;
  buffer: Uint8Array = new Uint8Array(0);
  /** 是否正在处理某个请求（防并发写同一连接） */
  busy: boolean = false;
  reqId: string = '';
  closed: boolean = false;
  readonly disconnected: Promise<null>;
  private resolveDisconnected: (() => void) | null = null;

  constructor(conn: socket.TCPSocketConnection) {
    this.conn = conn;
    this.disconnected = new Promise<null>((resolve) => { this.resolveDisconnected = () => resolve(null); });
  }

  markClosed(): void {
    this.closed = true;
    this.resolveDisconnected?.();
    this.resolveDisconnected = null;
  }

  /** 追加接收字节 */
  append(data: ArrayBuffer): void {
    const incoming = new Uint8Array(data);
    const merged = new Uint8Array(this.buffer.length + incoming.length);
    merged.set(this.buffer, 0);
    merged.set(incoming, this.buffer.length);
    this.buffer = merged;
  }

  /** 消费已处理的字节（丢弃前 count 字节） */
  consume(count: number): void {
    if (count <= 0) {
      return;
    }
    const remain = this.buffer.length - count;
    if (remain <= 0) {
      this.buffer = new Uint8Array(0);
      return;
    }
    const next = new Uint8Array(remain);
    next.set(this.buffer.subarray(count), 0);
    this.buffer = next;
  }
}

export class DashMediaServer {
  private config: DashServerConfig | null = null;
  private server: socket.TCPSocketServer | null = null;
  private clients: Array<Client> = [];
  private port: number = 0;
  /** ⭐ 兜底段大小：sidx 无 size 时拉取上限 */
  private static readonly MAX_SEG: number = 4 * 1024 * 1024;
  /** ⭐ 回源字节缓存：key=url#start-end。预取首分片命中，免 CDN 冷连接（首帧关键路径） */
  private cache: Map<string, ArrayBuffer> = new Map();
  private cacheBytes: number = 0;
  /** ⭐ 在途回源请求：相同区间并发去重（预取与 AVPlayer 请求同时拉同一分片时合并，避免双份下载抢带宽） */
  private inflight: Map<string, DashRangeTransfer> = new Map();
  // 4K/HDR segments can exceed the small contiguous cache. Retain their owned
  // chunks so a native seek/re-read does not download the same 9MB segment again.
  private completed: Map<string, DashRangeTransfer> = new Map();
  private completedBytes: number = 0;
  private static readonly RETAINED_LIMIT: number = 32 * 1024 * 1024;
  /** 缓存总字节上限：超出按插入序淘汰最旧（后续分片无需长期缓存） */
  private static readonly CACHE_LIMIT: number = 8 * 1024 * 1024;

  private diagnosticRoot: PlaybackSpan | null;
  private videoEndsMs: number[] = [];
  private audioEndsMs: number[] = [];
  private deliveredVideo: Set<number> = new Set();
  private deliveredAudio: Set<number> = new Set();
  private prefetchRetryAfter: Map<string, number> = new Map();
  private speculative: Map<string, DashRangeTransfer> = new Map();
  private startupPins: Set<string> = new Set();
  private lastRefillAt: number = -1000;
  private lastRefillPosition: number = -1;

  constructor(diagnosticRoot: PlaybackSpan | null = null) {
    this.diagnosticRoot = diagnosticRoot;
  }

  getPort(): number {
    return this.port;
  }

  setConfig(config: DashServerConfig): void {
    this.config = {
      mpdXml: config.mpdXml,
      videoUrl: config.videoUrl,
      audioUrl: config.audioUrl,
      referer: config.referer,
      userAgent: config.userAgent,
      cookie: '',
      videoSegments: config.videoSegments,
      audioSegments: config.audioSegments,
      videoInitSize: config.videoInitSize,
      audioInitSize: config.audioInitSize,
      videoFileSize: config.videoFileSize,
      audioFileSize: config.audioFileSize,
      videoRoute: config.videoRoute,
      audioRoute: config.audioRoute,
      videoInitBuffer: config.videoInitBuffer,
      audioInitBuffer: config.audioInitBuffer,
      videoTimescale: config.videoTimescale,
      audioTimescale: config.audioTimescale
    };
    this.videoEndsMs = this.segmentEnds(config.videoSegments, config.videoTimescale || 0);
    this.audioEndsMs = this.segmentEnds(config.audioSegments, config.audioTimescale || 0);
    this.deliveredVideo.clear();
    this.deliveredAudio.clear();
    this.lastRefillAt = -1000;
    this.lastRefillPosition = -1;
    this.startupPins.clear();
  }

  private segmentEnds(segments: SegmentRange[], timescale: number): number[] {
    if (timescale <= 0) return [];
    const ends: number[] = [];
    let time = 0;
    for (let i = 0; i < segments.length; i++) {
      const duration = segments[i].duration || 0;
      if (duration <= 0) return [];
      time += duration / timescale * 1000;
      ends.push(time);
    }
    return ends;
  }

  /** 启动服务：监听 127.0.0.1:0（自动分配端口） */
  async start(): Promise<void> {
    const server = socket.constructTCPSocketServerInstance();
    this.server = server;
    server.on('connect', (conn: socket.TCPSocketConnection) => {
      this.handleConnection(conn);
    });

    // 监听地址：本机回环
    // socket.NetAddress 的 address 字段为 string
    const addr: socket.NetAddress = { address: '127.0.0.1', family: 1, port: 0 };
    await server.listen(addr);
    const localAddr = await server.getLocalAddress();
    this.port = localAddr.port ?? 0;
    console.info(`${TAG} 转播站已启动 127.0.0.1:${this.port}`);
  }

  async stop(): Promise<void> {
    this.config?.videoRoute?.cancel();
    this.config?.audioRoute?.cancel();
    this.config = null;
    this.inflight.forEach((transfer: DashRangeTransfer) => transfer.cancel());
    this.inflight.clear();
    this.deliveredVideo.clear();
    this.deliveredAudio.clear();
    this.prefetchRetryAfter.clear();
    this.speculative.clear();
    this.startupPins.clear();
    const clients = this.clients;
    this.clients = [];
    clients.forEach((client: Client) => {
      client.markClosed();
      client.conn.close().catch(() => {});
    });
    if (this.server) {
      try {
        await this.server.close();
      } catch (e) {
        console.error(`${TAG} stop error: ${(e as BusinessError).message}`);
      }
      this.server = null;
    }
    this.clients = [];
    this.port = 0;
    this.cache.clear();
    this.cacheBytes = 0;
    this.completed.clear();
    this.completedBytes = 0;
    this.inflight.clear();
  }

  // ==================== 回源缓存层（首分片预取 + 精确/切片命中） ====================

  private cacheKey(url: string, start: number, end: number): string {
    return `${url}#${start}-${end}`;
  }

  private cachePut(key: string, data: ArrayBuffer): void {
    const previous = this.cache.get(key);
    if (previous) this.cacheBytes -= previous.byteLength;
    this.cache.set(key, data);
    this.cacheBytes += data.byteLength;
    this.trimCache();
    this.trimCompleted();
  }

  private trimCache(): void {
    while (this.cacheBytes > DashMediaServer.CACHE_LIMIT && this.cache.size > 0) {
      const oldestKey = Array.from(this.cache.keys()).find((key: string) => !this.startupPins.has(key));
      if (!oldestKey) break;
      const old = this.cache.get(oldestKey);
      if (old) {
        this.cacheBytes -= old.byteLength;
      }
      this.cache.delete(oldestKey);
    }
  }

  private trimCompleted(): void {
    while (this.completedBytes + this.cacheBytes > DashMediaServer.RETAINED_LIMIT && this.completed.size > 0) {
      const key = Array.from(this.completed.keys()).find((item: string) => !this.startupPins.has(item));
      if (!key) break;
      const old = this.completed.get(key);
      if (old) this.completedBytes -= old.end - old.start + 1;
      this.completed.delete(key);
    }
  }

  private cacheGetExact(url: string, start: number, end: number): ArrayBuffer | null {
    const hit = this.cache.get(this.cacheKey(url, start, end));
    return hit ? hit : null;
  }

  /** 缓存中存在覆盖 [start,end] 的完整段时切片返回（AVPlayer 带 Range 请求也能命中整段预取） */
  private cacheGetSlice(url: string, start: number, end: number): ArrayBuffer | null {
    let bestKey: string | null = null;
    let bestStart = -1;
    let bestLen = Number.MAX_SAFE_INTEGER;
    this.cache.forEach((_data: ArrayBuffer, k: string) => {
      if (!k.startsWith(url + '#')) {
        return;
      }
      const m = /#(\d+)-(\d+)$/.exec(k);
      if (!m) {
        return;
      }
      const cStart = parseInt(m[1], 10);
      const cEnd = parseInt(m[2], 10);
      // 取覆盖 [start,end] 且范围最小者（避免误命中更大的相邻缓存）
      if (cStart <= start && end <= cEnd && (cEnd - cStart) < bestLen) {
        bestKey = k;
        bestStart = cStart;
        bestLen = cEnd - cStart;
      }
    });
    if (bestKey !== null) {
      const data = this.cache.get(bestKey);
      if (data) {
        return data.slice(start - bestStart, end - bestStart + 1);
      }
    }
    return null;
  }

  /** Covering downloads are shared by prefetch, normal requests and partial Range readers. */
  private getTransfer(url: string, start: number, end: number, cfg: DashServerConfig, demand: boolean = false): DashRangeTransfer {
    let covered: DashRangeTransfer | null = null;
    let completedKey: string = '';
    this.completed.forEach((transfer: DashRangeTransfer, key: string) => {
      if (transfer.url === url && transfer.start <= start && transfer.end >= end) { covered = transfer; completedKey = key; }
    });
    if (covered) {
      this.completed.delete(completedKey);
      this.completed.set(completedKey, covered);
      return covered;
    }
    this.inflight.forEach((transfer: DashRangeTransfer) => {
      if (transfer.url === url && transfer.start <= start && transfer.end >= end) covered = transfer;
    });
    if (covered) {
      if (demand) this.speculative.forEach((item: DashRangeTransfer, key: string) => {
        if (item === covered) this.speculative.delete(key);
      });
      return covered;
    }
    const key = this.cacheKey(url, start, end);
    const transfer = new DashRangeTransfer(url, start, end, url === cfg.videoUrl ? 'cdn-video' : 'cdn-audio', this.diagnosticRoot,
      (url === cfg.videoUrl ? cfg.videoRoute : cfg.audioRoute) || null);
    this.inflight.set(key, transfer);
    transfer.completion.then((success: boolean) => {
      if (this.inflight.get(key) !== transfer) return;
      this.inflight.delete(key);
      if (success && this.config === cfg) {
        const data = transfer.collect(DashMediaServer.CACHE_LIMIT);
        if (data) this.cachePut(key, data);
        else if (transfer.end - transfer.start + 1 <= DashMediaServer.RETAINED_LIMIT) {
          this.completed.set(key, transfer);
          this.completedBytes += transfer.end - transfer.start + 1;
          this.trimCompleted();
        }
      }
    });
    transfer.begin(cfg.referer, cfg.userAgent);
    return transfer;
  }

  private async fetchCached(url: string, start: number, end: number, cfg: DashServerConfig): Promise<ArrayBuffer | null> {
    const cached = this.cacheGetExact(url, start, end) || this.cacheGetSlice(url, start, end);
    if (cached) return cached;
    const transfer = this.getTransfer(url, start, end, cfg);
    if (!await transfer.completion) return null;
    const data = transfer.collect(DashMediaServer.MAX_SEG * 16);
    return data ? data.slice(start - transfer.start, end - transfer.start + 1) : null;
  }

  /** Startup can wait for both tracks only when every required range fits retained caches. */
  canRetainStartupSegments(positionMs: number, pin: boolean = false): boolean {
    const cfg = this.config;
    if (!cfg) return false;
    let total = 0;
    const keys: string[] = [];
    for (let track = 0; track < 2; track++) {
      const list = track === 0 ? cfg.videoSegments : cfg.audioSegments;
      const ends = track === 0 ? this.videoEndsMs : this.audioEndsMs;
      if (list.length === 0 || ends.length !== list.length) return false;
      let index = ends.findIndex((end: number) => end > Math.max(0, positionMs));
      if (index < 0) index = list.length - 1;
      const indices: number[] = index > 0 ? [0, index] : [0];
      for (let i = 0; i < indices.length; i++) {
        const size = list[indices[i]].size;
        if (size <= 0 || size > DashMediaServer.RETAINED_LIMIT) return false;
        total += size;
        const entry = list[indices[i]];
        const url = track === 0 ? cfg.videoUrl : cfg.audioUrl;
        keys.push(this.cacheKey(url, entry.fileOffset, entry.fileOffset + size - 1));
      }
    }
    if (total > DashMediaServer.RETAINED_LIMIT) return false;
    if (pin) keys.forEach((key: string) => this.startupPins.add(key));
    return true;
  }

  /** Native demand shares the transfer; startup may await a validated prefix instead of its tail. */
  prefetchSegment(isVideo: boolean, segIdx: number, prefixBytes: number = 0): Promise<boolean> {
    const cfg = this.config;
    if (!cfg) {
      return Promise.resolve(false);
    }
    const list = isVideo ? cfg.videoSegments : cfg.audioSegments;
    const url = isVideo ? cfg.videoUrl : cfg.audioUrl;
    const fileSize = isVideo ? cfg.videoFileSize : cfg.audioFileSize;
    if (segIdx < 0 || segIdx >= list.length) {
      return Promise.resolve(false);
    }
    const entry = list[segIdx];
    // 与 route 的 seg 计算保持一致：sidx size 兜底 + 异常大值防御 + 文件尾 clamp
    let segLen = entry.size > 0 ? entry.size : DashMediaServer.MAX_SEG;
    if (segLen > DashMediaServer.MAX_SEG * 16) {
      segLen = DashMediaServer.MAX_SEG;
    }
    let realEnd = entry.fileOffset + segLen - 1;
    if (fileSize > 0 && realEnd >= fileSize) {
      realEnd = fileSize - 1;
    }
    if (realEnd < entry.fileOffset) {
      return Promise.resolve(false);
    }
    if (this.cacheGetExact(url, entry.fileOffset, realEnd) || this.cacheGetSlice(url, entry.fileOffset, realEnd)) return Promise.resolve(true);
    const transfer = this.getTransfer(url, entry.fileOffset, realEnd, cfg);
    return prefixBytes > 0 ? transfer.waitForPrefix(prefixBytes) : transfer.completion;
  }

  /**
   * ⭐ 按【时间】预取分段（续播 / 切画质用）。
   *
   * 为什么需要：播放器 seek 到 N 秒时，必须冷拉覆盖该时刻的整段（高码率片一段 2~4MB），
   * 实测这是首帧前最大的一块等待 —— 3.83s 的首帧里有 2.8s 花在「拉 seg 6~9」上，
   * 而首分片预取只覆盖了第 0 段、对 seek 目标无能为力。
   * 本方法把「N 秒 → 分段下标」算出来后走同一条 prefetchSegment 通路，于是这段下载
   * 与 AVPlayer 创建 / prepare 并行，seek 发起时直接命中缓存。
   *
   * 只预取实际起播段；下一段由播放器按需请求，避免首帧前争抢带宽。
   */
  prefetchSegmentAtTime(isVideo: boolean, timeMs: number, prefixBytes: number = 0): Promise<boolean> {
    const cfg = this.config;
    if (!cfg || timeMs <= 0) {
      return timeMs <= 0 ? this.prefetchSegment(isVideo, 0, prefixBytes) : Promise.resolve(false);
    }
    const list = isVideo ? cfg.videoSegments : cfg.audioSegments;
    const timescale = isVideo ? cfg.videoTimescale : cfg.audioTimescale;
    if (!timescale || timescale <= 0 || list.length === 0) {
      return Promise.resolve(false);
    }
    // ⚠️ 分段时长不均匀（sidx 逐条给出），必须累加真实 duration 而不是 总时长/段数 均分
    const target = timeMs / 1000 * timescale;
    const fallback = timescale * 5;   // 缺 duration 时按 5 秒兜底
    let acc = 0;
    for (let i = 0; i < list.length; i++) {
      // ⚠️ duration 是可选字段，必须先 ?? 收敛成 number ——
      //    ArkTS 严格空值检查不允许在条件里判完再当 number 用（Object is possibly 'undefined'）
      const raw: number = list[i].duration ?? 0;
      const d: number = raw > 0 ? raw : fallback;
      acc += d;
      if (acc > target) {
        console.info(`${TAG} 按时间预取: ${timeMs}ms -> seg[${i}]${(isVideo ? '(video)' : '(audio)')}`);
        return this.prefetchSegment(isVideo, i, prefixBytes);
      }
    }
    // Resume points may round a few milliseconds past the final indexed tick.
    return this.prefetchSegment(isVideo, list.length - 1, prefixBytes);
  }

  /** Only speculate on the next missing segment within four seconds of delivered coverage. */
  refillForPlayback(positionMs: number, rate: number = 1): void {
    if (!this.config || !Number.isFinite(positionMs) || positionMs < 0 || !Number.isFinite(rate)) return;
    const now = Date.now();
    const jumped = this.lastRefillPosition >= 0 && (positionMs < this.lastRefillPosition - 1000 ||
      positionMs - this.lastRefillPosition > 6000 * Math.max(1, rate));
    if (!jumped && now - this.lastRefillAt < 750) return;
    if (jumped) {
      this.deliveredVideo.clear(); this.deliveredAudio.clear();
      this.speculative.forEach((transfer: DashRangeTransfer) => transfer.cancel());
      this.speculative.clear();
    }
    this.lastRefillAt = now;
    this.lastRefillPosition = positionMs;
    const horizon = 4000 * Math.max(0.25, Math.min(4, rate));
    this.refillTrack(false, positionMs, horizon, now);
    this.refillTrack(true, positionMs, horizon, now);
  }

  private refillTrack(isVideo: boolean, position: number, horizon: number, now: number): void {
    const cfg = this.config;
    if (!cfg) return;
    const ends = isVideo ? this.videoEndsMs : this.audioEndsMs;
    const list = isVideo ? cfg.videoSegments : cfg.audioSegments;
    const delivered = isVideo ? this.deliveredVideo : this.deliveredAudio;
    const url = isVideo ? cfg.videoUrl : cfg.audioUrl;
    let low = 0;
    let high = ends.length;
    while (low < high) { const mid = Math.floor((low + high) / 2); if (ends[mid] <= position) low = mid + 1; else high = mid; }
    if (low >= ends.length) return;
    // Retain one previous segment for short backward seeks, reclaim older byte buffers.
    const cutoff = list[Math.max(0, low - 1)].fileOffset;
    this.cache.forEach((data: ArrayBuffer, key: string) => {
      const match = key.startsWith(url + '#') ? /#(\d+)-(\d+)$/.exec(key) : null;
      if (match && Number(match[2]) < cutoff) { this.cache.delete(key); this.cacheBytes -= data.byteLength; }
    });
    this.completed.forEach((transfer: DashRangeTransfer, key: string) => {
      if (transfer.url === url && transfer.end < cutoff) {
        this.completed.delete(key); this.completedBytes -= transfer.end - transfer.start + 1;
      }
    });
    let coverage = position;
    for (let i = low; i < ends.length; i++) {
      const entry = list[i];
      const fileSize = isVideo ? cfg.videoFileSize : cfg.audioFileSize;
      let size = entry.size > 0 && entry.size <= DashMediaServer.MAX_SEG * 16 ? entry.size : DashMediaServer.MAX_SEG;
      if (fileSize > 0) size = Math.min(size, fileSize - entry.fileOffset);
      if (size <= 0) return;
      const start = entry.fileOffset;
      const end = start + size - 1;
      if (delivered.has(i) || this.hasCompletedRange(url, start, end)) {
        coverage = ends[i];
        if (coverage - position >= horizon) return;
        continue;
      }
      const key = this.cacheKey(url, start, end);
      if ((this.prefetchRetryAfter.get(key) || 0) > now) return;
      let reserved = this.cacheBytes + this.completedBytes;
      let trackBusy = false;
      this.inflight.forEach((transfer: DashRangeTransfer) => {
        reserved += transfer.end - transfer.start + 1;
        if (transfer.url === url) trackBusy = true;
      });
      // Native demand always wins. Speculation cannot add another same-track download
      // or push retained + reserved byte ranges beyond the existing 32MiB budget.
      if (trackBusy || reserved + size > DashMediaServer.RETAINED_LIMIT) return;
      this.diagnosticRoot?.mark(isVideo ? 'refill-video' : 'refill-audio', i + 1, size);
      const pending = this.prefetchSegment(isVideo, i);
      const speculative = this.inflight.get(key);
      if (speculative) this.speculative.set(key, speculative);
      pending.then((success: boolean) => {
        if (!speculative || this.speculative.get(key) !== speculative) return;
        this.speculative.delete(key);
        if (this.config !== cfg || success) return;
        this.prefetchRetryAfter.set(key, Date.now() + 30000);
        if (this.prefetchRetryAfter.size > 64) this.prefetchRetryAfter.delete(this.prefetchRetryAfter.keys().next().value as string);
      });
      return;
    }
  }

  private hasCompletedRange(url: string, start: number, end: number): boolean {
    let found = false;
    this.cache.forEach((_data: ArrayBuffer, key: string) => {
      const match = key.startsWith(url + '#') ? /#(\d+)-(\d+)$/.exec(key) : null;
      if (match && Number(match[1]) <= start && Number(match[2]) >= end) found = true;
    });
    this.completed.forEach((transfer: DashRangeTransfer) => {
      if (transfer.url === url && transfer.start <= start && transfer.end >= end) found = true;
    });
    return found;
  }

  private handleConnection(conn: socket.TCPSocketConnection): void {
    const client = new Client(conn);
    this.clients.push(client);

    conn.on('message', (info: socket.SocketMessageInfo) => {
      client.append(info.message);
      this.tryParseAndRespond(client);
    });
    conn.on('close', () => {
      this.removeClient(client);
    });
    conn.on('error', () => {
      this.removeClient(client);
    });
  }

  private removeClient(client: Client): void {
    client.markClosed();
    const idx = this.clients.indexOf(client);
    if (idx >= 0) {
      this.clients.splice(idx, 1);
    }
  }

  /**
   * 从缓冲区尝试解析 HTTP 请求头（\r\n\r\n 为界）。
   * 同一连接支持连续多请求（keep-alive）：解析并消费一个请求后，
   * 若缓冲区仍有数据则继续处理（由 route 完成后重新调用）。
   */
  private tryParseAndRespond(client: Client): void {
    if (client.busy || client.closed) {
      return;
    }
    const buf = client.buffer;
    // 找 \r\n\r\n
    let headerEnd = -1;
    for (let i = 0; i + 3 < buf.length; i++) {
      if (buf[i] === 0x0d && buf[i + 1] === 0x0a && buf[i + 2] === 0x0d && buf[i + 3] === 0x0a) {
        headerEnd = i + 3;
        break;
      }
    }
    if (headerEnd < 0) {
      // 头未完整，继续等（但限最大长度防滥用）
      if (buf.length > 65536) {
        this.sendResponse(client, 400, 'text/plain', strToArrayBuffer('Bad Request: header too large'), -1, -1, -1);
      }
      return;
    }
    const headerText = bytesToString(buf, 0, headerEnd);
    console.info(`${TAG} request: ${headerText.split('\r\n')[0]}`);
    // 解析请求行与 Range
    const req = parseHttpRequest(headerText);
    if (!req) {
      this.sendResponse(client, 400, 'text/plain', strToArrayBuffer('Bad Request'), -1, -1, -1);
      return;
    }
    client.reqId = req.path;
    // ⭐ 消费已解析的请求头，之后同一连接可继续收新请求
    client.consume(headerEnd + 1);
    client.busy = true;
    this.route(client, req).then(() => {
      client.busy = false;
      // 若缓冲区还有数据（同一请求管线下的后续请求），继续解析
      if (client.buffer.length > 0) {
        this.tryParseAndRespond(client);
      }
    });
  }

  /** 路由请求 */
  private async route(client: Client, req: HttpRequestInfo): Promise<void> {
    const name = req.path === '/manifest.mpd' ? 'manifest' :
      (/^\/(video|audio)_(init|seg_\d+)\.m4s$/.test(req.path) ? req.path.replace(/[^a-zA-Z0-9_-]/g, '') : 'unknown');
    const profile = PlaybackStartup.span('local-' + name, this.diagnosticRoot);
    const cfg = this.config;
    if (!cfg) {
      await this.sendResponse(client, 503, 'text/plain', strToArrayBuffer('no config'), -1, -1, -1);
      return;
    }

    try {
      // ⭐ MPD
      if (req.path === '/manifest.mpd' || req.path === '/') {
        await this.sendResponse(client, 200, 'application/dash+xml', strToArrayBuffer(cfg.mpdXml), req.rangeStart, req.rangeEnd, -1);
        return;
      }

      // ⭐ init 段：video_init.m4s / audio_init.m4s（与 MPD initialization 一致）
      if (req.path === '/video_init.m4s' || req.path === '/audio_init.m4s') {
        const isVideo = req.path === '/video_init.m4s';
        const size = isVideo ? cfg.videoInitSize : cfg.audioInitSize;
        if (size <= 0) {
          await this.sendResponse(client, 500, 'text/plain', strToArrayBuffer('init size unknown'), -1, -1, -1);
          return;
        }
        const url = isVideo ? cfg.videoUrl : cfg.audioUrl;
        // ⭐ 按 AVPlayer Range 精确切片；无 Range 则整段
        const start = req.rangeStart >= 0 ? req.rangeStart : 0;
        const end = req.rangeEnd >= 0 ? req.rangeEnd : size - 1;
        const clampedEnd = Math.min(end, size - 1);
        // ⭐ 探测缓冲命中：探测窗口完整覆盖 initRange，直接切片零回源（首帧关键路径）
        const headBuf = isVideo ? cfg.videoInitBuffer : cfg.audioInitBuffer;
        if (headBuf && headBuf.byteLength > 0 && start >= 0 && clampedEnd < headBuf.byteLength) {
          const slice = headBuf.slice(start, clampedEnd + 1);
          await this.sendResponse(client, 200, 'video/mp4', slice, req.rangeStart, req.rangeEnd, size);
          return;
        }
        const data = await this.fetchCached(url, start, clampedEnd, cfg);
        if (data) {
          await this.sendResponse(client, 200, 'video/mp4', data, req.rangeStart, req.rangeEnd, size);
        } else {
          await this.sendResponse(client, 502, 'text/plain', strToArrayBuffer('fetch init failed'), -1, -1, -1);
        }
        return;
      }

      // ⭐ 媒体段：video_seg_N.m4s / audio_seg_N.m4s（与 MPD media 模板一致，startNumber=1）
      const segMatch = /^\/(video|audio)_seg_(\d+)\.m4s$/.exec(req.path);
      if (segMatch) {
        const isVideo = segMatch[1] === 'video';
        const num = parseInt(segMatch[2], 10);
        const idx = num - 1;
        const list = isVideo ? cfg.videoSegments : cfg.audioSegments;
        if (idx < 0 || list.length === 0) {
          await this.sendResponse(client, 404, 'text/plain', strToArrayBuffer('segment not found'), -1, -1, -1);
          return;
        }
        // ⭐ 越界兜底（2026-09-19）：这里就是「最后几秒画面静止 / 结尾报错」的直接现场。
        //    ⚠️ **不能回 404** —— 实测 AVPlayer 收到 404 会抛 5411007 IO Resource Not Found
        //    并进入 error 态（后续 seek/播放全部失败），比「最后一段数据重复」严重得多。
        //    ⇒ 回落到最后一段返回（重复尾部数据）：播放能正常走到片尾，不会中途崩掉。
        //    根治在 DashMpdBuilder.safeSegmentTemplateTicks()（让播放器根本不会请求越界段），这里只是安全网。
        const servedIdx = idx < list.length ? idx : list.length - 1;
        if (servedIdx !== idx) {
          console.warn(`${TAG} seg[${num}] 越界(${isVideo ? 'video' : 'audio'}: idx=${idx}, list=${list.length}) → 回落到最后一段 seg[${servedIdx + 1}]`);
        }
        const entry = list[servedIdx];
        const url = isVideo ? cfg.videoUrl : cfg.audioUrl;
        const fileSize = isVideo ? cfg.videoFileSize : cfg.audioFileSize;
        // ⭐ 用 sidx 真实 fileOffset 映射（seek/乱序请求也准确）。
        //    此前游标顺序分配只在顺序播放时正确，seek 后 AVPlayer 按任意 seg_N 请求
        //    会错乱映射（实测拖动进度条后音画全无）。
        //    若该段 fileOffset 超出文件（sidx 尾条失真），回退游标模式。
        let segmentSize = entry.size > 0 && entry.size <= DashMediaServer.MAX_SEG * 16 ? entry.size : DashMediaServer.MAX_SEG;
        if (fileSize > 0) segmentSize = Math.min(segmentSize, fileSize - entry.fileOffset);
        if (req.rangeStart >= segmentSize || segmentSize <= 0) {
          console.warn(`${TAG} rejected range start=${req.rangeStart} size=${segmentSize} path=${req.path}`);
          await this.sendResponse(client, 416, 'text/plain', strToArrayBuffer('range outside segment'), -1, -1, -1);
          return;
        }
        const rangeStart = req.rangeStart >= 0 ? req.rangeStart : 0;
        const hasRangeEnd = req.rangeEnd >= 0;
        let realStart = entry.fileOffset + rangeStart;
        let realEnd = hasRangeEnd ? entry.fileOffset + req.rangeEnd : -1;
        if (realEnd >= 0) realEnd = Math.min(realEnd, entry.fileOffset + segmentSize - 1);
        // 无 Range：段大小优先用 entry.size，再兜底 4MB；并 clamp 到文件尾
        if (realEnd < 0) {
          let segLen = (entry.size > 0 ? entry.size : DashMediaServer.MAX_SEG);
          // ⭐ 防御：个别文件 sidx 条目解析出异常大值(>64MB)时按 4MB 兜底，
          //    避免对 CDN 发起千次分块拉取把回源拖死
          if (segLen > DashMediaServer.MAX_SEG * 16) {
            console.warn(`${TAG} seg[${num}] size 异常(${segLen})，按 ${DashMediaServer.MAX_SEG} 兜底`);
            segLen = DashMediaServer.MAX_SEG;
          }
          realEnd = entry.fileOffset + segLen - 1;
        }
        // ⭐ clamp 到文件末尾：CDN 对越界 Range 回 416
        if (fileSize > 0 && realEnd >= fileSize) {
          // ⚠️ 被夹紧意味着 sidx 尾条(fileOffset/size)与实际文件大小不一致：
          //    该段只会拿到预期的一部分字节 ⇒ 解码器拿不到完整尾段（表现为结尾画面异常/静止）。
          console.warn(`${TAG} seg[${num}](${isVideo ? 'video' : 'audio'}) Range 被文件尾夹紧: 期望到 ${realEnd} 实际到 ${fileSize - 1} (fileSize=${fileSize}, sidx offset=${entry.fileOffset} size=${entry.size})`);
          realEnd = fileSize - 1;
        }
        const fetchLen = realEnd - realStart + 1;
        if (fetchLen <= 0) {
          await this.sendResponse(client, 400, 'text/plain', strToArrayBuffer('bad range'), -1, -1, -1);
          return;
        }
        console.info(`${TAG} seg[${num}] fetch bytes=${realStart}-${realEnd} len=${fetchLen} (sidx offset=${entry.fileOffset} size=${entry.size})`);
        const sent = await this.sendSegment(client, req, url, realStart, realEnd, entry.fileOffset, segmentSize, cfg, profile);
        if (sent && this.config === cfg && realStart === entry.fileOffset && realEnd === entry.fileOffset + segmentSize - 1) {
          (isVideo ? this.deliveredVideo : this.deliveredAudio).add(servedIdx);
          this.startupPins.delete(this.cacheKey(url, realStart, realEnd));
          this.trimCache();
          this.trimCompleted();
        }
        return;
      }

      await this.sendResponse(client, 404, 'text/plain', strToArrayBuffer('Not Found: ' + req.path), -1, -1, -1);
    } catch (e) {
      console.error(`${TAG} route error: ${(e as BusinessError).message}`);
      await this.sendResponse(client, 500, 'text/plain', strToArrayBuffer('internal error'), -1, -1, -1);
    } finally { profile?.end(); }
  }

  /** Send ordered bytes as they arrive; a partial response failure closes this connection. */
  private async sendSegment(client: Client, req: HttpRequestInfo, url: string, start: number, end: number,
    segmentStart: number, segmentSize: number, cfg: DashServerConfig, profile?: PlaybackSpan | null): Promise<boolean> {
    const cached = this.cacheGetExact(url, start, end) || this.cacheGetSlice(url, start, end);
    const rangeStart = req.rangeStart >= 0 ? start - segmentStart : -1;
    const rangeEnd = req.rangeStart >= 0 ? end - segmentStart : -1;
    if (cached) {
      profile?.mark('cache-hit', 0, cached.byteLength);
      await this.sendResponse(client, 200, 'video/mp4', cached, rangeStart, rangeEnd, segmentSize);
      return !client.closed;
    }
    let transfer = this.getTransfer(url, start, end, cfg, true);
    profile?.mark('transfer', transfer.traceId());
    let offset = start;
    let sentHeaders = false;
    let retried = false;
    try {
      while (offset <= end && !client.closed) {
        const chunk = await Promise.race([transfer.read(offset, end), client.disconnected]);
        if (client.closed) return false;
        if (!chunk) {
          // Before any response bytes are sent a failed CDN request can be retried safely.
          // After the prefix is sent, close the response and let the native client reconnect.
          if (!sentHeaders && !retried && this.config === cfg) {
            await transfer.completion;
            transfer = this.getTransfer(url, start, end, cfg, true);
            retried = true;
            continue;
          }
          throw new Error('incomplete media range');
        }
        if (!sentHeaders) {
          profile?.mark('first-ready', 0, chunk.byteLength);
          const header = responseHeader(rangeStart >= 0 ? 206 : 200, 'video/mp4', end - start + 1,
            rangeStart, rangeEnd, segmentSize);
          await client.conn.send({ data: strToArrayBuffer(header) });
          sentHeaders = true;
        }
        // Keep cache/download buffers owned here across native asynchronous sends.
        const length = chunk.byteLength;
        await client.conn.send({ data: chunk.slice(0) });
        offset += length;
        profile?.once('first-sent', 0, length);
      }
      profile?.mark(client.closed ? 'client-closed' : 'body-sent', end - start + 1, offset - start);
      return offset > end && !client.closed;
    } catch (_) {
      profile?.mark('stream-failed', sentHeaders ? 1 : 0, offset - start);
      console.warn(`${TAG} stream interrupted headers=${sentHeaders} path=${req.path}`);
      if (sentHeaders) {
        client.markClosed();
        await client.conn.close().catch(() => {});
      } else if (!client.closed) {
        await this.sendResponse(client, 502, 'text/plain', strToArrayBuffer('fetch seg failed'), -1, -1, -1);
      }
      return false;
    }
  }

  /**
   * 发送 HTTP 响应（大响应分块发送）。
   * ⭐ body 已是 route 按 Range 精确拉取的结果，不再二次切片；
   *    仅当带 Range 且 body 未按 Range 处理时（无 Range 请求）返回全部。
   */
  private async sendResponse(
    client: Client,
    code: number,
    contentType: string,
    body: ArrayBuffer,
    rangeStart: number,
    rangeEnd: number,
    totalSize: number
  ): Promise<void> {
    const sendBody = body;
    const partial = rangeStart >= 0 && body.byteLength > 0;
    const last = rangeStart + body.byteLength - 1;
    const head = responseHeader(partial ? 206 : code, contentType, body.byteLength,
      partial ? rangeStart : -1, rangeEnd >= 0 ? Math.min(rangeEnd, last) : last, totalSize);
    const headBytes = strToArrayBuffer(head);

    try {
      // 先发头，再发体（TCP 顺序保证）；大响应按 4MB 分块避免单次 send 过载
      const headOpt: socket.TCPSendOptions = { data: headBytes };
      await client.conn.send(headOpt);
      const SEND_CHUNK = 4 * 1024 * 1024;
      let pos = 0;
      const sendLen = sendBody.byteLength;
      while (pos < sendLen) {
        const endPos = Math.min(pos + SEND_CHUNK, sendLen);
        const chunk = sendBody.slice(pos, endPos);
        const bodyOpt: socket.TCPSendOptions = { data: chunk };
        await client.conn.send(bodyOpt);
        pos = endPos;
      }
    } catch (e) {
      console.error(`${TAG} send error: ${(e as BusinessError).message}`);
      client.markClosed();
      try {
        await client.conn.close();
      } catch (_e) {
      }
    }
  }
}

function responseHeader(code: number, contentType: string, length: number,
  start: number, end: number, total: number): string {
  let reason = 'OK';
  if (code === 206) reason = 'Partial Content';
  else if (code === 400) reason = 'Bad Request';
  else if (code === 404) reason = 'Not Found';
  else if (code === 416) reason = 'Range Not Satisfiable';
  else if (code === 500) reason = 'Internal Server Error';
  else if (code === 502) reason = 'Bad Gateway';
  else if (code === 503) reason = 'Service Unavailable';
  const range = code === 206 ? `Content-Range: bytes ${start}-${end}/${total}\r\n` : '';
  return `HTTP/1.1 ${code} ${reason}\r\nContent-Type: ${contentType}\r\nContent-Length: ${length}\r\n` +
    `Accept-Ranges: bytes\r\n${range}Connection: keep-alive\r\n\r\n`;
}

/** 解析后的 HTTP 请求信息 */
interface HttpRequestInfo {
  method: string;
  path: string;
  rangeStart: number;
  rangeEnd: number;
}

/** 解析 HTTP 请求头文本（请求行 + Range 头） */
function parseHttpRequest(headerText: string): HttpRequestInfo | null {
  const lines = headerText.split('\r\n');
  if (lines.length < 1) {
    return null;
  }
  const parts = lines[0].split(' ');
  if (parts.length < 2) {
    return null;
  }
  const method = parts[0];
  const target = parts[1];
  // 去 query
  const qIdx = target.indexOf('?');
  const path = qIdx >= 0 ? target.substring(0, qIdx) : target;

  let rangeStart = -1;
  let rangeEnd = -1;
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    const cIdx = line.indexOf(':');
    if (cIdx < 0) {
      continue;
    }
    const name = line.substring(0, cIdx).toLowerCase();
    const value = line.substring(cIdx + 1).trim();
    if (name === 'range') {
      const m = /bytes=(\d+)-(\d*)/.exec(value);
      if (m) {
        rangeStart = parseInt(m[1], 10);
        if (m[2] && m[2].length > 0) {
          rangeEnd = parseInt(m[2], 10);
        }
      } else {
        const m2 = /bytes=-(\d+)/.exec(value);
        if (m2) {
          rangeStart = 0;
          rangeEnd = -1; // 未知，按全量处理
        }
      }
    }
  }

  const info: HttpRequestInfo = {
    method: method,
    path: path,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd
  };
  return info;
}

function strToArrayBuffer(str: string): ArrayBuffer {
  const buf = new ArrayBuffer(str.length);
  const view = new Uint8Array(buf);
  for (let i = 0; i < str.length; i++) {
    view[i] = str.charCodeAt(i);
  }
  return buf;
}

function bytesToString(view: Uint8Array, start: number, end: number): string {
  let s = '';
  for (let i = start; i < end; i++) {
    s += String.fromCharCode(view[i]);
  }
  return s;
}
