import { image } from '@kit.ImageKit';
/** Geometry shared by the outgoing live surface and the floating host. All values are vp. */
export interface FloatingVideoRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class FloatingVideoTransition {
  static readonly DURATION: number = 320;
  static direction: string = '';
  static generation: number = 0;
  static restoreExpanded: boolean = false;
  static pausedFrame: image.PixelMap | undefined = undefined;
  static mini: FloatingVideoRect | undefined = undefined;
  static source: FloatingVideoRect | undefined = undefined;

  static clearPausedFrame(): void {
    const frame = FloatingVideoTransition.pausedFrame;
    FloatingVideoTransition.pausedFrame = undefined;
    if (frame) frame.release().catch(() => {});
  }

  static active(): boolean { return FloatingVideoTransition.direction !== ''; }

  static remember(rect: FloatingVideoRect): void {
    FloatingVideoTransition.mini = rect;
  }

  static begin(direction: string): void {
    FloatingVideoTransition.direction = direction;
    FloatingVideoTransition.generation++;
    AppStorage.setOrCreate('floatingMorphBusy', true);
  }

  static finish(): void {
    FloatingVideoTransition.direction = '';
    AppStorage.setOrCreate('floatingMorphBusy', false);
  }
}
