import { common } from '@kit.AbilityKit';
import { pollTvQrCodeStatusApi, QrCodeStatus } from '../api/BilibiliApi';
import { hasLoginSession, mergeLoginCookies } from '../utils/LoginCookie';
import { loginCredentialRevision, saveLoginCredentials } from '../utils/CredentialStore';
import { logWarn } from '../utils/Logger';

export interface TvAuthorizationState {
  status: QrCodeStatus;
  remainingSeconds: number;
  message: string;
}

/** Phone confirmation can finish after the QR page is closed. The authorization owns its poller. */
export class TvQrAuthorization {
  private static generation: number = 0;
  private static timer: number = -1;
  private static listener?: (state: TvAuthorizationState) => void;

  static cancel(session: number): void {
    if (session !== TvQrAuthorization.generation) return;
    if (TvQrAuthorization.timer !== -1) clearInterval(TvQrAuthorization.timer);
    TvQrAuthorization.timer = -1;
    TvQrAuthorization.listener = undefined;
    TvQrAuthorization.generation++;
    AppStorage.setOrCreate('biliTvAuthorizationStatus', 'idle');
  }

  static detach(session: number): void {
    if (session === TvQrAuthorization.generation) TvQrAuthorization.listener = undefined;
  }

  static begin(context: common.Context, authCode: string,
    listener: (state: TvAuthorizationState) => void): number {
    TvQrAuthorization.cancel(TvQrAuthorization.generation);
    const generation = TvQrAuthorization.generation;
    const revision = loginCredentialRevision();
    const expiresAt = Date.now() + 180000;
    let busy = false;
    let finished = false;
    let lastPollAt = 0;
    let status = QrCodeStatus.NOT_SCANNED;
    TvQrAuthorization.listener = listener;
    AppStorage.setOrCreate('biliTvAuthorizationStatus', 'pending');

    const publish = (next: QrCodeStatus, remaining: number, message: string): void => {
      if (generation !== TvQrAuthorization.generation) return;
      const current = TvQrAuthorization.listener;
      if (current) current({ status: next, remainingSeconds: remaining, message: message });
    };
    const finish = (next: QrCodeStatus, message: string): void => {
      if (generation !== TvQrAuthorization.generation) return;
      finished = true;
      if (TvQrAuthorization.timer !== -1) clearInterval(TvQrAuthorization.timer);
      TvQrAuthorization.timer = -1;
      AppStorage.setOrCreate('biliTvAuthorizationStatus', next === QrCodeStatus.SUCCESS ? 'success' : 'error');
      publish(next, 0, message);
      TvQrAuthorization.listener = undefined;
    };
    const poll = async (): Promise<void> => {
      if (finished || generation !== TvQrAuthorization.generation) return;
      if (revision !== loginCredentialRevision()) { TvQrAuthorization.cancel(generation); return; }
      const now = Date.now();
      const remaining = Math.max(0, Math.ceil((expiresAt - now) / 1000));
      if (!remaining) {
        // Allow a pending response to deliver an already approved token, but never revive an expired scan state.
        if (!busy) finish(QrCodeStatus.EXPIRED, '二维码已过期，请重新获取');
        else publish(QrCodeStatus.EXPIRED, 0, '二维码已过期，正在等待最后一次授权响应');
        return;
      }
      publish(status, remaining, status === QrCodeStatus.SCANNED ? '已扫码，请在手机上确认登录' : '请使用B站客户端扫描二维码');
      if (busy || now - lastPollAt < 2000) return;
      busy = true;
      lastPollAt = now;
      try {
        const result = await pollTvQrCodeStatusApi(authCode);
        if (generation !== TvQrAuthorization.generation || revision !== loginCredentialRevision()) return;
        if (result.status === QrCodeStatus.SUCCESS) {
          const cookie = mergeLoginCookies([result.cookies]);
          if (!hasLoginSession(cookie) || !result.accessKey) {
            finish(QrCodeStatus.ERROR, 'TV 授权响应不完整，请重新获取二维码');
            return;
          }
          await saveLoginCredentials(context, cookie, result.accessKey, true, revision);
          if (generation !== TvQrAuthorization.generation || loginCredentialRevision() !== revision + 1) return;
          AppStorage.setOrCreate('refreshHomeFlag', (AppStorage.get<number>('refreshHomeFlag') || 0) + 1);
          finish(QrCodeStatus.SUCCESS, 'TV 登录成功！');
        } else if (result.status === QrCodeStatus.ERROR || result.status === QrCodeStatus.EXPIRED) {
          finish(result.status, result.message || '二维码已过期，请重新获取');
        } else if (Date.now() >= expiresAt) {
          finish(QrCodeStatus.EXPIRED, '二维码已过期，请重新获取');
        } else {
          if (result.status === QrCodeStatus.SCANNED) status = result.status;
          publish(status, Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000)),
            status === QrCodeStatus.SCANNED ? '已扫码，请在手机上确认登录' : '请使用B站客户端扫描二维码');
        }
      } catch (_) {
        logWarn('[TV授权] 保存或接收授权失败');
        finish(QrCodeStatus.ERROR, 'TV 授权保存失败，请重新获取二维码');
      } finally { busy = false; }
    };
    TvQrAuthorization.timer = setInterval(() => { poll(); }, 1000);
    poll();
    return generation;
  }
}
