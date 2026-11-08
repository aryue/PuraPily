import { hilog } from '@kit.PerformanceAnalysisKit';
import type { http } from '@kit.NetworkKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PlaybackStartup';
const MAX_EVENTS: number = 400;
const MAX_MARKS: number = 16;
const NAV_GRACE_MS: number = 15000;

/** One startup event. offset = ms since the session start (the tap), value = ms since the caller's own baseline. */
class StartupEvent {
  at: number;
  offset: number;
  label: string;
  value: number;
  bytes: number;
  trace: boolean;

  constructor(at: number, offset: number, label: string, value: number, bytes: number, trace: boolean) {
    this.at = at;
    this.offset = offset;
    this.label = label;
    this.value = value;
    this.bytes = bytes;
    this.trace = trace;
  }
}

/**
 * A measured stage. Cheap: only pushes one event per mark/end.
 * Kept API-compatible with the previous stub so existing call sites stay valid.
 */
export class PlaybackSpan {
  readonly id: number;
  private label: string;
  private startedAt: number;
  private ended: boolean = false;
  private seenOnce: Set<string> = new Set<string>();

  constructor(id: number, label: string) {
    this.id = id;
    this.label = label;
    this.startedAt = Date.now();
  }

  mark(event: string, value: number = 0, bytes: number = 0): void {
    PlaybackStartup.record(event, value, bytes, false);
  }

  network(response: http.HttpResponse): void {
    const code: number = response.responseCode;
    PlaybackStartup.record(`net-${code}`, 0, 0, false);
  }

  once(event: string, value: number = 0, bytes: number = 0): void {
    if (this.seenOnce.has(event)) {
      return;
    }
    this.seenOnce.add(event);
    PlaybackStartup.record(event, value, bytes, false);
  }

  seen(event: string): boolean {
    return this.seenOnce.has(event);
  }

  end(value: number = 0): void {
    if (this.ended) {
      return;
    }
    this.ended = true;
    PlaybackStartup.record(`${this.label}:end`, Date.now() - this.startedAt, 0, false);
    if (value !== 0) {
      PlaybackStartup.record(`${this.label}:fail`, value, 0, false);
    }
  }
}

/**
 * Startup timeline for one playback entry: tap -> page -> player -> url -> bridge -> prepared -> first frame.
 * Every offset is relative to the tap, so `frame` is the number worth watching.
 */
export class PlaybackStartup {
  private static seq: number = 0;
  private static sessionStart: number = 0;
  private static navAt: number = 0;
  private static events: StartupEvent[] = [];
  private static repeats: Map<string, number> = new Map<string, number>();
  private static activeSpan: PlaybackSpan | null = null;
  private static path: string = 'cold';
  private static reported: boolean = false;
  private static lastReport: string = '';

  static navigation(): void {
    PlaybackStartup.navAt = Date.now();
  }

  static page(): PlaybackSpan {
    const now: number = Date.now();
    const fromTap: boolean = PlaybackStartup.navAt > 0 && now - PlaybackStartup.navAt <= NAV_GRACE_MS;
    PlaybackStartup.sessionStart = fromTap ? PlaybackStartup.navAt : now;
    PlaybackStartup.navAt = 0;
    PlaybackStartup.events = [];
    PlaybackStartup.repeats.clear();
    PlaybackStartup.seq = 0;
    PlaybackStartup.path = 'cold';
    PlaybackStartup.reported = false;
    PlaybackStartup.seq++;
    const span: PlaybackSpan = new PlaybackSpan(PlaybackStartup.seq, 'page');
    PlaybackStartup.activeSpan = span;
    PlaybackStartup.record('page-open', 0, 0, false);
    return span;
  }

  static current(): PlaybackSpan | null {
    return PlaybackStartup.activeSpan;
  }

  static begin(label: string): PlaybackSpan {
    PlaybackStartup.seq++;
    return new PlaybackSpan(PlaybackStartup.seq, label);
  }

  static span(label: string, parent?: PlaybackSpan | null): PlaybackSpan {
    PlaybackStartup.seq++;
    return new PlaybackSpan(PlaybackStartup.seq, label);
  }

  /** How this entry was served: 'prewarm' (adopted a warm bridge) or 'cold'. */
  static setPath(kind: string): void {
    PlaybackStartup.path = kind;
  }

  static trace(stage: string, startedAt: number): void {
    const now: number = Date.now();
    PlaybackStartup.record(stage, Math.max(0, now - startedAt), 0, true);
  }

  static finish(span: PlaybackSpan | null, event: string): void {
    PlaybackStartup.report(event);
  }

  static deactivate(span: PlaybackSpan | null): void {
    if (span !== null && PlaybackStartup.activeSpan === span) {
      PlaybackStartup.activeSpan = null;
    }
  }

  /** Logs the timeline once per entry. Safe to call repeatedly. */
  static report(reason: string): void {
    if (PlaybackStartup.reported || PlaybackStartup.events.length === 0) {
      return;
    }
    PlaybackStartup.reported = true;
    const traces: string[] = [];
    const marks: string[] = [];
    let total: number = 0;
    for (let i = 0; i < PlaybackStartup.events.length; i++) {
      const item: StartupEvent = PlaybackStartup.events[i];
      if (item.trace) {
        if (traces.length < 24) {
          traces.push(`${item.label}@${item.offset}`);
        }
        if (item.label === 'frame') {
          total = item.offset;
        }
      } else if (marks.length < MAX_MARKS && item.value !== 0) {
        marks.push(`${item.label}=${item.value}`);
      }
    }
    const head: string = `reason=${reason} path=${PlaybackStartup.path} frame=${total}ms`;
    PlaybackStartup.lastReport = `${head} | ${traces.join(' ')}`;
    hilog.info(DOMAIN, TAG, '%{public}s', `[Startup] ${PlaybackStartup.lastReport}`);
    if (marks.length > 0) {
      hilog.info(DOMAIN, TAG, '%{public}s', `[Startup] marks ${marks.join(' ')}`);
    }
  }

  static summary(): string {
    return PlaybackStartup.lastReport;
  }

  /** Internal: single event sink shared by spans and traces. */
  static record(label: string, value: number, bytes: number, trace: boolean): void {
    if (PlaybackStartup.events.length >= MAX_EVENTS) {
      return;
    }
    // 分段级事件每秒几十条，只保留计数，别把时间轴刷掉。
    if (label.startsWith('range-')) {
      return;
    }
    const seen: number = PlaybackStartup.repeats.get(label) ?? 0;
    if (seen >= 3) {
      return;
    }
    PlaybackStartup.repeats.set(label, seen + 1);
    const now: number = Date.now();
    const base: number = PlaybackStartup.sessionStart > 0 ? PlaybackStartup.sessionStart : now;
    PlaybackStartup.events.push(new StartupEvent(now, now - base, label, value, bytes, trace));
  }
}
