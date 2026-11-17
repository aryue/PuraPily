import type { PgcEpisode, PgcSeasonInfo, VideoDetail, VideoPageItem } from '../api/BilibiliApi';
import { getPgcEpisodeInfo, getPgcSeasonInfoByEpId } from '../api/BilibiliApi';

export interface PgcEpisodeEntry {
  season: PgcSeasonInfo | null;
  episode: PgcEpisode | null;
  cid: number;
}

export async function resolvePgcEpisodeEntry(epId: number): Promise<PgcEpisodeEntry> {
  const fallback = getPgcEpisodeInfo(epId).catch(() => null);
  const season = await getPgcSeasonInfoByEpId(epId).catch(() => null);
  const episode = season?.episodes.find((item: PgcEpisode) => item.id === epId) ?? season?.episodes[0] ?? null;
  const seasonCid = episode?.cid || 0;
  const cid = seasonCid > 0 ? seasonCid : (await fallback)?.cid || 0;
  return { season, episode, cid };
}

interface PgcPlaybackRow {
  page: VideoPageItem;
  epId: number;
  aid: number;
  bvid: string;
}

/** Keeps each episode's page, playback, comments and subtitle identity together. */
export class PgcPlaybackEpisodes {
  private rows: PgcPlaybackRow[] = [];
  private season: PgcSeasonInfo | null = null;
  private seasonEpisode: number = 0;
  private seasonVersion: number = 0;
  private pending: Map<number, Promise<PgcSeasonInfo | null>> = new Map();

  rememberSeason(season: PgcSeasonInfo, epId: number): void {
    this.seasonVersion++;
    this.season = season;
    this.seasonEpisode = epId;
  }

  async seasonForEpisode(epId: number): Promise<PgcSeasonInfo | null> {
    if (this.season && (this.seasonEpisode === epId ||
      this.season.episodes.some((episode: PgcEpisode) => episode.id === epId))) return this.season;
    const running = this.pending.get(epId);
    if (running) return running;
    const version = ++this.seasonVersion;
    const request = getPgcSeasonInfoByEpId(epId).catch(() => null);
    this.pending.set(epId, request);
    try {
      const season = await request;
      if (season && version === this.seasonVersion) this.rememberSeason(season, epId);
      return season;
    } finally {
      this.pending.delete(epId);
    }
  }

  load(season: PgcSeasonInfo, episode: PgcEpisode, cid: number): VideoDetail {
    this.rows = season.episodes.map((item: PgcEpisode, index: number): PgcPlaybackRow => {
      const page: VideoPageItem = {
        cid: item.cid || 0,
        page: index + 1,
        part: item.long_title || item.title || `第${index + 1}话`,
        duration: item.duration ? Math.floor(item.duration / 1000) : 0,
        cover: item.cover || ''
      };
      return { page, epId: item.id || 0, aid: item.aid || 0, bvid: item.bvid || '' };
    });
    return {
      bvid: '', aid: episode.aid || this.aidAt(0), cid,
      title: season.title, desc: season.desc || `${season.actors || ''} ${season.staff || ''}`.trim(),
      pic: season.cover, ctime: season.pubdate, pubdate: season.pubdate, duration: 0,
      owner: {
        mid: season.upInfo.mid || 0,
        name: season.upInfo.uname || season.staff || season.actors || '',
        face: season.upInfo.avatar || ''
      },
      stat: {
        aid: 0, view: season.stat.view, danmaku: season.stat.danmaku, reply: season.stat.reply,
        favorite: season.stat.favorite, coin: season.stat.coin, share: 0, like: season.stat.like, dislike: 0
      },
      pages: this.rows.map((row: PgcPlaybackRow) => row.page)
    };
  }

  indexOf(epId: number): number {
    return this.rows.findIndex((row: PgcPlaybackRow) => row.epId === epId);
  }

  episodeAt(index: number): number {
    return this.rows[index]?.epId || 0;
  }

  aidAt(index: number): number {
    return this.rows[index]?.aid || 0;
  }

  bvidForCid(cid: number): string {
    return this.rows.find((row: PgcPlaybackRow) => row.page.cid === cid)?.bvid || '';
  }
}
