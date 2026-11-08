/** Shared neutral surfaces; cards remain distinct when page wallpaper is disabled. */
export function pageBackgroundColor(dark: boolean): string {
  return dark ? '#101114' : '#F1F2F4';
}

export function ordinaryCardColor(dark: boolean): string {
  return dark ? '#17181A' : '#FFFFFF';
}
