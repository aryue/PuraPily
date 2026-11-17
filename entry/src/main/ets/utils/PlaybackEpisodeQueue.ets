import type { SeasonEpisode, SeasonSection } from '../api/BilibiliApi';

export type PlaybackCompletionAction = 'sleep' | 'stop' | 'replay' | 'feed' | 'episode' | 'episodeWrap';

export function playbackCompletionAction(mode: string, stopAtEnd: boolean, feed: boolean,
  pgc: boolean): PlaybackCompletionAction {
  if (stopAtEnd) return 'sleep';
  if (mode === 'single') return 'stop';
  if (mode === 'loop') return 'replay';
  if (feed && !pgc) return 'feed';
  return mode === 'listLoop' ? 'episodeWrap' : 'episode';
}

export function neighboringSeasonEpisode(sections: SeasonSection[] | undefined, step: number,
  current: (episode: SeasonEpisode) => boolean): SeasonEpisode | null {
  if (!sections) return null;
  const episodes: SeasonEpisode[] = [];
  for (const section of sections) {
    for (const episode of section.episodes || []) episodes.push(episode);
  }
  const index = episodes.findIndex(current);
  return index < 0 ? null : episodes[index + step] ?? null;
}

export function firstSeasonEpisode(sections: SeasonSection[] | undefined): SeasonEpisode | null {
  if (!sections) return null;
  for (const section of sections) {
    if (section.episodes && section.episodes.length > 0) return section.episodes[0];
  }
  return null;
}

export interface PlaybackEpisodeTarget {
  partIndex: number;
  seasonEpisode: SeasonEpisode | null;
}

/** Playback order is parts first, then the containing season. */
export function nextPlaybackEpisode(partCount: number, partIndex: number, bvid: string, wrap: boolean,
  seasonNeighbor: (step: number) => SeasonEpisode | null,
  seasonFirst: () => SeasonEpisode | null): PlaybackEpisodeTarget | null {
  if (partCount > 1 && partIndex + 1 < partCount) {
    return { partIndex: partIndex + 1, seasonEpisode: null };
  }
  const next = seasonNeighbor(1);
  if (next) return { partIndex: -1, seasonEpisode: next };
  if (!wrap) return null;
  const first = seasonNeighbor(0) ? seasonFirst() : null;
  if (first?.bvid && first.bvid !== bvid) return { partIndex: -1, seasonEpisode: first };
  return partCount > 1 && partIndex !== 0 ? { partIndex: 0, seasonEpisode: null } : null;
}
