import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { clearLoginCredentials } from '../utils/CredentialStore';
import { setErrorLogContext, clearErrorLog } from '../utils/ErrorLogCollector';
import { ImGrpcService } from './ImGrpcService';
import { clearFollowedMidsCache, resetRecommendIndex } from '../api/BilibiliApi';

export async function logoutSession(context: common.Context): Promise<void> {
  const clearing = clearLoginCredentials(context);
  ImGrpcService.resetSession();
  clearFollowedMidsCache();
  resetRecommendIndex();
  // Remove files left by older versions when the user signs out.
  setErrorLogContext(context);
  clearErrorLog();
  try {
    // Synchronous cookie clearing happens before any await can allow another login page to open.
    webview.WebCookieManager.clearAllCookiesSync();
    webview.WebviewController.setWebDebuggingAccess(false);
  } finally {
    await clearing;
  }
}
