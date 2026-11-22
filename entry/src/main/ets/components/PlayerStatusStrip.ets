// PlayerStatusStrip.ets - 播放器顶栏自绘状态条（网速 · 时间 · 电量）
import { PlayerStatusSampler } from '../utils/PlayerStatusSampler';

/**
 * 系统状态栏隐藏时（横屏全屏）替代显示的顶部状态条，与普通横屏播放页
 * `VideoControls.topBarStatusInfo` 同一内容与位置口径：屏幕居中 y:3，
 * 网速组/时间/电量组各 88vp 等宽；低电与充电按秒闪烁、网速脉冲。
 * 可见时每秒更新时钟和网速，每 15 秒刷新电量。
 * 挂载首帧禁用入场 transition，避免随控制栏整体挂载时重放动画。
 */
@Component
export struct PlayerStatusStrip {
  @Prop @Watch('refreshStatusSampling') samplingVisible: boolean = true;
  @State private status: PlayerStatusSampler = new PlayerStatusSampler();
  @State private mounted: boolean = false;
  private statusOwnerAttached: boolean = false;

  aboutToAppear(): void {
    this.statusOwnerAttached = true;
    this.refreshStatusSampling();
    setTimeout(() => { this.mounted = true; }, 120);
  }

  aboutToDisappear(): void {
    this.statusOwnerAttached = false;
    this.status.stop();
  }

  private refreshStatusSampling(): void {
    if (this.statusOwnerAttached && this.samplingVisible) {
      this.status.start();
    } else {
      this.status.stop();
    }
  }

  private gatedT(effect: TransitionEffect): TransitionEffect {
    return this.mounted ? effect : TransitionEffect.IDENTITY;
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
          .scale({ x: this.status.speedPulse ? 1.1 : 1, y: this.status.speedPulse ? 1.1 : 1 })
          .animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.Sharp })
          .transition(this.gatedT(
            TransitionEffect.OPACITY.animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseInOut })
              .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }).animation({ expectedFrameRateRange: { min: 60, max: 120, expected: 120 }, duration: 250, curve: Curve.EaseOut }))
          ))
        Text(this.status.speedText)
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

      Text(this.status.clockText)
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
        Text(this.status.batteryText)
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
        Image($r(this.status.isCharging ? 'app.media.battery_charge14' : 'app.media.batteryfull_32'))
          .width(20)
          .height(20)
          .fillColor(this.status.isLowBattery ? '#FF5A5A' : this.status.isMediumBattery ? '#FFB300' : this.status.isCharging ? '#57C15A' : '#FFFFFF')
          .opacity(this.status.isLowBattery ? (this.status.blinkPhase ? 0.4 : 1)
            : this.status.isCharging ? (this.status.blinkPhase ? 0.75 : 1) : 0.85)
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
