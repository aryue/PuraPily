import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { mergeLoginCookies } from '../utils/LoginCookie';

export const WEB_INTERACTION_UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
interface DeviceResponse { code: number; data?: DeviceData; }
interface DeviceData { b_3?: string; b_4?: string; }
let deviceCookie: string = '';
let pending: Promise<string> | undefined;

async function loadDeviceCookie(): Promise<string> {
  const context = AppStorage.get<common.Context>('appContext');
  const pref = context ? await preferences.getPreferences(context, 'web_device_identity') : undefined;
  const stored = pref ? await pref.get('cookie', '') as string : '';
  if (/(?:^|;\s*)buvid3=[^;\s]+/.test(stored)) return stored;
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.bilibili.com/x/frontend/finger/spi', {
      method: http.RequestMethod.GET,
      header: { 'User-Agent': WEB_INTERACTION_UA, 'Referer': 'https://www.bilibili.com/' },
      connectTimeout: 8000, readTimeout: 8000
    });
    if (response.responseCode !== 200) throw new Error('设备标识获取失败，请稍后重试');
    const result = JSON.parse(response.result as string) as DeviceResponse;
    if (result.code !== 0 || !result.data?.b_3 || /[;\s]/.test(result.data.b_3)) {
      throw new Error('设备标识响应不完整，请稍后重试');
    }
    const cookie = mergeLoginCookies([`buvid3=${result.data.b_3}`,
      result.data.b_4 && !/[;\s]/.test(result.data.b_4) ? `buvid4=${result.data.b_4}` : '']);
    if (pref) { await pref.put('cookie', cookie); await pref.flush(); }
    return cookie;
  } finally { request.destroy(); }
}

/** Reuse server-issued identifiers; never fabricate or rotate fingerprints for each mutation. */
export async function webInteractionCookie(cookie: string): Promise<string> {
  if (/(?:^|;\s*)buvid3=[^;\s]+/.test(cookie)) return cookie;
  if (!deviceCookie) {
    if (!pending) pending = loadDeviceCookie();
    try { deviceCookie = await pending; } finally { pending = undefined; }
  }
  return mergeLoginCookies([deviceCookie, cookie]);
}
