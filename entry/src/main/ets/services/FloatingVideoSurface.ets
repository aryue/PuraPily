import { UIContext, ComponentContent } from '@kit.ArkUI';
import { media } from '@kit.MediaKit';
import { PlayerService } from './PlayerService';
import { FloatingVideoRect } from './FloatingVideoTransition';
import { logInfo, logWarn } from '../utils/Logger';

class SurfaceParams {
  rect: FloatingVideoRect;
  visible: boolean;
  constructor(rect: FloatingVideoRect, visible: boolean) { this.rect = rect; this.visible = visible; }
}

@Component
struct SystemVideoSource {
  @Prop rect: FloatingVideoRect = { x: 0, y: 0, width: 1, height: 1 };
  @Prop visible: boolean = true;
  build() {
    Stack() {
      XComponent({ id: 'system_pip_source', type: XComponentType.SURFACE, controller: FloatingVideoSurface.controller })
        .id('system-pip-source-anchor')
        .width(this.rect.width).height(this.rect.height)
        .position({ x: this.visible ? this.rect.x : -10000, y: this.rect.y })
        .onLoad(() => FloatingVideoSurface.loaded())
        .onDestroy(() => FloatingVideoSurface.unloaded())
        .hitTestBehavior(HitTestMode.None)
    }.width('100%').height('100%').expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .focusable(false).hitTestBehavior(HitTestMode.Transparent)
  }
}

@Builder
function buildSource(params: SurfaceParams) {
  SystemVideoSource({ rect: params.rect, visible: params.visible })
}

/** A full-video source anchor above Router pages; only the system owns the small window. */
export class FloatingVideoSurface {
  static controller: XComponentController = new XComponentController();
  private static context_: UIContext | null = null;
  private static content_: ComponentContent<SurfaceParams> | null = null;
  private static loaded_: boolean = false;
  private static desired_: FloatingVideoRect = { x: 0, y: 0, width: 1, height: 1 };
  private static rect_: FloatingVideoRect = { x: 0, y: 0, width: 1, height: 1 };

  static loaded(): void { FloatingVideoSurface.loaded_ = true; FloatingVideoSurface.bindPlayer(); }
  static unloaded(): void { FloatingVideoSurface.loaded_ = false; }

  static prepare(context: UIContext, rect: FloatingVideoRect): void {
    // Keep the measured overlay-origin correction when restoring the same source.
    // The system can locate it immediately after ABOUT_TO_RESTORE, before our next layout check.
    const offsetX = FloatingVideoSurface.content_ && FloatingVideoSurface.context_ === context ?
      FloatingVideoSurface.rect_.x - FloatingVideoSurface.desired_.x : 0;
    const offsetY = FloatingVideoSurface.content_ && FloatingVideoSurface.context_ === context ?
      FloatingVideoSurface.rect_.y - FloatingVideoSurface.desired_.y : 0;
    FloatingVideoSurface.context_ = context;
    FloatingVideoSurface.desired_ = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    FloatingVideoSurface.rect_ = { x: rect.x + offsetX, y: rect.y + offsetY, width: rect.width, height: rect.height };
    const params = new SurfaceParams(FloatingVideoSurface.rect_, true);
    if (!FloatingVideoSurface.content_) {
      FloatingVideoSurface.content_ = new ComponentContent(context, wrapBuilder<[SurfaceParams]>(buildSource), params);
      context.getOverlayManager().addComponentContent(FloatingVideoSurface.content_);
    } else {
      FloatingVideoSurface.content_.update(params);
      context.getOverlayManager().showComponentContent(FloatingVideoSurface.content_);
    }
  }

  static park(): void {
    const content = FloatingVideoSurface.content_;
    if (!content) return;
    content.update(new SurfaceParams(FloatingVideoSurface.rect_, false));
    // Hide the OverlayManager entry as well as parking its Surface: the manager's
    // wrapper otherwise keeps a full-window input region even with a transparent root.
    FloatingVideoSurface.context_?.getOverlayManager().hideComponentContent(content);
  }

  static async waitForLayout(): Promise<boolean> {
    await new Promise<void>((resolve) => { setTimeout(resolve, 32); });
    for (let i = 0; i < 90; i++) {
      const context = FloatingVideoSurface.context_;
      const node = context?.getFrameNodeById('system-pip-source-anchor');
      const size = node?.getMeasuredSize();
      if (context && node && size && FloatingVideoSurface.loaded_ && size.width > 1 && size.height > 1) {
        const pos = node.getPositionToWindow();
        const target = FloatingVideoSurface.desired_;
        // FrameNode positions are already vp, unlike display and Surface dimensions.
        const dx = target.x - pos.x;
        const dy = target.y - pos.y;
        if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
          FloatingVideoSurface.rect_ = { x: FloatingVideoSurface.rect_.x + dx, y: FloatingVideoSurface.rect_.y + dy, width: target.width, height: target.height };
          FloatingVideoSurface.content_?.update(new SurfaceParams(FloatingVideoSurface.rect_, true));
          // The source is now corrected for the window's actual safe-area origin.
          await new Promise<void>((resolve) => { setTimeout(resolve, 32); });
          continue;
        }
        FloatingVideoSurface.bindPlayer();
        return true;
      }
      await new Promise<void>((resolve) => { setTimeout(resolve, 16); });
    }
    return false;
  }

  static bindPlayer(): void {
    const video = PlayerService.getInstance().videoPlayer;
    const sid = FloatingVideoSurface.controller.getXComponentSurfaceId();
    if (!video || !sid || video.surfaceId === sid) return;
    try {
      video.surfaceId = sid;
      if (video.state === 'paused') video.seek(Math.max(0, video.currentTime), media.SeekMode.SEEK_CLOSEST);
      logInfo(`[FloatingPiP] bound surface=${sid}, time=${video.currentTime}, player=${video.state}`);
    } catch (error) { logWarn(`[FloatingPiP] bind: ${error}`); }
  }
}
