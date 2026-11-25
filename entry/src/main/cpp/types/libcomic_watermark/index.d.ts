export const load: (path: string) => Promise<ArrayBuffer>;
export const process: (path: string, rgba: ArrayBuffer, width: number, height: number) => Promise<ArrayBuffer>;
