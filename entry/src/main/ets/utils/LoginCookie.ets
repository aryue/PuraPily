/** Convert Cookie / Set-Cookie strings into a request Cookie header without decoding values. */
export function mergeLoginCookies(sources: string[]): string {
  const values = new Map<string, string>();
  const attributes = ['path', 'domain', 'expires', 'max-age', 'samesite', 'secure', 'httponly', 'partitioned'];
  for (const source of sources) {
    // A comma in Expires is not a cookie separator; a following name=value is.
    const entries = source.split(/\r?\n|,(?=\s*[^\s;,=]+=)/);
    for (const entry of entries) {
      for (const pair of entry.split(';')) {
        const eq = pair.indexOf('=');
        if (eq <= 0) continue;
        const name = pair.substring(0, eq).trim();
        const value = pair.substring(eq + 1).trim();
        if (!attributes.includes(name.toLowerCase()) && value && value !== 'undefined') {
          values.set(name, value);
        }
      }
    }
  }
  const parts: string[] = [];
  values.forEach((value, name) => parts.push(`${name}=${value}`));
  return parts.join('; ');
}

export function hasLoginSession(cookie: string): boolean {
  return /(?:^|;\s*)SESSDATA=([^;\s]+)/.test(cookie);
}

export function loginHeaderValues(headers: Record<string, Object>, name: string): string[] {
  const values: string[] = [];
  if (!headers) return values;
  for (const key of Object.keys(headers)) {
    if (key.toLowerCase() !== name.toLowerCase()) continue;
    const value = headers[key];
    if (typeof value === 'string') values.push(value);
    else if (Array.isArray(value)) {
      for (const item of value as Object[]) if (typeof item === 'string') values.push(item);
    }
  }
  return values;
}

/** Native cookies can omit cookies that are still present in Set-Cookie. */
export function loginCookiesFromResponse(cookies: string, headers: Record<string, Object>): string {
  return mergeLoginCookies([cookies || '', ...loginHeaderValues(headers, 'set-cookie')]);
}

/** Cookie values in the redirect query are already encoded for transport. */
export function loginCookiesFromUrl(url: string): string {
  const start = url.indexOf('?');
  if (start < 0) return '';
  const allowed = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5', 'sid'];
  const parts: string[] = [];
  for (const param of url.substring(start + 1).split('#')[0].split('&')) {
    const eq = param.indexOf('=');
    if (eq < 0) continue;
    const name = decodeURIComponent(param.substring(0, eq));
    const value = param.substring(eq + 1);
    if (allowed.includes(name) && value) parts.push(`${name}=${value}`);
  }
  return parts.join('; ');
}

export type LoginVerificationState = 'authenticated' | 'rejected' | 'unavailable';

export function classifyLoginVerification(httpCode: number, apiCode: number,
  isLogin: boolean): LoginVerificationState {
  if (httpCode !== 200) return 'unavailable';
  if (apiCode === -101 || (apiCode === 0 && !isLogin)) return 'rejected';
  return apiCode === 0 && isLogin ? 'authenticated' : 'unavailable';
}
