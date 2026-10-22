import { JSBoundedExecutionResult, JSContext, JSRuntimeOptions } from '@devzeng/quickjs';
import { taskpool } from '@kit.ArkTS';
import { NativeSourceCrypto } from './light/upstream/core/nativesource/NativeSourceCrypto';
import { LocalRuleQuickJsHostChannel } from './LocalRuleQuickJsHostChannel';

@Concurrent
function runBoundedHostQuickJs(script: string, sourceUrl: string, timeoutMs: number,
  control: Int32Array, response: Uint8Array): string {
  const options = new JSRuntimeOptions();
  options.memoryLimitBytes = 64 * 1024 * 1024;
  options.stackLimitBytes = 1024 * 1024;
  const context = new JSContext(options);
  try {
    const result = context.evaluateBounded(script, sourceUrl, timeoutMs, 32, undefined, undefined,
      control.subarray(0, 1), (name: string, payload: string): string => {
        return LocalRuleQuickJsHostChannel.call(control, response, name, payload);
      });
    if (result.value.length > 8 * 1024 * 1024) throw new Error('原生 JS 输出超过限制');
    return JSON.stringify(result);
  } finally { context.release(); }
}

@Concurrent
function runBoundedImageQuickJs(script: string, input: Uint8Array, signal: Int32Array): ArrayBuffer {
  const options = new JSRuntimeOptions();
  options.memoryLimitBytes = 96 * 1024 * 1024;
  options.stackLimitBytes = 1024 * 1024;
  const context = new JSContext(options);
  try {
    const result = context.evaluateBounded(script, 'content.imageDecode.js', 2000, 32, input,
      (name: string, data: Uint8Array, params: string): Uint8Array => {
        return NativeSourceCrypto.imageOperationSync(name, data, params);
      }, signal);
    if (!result.success) throw new Error(result.error || '图片脚本执行失败');
    if (!result.bytes.length || result.bytes.length > 20 * 1024 * 1024) throw new Error('图片脚本输出超过限制');
    return result.bytes.slice().buffer;
  } finally { context.release(); }
}

@Concurrent
function runBoundedQuickJs(script: string, sourceUrl: string, timeoutMs: number,
  maxPendingJobs: number, memoryLimitBytes: number, stackLimitBytes: number): string {
  const options = new JSRuntimeOptions();
  options.memoryLimitBytes = memoryLimitBytes;
  options.stackLimitBytes = stackLimitBytes;
  const context = new JSContext(options);
  try {
    const nativeResult: JSBoundedExecutionResult = context.evaluateBounded(
      script, sourceUrl, timeoutMs, maxPendingJobs);
    return `{"success":${nativeResult.success},"value":${JSON.stringify(nativeResult.value)},` +
      `"error":${JSON.stringify(nativeResult.error)},"timedOut":${nativeResult.timedOut},` +
      `"elapsedMs":${nativeResult.elapsedMs},"pendingJobs":${nativeResult.pendingJobs}}`;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error || 'QuickJS 执行失败');
    return `{"success":false,"value":"","error":${JSON.stringify(message)},` +
      `"timedOut":false,"elapsedMs":0,"pendingJobs":0}`;
  } finally {
    context.release();
  }
}

/** 单次 QuickJS 执行参数。所有预算还会在 native 调用前被收紧到安全范围。 */
export class LocalRuleQuickJsRequest {
  script: string = '';
  sourceUrl: string = 'local-rule';
  timeoutMs: number = 1000;
  maxPendingJobs: number = 8;
  memoryLimitBytes: number = 64 * 1024 * 1024;
  stackLimitBytes: number = 256 * 1024;
  binaryInput: Uint8Array | undefined = undefined;
  cancelSignal: Int32Array | undefined = undefined;
  hostHandler: ((name: string, payload: string) => Promise<string>) | undefined = undefined;
  hostCheck: (() => void) | undefined = undefined;
}

/** 与 QuickJS 类型解耦的结果，业务层不会获得 context 或原生 value handle。 */
export class LocalRuleQuickJsResult {
  success: boolean = false;
  value: string = '';
  errorMessage: string = '';
  timedOut: boolean = false;
  elapsedMs: number = 0;
  pendingJobs: number = 0;
  bytes: Uint8Array = new Uint8Array();

  static failed(message: string): LocalRuleQuickJsResult {
    const result = new LocalRuleQuickJsResult();
    result.errorMessage = message;
    return result;
  }
}

/**
 * 不可信书源脚本的最小 QuickJS 门面。
 *
 * 每次调用在 taskpool 中创建独立 context，仅走原生 interrupt 支持的 evaluateBounded，
 * 并在 finally 中释放。
 * 原生阶段可传入 JSON 宿主处理器，由主线程通过独立有界邮箱响应；脚本不能取得平台对象。
 */
export class LocalRuleQuickJsRuntime {
  private static readonly MAX_SCRIPT_CHARS: number = 12 * 1024 * 1024;
  private static readonly MAX_SOURCE_URL_CHARS: number = 512;
  private static readonly MIN_TIMEOUT_MS: number = 1;
  private static readonly MAX_TIMEOUT_MS: number = 5000;
  private static readonly MAX_PENDING_JOBS: number = 32;
  private static readonly MIN_MEMORY_BYTES: number = 1024 * 1024;
  private static readonly MAX_MEMORY_BYTES: number = 64 * 1024 * 1024;
  private static readonly MIN_STACK_BYTES: number = 64 * 1024;
  private static readonly MAX_STACK_BYTES: number = 1024 * 1024;

  static async execute(request: LocalRuleQuickJsRequest): Promise<LocalRuleQuickJsResult> {
    if (request.binaryInput !== undefined) return LocalRuleQuickJsRuntime.executeBinary(request);
    if (request.script.trim().length === 0) {
      return LocalRuleQuickJsResult.failed('QuickJS 脚本不能为空');
    }
    if (request.script.length > LocalRuleQuickJsRuntime.MAX_SCRIPT_CHARS) {
      return LocalRuleQuickJsResult.failed('QuickJS 输入超过 12 MiB 执行预算');
    }
    if (request.hostHandler) return LocalRuleQuickJsRuntime.executeHost(request);

    const options = new JSRuntimeOptions();
    options.memoryLimitBytes = LocalRuleQuickJsRuntime.clamp(request.memoryLimitBytes,
      LocalRuleQuickJsRuntime.MIN_MEMORY_BYTES, LocalRuleQuickJsRuntime.MAX_MEMORY_BYTES);
    options.stackLimitBytes = LocalRuleQuickJsRuntime.clamp(request.stackLimitBytes,
      LocalRuleQuickJsRuntime.MIN_STACK_BYTES, LocalRuleQuickJsRuntime.MAX_STACK_BYTES);
    const timeoutMs = LocalRuleQuickJsRuntime.clamp(request.timeoutMs,
      LocalRuleQuickJsRuntime.MIN_TIMEOUT_MS, LocalRuleQuickJsRuntime.MAX_TIMEOUT_MS);
    const maxPendingJobs = LocalRuleQuickJsRuntime.clamp(request.maxPendingJobs,
      0, LocalRuleQuickJsRuntime.MAX_PENDING_JOBS);
    const sourceUrl = LocalRuleQuickJsRuntime.normalizeSourceUrl(request.sourceUrl);
    try {
      const execution: Promise<Object> = taskpool.execute(runBoundedQuickJs,
        request.script, sourceUrl, timeoutMs, maxPendingJobs,
        options.memoryLimitBytes, options.stackLimitBytes);
      return LocalRuleQuickJsRuntime.parseResult(String(await execution));
    } catch (error) {
      if (error instanceof Error) {
        return LocalRuleQuickJsResult.failed(error.message || 'QuickJS 执行失败');
      }
      return LocalRuleQuickJsResult.failed(String(error || 'QuickJS 执行失败'));
    }
  }

  private static async executeHost(request: LocalRuleQuickJsRequest): Promise<LocalRuleQuickJsResult> {
    const handler = request.hostHandler;
    const check = request.hostCheck;
    if (!handler || !check) return LocalRuleQuickJsResult.failed('原生 JS 宿主参数无效');
    const channel = new LocalRuleQuickJsHostChannel(handler, check);
    const task = new taskpool.Task(runBoundedHostQuickJs, request.script,
      LocalRuleQuickJsRuntime.normalizeSourceUrl(request.sourceUrl),
      LocalRuleQuickJsRuntime.clamp(request.timeoutMs, 1, 2000), channel.control, channel.response);
    task.setTransferList([]);
    task.onReceiveData((sequence: number, name: string, payload: string): void => {
      channel.answer(sequence, name, payload).catch((error: Error): void => {
        channel.error = error.message || '原生 JS 宿主返回失败';
        channel.close();
      });
    });
    const timer = setInterval((): void => { channel.tick(); }, 25);
    try {
      channel.tick();
      if (channel.error) return LocalRuleQuickJsResult.failed(channel.error);
      const result = LocalRuleQuickJsRuntime.parseResult(String(await taskpool.execute(task)));
      return channel.error ? LocalRuleQuickJsResult.failed(channel.error) : result;
    } catch (error) {
      return LocalRuleQuickJsResult.failed(channel.error ||
        (error instanceof Error ? error.message : '原生 JS 执行失败'));
    } finally {
      clearInterval(timer);
      channel.close();
      task.onReceiveData();
    }
  }

  private static async executeBinary(request: LocalRuleQuickJsRequest): Promise<LocalRuleQuickJsResult> {
    const input = request.binaryInput;
    const signal = request.cancelSignal;
    if (!input || !input.length || input.length > 20 * 1024 * 1024 || !signal || signal.length !== 1 ||
      !request.script.trim() || request.script.length > 384 * 1024) {
      return LocalRuleQuickJsResult.failed('图片脚本参数超过执行预算');
    }
    try {
      const task = new taskpool.Task(runBoundedImageQuickJs, request.script, input, signal);
      task.setTransferList([]);
      const output: Object = await taskpool.execute(task);
      if (!(output instanceof ArrayBuffer)) return LocalRuleQuickJsResult.failed('图片脚本返回格式无效');
      const result = new LocalRuleQuickJsResult();
      result.bytes = new Uint8Array(output);
      result.success = result.bytes.length > 0 && result.bytes.length <= 20 * 1024 * 1024;
      if (!result.success) result.errorMessage = '图片脚本输出超过限制';
      return result;
    } catch (error) {
      return LocalRuleQuickJsResult.failed(error instanceof Error ? error.message : '图片脚本执行失败');
    }
  }

  private static parseResult(payload: string): LocalRuleQuickJsResult {
    try {
      const parsed = JSON.parse(payload) as Object;
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return LocalRuleQuickJsResult.failed('QuickJS 返回格式无效');
      }
      const record = parsed as Record<string, Object>;
      const result = new LocalRuleQuickJsResult();
      result.success = record['success'] === true;
      result.value = String(record['value'] ?? '');
      result.errorMessage = String(record['error'] ?? '');
      result.timedOut = record['timedOut'] === true;
      result.elapsedMs = Number(record['elapsedMs'] ?? 0);
      result.pendingJobs = Number(record['pendingJobs'] ?? 0);
      return result;
    } catch (_error) {
      return LocalRuleQuickJsResult.failed('QuickJS 返回格式无效');
    }
  }

  private static normalizeSourceUrl(value: string): string {
    const normalized = value.trim() || 'local-rule';
    return normalized.substring(0, LocalRuleQuickJsRuntime.MAX_SOURCE_URL_CHARS);
  }

  private static clamp(value: number, minValue: number, maxValue: number): number {
    if (!Number.isFinite(value)) return minValue;
    return Math.max(minValue, Math.min(maxValue, Math.floor(value)));
  }
}
