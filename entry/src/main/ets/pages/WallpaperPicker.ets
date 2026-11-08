// System photo picker grants access to the selected image only. Keep the copy in filesDir.
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { PageWallpaperService } from '../services/PageWallpaperService';

export namespace WallpaperPicker {
  export type WallpaperChangeCallback = (uri: string) => void | Promise<void>;
  export async function pickAndSetWallpaper(context: common.Context, onSuccess: WallpaperChangeCallback): Promise<void> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const result = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (!result.photoUris.length) return;
    const destination = context.filesDir + '/page_wallpaper_local_' + Date.now() + '.img';
    const source = fileIo.openSync(result.photoUris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(source.fd);
      if (stat.size <= 0 || stat.size > 30 * 1024 * 1024) throw new Error('请选择 30 MB 以内的图片');
      fileIo.copyFileSync(source.fd, destination);
      await PageWallpaperService.getInstance().validateFile(destination);
      await onSuccess(destination);
    } catch (error) {
      try { fileIo.unlinkSync(destination); } catch (_) {}
      throw error as Error;
    } finally { fileIo.closeSync(source); }
  }
}
