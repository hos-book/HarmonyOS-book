import { BookSource } from '../../model/data/Book';
import { NativeSourceSpec } from './NativeSourceSpec';
import type { NativeSourceDefinition } from './NativeSourceSpec';

/** Definition conversion only: no cache invalidation, IO or runtime dependencies. */
export class NativeSourceImport {
  static toBookSource(definition: NativeSourceDefinition, existing: BookSource | null = null): BookSource {
    const source = existing ? Object.assign(new BookSource(), existing) : new BookSource();
    source.bookSourceUrl = definition.url;
    source.bookSourceName = definition.name;
    source.bookSourceGroup = definition.group || '';
    source.bookSourceComment = definition.comment || '';
    source.bookSourceType = NativeSourceSpec.bookSourceType(definition);
    source.concurrentRate = definition.rate || '';
    source.header = NativeSourceImport.literalHeaders(definition);
    source.jsLib = NativeSourceSpec.pack(definition);
    source.searchUrl = definition.search ? NativeSourceSpec.SEARCH_MARKER : '';
    source.exploreUrl = definition.explore ? NativeSourceSpec.EXPLORE_MARKER : '';
    // 登录页地址放进 loginUrl，列表上的登录状态角标和 Cookie 同步沿用现有逻辑。
    source.loginUrl = definition.login && definition.login.url ? definition.login.url : '';
    source.loginUi = '';
    source.loginCheckJs = '';
    source.rawSourceJson = '';
    source.bookUrlPattern = '';
    if (!existing) {
      source.enabled = definition.enabled !== false;
      source.enabledExplore = definition.enabledExplore !== false;
    }
    source.lastUpdateTime = Date.now();
    return source;
  }

  /**
   * 书源记录的 header 只放顶层 headers 里的字面值：应用其他地方（听书、验证页等）把它当固定请求头用。
   * 模板和表达式由运行器在每次请求时求值，不能原样写进去。
   */
  static literalHeaders(definition: NativeSourceDefinition): string {
    const headers = definition.headers || {};
    const literal: Record<string, string> = {};
    for (const name of Object.keys(headers)) {
      const value = String(headers[name]);
      if (value && !value.trim().startsWith('=') && value.indexOf('{{') < 0) literal[name] = value;
    }
    return Object.keys(literal).length > 0 ? JSON.stringify(literal) : '';
  }

  static importObject(value: Object, existing: BookSource | null = null): BookSource {
    return NativeSourceImport.toBookSource(NativeSourceSpec.fromObject(value), existing);
  }
}
