export function publishHomeScrollOffset(offset: number): void {
  const normalizedOffset = Math.max(0, offset);
  if ((AppStorage.get<number>('homeScrollOffset') ?? -1) === normalizedOffset) return;
  AppStorage.setOrCreate('homeScrollOffset', normalizedOffset);
}
