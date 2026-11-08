import type { PlayUrlResult } from '../api/BilibiliApi';

/** Keep the full quality catalogue; use a merged source only at the identical quality. */
export async function preferSameQualityMerged(base: PlayUrlResult,
  candidate: Promise<PlayUrlResult | null>, waitMs: number = 250): Promise<PlayUrlResult> {
  let timer: number = -1;
  try {
    const timeout = new Promise<null>((resolve) => { timer = setTimeout(() => resolve(null), waitMs); });
    const merged = await Promise.race([candidate, timeout]);
    if (!merged?.url || merged.audioUrl || merged.dash || merged.actualQn !== base.actualQn) return base;
    return { url: merged.url, actualQn: base.actualQn, audioUrl: undefined, dash: undefined,
      acceptQuality: base.acceptQuality?.slice(), acceptDescription: base.acceptDescription?.slice(),
      lastPlayTimeMs: base.lastPlayTimeMs, mediaUserAgent: merged.mediaUserAgent, mediaReferer: merged.mediaReferer };
  } catch (_) { return base; }
  finally { clearTimeout(timer); }
}
