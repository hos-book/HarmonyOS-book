import { BookSource } from '../../model/data/Book';
import { BookSourceRuntimePersistence } from '../book/BookSourceRuntimeStore';
import type { NativeRunnerHost } from '../nativesource/NativeSourceRunner';

/** Native JS execution belongs to the host when supplied, including expression evaluation. */
export interface SourceNativeScripts {
  create(source: BookSource, host: NativeRunnerHost): Pick<NativeRunnerHost, 'scriptEngine' | 'evaluateExpression'>;
}

/** Isolated binary image execution. The program only receives image bytes and bounded crypto. */
export interface SourceImageScripts {
  run(program: string, input: Uint8Array, cancelled: () => boolean): Promise<Uint8Array>;
}

/**
 * 宿主应用可以替换的引擎能力（“端口”）。端口都是可信的应用代码，绝不能暴露给书源脚本。
 * 每个端口都可以不提供：没装时引擎用自己的默认实现，开源轻页本身就不安装任何端口。
 */

/** 按书源隔离的 Cookie 存储。方法与 CookieStore 的静态方法一一对应。 */
export interface SourceCookieJar {
  getCookie(url: string): string;
  getCookieValue(url: string, name: string): string;
  setCookies(url: string, value: string): void;
  replaceCookies(url: string, value: string): void;
  removeCookie(url: string, name?: string): void;
  copyCookies(from: string, to: string): void;
  saveAsync(): void;
  saveSync(): void;
  clearAll(): void;
}

/** 限流排队中的一个等待者。 */
export interface SourceRateWaiter {
  isCancelled(): boolean;
  wait(ms: number): Promise<void>;
}

/**
 * 宿主决定同一书源下谁先发请求、哪些请求已取消。请求频率窗口始终由引擎维护，
 * 优先级只改变排队顺序，不会额外放出额度。
 */
export interface SourceRequestScheduler {
  isCancelled(source: BookSource | null): boolean;
  priority(source: BookSource | null): number;
  enqueue(key: string, source: BookSource, cancelCheck?: () => boolean): SourceRateWaiter;
  first(key: string, waiter: SourceRateWaiter): boolean;
  remove(key: string, waiter: SourceRateWaiter): void;
}

/** 替代 ArkWeb 执行阶段脚本的执行器。 */
export interface SourceScriptExecutor {
  /** 只有每次执行都在独立、有预算限制的上下文里才能声明并发；共享的 ArkWeb 控制器必须串行。 */
  concurrent: boolean;
  /** 只要有脚本就走完整脚本运行层，不再走轻量兼容解释器。 */
  forceFullScripts: boolean;
  /** 为 false 时禁止在调用线程上同步执行 QuickJS。 */
  allowSynchronousQuickJs: boolean;
  evaluate(script: string, sourceUrl: string, timingId: number): Promise<string>;
}

/** 网页会话租约：WebView 抓取和音频嗅探在租约内执行。 */
export interface SourceWebSession {
  run<T>(sourceUrl: string, action: () => Promise<T>): Promise<T>;
}

/** 按书源记录最近一次失败原因，替代全局的 AppStorage 键。 */
export interface SourceExecutionState {
  /** 引擎为某次请求复制了书源对象时调用，让副本与原书源共用同一份状态。 */
  bindSource(source: BookSource, target: BookSource): void;
  setError(source: BookSource, message: string): void;
  getError(source: BookSource): string;
}

/** 分段耗时诊断。id 返回 0 表示这个书源不记录。 */
export interface SourceDiagnostics {
  id(source: BookSource | null): number;
  end(id: number, stage: string, startedAt: number, details?: string): void;
}

export interface SourceEngineHostAdapter {
  /** Pure native-rule parsing, JSON in/out; no network or application state is transferred. */
  nativeParsing?: (input: string, source: BookSource) => Promise<string>;
  imageScripts?: SourceImageScripts;
  nativeScripts?: SourceNativeScripts;
  cookies?: (sourceUrl: string) => SourceCookieJar;
  persistence?: (source: BookSource) => BookSourceRuntimePersistence;
  scripts?: SourceScriptExecutor;
  web?: SourceWebSession;
  requests?: SourceRequestScheduler;
  state?: SourceExecutionState;
  diagnostics?: SourceDiagnostics;
}

class DefaultRateWaiter implements SourceRateWaiter {
  private cancelCheck?: () => boolean;

  constructor(cancelCheck?: () => boolean) {
    this.cancelCheck = cancelCheck;
  }

  isCancelled(): boolean {
    return !!this.cancelCheck && this.cancelCheck();
  }

  wait(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, ms));
  }
}

/**
 * 端口的全局入口。在应用启动、执行任何书源之前调用一次 install；任务执行期间不要更换 adapter。
 * 这里不保存“当前书源”之类的可变状态，书源身份都由调用方显式传入。
 */
export class SourceEngineHost {
  /** 没装宿主时记录最近一次失败原因的 AppStorage 键，界面从这里读取。 */
  static readonly LAST_ERROR_KEY: string = 'bookSourceStageLastError';

  private static adapter: SourceEngineHostAdapter = {};
  private static deferredReaderImages: WeakSet<BookSource> = new WeakSet<BookSource>();
  private static waiterOwners: WeakMap<SourceRateWaiter, SourceRequestScheduler> =
    new WeakMap<SourceRateWaiter, SourceRequestScheduler>();

  static install(adapter: SourceEngineHostAdapter): void {
    SourceEngineHost.adapter = adapter;
  }

  static cookies(sourceUrl: string): SourceCookieJar | undefined {
    const factory = SourceEngineHost.adapter.cookies;
    return factory ? factory(sourceUrl) : undefined;
  }

  static persistence(source: BookSource): BookSourceRuntimePersistence | undefined {
    const factory = SourceEngineHost.adapter.persistence;
    return factory ? factory(source) : undefined;
  }

  static scriptExecutor(): SourceScriptExecutor | undefined {
    return SourceEngineHost.adapter.scripts;
  }

  static nativeScripts(): SourceNativeScripts | undefined {
    return SourceEngineHost.adapter.nativeScripts;
  }

  static nativeParsing(): SourceEngineHostAdapter['nativeParsing'] {
    return SourceEngineHost.adapter.nativeParsing;
  }

  static imageScripts(): SourceImageScripts | undefined {
    return SourceEngineHost.adapter.imageScripts;
  }

  static async evaluate(script: string, sourceUrl: string, timingId: number = 0): Promise<string> {
    const executor = SourceEngineHost.adapter.scripts;
    if (!executor) throw new Error('Source script executor is not installed');
    return executor.evaluate(script, sourceUrl, timingId);
  }

  static async withWeb<T>(sourceUrl: string, action: () => Promise<T>): Promise<T> {
    const session = SourceEngineHost.adapter.web;
    return session ? session.run(sourceUrl, action) : action();
  }

  static bindSource(source: BookSource, target: BookSource): void {
    SourceEngineHost.setReaderImagesDeferred(target, SourceEngineHost.readerImagesDeferred(source));
    const state = SourceEngineHost.adapter.state;
    if (state) state.bindSource(source, target);
  }

  /** Trusted host opt-in for readers that materialize protected images on demand. Never exposed to rules. */
  static setReaderImagesDeferred(source: BookSource, deferred: boolean): void {
    if (deferred) SourceEngineHost.deferredReaderImages.add(source);
    else SourceEngineHost.deferredReaderImages.delete(source);
  }

  static readerImagesDeferred(source: BookSource): boolean {
    return SourceEngineHost.deferredReaderImages.has(source);
  }

  static setError(source: BookSource, message: string): void {
    const state = SourceEngineHost.adapter.state;
    if (state) {
      state.setError(source, message);
    } else {
      AppStorage.setOrCreate(SourceEngineHost.LAST_ERROR_KEY, message);
    }
  }

  static getError(source: BookSource): string {
    const state = SourceEngineHost.adapter.state;
    return state ? state.getError(source) : (AppStorage.get<string>(SourceEngineHost.LAST_ERROR_KEY) || '');
  }

  /** 诊断计时编号；没装诊断端口时恒为 0，调用方据此跳过拼接耗时明细。 */
  static id(source: BookSource | null): number {
    const diagnostics = SourceEngineHost.adapter.diagnostics;
    return diagnostics ? diagnostics.id(source) || 0 : 0;
  }

  static end(id: number, stage: string, startedAt: number, details: string = ''): void {
    const diagnostics = SourceEngineHost.adapter.diagnostics;
    if (id > 0 && diagnostics) diagnostics.end(id, stage, startedAt, details);
  }

  static isCancelled(source: BookSource | null): boolean {
    const requests = SourceEngineHost.adapter.requests;
    return requests ? requests.isCancelled(source) : false;
  }

  static priority(source: BookSource | null): number {
    const requests = SourceEngineHost.adapter.requests;
    return requests ? requests.priority(source) : 1;
  }

  static enqueue(key: string, source: BookSource, cancelCheck?: () => boolean): SourceRateWaiter {
    const scheduler = SourceEngineHost.adapter.requests;
    if (!scheduler) return new DefaultRateWaiter(cancelCheck);
    const waiter = scheduler.enqueue(key, source, cancelCheck);
    SourceEngineHost.waiterOwners.set(waiter, scheduler);
    return waiter;
  }

  /** 没有宿主排队时等待者总是排在第一位。 */
  static first(key: string, waiter: SourceRateWaiter): boolean {
    const scheduler = SourceEngineHost.waiterOwners.get(waiter);
    return scheduler ? scheduler.first(key, waiter) : true;
  }

  static remove(key: string, waiter: SourceRateWaiter): void {
    const scheduler = SourceEngineHost.waiterOwners.get(waiter);
    SourceEngineHost.waiterOwners.delete(waiter);
    if (scheduler) scheduler.remove(key, waiter);
  }
}
