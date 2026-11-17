import type { PlayUrlResult } from '../api/BilibiliApi';

/**
 * 画质档位表（qn ↔ 文案）。
 *
 * 设置页的两套画质偏好（Wi-Fi / 移动网络）、播放页清晰度弹窗和缓存键都按同一份 qn 取流，
 * 档位表放这里，避免「设置页多了 1080P+、播放页没有」这种漂移。
 */
export interface QualityOption {
  qn: number;
  label: string;
}

export const QUALITY_OPTIONS: QualityOption[] = [
  { qn: 16, label: '360P' },
  { qn: 32, label: '480P' },
  { qn: 64, label: '720P' },
  { qn: 80, label: '1080P' },
  { qn: 112, label: '1080P+' },
  { qn: 116, label: '1080P60' },
  { qn: 120, label: '4K' }
];

export function playbackQualityOptions(result: PlayUrlResult): QualityOption[] {
  const qualities = result.acceptQuality || [];
  const descriptions = result.acceptDescription || [];
  const options: QualityOption[] = [];
  for (let i = 0; i < qualities.length; i++) {
    const qn = qualities[i];
    if (qn <= 0 || options.some((item: QualityOption) => item.qn === qn)) continue;
    const known = QUALITY_OPTIONS.find((item: QualityOption) => item.qn === qn);
    options.push({ qn, label: descriptions[i] || known?.label || `${qn}` });
  }
  // Without an advertised catalogue, the returned stream is the only known option.
  if (options.length === 0 && result.url && result.actualQn && result.actualQn > 0) {
    const qn = result.actualQn;
    const known = QUALITY_OPTIONS.find((item: QualityOption) => item.qn === qn);
    options.push({ qn, label: known?.label || `${qn}` });
  }
  return options;
}

/** Wi-Fi 档默认 1080P60：与设置页历史上的默认值保持一致。 */
export const DEFAULT_QUALITY_QN: number = 116;
/** 移动网络/热点档默认 720P：计费链路上先控流量，用户可在设置页改。 */
export const DEFAULT_CELLULAR_QUALITY_QN: number = 64;

const FALLBACK_LABEL: string = '1080P60';

export function qualityLabel(qn: number): string {
  const hit = QUALITY_OPTIONS.find((item: QualityOption) => item.qn === qn);
  return hit ? hit.label : FALLBACK_LABEL;
}

/** 偏好文件里的值可能是旧版本/手改的脏值，只有表内档位才认。 */
export function isKnownQuality(qn: number): boolean {
  return QUALITY_OPTIONS.some((item: QualityOption) => item.qn === qn);
}
