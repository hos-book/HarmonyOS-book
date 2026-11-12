import { common } from '@kit.AbilityKit';
import { RankingBook } from '../../model/Ranking';
import { HttpClient } from '../http/HttpClient';
import { JsonObj } from '../builtin/JsonValue';
import { RankingParser } from './RankingParser';
import { RankingService } from './RankingService';
import { RankingStorage } from './RankingStorage';
import { RankingComicMetadata } from './RankingComicMetadata';

const CACHE_PREFIX: string = 'ranking-cover-';
const CACHE_TTL_MS: number = 3 * 86400000;
const PENDING: Map<string, Promise<string>> = new Map<string, Promise<string>>();

/**
 * 平台无关的榜单封面兜底。
 * 先信榜单 parser 已给的 cover；为空或图片加载失败时，再按 originalUrl 访问详情页补一次。
 * qqcomic 的榜单页本身不给封面，复用 RankingComicMetadata 的作品页解析。
 */
export class RankingCoverResolver {
  static async resolve(context: common.Context, book: RankingBook, force: boolean): Promise<string> {
    if (!force && book.coverUrl.length > 0) return book.coverUrl;
    if (book.platformId === 'qqcomic') {
      if (force) return RankingComicMetadata.refresh(context, book);
      await RankingComicMetadata.hydrate(context, book);
      return book.coverUrl;
    }
    const cacheKey: string = `${CACHE_PREFIX}${book.platformId}-${book.id}`;
    if (!force) {
      const cached: string = await RankingCoverResolver.readCache(context, cacheKey);
      if (cached.length > 0) {
        book.coverUrl = cached;
        return cached;
      }
    }
    const active: Promise<string> | undefined = PENDING.get(cacheKey);
    if (active !== undefined) return active;
    const task: Promise<string> = RankingCoverResolver.fetchDetail(context, book).then(
      async (cover: string): Promise<string> => {
        PENDING.delete(cacheKey);
        if (cover.length > 0) {
          book.coverUrl = cover;
          await RankingCoverResolver.writeCache(context, cacheKey, cover);
        }
        return cover;
      }).catch((): string => {
        PENDING.delete(cacheKey);
        return '';
      });
    PENDING.set(cacheKey, task);
    return task;
  }

  private static async readCache(context: common.Context, key: string): Promise<string> {
    try {
      const raw = await RankingStorage.read(context, key);
      if (!raw) return '';
      const record = new JsonObj(JSON.parse(raw));
      const cover = RankingParser.imageUrl(record.getString('cover'));
      const age = Date.now() - record.getInt('updatedAt');
      return cover && age >= 0 && age < CACHE_TTL_MS ? cover : '';
    } catch (_error) {
      return '';
    }
  }

  private static async writeCache(context: common.Context, key: string, cover: string): Promise<void> {
    try {
      await RankingStorage.write(context, key, JSON.stringify({ cover: cover, updatedAt: Date.now() }));
    } catch (_error) { /* 缓存失败不影响本次封面 */ }
  }

  private static async fetchDetail(context: common.Context, book: RankingBook): Promise<string> {
    if (book.originalUrl.length === 0) return '';
    try {
      const response = await HttpClient.request(book.originalUrl, {
        timeout: 10000,
        headers: RankingService.headers(book.platformId),
        charset: book.platformId === 'faloo' ? 'gb18030' : 'utf-8'
      });
      if (response.statusCode !== 200) return '';
      return RankingCoverResolver.extract(response.body);
    } catch (_error) {
      return '';
    }
  }

  /** 详情页封面：og:image → 懒加载 data-src → 页面 JSON → 普通 img。 */
  private static extract(html: string): string {
    const og = /<meta[^>]+(?:property|name)=["']og:image["'][^>]+content=["']([^"']+)["']/i.exec(html)?.[1]
      ?? /<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image["']/i.exec(html)?.[1] ?? '';
    if (og.length > 0) return RankingParser.imageUrl(og);
    const dataSrc = /<img\b[^>]*\bdata-src=["']([^"']+)["']/i.exec(html)?.[1] ?? '';
    if (dataSrc.length > 0) return RankingParser.imageUrl(dataSrc);
    const jsonCover = /"(?:vertical_cover|cover|image|thumb_url|thumbUri)"\s*:\s*"([^"]+)"/i.exec(html)?.[1] ?? '';
    if (jsonCover.length > 0) return RankingParser.imageUrl(jsonCover.replace(/\\\//g, '/'));
    const src = /<img\b[^>]*\bsrc=["']([^"']+)["']/i.exec(html)?.[1] ?? '';
    return src.length > 0 ? RankingParser.imageUrl(src) : '';
  }
}
