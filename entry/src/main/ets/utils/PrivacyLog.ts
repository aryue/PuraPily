/** Keep credentials and user supplied URLs out of diagnostics, including older exported logs. */
export function redactPrivateLog(message: string): string {
  return message
    .replace(/\b(?:https?|wss?):\/\/[^\s<>"'`]+/gi, '[URL removed]')
    .replace(/(?:Cookie|Set-Cookie|Authorization|初始Cookie)\s*[:=：]\s*[^\r\n]*/gi, '[credentials removed]')
    .replace(/(["']?(?:SESSDATA|bili_jct|DedeUserID(?:__ckMd5)?|access[_-]?(?:key|token)|refresh[_-]?token|qrcode_key|auth_code|buvid[34]|csrf)["']?\s*(?:[:=：]|%3[dD])\s*["']?)[^\s,;}&"']+/gi, '$1[REDACTED]');
}
