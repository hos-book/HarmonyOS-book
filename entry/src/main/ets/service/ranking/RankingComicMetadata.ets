import { common } from '@kit.AbilityKit';
import { RankingBook } from '../../model/Ranking';
import { HttpClient } from '../http/HttpClient';
import { JsonObj } from '../builtin/JsonValue';
import { RankingParser } from './RankingParser';
import { RankingService } from './RankingService';
import { RankingStorage } from './RankingStorage';

class ComicMetadataRecord {
  updatedAt: number = Date.now();
  cover: string;
  author: string;
  intro: string;
  rating: number;
  constructor(book: RankingBook) {
    this.cover = book.coverUrl;
    this.author = book.author;
    this.intro = book.intro;
    this.rating = book.rating;
  }
}

/** 仅给可见漫画/轮播补元数据，不抓章节；同一本书跨榜合并请求，最多三个并发。 */
export class RankingComicMetadata {
  private static memory: Map<string, RankingBook> = new Map<string, RankingBook>();
  private static pending: Map<string, Promise<RankingBook | null>> = new Map<string, Promise<RankingBook | null>>();
  private static failedAt: Map<string, number> = new Map<string, number>();
  private static queue: Array<() => void> = [];
  private static running: number = 0;

  static async hydrate(context: common.Context, book: RankingBook): Promise<void> {
    if (book.platformId !== 'qqcomic' || !/^qqcomic:\d+$/.test(book.id) || book.coverUrl) return;
    const cached = RankingComicMetadata.memory.get(book.id);
    let result: RankingBook | null = cached ?? null;
    if (result === null) {
      if (Date.now() - (RankingComicMetadata.failedAt.get(book.id) ?? 0) < 60000) return;
      let task = RankingComicMetadata.pending.get(book.id);
      if (task === undefined) {
        if (RankingComicMetadata.pending.size >= 64) return;
        task = new Promise<RankingBook | null>((resolve): void => {
          RankingComicMetadata.queue.push((): void => {
            RankingComicMetadata.fetch(context, book.id).then(resolve).catch((): void => resolve(null))
              .finally((): void => {
                RankingComicMetadata.running--;
                RankingComicMetadata.pump();
              });
          });
        });
        RankingComicMetadata.pending.set(book.id, task);
        RankingComicMetadata.pump();
      }
      result = await task;
      RankingComicMetadata.pending.delete(book.id);
    }
    if (result === null) {
      RankingComicMetadata.failedAt.set(book.id, Date.now());
      if (RankingComicMetadata.failedAt.size > 256) RankingComicMetadata.failedAt.clear();
      return;
    }
    book.coverUrl = result.coverUrl;
    book.author = result.author;
    book.intro = result.intro;
    book.rating = result.rating;
    RankingComicMetadata.memory.set(book.id, result);
    if (RankingComicMetadata.memory.size > 256) {
      for (const key of RankingComicMetadata.memory.keys()) { RankingComicMetadata.memory.delete(key); break; }
    }
  }

  private static pump(): void {
    while (RankingComicMetadata.running < 3 && RankingComicMetadata.queue.length > 0) {
      const next = RankingComicMetadata.queue.shift();
      if (next !== undefined) { RankingComicMetadata.running++; next(); }
    }
  }

  private static async fetch(context: common.Context, id: string): Promise<RankingBook | null> {
    const key = `qqcomic-info-${id.substring(8)}`;
    let stale: RankingBook | null = null;
    try {
      const raw = await RankingStorage.read(context, key);
      if (raw) {
        const record = new JsonObj(JSON.parse(raw));
        const cover = RankingParser.imageUrl(record.getString('cover'));
        if (cover) {
          stale = new RankingBook();
          stale.coverUrl = cover;
          stale.author = record.getString('author');
          stale.intro = record.getString('intro');
          const rating = Number(record.getString('rating'));
          stale.rating = Number.isFinite(rating) && rating > 0 && rating <= 10 ? rating : 0;
          const age = Date.now() - record.getInt('updatedAt');
          if (age >= 0 && age < 7 * 86400000) return stale;
        }
      }
    } catch (_error) { /* 缓存失效时访问官方作品页。 */ }
    try {
      const response = await HttpClient.request(`https://ac.qq.com/Comic/comicInfo/id/${id.substring(8)}`,
        { timeout: 10000, headers: RankingService.headers('qqcomic') });
      if (response.statusCode !== 200) return stale;
      const book = RankingParser.qqComicMetadata(id, response.body);
      if (book !== null) {
        try { await RankingStorage.write(context, key, JSON.stringify(new ComicMetadataRecord(book))); }
        catch (_error) { /* 磁盘失败不丢弃已拿到的封面。 */ }
      }
      return book ?? stale;
    } catch (_error) { return stale; }
  }
}
