import { parseRanking, NativeRankingBook, NativeRankingResult } from 'libhsda_core.so';
import { RankingBook } from '../../model/Ranking';
import { BookMetadataPolicy } from '../../utils/BookMetadataPolicy';
import { JsonObj } from '../builtin/JsonValue';
import { FanqieRankingText } from './FanqieRankingText';

export class RankingParsedResult {
  books: RankingBook[] = [];
  fetchedAt: number = 0;
}

/** 榜单原文和缓存记录统一由 Rust 后台任务解析。 */
export class RankingParser {
  static async parse(platform: string, boardId: string, body: string,
    cached: boolean = false): Promise<RankingParsedResult> {
    const native: NativeRankingResult = await parseRanking(platform, boardId, body,
      FanqieRankingText.GLYPHS, cached, Date.now());
    const result: RankingParsedResult = new RankingParsedResult();
    result.fetchedAt = native.fetchedAt;
    result.books = native.books.map((item: NativeRankingBook): RankingBook => {
      const book: RankingBook = new RankingBook();
      book.id = item.id;
      book.platformId = item.platformId;
      book.title = item.title;
      book.author = item.author;
      book.narrator = item.narrator;
      book.coverUrl = item.coverUrl;
      book.originalUrl = item.originalUrl;
      book.intro = item.intro;
      book.contentType = item.contentType === 1 ? 'audio' : item.contentType === 2 ? 'comic' : 'text';
      book.rank = item.rank;
      book.rating = item.rating;
      return book;
    });
    return result;
  }

  static text(html: string): string {
    return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
      .replace(/&nbsp;|\u00a0/g, ' ').replace(/&#(\d+);/g,
        (_match: string, code: string): string => String.fromCharCode(Number(code)))
      .replace(/\s+/g, ' ').trim();
  }

  static imageUrl(value: string): string {
    const clean = value.replace(/&amp;/g, '&').trim();
    if (clean.startsWith('//')) return `https:${clean}`;
    return clean.startsWith('https://') ? clean : '';
  }

  static qqComicMetadata(id: string, body: string): RankingBook | null {
    if (!/^qqcomic:\d+$/.test(id) || body.length > 2 * 1024 * 1024) return null;
    const scripts = body.match(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) ?? [];
    for (const script of scripts) {
      try {
        const text = />([\s\S]*?)<\/script>/i.exec(script)?.[1] ?? '';
        const root = new JsonObj(JSON.parse(text));
        const items: JsonObj[] = [root];
        const graph = root.getArr('@graph');
        for (let index: number = 0; index < graph.length(); index++) {
          items.push(graph.getObj(index));
        }
        for (const item of items) {
          if (item.getString('@type') !== 'ComicSeries' ||
            item.getString('url').toLowerCase() !== `https://ac.qq.com/comic/comicinfo/id/${id.substring(8)}`) continue;
          const cover = RankingParser.imageUrl(item.getString('image'));
          if (!cover) continue;
          const book = new RankingBook();
          book.id = id;
          book.coverUrl = cover;
          const authors = item.getArr('author');
          const authorNames: string[] = [];
          for (let index: number = 0; index < authors.length(); index++) {
            authorNames.push(RankingParser.text(authors.getObj(index).getString('name')));
          }
          book.author = authorNames.length > 0 ? authorNames.join('、')
            : RankingParser.text(item.getObj('author').getString('name'));
          book.intro = RankingParser.text(item.getString('description'));
          book.rating = BookMetadataPolicy.rating(item.getObj('aggregateRating').getString('ratingValue'));
          return book;
        }
      } catch (_error) { /* 继续读取下一段结构化元数据。 */ }
    }
    return null;
  }

}
