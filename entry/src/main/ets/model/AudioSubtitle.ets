export const SUBTITLE_CHUNK_MS: number = 12000;
export const SUBTITLE_CONTEXT_MS: number = 2000;
export const SUBTITLE_MODEL_VERSION: string = 'zipformer-ctc-zh-20250703-ct-punct-v6';

export class SubtitleCue {
  id: string = '';
  startMs: number = 0;
  endMs: number = 0;
  text: string = '';
  continues: boolean = false;

  constructor(id: string = '', startMs: number = 0, endMs: number = 0, text: string = '') {
    this.id = id; this.startMs = startMs; this.endMs = endMs; this.text = text;
  }
}

export class SubtitleChunk {
  index: number = 0;
  endMs: number = 0;
  cues: SubtitleCue[] = [];
  units: SubtitleUnit[] = [];
  annotated: SubtitleUnit[] = [];
}

export class SubtitleUnit {
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
  private static protectedWords: Set<string> = new Set();
  // sherpa-onnx 1.13.3 bbpe.cc: byte values 127 through 255, in order.
  private static byteAlphabet: string = 'ĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľŁłŃńŅņŇňŊŋŌōŎŏŐőŒœŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽžƀƁƂƃƄƅƆƇƈƉƊƋƌƍƎƏƐƑƒƓƔƕƖƗƘƙƚƛƜƝƞƟƠơƢƣƤƥƦ';

  static setProtectedWords(words: string[]): void {
    SubtitleSegmenter.protectedWords = new Set(words.map((word: string): string => word.trim()).filter((word: string): boolean =>
      /^[\u4e00-\u9fff]{2,12}$/.test(word)).slice(0, 50000));
  }
  private static plain(text: string): string {
    return text.replace(/[\s，。！？；：、,.!?;:"“”‘’「」『』（）()]/g, '').toLowerCase();
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
    const overlapStart = boundaryMs - SUBTITLE_CONTEXT_MS;
    let left = -1;
    let right = -1;
    let longest = 0;
    let nearest = Number.MAX_VALUE;
    for (let i = 0; i < previous.length; i++) {
      if (previous[i].startMs < overlapStart || !SubtitleSegmenter.plain(previous[i].text)) continue;
      for (let j = 0; j < current.length && current[j].startMs < boundaryMs; j++) {
        let length = 0;
        while (i + length < previous.length && j + length < current.length &&
          SubtitleSegmenter.plain(previous[i + length].text) === SubtitleSegmenter.plain(current[j + length].text) &&
          Math.abs(previous[i + length].startMs - current[j + length].startMs) <= 600) length++;
        const distance = Math.abs(previous[i].startMs - current[j].startMs);
        if (length > longest || (length > 0 && length === longest && distance < nearest)) {
          longest = length; nearest = distance;
          left = i + Math.floor(length / 2); right = j + Math.floor(length / 2);
        }
      }
    }
    if (left >= 0) {
      const before = previous.slice(0, left).map((unit: SubtitleUnit): SubtitleUnit =>
        new SubtitleUnit(unit.text, unit.startMs, Math.min(unit.endMs, current[right].startMs)));
      return before.filter((unit: SubtitleUnit): boolean => unit.endMs > unit.startMs).concat(current.slice(right));
    }
    return previous.concat(current.filter((unit: SubtitleUnit): boolean => unit.startMs >= boundaryMs));
  }

  static text(units: SubtitleUnit[]): string {
    return units.map((unit: SubtitleUnit): string => unit.text).join('');
  }

  static punctuate(units: SubtitleUnit[], output: string, finalChunk: boolean): SubtitleUnit[] {
    const original = SubtitleSegmenter.text(units);
    const words = units.filter((unit: SubtitleUnit): boolean => SubtitleSegmenter.plain(unit.text).length > 0);
    // Punctuation is allowed to add separators, never to change, omit or hallucinate words.
    const matched = SubtitleSegmenter.plain(original) === SubtitleSegmenter.plain(output);
    let text = matched ? output : original;
    // CT-Transformer forcibly adds a terminal period to every call. A window end is not a sentence end.
    if (!finalChunk && matched) text = text.replace(/[。！？.!?]+(["”’」』]*)\s*$/, '$1');
    const result: SubtitleUnit[] = [];
    let cursor = 0;
    const chars = Array.from(text);
    for (let position = 0; position < chars.length; position++) {
      const char = chars[position];
      if (SubtitleSegmenter.plain(char).length === 0) {
        if (result.length > 0) {
          const last = result[result.length - 1];
          last.text += char;
          const decimal = char === '.' && position > 0 && position + 1 < chars.length &&
            /[0-9]/.test(chars[position - 1]) && /[0-9]/.test(chars[position + 1]);
          if (/[。！？!?]/.test(char) || (char === '.' && !decimal)) last.sentenceEnd = true;
        }
      } else if (cursor < words.length) {
        const source = words[cursor++];
        result.push(new SubtitleUnit(source.text, source.startMs, source.endMs));
      }
    }
    return result;
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
    const result: SubtitleCue[] = [];
    let run: SubtitleUnit[] = [];
    let previousIndex = -2;
    for (const chunk of chunks) {
      if (chunk.index !== previousIndex + 1 || chunk.cues.length === 0) {
        result.push(...SubtitleSegmenter.displayCues(run)); run = [];
      }
      if (chunk.annotated && chunk.annotated.length > 0) {
        for (const unit of chunk.annotated) {
          const copy = new SubtitleUnit(unit.text, unit.startMs, unit.endMs);
          copy.sentenceEnd = unit.sentenceEnd; run.push(copy);
        }
      } else {
        // Legacy/empty alignment fallback retains cue timing and boundaries.
        for (const cue of chunk.cues) {
          const chars = Array.from(cue.text);
          for (let i = 0; i < chars.length; i++) {
            const unit = new SubtitleUnit(chars[i], cue.startMs + (cue.endMs - cue.startMs) * i / chars.length,
              cue.startMs + (cue.endMs - cue.startMs) * (i + 1) / chars.length);
            unit.sentenceEnd = i === chars.length - 1 && !cue.continues; run.push(unit);
          }
        }
      }
      previousIndex = chunk.index;
    }
    result.push(...SubtitleSegmenter.displayCues(run));
    return result;
  }

  /** Repair punctuation inside known idioms after joining windows, before deciding display boundaries. */
  private static displayCues(units: SubtitleUnit[]): SubtitleCue[] {
    if (units.length === 0) return [];
    const letters: string[] = [];
    const positions: number[] = [];
    for (let i = 0; i < units.length; i++) {
      const word = SubtitleSegmenter.plain(units[i].text);
      if (word.length > 0) { letters.push(word); positions.push(i); }
    }
    for (let i = 0; i < letters.length; i++) {
      let word = '';
      for (let j = i; j < Math.min(letters.length, i + 12); j++) {
        word += letters[j];
        if (!SubtitleSegmenter.protectedWords.has(word)) continue;
        for (let k = positions[i]; k < positions[j]; k++) {
          // Only remove predicted separators; preserve letters, spaces and quotation marks.
          units[k].text = units[k].text.replace(/[，。！？；：、,.!?;:]/g, '');
          units[k].sentenceEnd = false;
        }
      }
    }
    const cues: SubtitleCue[] = [];
    let first = 0;
    for (let i = 0; i < units.length; i++) {
      if (!units[i].sentenceEnd && i !== units.length - 1) continue;
      SubtitleSegmenter.splitLongSentence(units.slice(first, i + 1), cues);
      first = i + 1;
    }
    return cues;
  }

  private static splitLongSentence(units: SubtitleUnit[], cues: SubtitleCue[]): void {
    let first = 0;
    while (first < units.length) {
      let end = units.length - 1;
      // 42 is a soft display budget, never a character-cut position.
      if (units.length - first > 42) {
        let best = -1;
        let distance = Number.MAX_VALUE;
        for (let i = first + 7; i < units.length - 8; i++) {
          if (!/[，,；;]/.test(units[i].text)) continue;
          const candidate = Math.abs(i - first + 1 - 28);
          if (candidate < distance) { best = i; distance = candidate; }
        }
        if (best >= 0) end = best;
      }
      const text = SubtitleSegmenter.text(units.slice(first, end + 1)).trim();
      if (text) {
        const cue = new SubtitleCue(`subtitle-${units[first].startMs}`, units[first].startMs, units[end].endMs, text);
        cue.continues = end === units.length - 1 && !units[end].sentenceEnd;
        cues.push(cue);
      }
      first = end + 1;
    }
  }
}

export class SubtitleWorkerRequest {
  shutdown: boolean = false;
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
