/** 0: local HTML, 1: local entities, 2: HTML encode, 3: HTML decode, 4: EPUB XML, 5: reader text, 6: speech text. */
export const transformText: (input: string, operation: number) => string;
export const transformHtmlBounded: (input: string, encode: boolean, timeoutMs: number) => string;
/** Fixed 50 ms mailbox polling interval for the existing taskpool worker. */
export const waitRuleHostInterval: () => void;
/** Clean HTML and resolve image placeholders within one native call. */
export const cleanEpubHtml: (html: string, prefix: string, images: string[]) => string;
/** Call from an existing background task. */
export const cleanHtmlBatch: (input: string[]) => string[];
/** Returns UTF-16 code unit offsets, including overlapping matches. */
export const searchOffsets: (text: string, keyword: string, limit: number) => Uint32Array;
export const detectWhiteBorder: (pixels: Uint8Array, width: number, height: number) => number[];
export const encodeWave: (samples: Float32Array, sampleRate: number) => ArrayBuffer;
export class NativeSpeechStreamStatus {
  rate: number;
  channels: number;
  queued: number;
  duration: number;
  done: boolean;
  error: string;
}
export const createSpeechStream: () => Object;
export const feedSpeechStream: (stream: Object, data: ArrayBuffer, sampleRate: number) => void;
export const finishSpeechStream: (stream: Object) => void;
export const startSpeechStream: (stream: Object) => void;
export const cancelSpeechStream: (stream: Object) => void;
export const readSpeechPcm: (stream: Object, buffer: ArrayBuffer) => number;
export const speechStreamStatus: (stream: Object) => NativeSpeechStreamStatus;
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

export class TxtImportSection {
  title: string;
  content: string;
  preserveChapter: boolean;
}
/** One sequential import owns the parser and awaits each background feed before release. */
export const createTxtImporter: (title: string) => Object;
export const feedTxtImporter: (parser: Object, content: string, finalChunk: boolean) => Promise<TxtImportSection[]>;
export const releaseTxtImporter: (parser: Object) => void;

export class NativeRankingBook {
  id: string;
  platformId: string;
  title: string;
  author: string;
  narrator: string;
  coverUrl: string;
  originalUrl: string;
  intro: string;
  contentType: number;
  rank: number;
  rating: number;
}
export class NativeRankingResult {
  books: NativeRankingBook[];
  fetchedAt: number;
}
/** Parses downloaded ranking pages and cached responses on native asynchronous work. */
export const parseRanking: (platform: string, boardId: string, body: string, glyphs: string,
  cached: boolean, now: number) => Promise<NativeRankingResult>;

export class ReaderDisplay {
  text: string;
  indents: number[];
}
export const indentReaderText: (content: string, hiddenPrefix: number) => ReaderDisplay;
/** Start/end UTF-16 pairs for the existing selector engine's same-tag pattern. */
export const sourceTagPairs: (content: string, tag: string) => number[];

export interface NativeSpeechSegment {
  text: string;
  start: number;
  end: number;
  leadingWhitespace: number;
  paragraphStart: number;
  paragraphEnd: number;
}
export const splitSpeechText: (content: string, boundaries: number[], filter: boolean,
  maxLength: number, hardLimit: number) => NativeSpeechSegment[];

export interface NativeSubtitleUnit {
  text: string;
  startMs: number;
  endMs: number;
  sentenceEnd: boolean;
}
export interface NativeSubtitleCue {
  text: string;
  startMs: number;
  endMs: number;
  continues: boolean;
}
export interface NativeSubtitleChunk {
  index: number;
  annotated: NativeSubtitleUnit[];
  cues: NativeSubtitleCue[];
}
export const createSubtitleDictionary: (words: string[]) => Object;
export const joinSubtitleUnits: (previous: NativeSubtitleUnit[], current: NativeSubtitleUnit[],
  boundaryMs: number) => NativeSubtitleUnit[];
export const punctuateSubtitleUnits: (units: NativeSubtitleUnit[], output: string,
  finalChunk: boolean) => NativeSubtitleUnit[];
export const buildSubtitleTimeline: (chunks: NativeSubtitleChunk[], dictionary: Object | undefined) => NativeSubtitleCue[];
