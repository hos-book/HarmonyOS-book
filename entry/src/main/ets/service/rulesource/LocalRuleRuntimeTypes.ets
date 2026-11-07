export class LocalRuleDocumentKind {
  static readonly JSON: number = 1;
  static readonly HTML: number = 2;
  static readonly TEXT: number = 3;
}

/** 规则执行中的不可变解析上下文。payload 保存 JSON、HTML 片段或纯文本。 */
export class LocalRuleDocument {
  kind: number = LocalRuleDocumentKind.TEXT;
  payload: string = '';
  baseUrl: string = '';
  /** 仅供当前解析批次复用的静态 DOM 字段，消费后释放。 */
  htmlFields: Map<string, string[]> = new Map();

  static of(kind: number, payload: string, baseUrl: string): LocalRuleDocument {
    const document = new LocalRuleDocument();
    document.kind = kind;
    document.payload = payload;
    document.baseUrl = baseUrl;
    return document;
  }
}

export class LocalRuleRequestPlan {
  url: string = '';
  method: string = 'GET';
  headers: Record<string, string> = {};
  body: string | Object | undefined = undefined;
  rawBody: boolean = false;
  charset: string = 'utf-8';
  timeoutMs: number = 18000;
  retry: number = 0;
  followRedirects: boolean = true;
  inlineBody: string | undefined = undefined;
  webView: boolean = false;
  webJs: string = '';
  audioSniff: boolean = false;
  bodyJs: string = '';
  session: Record<string, Object> = {};
}

/** HttpClient 外层的安全结果；网络与协议错误不会以异常越过 Dispatcher。 */
export class LocalRuleFetchResult {
  renderedHtml: string = '';
  ok: boolean = false;
  statusCode: number = 0;
  requestUrl: string = '';
  headers: Record<string, string> = {};
  body: string = '';
  errorMessage: string = '';
  browserState: string = '';
  resourceUrls: string[] = [];

  static failed(url: string, message: string, statusCode: number = 0): LocalRuleFetchResult {
    const result = new LocalRuleFetchResult();
    result.requestUrl = url;
    result.errorMessage = message;
    result.statusCode = statusCode;
    return result;
  }
}

export class LocalRuleInteraction {
  offset: number = 0;
  label: string = '';
  url: string = '';
  title: string = '';
}

export class LocalRuleReaderActionResult {
  commentData: string = '';
  offline: boolean = false;
  url: string = '';
  html: string = '';
  value: string = '';
  message: string = '';
}

export class LocalRuleVoice {
  id: string = '';
  name: string = '';
}

export class LocalRuleContentResult {
  title: string = '';
  content: string = '';
  audioUrl: string = '';
  nextContentUrl: string = '';
  requestHeaders: Record<string, string> = {};
  /** Lossless upstream content, including image and source-provided interaction markers. */
  richContent: string = '';
  imageUrls: string[] = [];
  videoUrl: string = '';
  mediaType: string = 'text';
  hasInteractions: boolean = false;
  interactions: LocalRuleInteraction[] = [];
  variables: Record<string, string> = {};
}

export class LocalRuleExecutionLimits {
  static readonly INLINE_HTML_CSP: string = "script-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action https:";
  static readonly MAX_URL_CHARS: number = 2048;
  static readonly MAX_RESPONSE_CHARS: number = 4 * 1024 * 1024;
  static readonly MAX_STAGE_RESPONSE_CHARS: number = 16 * 1024 * 1024;
  static readonly MAX_FIELD_CHARS: number = 8192;
  static readonly MAX_INTRO_CHARS: number = 1200;
  static readonly MAX_CONTENT_CHARS: number = 8 * 1024 * 1024;
  static readonly MAX_SEARCH_RESULTS: number = 50;
  static readonly MAX_TOC_ITEMS: number = 20000;
  static readonly MAX_JSON_NODES: number = 20000;
  static readonly MAX_JSON_DEPTH: number = 64;
  static readonly MIN_TIMEOUT_MS: number = 3000;
  static readonly MAX_TIMEOUT_MS: number = 60000;
  static readonly MAX_RETRY: number = 2;
}
