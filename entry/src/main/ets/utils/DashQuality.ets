import type { DashVideoItem } from '../api/BilibiliApi';

/** Pick a decodable rendition at the selected quality, rather than the highest advertised track. */
export function selectDashVideo(list: DashVideoItem[], quality: number): DashVideoItem | null {
  if (!list || list.length === 0) return null;
  const nonAv1 = list.filter((item: DashVideoItem) => item.codecid !== 13);
  const usable = (nonAv1.length > 0 ? nonAv1 : list).slice()
    .sort((a: DashVideoItem, b: DashVideoItem) => b.id - a.id);
  if (quality <= 0) return usable[0];
  return usable.find((item: DashVideoItem) => item.id === quality) ||
    usable.find((item: DashVideoItem) => item.id < quality) || usable[usable.length - 1];
}
