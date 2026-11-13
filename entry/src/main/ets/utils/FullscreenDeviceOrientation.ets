import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { sensor } from '@kit.SensorServiceKit';

/** The viewport stays landscape in fullscreen, so track device posture separately. */
export class FullscreenDeviceOrientation {
  private listening: boolean = false;
  private landscape: boolean | null = null;
  private sampledAt: number = 0;
  private readonly onGravity = (value: sensor.GravityResponse): void => {
    const x = Math.abs(value.x);
    const y = Math.abs(value.y);
    const dominant = Math.max(x, y);
    // Flat or diagonal poses do not establish a new orientation.
    if (dominant < 4 || dominant < Math.abs(value.z) * 0.6 || Math.abs(x - y) < 1.5) return;
    this.landscape = x > y;
    this.sampledAt = Date.now();
  };

  start(): void {
    if (this.listening) return;
    try {
      sensor.on(sensor.SensorId.GRAVITY, this.onGravity);
      this.listening = true;
    } catch (_e) {}
  }

  stop(): void {
    if (this.listening) {
      try { sensor.off(sensor.SensorId.GRAVITY, this.onGravity); } catch (_e) {}
    }
    this.listening = false;
    this.landscape = null;
    this.sampledAt = 0;
  }

  returnLandscape(policy: window.Orientation, current: boolean, context: common.UIAbilityContext): boolean {
    switch (policy) {
      case window.Orientation.PORTRAIT:
      case window.Orientation.PORTRAIT_INVERTED:
      case window.Orientation.AUTO_ROTATION_PORTRAIT:
        return false;
      case window.Orientation.LANDSCAPE:
      case window.Orientation.LANDSCAPE_INVERTED:
      case window.Orientation.AUTO_ROTATION_LANDSCAPE:
        return true;
      case window.Orientation.AUTO_ROTATION_RESTRICTED:
        try {
          if (settings.getValueSync(context, settings.general.ACCELEROMETER_ROTATION_STATUS, '') !== '1') return current;
        } catch (_e) { return current; }
        break;
      case window.Orientation.AUTO_ROTATION:
        break;
      default:
        return current;
    }
    return this.landscape !== null && Date.now() - this.sampledAt <= 800 ? this.landscape : current;
  }
}
