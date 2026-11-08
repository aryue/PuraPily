/** 消息接口混用秒、毫秒、微秒、纳秒以及北京时间字符串。统一为秒。 */
export function messageTimestamp(value: Object): number {
  if (typeof value !== 'number' && typeof value !== 'string') { return 0; }
  const raw = String(value).trim();
  if (!raw) { return 0; }
  let ts = Number(raw);
  if (!Number.isFinite(ts)) {
    let date = raw.replace(' ', 'T');
    // 系统通知的无时区日期按服务端北京时间解释。
    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(date)) { date += '+08:00'; }
    ts = Date.parse(date) / 1000;
  } else if (ts >= 1e17) { ts /= 1e9; }
  else if (ts >= 1e14) { ts /= 1e6; }
  else if (ts >= 1e11) { ts /= 1e3; }
  return Number.isFinite(ts) && ts > 0 ? Math.floor(ts) : 0;
}

export function messageImageUrl(value: string): string {
  const url = value.trim();
  if (url.startsWith('//')) { return 'https:' + url; }
  return url.startsWith('http://') ? 'https://' + url.substring(7) : url;
}

export function formatMessageTime(ts: number, compact: boolean = false, nowMs: number = Date.now()): string {
  const seconds = messageTimestamp(ts);
  if (seconds <= 0) { return ''; }
  const date = new Date(seconds * 1000);
  const now = new Date(nowMs);
  const hm = `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  if (date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth() && date.getDate() === now.getDate()) { return hm; }
  const md = `${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  const day = date.getFullYear() === now.getFullYear() ? md : `${date.getFullYear()}-${md}`;
  return compact ? day : `${day} ${hm}`;
}
