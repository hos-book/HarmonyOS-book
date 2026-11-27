import { NativeSubtitleUnit, NativeSubtitleCue, NativeSubtitleChunk, createSubtitleDictionary,
  joinSubtitleUnits, punctuateSubtitleUnits, buildSubtitleTimeline } from 'libhsda_core.so';

export const SUBTITLE_CHUNK_MS: number = 12000;
export const SUBTITLE_CONTEXT_MS: number = 2000;
export const SUBTITLE_MODEL_VERSION: string = 'zipformer-ctc-zh-20250703-ct-punct-v6';

export class SubtitleCue implements NativeSubtitleCue {
  id: string = '';
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';
  continues: boolean = false;

  constructor(id: string = '', startMs: number = 0, endMs: number = 0, text: string = '') {
    this.id = id; this.startMs = startMs; this.endMs = endMs; this.text = text;
  }
}

export class SubtitleChunk implements NativeSubtitleChunk {
  index: number = 0;
  endMs: number = 0;
  cues: SubtitleCue[] = [];
  units: SubtitleUnit[] = [];
  annotated: SubtitleUnit[] = [];
}

export class SubtitleCache {
  version: string = SUBTITLE_MODEL_VERSION;
  chunks: SubtitleChunk[] = [];
}

export class SubtitleUnit implements NativeSubtitleUnit {
  text: string = '';
  startMs: number = 0;
  endMs: number = 0;
  sentenceEnd: boolean = false;
  constructor(text: string = '', startMs: number = 0, endMs: number = 0) {
    this.text = text; this.startMs = startMs; this.endMs = endMs;
  }
}

class SubtitleTokenSpan {
  text: string;
  first: number;
  last: number;
  constructor(text: string, first: number, last: number) {
    this.text = text; this.first = first; this.last = last;
  }
}

/** Punctuation predicts sentence ends; timestamps only align the original recognized words. */
export class SubtitleSegmenter {
  private static protectedWords: Object | undefined = undefined;
  // sherpa-onnx 1.13.3 bbpe.cc: byte values 127 through 255, in order.
  private static byteAlphabet: string = 'ĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľŁłŃńŅņŇňŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžƀƁƂƃƄƅƆƇƈƉƊƋƌƍƎƏƐƑƒƓƔƕƖƗƘƙƚƛƜƝƞƟƠơƢƣƤƥƦ';

  static setProtectedWords(words: string[]): void {
    SubtitleSegmenter.protectedWords = createSubtitleDictionary(words);
  }

  private static nativeUnits(units: NativeSubtitleUnit[]): SubtitleUnit[] {
    return units.map((unit: NativeSubtitleUnit): SubtitleUnit => {
      const result = new SubtitleUnit(unit.text, unit.startMs, unit.endMs);
      result.sentenceEnd = unit.sentenceEnd;
      return result;
    });
  }

  private static tokenText(spans: SubtitleTokenSpan[]): string {
    return spans.map((span: SubtitleTokenSpan): string => span.text).join('').replace(/\s/g, '').toLowerCase();
  }

  private static byteBpeSpans(tokens: string[]): SubtitleTokenSpan[] {
    const spans: SubtitleTokenSpan[] = [];
    let text = '';
    let first = 0;
    let remaining = 0;
    let point = 0;
    let minimum = 0;
    let previousByte = -1;
    for (let i = 0; i < tokens.length; i++) {
      for (const char of Array.from(tokens[i])) {
        if (char === '▁') {
          if (previousByte > 32 && previousByte < 127) { text += ' '; previousByte = 32; }
          continue;
        }
        const code = char.charCodeAt(0);
        const mapped = SubtitleSegmenter.byteAlphabet.indexOf(char);
        const byte = char === '⁇' ? 32 : mapped >= 0 ? mapped + 127 :
          code >= 256 && code < 288 ? code - 256 : code;
        previousByte = byte;
        if (remaining > 0 && byte >= 128 && byte < 192) {
          point = (point << 6) | (byte & 63);
          remaining--;
          if (remaining === 0 && point >= minimum && point <= 0x10FFFF && (point < 0xD800 || point > 0xDFFF)) {
            text += String.fromCodePoint(point);
          }
          continue;
        }
        // Recognition can emit partial UTF-8. Resume at the next complete character.
        remaining = 0;
        if (text.length === 0) first = i;
        if (byte < 128) {
          text += String.fromCharCode(byte);
        } else if (byte >= 194 && byte < 224) {
          point = byte & 31; remaining = 1; minimum = 0x80;
        } else if (byte >= 224 && byte < 240) {
          point = byte & 15; remaining = 2; minimum = 0x800;
        } else if (byte >= 240 && byte < 245) {
          point = byte & 7; remaining = 3; minimum = 0x10000;
        }
      }
      // Keep UTF-8 characters spanning several tokens in one timed group.
      if (remaining === 0) {
        if (text.length > 0) spans.push(new SubtitleTokenSpan(text, first, i));
        text = ''; first = i + 1;
      }
    }
    return spans;
  }

  static units(index: number, endMs: number, text: string, tokens: string[], times: number[],
    start: number = index * SUBTITLE_CHUNK_MS): SubtitleUnit[] {
    const end = endMs;
    if (!text.trim() || end <= start) return [];
    const normalized = text.replace(/[\s�]/g, '').toLowerCase();
    let spans = tokens.map((token: string, position: number): SubtitleTokenSpan =>
      new SubtitleTokenSpan(token.replace(/▁/g, ' '), position, position));
    if (SubtitleSegmenter.tokenText(spans) !== normalized) spans = SubtitleSegmenter.byteBpeSpans(tokens);
    let aligned = SubtitleSegmenter.tokenText(spans) === normalized && tokens.length === times.length && times.length > 0;
    for (let i = 0; i < times.length; i++) {
      if (!Number.isFinite(times[i]) || times[i] < 0 || (i > 0 && times[i] < times[i - 1])) aligned = false;
    }
    const result: SubtitleUnit[] = [];
    if (aligned) {
      for (const span of spans) {
        const begin = Math.min(end, start + times[span.first] * 1000);
        const finish = Math.min(end, start + times[span.last] * 1000 + 400,
          span.last + 1 < times.length ? start + times[span.last + 1] * 1000 : end);
        const chars = Array.from(span.text);
        for (let j = 0; j < chars.length; j++) {
          if (finish > begin) result.push(new SubtitleUnit(chars[j], begin + (finish - begin) * j / chars.length,
            begin + (finish - begin) * (j + 1) / chars.length));
        }
      }
    } else {
      // Approximate character timing uses the actual decoded audio span.
      const chars = Array.from(text.replace(/�/g, '').trim());
      for (let i = 0; i < chars.length; i++) {
        result.push(new SubtitleUnit(chars[i], start + (end - start) * i / chars.length,
          start + (end - start) * (i + 1) / chars.length));
      }
    }
    return result;
  }

  static owned(index: number, units: SubtitleUnit[]): SubtitleUnit[] {
    const start = index * SUBTITLE_CHUNK_MS;
    const end = start + SUBTITLE_CHUNK_MS;
    return units.filter((unit: SubtitleUnit): boolean => unit.startMs >= start && unit.startMs < end)
      .map((unit: SubtitleUnit): SubtitleUnit => {
        const copy = new SubtitleUnit(unit.text, unit.startMs, Math.min(end, unit.endMs));
        copy.sentenceEnd = unit.sentenceEnd;
        return copy;
      });
  }

  /** Join adjacent recognition passes at shared words inside their acoustic overlap. */
  static join(previous: SubtitleUnit[], current: SubtitleUnit[], boundaryMs: number): SubtitleUnit[] {
    return SubtitleSegmenter.nativeUnits(joinSubtitleUnits(previous, current, boundaryMs));
  }

  static text(units: SubtitleUnit[]): string {
    return units.map((unit: SubtitleUnit): string => unit.text).join('');
  }

  static punctuate(units: SubtitleUnit[], output: string, finalChunk: boolean): SubtitleUnit[] {
    return SubtitleSegmenter.nativeUnits(punctuateSubtitleUnits(units, output, finalChunk));
  }

  static cues(index: number, units: SubtitleUnit[], finalChunk: boolean): SubtitleCue[] {
    const owned = units.filter((unit: SubtitleUnit): boolean =>
      unit.startMs >= index * SUBTITLE_CHUNK_MS && unit.startMs < (index + 1) * SUBTITLE_CHUNK_MS);
    const cues: SubtitleCue[] = [];
    let text = '';
    let first = 0;
    for (let i = 0; i < owned.length; i++) {
      text += owned[i].text;
      const last = i === owned.length - 1;
      if (!owned[i].sentenceEnd && !last) continue;
      const cue = new SubtitleCue(`chunk-${index}-${cues.length}`, owned[first].startMs, owned[i].endMs, text.trim());
      cue.continues = !owned[i].sentenceEnd && !(last && finalChunk);
      if (cue.text) cues.push(cue);
      text = ''; first = i + 1;
    }
    return cues;
  }

  static timeline(chunks: SubtitleChunk[]): SubtitleCue[] {
    chunks.sort((left: SubtitleChunk, right: SubtitleChunk): number => left.index - right.index);
    return buildSubtitleTimeline(chunks, SubtitleSegmenter.protectedWords)
      .map((cue: NativeSubtitleCue): SubtitleCue => {
        const result = new SubtitleCue(`subtitle-${cue.startMs}`, cue.startMs, cue.endMs, cue.text);
        result.continues = cue.continues;
        return result;
      });
  }
}

export class SubtitleWorkerRequest {
  shutdown: boolean = false;
  initialize: boolean = false;
  background: boolean = false;
  chunks: SubtitleChunk[] = [];
  previewChunk: SubtitleChunk | null = null;
  protectedWords: string[] = [];
  requestId: number = 0;
  modelDir: string = '';
  audioPath: string = '';
  chunk: number = 0;
  previous: SubtitleChunk | null = null;
  prefix: SubtitleUnit[] = [];
  finalChunk: boolean = false;
  preview: boolean = false;
  positionMs: number = 0;
}

export class SubtitleWorkerResponse {
  requestId: number = 0;
  initialized: boolean = false;
  background: boolean = false;
  cues: SubtitleCue[] = [];
  cacheText: string = '';
  chunk: SubtitleChunk = new SubtitleChunk();
  error: string = '';
  previous: SubtitleChunk | null = null;
  preview: boolean = false;
}

/** Media time is authoritative. Silence must not highlight the previous cue forever. */
export class SubtitleTimeline {
  static activeIndex(cues: SubtitleCue[], positionMs: number): number {
    let low = 0;
    let high = cues.length - 1;
    let candidate = -1;
    while (low <= high) {
      const middle = Math.floor((low + high) / 2);
      if (cues[middle].startMs <= positionMs) { candidate = middle; low = middle + 1; }
      else high = middle - 1;
    }
    return candidate >= 0 && positionMs < cues[candidate].endMs ? candidate : -1;
  }
}
