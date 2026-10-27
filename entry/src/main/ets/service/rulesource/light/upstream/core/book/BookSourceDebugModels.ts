/**
 * Optional, in-memory diagnostics for one book-source execution.
 * Normal search/reading never creates this context, so tracing is opt-in.
 */
export class BookSourceDebugLimits {
  static readonly MAX_REQUESTS: number = 50;
  static readonly MAX_RULES: number = 200;
  static readonly MAX_LOGS: number = 200;
  static readonly MAX_BODY_PREVIEW: number = 8192;
  static readonly MAX_VALUE_PREVIEW: number = 2048;
  static readonly MAX_TOTAL_BYTES: number = 1024 * 1024;
}

export class BookSourceDebugNetworkTrace {
  requestId: string = '';
  transport: string = '';
  retryAttempt: number = 0;
  retryReason: string = '';
  attempts: string = '';
  requestHeaders: Record<string, string> = {};
  responseHeaders: Record<string, string> = {};
  headersAvailable: boolean = false;
  responseChars: number = 0;
  method: string = '';
  url: string = '';
  finalUrl: string = '';
  statusCode: number = 0;
  /** Measured wire bytes, -1 when unavailable. */
  responseBytes: number = -1;
  bodyPreview: string = '';
  elapsedMs: number = 0;
  error: string = '';
}

export class BookSourceDebugRuleTrace {
  field: string = '';
  rule: string = '';
  ruleType: string = '';
  inputCount: number = 0;
  matchedCount: number = 0;
  outputPreview: string = '';
  elapsedMs: number = 0;
  error: string = '';
}

export class BookSourceDebugLog {
  level: string = 'info';
  message: string = '';
  timestamp: number = 0;
}

export class BookSourceDebugStep {
  stage: string = '';
  name: string = '';
  startedAt: number = 0;
  status: string = 'running';
  elapsedMs: number = 0;
  requests: BookSourceDebugNetworkTrace[] = [];
  rules: BookSourceDebugRuleTrace[] = [];
  outputs: Record<string, string> = {};
  error: string = '';
}

export class BookSourceDebugSession {
  sessionId: string = '';
  sourceUrl: string = '';
  sourceName: string = '';
  stage: string = '';
  startedAt: number = 0;
  elapsedMs: number = 0;
  status: string = 'running';
  steps: BookSourceDebugStep[] = [];
  logs: BookSourceDebugLog[] = [];
}

/** Central sink shared by HTTP, rule and ArkWeb layers. */
export class BookSourceDebugContext {
  readonly session: BookSourceDebugSession;
  private currentStep: BookSourceDebugStep | null = null;
  private usedBytes: number = 0;

  constructor(sourceUrl: string = '', sourceName: string = '', stage: string = '') {
    this.session = new BookSourceDebugSession();
    this.session.sessionId = `debug_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
    this.session.sourceUrl = sourceUrl || '';
    this.session.sourceName = sourceName || sourceUrl || '';
    this.session.stage = stage || '';
    this.session.startedAt = Date.now();
  }

  beginStep(stage: string, name: string): BookSourceDebugStep {
    const step = new BookSourceDebugStep();
    step.stage = stage || '';
    step.name = name || stage || '';
    step.startedAt = Date.now();
    this.session.steps.push(step);
    this.currentStep = step;
    return step;
  }

  finishStep(status: string = 'passed', error: string = ''): void {
    if (!this.currentStep) return;
    this.currentStep.status = status;
    this.currentStep.error = this.safe(error, 2000);
    this.currentStep.elapsedMs = Math.max(0, Date.now() - this.currentStep.startedAt);
  }

  addNetwork(trace: BookSourceDebugNetworkTrace): void {
    if (!this.currentStep || this.requestCount() >= BookSourceDebugLimits.MAX_REQUESTS) return;
    trace.requestHeaders = this.boundedHeaders(trace.requestHeaders);
    trace.responseHeaders = this.boundedHeaders(trace.responseHeaders);
    trace.retryReason = BookSourceDebugRedactor.text(trace.retryReason);
    trace.url = BookSourceDebugRedactor.url(trace.url);
    trace.finalUrl = BookSourceDebugRedactor.url(trace.finalUrl);
    trace.bodyPreview = this.reserve(BookSourceDebugRedactor.text(trace.bodyPreview),
      BookSourceDebugLimits.MAX_BODY_PREVIEW);
    trace.error = this.safe(BookSourceDebugRedactor.text(BookSourceDebugRedactor.url(trace.error)), 2000);
    this.currentStep.requests.push(trace);
  }

  addRule(trace: BookSourceDebugRuleTrace): void {
    if (!this.currentStep || this.ruleCount() >= BookSourceDebugLimits.MAX_RULES) return;
    trace.rule = this.safe(trace.rule, 4096);
    trace.outputPreview = this.safe(trace.outputPreview, BookSourceDebugLimits.MAX_VALUE_PREVIEW);
    trace.error = this.safe(trace.error, 2000);
    this.currentStep.rules.push(trace);
  }

  setOutput(name: string, value: string): void {
    if (!this.currentStep || !name) return;
    this.currentStep.outputs[name] = this.safe(BookSourceDebugRedactor.text(value), BookSourceDebugLimits.MAX_VALUE_PREVIEW);
  }

  /** Records a bounded first-page before/after preview for content replacement debugging. */
  recordContentReplaceComparison(before: string, after: string): void {
    if (!this.currentStep) return;
    if (!this.currentStep.outputs['正文替换净化前（首段预览）']) {
      this.setOutput('正文替换净化前（首段预览）', before);
      this.setOutput('正文替换净化后（首段预览）', after);
    }
    const changed = before !== after;
    if (changed || !this.currentStep.outputs['正文替换净化是否有变化']) {
      this.setOutput('正文替换净化是否有变化', changed ? '是' : '否');
    }
  }

  addLog(level: string, message: string): void {
    if (this.session.logs.length >= BookSourceDebugLimits.MAX_LOGS) return;
    const log = new BookSourceDebugLog();
    log.level = level || 'info';
    log.message = this.safe(BookSourceDebugRedactor.text(message), 2000);
    log.timestamp = Date.now();
    this.session.logs.push(log);
  }

  finish(status: string = 'passed'): BookSourceDebugSession {
    this.session.status = status;
    this.session.elapsedMs = Math.max(0, Date.now() - this.session.startedAt);
    return this.session;
  }

  private boundedHeaders(headers: Record<string, string>): Record<string, string> {
    const result = BookSourceDebugRedactor.headers(headers || {});
    const bounded: Record<string, string> = {};
    for (const key of Object.keys(result).slice(0, 64)) bounded[key.substring(0, 128)] = this.reserve(result[key], 512);
    return bounded;
  }

  private requestCount(): number {
    return this.session.steps.reduce((count: number, step: BookSourceDebugStep): number => count + step.requests.length, 0);
  }

  private ruleCount(): number {
    return this.session.steps.reduce((count: number, step: BookSourceDebugStep): number => count + step.rules.length, 0);
  }

  private reserve(value: string, maxLength: number): string {
    const result = this.safe(value, maxLength);
    const available = Math.max(0, BookSourceDebugLimits.MAX_TOTAL_BYTES - this.usedBytes);
    const clipped = result.substring(0, available);
    this.usedBytes += clipped.length;
    return clipped;
  }

  private safe(value: string, maxLength: number): string {
    return String(value || '').substring(0, Math.max(0, maxLength));
  }
}

export class BookSourceDebugRedactor {
  static url(value: string): string {
    const text = String(value || '');
    if (!text) return '';
    return text.replace(/([?&](?:token|access_token|apikey|api_key|key|password|passwd|secret|sign)=)[^&]*/gi,
      '$1[REDACTED]');
  }

  static headers(headers: Record<string, string>): Record<string, string> {
    const result: Record<string, string> = {};
    for (const key of Object.keys(headers || {})) {
      result[key] = /cookie|authorization|token|secret|password|passwd|api[-_]?key|signature/i.test(key) ?
        '[REDACTED]' : BookSourceDebugRedactor.text(BookSourceDebugRedactor.url(String(headers[key] || ''))).substring(0, 512);
    }
    return result;
  }

  static text(value: string): string {
    return String(value || '').replace(/((?:token|access_token|apikey|api_key|password|passwd|secret|authorization)\s*[:=]\s*["']?)[^,;\s"'}]+/gi,
      '$1[REDACTED]');
  }
}
