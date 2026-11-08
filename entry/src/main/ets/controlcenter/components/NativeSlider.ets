import { headphoneIconResource } from '../../utils/HeadphoneIcons';
import { OriginalProgress } from '../material/OriginalProgress';
import { UpperLightPreview } from '../material/UpperLightPreview';
import lottie, { AnimationItem, AnimationSegment } from '@ohos/lottie';
import { util } from '@kit.ArkTS';
import { curves } from '@kit.ArkUI';
import { PressController } from '../model/PressController';
import { IconFrames } from '../model/IconFrames';
import { ImmersiveShellMaterial } from '../material/ImmersiveShellMaterial';
import { OriginalShellMaterial, OriginalPointSource } from '../material/OriginalFillMaterial';
import { SurfaceLight } from '../material/SurfaceLight';
import { ProgressFill } from '../material/ProgressFill';
import { FirmwareParticles } from '../particles/FirmwareParticles';
import { ParticleGeometry } from '../model/ParticleGeometry';
import { ParticleMaterial } from '../particles/ParticleMaterial';
import { i18n } from '@kit.LocalizationKit';
import { JellyMotion, JellyHost } from '../model/JellyMotion';
import { NativeJellyMotion } from '../model/NativeJellyMotion';
import { JellyRenderer } from '../material/JellyRenderer';
import { NativeCollapse } from '../material/NativeCollapse';
import { SdfKeyframes } from '../model/SdfKeyframes';
import { uiEffect } from '@kit.ArkGraphics2D';
import { AdjustmentMotion } from '../model/AdjustmentMotion';

@Component
struct FirmwareIcon {
  @Prop @Watch('refresh') value: number = 0;
  @Prop kind: string = 'sun';
  @Prop sliderLength: number = 128;
  @Prop @Watch('recolor') ink: boolean = false;
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private animationItem: AnimationItem | null = null;
  private alive: boolean = true;
  private loaded: boolean = false;
  private previousLevel: number = -1;
  private name: string = `icon_${Date.now()}_${Math.random()}`;

  private refresh(): void {
    if (!this.loaded) { return; }
    if (this.kind !== 'volume') {
      this.animationItem?.goToAndStop(IconFrames.sun(this.value, this.sliderLength), true);
      return;
    }
    const level: number = IconFrames.volumeLevel(this.value);
    if (this.previousLevel === level) { return; }
    if (this.previousLevel === -1) {
      this.animationItem?.goToAndStop(IconFrames.volumeRestFrame(level), true);
    } else {
      const range: number[] = IconFrames.volumeSegment(this.previousLevel, level);
      const segment: AnimationSegment = [range[0], range[1]];
      this.animationItem?.setSpeed(2);
      this.animationItem?.playSegments(segment, true);
    }
    this.previousLevel = level;
  }

  private recolor(): void {
    this.animationItem?.changeColor(this.ink ? [0, 0, 0, 1] : [255, 255, 255, 1]);
    this.refresh();
  }

  private async load(): Promise<void> {
    try {
      const name: string = this.kind === 'volume' ? 'player_cc_lottie_volume_media_cc.json' : 'player_cc_sun.json';
      const bytes: Uint8Array = await this.getUIContext().getHostContext()!.resourceManager.getRawFileContent(name);
      if (!this.alive) { return; }
      const data: Object = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(bytes)) as Object;
      this.animationItem = lottie.loadAnimation({ container: this.canvas, renderer: 'canvas',
        autoplay: false, loop: false, name: this.name, animationData: data, contentMode: 'Contain' });
      this.animationItem.addEventListener('DOMLoaded', () => {
        if (!this.alive) { return; }
        this.loaded = true;
        this.animationItem?.changeColor(this.ink ? [0, 0, 0, 1] : [255, 255, 255, 1]);
        this.refresh();
      });
    } catch (error) {
      console.error(`FirmwareIcon load failed: ${error}`);
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    lottie.destroy(this.name);
    this.animationItem = null;
  }

  build() {
    Canvas(this.canvas).width(28).height(28).onReady(() => { this.load(); })
      .hitTestBehavior(HitTestMode.None)
  }
}

@Component
export struct NativeSlider {
  @Link @Watch('valueChanged') value: number;
  @Prop kind: string = 'sun';
  @Prop headphones: boolean = false;
  @Prop headphoneIcon: string = 'headphones_fill';
  @Prop @Watch('syncProgress') wide: boolean = false;
  @Prop @Watch('syncProgress') vertical: boolean = false;
  @Prop particlesEnabled: boolean = true;
  @Prop lightEnabled: boolean = true;
  @Prop immersiveEnabled: boolean = false;
  @Prop immersiveStyle: number = 0;
  @Prop originalLight: boolean = false;
  @Prop levelLight: boolean = false;
  @Prop upperLightGain: number = 0.4;
  @Prop emulatorLightPreview: boolean = false;
  @Prop @Watch('syncAdjusting') adjusting: boolean = false;
  @Prop @Watch('syncPressing') pressing: boolean = false;
  @Prop @Watch('motionChanged') adjustmentMotion: AdjustmentMotion | undefined = undefined;
  @Prop brightnessMotion: boolean = false;
  @Prop touchEnabled: boolean = true;
  @Prop @Watch('cancelJelly') jellyEnabled: boolean = true;
  @State private jellyShowing: boolean = false;
  @State private jellyCaptureMode: boolean = false;
  @State private nativeJellyEffect: uiEffect.VisualEffect | undefined = undefined;
  @State private nativeJellyActive: boolean = false;
  @State private nativeJellyPrepared: boolean = false;
  private nativeJellyReady: boolean = false;
  private nativeBaseScale: number = 1;
  private outerPressed: boolean = false;
  private jellyRenderer: JellyRenderer = new JellyRenderer();
  private jellySnapshotId: string = `jelly_${Date.now()}_${Math.random()}`;
  private jellyController: JellyMotion | NativeJellyMotion | null = null;
  @State private dragging: boolean = false;
  @State private chosen: boolean = false;
  @State private buttonZoom: number = 1;
  @State private innerZoomX: number = 1;
  @State private innerZoomY: number = 1;
  @State private lightX: number = 72;
  @State private lightY: number = 32;
  @State private lightIntensity: number = 0;
  // Visual calibration for the current mixed material stack. Keep the contact
  // envelope and Canvas fallback at 0..1; increase only the native point source.
  private nativeLightGain: number = 1.5;
  @State private showParticles: boolean = false;
  @State private particleOpacity: number = 0;
  @State private fields: RippleFieldOptions[] = [];
  @State private velocity: number = 0;
  @State private uiValue: number = 0;
  private sliderRate: number = 0.6;
  private startValue: number = 0;
  private startOffset: number = 0;
  private lastOffset: number = 0;
  private accumulated: number = 0;
  private fingerX: number = 0;
  private fingerY: number = 0;
  private rippleTimer: number = -1;
  private particleGeneration: number = 0;
  private pressController: PressController | null = null;
  private appeared: boolean = false;
  private directContact: boolean = false;
  private adjustmentTimer: number = -1;
  private feedbackActive: boolean = false;
  private internalValueWrite: boolean = false;
  private observedValue: number = 0;
  private externalValueAt: number = 0;
  private motionSequence: number = -1;

  private externalAnchor(): void {
    this.fingerX = this.sourceX();
    this.fingerY = this.sourceY();
  }

  private externalIdle(): void {
    if (this.adjusting) { return; }
    this.cancelAdjustmentTimer();
    this.adjustmentTimer = setTimeout(() => {
      this.adjustmentTimer = -1;
      if (!this.adjusting && !this.dragging && !this.directContact) { this.finishAdjustment(); }
    }, 600);
  }

  private externalMovement(delta: number, velocity: number): void {
    this.externalAnchor();
    this.accumulated += delta * this.trackVp();
    const direction: number = this.vertical ? -1 :
      (i18n.isRTL(i18n.System.getAppPreferredLanguage()) ? -1 : 1);
    this.velocity = ParticleGeometry.velocity(velocity * this.trackVp() * direction);
    this.externalValueAt = Date.now();
  }

  private motionChanged(): void {
    const sample: AdjustmentMotion | undefined = this.adjustmentMotion;
    if (!this.appeared || !this.levelLight || sample === undefined || sample.sequence === this.motionSequence) { return; }
    this.motionSequence = sample.sequence;
    if (!this.adjusting) { return; }
    if (this.dragging || this.directContact) { return; }
    this.externalAnchor();
    this.startAdjustment();
    this.externalMovement(sample.delta, sample.velocity);
    this.externalIdle();
  }

  private sourceX(): number {
    if (!this.levelLight) { return this.lightX; }
    return this.vertical ? this.widthVp() / 2 :
      this.widthVp() / 2 + (Math.max(0, Math.min(this.trackVp(), this.uiValue)) - this.trackVp() / 2) * this.innerZoomX;
  }

  private sourceY(): number {
    if (!this.levelLight) { return this.lightY; }
    return this.vertical ? this.heightVp() / 2 +
      (this.trackVp() / 2 - Math.max(0, Math.min(this.trackVp(), this.uiValue))) * this.innerZoomY : this.heightVp() / 2;
  }

  private opticalCut(): number {
    return Math.max(0, Math.min(this.heightVp(), this.sourceY()));
  }

  private hasJellyMotion(): boolean {
    return this.vertical && (this.kind !== 'volume' || this.brightnessMotion);
  }

  @Builder
  private opticalSurface(alpha: number) {
    // Always render the complete original material shape. Its parent masks
    // visibility; a percentage-sized material would create a new bright rim.
    Row().width(this.widthVp()).height(this.heightVp()).borderRadius(32)
      .constraintSize({ minHeight: this.heightVp(), maxHeight: this.heightVp() })
      .attributeModifier(new OriginalShellMaterial(this.chosen, this.lightEnabled))
      .opacity(alpha)
      .hitTestBehavior(HitTestMode.None)
  }

  private cancelAdjustmentTimer(): void {
    if (this.adjustmentTimer !== -1) { clearTimeout(this.adjustmentTimer); this.adjustmentTimer = -1; }
  }

  private syncPressing(): void {
    if (!this.appeared || !this.levelLight || this.directContact) { return; }
    if (this.pressing) { this.contact().down(); }
    else { this.contact().up(); }
  }

  private syncAdjusting(): void {
    if (!this.appeared || !this.levelLight) { return; }
    this.cancelAdjustmentTimer();
    if (this.adjusting) {
      this.externalAnchor();
      this.startAdjustment();
    } else if (!this.dragging && !this.directContact) { this.finishAdjustment(); }
  }

  private valueChanged(): void {
    const delta: number = this.value - this.observedValue;
    const elapsed: number = this.feedbackActive ? Math.max(16, Date.now() - this.externalValueAt) : 16;
    this.observedValue = this.value;
    this.syncProgress();
    if (this.internalValueWrite || (this.adjustmentMotion !== undefined && !this.adjusting)) { return; }
    if (!this.appeared || !this.levelLight || this.dragging || this.directContact) { return; }
    this.cancelAdjustmentTimer();
    this.externalAnchor();
    this.startAdjustment();
    if (this.adjustmentMotion === undefined) { this.externalMovement(delta, delta * 1000 / elapsed); }
    this.externalIdle();
  }

  private contact(): PressController {
    if (this.pressController === null) {
      this.pressController = new PressController({
        schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
        cancel: (id: number): void => { clearTimeout(id); },
        outerChanged: (pressed: boolean): void => {
          this.outerPressed = pressed;
          if (!this.nativeJellyActive) {
            this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 180, 20) }, () => {
              this.buttonZoom = pressed ? 1.1 : 1;
            });
          }
        },
        contactChanged: (pressed: boolean): void => {
          this.getUIContext().animateTo({ curve: curves.springMotion(0.3, 1) }, () => {
            this.lightIntensity = pressed ? 1 : 0;
          });
        },
        innerChanged: (selected: boolean): void => {
          // The actual Lottie changes color as a whole. It is outside the scaled fill.
          this.chosen = selected;
          this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.28, 1, 0) }, () => {
            this.innerZoomX = selected ? this.widthVp() / this.innerWidthVp() : 1;
            this.innerZoomY = selected ? this.heightVp() / this.innerHeightVp() : 1;
          });
        }
      });
    }
    return this.pressController;
  }

  private jelly(): JellyMotion | NativeJellyMotion {
    if (this.jellyController === null) {
      const host: JellyHost = {
        now: (): number => Date.now(),
        schedule: (callback: () => void, delay: number): number => setTimeout(callback, delay),
        cancel: (id: number): void => { clearTimeout(id); },
        activate: (): boolean => {
          try {
            if (this.nativeJellyReady) {
              this.nativeBaseScale = this.buttonZoom;
              this.nativeJellyActive = true;
              console.info(`CCLab native distortionCollapse activated; no component snapshots; kind=${this.kind}`);
              return true;
            }
            this.jellyRenderer.resize(this.widthVp(), this.heightVp());
            this.jellyRenderer.capture(this.getUIContext(), this.jellySnapshotId, true);
            this.jellyShowing = true;
            console.info('CCLab brightness jelly activated: original timing, public mesh renderer');
            return true;
          } catch (error) {
            console.error(`CCLab jelly capture failed: ${error}`);
            return false;
          }
        },
        frame: (shape: number[]): void => {
          try {
            if (this.nativeJellyActive) {
              this.nativeJellyEffect = NativeCollapse.create(shape, this.nativeBaseScale);
              return;
            }
            this.jellyRenderer.setIcon(this.value, this.trackVp(), this.chosen, this.kind !== 'volume');
            this.jellyRenderer.capture(this.getUIContext(), this.jellySnapshotId);
            this.jellyRenderer.frame(shape);
          } catch (error) {
            console.error(`CCLab jelly stopped: ${error}`);
            this.jellyController?.stop();
          }
        },
        finish: (): void => {
          const wasNative: boolean = this.nativeJellyActive;
          this.nativeJellyActive = false;
          this.nativeJellyPrepared = false;
          if (this.nativeJellyReady) { this.nativeJellyEffect = NativeCollapse.clear(); }
          if (wasNative) {
            // Final compensated identity * frozen base = identity. Clear both
            // factors together; never restore a stale pressed multiplier.
            this.buttonZoom = 1;
            if (this.outerPressed) {
              this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 180, 20) }, () => {
                this.buttonZoom = 1.1;
              });
            }
          }
          this.jellyShowing = false;
          this.jellyCaptureMode = false;
          this.jellyRenderer.clear();
        }
      };
      if (this.nativeJellyReady) {
        this.jellyController = new NativeJellyMotion(host,
          (shape: number[], delay: number, onFinish?: () => void): void => {
            this.getUIContext().animateTo({ curve: curves.interpolatingSpring(0, 1, 140, 20),
              delay: delay, onFinish: onFinish }, () => { host.frame(shape); });
          });
      } else {
        this.jellyController = new JellyMotion(host);
      }
    }
    return this.jellyController;
  }

  private cancelJelly(): void {
    if (!this.jellyEnabled) { this.jellyController?.stop(); }
  }

  private widthVp(): number { return this.vertical ? 64 : (this.wide ? 312 : 144); }
  private heightVp(): number { return this.vertical ? (this.wide ? 312 : 144) : 64; }
  private trackVp(): number { return this.wide ? 272 : 128; }
  private innerWidthVp(): number { return this.vertical ? 48 : this.trackVp(); }
  private innerHeightVp(): number { return this.vertical ? this.trackVp() : 48; }
  aboutToAppear(): void {
    this.uiValue = this.value * this.trackVp();
    this.observedValue = this.value;
    this.externalValueAt = Date.now();
    this.motionSequence = this.adjustmentMotion === undefined ? -1 : this.adjustmentMotion.sequence;
    this.sliderRate = ParticleMaterial.rate();
    if (this.hasJellyMotion()) {
      try {
        NativeCollapse.create(SdfKeyframes.identity);
        this.nativeJellyReady = true;
        console.info(`CCLab native distortionCollapse probe accepted; kind=${this.kind}`);
      } catch (error) {
        console.warn(`CCLab native distortionCollapse unavailable: ${error}`);
      }
    }
    this.appeared = true;
    this.syncPressing();
    this.syncAdjusting();
  }
  private syncProgress(): void {
    this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion(0.1, 1, 0) }, () => {
      this.uiValue = this.value * this.trackVp();
    });
  }
  private stopTimer(): void {
    if (this.rippleTimer !== -1) { clearInterval(this.rippleTimer); this.rippleTimer = -1; }
  }
  aboutToDisappear(): void {
    this.appeared = false;
    this.feedbackActive = false;
    this.cancelAdjustmentTimer();
    this.jellyController?.stop();
    this.jellyRenderer.dispose();
    this.pressController?.dispose();
    this.stopTimer();
    this.particleGeneration++;
  }
  private ripple(): void {
    const field: RippleFieldOptions = { amplitude: 120, wavelength: 450, waveSpeed: 300, attenuation: 0,
      center: this.vertical ? { x: this.widthVp() / 2, y: this.fingerY } :
        { x: this.fingerX, y: this.heightVp() / 2 },
      region: { shape: DisturbanceFieldShape.RECT,
        position: { x: this.widthVp() / 2, y: this.heightVp() / 2 },
        size: { width: this.widthVp(), height: this.heightVp() } } };
    this.fields = this.fields.length >= 20 ? [field] : [...this.fields, field];
  }
  private startAdjustment(): void {
    if (this.feedbackActive) { return; }
    this.feedbackActive = true;
    this.contact().down();
    this.contact().startDragging();
    this.stopTimer();
    this.particleGeneration++;
    this.accumulated = 0;
    this.velocity = 0;
    if (this.hasJellyMotion() && this.jellyEnabled) {
      if (this.nativeJellyReady && !this.nativeJellyActive) {
        // Install an identity filter during the 300ms waiting period, so the
        // first spring changes an existing effect instead of adding its first
        // target as a new filter's initial value in the same render transaction.
        try {
          this.nativeJellyEffect = NativeCollapse.create(SdfKeyframes.identity);
          this.nativeJellyPrepared = true;
        } catch (error) {
          console.warn(`CCLab native jelly preparation failed: ${error}`);
          this.jellyController?.stop();
          this.jellyController = null;
          this.nativeJellyReady = false;
        }
      }
      this.jellyCaptureMode = !this.nativeJellyReady;
      this.jelly().down();
    }
    if (!this.particlesEnabled) { return; }
    this.fields = [];
    this.showParticles = true;
    this.particleOpacity = 1;
    this.ripple();
    this.rippleTimer = setInterval(() => {
      if (Math.abs(this.accumulated) > 30) { this.accumulated = 0; this.ripple(); }
      if (!this.dragging && Date.now() - this.externalValueAt > 140) { this.velocity = 0; }
    }, 140);
  }
  private begin(event: GestureEvent): void {
    if (!this.touchEnabled) { return; }
    this.cancelAdjustmentTimer();
    this.startValue = this.value;
    this.startOffset = this.vertical ? event.offsetY : event.offsetX;
    this.lastOffset = this.startOffset;
    this.fingerX = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
    this.fingerY = event.fingerList.length > 0 ? event.fingerList[0].localY : 0;
    this.dragging = true;
    this.startAdjustment();
  }
  private setInputValue(value: number): void {
    this.internalValueWrite = true;
    try { this.value = value; } finally { this.internalValueWrite = false; }
  }

  private move(event: GestureEvent): void {
    if (!this.touchEnabled) { return; }
    if (event.fingerList.length > 0) {
      this.followLight(event.fingerList[0].localX, event.fingerList[0].localY);
    }
    const direction: number = this.vertical ? -1 :
      (i18n.isRTL(i18n.System.getAppPreferredLanguage()) ? -1 : 1);
    const offset: number = this.vertical ? event.offsetY : event.offsetX;
    const delta: number = (offset - this.lastOffset) * direction;
    if (Math.abs(delta) < Number.EPSILON) { return; }
    this.setInputValue(Math.max(0, Math.min(1,
      this.startValue + (offset - this.startOffset) * direction / this.trackVp())));
    if (event.fingerList.length > 0) {
      const x: number = event.fingerList[0].localX;
      const y: number = event.fingerList[0].localY;
      if (!this.vertical && x >= 0 && x <= this.trackVp()) { this.fingerX = x; }
      if (this.vertical && y >= 0 && y <= this.trackVp()) { this.fingerY = y; }
    }
    this.accumulated += delta;
    this.lastOffset = offset;
    this.velocity = ParticleGeometry.velocity(this.vertical ? event.velocityY : event.velocityX);
  }
  private end(): void {
    this.dragging = false;
    if (!this.adjusting) { this.finishAdjustment(); }
  }
  private finishAdjustment(): void {
    this.contact().endDragging();
    if (!this.directContact && !this.pressing) { this.contact().up(); }
    if (!this.feedbackActive) { return; }
    this.feedbackActive = false;
    this.jellyController?.up();
    if (this.nativeJellyPrepared && !this.nativeJellyActive) {
      this.nativeJellyEffect = NativeCollapse.clear();
      this.nativeJellyPrepared = false;
    }
    if (!this.jellyShowing) { this.jellyCaptureMode = false; }
    this.stopTimer();
    const generation: number = this.particleGeneration;
    this.getUIContext().animateTo({ duration: 600, curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.feedbackActive && generation === this.particleGeneration) { this.showParticles = false; }
      }
    }, () => { this.particleOpacity = 0; });
  }

  private followLight(x: number, y: number): void {
    const targetX: number = Math.max(0, Math.min(this.widthVp(), x));
    const targetY: number = Math.max(0, Math.min(this.heightVp(), y));
    this.getUIContext().animateTo({ curve: curves.responsiveSpringMotion() }, () => {
      this.lightX = targetX;
      this.lightY = targetY;
    });
  }

  private tap(event: GestureEvent): void {
    if (!this.touchEnabled) { return; }
    if (event.fingerList.length === 0) { return; }
    const margin: number = ((this.vertical ? this.heightVp() : this.widthVp()) - this.trackVp()) / 2;
    const position: number = this.vertical ? this.heightVp() - margin - event.fingerList[0].localY :
      event.fingerList[0].localX - margin;
    this.setInputValue(Math.max(0, Math.min(1, position / this.trackVp())));
  }

  @Builder
  private surface() {
    Stack({ alignContent: Alignment.Center }) {
      // Keep the persistent outer material on the SDF root. Scene 49 is a
      // separate full-button optical layer, never a replacement for that shell
      // or a material on the percentage-clipped progress surface.
      if (this.originalLight && this.immersiveEnabled && this.vertical && this.chosen && !this.emulatorLightPreview) {
        if (this.levelLight && this.upperLightGain < 1) {
          if (this.opticalCut() > 0) {
            Stack({ alignContent: Alignment.Top }) {
              this.opticalSurface(0.45 * Math.max(0, Math.min(1, this.upperLightGain)))
            }.width(this.widthVp()).height(this.opticalCut())
              .position({ x: 0, y: 0 }).clip(true).hitTestBehavior(HitTestMode.None)
          }
          if (this.opticalCut() < this.heightVp()) {
            Stack({ alignContent: Alignment.Bottom }) {
              this.opticalSurface(0.45)
            }.width(this.widthVp()).height(this.heightVp() - this.opticalCut())
              .position({ x: 0, y: this.opticalCut() }).clip(true).hitTestBehavior(HitTestMode.None)
          }
        } else {
          this.opticalSurface(0.45)
        }
      }
      if (this.emulatorLightPreview && this.levelLight && this.vertical && this.immersiveEnabled) {
        UpperLightPreview({ surfaceWidth: this.widthVp(), surfaceHeight: this.heightVp(),
          liquidY: this.opticalCut(), gain: this.upperLightGain,
          intensity: this.chosen && this.lightEnabled ? this.lightIntensity : 0 })
      }
      Stack({ alignContent: this.vertical ? Alignment.Bottom : Alignment.Start }) {
        // Only the complete track is rounded. The percentage fill has a straight trailing edge.
        if (this.originalLight && this.immersiveEnabled && this.vertical && this.chosen) {
          OriginalProgress({ fill: this.uiValue, track: this.trackVp(),
            lightX: this.sourceX(), lightY: this.sourceY(),
            intensity: this.lightEnabled ? this.lightIntensity : 0 })
        } else {
        ProgressFill({ fillWidth: this.uiValue, trackWidth: this.trackVp(),
          shellWidth: this.vertical ? this.heightVp() : this.widthVp(), vertical: this.vertical,
          surfaceHighlight: this.immersiveEnabled && this.vertical && !this.levelLight,
          chosen: this.chosen, lightX: this.sourceX(), lightY: this.sourceY(),
          intensity: this.lightEnabled ? this.lightIntensity : 0 })
        }
      }.width(this.innerWidthVp()).height(this.innerHeightVp()).borderRadius(32).clip(true)
        .scale({ x: this.innerZoomX, y: this.innerZoomY })
        .hitTestBehavior(HitTestMode.None)
      if (this.showParticles && this.particlesEnabled) {
        Stack() {
          FirmwareParticles({ surfaceWidth: this.widthVp(), surfaceHeight: this.heightVp(),
            horizontal: !this.vertical, uiValue: this.uiValue,
            opacityValue: this.particleOpacity, vx: this.vertical ? 0 : this.velocity,
            vy: this.vertical ? this.velocity : 0, fields: this.fields,
            sliderRate: this.sliderRate })
        }.width(this.widthVp()).height(this.heightVp()).padding(2).borderRadius(32).clip(true)
          .hitTestBehavior(HitTestMode.None)
      }
      // The shell's reflection and icon are above fill and particles.
      if (!this.immersiveEnabled) {
        SurfaceLight({ surfaceWidth: this.vertical ? this.heightVp() : this.widthVp(), vertical: this.vertical,
          lightX: this.sourceX(), lightY: this.sourceY(),
          intensity: this.lightEnabled ? this.lightIntensity : 0 })
      }
    }
    // A transformed child clip becomes elliptical. This final, unscaled shell clip
    // constrains fill, highlights and particles before the whole volume-button scale.
    .width(this.widthVp()).height(this.heightVp()).borderRadius(32).clip(true)
    .attributeModifier(new ImmersiveShellMaterial(false, this.immersiveStyle,
      this.lightEnabled, this.jellyCaptureMode || this.nativeJellyPrepared || this.nativeJellyActive,
      !this.immersiveEnabled))
    .id(this.jellySnapshotId).renderGroup(true)
  }

  build() {
    Stack() {
      Stack() { this.surface() }.opacity(this.jellyShowing ? 0 : 1)
      if (this.hasJellyMotion()) {
        NodeContainer(this.jellyRenderer).width(this.widthVp() + 72).height(this.heightVp() + 72)
          .position({ x: -36, y: -36 }).hitTestBehavior(HitTestMode.None)
      }
      // Native distortion transforms the complete live subtree. In the mesh
      // fallback the sun is drawn by the RenderNode; keep the speaker live
      // above that node instead of hiding it or drawing a sun in its place.
      if (this.kind === 'volume' && this.headphones) {
        Image(headphoneIconResource(this.headphoneIcon))
          .id('player-volume-headphones-icon').width(28).height(28)
          .fillColor(this.chosen ? '#000000' : '#FFFFFF')
          .position({ x: 18, y: this.heightVp() - 46 })
          .hitTestBehavior(HitTestMode.None)
      } else {
        FirmwareIcon({ value: this.value, kind: this.kind, sliderLength: this.trackVp(), ink: this.chosen })
          .position({ x: this.vertical ? 18 : (this.widthVp() - this.trackVp()) / 2 + 10,
            y: this.vertical ? this.heightVp() - (this.heightVp() - this.trackVp()) / 2 - 38 : 18 })
          .opacity(this.jellyShowing && this.kind !== 'volume' ? 0 : 1)
      }
    }.width(this.widthVp()).height(this.heightVp())
    .scale({ x: this.jellyShowing ? 1 : this.buttonZoom,
      y: this.jellyShowing ? 1 : this.buttonZoom })
    .borderRadius(32)
    .attributeModifier(new ImmersiveShellMaterial(this.immersiveEnabled, this.immersiveStyle,
      this.lightEnabled && !this.originalLight && !this.levelLight, false, false))
    .attributeModifier(new OriginalPointSource(!this.emulatorLightPreview && (this.originalLight || this.levelLight) && this.immersiveEnabled && this.lightEnabled,
      this.sourceX(), this.sourceY(), this.lightIntensity * this.nativeLightGain, 110))
    .visualEffect(this.nativeJellyEffect)
    .accessibilityText(this.kind === 'volume' ? '音量' : '亮度')
    .accessibilityDescription(`${Math.round(this.value * 100)}%`)
    .onTouch((event: TouchEvent) => {
      if (!this.touchEnabled) { return; }
      if (event.type === TouchType.Down) {
        this.directContact = true;
        this.cancelAdjustmentTimer();
        if (event.touches.length > 0) {
          this.lightX = event.touches[0].x;
          this.lightY = event.touches[0].y;
        }
        this.contact().down();
      } else if (event.type === TouchType.Move && event.touches.length > 0) {
        this.followLight(event.touches[0].x, event.touches[0].y);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.directContact = false;
        this.contact().up();
        this.end();
      }
    })
    .priorityGesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({ direction: this.vertical ? PanDirection.Vertical : PanDirection.Horizontal,
          distance: 2, fingers: 1 })
          .onActionStart((event: GestureEvent) => { this.begin(event); })
          .onActionUpdate((event: GestureEvent) => { this.move(event); })
          .onActionEnd(() => { if (this.touchEnabled) { this.end(); } })
          .onActionCancel(() => { if (this.touchEnabled) { this.end(); } }),
        TapGesture().onAction((event: GestureEvent) => { this.tap(event); })
      )
    )
  }
}
