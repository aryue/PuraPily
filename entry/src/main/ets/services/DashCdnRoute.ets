import { http } from '@kit.NetworkKit';
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';

/** One lazy, shared validation per track. Only API-provided alternate URLs are used. */
export class DashCdnRoute {
  currentUrl: string;
  private candidate: string;
  private head: ArrayBuffer;
  private fileSize: number;
  private prefixLength: number;
  private referer: string;
  private userAgent: string;
  private root: PlaybackSpan | null;
  private pending: Promise<string | null> | null = null;
  private tried: boolean = false;
  private stopped: boolean = false;
  private cancelWait: (() => void) | null = null;

  constructor(primary: string, candidates: string[], head: ArrayBuffer | undefined, fileSize: number,
    referer: string, userAgent: string, root: PlaybackSpan | null, prefixLength: number = 0) {
    this.currentUrl = primary;
    this.candidate = candidates.find((url: string) => !!url && url !== primary) || '';
    this.head = head || new ArrayBuffer(0);
    this.fileSize = fileSize;
    this.prefixLength = prefixLength > 0 ? prefixLength : Math.min(this.head.byteLength, 65536);
    if (this.prefixLength > this.head.byteLength || this.prefixLength > fileSize || this.prefixLength > 2 * 1024 * 1024) {
      this.candidate = '';
    }
    this.referer = referer;
    this.userAgent = userAgent;
    this.root = root;
  }

  async fallback(failedUrl: string): Promise<string | null> {
    if (this.stopped) return null;
    if (this.currentUrl !== failedUrl) return this.currentUrl;
    if (this.pending) return this.pending;
    if (this.tried || !this.candidate || this.head.byteLength === 0 || this.fileSize <= 0) return null;
    this.tried = true;
    const task = this.validate();
    this.pending = task;
    try { return await task; }
    finally { if (this.pending === task) this.pending = null; }
  }

  private async validate(): Promise<string | null> {
    const profile = PlaybackStartup.span('cdn-alternate-validation', this.root);
    let request: http.HttpRequest | null = null;
    let timer: number = -1;
    const cancelled = new Promise<null>((resolve) => { this.cancelWait = () => resolve(null); });
    try {
      const length = this.prefixLength;
      request = http.createHttp();
      const headers: Record<string, string> = {
        'User-Agent': this.userAgent, 'Range': `bytes=0-${length - 1}`, 'Accept-Encoding': 'identity'
      };
      if (this.referer) { headers['Referer'] = this.referer; headers['Origin'] = 'https://www.bilibili.com'; }
      timer = setTimeout(() => this.cancelWait?.(), 2000);
      const response = await Promise.race([request.request(this.candidate, {
        method: http.RequestMethod.GET, header: headers, expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 2000, readTimeout: 2000
      }), cancelled]);
      if (this.stopped || !response || response.responseCode !== 206) { profile?.mark('alternate-rejected', 1); return null; }
      const values = response.header as Record<string, string>;
      const rangeKey = Object.keys(values).find((key: string) => key.toLowerCase() === 'content-range');
      const range = rangeKey ? /^bytes\s+0-(\d+)\/(\d+)$/i.exec(String(values[rangeKey]).trim()) : null;
      if (!range || Number(range[1]) !== length - 1 || Number(range[2]) !== this.fileSize) {
        profile?.mark('alternate-rejected', 2); return null;
      }
      const body = response.result;
      if (!(body instanceof ArrayBuffer) || body.byteLength !== length) { profile?.mark('alternate-rejected', 3); return null; }
      // The known prefix includes the initialization and complete sidx table.
      // Reject another rendition/layout even if its advertised quality is the same.
      const expected = new Uint8Array(this.head, 0, length);
      const actual = new Uint8Array(body);
      for (let i = 0; i < length; i++) {
        if (expected[i] !== actual[i]) { profile?.mark('alternate-rejected', 4); return null; }
      }
      if (this.stopped) return null;
      this.currentUrl = this.candidate;
      profile?.mark('alternate-ready');
      return this.currentUrl;
    } catch (_) { profile?.mark('alternate-rejected', 5); return null; }
    finally {
      clearTimeout(timer);
      this.cancelWait = null;
      try { request?.destroy(); } catch (_) { }
      profile?.end();
    }
  }

  cancel(): void {
    this.stopped = true;
    this.cancelWait?.();
  }
}
