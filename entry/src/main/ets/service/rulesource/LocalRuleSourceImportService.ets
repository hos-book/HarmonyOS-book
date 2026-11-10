import { LocalRuleSource } from '../../model/LocalRuleSource';
import { Chapter } from '../../model/Book';
import { SearchCache } from '../../utils/SearchCache';
import { DataService } from '../DataService';
import { ChapterCacheService } from '../ChapterCacheService';
import { SourceDataService } from '../SourceDataService';
import { BookSourceService } from '../BookSourceService';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';

/** All user import routes reset content caches for successfully replaced, unlocked sources. */
export class LocalRuleSourceImportService {
  static async importSources(sources: LocalRuleSource[]): Promise<number> {
    if (sources.length === 0) return 0;
    const replaced = await LocalRuleSourceRepository.getUnlockedSourceUrls(
      sources.map((source: LocalRuleSource): string => source.bookSourceUrl));
    const count = await LocalRuleSourceRepository.upsertImportedBatch(sources);
    SourceDataService.invalidateLocalSources();
    if (replaced.size > 0) {
      BookSourceService.invalidateAudioTocs(replaced);
      const cache = ChapterCacheService.getInstance();
      cache.suspendPreload();
      try {
        const protectedIds = await DataService.historyBookIds();
        const clearAudio = (bookId: string, chapters: Chapter[]): void => {
          if (protectedIds !== null && !protectedIds.has(bookId)) cache.clearBook(bookId, chapters);
        };
        if (protectedIds !== null) SearchCache.invalidateSources(replaced, clearAudio, protectedIds);
        await DataService.invalidateSourceCaches(replaced, clearAudio);
      } finally {
        cache.resumePreload();
      }
    }
    return count;
  }
}
