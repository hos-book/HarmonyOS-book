export const load: (path: string, mindir: boolean) => Promise<ArrayBuffer>;
export const process: (path: string, rgba: ArrayBuffer, width: number, height: number,
  requestId: number) => Promise<ArrayBuffer>;
export const cancel: (requestId: number) => void;
export const progress: (requestId: number) => number[];
export const release: () => Promise<ArrayBuffer>;
