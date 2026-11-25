import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';
import { logInfo } from './Logger';

/** The viewport stays landscape in fullscreen, so track device posture separately. */
export class FullscreenDeviceOrientation {
  private listening: boolean = false;
  private landscape: boolean | null = null;
  private sampledAt: number = 0;
  private lastRawLogAt: number = 0;
  /** Last successfully read system auto-rotation switch; '1' = unlocked, '0' = locked. */
  private cachedRotationLock: string = '';
  private readonly onGravity = (value: sensor.GravityResponse): void => {
    const x = Math.abs(value.x);
    const y = Math.abs(value.y);
    const z = Math.abs(value.z);
    const dominant = Math.max(x, y);
    if (Date.now() - this.lastRawLogAt >= 1000) {
      this.lastRawLogAt = Date.now();
      logInfo(`[FSOrient] gravity raw x=${value.x.toFixed(2)} y=${value.y.toFixed(2)} z=${value.z.toFixed(2)}`);
    }
    // Flat or diagonal poses do not establish a new orientation.
    if (dominant < 4 || dominant < z * 0.6 || Math.abs(x - y) < 1.5) return;
    this.landscape = x > y;
    this.sampledAt = Date.now();
  };

  start(): void {
    if (this.listening) return;
    try {
      sensor.on(sensor.SensorId.GRAVITY, this.onGravity);
      this.listening = true;
      logInfo('[FSOrient] gravity listening');
    } catch (e) {
      logInfo(`[FSOrient] gravity subscribe failed: ${(e as Error)?.message ?? e}`);
    }
  }

  stop(): void {
    if (this.listening) {
      try { sensor.off(sensor.SensorId.GRAVITY, this.onGravity); } catch (_e) {}
    }
    this.listening = false;
    logInfo(`[FSOrient] gravity stopped, last=${this.landscape}`);
    this.landscape = null;
    this.sampledAt = 0;
    this.lastRawLogAt = 0;
  }

  /**
   * Read and cache the system auto-rotation switch while a UIAbilityContext is guaranteed.
   *
   * `getHostContext()` can be transiently unavailable during window/navigation transitions;
   * a failed synchronous read used to fall back to the pre-fullscreen orientation even when
   * the system was unlocked, which looks like "returned to the wrong direction".
   */
  refreshRotationLock(context: common.UIAbilityContext | undefined): void {
    if (!context) return;
    try {
      const raw = settings.getValueSync(context, settings.general.ACCELEROMETER_ROTATION_STATUS, '');
      if (raw === '0' || raw === '1') this.cachedRotationLock = raw;
    } catch (_e) {}
  }

  private rotationLockRaw(context: common.UIAbilityContext | undefined): string {
    if (context) {
      try {
        const raw = settings.getValueSync(context, settings.general.ACCELEROMETER_ROTATION_STATUS, '');
        if (raw === '0' || raw === '1') {
          this.cachedRotationLock = raw;
          return raw;
        }
      } catch (_e) {}
    }
    return this.cachedRotationLock;
  }

  returnLandscape(policy: window.Orientation, current: boolean, phoneViewport: boolean,
    context: common.UIAbilityContext): boolean {
    let lockRaw = '';
    const physicalAge = this.landscape !== null ? Date.now() - this.sampledAt : -1;
    switch (policy) {
      case window.Orientation.PORTRAIT:
      case window.Orientation.PORTRAIT_INVERTED:
      case window.Orientation.AUTO_ROTATION_PORTRAIT:
        logInfo(`[FSOrient] policy=${policy} -> portrait (explicit)`);
        return false;
      case window.Orientation.LANDSCAPE:
      case window.Orientation.LANDSCAPE_INVERTED:
      case window.Orientation.AUTO_ROTATION_LANDSCAPE:
        logInfo(`[FSOrient] policy=${policy} -> landscape (explicit)`);
        return true;
      case window.Orientation.AUTO_ROTATION_RESTRICTED:
        lockRaw = this.rotationLockRaw(context);
        if (lockRaw !== '1') {
          if (phoneViewport) {
            // Phones do not support a landscape rotation lock: while locked the non-fullscreen
            // state is always portrait, even if fullscreen was entered from a landscape window.
            logInfo(`[FSOrient] policy=restricted lock=${lockRaw || 'unknown'} phone -> portrait`);
            return false;
          }
          const lockedPhysical = this.landscape !== null && physicalAge >= 0 && physicalAge <= 800;
          const result = lockedPhysical ? (this.landscape as boolean) : current;
          logInfo(`[FSOrient] policy=restricted lock=${lockRaw || 'unknown'} tablet physical=${this.landscape} ` +
            `age=${physicalAge} -> ${result ? 'landscape' : 'portrait'}`);
          return result;
        }
        break;
      case window.Orientation.AUTO_ROTATION:
        break;
      default:
        logInfo(`[FSOrient] policy=${policy} -> current=${current} (unhandled)`);
        return current;
    }
    const followPhysical = this.landscape !== null && physicalAge >= 0 && physicalAge <= 800;
    const result = followPhysical ? (this.landscape as boolean) : current;
    logInfo(`[FSOrient] policy=${policy} lock=${lockRaw || 'n/a'} physical=${this.landscape} age=${physicalAge} ` +
      `follow=${followPhysical} -> ${result ? 'landscape' : 'portrait'}`);
    return result;
  }
}
