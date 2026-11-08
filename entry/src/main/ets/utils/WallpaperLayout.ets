export class WallpaperCrop {
  zoom: number = 1;
  x: number = 0;
  y: number = 0;
}

export class LocalWallpaper {
  path: string = '';
  width: number = 1;
  height: number = 1;
  portrait: WallpaperCrop = new WallpaperCrop();
  landscape: WallpaperCrop = new WallpaperCrop();
}

export function cleanWallpaperCrop(value: WallpaperCrop): WallpaperCrop {
  const crop = new WallpaperCrop();
  crop.zoom = Number.isFinite(value?.zoom) ? Math.max(1, Math.min(4, value.zoom)) : 1;
  crop.x = Number.isFinite(value?.x) ? Math.max(-1, Math.min(1, value.x)) : 0;
  crop.y = Number.isFinite(value?.y) ? Math.max(-1, Math.min(1, value.y)) : 0;
  return crop;
}

export class WallpaperFrame {
  width: number = 0;
  height: number = 0;
  x: number = 0;
  y: number = 0;
}

// Normalized offsets use the available overflow, so preview and full-screen agree.
export function wallpaperFrame(viewWidth: number, viewHeight: number, imageWidth: number,
  imageHeight: number, crop: WallpaperCrop): WallpaperFrame {
  const frame = new WallpaperFrame();
  const safe = cleanWallpaperCrop(crop);
  const factor = Math.max(viewWidth / Math.max(1, imageWidth), viewHeight / Math.max(1, imageHeight)) * safe.zoom;
  frame.width = imageWidth * factor;
  frame.height = imageHeight * factor;
  frame.x = safe.x * Math.max(0, frame.width - viewWidth) / 2;
  frame.y = safe.y * Math.max(0, frame.height - viewHeight) / 2;
  return frame;
}
