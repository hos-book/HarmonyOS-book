/** 0: local HTML text, 1: local entities, 2: HTML encode, 3: HTML decode, 4: EPUB XML. */
export const transformText: (input: string, operation: number) => string;
export const transformHtmlBounded: (input: string, encode: boolean, timeoutMs: number) => string;
export const replaceEpubImages: (text: string, prefix: string, images: string[]) => string;
/** Call from an existing background task. */
export const cleanHtmlBatch: (input: string[]) => string[];
/** Returns UTF-16 code unit offsets, including overlapping matches. */
export const searchOffsets: (text: string, keyword: string, limit: number) => Uint32Array;
export const detectWhiteBorder: (pixels: Uint8Array, width: number, height: number) => number[];
export const encodeWave: (samples: Float32Array, sampleRate: number) => ArrayBuffer;
/** Background ZIP reads; each entry supplies offset, compressed size, expanded size and method. */
export const readEpubEntries: (fd: number, fileSize: number, entries: number[]) => Promise<ArrayBuffer[]>;
/** Native asynchronous work; each handle belongs to one sequential import. */
export const createMobiHuff: (records: Uint8Array[], capacity: number) => Promise<Object>;
export const decodeMobiBatch: (records: Uint8Array[], capacity: number,
  huff: Object | undefined) => Promise<Uint8Array[]>;
export const releaseMobiHuff: (huff: Object) => void;
/** INDX/TAGX parsing and fragment assembly on native asynchronous work. */
export const rebuildKf8: (skeletons: Uint8Array[], fragments: Uint8Array[],
  body: Uint8Array) => Promise<Uint8Array[]>;
