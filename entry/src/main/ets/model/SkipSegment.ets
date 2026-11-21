/**
 * 空降助手数据模型。
 *
 * 两类来源共用同一份结构：
 * - SponsorBlock 社区片段：秒 → 毫秒，category 为英文分类名；
 * - 番剧 playurl 的 clip_info_list：CLIP_TYPE_OP/ED → intro/outro。
 *
 * 零长度片段（startMs === endMs）是时间点标记（例如「精彩时刻」），
 * 只画进度条刻度、不自动跳过。
 */

export enum SkipMode {
  Always = 'alwaysSkip',
  Once = 'skipOnce',
  Manual = 'skipManual',
  Show = 'showOnly',
  Disable = 'disable'
}

export class SkipModeOption {
  readonly mode: SkipMode;
  readonly label: string;

  constructor(mode: SkipMode, label: string) {
    this.mode = mode;
    this.label = label;
  }
}

export const SKIP_MODE_OPTIONS: SkipModeOption[] = [
  new SkipModeOption(SkipMode.Always, '总是跳过'),
  new SkipModeOption(SkipMode.Once, '跳过一次'),
  new SkipModeOption(SkipMode.Manual, '手动跳过'),
  new SkipModeOption(SkipMode.Show, '仅显示'),
  new SkipModeOption(SkipMode.Disable, '禁用')
];

export class SkipCategoryMeta {
  readonly key: string;
  readonly title: string;
  readonly shortTitle: string;
  readonly color: string;

  constructor(key: string, title: string, shortTitle: string, color: string) {
    this.key = key;
    this.title = title;
    this.shortTitle = shortTitle;
    this.color = color;
  }
}

/** 顺序与 SponsorBlock 设置位（sponsorBlockModes）逐位对应，新增分类只能追加。 */
export const SKIP_CATEGORIES: SkipCategoryMeta[] = [
  new SkipCategoryMeta('sponsor', '赞助/恰饭', '赞助', '#00D400'),
  new SkipCategoryMeta('selfpromo', '无偿/自我推广', '推广', '#FFFF00'),
  new SkipCategoryMeta('exclusive_access', '独家访问/抢先体验', '品牌合作', '#008A5C'),
  new SkipCategoryMeta('interaction', '三连/互动提醒', '三连提醒', '#CC00FF'),
  new SkipCategoryMeta('poi_highlight', '精彩时刻/重点', '精彩时刻', '#FF1684'),
  new SkipCategoryMeta('intro', '过场/开场动画', '开场动画', '#00FFFF'),
  new SkipCategoryMeta('outro', '鸣谢/结束画面', '片尾', '#0202ED'),
  new SkipCategoryMeta('preview', '回顾/概要', '预览', '#008FD6'),
  new SkipCategoryMeta('padding', '填充内容/前黑/后黑', '填充内容', '#222222'),
  new SkipCategoryMeta('filler', '离题闲聊/玩笑', '离题', '#7300FF'),
  new SkipCategoryMeta('music_offtopic', '音乐:非音乐部分', '非音乐', '#FF9900'),
  new SkipCategoryMeta('jumpscare', '惊吓片段', '惊吓', '#E53935')
];

export function skipCategoryIndex(key: string): number {
  for (let i = 0; i < SKIP_CATEGORIES.length; i++) {
    if (SKIP_CATEGORIES[i].key === key) return i;
  }
  return -1;
}

export function skipCategoryMeta(key: string): SkipCategoryMeta {
  const index = skipCategoryIndex(key);
  return index >= 0 ? SKIP_CATEGORIES[index] : SKIP_CATEGORIES[0];
}

export class SkipSegment {
  startMs: number;
  endMs: number;
  category: string;
  mode: SkipMode;
  uuid: string;
  official: boolean;
  /** 本次播放是否已自动跳过 / 已弹出手动提示；离开片段后手动类型会复位。 */
  skipped: boolean = false;

  constructor(startMs: number, endMs: number, category: string, mode: SkipMode,
    uuid: string = '', official: boolean = false) {
    this.startMs = startMs;
    this.endMs = endMs;
    this.category = category;
    this.mode = mode;
    this.uuid = uuid;
    this.official = official;
  }

  get isPoint(): boolean {
    return this.startMs === this.endMs;
  }

  get durationMs(): number {
    return Math.max(0, this.endMs - this.startMs);
  }
}

export class SkipMark {
  readonly startRatio: number;
  readonly endRatio: number;
  readonly color: string;

  constructor(startRatio: number, endRatio: number, color: string) {
    this.startRatio = startRatio;
    this.endRatio = endRatio;
    this.color = color;
  }
}

/** 番剧 playurl 的 clip_info_list 子项（start/end 单位秒）。 */
export interface ClipInfoItem {
  start?: number;
  end?: number;
  clipType?: string;
}

/** SponsorBlock /api/skipSegments 返回子项（segment/videoDuration 单位秒）。 */
export interface SponsorBlockItem {
  cid?: string;
  category?: string;
  actionType?: string;
  segment?: number[];
  UUID?: string;
  videoDuration?: number;
  votes?: number;
}
