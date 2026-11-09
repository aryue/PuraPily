/** Device-name rules supplied by the user. Unknown names keep the generic icon. */
export function headphoneIconName(name: string): string {
  const normalized = name.toLowerCase().replace(/[_-]/g, ' ');
  if (/\bfree\s*buds\s*pro(?:\s*\d+)?\b/.test(normalized)) return 'earphone_16643';
  if (/\bfree\s*buds\s*studio\b/.test(normalized)) return 'earphone_roc';
  if (/\bfree\s*arc(?:\s*\d+)?\b/.test(normalized)) return 'earphone_16661';
  if (/\bfree\s*clip(?:\s*\d+)?\b/.test(normalized)) return 'earphone_16659';
  if (/(?:glasses|eyewear)/i.test(normalized)) return 'earphone_5888';
  if (/\bfree\s*buds\s*\d+\s*i\b/.test(normalized)) return 'earphone_16644';
  if (/\bfree\s*buds\s*(2|3|4|7)\b/.test(normalized)) return 'earphone_16646';
  if (/\bfree\s*buds\s*(5|6)\b/.test(normalized)) return 'earphone_16660';
  return 'headphones_fill';
}

export function headphoneIconResource(name: string): Resource {
  switch (name) {
    case 'earphone_16643': return $r('app.media.earphone_16643');
    case 'earphone_16646': return $r('app.media.earphone_16646');
    case 'earphone_16660': return $r('app.media.earphone_16660');
    case 'earphone_roc': return $r('app.media.earphone_roc');
    case 'earphone_16661': return $r('app.media.earphone_16661');
    case 'earphone_5888': return $r('app.media.earphone_5888');
    case 'earphone_16659': return $r('app.media.earphone_16659');
    case 'earphone_16644': return $r('app.media.earphone_16644');
    default: return $r('app.media.headphones_fill');
  }
}
