import { common } from '@kit.AbilityKit';
import { Book, Chapter } from '../model/Book';
import { ReadingSession } from '../model/ReadingSession';
import { JianjianBookContext, JianjianChatRoute, JianjianCitation, JianjianExcerpt } from '../model/JianjianAi';
import { ReadingSessionService } from './ReadingSessionService';
import { OnlineTextContentCache } from './text/OnlineTextContentCache';
import { LocalTextImage } from './text/LocalTextImage';

class ReadRange {
  chapterIndex: number = 0;
  start: number = 0;
  end: number = 0;
}

class EvidenceItem {
  reference: string = '';
  chapter: string = '';
  text: string = '';
}

export class JianjianBookContextService {
  static matches(book: Book, route: JianjianChatRoute): boolean {
    return book.contentType === 'text' && book.id === route.bookId && book.sourceUrl === route.sourceUrl &&
      (book.bookUrl || book.id) === (route.bookUrl || route.bookId);
  }

  /** Cache existence never proves a chapter was read. Only recorded text intervals are eligible. */
  static ranges(book: Book, route: JianjianChatRoute, sessions: ReadingSession[]): ReadRange[] {
    if (!JianjianBookContextService.matches(book, route) || !Number.isSafeInteger(route.chapterIndex) ||
      !Number.isSafeInteger(route.charOffset) || route.chapterIndex < 0 || route.charOffset < 0) return [];
    const ranges: ReadRange[] = [];
    for (const session of sessions) {
      if (!['reading', 'tts'].includes(session.kind) || session.start.bookId !== book.id || session.end.bookId !== book.id ||
        session.start.chapterIndex !== session.end.chapterIndex || session.start.chapterId !== session.end.chapterId) continue;
      const index = session.end.chapterIndex;
      const chapter = book.chapters[index];
      if (!Number.isSafeInteger(index) || index < 0 || index > route.chapterIndex || !chapter ||
        chapter.id !== session.end.chapterId ||
        (session.end.chapterUrl && session.end.chapterUrl !== (chapter.originSourceValue || chapter.source.value))) continue;
      const start = session.start.position;
      const end = Math.min(session.end.position, index === route.chapterIndex ? route.charOffset : session.end.position);
      if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end <= start) continue;
      const range = new ReadRange();
      range.chapterIndex = index; range.start = start; range.end = end;
      ranges.push(range);
    }
    ranges.sort((a: ReadRange, b: ReadRange): number => a.chapterIndex - b.chapterIndex || a.start - b.start);
    const merged: ReadRange[] = [];
    for (const range of ranges) {
      const last = merged[merged.length - 1];
      if (last && last.chapterIndex === range.chapterIndex && range.start <= last.end) last.end = Math.max(last.end, range.end);
      else merged.push(range);
    }
    return merged;
  }

  static async collect(context: common.Context, book: Book, route: JianjianChatRoute,
    alive: () => boolean): Promise<JianjianBookContext> {
    const sessions = await ReadingSessionService.list([book.id], alive);
    const ranges = JianjianBookContextService.ranges(book, route, sessions);
    const result = new JianjianBookContext();
    const chapters: Set<number> = new Set<number>();
    const available: Set<number> = new Set<number>();
    let scanned = 0;
    let cachedIndex = -1;
    let content = '';
    for (let index = ranges.length - 1; index >= 0 && alive(); index--) {
      const range = ranges[index];
      if (scanned >= 240000 || (chapters.size >= 40 && !chapters.has(range.chapterIndex))) { result.limited = true; break; }
      const chapter = book.chapters[range.chapterIndex];
      if (cachedIndex !== range.chapterIndex) {
        cachedIndex = range.chapterIndex;
        chapters.add(cachedIndex);
        try {
          content = await OnlineTextContentCache.read(context, OnlineTextContentCache.key(book.sourceUrl, book.bookUrl || book.id,
            chapter.originSourceValue || chapter.source.value)) ?? '';
        } catch (_error) { content = ''; }
        if (!content) result.missingChapters++;
      }
      if (!alive() || !content) continue;
      const end = Math.min(content.length, range.end);
      const start = Math.max(range.start, end - Math.max(0, 240000 - scanned));
      if (start >= end) continue;
      if (start > range.start) result.limited = true;
      // Remove local image markers before slicing, retaining character offsets and never sending local paths.
      const plain = LocalTextImage.speechContent(content).substring(start, end);
      scanned += end - start;
      for (let offset = 0; offset < plain.length; offset += 900) {
        const text = plain.substring(offset, Math.min(offset + 1100, plain.length));
        if (!text.trim()) continue;
        const excerpt = new JianjianExcerpt();
        excerpt.chapterId = chapter.id;
        excerpt.chapterUrl = chapter.originSourceValue || chapter.source.value;
        excerpt.chapterTitle = chapter.title.substring(0, 256);
        excerpt.chapterIndex = range.chapterIndex;
        excerpt.charOffset = start + offset;
        excerpt.endOffset = start + offset + text.length;
        excerpt.text = text;
        result.excerpts.push(excerpt);
        available.add(range.chapterIndex);
      }
    }
    result.chapterCount = available.size;
    return result;
  }

  static select(context: JianjianBookContext, question: string, recap: boolean): JianjianExcerpt[] {
    const terms: Set<string> = new Set<string>();
    const words = question.toLowerCase().match(/[a-z0-9]{2,}|[\u4e00-\u9fff]{2,}/g) ?? [];
    for (const word of words) {
      if (/^[a-z0-9]/.test(word)) terms.add(word);
      else for (let index = 0; index + 1 < word.length; index++) terms.add(word.substring(index, index + 2));
    }
    const ranked = context.excerpts.slice();
    for (const excerpt of ranked) {
      const text = excerpt.text.toLowerCase();
      excerpt.score = 0;
      for (const term of terms) if (text.includes(term)) excerpt.score++;
    }
    ranked.sort((a: JianjianExcerpt, b: JianjianExcerpt): number =>
      (!recap ? b.score - a.score : 0) || b.chapterIndex - a.chapterIndex || b.charOffset - a.charOffset);
    const selected: JianjianExcerpt[] = [];
    for (const item of ranked) {
      if (selected.length >= 8) break;
      if (selected.some((other: JianjianExcerpt): boolean => other.chapterIndex === item.chapterIndex &&
        Math.abs(other.charOffset - item.charOffset) < 900)) continue;
      selected.push(item);
    }
    selected.sort((a: JianjianExcerpt, b: JianjianExcerpt): number => a.chapterIndex - b.chapterIndex || a.charOffset - b.charOffset);
    for (let index = 0; index < selected.length; index++) selected[index].id = String(index + 1);
    return selected;
  }

  static evidence(excerpts: JianjianExcerpt[]): string {
    return excerpts.map((e: JianjianExcerpt): string => {
      const value = new EvidenceItem();
      value.reference = e.id; value.chapter = e.chapterTitle; value.text = e.text;
      return JSON.stringify(value);
    }).join('\n');
  }

  static citations(reply: string, excerpts: JianjianExcerpt[]): JianjianCitation[] {
    const refs: JianjianCitation[] = [];
    for (const item of excerpts) {
      if (!reply.includes('[' + item.id + ']')) continue;
      const ref = new JianjianCitation();
      ref.id = item.id; ref.chapterId = item.chapterId; ref.chapterUrl = item.chapterUrl;
      ref.chapterTitle = item.chapterTitle; ref.chapterIndex = item.chapterIndex;
      ref.charOffset = item.charOffset; ref.endOffset = item.endOffset;
      refs.push(ref);
    }
    return refs;
  }

  static resolveCitation(book: Book, ref: JianjianCitation): number {
    return book.chapters.findIndex((chapter: Chapter): boolean => chapter.id === ref.chapterId &&
      (chapter.originSourceValue || chapter.source.value) === ref.chapterUrl);
  }
}
