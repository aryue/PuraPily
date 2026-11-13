export const source: (directory: string, video: string, audio: string, agent?: string, referer?: string, cookie?: string, cacheOn?: number, videoBackup?: string, audioBackup?: string, videoBps?: number, audioBps?: number, backupDelayMs?: number) => string;
export const createPlayer: (event: (type: number, first: number, second: number) => void) => number;
export const preparePlayer: (id: number, path: string, surfaceId: string, position: number) => number;
export const controlPlayer: (id: number, operation: number, value: number) => number;
export const bindPlayer: (id: number, surfaceId: string) => number;
export const releasePlayer: (id: number) => Promise<void>;
export const prewarmUrl: (url: string, agent: string, referer: string, cookie: string, bytes?: number, seekMs?: number) => number;
export const prefetchFirstRender: (directory: string, video: string, audio: string, agent?: string, referer?: string, cookie?: string) => number;
