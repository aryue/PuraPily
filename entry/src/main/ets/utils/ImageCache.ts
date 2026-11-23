import { image } from '@kit.ImageKit';
import { http } from '@kit.NetworkKit';

interface CachedImage {
  bitmap: image.PixelMap;
  bytes: number;
}

const MAX_CACHE_BYTES = 12 * 1024 * 1024;
const MAX_CACHE_ITEMS = 96;
const cache = new Map<string, CachedImage>();
const pending = new Map<string, Promise<void>>();
let cacheBytes = 0;
let generation = 0;

export function predecodeImage(url: string): Promise<void> {
  if (!url || getCachedPixelMap(url)) return Promise.resolve();
  const existing = pending.get(url);
  if (existing) return existing;

  const job: Promise<void> = decodeImage(url, generation).finally(() => {
    if (pending.get(url) === job) pending.delete(url);
  });
  pending.set(url, job);
  return job;
}

async function decodeImage(url: string, expectedGeneration: number): Promise<void> {
  try {
    const request = http.createHttp();
    let response: http.HttpResponse;
    try {
      response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 5000,
        readTimeout: 10000,
        usingProtocol: http.HttpProtocol.HTTP1_1,
        header: {
          'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'Mozilla/5.0'
        }
      });
    } finally {
      request.destroy();
    }
    if (expectedGeneration !== generation || response.responseCode !== 200 || !response.result) return;

    const source = image.createImageSource(response.result as ArrayBuffer);
    try {
      const bitmap = await source.createPixelMap();
      let retained = false;
      try {
        const bytes = bitmap.getPixelBytesNumber();
        if (expectedGeneration !== generation || bytes <= 0 || bytes > MAX_CACHE_BYTES) return;
        cache.set(url, { bitmap, bytes });
        cacheBytes += bytes;
        retained = true;
        while (cache.size > MAX_CACHE_ITEMS || cacheBytes > MAX_CACHE_BYTES) {
          const oldest = cache.keys().next().value as string;
          const retired = cache.get(oldest)!;
          cacheBytes -= retired.bytes;
          // A mounted Image can still be borrowing this bitmap.
          cache.delete(oldest);
        }
      } finally {
        if (!retained) await bitmap.release();
      }
    } finally {
      await source.release();
    }
  } catch (_e) {
    // Predecoding is optional. The next request can retry.
  }
}

export function getCachedPixelMap(url: string): image.PixelMap | undefined {
  const entry = cache.get(url);
  if (!entry) return undefined;
  cache.delete(url);
  cache.set(url, entry);
  return entry.bitmap;
}

export function clearImageCache(): void {
  generation++;
  pending.clear();
  cache.clear();
  cacheBytes = 0;
}
