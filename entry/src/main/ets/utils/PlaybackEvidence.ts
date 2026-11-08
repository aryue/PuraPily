import { fileIo } from '@kit.CoreFileKit';
import { redactPrivateLog } from './PrivacyLog';

interface EvidenceLine { at: number; text: string; }
interface PlaybackFault {
  version: number;
  at: number;
  root: number;
  reason: string;
  scope: string;
  complete: boolean;
  records: EvidenceLine[];
}

const MAX_CHARS = 192 * 1024;
const MAX_RECORDS = 1500;
let ring: EvidenceLine[] = [];
let ringChars = 0;
let faults: PlaybackFault[] = [];
let active: PlaybackFault | null = null;
let activeChars = 0;
let timer: number = -1;
let path = '';
let ready: Promise<void> = Promise.resolve();
let writes: Promise<void> = Promise.resolve();
let revision = 0;
let savedChars = 0;
let lastFaultAt = -60000;

/** Memory only during normal playback. No IDs, URLs, cookies or media payloads. */
export function recordPlaybackEvidence(text: string, at: number): void {
  const line: EvidenceLine = { at, text: redactPrivateLog(text).slice(0, 2048) };
  ring.push(line);
  ringChars += line.text.length;
  while (ring.length > MAX_RECORDS || ringChars > MAX_CHARS || (ring.length > 0 && at - ring[0].at > 45000)) {
    ringChars -= ring.shift()!.text.length;
  }
  if (active && at - active.at <= 10000) {
    active.records.push(line);
    activeChars += line.text.length;
    // Preserve the pre-fault window; discard excess post-fault traffic.
    if (active.records.length > MAX_RECORDS || activeChars > MAX_CHARS) {
      active.records.pop();
      activeChars -= line.text.length;
    }
  }
}

/** Save immediately, then seal after ten seconds. A global cooldown bounds failures. */
export function triggerPlaybackEvidence(root: number, reason: string): void {
  const now = Date.now();
  if (active || now - lastFaultAt < 30000) return;
  lastFaultAt = now;
  active = { version: 1, at: now, root, reason, complete: false,
    scope: 'app-events-and-public-AVPlayer-statistics; system-service-logs-not-available',
    records: ring.slice(-1000) };
  activeChars = active.records.reduce((sum: number, line: EvidenceLine) => sum + line.text.length, 0);
  faults.push(active);
  faults = faults.slice(-3);
  persist();
  clearTimeout(timer);
  timer = setTimeout(() => { sealPlaybackEvidence(); }, 10000);
}

export function sealPlaybackEvidence(): void {
  if (!active) return;
  active.complete = true;
  active = null;
  clearTimeout(timer);
  timer = -1;
  persist();
}

/** Restore previous faults before any new write, including faults captured during startup. */
export function setPlaybackEvidenceDirectory(filesDir: string): void {
  const next = filesDir + '/playback_faults.json';
  if (path === next) return;
  path = next;
  const epoch = revision;
  ready = (async () => {
    try {
      const stat = await fileIo.stat(next);
      if (stat.size > 2 * 1024 * 1024) return;
      const text = await fileIo.readText(next);
      const previous = JSON.parse(text) as PlaybackFault[];
      if (epoch !== revision || path !== next || !Array.isArray(previous)) return;
      faults = previous.filter((fault: PlaybackFault) => fault.version === 1 && Array.isArray(fault.records))
        .concat(faults).slice(-3);
      savedChars = text.length;
    } catch (_) { }
  })();
}

function persist(): void {
  const epoch = revision;
  const target = path;
  if (!target) return;
  writes = writes.then(async () => {
    await ready;
    if (epoch !== revision || target !== path) return;
    const text = redactPrivateLog(JSON.stringify(faults));
    const temporary = target + '.tmp';
    const file = await fileIo.open(temporary, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    try { await fileIo.write(file.fd, text); }
    finally { await fileIo.close(file); }
    // Publish a complete snapshot; an interrupted write leaves the previous packet intact.
    await fileIo.rename(temporary, target);
    savedChars = text.length;
  }).catch(() => { /* Keep the in-memory packet available for export on I/O failure. */ });
}

export async function playbackEvidenceReady(): Promise<void> { await ready; }

export function getPlaybackEvidenceSize(): number {
  return Math.max(savedChars, faults.reduce((sum: number, fault: PlaybackFault) =>
    sum + fault.records.reduce((n: number, line: EvidenceLine) => n + line.text.length, 256), 0));
}

export async function readPlaybackEvidence(): Promise<string> {
  await ready;
  // Include the live post-fault tail without waiting ten seconds for an export.
  if (active) persist();
  await writes;
  return faults.length > 0 ? '\n=== 自动播放故障取证（最近三次；不含系统服务内部日志） ===\n' +
    redactPrivateLog(JSON.stringify(faults, null, 2)) + '\n' : '';
}

export function clearPlaybackEvidence(): void {
  revision++;
  ring = [];
  ringChars = 0;
  faults = [];
  active = null;
  savedChars = 0;
  lastFaultAt = -60000;
  clearTimeout(timer);
  const target = path;
  writes = writes.then(async () => {
    await ready;
    if (target) {
      try { await fileIo.unlink(target); } catch (_) { }
      try { await fileIo.unlink(target + '.tmp'); } catch (_) { }
    }
  });
}
