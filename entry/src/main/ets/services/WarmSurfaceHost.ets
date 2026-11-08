/**
 * 全局预热 surface 宿主。
 *
 * Index 页里挂一个 1x1 的隐藏 XComponent，它的 surface 会随着首页常驻，
 * 页面路由压栈时也不销毁；预热播放器绑在这里 prepare，进入播放页后改绑到页面 surface。
 * 仅保存 surfaceId，不持有播放器。
 */
export class WarmSurfaceHost {
  private static surfaceId: string = '';
  private static readyAt: number = 0;

  static set(id: string): void {
    if (id.length === 0) {
      return;
    }
    WarmSurfaceHost.surfaceId = id;
    WarmSurfaceHost.readyAt = Date.now();
  }

  static get(): string {
    return WarmSurfaceHost.surfaceId;
  }

  static ready(): boolean {
    return WarmSurfaceHost.surfaceId.length > 0;
  }

  static ageMs(): number {
    return WarmSurfaceHost.readyAt > 0 ? Date.now() - WarmSurfaceHost.readyAt : -1;
  }
}
