import {
  SkipMode,
  SkipSegment,
  skipCategoryMeta
} from '../model/SkipSegment';
import { SponsorBlockPrefs } from '../utils/SponsorBlockPrefs';

export interface SkipCallbacks {
  seek: (positionMs: number) => void;
  toast: (message: string) => void;
  prompt: (segment: SkipSegment) => void;
}

/**
 * 空降片段执行器。
 *
 * 与 PiliNara 的行为对齐：
 * - 默认只在刚进入片段的前 1 秒内自动触发，避免用户主动拖进中间被弹走；
 * - 「快进至片段中间时跳过」打开后，任意位置进入都处理；
 * - 跳过后 ignoreUntil 略微越过片段终点，防止关键帧回退导致反复 seek。
 */
export class SkipSegmentEngine {
  private official: SkipSegment[] = [];
  private remote: SkipSegment[] = [];
  private segments: SkipSegment[] = [];
  private lastCheckMs: number = -1;
  private ignoreUntilMs: number = -1;
  private promptedKey: string = '';

  reset(): void {
    this.official = [];
    this.remote = [];
    this.segments = [];
    this.lastCheckMs = -1;
    this.ignoreUntilMs = -1;
    this.promptedKey = '';
  }

  setOfficial(list: SkipSegment[]): void {
    this.official = list;
    this.rebuild();
  }

  setRemote(list: SkipSegment[]): void {
    this.remote = list;
    this.rebuild();
  }

  get count(): number {
    return this.segments.length;
  }

  /** 进度条原始标记（毫秒 + 颜色），比例交给持有真实 duration 的控件计算。 */
  rawMarks(): string {
    return this.segments.map((segment: SkipSegment): string =>
      `${segment.startMs},${segment.endMs},${skipCategoryMeta(segment.category).color}`).join(';');
  }

  onPosition(positionMs: number, callbacks: SkipCallbacks): void {
    if (!(positionMs >= 0) || this.segments.length === 0) return;
    if (this.lastCheckMs >= 0 && positionMs >= this.lastCheckMs &&
      positionMs - this.lastCheckMs < 100) {
      return;
    }
    this.lastCheckMs = positionMs;
    if (positionMs < this.ignoreUntilMs) return;

    const seekInto = SponsorBlockPrefs.seekIntoEnabled();
    for (const segment of this.segments) {
      const inside = segment.startMs <= positionMs && positionMs < segment.endMs;
      if (!inside) {
        if (segment.mode === SkipMode.Manual && segment.skipped) segment.skipped = false;
        continue;
      }
      // 点标记（start === end）没有可跳转区间，只用于进度条刻度。
      if (segment.isPoint) continue;
      // 进入片段超过 1 秒视为用户主动拖动，默认不自动跳。
      // 例外：开播前 5 秒才拿到片段数据（社区源 RTT 2~3s）时，起点为 0 的片头
      // 仍按「刚进入」处理，否则起播必然错过 1 秒窗口。
      const startupCatchUp = segment.startMs === 0 && positionMs <= 5000;
      if (!seekInto && !startupCatchUp && positionMs - segment.startMs >= 1000) continue;
      switch (segment.mode) {
        case SkipMode.Always:
          this.skip(segment, callbacks);
          return;
        case SkipMode.Once:
          if (!segment.skipped) this.skip(segment, callbacks);
          return;
        case SkipMode.Manual:
          if (!segment.skipped) {
            segment.skipped = true;
            const key = `${segment.category}:${segment.startMs}:${segment.endMs}`;
            if (this.promptedKey !== key) {
              this.promptedKey = key;
              callbacks.prompt(segment);
            }
          }
          return;
        default:
          return;
      }
    }
  }

  skip(segment: SkipSegment, callbacks: SkipCallbacks): void {
    if (segment.mode !== SkipMode.Always) segment.skipped = true;
    this.ignoreUntilMs = Math.max(this.ignoreUntilMs, segment.endMs + 350);
    this.promptedKey = '';
    callbacks.seek(segment.endMs);
    if (SponsorBlockPrefs.toastEnabled()) {
      const label = skipCategoryMeta(segment.category).shortTitle;
      callbacks.toast(segment.isPoint ? `已跳至${label}` : `已跳过${label}片段`);
    }
  }

  private rebuild(): void {
    const merged: SkipSegment[] = [];
    for (const item of this.official) merged.push(item);
    for (const item of this.remote) {
      let duplicated = false;
      for (const official of this.official) {
        if (official.category === item.category && official.startMs === item.startMs &&
          official.endMs === item.endMs) {
          duplicated = true;
          break;
        }
      }
      if (!duplicated) merged.push(item);
    }
    merged.sort((a: SkipSegment, b: SkipSegment): number => {
      if (a.startMs !== b.startMs) return a.startMs - b.startMs;
      return a.endMs - b.endMs;
    });
    this.segments = merged;
    this.lastCheckMs = -1;
    this.ignoreUntilMs = -1;
    this.promptedKey = '';
  }
}
