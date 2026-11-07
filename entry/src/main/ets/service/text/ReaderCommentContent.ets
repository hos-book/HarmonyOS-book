import { ReaderParagraphComment, ReaderCommentChapter } from '../../model/ReaderComment';
import { ReaderTextDocument } from '../../model/ReaderTools';
import { ReaderActionMarker } from '../rulesource/light/upstream/core/book/ReaderActionMarker';
import { OnlineTextPaginator } from './OnlineTextPaginator';

/** 沿用轻页标记契约，只提取段评；规范化和替换后仍保持原文坐标。 */
export class ReaderCommentContent {
  static parse(content: string, richContent: string): ReaderCommentChapter {
    const result = new ReaderCommentChapter();
    result.content = OnlineTextPaginator.normalizeContent(content);
    result.commentsLoaded = true;
    if (!ReaderActionMarker.has(richContent)) return result;
    const rich = ReaderActionMarker.limit(richContent).replace(/\[\[LEGADO_EPUB_IMAGE:[\s\S]*?\]\]/g, '');
    let token = '\uE100JT_COMMENT';
    while (rich.includes(token)) token += '_';
    const comments: ReaderParagraphComment[] = [];
    const pieces: string[] = [];
    let cursor = 0;
    while (cursor < rich.length) {
      const bounds = ReaderActionMarker.findFirstRawRange(rich, cursor);
      if (bounds.length < 2) { pieces.push(rich.substring(cursor)); break; }
      pieces.push(rich.substring(cursor, bounds[0]));
      const action = ReaderActionMarker.parse(rich.substring(bounds[0], bounds[1]));
      if (action && ReaderCommentContent.isParagraph(action.label, action.title)) {
        const comment = new ReaderParagraphComment();
        comment.label = action.label;
        comment.title = action.title;
        comment.url = action.url;
        pieces.push(token + comments.length + '\uE101');
        comments.push(comment);
      }
      cursor = bounds[1];
    }
    // 临时哨兵只参与规范化，绝不进入缓存、复制或朗读文本。
    const decorated = OnlineTextPaginator.normalizeContent(pieces.join(''));
    const tokenPattern = new RegExp(token + '(\\d+)\uE101', 'g');
    const stripped = decorated.replace(tokenPattern, '');
    if (stripped.replace(/\s/g, '') !== result.content.replace(/\s/g, '')) return result;
    const offsets: number[] = [];
    let removed = 0;
    let match = tokenPattern.exec(decorated);
    while (match !== null) {
      offsets[Number(match[1])] = match.index - removed;
      removed += match[0].length;
      match = tokenPattern.exec(decorated);
    }
    let source = 0;
    let target = 0;
    let lastEnd = 0;
    for (let index = 0; index < comments.length; index++) {
      const end = offsets[index];
      if (end === undefined) continue;
      while (source < end) {
        if (!/\s/.test(stripped.charAt(source))) {
          while (target < result.content.length && /\s/.test(result.content.charAt(target))) target++;
          target++;
          lastEnd = target;
        }
        source++;
      }
      if (lastEnd === 0) continue;
      const comment = comments[index];
      comment.offset = lastEnd;
      if (!result.comments.some((item: ReaderParagraphComment): boolean => item.offset === lastEnd)) {
        result.comments.push(comment);
      }
    }
    return result;
  }

  static isParagraph(label: string, title: string): boolean {
    const text = title + ' ' + label;
    if (/本章说|章评|chapter/i.test(text) || !/段评|paragraph|comment|review/i.test(text)) return false;
    // 入口存在不代表有评论；无计数的通用“段评”按钮不生成气泡。
    const count = /(?:段评|paragraph|comments?|reviews?)\s*[：:(（·]?\s*(\d+(?:\.\d+)?)\s*([万千kKwW]?)\+?\s*(?:条)?\s*[)）]?\s*$/i.exec(label);
    return count !== null && Number(count[1]) > 0;
  }

  static display(comments: ReaderParagraphComment[], document: ReaderTextDocument): ReaderParagraphComment[] {
    const output: ReaderParagraphComment[] = [];
    for (const item of comments) {
      if (!ReaderCommentContent.isParagraph(item.label, item.title)) continue;
      const offset = document.toDisplay(item.offset);
      const before = document.toDisplay(Math.max(0, item.offset - 1));
      if (offset <= before || offset <= 0) continue;
      const comment = new ReaderParagraphComment();
      comment.offset = offset;
      comment.label = item.label;
      comment.title = item.title;
      comment.url = item.url;
      output.push(comment);
    }
    return output;
  }
}
