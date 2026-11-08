export class JianjianAiConfig {
  address: string = '';
  apiKey: string = '';
  model: string = '';
}

export const JIANJIAN_PROMPT_MAX_LENGTH: number = 8000;

export class JianjianAiPrompts {
  chat: string = '';
  book: string = '';
}

export class JianjianAiMessage {
  role: string;
  content: string;

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

export class JianjianChatItem {
  id: string;
  role: string;
  content: string;
  references: JianjianCitation[] = [];
  boundaryChapter: number = -1;
  boundaryOffset: number = -1;

  constructor(id: string, role: string, content: string) {
    this.id = id;
    this.role = role;
    this.content = content;
  }
}

/** Only reader-owned parameters can opt a conversation into book context. */
export class JianjianChatRoute {
  bookId: string = '';
  sourceUrl: string = '';
  bookUrl: string = '';
  chapterIndex: number = -1;
  charOffset: number = 0;
  recap: boolean = false;
}

export class JianjianCitation {
  id: string = '';
  chapterId: string = '';
  chapterUrl: string = '';
  chapterTitle: string = '';
  chapterIndex: number = 0;
  charOffset: number = 0;
  endOffset: number = 0;
}

export class JianjianExcerpt extends JianjianCitation {
  text: string = '';
  score: number = 0;
}

export class JianjianBookContext {
  excerpts: JianjianExcerpt[] = [];
  chapterCount: number = 0;
  missingChapters: number = 0;
  limited: boolean = false;
}

export enum JianjianAiErrorCode { CONFIG, MODEL, AUTH, ENDPOINT, LIMIT, NETWORK, SERVER, INVALID, TOO_LARGE, CANCELLED, PROMPT }

export class JianjianAiError extends Error {
  code: JianjianAiErrorCode;
  status: number;

  constructor(code: JianjianAiErrorCode, status: number = 0) {
    super('Jianjian AI request failed');
    this.code = code;
    this.status = status;
  }
}
