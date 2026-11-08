// Recover 8vp of title spacing for the camera safe area without growing the header.
/** The home search row is shared across channels; its visible height may be zero. */
export const HOME_SEARCH_ROW_HEIGHT: number = 44;
export const HOME_CHANNEL_ROW_HEIGHT: number = 36;
// Popular page baseline; includes the spacing below the channel labels.
export const HOME_CONTENT_EXPANDED_HEIGHT: number = 84;

/** All home channels use the popular page clearance, including a collapsed search row. */
export function homeHeaderContentHeight(searchHeight: number): number {
  return HOME_CONTENT_EXPANDED_HEIGHT - HOME_SEARCH_ROW_HEIGHT +
    Math.max(0, Math.min(HOME_SEARCH_ROW_HEIGHT, searchHeight));
}

export function homeHeaderTopInset(statusHeight: number, hideStatusBar: boolean,
  searchHeight: number): number {
  return (hideStatusBar ? 0 : Math.max(0, statusHeight)) +
    homeHeaderContentHeight(searchHeight);
}
