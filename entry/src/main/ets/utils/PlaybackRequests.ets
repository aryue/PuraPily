/** 达到目标的结果先返回；否则等待全部结果供调用方比较画质并回退。 */
export function firstPreferredResults<T>(requests: Promise<T>[], empty: T,
  preferred: (value: T) => boolean, usable?: (value: T) => boolean): Promise<T[]> {
  return new Promise<T[]>((resolve) => {
    const results: T[] = requests.map(() => empty);
    let remaining = requests.length;
    let resolved = false;
    let timer: number = -1;
    const finish = (): void => {
      if (resolved) return;
      resolved = true;
      clearTimeout(timer);
      resolve(results.slice());
    };
    if (remaining === 0) { resolve(results); return; }
    requests.forEach((request: Promise<T>, index: number) => {
      request.catch(() => empty).then((value: T) => {
        results[index] = value;
        remaining--;
        if (!resolved && (preferred(value) || remaining === 0)) {
          finish();
        } else if (!resolved && timer === -1 && usable?.(value)) {
          // A downgraded but playable reply must not wait for an unresponsive
          // competing API indefinitely. Give the requested rendition a short grace.
          timer = setTimeout(finish, 800);
        }
      });
    });
  });
}
