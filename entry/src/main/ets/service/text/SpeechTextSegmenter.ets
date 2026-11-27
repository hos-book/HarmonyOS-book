import { LocalTextImage } from './LocalTextImage';
import { SpeechSynthesisSettings } from '../../model/SpeechSynthesisSettings';
import { NativeSpeechSegment, splitSpeechText, transformText } from 'libhsda_core.so';

export class SpeechSegment implements NativeSpeechSegment {
  start: number = 0;
  end: number = 0;
  text: string = '';
  leadingWhitespace: number = 0;
  paragraphStart: number = 0;
  paragraphEnd: number = 0;
}

/** Segment positions share the reader's normalized UTF-16 coordinate space. */
export class SpeechTextSegmenter {
  private static readonly SPOKEN_CHARACTER: RegExp = new RegExp('[\\p{L}\\p{N}]', 'u');

  private static spokenText(content: string): string {
    return transformText(content, 6);
  }

  private static isPunctuationOnly(text: string): boolean {
    return !SpeechTextSegmenter.SPOKEN_CHARACTER.test(text);
  }

  static split(content: string, mergeShort: boolean = false, pageEnds: number[] = [],
    filter: boolean = true, maxLength: number = 180, hardLimit: number = Number.MAX_SAFE_INTEGER): SpeechSegment[] {
    const native = splitSpeechText(content, pageEnds, filter, maxLength, Math.min(hardLimit, content.length + 1));
    const result: SpeechSegment[] = [];
    for (const value of native) {
      if (SpeechTextSegmenter.isPunctuationOnly(value.text)) continue;
      const segment = new SpeechSegment();
      segment.start = value.start;
      segment.end = value.end;
      segment.text = value.text;
      segment.leadingWhitespace = value.leadingWhitespace;
      segment.paragraphStart = value.paragraphStart;
      segment.paragraphEnd = value.paragraphEnd;
      result.push(segment);
    }
    return mergeShort ? SpeechTextSegmenter.mergeShortSegments(LocalTextImage.speechContent(content), result, pageEnds) : result;
  }

  private static mergeShortSegments(content: string, segments: SpeechSegment[], pageEnds: number[]): SpeechSegment[] {
    const result: SpeechSegment[] = [];
    for (const segment of segments) {
      const previous = result.length > 0 ? result[result.length - 1] : null;
      const punctuation = SpeechTextSegmenter.isPunctuationOnly(segment.text);
      if (previous !== null && previous.paragraphStart === segment.paragraphStart &&
        !pageEnds.some((offset: number): boolean => offset > previous.start && offset < segment.end) &&
        (previous.text.length < 64 || punctuation) && segment.end - previous.start <= (punctuation ? 196 : 180)) {
        previous.end = segment.end;
        previous.text = SpeechTextSegmenter.spokenText(content.substring(previous.start, previous.end));
      } else if (!punctuation) {
        result.push(segment);
      }
    }
    return result;
  }

  static indexAt(segments: SpeechSegment[], offset: number): number {
    let low = 0;
    let high = segments.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (segments[middle].end > offset) high = middle;
      else low = middle + 1;
    }
    return low;
  }

  /** Synthesis batches retain provider limits, replacements, paragraph counts and quick-start behavior. */
  static batches(content: string, settings: SpeechSynthesisSettings, custom: boolean, pageEnds: number[] = [],
    roleBoundaries: number[] = []): SpeechSegment[] {
    const limit = Math.min(settings.maxChars, custom && roleBoundaries.length === 0 ? 4000 : 300);
    const boundaries = pageEnds.concat(roleBoundaries);
    const segments = SpeechTextSegmenter.split(content, false, boundaries, settings.filterSymbols,
      limit - 2, limit);
    const result: SpeechSegment[] = [];
    const startOffset = pageEnds.length > 0 ? Math.max(...pageEnds) : 0;
    let firstSpoken = false;
    let protectFirst = false;
    let paragraphs = 0;
    let lastParagraph = -1;
    for (const segment of segments) {
      segment.text = SpeechSynthesisSettings.replace(segment.text, settings.replacements).trim();
      if (!segment.text || SpeechTextSegmenter.isPunctuationOnly(segment.text)) continue;
      if (segment.text.length > limit) throw new Error('TTS replacement exceeds synthesis limit');
      const previous = result.length > 0 ? result[result.length - 1] : null;
      const newParagraph = segment.paragraphStart !== lastParagraph;
      const separator = newParagraph ? '\n' : (segment.leadingWhitespace > 0 ? ' ' : '');
      const first = custom && settings.quickStart && !firstSpoken && segment.end > startOffset;
      if (segment.end > startOffset) firstSpoken = true;
      if (!first && !protectFirst && previous !== null && paragraphs + (newParagraph ? 1 : 0) <= settings.paragraphs &&
        previous.text.length + separator.length + segment.text.length <= limit &&
        !boundaries.some((offset: number): boolean => offset > previous.start && offset < segment.end)) {
        previous.end = segment.end;
        previous.text += separator + segment.text;
        paragraphs += newParagraph ? 1 : 0;
      } else {
        result.push(segment);
        paragraphs = 1;
      }
      protectFirst = first;
      lastParagraph = segment.paragraphStart;
    }
    return result;
  }
}
