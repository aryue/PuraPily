export function homeArtworkRetained(mask: number, channel: number): boolean {
  return channel < 0 || (mask & (1 << channel)) !== 0;
}
