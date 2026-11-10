// PlayerStatusStrip.ets - 播放器顶栏自绘状态条（网速 · 时间 · 电量）
import { statistics } from '@kit.NetworkKit';
import { batteryInfo } from '@kit.BasicServicesKit';

/**
 * 系统状态栏隐藏时（横屏全屏）替代显示的顶部状态条，与普通横屏播放页
 * `VideoControls.topBarStatusInfo` 同一内容与位置口径：屏幕居中 y:3，
 * 网速组/时间/电量组各 88vp 等宽；低电与充电按秒闪烁、网速脉冲。
 * 自带 1s 定时器（时间+网速，每 15s 刷电量），挂载即启动、卸载即停止；
 * 挂载首帧禁用入场 transition，避免随控制栏整体挂载时重放动画。
 */
@Component
export struct PlayerStatusStrip {
  @State speedText: string = '--';
  @State clockText: string = '';
  @State batteryText: string = '';
  @State blinkPhase: boolean = false;
  @State isLowBattery: boolean = false;
  @State isMediumBattery: boolean = false;
  @State isCharging: boolean = false;
  @State speedPulse: boolean = false;
  @State private mounted: boolean = false;
  private statusTimerId: number = -1;
  private statusTickCount: number = 0;
  private lastRxBytes: number = -1;
  private lastTxBytes: number = -1;
  private lastSampleTime: number = -1;

  aboutToAppear(): void {
    this.updateClock();
    this.updateBattery();
    void this.sampleSpeed(true);
    if (this.statusTimerId !== -1) {
      clearInterval(this.statusTimerId);
    }
    this.statusTimerId = setInterval(() => {
      this.updateClock();
      void this.sampleSpeed(false);
      this.statusTickCount++;
      if (this.statusTickCount % 15 === 0) {
        this.updateBattery();
      }
      if (this.isLowBattery || this.isCharging) {
        this.blinkPhase = !this.blinkPhase;
      }
    }, 1000);
    setTimeout(() => { this.mounted = true; }, 120);
  }

  aboutToDisappear(): void {
    if (this.statusTimerId !== -1) {
      clearInterval(this.statusTimerId);
      this.statusTimerId = -1;
    }
  }

  private gatedT(effect: TransitionEffect): TransitionEffect {
    return this.mounted ? effect : TransitionEffect.IDENTITY;
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
      this.isMediumBattery = soc >= 0 && soc > 20 && soc <= 35;
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

  /** 采样系统上下行总流量差分，计算实时网速；first=true 只建立基线不更新显示 */
  private async sampleSpeed(first: boolean): Promise<void> {
    try {
      const rx = await statistics.getAllRxBytes();
      const tx = await statistics.getAllTxBytes();
      const now = Date.now();
      if (!first && this.lastRxBytes >= 0 && this.lastTxBytes >= 0 && this.lastSampleTime > 0) {
        const dt = (now - this.lastSampleTime) / 1000;
        if (dt > 0) {
          const speed = ((rx - this.lastRxBytes) + (tx - this.lastTxBytes)) / dt;
          this.speedText = this.formatSpeed(speed);
          this.speedPulse = !this.speedPulse;
        }
      }
      this.lastRxBytes = rx;
      this.lastTxBytes = tx;
      this.lastSampleTime = now;
    } catch (_) {
      this.speedText = '--';
    }
  }

  build() {
    Row() {
      // 网速组（图标 + 定宽文本：右对齐→右侧稳定、数值变化向左生长）
      Row() {
        Image($r('app.media.heart_rate'))
          .width(20)
          .height(20)
          .fillColor('#FFFFFF')
          .opacity(0.85)
          .margin({ right: 2 })
          .scale({ x: this.speedPulse ? 1.1 : 1, y: this.speedPulse ? 1.1 : 1 })
          .animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.Sharp })
          .transition(this.gatedT(
            TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut })
              .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut }))
          ))
        Text(this.speedText)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(66)
          .maxLines(1)
          .textAlign(TextAlign.End)
          .transition(this.gatedT(
            TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut, delay: 40 })
              .combine(TransitionEffect.translate({ y: 6 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut, delay: 40 }))
          ))
      }
      .width(88)

      Text('·')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .opacity(0.5)
        .margin({ left: 5, right: 5 })

      Text(this.clockText)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(48)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .transition(this.gatedT(
          TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut, delay: 40 })
            .combine(TransitionEffect.translate({ y: 6 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut, delay: 40 }))
        ))

      Text('·')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .opacity(0.5)
        .margin({ left: 5, right: 5 })

      // 电量组（文本 + 图标，与网速组等宽 88vp，时间两侧均衡）
      Row() {
        Text(this.batteryText)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(40)
          .maxLines(1)
          .textAlign(TextAlign.Start)
          .transition(this.gatedT(
            TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut, delay: 40 })
              .combine(TransitionEffect.translate({ y: 6 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut, delay: 40 }))
          ))
        Image($r(this.isCharging ? 'app.media.battery_charge14' : 'app.media.batteryfull_32'))
          .width(20)
          .height(20)
          .fillColor(this.isLowBattery ? '#FF5A5A' : this.isMediumBattery ? '#FFB300' : this.isCharging ? '#57C15A' : '#FFFFFF')
          .opacity(this.isLowBattery ? (this.blinkPhase ? 0.4 : 1)
            : this.isCharging ? (this.blinkPhase ? 0.75 : 1) : 0.85)
          .margin({ left: 2 })
          .animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 500, curve: Curve.Linear })
          .transition(this.gatedT(
            TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut })
              .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut }))
          ))
      }
      .width(88)
    }
    .position({ x: '50%', y: 3 })
    .translate({ x: '-50%' })
    .hitTestBehavior(HitTestMode.None)
  }
}
