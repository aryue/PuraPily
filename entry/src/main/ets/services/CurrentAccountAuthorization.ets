import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import { generateTvLoginQrCode, pollTvQrCodeStatusApi, QrCodeStatus } from '../api/BilibiliApi';
import { loginCredentialRevision, saveLoginCredentials } from '../utils/CredentialStore';
import { hasLoginSession } from '../utils/LoginCookie';

interface ConfirmResponse { code: number; }

/** Called only after the user confirms the client authorization dialog. Never used as an automatic fallback. */
export async function authorizeCurrentAccount(context: common.Context, cookie: string): Promise<void> {
  const revision = loginCredentialRevision();
  const csrf = cookie.match(/(?:^|;\s*)bili_jct=([^;]+)/)?.[1] || '';
  const mid = cookie.match(/(?:^|;\s*)DedeUserID=(\d+)/)?.[1] || '';
  if (!hasLoginSession(cookie) || !csrf || !mid) throw new Error('当前登录信息不完整，请使用扫码登录');
  const assertCurrent = (): void => {
    if (revision !== loginCredentialRevision() || cookie !== AppStorage.get<string>('biliCookie')) {
      throw new Error('账号已变化，请重新确认授权');
    }
  };
  const ticket = await generateTvLoginQrCode();
  assertCurrent();
  if (!ticket) throw new Error('生成授权请求失败，请稍后重试');
  const request = http.createHttp();
  try {
    const response = await request.request('https://passport.bilibili.com/x/passport-tv-login/h5/qrcode/confirm', {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': cookie,
        'Origin': 'https://passport.bilibili.com',
        'Referer': ticket.url,
        'User-Agent': 'Mozilla/5.0 BiliDroid/8.43.0 (bbcallen@gmail.com) os/android model/android mobi_app/android build/8430300 channel/master innerVer/8430300 osVer/15 network/2'
      },
      extraData: `auth_code=${encodeURIComponent(ticket.qrcode_key)}&csrf=${encodeURIComponent(csrf)}&scanning_type=1&build=8430300`,
      connectTimeout: 8000,
      readTimeout: 8000
    });
    assertCurrent();
    if (response.responseCode !== 200) throw new Error(`授权请求失败（HTTP ${response.responseCode}）`);
    const result = JSON.parse(response.result as string) as ConfirmResponse;
    if (result.code !== 0) throw new Error(`客户端授权被拒绝（${result.code}），请使用扫码登录`);
  } finally { request.destroy(); }
  for (let attempt = 0; attempt < 5; attempt++) {
    assertCurrent();
    const result = await pollTvQrCodeStatusApi(ticket.qrcode_key);
    assertCurrent();
    if (result.status === QrCodeStatus.SUCCESS) {
      const returnedMid = result.cookies.match(/(?:^|;\s*)DedeUserID=(\d+)/)?.[1] || '';
      if (!result.accessKey || returnedMid !== mid) throw new Error('授权账号校验未通过，请使用扫码登录');
      // Preserve the active Web session, attaching only the verified same-account client token.
      await saveLoginCredentials(context, cookie, result.accessKey, true, revision);
      AppStorage.setOrCreate('refreshHomeFlag', (AppStorage.get<number>('refreshHomeFlag') || 0) + 1);
      return;
    }
    if (result.status === QrCodeStatus.ERROR || result.status === QrCodeStatus.EXPIRED) {
      throw new Error(result.message || '客户端授权已失效，请重试');
    }
    await new Promise<void>((resolve) => { setTimeout(resolve, 500); });
  }
  throw new Error('暂未收到客户端授权结果，请重新授权');
}
