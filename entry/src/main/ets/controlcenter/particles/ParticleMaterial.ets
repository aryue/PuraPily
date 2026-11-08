import { hdsMaterial } from '@kit.UIDesignKit';

export class ParticleMaterial {
  static rate(): number {
    // Public MaterialLevel is NOT the firmware TransparencyLevel enum.
    // Its private getter is not in the public SDK. Match EnvVm's NORMAL fallback.
    try {
      console.info(`CCLab material types=${hdsMaterial.getSystemMaterialTypes().join(',')}`);
    } catch (error) {
      console.warn(`CCLab particle transparency query failed: ${error}`);
    }
    console.info('CCLab particle transparency unavailable; firmware NORMAL fallback, sliderRate=0.6');
    return 0.6;
  }
}
