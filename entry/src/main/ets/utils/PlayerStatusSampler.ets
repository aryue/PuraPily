import { batteryInfo } from '@kit.BasicServicesKit';
import { statistics } from '@kit.NetworkKit';

@Observed
export class PlayerStatusSampler {
  speedText: string = '--';
  clockText: string = '';
  batteryText: string = '';
  blinkPhase: boolean = false;
  isLowBattery: boolean = false;
  isMediumBattery: boolean = false;
  isCharging: boolean = false;
  speedPulse: boolean = false;
  private timer: number = -1;
  private generation: number = 0;
  private sampling: boolean = false;
  private lastRxBytes: number = 0;
  private lastTxBytes: number = 0;
  private lastSampleTime: number = -1;

  start(): void {
    if (this.timer !== -1) return;
    const generation = ++this.generation;
    let ticks = 0;
    this.speedText = '--';
    this.speedPulse = false;
    this.blinkPhase = false;
    this.lastSampleTime = -1;
    this.updateClock();
    this.updateBattery();
    void this.sampleSpeed(generation);
    this.timer = setInterval(() => {
      if (generation !== this.generation) return;
      this.updateClock();
      void this.sampleSpeed(generation);
      if (++ticks % 15 === 0) this.updateBattery();
      if (this.isLowBattery || this.isCharging) this.blinkPhase = !this.blinkPhase;
    }, 1000);
  }

  stop(): void {
    if (this.timer === -1) return;
    clearInterval(this.timer);
    this.timer = -1;
    this.generation++;
    this.sampling = false;
  }

  private updateClock(): void {
    const d = new Date();
    this.clockText = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  }

  private updateBattery(): void {
    try {
      const soc = batteryInfo.batterySOC;
      this.isCharging = batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE;
      this.isLowBattery = soc >= 0 && soc <= 20;
      this.isMediumBattery = soc > 20 && soc <= 35;
      this.batteryText = soc >= 0 ? `${soc}%` : '--';
    } catch (_) {
      this.batteryText = '--';
    }
  }

  private formatSpeed(bytesPerSec: number): string {
    if (bytesPerSec < 1024) {
      return `${Math.max(0, Math.round(bytesPerSec))}B/s`;
    }
    if (bytesPerSec < 1024 * 1024) {
      return `${(bytesPerSec / 1024).toFixed(1)}KB/s`;
    }
    return `${(bytesPerSec / (1024 * 1024)).toFixed(1)}MB/s`;
  }

  private async sampleSpeed(generation: number): Promise<void> {
    if (this.sampling) return;
    this.sampling = true;
    try {
      const rx = await statistics.getAllRxBytes();
      if (generation !== this.generation) return;
      const tx = await statistics.getAllTxBytes();
      if (generation !== this.generation) return;

      const now = Date.now();
      if (this.lastSampleTime >= 0 && now > this.lastSampleTime) {
        const seconds = (now - this.lastSampleTime) / 1000;
        const speed = ((rx - this.lastRxBytes) + (tx - this.lastTxBytes)) / seconds;
        this.speedText = this.formatSpeed(speed);
        this.speedPulse = !this.speedPulse;
      }
      this.lastRxBytes = rx;
      this.lastTxBytes = tx;
      this.lastSampleTime = now;
    } catch (_) {
      if (generation === this.generation) {
        this.speedText = '--';
        this.lastSampleTime = -1;
      }
    } finally {
      if (generation === this.generation) this.sampling = false;
    }
  }
}
