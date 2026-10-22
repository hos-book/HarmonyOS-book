export class ReaderBookmark {
  id: string = '';
  bookId: string = '';
  chapterId: string = '';
  chapterUrl: string = '';
  chapterTitle: string = '';
  resourceIndex: number = 0;
  charOffset: number = 0;
  domPos: string = '';
  preview: string = '';
  createdAt: number = 0;
}

export class ReaderReplaceRule {
  id: string = '';
  name: string = '';
  pattern: string = '';
  replacement: string = '';
  isRegex: boolean = false;
  enabled: boolean = true;
  /** 空字符串表示全部书籍，其余为精确书籍身份。 */
  bookId: string = '';
}

export class ReaderTextEdit {
  start: number = 0;
  end: number = 0;
  length: number = 0;
}

export class ReaderTextStage {
  edits: ReaderTextEdit[] = [];
}

/** 坐标映射使持久进度、书签不依赖用户当前开启的替换规则。 */
export class ReaderTextDocument {
  content: string = '';
  rawLength: number = 0;
  stages: ReaderTextStage[] = [];
  failed: boolean = false;

  static original(content: string): ReaderTextDocument {
    const value = new ReaderTextDocument();
    value.content = content;
    value.rawLength = content.length;
    return value;
  }

  toDisplay(offset: number): number {
    let result = Math.max(0, Math.min(offset, this.rawLength));
    for (const stage of this.stages) {
      let delta = 0;
      let mapped = false;
      for (const edit of stage.edits) {
        if (result < edit.start) break;
        if (result < edit.end) {
          result = edit.start + delta + Math.min(result - edit.start, edit.length);
          mapped = true;
          break;
        }
        delta += edit.length - (edit.end - edit.start);
      }
      if (!mapped) result += delta;
    }
    return Math.max(0, Math.min(result, this.content.length));
  }

  toRaw(offset: number): number {
    let result = Math.max(0, Math.min(offset, this.content.length));
    for (let index = this.stages.length - 1; index >= 0; index--) {
      let delta = 0;
      let mapped = false;
      for (const edit of this.stages[index].edits) {
        const start = edit.start + delta;
        if (result < start) break;
        if (result < start + edit.length) {
          result = edit.start + Math.min(result - start, edit.end - edit.start);
          mapped = true;
          break;
        }
        delta += edit.length - (edit.end - edit.start);
      }
      if (!mapped) result -= delta;
    }
    return Math.max(0, Math.min(result, this.rawLength));
  }
}

export class ReaderToolsSnapshot {
  bookmarks: ReaderBookmark[] = [];
  rules: ReaderReplaceRule[] = [];
}
