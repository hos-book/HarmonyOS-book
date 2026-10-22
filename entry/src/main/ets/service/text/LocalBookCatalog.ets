import { bookParser } from '@hms.core.readerservice.bookParser';
import { LocalBookHtmlText } from './LocalBookHtmlText';

export class LocalCatalogSection {
  title: string = '';
  start: number = 0;
  end: number = 0;
}

/** 原书目录只决定切分位置；正文仍按文件顺序完整保留。 */
export class LocalBookCatalog {
  private static clean(value: string): string {
    return LocalBookHtmlText.clean(value).substring(0, 200);
  }

  private static decode(value: string): string {
    const text = value.replace(/&amp;/gi, '&').replace(/&quot;/gi, '"').replace(/&#39;/g, "'");
    try { return decodeURIComponent(text); } catch (_error) { return text; }
  }

  private static path(value: string): string {
    const parts: string[] = [];
    for (const part of LocalBookCatalog.decode(value.split('#')[0]).replace(/\\/g, '/').split('/')) {
      if (part === '..') parts.pop();
      else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  }

  private static anchors(html: string): Map<string, number> {
    const anchors = new Map<string, number>();
    const tags = /<[a-z][^>]*>/gi;
    let tag = tags.exec(html);
    while (tag !== null) {
      const attrs = /(?:^|\s)(?:id|name)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi;
      let attr = attrs.exec(tag[0]);
      while (attr !== null) {
        const name = LocalBookCatalog.decode(attr[1] ?? attr[2] ?? attr[3] ?? '');
        if (name && !anchors.has(name)) anchors.set(name, tag.index);
        attr = attrs.exec(tag[0]);
      }
      tag = tags.exec(html);
    }
    return anchors;
  }

  private static mark(marks: LocalCatalogSection[], title: string, start: number): void {
    const label = LocalBookCatalog.clean(title);
    if (!label || start < 0 || marks.length >= 50000) return;
    const section = new LocalCatalogSection();
    section.title = label;
    section.start = start;
    marks.push(section);
  }

  private static sections(html: string, fallback: string, marks: LocalCatalogSection[]): LocalCatalogSection[] {
    if (marks.length === 0) {
      const headings = /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1\s*>|<mbp:pagebreak\b[^>]*\/?\s*>/gi;
      let match = headings.exec(html);
      while (match !== null) {
        LocalBookCatalog.mark(marks, match[2] ?? `${fallback} ${marks.length + 1}`, match.index);
        match = headings.exec(html);
      }
    }
    marks.sort((a, b): number => a.start - b.start);
    marks = marks.filter((item: LocalCatalogSection, index: number): boolean => index === 0 || marks[index - 1].start !== item.start);
    if (marks.length === 0 || marks[0].start > 0) {
      const first = new LocalCatalogSection();
      first.title = fallback;
      marks.unshift(first);
    }
    for (let i = 0; i < marks.length; i++) marks[i].end = i + 1 < marks.length ? marks[i + 1].start : html.length;
    return marks;
  }

  static spineKey(spine: bookParser.SpineItem): string { return LocalBookCatalog.path(spine.href); }

  static epubIndex(spines: bookParser.SpineItem[], catalog: bookParser.CatalogItem[]): Map<string, bookParser.CatalogItem[]> {
    const result = new Map<string, bookParser.CatalogItem[]>();
    const ids = new Map<string, string>();
    const duplicateIds = new Set<string>();
    for (const spine of spines) {
      const path = LocalBookCatalog.spineKey(spine);
      result.set(path, []);
      if (spine.idRef) {
        if (ids.has(spine.idRef)) duplicateIds.add(spine.idRef);
        ids.set(spine.idRef, path);
      }
    }
    for (const item of catalog) {
      const path = LocalBookCatalog.path(item.resourceFile || item.href || '');
      const key = result.has(path) ? path :
        (item.idRef && !duplicateIds.has(item.idRef) ? ids.get(item.idRef) : undefined);
      if (key !== undefined) result.get(key)?.push(item);
    }
    return result;
  }

  static epub(html: string, spine: bookParser.SpineItem, catalog: bookParser.CatalogItem[],
    fallback: string): LocalCatalogSection[] {
    const anchors = catalog.some((item): boolean => (item.href ?? '').includes('#')) ?
      LocalBookCatalog.anchors(html) : new Map<string, number>();
    const marks: LocalCatalogSection[] = [];
    const path = LocalBookCatalog.path(spine.href);
    for (const item of catalog) {
      if (!(spine.idRef && item.idRef === spine.idRef) &&
        LocalBookCatalog.path(item.resourceFile || item.href || '') !== path) continue;
      const href = item.href ?? '';
      const hash = href.indexOf('#');
      if (hash >= 0 && hash < href.length - 1) {
        const offset = anchors.get(LocalBookCatalog.decode(href.substring(hash + 1)));
        if (offset !== undefined) LocalBookCatalog.mark(marks, item.catalogName, offset);
      } else {
        LocalBookCatalog.mark(marks, item.catalogName, 0);
      }
    }
    return LocalBookCatalog.sections(html, fallback, marks);
  }

  static html(html: string, fallback: string, fileName: string = '', encoding: string = ''): LocalCatalogSection[] {
    const anchors = LocalBookCatalog.anchors(html);
    const marks: LocalCatalogSection[] = [];
    const positions: LocalCatalogSection[] = [];
    const links = /<a\b([^>]*)>([\s\S]*?)<\/a\s*>/gi;
    let link = links.exec(html);
    while (link !== null) {
      const href = /\bhref\s*=\s*["']([^"']+)["']/i.exec(link[1]);
      const filepos = /\bfilepos\s*=\s*["']?(\d+)/i.exec(link[1]);
      if (href !== null) {
        const hash = href[1].indexOf('#');
        const path = LocalBookCatalog.path(href[1]);
        if (hash >= 0 && (!path || path === LocalBookCatalog.path(fileName))) {
          const offset = anchors.get(LocalBookCatalog.decode(href[1].substring(hash + 1)));
          if (offset !== undefined) LocalBookCatalog.mark(marks, link[2], offset);
        }
      } else if (filepos !== null && encoding) {
        LocalBookCatalog.mark(positions, link[2], Number(filepos[1]));
      }
      link = links.exec(html);
    }
    // MOBI filepos 是解压后正文的字节偏移，不能直接当成 UTF-16 字符下标。
    positions.sort((a, b): number => a.start - b.start);
    let bytes = 0;
    let index = 0;
    for (const position of positions) {
      while (index < html.length && bytes < position.start) {
        const code = html.charCodeAt(index);
        if (encoding !== 'utf-8' || code < 128) { bytes++; index++; }
        else if (code < 2048) { bytes += 2; index++; }
        else if (code >= 0xD800 && code <= 0xDBFF && index + 1 < html.length) { bytes += 4; index += 2; }
        else { bytes += 3; index++; }
      }
      if (bytes === position.start && index < html.length) LocalBookCatalog.mark(marks, position.title, index);
    }
    return LocalBookCatalog.sections(html, fallback, marks);
  }
}
