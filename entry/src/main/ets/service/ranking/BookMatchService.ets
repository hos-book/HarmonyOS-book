import { common } from '@kit.AbilityKit';
import { Book, Chapter } from '../../model/Book';
import { BookSource, SearchResult } from '../../model/BookSource';
import { RankingBook } from '../../model/Ranking';
import { BookIdentity } from '../../utils/BookIdentity';
import { SourceDataService } from '../SourceDataService';
import { BookSourceService } from '../BookSourceService';
import { PreferenceService } from '../PreferenceService';
import { RankingStorage } from './RankingStorage';
import { JsonObj } from '../builtin/JsonValue';

export class RankingMatch {
  book: Book;
  sourceName: string;
  score: number;
  remembered: boolean = false;
  constructor(book: Book, sourceName: string, score: number) {
    this.book = book;
    this.sourceName = sourceName;
    this.score = score;
  }
}

export class RankingMatchProgress {
  matches: RankingMatch[] = [];
  total: number = 0;
  completed: number = 0;
  failed: number = 0;
}

class RankingMatchMemory {
  id: string;
  sourceUrl: string;
  bookUrl: string;
  constructor(id: string, sourceUrl: string, bookUrl: string) {
    this.id = id;
    this.sourceUrl = sourceUrl;
    this.bookUrl = bookUrl;
  }
}

/** 可取消的匹配会话；旧会话不会调度更多书源或覆盖新点击。 */
export class BookMatchService {
  private generation: number = 0;

  cancel(): void { this.generation++; }

  static keyword(book: RankingBook): string {
    return book.title.split(/[|｜]/)[0].replace(/【[^】]*】|\[[^\]]*\]/g, '').trim() || book.title;
  }

  private static normalized(text: string): string {
    return text.toLowerCase().replace(/[\s·《》【】\[\]（）()，,。.!！?？:：|｜、\-]/g, '');
  }

  static score(target: RankingBook, result: SearchResult): number {
    const expected = BookMatchService.normalized(BookMatchService.keyword(target));
    const actual = BookMatchService.normalized(result.name.split(/[|｜]/)[0]);
    let score = actual === expected ? 60 : actual.includes(expected) || expected.includes(actual) ? 25 : 0;
    if (actual.length === 0 || score === 0) return 0;
    const author = BookMatchService.normalized(target.author);
    if (author && author === BookMatchService.normalized(result.author)) score += 25;
    // SearchResult 没有独立主播字段，只在来源返回的书名/简介中比对，不能拿书源名冒充主播。
    const narrator = BookMatchService.normalized(target.narrator);
    if (narrator && BookMatchService.normalized(`${result.name} ${result.intro}`).includes(narrator)) score += 15;
    return score;
  }

  static toBook(result: SearchResult, type: 'audio' | 'text' | 'comic'): Book {
    const chapters: Chapter[] = [];
    return {
      id: type === 'comic' ? BookIdentity.onlineComicBookId(result.sourceUrl, result.bookUrl) : type === 'text' ? BookIdentity.onlineTextBookId(result.sourceUrl, result.bookUrl)
        : BookIdentity.onlineAudioBookId(result.sourceUrl, result.bookUrl),
      title: result.name, author: result.author, narrator: '', cover: result.coverUrl,
      category: result.kind, contentType: type, intro: result.intro, totalDuration: 0,
      chapterCount: 0, rating: result.rating ?? 0, tags: [result.sourceName], chapters: chapters,
      bookUrl: result.bookUrl, sourceUrl: result.sourceUrl, variables: result.variables,
      wordCount: result.wordCount, latestChapterTitle: result.lastChapter,
      updateTime: result.updateTime, completed: result.completed
    };
  }

  private static async memories(context: common.Context): Promise<RankingMatchMemory[]> {
    try {
      const raw = await RankingStorage.read(context, 'matches');
      if (!raw) return [];
      const items = new JsonObj(JSON.parse(raw)).getArr('items');
      const records: RankingMatchMemory[] = [];
      for (let index = 0; index < Math.min(items.length(), 100); index++) {
        const item = items.getObj(index);
        records.push(new RankingMatchMemory(item.getString('id'), item.getString('sourceUrl'), item.getString('bookUrl')));
      }
      return records;
    } catch (_error) { return []; }
  }

  static async remember(context: common.Context, target: RankingBook, match: RankingMatch): Promise<void> {
    const records = (await BookMatchService.memories(context)).filter((entry: RankingMatchMemory): boolean =>
      entry.id !== target.id);
    records.unshift(new RankingMatchMemory(target.id, match.book.sourceUrl, match.book.bookUrl));
    const record: RankingMatchRecords = new RankingMatchRecords();
    record.items = records.slice(0, 100);
    await RankingStorage.write(context, 'matches', JSON.stringify(record));
  }

  async search(context: common.Context, target: RankingBook, keyword: string,
    onProgress: (progress: RankingMatchProgress) => void): Promise<void> {
    const generation = ++this.generation;
    const progress = new RankingMatchProgress();
    const memories = await BookMatchService.memories(context);
    const remembered = memories.find((entry: RankingMatchMemory): boolean => entry.id === target.id);
    const sources = await SourceDataService.getEnabledSources();
    const concurrency = await PreferenceService.getSearchConcurrency();
    if (generation !== this.generation) return;
    const eligible = sources.filter((source: BookSource): boolean => source.bookSourceType !== 2);
    // 上次选择的来源优先搜索；仍重新执行规则验证，不复用过期结果或自动跳转。
    eligible.sort((left: BookSource, right: BookSource): number =>
      Number(right.bookSourceUrl === remembered?.sourceUrl) - Number(left.bookSourceUrl === remembered?.sourceUrl));
    progress.total = eligible.length;
    onProgress(progress);
    let cursor = 0;
    const seen = new Set<string>();
    const worker = async (): Promise<void> => {
      while (generation === this.generation && cursor < eligible.length) {
        const source = eligible[cursor++];
        try {
          const results = await BookSourceService.searchBooks(source, keyword);
          if (generation !== this.generation) return;
          for (const result of results.slice(0, 80)) {
            if (!result.bookUrl || !result.sourceUrl) continue;
            const type: 'text' | 'audio' | 'comic' = result.contentType ??
              (source.bookSourceType === 0 || source.bookSourceType === 3 ? 'text' : source.bookSourceType === 2 ? 'comic' : 'audio');
            const score = BookMatchService.score(target, result);
            const key = `${result.sourceUrl}\u001f${result.bookUrl}`;
            if (score <= 0 || seen.has(key) || progress.matches.length >= 150) continue;
            seen.add(key);
            const match = new RankingMatch(BookMatchService.toBook(result, type), source.bookSourceName, score);
            match.remembered = match.book.sourceUrl === remembered?.sourceUrl && match.book.bookUrl === remembered?.bookUrl;
            progress.matches.push(match);
          }
        } catch (_error) { progress.failed++; }
        if (generation !== this.generation) return;
        progress.completed++;
        progress.matches.sort((left: RankingMatch, right: RankingMatch): number =>
          Number(right.remembered) - Number(left.remembered) || right.score - left.score ||
          left.sourceName.localeCompare(right.sourceName));
        onProgress(progress);
      }
    };
    const tasks: Promise<void>[] = [];
    for (let index = 0; index < Math.min(12, Math.max(1, concurrency), eligible.length); index++) tasks.push(worker());
    await Promise.all(tasks);
  }
}

class RankingMatchRecords {
  items: RankingMatchMemory[] = [];
}
