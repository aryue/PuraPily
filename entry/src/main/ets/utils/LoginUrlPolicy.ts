/** Validate the actual authority, never substring-match a login URL. */
export function isBilibiliHttpsUrl(value: string): boolean {
  return /^https:\/\/(?:[a-z0-9-]+\.)*bilibili\.com(?::443)?(?:[/?#]|$)/i.test(value);
}

/** Web QR tickets are also redeemed by this specific official passport host. */
export function isLoginRedirectUrl(value: string): boolean {
  return isBilibiliHttpsUrl(value) || /^https:\/\/passport\.biligame\.com(?::443)?(?:[/?#]|$)/i.test(value);
}

export function resolveLoginRedirect(current: string, location: string): string {
  if (/^https:\/\//i.test(location)) return location;
  if (location.startsWith('//')) return `https:${location}`;
  const origin = current.match(/^https:\/\/[^/?#]+/i)?.[0] || '';
  if (location.startsWith('/')) return origin + location;
  const path = current.split('#')[0].split('?')[0];
  if (location.startsWith('?')) return path + location;
  return path.substring(0, path.lastIndexOf('/') + 1) + location;
}
