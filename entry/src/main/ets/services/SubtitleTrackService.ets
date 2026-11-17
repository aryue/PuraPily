import { http } from '@kit.NetworkKit';
import { AppSign } from '../utils/SignUtils';
import { logInfo, logWarn } from '../utils/Logger';

export interface ReferenceSubtitleTrack { subtitle_url: string; lan_doc: string }
export interface ReferenceSubtitleCue { from: number; to: number; content: string }
interface ReferenceSubtitleBody { body?: ReferenceSubtitleCue[] }

interface ReferenceSubtitleList { subtitles?: ReferenceSubtitleTrack[] }
interface ReferenceSubtitleData {
  // ⭐ 接口会把实际解析到的稿件回显回来（bvid/cid 原样带回），可用于校验没有串到别的稿件
  aid?: number;
  bvid?: string;
  cid?: number;
  subtitle?: ReferenceSubtitleList;
}
interface ReferenceSubtitleInfo { code: number; data?: ReferenceSubtitleData }
// ⭐ /x/web-interface/view 反查出来的权威稿件身份（字幕轨要拿它比对文件名）
interface SubtitleIdentity { aid: number; cid: number; duration: number }
export interface SubtitlePlaybackIdentity { aid: number; bvid: string; cid: number; pgc: boolean }
interface SubtitleViewData { aid?: number; cid?: number; duration?: number }
interface SubtitleViewInfo { code: number; data?: SubtitleViewData }
type SubtitleRequest = 'toggle' | 'menu' | 'selection';

export class SubtitleTrackService {
  private subtitleIdentityCache_: Map<string, SubtitleIdentity> = new Map<string, SubtitleIdentity>();
  private cues: ReferenceSubtitleCue[] = [];
  private cueOwner: string = '';
  private requestSerial: number = 0;
  private requests: Map<SubtitleRequest, number> = new Map<SubtitleRequest, number>();
  private menuOwner: string = '';
  private menuTracks: ReferenceSubtitleTrack[] = [];

  beginRequest(kind: SubtitleRequest): number {
    const token = ++this.requestSerial;
    this.requests.set(kind, token);
    return token;
  }

  isCurrentRequest(kind: SubtitleRequest, token: number): boolean {
    return this.requests.get(kind) === token;
  }

  resetPlayback(): void {
    this.requests.clear();
    this.clearCues();
    this.clearMenuTracks();
  }

  clearMenuTracks(): void {
    this.menuOwner = '';
    this.menuTracks = [];
  }

  setMenuTracks(owner: string, tracks: ReferenceSubtitleTrack[]): string[] {
    this.menuOwner = owner;
    this.menuTracks = tracks;
    return tracks.map((track: ReferenceSubtitleTrack) => track.lan_doc || '字幕');
  }

  hasMenuTracksFor(owner: string): boolean {
    return this.menuOwner === owner;
  }

  menuTrackUrl(index: number): string {
    return this.menuTracks[index]?.subtitle_url || '';
  }

  clearCues(): void {
    this.cues = [];
    this.cueOwner = '';
  }

  setCues(cues: ReferenceSubtitleCue[], bvid: string, cid: number): void {
    this.cues = cues;
    this.cueOwner = `${bvid}:${cid}`;
  }

  /** Null signals stale cues. An empty string is a valid gap. */
  textAt(owner: string, seconds: number): string | null {
    if (this.cues.length > 0 && this.cueOwner !== owner) return null;
    const cue = this.cues.find((item: ReferenceSubtitleCue) => item.from <= seconds && item.to >= seconds);
    return cue?.content || '';
  }

  /** Manual tracks have no media identity in the filename, so check the cue span as well. */
  subtitleCueFits(cues: ReferenceSubtitleCue[], duration: number | undefined, playerDuration: number): boolean {
    if (cues.length === 0) return false;
    const videoDuration = duration !== undefined && duration > 0 ? duration : playerDuration;
    return !(videoDuration > 0) || cues[cues.length - 1].to <= videoDuration * 1.2 + 15;
  }

  logSubtitleCueSpan(cues: ReferenceSubtitleCue[], bvid: string, cid: number, duration: number | undefined): void {
    if (cues.length === 0) {
      logWarn(`[Subtitle] cues=0 bvid=${bvid} cid=${cid}`);
      return;
    }
    const first = cues[0];
    const last = cues[cues.length - 1];
    const samples = cues.slice(0, 3).map((cue: ReferenceSubtitleCue) =>
      `${cue.from.toFixed(1)}|${(cue.content || '').replace(/\s+/g, ' ').slice(0, 12)}`).join(' / ');
    logInfo(`[Subtitle] cues=${cues.length} span=${first.from.toFixed(1)}~${last.to.toFixed(1)}s ` +
      `duration=${duration}s id=${bvid}:${cid} head=${samples}`);
  }

  async downloadTrack(url: string): Promise<ReferenceSubtitleCue[]> {
    const request = http.createHttp();
    try {
      const response = await request.request(url.startsWith('//') ? `https:${url}` : url, {
        method: http.RequestMethod.GET, connectTimeout: 8000, readTimeout: 8000,
        header: { 'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
      });
      if (response.responseCode !== 200) throw new Error(`字幕 HTTP ${response.responseCode}`);
      const body = JSON.parse(response.result as string) as ReferenceSubtitleBody;
      return body.body || [];
    } finally {
      request.destroy();
    }
  }

  // AI 文件名以 aid + cid 开头，末尾是 32 位 MD5。
  subtitleTrackPrefix(url: string): string {
    const path = url.split('?')[0];
    const name = path.slice(path.lastIndexOf('/') + 1);
    if (name.length <= 32) return '';
    return name.slice(0, name.length - 32);
  }

  private subtitleIsAiTrack(url: string): boolean {
    return url.indexOf('/ai_subtitle/prod/') >= 0;
  }

  /**
   * ⭐ 轨道归属判定：AI 轨文件名自带 `<aid><cid>`，与当前稿件不一致就是**别的视频**的字幕。
   * 2026-11-12 实测：aid+bvid+cid 三者给全、登录态下请求 /x/player/v2，服务端依然会返回
   * 账号里另一条视频的 AI 轨（36s 的《卡莉亚的炼金工房》预告拿到 250s 探店 vlog 的轨，
   * 回显的 bvid/cid 却是对的），所以接口回显校验拦不住，必须看文件名。
   * 人工字幕文件名是纯 md5，没有身份信息，只能靠时长兜底（subtitleCueFits）。
   */
  private subtitleTrackOwned(track: ReferenceSubtitleTrack, aid: number, cid: number): boolean {
    const url = track.subtitle_url || '';
    if (!url) return false;
    if (!this.subtitleIsAiTrack(url)) return true;
    if (aid <= 0 || cid <= 0) return false;
    return this.subtitleTrackPrefix(url) === `${aid}${cid}`;
  }

  /**
   * ⭐ 权威 aid：AI 轨文件名里的 aid 必须和请求一致才能认出自己的轨，
   * 所以 aid 由 bvid 反查（公开接口，不需要登录），不用详情/路由里可能停在上一条的值。
   */
  private async subtitleAuthoritativeIdentity(bvid: string): Promise<SubtitleIdentity | null> {
    const cached = this.subtitleIdentityCache_.get(bvid);
    if (cached) return cached;
    const request = http.createHttp();
    try {
      const result = await request.request(`https://api.bilibili.com/x/web-interface/view?bvid=${bvid}`, {
        method: http.RequestMethod.GET, connectTimeout: 6000, readTimeout: 6000,
        header: { 'Referer': 'https://www.bilibili.com/' }
      });
      const info = JSON.parse(result.result as string) as SubtitleViewInfo;
      const aid = info.data?.aid || 0;
      if (info.code !== 0 || aid <= 0) {
        logWarn(`[Subtitle] 反查 aid 失败 code=${info.code} bvid=${bvid}`);
        return null;
      }
      const identity: SubtitleIdentity = { aid, cid: info.data?.cid || 0, duration: info.data?.duration || 0 };
      this.subtitleIdentityCache_.set(bvid, identity);
      return identity;
    } catch (error) {
      logWarn('[Subtitle] 反查 aid 异常', error);
      return null;
    } finally { request.destroy(); }
  }

  /**
   * ⭐ 取字幕轨列表：先试网页播放器在用的 wbi 版，再退回老版；两条都要过归属校验。
   * @returns 只包含属于当前视频的轨；空数组 = 这条视频确实没有可用字幕
   */
  async subtitleFetchTracks(playback: SubtitlePlaybackIdentity): Promise<ReferenceSubtitleTrack[]> {
    const bvid = playback.bvid;
    const cid = playback.cid;
    const localAid = playback.aid;
    const identity = await this.subtitleAuthoritativeIdentity(bvid);
    // ⚠️ 请求口径与校验口径要分开：番剧/影视带 aid 反而返回空列表（见 subtitleAid_），
    //   但 AI 轨文件名里的 aid 依然是这条视频的 aid，校验时必须用它。
    const requestAid = playback.pgc ? 0 : (identity ? identity.aid : localAid);
    const expectAid = identity ? identity.aid : requestAid;
    if (!playback.pgc && identity && localAid > 0 && identity.aid !== localAid) {
      logWarn(`[Subtitle] aid 修正 本地=${localAid} 权威=${identity.aid} bvid=${bvid}`);
    }
    const urls: string[] = [];
    try {
      const params: Record<string, string> = {};
      if (requestAid > 0) params['aid'] = `${requestAid}`;
      params['bvid'] = bvid;
      params['cid'] = `${cid}`;
      urls.push(`https://api.bilibili.com/x/player/wbi/v2?${await AppSign.generateWebParams(params)}`);
    } catch (error) {
      logWarn('[Subtitle] wbi 签名失败，跳过 wbi 版', error);
    }
    const legacy = requestAid > 0 ? `aid=${requestAid}&bvid=${bvid}&cid=${cid}` : `bvid=${bvid}&cid=${cid}`;
    urls.push(`https://api.bilibili.com/x/player/v2?${legacy}`);
    const cookie = AppStorage.get<string>('biliCookie') || '';
    for (let i = 0; i < urls.length; i++) {
      const label = i === 0 ? 'wbi' : 'v2';
      const request = http.createHttp();
      try {
        const result = await request.request(urls[i], {
          method: http.RequestMethod.GET, connectTimeout: 8000, readTimeout: 8000,
          header: { 'Cookie': cookie, 'Referer': 'https://www.bilibili.com/' }
        });
        const info = JSON.parse(result.result as string) as ReferenceSubtitleInfo;
        const raw = info.data?.subtitle?.subtitles || [];
        const owned = raw.filter((track: ReferenceSubtitleTrack) => this.subtitleTrackOwned(track, expectAid, cid));
        const files = raw.map((track: ReferenceSubtitleTrack) =>
          this.subtitleTrackPrefix(track.subtitle_url) || 'md5').join(',');
        logInfo(`[Subtitle] ${label} code=${info.code} aid=${requestAid} cid=${cid} ` +
          `echo=${info.data?.bvid || '-'}/${info.data?.cid ?? 0} tracks=${raw.length} owned=${owned.length} files=${files}`);
        if (owned.length > 0) return owned;
        if (raw.length > 0) logWarn(`[Subtitle] ${label} 轨道全部不属于 ${bvid}:${cid}，丢弃`);
      } catch (error) {
        logWarn(`[Subtitle] ${label} 字幕列表请求失败`, error);
      } finally { request.destroy(); }
    }
    return [];
  }

}
