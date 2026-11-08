/** Explicit, versioned continuation data. Never serialize router stacks, cookies or stream URLs. */
export const CONTINUATION_KEY: string = 'pura.continuation';
export const CONTINUATION_MIN_VERSION: number = 1000021;

export interface ContinuationPage {
  page: string;
  params: Record<string, Object>;
}

export interface ContinuationSnapshot {
  schema: number;
  tab: number;
  channel: number;
  destination: ContinuationPage;
}

export class AppContinuation {
  private static owner: Object | null = null;
  private static page: string = '';
  private static capture: (() => ContinuationPage | null) | null = null;

  static register(owner: Object, page: string, capture: () => ContinuationPage | null): void {
    AppContinuation.owner = owner;
    AppContinuation.page = page;
    AppContinuation.capture = capture;
  }

  static unregister(owner: Object): void {
    if (AppContinuation.owner !== owner) return;
    AppContinuation.owner = null;
    AppContinuation.capture = null;
    AppContinuation.page = '';
  }

  static normalizePage(path: string): string {
    return path.replace(/^\//, '').replace(/\.(ets|js|ts)$/, '');
  }

  static isPlaybackPage(path: string): boolean {
    const page = AppContinuation.normalizePage(path);
    return page === 'pages/VideoPlayerPage' || page === 'pages/LivePlayerPage';
  }

  static snapshot(path: string, _params: Record<string, Object>): ContinuationSnapshot | null {
    const page = AppContinuation.normalizePage(path);
    if (!AppContinuation.isPlaybackPage(page)) return null;
    let destination: ContinuationPage | null = null;
    if (AppContinuation.capture && page === AppContinuation.page) {
      destination = AppContinuation.capture();
    }
    if (!destination) return null;
    return AppContinuation.fromPage(destination);
  }

  static fromPage(destination: ContinuationPage): ContinuationSnapshot | null {
    return AppContinuation.decode(JSON.stringify({
      schema: 1,
      tab: AppStorage.get<number>('continuationMainTab') ?? 0,
      channel: AppStorage.get<number>('homeChannelIndex') ?? 2,
      destination: destination
    } as ContinuationSnapshot));
  }

  /** Treat transferred data as untrusted; copy only known primitive fields. */
  static decode(raw: Object | undefined): ContinuationSnapshot | null {
    if (typeof raw !== 'string' || raw.length > 16384) return null;
    try {
      const input = JSON.parse(raw) as ContinuationSnapshot;
      if (!input || input.schema !== 1 || !input.destination) return null;
      const page = input.destination.page;
      let keys: string[] = [];
      if (page === 'pages/VideoPlayerPage') {
        keys = ['bvid', 'aid', 'cid', 'epId', 'seasonId', 'title', 'initialProgress', 'continuationPaused', 'continuationRate'];
      } else if (page === 'pages/LivePlayerPage') {
        keys = ['roomId', 'areaId'];
      } else {
        return null;
      }
      const source = input.destination.params;
      if (!source || typeof source !== 'object' || Array.isArray(source)) return null;
      const params: Record<string, Object> = {};
      for (const key of keys) {
        const value = source[key];
        if (typeof value === 'string' && value.length <= 512) params[key] = value;
        if (typeof value === 'number' && Number.isFinite(value) && value >= 0) params[key] = value;
        if (typeof value === 'boolean') params[key] = value;
      }
      if (page === 'pages/VideoPlayerPage') {
        const bvid = params['bvid'];
        if (!(typeof bvid === 'string' && /^(BV[0-9A-Za-z]+|[0-9]+)$/.test(bvid)) &&
          !AppContinuation.positiveId(params['aid']) && !AppContinuation.positiveId(params['epId'])) return null;
        if (typeof params['initialProgress'] !== 'number') params['initialProgress'] = 0;
        const rate = params['continuationRate'];
        if (typeof rate !== 'number' || ![0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3].includes(rate)) {
          params['continuationRate'] = 1;
        }
      }
      if (page === 'pages/LivePlayerPage' && !AppContinuation.positiveId(params['roomId'])) return null;
      return {
        schema: 1,
        tab: Number.isInteger(input.tab) && input.tab >= 0 && input.tab <= 2 ? input.tab : 0,
        channel: Number.isInteger(input.channel) && input.channel >= 0 && input.channel <= 5 ? input.channel : 2,
        destination: { page: page, params: params }
      };
    } catch (_error) {
      return null;
    }
  }

  private static positiveId(value: Object | undefined): boolean {
    return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
  }
}
