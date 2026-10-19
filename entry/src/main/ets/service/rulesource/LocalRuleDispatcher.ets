import { BookInfo, SearchResult, TocItem } from '../../model/BookSource';
import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { LocalRuleContentResult, LocalRuleExecutionLimits } from './LocalRuleRuntimeTypes';
import { LocalRuleExploreResult } from '../../model/LocalRulePanel';
import { LightSourceBridge } from './light/LightSourceBridge';
import { LightSourceRequest } from './light/LightSourceRequestPolicy';

export class LocalRuleDispatcher {
  static async cacheComicImages(source: LocalRuleSource, urls: string[], request?: LightSourceRequest): Promise<string[]> {
    LocalRuleDispatcher.requireSource(source);
    return LightSourceBridge.cacheComicImages(source, urls, request);
  }

  static async explore(source: LocalRuleSource, address: string, page: number = 1,
    variables: Record<string, string> = {},
    resultLimit: number = LocalRuleExecutionLimits.MAX_SEARCH_RESULTS): Promise<LocalRuleExploreResult> {
    LocalRuleDispatcher.requireSource(source);
    if (!source.enabledExplore) throw new Error('书源未启用发现');
    return LightSourceBridge.explore(source, address, page, resultLimit);
  }

  static async search(source: LocalRuleSource, keyword: string,
    page: number = 1): Promise<SearchResult[]> {
    if (!source.isSearchEnabled()) return [];
    try {
      return await LocalRuleDispatcher.searchStrict(source, keyword, page);
    } catch (error) {
      LocalRuleDispatcher.logFailure(source, 'search', error as Object);
      return [];
    }
  }

  /** 健康检查需要绕过启用开关，并保留网络或规则异常供上层判定。 */
  static async searchForHealthCheck(source: LocalRuleSource, keyword: string,
    page: number = 1, variables: Record<string, string> = {}): Promise<SearchResult[]> {
    return LocalRuleDispatcher.searchStrict(source, keyword, page, variables);
  }

  static async testSearch(source: LocalRuleSource, keyword: string = '测试'): Promise<LocalRuleSourceHealth> {
    const health = new LocalRuleSourceHealth();
    health.sourceUrl = source.bookSourceUrl;
    health.checkedAt = Date.now();
    const startedAt = Date.now();
    if (!source.canExecute()) {
      health.status = LocalRuleSourceStatus.UNSUPPORTED;
      health.message = source.validationMessage || '书源包含当前版本不支持的能力';
      return health;
    }
    try {
      const results = await LocalRuleDispatcher.searchStrict(source, keyword, 1);
      health.responseTimeMs = Date.now() - startedAt;
      if (results.length === 0) {
        health.status = LocalRuleSourceStatus.FAILED;
        health.message = '请求成功，但搜索规则没有解析出有效书籍';
      } else {
        health.status = LocalRuleSourceStatus.READY;
        health.message = `搜索正常，共 ${results.length} 条`;
      }
    } catch (error) {
      health.responseTimeMs = Date.now() - startedAt;
      health.status = LocalRuleSourceStatus.FAILED;
      health.message = LocalRuleDispatcher.errorMessage(error as Object);
    }
    return health;
  }

  static async getBookInfo(source: LocalRuleSource, bookUrl: string,
    variables: Record<string, string> = {}): Promise<BookInfo | null> {
    LocalRuleDispatcher.requireSource(source);
    return LightSourceBridge.detail(source, bookUrl, variables);
  }

  static async getBookToc(source: LocalRuleSource, tocUrl: string,
    variables: Record<string, string> = {},
    onBatch?: (items: TocItem[]) => void): Promise<TocItem[]> {
    LocalRuleDispatcher.requireSource(source);
    const items = await LightSourceBridge.toc(source, tocUrl, variables);
    if (onBatch !== undefined) onBatch(items);
    return items;
  }

  static async resolveContent(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}, request?: LightSourceRequest): Promise<LocalRuleContentResult> {
    LocalRuleDispatcher.requireSource(source);
    return LightSourceBridge.content(source, chapterUrl, variables, request);
  }

  static async getContent(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): Promise<string> {
    const result = await LocalRuleDispatcher.resolveContent(source, chapterUrl, variables);
    return result.content;
  }

  static async getAudioUrl(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): Promise<string> {
    const result = await LocalRuleDispatcher.resolveContent(source, chapterUrl, variables);
    return result.audioUrl;
  }

  /** 明确的本地音频直链无需先作为正文完整下载；返回 undefined 时继续原解析链。 */
  static resolveDirectAudioRequest(source: LocalRuleSource, chapterUrl: string,
    variables: Record<string, string> = {}): LocalRuleContentResult | undefined {
    return undefined;
  }

  static getAudioHeaders(source: LocalRuleSource, _audioUrl: string,
    variables: Record<string, string> = {}): Record<string, string> {
    return {};
  }

  private static async searchStrict(source: LocalRuleSource, keyword: string,
    page: number, variables: Record<string, string> = {}): Promise<SearchResult[]> {
    LocalRuleDispatcher.requireSource(source);
    return LightSourceBridge.search(source, keyword, page);
  }

  private static requireSource(source: LocalRuleSource): void {
    if (!source.canExecute()) throw new Error('此书源格式已停用，请导入轻页支持的定义');
  }

  private static logFailure(source: LocalRuleSource, stage: string, error: Object): void {
    console.warn(`[LocalRuleDispatcher] ${stage} ${source.bookSourceName} failed: ` +
      LocalRuleDispatcher.errorMessage(error));
  }

  private static errorMessage(error: Object): string {
    if (error instanceof Error) return error.message || '规则执行失败';
    return String(error || '规则执行失败');
  }
}
