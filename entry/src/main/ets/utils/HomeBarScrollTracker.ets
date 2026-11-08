/** Only user scrolling may change the shared home header/bottom-bar visibility. */
export class HomeBarScrollTracker {
  private distance: number = 0;
  private readonly threshold: number;

  constructor(threshold: number = 10) {
    this.threshold = threshold;
  }

  update(offset: number, source: ScrollSource): boolean | undefined {
    const userScroll = source === ScrollSource.DRAG || source === ScrollSource.FLING ||
      source === ScrollSource.OTHER_USER_INPUT || source === ScrollSource.SCROLL_BAR ||
      source === ScrollSource.SCROLL_BAR_FLING;
    if (!userScroll) {
      // Appending cards, restoring a position and edge rebound must preserve visibility.
      this.distance = 0;
      return undefined;
    }
    if (offset === 0) return undefined;
    if (this.distance * offset < 0) this.distance = 0;
    this.distance += offset;
    if (Math.abs(this.distance) < this.threshold) return undefined;
    const hidden = this.distance > 0;
    this.distance = 0;
    return hidden;
  }
}
