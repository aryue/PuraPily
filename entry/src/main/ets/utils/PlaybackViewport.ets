/** The portrait detail panel stops at a screen-wide 16:9 viewport. */
export function portraitMinimumHeight(width: number): number {
  return width * 9 / 16;
}

export function portraitDetailBaseHeight(width: number, height: number, aspect: number): number {
  return Math.max(portraitMinimumHeight(width), Math.min(height * 0.52, width / Math.max(0.2, aspect)));
}

export function portraitPanelDragOffset(offset: number, minimum: number): number {
  return Math.max(minimum, offset > 110 ? 110 + Math.min(50, (offset - 110) * 0.25) : offset);
}

/** The canvas keeps its resting dimensions while the detail panel is dragged. */
export function portraitDanmakuCanvasHeight(height: number, safeTop: number, baseHeight: number,
  inset: number): number {
  const resting = Math.min(Math.max(1, height - safeTop), Math.max(1, baseHeight));
  return Math.max(1, resting - inset);
}

export function portraitDanmakuTrackHeight(canvasHeight: number, visibleHeight: number, inset: number): number {
  return Math.min(canvasHeight, Math.max(1, visibleHeight - inset));
}

export function portraitMediaDimension(width: number, areaHeight: number, aspect: number,
  contained: boolean, cropProgress: number | null, horizontal: boolean): number {
  const ratio = Math.max(0.2, aspect);
  const fittedWidth = Math.max(1, Math.min(width, areaHeight * ratio));
  const fitted = horizontal ? fittedWidth : fittedWidth / ratio;
  const full = horizontal ? Math.max(1, width) : areaHeight;
  if (cropProgress !== null) return fitted + (full - fitted) * cropProgress;
  return contained ? fitted : full;
}

export function feedCommentHeight(height: number): number {
  return Math.max(100, height * 0.34);
}

export function feedMediaTop(width: number, height: number, aspect: number, contained: boolean): number {
  const mediaHeight = contained ? Math.min(height, width / Math.max(0.2, aspect)) : height;
  return Math.max(0, height * (aspect >= 1 ? 0.4 : 0.5) - mediaHeight / 2);
}

export function feedCommentMediaTop(width: number, height: number, safeTop: number, aspect: number,
  contained: boolean, progress: number): number {
  const start = feedMediaTop(width, height, aspect, contained);
  const area = feedCommentHeight(height);
  const end = safeTop + Math.max(0, area - Math.min(area, width / Math.max(0.2, aspect))) / 2;
  return start + (end - start) * progress;
}

export function feedCommentMediaDimension(width: number, height: number, aspect: number,
  contained: boolean, progress: number, horizontal: boolean): number {
  const ratio = Math.max(0.2, aspect);
  const commentHeight = feedCommentHeight(height);
  const start = horizontal ? (contained ? Math.min(width, height * ratio) : width)
    : (contained ? Math.min(height, width / ratio) : height);
  const end = horizontal ? Math.min(width, commentHeight * ratio) : Math.min(commentHeight, width / ratio);
  return start + (end - start) * progress;
}
/** Normalize the remaining entry animation after taking over an in-flight gesture. */
export function fullscreenEntryProgress(progress: number, start: number): number {
  if (start >= 1) return 1;
  return Math.min(1, Math.max(0, (progress - start) / (1 - start)));
}

export function fullscreenViewportExtent(full: number, normal: number, snapshot: number,
  direction: number, progress: number, start: number): number {
  if (direction === 1) return Math.max(1, snapshot + (full - snapshot) * fullscreenEntryProgress(progress, start));
  if (direction === 2) return Math.max(1, full + (normal - full) * (1 - progress));
  return Math.max(1, full);
}

export function fullscreenSurfaceExtent(target: number, snapshot: number, fullscreen: boolean,
  direction: number, progress: number, start: number): number {
  if (!fullscreen || direction === 0) return Math.max(1, target);
  const fraction = direction === 1 ? fullscreenEntryProgress(progress, start) : progress;
  return direction === 1 ? Math.max(1, snapshot + (target - snapshot) * fraction) :
    Math.max(1, target + (snapshot - target) * fraction);
}

export function fullscreenCornerRadius(full: number, normal: number, fullscreen: boolean,
  direction: number, progress: number, start: number): number {
  if (!fullscreen) return normal;
  if (direction === 1) return normal + (full - normal) * fullscreenEntryProgress(progress, start);
  if (direction === 2) return normal + (full - normal) * Math.min(1, Math.max(0, progress));
  return full;
}

