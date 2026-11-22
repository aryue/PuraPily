import { FrameCallback } from '@ohos.arkui.UIContext';

export class PlaybackViewportFrameCallback extends FrameCallback {
  private callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onFrame(_frameTimeInNano: number): void {
    this.callback();
  }

  onIdle(_timeLeftInNano: number): void {}
}
