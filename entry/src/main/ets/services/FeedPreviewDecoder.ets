import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import type { FeedPlaybackSession } from './FeedPlaybackSession';
import { logInfo, logWarn } from '../utils/Logger';

/** Ignore sparse logos or subtitles on an otherwise black opening frame. */
export async function feedStillHasPicture(frame: image.PixelMap): Promise<boolean> {
  try {
    const info = frame.getImageInfoSync();
    if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888 &&
      info.pixelFormat !== image.PixelMapFormat.BGRA_8888) return true;
    const stride = frame.getBytesNumberPerRow();
    const buffer = new ArrayBuffer(frame.getPixelBytesNumber());
    await frame.readPixelsToBuffer(buffer);
    const pixels = new Uint8Array(buffer);
    let visible = 0;
    for (let y = 1; y <= 20; y++) {
      const row = Math.floor(y * info.size.height / 21) * stride;
      for (let x = 1; x <= 20; x++) {
        const i = row + Math.floor(x * info.size.width / 21) * 4;
        if (Math.max(pixels[i], pixels[i + 1], pixels[i + 2]) > 28 && ++visible >= 32) return true;
      }
    }
    return false;
  } catch (error) {
    logWarn('[ReferenceFeed] still pixel read failed', error);
    return true;
  }
}

async function waitForFeedPicture(session: FeedPlaybackSession, current: () => boolean): Promise<image.PixelMap | null> {
  if (deviceInfo.abiList.includes('x86_64')) return null;
  const stopAt = Date.now() + 700;
  while (current() && !session.reserved && Date.now() < stopAt) {
    let frame: image.PixelMap | null = null;
    try {
      frame = await image.createPixelMapFromSurfaceWithTransformation(session.surfaceId, true);
      if (await feedStillHasPicture(frame)) {
        const picture = frame;
        frame = null;
        return picture;
      }
    } catch (_) {
      return null;
    } finally {
      frame?.release().catch(() => {});
    }
    await new Promise<void>(resolve => setTimeout(resolve, 70));
  }
  return null;
}

export interface FeedPreviewPicture {
  aspect: number;
  frame: image.PixelMap | null;
}

/** Prepare a paused frame, then wait for the decoder and the inactive Surface to settle. */
export async function prepareFeedPreviewDecoder(session: FeedPlaybackSession, aspect: number, cookie: string,
  current: () => boolean): Promise<FeedPreviewPicture | null> {
  let picture: image.PixelMap | null = null;
  try {
    let decoderAspect = 0;
    session.onSizeChanged = (real: number) => {
      decoderAspect = real;
      logInfo(`[ReferenceFeed] decoder ${session.id} size aspect=${real.toFixed(4)} declared=${aspect.toFixed(4)}`);
    };
    // Capture a complete frame; the Image applies the destination crop exactly once.
    const ready = await session.prepare(media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT, cookie,
      async () => { picture = await waitForFeedPicture(session, current); });
    if (!ready || !current()) return null;
    // ⭐ 先等解码器把画幅真正切过来再抓图：预热 surface 会沿用上一条（可能是横屏）的 buffer
    //   尺寸，竖屏视频这时被输出到横屏 buffer 里，抓下来的就是**已经被拉伸的画面**，
    //   切过去先显示这张静帧 → 用户看到「首帧拉伸」，等 Surface 出真帧才恢复。
    //   横切横时 videoSizeChange 不会触发，最多等 400ms 就照抓，不拖慢预热。
    //   400ms 而不是 120ms：实测 120ms 时竖屏视频仍拿到上一条横屏的 buffer（1320x743），
    //   抓出来的静帧比例 1.7766 与画幅 0.5625 不符，切到 Surface 必然跳一次。
    const aspectDeadline = Date.now() + 400;
    while (Date.now() < aspectDeadline) {
      if (decoderAspect > 0 && Math.abs(decoderAspect / aspect - 1) <= 0.02) break;
      await new Promise<void>((resolve) => setTimeout(resolve, 16));
      if (!current()) return null;
    }
    // Allow the inactive Surface to adopt the decoded aspect before taking its fallback frame.
    await new Promise<void>((resolve) => setTimeout(resolve, 32));
    if (!current()) return null;
    const result: FeedPreviewPicture = { aspect: decoderAspect || session.aspectRatio, frame: picture };
    picture = null;
    return result;
  } finally {
    if (picture) (picture as image.PixelMap).release().catch(() => {});
  }
}

/**
 * 将复用 Surface 抓图还原为真实画幅。
 * AVPlayer 的 SCALED_ASPECT 会补黑边，按画幅裁边；IJK 整帧铺满 buffer，
 * 即使 buffer 沿用上一条比例也须保留完整内容，通过缩放还原，不能当黑边裁掉。
 */
export async function cropStillToPicture(pm: image.PixelMap, contentRatio: number,
  stretchedBuffer: boolean = false): Promise<image.PixelMap> {
  try {
    const info = pm.getImageInfoSync();
    const w = info.size?.width || 0;
    const h = info.size?.height || 0;
    if (!w || !h || !(contentRatio > 0)) return pm;
    const canvasRatio = w / h;
    if (Math.abs(canvasRatio / contentRatio - 1) <= 0.02) return pm;
    let rw = w;
    let rh = h;
    if (contentRatio < canvasRatio) rw = Math.max(2, Math.min(w, Math.round(h * contentRatio)));
    else rh = Math.max(2, Math.min(h, Math.round(w / contentRatio)));
    if (rw === w && rh === h) return pm;
    // IJK 的 videoScaleType 不参与原生渲染：整帧铺满 buffer，并没有 FIT 黑边。
    // 复用旧比例 buffer 时须还原整张画面的比例，裁中央会丢掉真实内容。
    if (stretchedBuffer) {
      await pm.scale(rw / w, rh / h);
      logInfo(`[ReferenceFeed] still restore ${w}x${h} -> ${rw}x${rh} real=${contentRatio.toFixed(4)}`);
      return pm;
    }
    // PixelMap.crop 是原地裁切（Promise<void>），返回同一张位图。
    await pm.crop({
      x: Math.round((w - rw) / 2), y: Math.round((h - rh) / 2),
      size: { width: rw, height: rh }
    });
    logInfo(`[ReferenceFeed] still crop ${w}x${h} -> ${rw}x${rh} canvas=${canvasRatio.toFixed(4)} real=${contentRatio.toFixed(4)}`);
    return pm;
  } catch (error) {
    logWarn(`[ReferenceFeed] still crop failed: ${error}`);
    return pm;
  }
}
