/** 用户导入规则源的只读聚合入口。 */
import { BookSource } from '../model/BookSource';
import { LocalRuleSource } from '../model/LocalRuleSource';
import { LocalRuleSourceRepository } from './rulesource/LocalRuleSourceRepository';
import { emitter } from '@kit.BasicServicesKit';

export const EVT_RULE_SOURCES_CHANGED = 'app.ruleSources.changed';

export class SourceDataService {
  private static localSourceUrls: Set<string> = new Set();
  private static localSourcesByUrl: Map<string, LocalRuleSource> = new Map<string, LocalRuleSource>();
  private static invalidationCounter: number = 0;
  private static localSources: LocalRuleSource[] | undefined = undefined;
  private static sourcesLoading: Promise<LocalRuleSource[]> | undefined = undefined;
  private static sourceLoads: Map<string, Promise<LocalRuleSource | undefined>> = new Map();

  static getInvalidationCounter(): number {
    return SourceDataService.invalidationCounter;
  }

  static async getSources(): Promise<BookSource[]> {
    return (await SourceDataService.loadLocalSources()).slice();
  }

  static async getEnabledSources(): Promise<BookSource[]> {
    const sources = await SourceDataService.loadLocalSources();
    return sources.filter((source: LocalRuleSource): boolean => source.isSearchEnabled());
  }

  /** 同一版定义只读库、解析一次；并发搜索、换源与首页共用在途请求。 */
  private static async loadLocalSources(): Promise<LocalRuleSource[]> {
    if (SourceDataService.localSources !== undefined) return SourceDataService.localSources;
    if (SourceDataService.sourcesLoading !== undefined) return SourceDataService.sourcesLoading;
    const task = SourceDataService.readLocalSources(SourceDataService.invalidationCounter);
    SourceDataService.sourcesLoading = task;
    try { return await task; }
    finally {
      if (SourceDataService.sourcesLoading === task) SourceDataService.sourcesLoading = undefined;
    }
  }

  private static async readLocalSources(revision: number): Promise<LocalRuleSource[]> {
    try {
      const localSources = await LocalRuleSourceRepository.getAll();
      // 读取期间发生导入、编辑或删除，旧快照不能回填缓存或交给调用者。
      if (revision !== SourceDataService.invalidationCounter) return SourceDataService.loadLocalSources();
      SourceDataService.localSources = SourceDataService.acceptLocalSources(localSources);
      return SourceDataService.localSources;
    } catch (error) {
      if (revision !== SourceDataService.invalidationCounter) return SourceDataService.loadLocalSources();
      console.warn(`[SourceDataService] local rules unavailable: ${SourceDataService.errorMessage(error)}`);
      SourceDataService.invalidateLocalSources();
      return [];
    }
  }

  /** 单源热路径优先使用导入源缓存，未命中时查询独立数据库。 */
  static async getSourceByUrl(sourceUrl: string): Promise<BookSource | undefined> {
    const cached = SourceDataService.localSourcesByUrl.get(sourceUrl);
    if (cached !== undefined) return cached;
    const loading = SourceDataService.sourceLoads.get(sourceUrl);
    if (loading !== undefined) return loading;
    const task = SourceDataService.readLocalSource(sourceUrl, SourceDataService.invalidationCounter);
    SourceDataService.sourceLoads.set(sourceUrl, task);
    try { return await task; }
    finally {
      if (SourceDataService.sourceLoads.get(sourceUrl) === task) SourceDataService.sourceLoads.delete(sourceUrl);
    }
  }

  private static async readLocalSource(sourceUrl: string, revision: number): Promise<LocalRuleSource | undefined> {
    try {
      const localSource = await LocalRuleSourceRepository.getByUrl(sourceUrl);
      if (revision !== SourceDataService.invalidationCounter) {
        return SourceDataService.readLocalSource(sourceUrl, SourceDataService.invalidationCounter);
      }
      if (localSource === undefined || !SourceDataService.acceptLocalSource(localSource)) return undefined;
      SourceDataService.localSourcesByUrl.set(sourceUrl, localSource);
      SourceDataService.localSourceUrls.add(sourceUrl);
      return localSource;
    } catch (error) {
      console.warn(`[SourceDataService] source lookup failed: ${SourceDataService.errorMessage(error)}`);
      return undefined;
    }
  }

  /** 书源导入、更新、启停或删除后调用；下次读取会回到数据库最新定义。 */
  static invalidateLocalSources(sourceUrl: string = ''): void {
    SourceDataService.invalidationCounter++;
    SourceDataService.localSources = undefined;
    SourceDataService.sourcesLoading = undefined;
    SourceDataService.sourceLoads.clear();
    if (sourceUrl.length > 0) {
      SourceDataService.localSourcesByUrl.delete(sourceUrl);
      SourceDataService.localSourceUrls.delete(sourceUrl);
    } else {
      SourceDataService.localSourcesByUrl.clear();
      SourceDataService.localSourceUrls.clear();
    }
    emitter.emit(EVT_RULE_SOURCES_CHANGED);
  }

  static isLocalRuleSource(sourceUrl: string): boolean {
    return SourceDataService.localSourceUrls.has(sourceUrl);
  }

  private static acceptLocalSources(sources: LocalRuleSource[]): LocalRuleSource[] {
    const accepted: LocalRuleSource[] = [];
    SourceDataService.localSourceUrls.clear();
    SourceDataService.localSourcesByUrl.clear();
    for (const source of sources) {
      if (!SourceDataService.acceptLocalSource(source)) continue;
      SourceDataService.localSourceUrls.add(source.bookSourceUrl);
      SourceDataService.localSourcesByUrl.set(source.bookSourceUrl, source);
      accepted.push(source);
    }
    return accepted;
  }

  private static acceptLocalSource(source: LocalRuleSource): boolean {
    return source.bookSourceUrl.length > 0 && !source.bookSourceUrl.startsWith('builtin://');
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message;
    return String(error);
  }
}
