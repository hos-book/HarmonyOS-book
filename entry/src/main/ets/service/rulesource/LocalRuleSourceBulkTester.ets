import {
  LocalRuleSource,
  LocalRuleSourceHealth,
  LocalRuleSourceStatus
} from '../../model/LocalRuleSource';
import { BookSourceService } from '../BookSourceService';
import { LocalRuleSourceRepository } from './LocalRuleSourceRepository';
import { LocalRuleBrowserLoginCoordinator } from './LocalRuleBrowserLoginCoordinator';

const BULK_TEST_BATCH_SIZE: number = 6;

export class LocalRuleSourceBulkTestProgress {
  total: number = 0;
  completed: number = 0;
  passed: number = 0;
  failed: number = 0;
  testedSource: LocalRuleSource | undefined = undefined;

  static copy(report: LocalRuleSourceBulkTestReport,
    testedSource?: LocalRuleSource): LocalRuleSourceBulkTestProgress {
    const progress = new LocalRuleSourceBulkTestProgress();
    progress.total = report.total;
    progress.completed = report.completed;
    progress.passed = report.passed;
    progress.failed = report.failed;
    progress.testedSource = testedSource;
    return progress;
  }
}

export class LocalRuleSourceBulkTestReport extends LocalRuleSourceBulkTestProgress {
  retained: number = 0;
  cancelled: boolean = false;
  failedSources: LocalRuleSource[] = [];
}

export type LocalRuleSourceBulkTestProgressHandler =
  (progress: LocalRuleSourceBulkTestProgress) => void;

export interface LocalRuleSourceBulkTestExecutor {
  test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth>;
}

export interface LocalRuleSourceBulkTestStore {
  saveTested(sources: LocalRuleSource[]): Promise<void>;
}

class DefaultLocalRuleSourceBulkTestExecutor implements LocalRuleSourceBulkTestExecutor {
  private mode: string;
  private isCancelled: () => boolean;

  constructor(mode: string, isCancelled: () => boolean) {
    this.mode = mode;
    this.isCancelled = isCancelled;
  }

  async test(source: LocalRuleSource, keyword: string): Promise<LocalRuleSourceHealth> {
    if (this.mode === 'exploreReading') {
      return BookSourceService.testLocalSourceExploreReading(source, this.isCancelled);
    }
    if (this.mode === 'singleSearch') {
      return BookSourceService.testLocalSource(source, keyword, this.isCancelled);
    }
    return BookSourceService.testLocalSourceAvailability(source, keyword, this.isCancelled);
  }
}

class DefaultLocalRuleSourceBulkTestStore implements LocalRuleSourceBulkTestStore {
  async saveTested(sources: LocalRuleSource[]): Promise<void> {
    await LocalRuleSourceRepository.updateValidationBatch(sources);
  }
}

class LocalRuleSourceBulkTestOutcome {
  source: LocalRuleSource = new LocalRuleSource();
  ready: boolean = false;
  sourceIndex: number = -1;
  cancelled: boolean = false;
}

export class LocalRuleSourceBulkTester {
  private executor: LocalRuleSourceBulkTestExecutor;
  private store: LocalRuleSourceBulkTestStore;
  private cancelled: boolean = false;
  private running: boolean = false;
  private mode: string = 'search';
  private activeBrowserScopes: Map<number, number> = new Map<number, number>();

  constructor(executor: LocalRuleSourceBulkTestExecutor, store: LocalRuleSourceBulkTestStore) {
    this.executor = executor;
    this.store = store;
  }

  static createDefault(mode: string = 'search'): LocalRuleSourceBulkTester {
    if (mode !== 'search' && mode !== 'singleSearch' && mode !== 'exploreReading') throw new Error('不支持的书源校验模式');
    const tester = new LocalRuleSourceBulkTester(
      new DefaultLocalRuleSourceBulkTestExecutor(mode, (): boolean => false),
      new DefaultLocalRuleSourceBulkTestStore());
    tester.mode = mode;
    tester.executor = new DefaultLocalRuleSourceBulkTestExecutor(mode, (): boolean => tester.cancelled);
    return tester;
  }

  cancel(): void {
    this.cancelled = true;
    for (const scopeId of this.activeBrowserScopes.values()) {
      LocalRuleBrowserLoginCoordinator.cancelScope(scopeId, '书源校验已取消');
    }
  }

  async run(sources: LocalRuleSource[], keyword: string,
    onProgress?: LocalRuleSourceBulkTestProgressHandler): Promise<LocalRuleSourceBulkTestReport> {
    const cleanKeyword = keyword.trim();
    if (this.mode !== 'exploreReading' && cleanKeyword.length === 0) throw new Error('搜索测试关键词不能为空');
    if (this.running) throw new Error('书源校验正在运行');
    this.running = true;
    this.cancelled = false;

    const report = new LocalRuleSourceBulkTestReport();
    report.total = sources.length;
    const activeTasks: Promise<LocalRuleSourceBulkTestOutcome>[] = [];
    const activeIndexes: number[] = [];
    const pendingSave: LocalRuleSource[] = [];
    let nextIndex = 0;
    try {
      LocalRuleSourceBulkTester.notifyProgress(report, onProgress);

      while (!this.cancelled && nextIndex < sources.length && activeTasks.length < BULK_TEST_BATCH_SIZE) {
        activeTasks.push(this.testOne(sources[nextIndex], cleanKeyword, nextIndex));
        activeIndexes.push(nextIndex);
        nextIndex++;
      }

      while (activeTasks.length > 0) {
        const outcome: LocalRuleSourceBulkTestOutcome =
          await Promise.race<LocalRuleSourceBulkTestOutcome>(activeTasks);
        const activePosition = activeIndexes.indexOf(outcome.sourceIndex);
        if (activePosition >= 0) {
          activeTasks.splice(activePosition, 1);
          activeIndexes.splice(activePosition, 1);
        }
        if (outcome.cancelled) continue;
        report.completed++;
        pendingSave.push(outcome.source);
        if (outcome.ready) {
          report.passed++;
        } else {
          report.failed++;
          report.failedSources.push(outcome.source);
        }
        LocalRuleSourceBulkTester.notifyProgress(report, onProgress, outcome.source);

        if (!this.cancelled && nextIndex < sources.length) {
          activeTasks.push(this.testOne(sources[nextIndex], cleanKeyword, nextIndex));
          activeIndexes.push(nextIndex);
          nextIndex++;
        }
        // 先补齐网络任务，让新请求与本批结果落库重叠执行。
        if (pendingSave.length >= BULK_TEST_BATCH_SIZE) {
          await this.store.saveTested(pendingSave.slice());
          pendingSave.length = 0;
        }
      }

      if (pendingSave.length > 0) await this.store.saveTested(pendingSave);
      report.retained = report.failed;
      report.cancelled = this.cancelled;
      return report;
    } finally {
      this.cancel();
      await Promise.all<LocalRuleSourceBulkTestOutcome>(activeTasks);
      this.running = false;
    }
  }

  private async testOne(source: LocalRuleSource,
    keyword: string, sourceIndex: number): Promise<LocalRuleSourceBulkTestOutcome> {
    const outcome = new LocalRuleSourceBulkTestOutcome();
    outcome.source = source;
    outcome.sourceIndex = sourceIndex;
    if (!source.canExecute()) {
      source.validationStatus = LocalRuleSourceStatus.UNSUPPORTED;
      if (source.validationMessage.length === 0) {
        source.validationMessage = '书源包含当前版本不支持的能力';
      }
      return outcome;
    }

    let browserScope = 0;
    try {
      browserScope = LocalRuleBrowserLoginCoordinator.openScope(source.bookSourceUrl);
      this.activeBrowserScopes.set(sourceIndex, browserScope);
      const health = await this.executor.test(source, keyword);
      if (this.cancelled) {
        outcome.cancelled = true;
        return outcome;
      }
      source.validationStatus = health.status;
      source.validationMessage = health.message;
      outcome.ready = health.status === LocalRuleSourceStatus.READY;
    } catch (error) {
      if (this.cancelled) {
        outcome.cancelled = true;
        return outcome;
      }
      source.validationStatus = LocalRuleSourceStatus.FAILED;
      source.validationMessage = error instanceof Error ? error.message : String(error);
    } finally {
      LocalRuleBrowserLoginCoordinator.closeScope(browserScope);
      this.activeBrowserScopes.delete(sourceIndex);
    }
    return outcome;
  }

  private static notifyProgress(report: LocalRuleSourceBulkTestReport,
    onProgress?: LocalRuleSourceBulkTestProgressHandler, testedSource?: LocalRuleSource): void {
    if (onProgress !== undefined) {
      onProgress(LocalRuleSourceBulkTestProgress.copy(report, testedSource));
    }
  }
}
