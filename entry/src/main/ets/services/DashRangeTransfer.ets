import { http } from '@kit.NetworkKit';
import { PlaybackStartup, PlaybackSpan } from '../utils/PlaybackStartup';
import { BusinessError } from '@kit.BasicServicesKit';
import type { DashCdnRoute } from './DashCdnRoute';

interface RangeChunk {
  offset: number;
  data: ArrayBuffer;
}

/** Shared bounded CDN range downloads; readers consume ordered blocks before the whole segment finishes. */
export class DashRangeTransfer {
  readonly url: string;
  readonly start: number;
  readonly end: number;
  readonly completion: Promise<boolean>;
  private resolveCompletion: ((success: boolean) => void) | null = null;
  private requests: Set<http.HttpRequest> = new Set();
  private requestCancellations: Set<() => void> = new Set();
  private begun: boolean = false;
  private chunks: RangeChunk[] = [];
  private received: number = 0;
  private finished: boolean = false;
  private success: boolean = false;
  private waiters: Set<() => void> = new Set();
  private deadline: number = -1;
  private startedAt: number = 0;
  private profile: PlaybackSpan | null = null;
  private route: DashCdnRoute | null;

  constructor(url: string, start: number, end: number, label: string = 'cdn-range', root: PlaybackSpan | null = null,
    route: DashCdnRoute | null = null) {
    this.profile = PlaybackStartup.span(label, root);
    this.profile?.mark('range', start, end - start + 1);
    this.url = url;
    this.start = start;
    this.end = end;
    this.route = route;
    this.completion = new Promise<boolean>((resolve) => { this.resolveCompletion = resolve; });
  }

  begin(referer: string, userAgent: string): void {
    if (this.begun || this.finished) return;
    this.begun = true;
    this.startedAt = Date.now();
    this.armDeadline();
    this.download(referer, userAgent).catch(() => this.finish(false));
  }

  private async download(referer: string, userAgent: string): Promise<void> {
    // Keep the bounded range layout, but publish 64KB batches while each response
    // is still arriving. Native HTTP callbacks never own buffers sent to readers.
    const starts: number[] = [];
    const ends: number[] = [];
    let offset = this.start;
    while (offset <= this.end) {
      const size = offset === this.start && this.end - this.start + 1 > 2 * 1024 * 1024
        ? 256 * 1024 : 2 * 1024 * 1024;
      const end = Math.min(this.end, offset + size - 1);
      starts.push(offset);
      ends.push(end);
      offset = end + 1;
    }
    let next = 0;
    const worker = async (): Promise<void> => {
      while (!this.finished) {
        const index = next++;
        if (index >= starts.length) return;
        let requestStart = starts[index];
        let requestUrl = this.route?.currentUrl || this.url;
        let overlap: Uint8Array | null = null;
        let resumeBoundary = 0;
        // Retry only this subrange, keeping validated prefixes and other workers.
        for (let attempt = 0; attempt < 2 && !this.finished; attempt++) {
          const requestProfile = PlaybackStartup.span('cdn-request', this.profile);
          let request: http.HttpRequest | null = null;
          let committedOffset = requestStart;
          let requestBytes = 0;
          let accepting = true;
          let idleTimer: number = -1;
          let rejectIdle: (error: Error) => void = () => {};
          const idleFailure = new Promise<number>((_resolve, reject) => { rejectIdle = reject; });
          idleFailure.catch(() => {});
          const cancelIdle = (): void => rejectIdle(new Error('range request cancelled'));
          this.requestCancellations.add(cancelIdle);
          const resetIdle = (): void => {
            clearTimeout(idleTimer);
            idleTimer = setTimeout(() => {
              if (!accepting || this.finished) return;
              requestProfile?.mark('request-idle-timeout', 4000, requestBytes);
              rejectIdle(new Error('range request stalled'));
            }, 4000);
          };
          try {
            request = http.createHttp();
            this.requests.add(request);
            requestProfile?.mark('http-start', requestStart, ends[index] - requestStart + 1);
            const expected = ends[index] - requestStart + 1;
            let publishOffset = resumeBoundary || requestStart;
            let overlapBytes = 0;
            let rangeVerified = false;
            let pending = new Uint8Array(64 * 1024);
            let pendingBytes = 0;
            const held: RangeChunk[] = [];
            const publish = (): void => {
              if (!accepting || !rangeVerified || this.finished || held.length === 0) return;
              held.forEach((chunk: RangeChunk) => {
                this.chunks.push(chunk);
                this.received += chunk.data.byteLength;
                committedOffset = chunk.offset + chunk.data.byteLength;
              });
              held.length = 0;
              requestProfile?.once('stream-first-ready', 0, this.received);
              this.notify();
            };
            const flush = (): void => {
              if (!accepting || pendingBytes === 0 || this.finished) return;
              held.push({ offset: publishOffset, data: pending.buffer.slice(0, pendingBytes) });
              publishOffset += pendingBytes;
              pendingBytes = 0;
              publish();
            };
            request.on('headersReceive', (headers: Object) => {
              if (!accepting || this.finished) return;
              const validation = this.verifyRange(headers, requestStart, ends[index]);
              if (validation < 0) { this.finish(false); return; }
              rangeVerified = validation > 0;
              if (rangeVerified) requestProfile?.once('stream-headers');
              publish();
            });
            request.on('dataReceive', (data: ArrayBuffer) => {
              if (!accepting || this.finished) return;
              if (requestBytes + data.byteLength > expected) { this.finish(false); return; }
              requestBytes += data.byteLength;
              resetIdle();
              requestProfile?.once('stream-first-data', 0, data.byteLength);
              this.armDeadline();
              const incoming = new Uint8Array(data);
              let offset = 0;
              if (overlap) {
                while (offset < incoming.byteLength && overlapBytes < overlap.byteLength) {
                  if (incoming[offset++] !== overlap[overlapBytes++]) {
                    requestProfile?.mark('cdn-overlap-mismatch');
                    this.finish(false);
                    return;
                  }
                }
              }
              while (offset < incoming.byteLength) {
                const count = Math.min(pending.byteLength - pendingBytes, incoming.byteLength - offset);
                pending.set(incoming.subarray(offset, offset + count), pendingBytes);
                pendingBytes += count;
                offset += count;
                if (pendingBytes === pending.byteLength) flush();
              }
            });
            request.on('dataEnd', () => {
              if (!accepting || this.finished) return;
              flush();
              requestProfile?.mark('stream-data-end', 0, requestBytes);
            });
            const requestHeaders: Record<string, string> = {
              'User-Agent': userAgent, 'Range': `bytes=${requestStart}-${ends[index]}`, 'Accept-Encoding': 'identity'
            };
            if (referer) { requestHeaders['Referer'] = referer; requestHeaders['Origin'] = 'https://www.bilibili.com'; }
            resetIdle();
            const code = await Promise.race([request.requestInStream(requestUrl, {
              method: http.RequestMethod.GET, header: requestHeaders,
              connectTimeout: 15000, readTimeout: 15000
            }), idleFailure]);
            requestProfile?.mark('http-return', code, requestBytes);
            if (this.finished) return;
            if (code !== 206 || requestBytes !== expected) {
              if (this.route && attempt === 0 && committedOffset === requestStart && code >= 400) throw new Error('media HTTP failure');
              this.finish(false);
              return;
            }
            // A valid completed 206 is also usable if a platform omitted the header event.
            // In that case all batches remained held until full response validation.
            rangeVerified = true;
            flush();
            publish();
            if (starts[index] === this.start) PlaybackStartup.trace('range-prefix-ready', this.startedAt);
            requestProfile?.mark('body', code, requestBytes);
          } catch (error) {
            accepting = false;
            if (this.finished) {
              requestProfile?.mark('request-cancelled');
              return;
            }
            const code = (error as BusinessError)?.code;
            requestProfile?.mark('request-failed', typeof code === 'number' ? code : 0, requestBytes);
            if (attempt === 0 && committedOffset <= ends[index]) {
              clearTimeout(idleTimer);
              if (request && this.requests.delete(request)) { try { request.destroy(); } catch (_) { } }
              const alternate = await this.route?.fallback(requestUrl);
              if (this.finished) return;
              requestStart = committedOffset;
              if (alternate && alternate !== requestUrl) {
                if (committedOffset > starts[index]) {
                  const overlapStart = Math.max(starts[index], committedOffset - 64 * 1024);
                  const known = this.publishedSlice(overlapStart, committedOffset - 1);
                  if (!known) { this.finish(false); return; }
                  overlap = new Uint8Array(known);
                  resumeBoundary = committedOffset;
                  requestStart = overlapStart;
                }
                requestUrl = alternate;
                requestProfile?.mark('cdn-node-switch', 1);
              }
              requestProfile?.mark('range-retry', requestStart, ends[index] - requestStart + 1);
              continue;
            }
            this.finish(false);
            return;
          } finally {
            accepting = false;
            clearTimeout(idleTimer);
            this.requestCancellations.delete(cancelIdle);
            requestProfile?.end();
            if (request && this.requests.delete(request)) {
              try { request.destroy(); } catch (_) { }
            }
          }
          break;
        }
      }
    };
    const workers: Promise<void>[] = [];
    for (let i = 0; i < Math.min(4, starts.length); i++) workers.push(worker());
    await Promise.all(workers);
    if (!this.finished) this.finish(this.received === this.end - this.start + 1);
  }

  /** Only publish early when the CDN confirms the exact absolute byte range. */
  private publishedSlice(start: number, end: number): ArrayBuffer | null {
    const result = new Uint8Array(end - start + 1);
    let cursor = start;
    while (cursor <= end) {
      const chunk = this.chunks.find((item: RangeChunk) => cursor >= item.offset && cursor < item.offset + item.data.byteLength);
      if (!chunk) return null;
      const begin = cursor - chunk.offset;
      const length = Math.min(end - cursor + 1, chunk.data.byteLength - begin);
      result.set(new Uint8Array(chunk.data, begin, length), cursor - start);
      cursor += length;
    }
    return result.buffer;
  }

  private verifyRange(headers: Object, start: number, end: number): number {
    const values = headers as Record<string, string>;
    const keys = Object.keys(values);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== 'content-range') continue;
      const match = /^bytes\s+(\d+)-(\d+)\/(\d+|\*)$/i.exec(String(values[keys[i]]).trim());
      return match !== null && Number(match[1]) === start && Number(match[2]) === end &&
        (match[3] === '*' || Number(match[3]) > end) ? 1 : -1;
    }
    return 0;
  }

  /** Absolute CDN offsets, including when a later reader asks for a subrange. */
  async read(offset: number, end: number): Promise<ArrayBuffer | null> {
    if (offset < this.start || end > this.end || offset > end) return null;
    while (true) {
      if (this.finished && !this.success) return null;
      for (let i = 0; i < this.chunks.length; i++) {
        const chunk = this.chunks[i];
        if (offset >= chunk.offset && offset < chunk.offset + chunk.data.byteLength) {
          const begin = offset - chunk.offset;
          const length = Math.min(chunk.data.byteLength - begin, end - offset + 1, 256 * 1024);
          return begin === 0 && length === chunk.data.byteLength ? chunk.data : chunk.data.slice(begin, begin + length);
        }
      }
      if (this.finished) return null;
      await new Promise<void>((resolve) => { this.waiters.add(resolve); });
    }
  }

  traceId(): number { return this.profile?.id || 0; }

  /** Wait for a contiguous, range-validated prefix while the shared transfer continues. */
  async waitForPrefix(bytes: number): Promise<boolean> {
    if (!Number.isFinite(bytes) || bytes <= 0) return false;
    const end = Math.min(this.end, this.start + Math.floor(bytes) - 1);
    let offset = this.start;
    while (offset <= end) {
      const chunk = await this.read(offset, end);
      if (!chunk || chunk.byteLength === 0) return false;
      offset += chunk.byteLength;
    }
    return true;
  }

  collect(limit: number): ArrayBuffer | null {
    if (!this.success || this.received > limit) return null;
    const result = new Uint8Array(this.received);
    this.chunks.forEach((chunk: RangeChunk) => { result.set(new Uint8Array(chunk.data), chunk.offset - this.start); });
    return result.buffer;
  }

  cancel(): void {
    this.finish(false);
  }

  private armDeadline(): void {
    if (this.deadline !== -1) clearTimeout(this.deadline);
    this.deadline = setTimeout(() => this.finish(false), 30000);
  }

  private notify(): void {
    this.waiters.forEach((resolve: () => void) => resolve());
    this.waiters.clear();
  }

  private finish(success: boolean): void {
    if (this.finished) return;
    this.profile?.end(success ? 0 : 1);
    this.finished = true;
    this.success = success;
    this.requestCancellations.forEach((cancel: () => void) => cancel());
    this.requestCancellations.clear();
    if (!success) this.chunks = [];
    if (this.deadline !== -1) clearTimeout(this.deadline);
    this.requests.forEach((request: http.HttpRequest) => {
      try { request.destroy(); } catch (_) { }
    });
    this.requests.clear();
    if (success) PlaybackStartup.trace('range-complete', this.startedAt);
    this.notify();
    this.resolveCompletion?.(success);
    this.resolveCompletion = null;
  }
}
