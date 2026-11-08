/** 0 releases the request. Returns the NativeVSync result code. */
export const setRate: (rate: number) => number;

/** Whether the system has a decoder for this video MIME type. */
export const hasVideoDecoder: (mime: string) => boolean;
