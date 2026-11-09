import { SearchResult } from '../model/BookSource';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { BookSourceService } from './BookSourceService';
import { SourceDataService } from './SourceDataService';
import { HomeSourceService } from './rulesource/HomeSourceService';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { LightSourceRequest } from './rulesource/light/LightSourceRequestPolicy';

const RECOMMENDATION_COUNT: number = 5;
const RECOMMENDATION_SOURCE_LIMIT: number = 6;
const RECOMMENDATION_TTL_MS: number = 5 * 60 * 1000;
const RECOMMENDATION_KEYWORDS: string[] = [
  '斗破苍穹', '三体', '凡人修仙传', '诡秘之主', '红楼梦', '盗墓笔记', '西游记', '庆余年'
];

/** 搜索推荐只保留五本内存结果；输入、返回和书源变更均可取消后续工作。 */
export class SearchRecommendationService {
  private static books: SearchResult[] = [];
  private static revision: string = '';
  private static loadedAt: number = 0;
  private static complete: boolean = false;

  static getRevision(): string {
    return `${SourceDataService.getInvalidationCounter()}:${LocalRuleSourceRepository.getCoverRevision()}`;
  }

  static async load(request: LightSourceRequest,
    onUpdate: (books: SearchResult[]) => void): Promise<void> {
    const revision = SearchRecommendationService.getRevision();
    const cancelled = (): boolean => request.isCancelled() || revision !== SearchRecommendationService.getRevision();
    if (cancelled()) return;
    const ttl = SearchRecommendationService.books.length > 0 ? RECOMMENDATION_TTL_MS : 30 * 1000;
    if (revision !== SearchRecommendationService.revision || Date.now() - SearchRecommendationService.loadedAt >= ttl) {
      SearchRecommendationService.books = [];
      SearchRecommendationService.complete = false;
      SearchRecommendationService.revision = revision;
    }
    const books = SearchRecommendationService.books.slice();
    const seen = new Set<string>(books.map((book: SearchResult): string => JSON.stringify([book.sourceUrl, book.bookUrl])));
    const append = (results: SearchResult[], fallbackType: 'audio' | 'text' | 'comic' = 'text'): void => {
      for (const book of results) {
        if (books.length >= RECOMMENDATION_COUNT) break;
        const key = JSON.stringify([book.sourceUrl, book.bookUrl]);
        if (!book.sourceUrl || !book.bookUrl || !book.name.trim() || seen.has(key)) continue;
        if (book.contentType === undefined) book.contentType = fallbackType;
        seen.add(key);
        books.push(book);
      }
    };
    const publish = (): void => {
      if (cancelled()) return;
      SearchRecommendationService.books = books.slice();
      SearchRecommendationService.loadedAt = Date.now();
      onUpdate(books.slice());
    };
    if (SearchRecommendationService.complete) { onUpdate(books.slice()); return; }
    append(HomeSourceService.getCachedRecommendations(RECOMMENDATION_COUNT));
    if (books.length > 0) publish();
    try {
      if (books.length < RECOMMENDATION_COUNT) {
        const urls = await LocalRuleSourceRepository.getRecommendationSourceUrls(RECOMMENDATION_SOURCE_LIMIT);
        for (const url of urls) {
          if (cancelled() || books.length >= RECOMMENDATION_COUNT) break;
          // 让已到达的书目先布局，每次只读一个源、执行一个低优先级请求。
          await new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 16); });
          if (cancelled()) break;
          try {
            const source = await SourceDataService.getSourceByUrl(url);
            if (cancelled()) break;
            if (!(source instanceof LocalRuleSource) || !source.isSearchEnabled()) continue;
            const keyword = RECOMMENDATION_KEYWORDS[Math.floor(Math.random() * RECOMMENDATION_KEYWORDS.length)];
            const results = await BookSourceService.searchBooks(source, keyword, 1, request);
            if (cancelled()) break;
            const previousCount = books.length;
            append(results, source.isAudio() ? 'audio' : source.isComic() ? 'comic' : 'text');
            if (books.length > previousCount) publish();
          } catch (_error) { /* 单源失败继续下一候选，不阻塞已显示的推荐。 */ }
        }
      }
      if (!cancelled()) {
        SearchRecommendationService.complete = true;
        publish();
      }
    } catch (_error) {
      // 数据库失败不缓存为成功的空结果，下次进入仍可重试。
    }
  }
}
