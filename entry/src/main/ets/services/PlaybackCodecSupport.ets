import nativeMedia from 'libhigh_refresh.so';
import type { PlayUrlResult, DashVideoItem } from '../api/BilibiliApi';
import { selectDashVideo } from '../utils/DashQuality';

function hasDecoder(video: DashVideoItem): boolean {
  let mime = '';
  if (video.codecid === 7) mime = 'video/avc';
  if (video.codecid === 12) mime = 'video/hevc';
  if (video.codecid === 13) mime = 'video/av01';
  return !mime || nativeMedia.hasVideoDecoder(mime);
}

/** Keep the current player intact when the requested rendition has no system decoder. */
export function canDecodePlayUrl(result: PlayUrlResult): boolean {
  if (!result.dash) return true;
  const video = selectDashVideo(result.dash.videoStreams, result.actualQn || result.dash.quality);
  return !video || hasDecoder(video);
}

/** A saved default from another device must not make initial playback fail. Do not mutate cached sources. */
export function selectDecodablePlayUrl(result: PlayUrlResult): PlayUrlResult {
  if (!result.dash || canDecodePlayUrl(result)) return result;
  const video = selectDashVideo(result.dash.videoStreams.filter((item: DashVideoItem) => hasDecoder(item)),
    result.actualQn || result.dash.quality);
  if (!video) return result;
  return { url: video.baseUrl, audioUrl: result.audioUrl, actualQn: video.id,
    mediaUserAgent: result.mediaUserAgent,
    mediaReferer: result.mediaReferer,
    acceptQuality: result.acceptQuality, acceptDescription: result.acceptDescription,
    lastPlayTimeMs: result.lastPlayTimeMs,
    dash: { videoStreams: result.dash.videoStreams, audioStreams: result.dash.audioStreams,
      timelength: result.dash.timelength, quality: video.id } };
}
