/** Lower values are preferred. Keep unrecognized endpoints available for playback. */
export function playbackCdnRank(url: string): number {
  const authority = /^(?:https?:)?\/\/([^/?#]+)/i.exec(url);
  if (!authority) return 1;
  const host = authority[1].toLowerCase().replace(/:\d+$/, '').replace(/\.$/, '');
  const query = url.split('#')[0].split('?')[1] || '';
  if (/(^|&)os=mcdn(&|$)/i.test(query) ||
    /(^|\.)mcdn\.bilivideo\.(com|cn|net)$/.test(host) ||
    /(^|\.)(mountaintoys\.cn|szbdyd\.com|nexusedgeio\.com|ahdohpiechei\.com)$/.test(host) ||
    /^(?:302[^.]*|upos-sz-mirror14b)\.bilivideo\.(com|cn|net)$/.test(host) ||
    /(?:302ppio|302kodo)/.test(host)) {
    return 2;
  }
  if (/^(?:upos-|proxy-tf-|cn-|d\d+--cn-)[a-z0-9-]+\.(?:bilivideo\.(com|cn|net)|akamaized\.net)$/.test(host)) {
    return 0;
  }
  return 1;
}

export function preferredPlaybackUrl(urls: string[]): string {
  let preferred = '';
  let rank = 3;
  for (const url of urls) {
    if (!url) continue;
    const candidateRank = playbackCdnRank(url);
    if (candidateRank < rank) {
      preferred = url;
      rank = candidateRank;
    }
  }
  return preferred;
}

/** Sort only interchangeable URLs from the same rendition, leaving signed URLs intact. */
export function playbackCdnCandidates(primary: string, backups?: string[]): string[] {
  const candidates = [primary].concat(backups || []).filter((url: string, index: number, all: string[]) =>
    !!url && all.indexOf(url) === index);
  return candidates.sort((left: string, right: string) => playbackCdnRank(left) - playbackCdnRank(right));
}
