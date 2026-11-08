/** 在实际测得的标题中心之间插值，适应系统字体与字号变化。 */
export function tabIndicatorCenter(centers: number[], position: number): number {
  const clamped = Math.max(0, Math.min(centers.length - 1, position));
  const left = Math.floor(clamped);
  const right = Math.min(left + 1, centers.length - 1);
  return centers[left] + (centers[right] - centers[left]) * (clamped - left);
}
