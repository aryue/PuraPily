export interface PressHost {
  schedule: (callback: () => void, delay: number) => number;
  cancel: (id: number) => void;
  outerChanged: (pressed: boolean) => void;
  contactChanged: (pressed: boolean) => void;
  innerChanged: (chosen: boolean) => void;
}

// Original Touch and Pan lifecycles are independent. Touch enlarges the shell;
// recognized Pan restores it and starts the cancellable 100ms fill selection.
export class PressController {
  private downState: boolean = false;
  private dragging: boolean = false;
  private selected: boolean = false;
  private chooseTask: number = -1;
  private releaseTask: number = -1;
  private generation: number = 0;
  private host: PressHost;

  constructor(host: PressHost) { this.host = host; }

  down(): void {
    if (this.downState) { return; }
    if (this.releaseTask !== -1) { this.host.cancel(this.releaseTask); this.releaseTask = -1; }
    this.downState = true;
    this.host.contactChanged(true);
    this.host.outerChanged(true);
  }

  startDragging(): void {
    if (this.dragging) { return; }
    this.dragging = true;
    this.host.outerChanged(false);
    const generation: number = ++this.generation;
    this.chooseTask = this.host.schedule(() => {
      if (generation !== this.generation || !this.dragging) { return; }
      this.chooseTask = -1;
      this.selected = true;
      this.host.innerChanged(true);
    }, 100);
  }

  endDragging(): void {
    this.dragging = false;
    this.generation++;
    if (this.chooseTask !== -1) { this.host.cancel(this.chooseTask); this.chooseTask = -1; }
    if (this.selected) { this.selected = false; this.host.innerChanged(false); }
  }

  up(): void {
    if (!this.downState) { return; }
    this.downState = false;
    this.releaseTask = this.host.schedule(() => {
      this.releaseTask = -1;
      if (!this.downState) {
        this.host.outerChanged(false);
        this.host.contactChanged(false);
      }
    }, 100);
  }

  dispose(): void {
    this.endDragging();
    if (this.releaseTask !== -1) { this.host.cancel(this.releaseTask); this.releaseTask = -1; }
    this.downState = false;
  }
}
