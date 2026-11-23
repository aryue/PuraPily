import { UIContext } from '@kit.ArkUI';
import { PlaybackViewportFrameCallback } from '../utils/PlaybackViewportFrameCallback';
import { GenericDataSource } from './GenericDataSource';

/** Let a cold List build a few real items per frame, with the whole response retained for data operations. */
export class FirstScreenDataSource<T> extends GenericDataSource<T> {
  private limit: number = -1;
  private revision: number = 0;

  totalCount(): number {
    const count = super.totalCount();
    return this.isPublishing() ? Math.min(count, this.limit) : count;
  }

  isPublishing(): boolean {
    return this.limit >= 0;
  }

  reloadItems(items: T[]): void {
    this.revision++;
    this.limit = -1;
    super.reloadItems(items);
  }

  replaceForViewport(items: T[], batchSize: number, ui: UIContext): void {
    if (this.totalCount() > 0 || items.length <= batchSize) {
      this.reloadItems(items);
      return;
    }

    const revision = ++this.revision;
    this.limit = batchSize;
    super.reloadItems(items);
    const frame: PlaybackViewportFrameCallback = new PlaybackViewportFrameCallback(() => {
      if (revision !== this.revision) return;
      this.limit += batchSize;
      if (this.limit >= super.totalCount()) this.limit = -1;
      this.notifyDataReload();
      if (revision === this.revision && this.isPublishing()) ui.postFrameCallback(frame);
    });
    // Allow the synchronous first batch to reach layout before publishing the next one.
    ui.postFrameCallback(new PlaybackViewportFrameCallback(() => {
      if (revision === this.revision) ui.postFrameCallback(frame);
    }));
  }

  notifyDataDelete(index: number): void {
    if (!this.isPublishing()) {
      super.notifyDataDelete(index);
    } else if (index < this.limit) {
      // Deleting from the visible prefix can bring a previously hidden item into it.
      this.notifyDataReload();
    }
  }
}
