import { inspectOriginalMaterial } from './OriginalMaterialRuntime';

export class OriginalMaterialProbe {
  private static inspected: boolean = false;
  static inspect(instance: CommonAttribute): void {
    if (OriginalMaterialProbe.inspected) { return; }
    OriginalMaterialProbe.inspected = true;
    try {
      console.info(`CCLab original material capabilities ${JSON.stringify(inspectOriginalMaterial(instance))}`);
    } catch (error) {
      console.warn(`CCLab original material inspection unavailable: ${error}`);
    }
  }
}
