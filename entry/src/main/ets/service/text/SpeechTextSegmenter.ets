import { LocalTextImage } from './LocalTextImage';
import { SpeechSynthesisSettings } from '../../model/SpeechSynthesisSettings';

export class SpeechSegment {
  start: number = 0;
  end: number = 0;
  text: string = '';
  leadingWhitespace: number = 0;
  paragraphStart: number = 0;
  paragraphEnd: number = 0;
}

/** 偏移始终对应阅读器规范化正文，分段不删除或重排原文。 */
export class SpeechTextSegmenter {
  /** 只清理合成输入；正文、段落与阅读字符偏移始终使用原文。 */
  private static spokenText(content: string, filter: boolean = true): string {
    if (!filter) return content.trim();
    return content.replace(new RegExp('\\[\\s*\\d{1,4}\\s*\\]|【\\s*\\d{1,4}\\s*】', 'g'), '')
      .replace(new RegExp('[*＊﹡※☆★◆◇■□●○◎▲△▼▽━─═\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F-\\u009F\\u200B-\\u200F\\u202A-\\u202E\\u2060-\\u206F\\uFEFF]+', 'g'), ' ')
      .replace(new RegExp('[~～_=#＃|｜]{3,}', 'g'), ' ').trim();
  }

  private static isPunctuationOnly(text: string): boolean {
    // 纯符号/表情没有可合成的文字，不能向系统或 HTTP 音色提交空音频请求。
    // Unicode 字母和数字包括中文、英文、日文等，不能简单地删除所有非中文内容。
    return !new RegExp('[\\p{L}\\p{N}]', 'u').test(text);
  }

  static split(content: string, mergeShort: boolean = false, pageEnds: number[] = [],
    filter: boolean = true, maxLength: number = 180, hardLimit: number = Number.MAX_SAFE_INTEGER): SpeechSegment[] {
    content = LocalTextImage.speechContent(content);
    const result: SpeechSegment[] = [];
    const boundaries: Set<number> = new Set<number>(pageEnds);
    let start = 0;
    let paragraphStart = 0;
    let paragraphEnd = content.indexOf('\n');
    if (paragraphEnd < 0) paragraphEnd = content.length;
    for (let i = 0; i < content.length; i++) {
      const ch = content.charAt(i);
      const boundary = boundaries.has(i + 1) || '。！？!?；;\n'.includes(ch) ||
        (ch === '.' && (i + 1 === content.length || new RegExp('\\s').test(content.charAt(i + 1))));
      // 限制单句长度，且不把 UTF-16 代理对拆开。
      const code = content.charCodeAt(i);
      const limit = i - start >= maxLength - 1 && !(code >= 0xD800 && code <= 0xDBFF);
      if (boundary || limit || i === content.length - 1) {
        let end = i + 1;
        // 连续问号和收尾标点随上一句合成，避免拆出没有语音数据的请求。
        while (end < content.length && end - start < hardLimit && !boundaries.has(end) &&
          '。！？!?；;”’」』）'.includes(content.charAt(end))) end++;
        const segment = new SpeechSegment();
        segment.start = start;
        segment.end = end;
        const raw = content.substring(start, end);
        segment.leadingWhitespace = Math.max(0, raw.search(new RegExp('\\S')));
        segment.text = SpeechTextSegmenter.spokenText(raw, filter);
        if (segment.text.length > 0 && !SpeechTextSegmenter.isPunctuationOnly(segment.text)) {
          const readStart = start + segment.leadingWhitespace;
          while (readStart >= paragraphEnd && paragraphEnd < content.length) {
            paragraphStart = paragraphEnd + 1;
            paragraphEnd = content.indexOf('\n', paragraphStart);
            if (paragraphEnd < 0) paragraphEnd = content.length;
          }
          segment.paragraphStart = paragraphStart;
          segment.paragraphEnd = paragraphEnd;
          result.push(segment);
        }
        start = end;
        i = end - 1;
      }
    }
    return mergeShort ? SpeechTextSegmenter.mergeShortSegments(content, result, pageEnds) : result;
  }

  /** HTTP 同段短句合并到约 64 字、上限约 180 字，允许附带尾部标点；不跨自然段。 */
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
    const index = segments.findIndex((segment: SpeechSegment): boolean => segment.end > offset);
    return index < 0 ? segments.length : index;
  }

  /** 同一次合成可覆盖多个自然段，位置仍对应原文；系统 PCM 单次限制 300 字。 */
  static batches(content: string, settings: SpeechSynthesisSettings, custom: boolean, pageEnds: number[] = []): SpeechSegment[] {
    const limit = Math.min(settings.maxChars, custom ? 4000 : 300);
    const segments = SpeechTextSegmenter.split(content, false, pageEnds, settings.filterSymbols, Math.min(limit - 2, 180), limit);
    const result: SpeechSegment[] = [];
    let paragraphs = 0;
    let lastParagraph = -1;
    for (const segment of segments) {
      segment.text = SpeechSynthesisSettings.replace(segment.text, settings.replacements).trim();
      if (!segment.text || SpeechTextSegmenter.isPunctuationOnly(segment.text)) continue;
      if (segment.text.length > limit) throw new Error('TTS replacement exceeds synthesis limit');
      const previous = result.length > 0 ? result[result.length - 1] : null;
      const newParagraph = segment.paragraphStart !== lastParagraph;
      const separator = newParagraph ? '\n' : (segment.leadingWhitespace > 0 ? ' ' : '');
      if (previous !== null && paragraphs + (newParagraph ? 1 : 0) <= settings.paragraphs &&
        previous.text.length + separator.length + segment.text.length <= limit &&
        !pageEnds.some((offset: number): boolean => offset > previous.start && offset < segment.end)) {
        previous.end = segment.end;
        previous.text += separator + segment.text;
        paragraphs += newParagraph ? 1 : 0;
      } else {
        result.push(segment);
        paragraphs = 1;
      }
      lastParagraph = segment.paragraphStart;
    }
    return result;
  }
}
