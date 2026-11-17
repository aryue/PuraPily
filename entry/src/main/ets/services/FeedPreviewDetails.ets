import { getVideoDetail, VideoDetail } from '../api/BilibiliApi';
import { logInfo, logWarn } from '../utils/Logger';

/** Detail cache shared by preview frames and the next feed switch. */
export class FeedPreviewDetails {
  private entries: Map<string, VideoDetail> = new Map();
  private pending: Map<string, Promise<VideoDetail | null>> = new Map();
  private closed: boolean = false;

  get(id: string): VideoDetail | undefined {
    return this.entries.get(id);
  }

  set(id: string, detail: VideoDetail): void {
    if (!this.closed) this.entries.set(id, detail);
  }

  delete(id: string): void {
    this.entries.delete(id);
  }

  close(): void {
    this.closed = true;
    this.entries.clear();
    this.pending.clear();
  }

  request(id: string, keep: (id: string) => boolean, ready: (detail: VideoDetail) => void): Promise<VideoDetail | null> {
    if (this.closed) return Promise.resolve(null);
    const cached = this.entries.get(id);
    if (cached) return Promise.resolve(cached);
    const running = this.pending.get(id);
    if (running) return running;
    const job = getVideoDetail(id).then((detail: VideoDetail | null) => {
      if (this.closed || !detail) return null;
      this.entries.set(id, detail);
      this.trim(id, keep);
      ready(detail);
      logInfo(`[ReferenceFeed] detail ready ${id} title=${detail.title} up=${detail.owner?.name}`);
      return detail;
    }).catch((error: Error) => {
      logWarn(`连续播放详情预热失败 ${id}: ${error?.message ?? error}`);
      return null;
    }).finally(() => { this.pending.delete(id); });
    this.pending.set(id, job);
    return job;
  }

  private trim(requested: string, keep: (id: string) => boolean): void {
    for (const id of this.entries.keys()) {
      if (this.entries.size <= 6) break;
      if (id !== requested && !keep(id)) this.entries.delete(id);
    }
  }
}
