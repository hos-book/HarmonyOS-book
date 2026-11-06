import { HomeBlockSection, SearchResult } from '../../model/BookSource';
import { LocalRuleSource } from '../../model/LocalRuleSource';
import { LocalRuleControl, LocalRulePanel } from '../../model/LocalRulePanel';
import { BookSourceService, ExploreFetchResult } from '../BookSourceService';
import { PreferenceService } from '../PreferenceService';
import { SourceDataService } from '../SourceDataService';
import { LocalRulePanelService } from './LocalRulePanelService';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { RankingService } from '../ranking/RankingService';

export class HomeSourceCategory {
  name: string;
  url: string;
  group: string;

  constructor(name: string, url: string, group: string = '') {
    this.name = name;
    this.url = url;
    this.group = group;
  }
}

export class HomeSourceContent {
  filters: LocalRuleControl[] = [];
  categories: HomeSourceCategory[] = [];
  channels: string[] = [];
  channel: string = '';
  blocks: HomeBlockSection[] = [];
  moreRecommendations: SearchResult[] = [];
  moreLoading: boolean = false;
  moreFailed: boolean = false;
  loadedAt: number = 0;
}

class HomeRecommendationCursor {
  url: string;
  page: number = 1;
  seenBooks: Set<string> = new Set();

  constructor(url: string) {
    this.url = url;
  }
}

class HomeSourceLoad {
  content: HomeSourceContent = new HomeSourceContent();
  listeners: Array<(content: HomeSourceContent) => void> = [];
  promise: Promise<HomeSourceContent> = Promise.resolve(this.content);
}

/** 首页使用用户选择的已启用小说或听书发现源，复用现有导入源发现链路。 */
export class HomeSourceService {
  private static readonly CACHE_TTL_MS: number = 5 * 60 * 1000;
  private static cache: Map<string, HomeSourceContent> = new Map();
  private static pending: Map<string, HomeSourceLoad> = new Map();
  private static revision: string = '';

  private static syncRevision(): string {
    const revision = `${SourceDataService.getInvalidationCounter()}:${LocalRuleSourceRepository.getLoginRevision()}`;
    if (revision !== HomeSourceService.revision) {
      HomeSourceService.cache.clear();
      HomeSourceService.pending.clear();
      HomeSourceService.revision = revision;
    }
    return revision;
  }

  /** 有界内存缓存；书源定义或登录状态变化即失效，下拉刷新绕过缓存。 */
  static async loadHome(source: LocalRuleSource, forceRefresh: boolean = false,
    onUpdate: (content: HomeSourceContent) => void = (): void => {}, channel: string = ''): Promise<HomeSourceContent> {
    const revision = HomeSourceService.syncRevision();
    const key = JSON.stringify([source.bookSourceUrl, channel]);
    const cached = HomeSourceService.cache.get(key);
    if (!forceRefresh && cached !== undefined && Date.now() - cached.loadedAt < HomeSourceService.CACHE_TTL_MS) {
      HomeSourceService.cache.delete(key);
      HomeSourceService.cache.set(key, cached);
      onUpdate(cached);
      return cached;
    }
    const active = HomeSourceService.pending.get(key);
    if (active !== undefined) {
      active.listeners.push(onUpdate);
      if (active.content.channels.length > 0 || active.content.categories.length > 0 ||
        active.content.blocks.length > 0) onUpdate(active.content);
      return active.promise;
    }
    const task = new HomeSourceLoad();
    task.listeners.push(onUpdate);
    HomeSourceService.pending.set(key, task);
    task.promise = HomeSourceService.fetchHome(source, task, channel, revision).then((content: HomeSourceContent): HomeSourceContent => {
      if (revision === HomeSourceService.syncRevision() && HomeSourceService.pending.get(key) === task &&
        content.blocks.length > 0) {
        content.loadedAt = Date.now();
        HomeSourceService.cache.delete(key);
        HomeSourceService.cache.set(key, content);
        while (HomeSourceService.cache.size > 4) {
          const oldest = HomeSourceService.cache.keys().next();
          if (oldest.done) break;
          HomeSourceService.cache.delete(oldest.value);
        }
      }
      return content;
    }).finally((): void => {
      task.listeners = [];
      if (HomeSourceService.pending.get(key) === task) HomeSourceService.pending.delete(key);
    });
    return task.promise;
  }

  private static async fetchHome(source: LocalRuleSource, task: HomeSourceLoad,
    channel: string, revision: string): Promise<HomeSourceContent> {
    const panel = await LocalRulePanelService.load(source, false);
    task.content.filters = panel.controls.filter((control: LocalRuleControl): boolean =>
      control.discoveryFilter && control.options.length > 0 && control.action.length > 0);
    const categories = (await HomeSourceService.getCategories(source, panel)).filter((category: HomeSourceCategory): boolean =>
      HomeSourceService.isSupportedChannel(category.group));
    task.content.channels = Array.from(new Set(categories.map((category: HomeSourceCategory): string => category.group)
      .filter((group: string): boolean => group.length > 0)));
    task.content.channel = task.content.channels.includes(channel) ? channel : '';
    task.content.categories = categories.filter((category: HomeSourceCategory): boolean =>
      HomeSourceService.isSupportedChannel(category.group) &&
      (!task.content.channel || category.group === task.content.channel));
    HomeSourceService.notifyHome(task);
    task.content.blocks = await HomeSourceService.getHomeBlocks(source, task.content.categories,
      (blocks: HomeBlockSection[]): void => {
        task.content.blocks = blocks;
        HomeSourceService.notifyHome(task);
      });
    // 预览先展示，后续书单独立补齐；单个发现分类失败不影响已显示的首页。
    if (task.content.blocks.length > 0 && revision === HomeSourceService.syncRevision()) {
      await HomeSourceService.loadMoreRecommendations(source, task, revision);
    }
    return task.content;
  }

  private static async loadMoreRecommendations(source: LocalRuleSource, task: HomeSourceLoad,
    revision: string): Promise<void> {
    const limit: number = 50;
    const requestBudget: number = 8;
    const books: SearchResult[] = [];
    const seen: Set<string> = new Set();
    const previewUrls: Set<string> = new Set();
    for (const block of task.content.blocks) {
      previewUrls.add(block.moreUrl);
      for (const book of block.books) seen.add(JSON.stringify([book.sourceUrl || source.bookSourceUrl, book.bookUrl]));
    }
    // 优先补充尚未展示的分类，再沿预览分类取后续内容；始终限定在当前源和频道。
    const ordered: HomeSourceCategory[] = task.content.categories
      .filter((category: HomeSourceCategory): boolean => !previewUrls.has(category.url))
      .concat(task.content.categories.filter((category: HomeSourceCategory): boolean => previewUrls.has(category.url)));
    const queue: HomeRecommendationCursor[] = [];
    const categoryUrls: Set<string> = new Set();
    for (const category of ordered) {
      if (categoryUrls.has(category.url)) continue;
      categoryUrls.add(category.url);
      queue.push(new HomeRecommendationCursor(category.url));
    }
    const requested: Set<string> = new Set();
    let requests: number = 0;
    let failed: boolean = false;
    task.content.moreLoading = queue.length > 0;
    HomeSourceService.notifyHome(task);
    while (books.length < limit && queue.length > 0 && requests < requestBudget &&
      revision === HomeSourceService.syncRevision()) {
      const batch: HomeRecommendationCursor[] = queue.splice(0, Math.min(2, requestBudget - requests));
      const results: Array<ExploreFetchResult | undefined> = await Promise.all(batch.map(
        async (cursor: HomeRecommendationCursor): Promise<ExploreFetchResult | undefined> => {
          const key: string = JSON.stringify([cursor.url, cursor.page]);
          if (requested.has(key)) return undefined;
          requested.add(key);
          requests++;
          try {
            return await BookSourceService.getExploreBooksByUrl(source, cursor.url, cursor.page, limit);
          } catch (_error) {
            failed = true;
            return undefined;
          }
        }));
      if (revision !== HomeSourceService.syncRevision()) break;
      for (let index: number = 0; index < results.length; index++) {
        const result: ExploreFetchResult | undefined = results[index];
        if (result === undefined) continue;
        const cursor: HomeRecommendationCursor = batch[index];
        let progressed: boolean = false;
        for (const book of result.books) {
          if (!book.bookUrl || !book.name) continue;
          const key: string = JSON.stringify([book.sourceUrl || source.bookSourceUrl, book.bookUrl]);
          if (!cursor.seenBooks.has(key)) {
            cursor.seenBooks.add(key);
            progressed = true;
          }
          if (seen.has(key) || books.length >= limit) continue;
          seen.add(key);
          books.push(book);
        }
        // 下一页必须由书源提供；重复页停止，不自行猜测 URL。
        if (result.nextUrl && progressed && books.length < limit) {
          cursor.url = result.nextUrl;
          cursor.page = result.nextPage ?? cursor.page + 1;
          queue.push(cursor);
        }
      }
      task.content.moreRecommendations = books.slice();
      HomeSourceService.notifyHome(task);
    }
    task.content.moreLoading = false;
    task.content.moreFailed = failed && books.length < limit;
    HomeSourceService.notifyHome(task);
  }

  private static notifyHome(task: HomeSourceLoad): void {
    for (const listener of task.listeners) listener(task.content);
  }

  static isEligible(source: LocalRuleSource): boolean {
    return source.enabled && (source.isAudio() || source.isText() || source.isComic()) && source.canExecute() &&
      HomeSourceService.hasHomeContent(source) &&
      !source.bookSourceUrl.startsWith('builtin://');
  }

  static async getSources(): Promise<LocalRuleSource[]> {
    const sources = await SourceDataService.getSources();
    const eligibleSources: LocalRuleSource[] = [];
    for (const source of sources) {
      if (source instanceof LocalRuleSource && HomeSourceService.isEligible(source)) eligibleSources.push(source);
    }
    return eligibleSources;
  }

  static selectAvailable(sources: LocalRuleSource[], preferredUrl: string): LocalRuleSource | undefined {
    const eligible = sources.filter((source: LocalRuleSource): boolean => HomeSourceService.isEligible(source));
    return eligible.find((source: LocalRuleSource): boolean => source.bookSourceUrl === preferredUrl) ??
      eligible.find((source: LocalRuleSource): boolean => HomeSourceService.hasHomeContent(source)) ?? eligible[0];
  }

  static async getSelectedSource(): Promise<LocalRuleSource | undefined> {
    const preferred = await PreferenceService.getHomeSourceUrl();
    if (!preferred || preferred === RankingService.HOME_URL) return undefined;
    const source = await SourceDataService.getSourceByUrl(preferred);
    return source instanceof LocalRuleSource && HomeSourceService.isEligible(source) ? source : undefined;
  }

  static async setSelectedSource(sourceUrl: string): Promise<void> {
    const source = await SourceDataService.getSourceByUrl(sourceUrl);
    if (!(source instanceof LocalRuleSource) || !HomeSourceService.isEligible(source)) {
      throw new Error('首页源必须已启用且支持发现');
    }
    await PreferenceService.setHomeSourceUrl(sourceUrl);
  }

  static hasHomeContent(source: LocalRuleSource): boolean {
    return source.enabledExplore && source.exploreUrl.trim().length > 0;
  }

  static async getCategories(source: LocalRuleSource, loadedPanel?: LocalRulePanel): Promise<HomeSourceCategory[]> {
    if (!source.enabledExplore || !source.exploreUrl.trim()) return [];
    const panel = loadedPanel ?? await LocalRulePanelService.load(source, false);
    const categories: HomeSourceCategory[] = [];
    const seen = new Set<string>();
    let group: string = '';
    for (const entry of panel.entries) {
      if (entry.action) continue;
      if (entry.type === 'group') {
        group = entry.title.trim();
        continue;
      }
      if (!entry.url.trim()) continue;
      const categoryGroup = (entry.group ?? '').trim() || group;
      const key = JSON.stringify([categoryGroup, entry.url]);
      if (seen.has(key)) continue;
      seen.add(key);
      categories.push(new HomeSourceCategory(entry.title, entry.url, categoryGroup));
    }
    return categories;
  }

  /** 仅识别明确的视频分组，不从站点域名或分类 URL 猜测内容类型。 */
  static isSupportedChannel(channel: string): boolean {
    return !['影视', '视频', '电影', '电视剧', 'video'].includes(channel.trim().toLowerCase());
  }

  /** 综合页轮询各分组，避免前四项被同一频道占满；单频道仍沿用原顺序。 */
  private static previewCategories(categories: HomeSourceCategory[]): HomeSourceCategory[] {
    const groups = new Map<string, HomeSourceCategory[]>();
    for (const category of categories) {
      const items = groups.get(category.group) ?? [];
      items.push(category);
      groups.set(category.group, items);
    }
    const selected: HomeSourceCategory[] = [];
    for (let index = 0; selected.length < Math.min(4, categories.length); index++) {
      for (const items of groups.values()) {
        if (items[index] !== undefined) selected.push(items[index]);
        if (selected.length === 4) break;
      }
    }
    return selected;
  }

  static async getHomeBlocks(source: LocalRuleSource,
    categories: HomeSourceCategory[],
    onUpdate: (blocks: HomeBlockSection[]) => void = (): void => {}): Promise<HomeBlockSection[]> {
    // 总预览预算保持四组、两路并发，各分类独立失败。
    let failureMessage: string = '';
    let failed: boolean = false;
    let completed: number = 0;
    const blocks: HomeBlockSection[] = HomeSourceService.previewCategories(categories).map((category: HomeSourceCategory): HomeBlockSection => {
      const block: HomeBlockSection = {
        title: category.group ? `${category.group} · ${category.name}` : category.name,
        books: [], moreUrl: category.url, layout: 'horizontal',
        sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl
      };
      return block;
    });
    const loadBlock = async (block: HomeBlockSection): Promise<void> => {
      try {
        const result = await BookSourceService.getExploreBooksByUrl(source, block.moreUrl, 1, 12);
        block.books = result.books.slice(0, 12);
        completed++;
        if (block.books.length > 0) {
          onUpdate(blocks.filter((item: HomeBlockSection): boolean => item.books.length > 0));
        }
      } catch (error) {
        failed = true;
        failureMessage = error instanceof Error ? error.message : String(error);
      }
    };
    // DOM 宿主串行执行，四个分类一起解析只会互相排队；最多两路并行补齐首页。
    let cursor = 0;
    const worker = async (): Promise<void> => {
      while (cursor < blocks.length) {
        const block = blocks[cursor++];
        await loadBlock(block);
      }
    };
    await Promise.all([worker(), worker()]);
    if (completed === 0 && failed) throw new Error(failureMessage);
    return blocks.filter((block: HomeBlockSection): boolean => block.books.length > 0);
  }
}
