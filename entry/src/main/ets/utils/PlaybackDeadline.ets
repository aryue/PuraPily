/** One budget for the entire startup, including native promises that may never settle. */
export class PlaybackDeadline {
  private readonly expiresAt: number;
  private cancelled: boolean = false;
  private cancellations: Set<() => void> = new Set();

  constructor(budgetMs: number = 15000) {
    this.expiresAt = Date.now() + budgetMs;
  }

  async wait<T>(task: Promise<T>, stage: string): Promise<T> {
    let timer: number = -1;
    let cancel: () => void = () => {};
    const timeout = new Promise<T>((_resolve, reject) => {
      cancel = () => reject(new Error('播放准备已取消'));
      if (this.cancelled) { cancel(); return; }
      this.cancellations.add(cancel);
      timer = setTimeout(() => reject(new Error(`${stage}超时，请重试`)), Math.max(0, this.expiresAt - Date.now()));
    });
    try {
      return await Promise.race([task, timeout]);
    } finally {
      clearTimeout(timer);
      this.cancellations.delete(cancel);
    }
  }

  cancel(): void {
    this.cancelled = true;
    this.cancellations.forEach((cancel: () => void) => cancel());
    this.cancellations.clear();
  }

  isCancelled(): boolean { return this.cancelled; }
  isExpired(): boolean { return Date.now() >= this.expiresAt; }
}
