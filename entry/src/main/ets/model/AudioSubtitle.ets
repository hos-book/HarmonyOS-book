export const SUBTITLE_CHUNK_MS: number = 12000;
export const SUBTITLE_MODEL_VERSION: string = 'zipformer-ctc-zh-20250703-ct-punct-v4';

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

/** Punctuation predicts sentence ends; timestamps only align the original recognized words. */
export class SubtitleSegmenter {
  private static protectedWords: Set<string> = new Set();

  static setProtectedWords(words: string[]): void {
    SubtitleSegmenter.protectedWords = new Set(words.map((word: string): string => word.trim()).filter((word: string): boolean =>
      /^[\u4e00-\u9fff]{2,12}$/.test(word)).slice(0, 50000));
  }
  private static plain(text: string): string {
    return text.replace(/[\s，。！？；：、,.!?;:"“”‘’「」『』（）()]/g, '').toLowerCase();
  }

  static units(index: number, endMs: number, text: string, tokens: string[], times: number[],
    start: number = index * SUBTITLE_CHUNK_MS): SubtitleUnit[] {
    const end = Math.min(endMs, (index + 1) * SUBTITLE_CHUNK_MS);
    if (!text.trim() || end <= start) return [];
    const pieces = tokens.map((token: string): string => token.replace(/▁/g, ' '));
    let aligned = pieces.join('').replace(/\s/g, '').toLowerCase() === text.replace(/\s/g, '').toLowerCase() &&
      pieces.length === times.length && times.length > 0;
    for (let i = 0; i < times.length; i++) {
      if (!Number.isFinite(times[i]) || times[i] < 0 || (i > 0 && times[i] < times[i - 1])) aligned = false;
    }
    const result: SubtitleUnit[] = [];
    if (aligned) {
      for (let i = 0; i < pieces.length; i++) {
        const begin = Math.min(end, start + times[i] * 1000);
        const finish = Math.min(end, begin + 400, i + 1 < times.length ? start + times[i + 1] * 1000 : end);
        const chars = Array.from(pieces[i]);
        for (let j = 0; j < chars.length; j++) {
          if (finish > begin) result.push(new SubtitleUnit(chars[j], begin + (finish - begin) * j / chars.length,
            begin + (finish - begin) * (j + 1) / chars.length));
        }
      }
    } else {
      // No word alignment is invented: this fallback has approximate character timing within the known audio span.
      const chars = Array.from(text.trim());
      for (let i = 0; i < chars.length; i++) {
        result.push(new SubtitleUnit(chars[i], start + (end - start) * i / chars.length,
          start + (end - start) * (i + 1) / chars.length));
      }
    }
    return result;
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
