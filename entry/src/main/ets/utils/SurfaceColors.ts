/** Shared neutral surfaces; cards remain distinct when page wallpaper is disabled. */
export function pageBackgroundColor(dark: boolean): string {
  return dark ? '#101114' : '#F1F2F4';
}

export function ordinaryCardColor(dark: boolean): string {
  return dark ? '#17181A' : '#FFFFFF';
}

/**
 * 语义前景色（2026-11-08 深浅色对比度修复）。
 *
 * 此前大量次级文字/图标直接写死中灰（#9499A0 / #757A81 / #999999 / #888888 …），
 * 既不随主题也不随底板亮度：深色玻璃里发灰、浅色白底上更低于 WCAG AA 4.5:1，
 * 即用户反馈的「动态页浅层几乎看不清」。下面三档按深/浅底分别取值，
 * 数值全部取自项目里已经在用、且对比度达标的色值，只做收敛、不改既有观感。
 *
 * 参考底：深色 #17181A / #101114，浅色 #FFFFFF / #F1F2F4。
 * 主文字约 16:1、次级约 7~11:1、三级约 5~7:1，两套主题均 >= AA。
 *
 * ⚠️ 叠在图片、封面、视频或彩色按钮上的白字不在这里：那些底不随主题变，保持白色。
 */
export function primaryTextColor(dark: boolean): string {
  return dark ? '#F2F4F8' : '#18191C';
}

export function secondaryTextColor(dark: boolean): string {
  return dark ? '#C9CDD3' : '#50545A';
}

export function tertiaryTextColor(dark: boolean): string {
  return dark ? '#A2A7AE' : '#606773';
}
