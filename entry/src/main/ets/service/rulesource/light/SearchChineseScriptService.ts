import { i18n } from '@kit.LocalizationKit';
import { SearchChineseScript } from './upstream/core/book/SearchChineseScript';

class SearchChineseScriptConverter {
  private readonly traditionalToSimplified: i18n.Transliterator =
    i18n.Transliterator.getInstance('Hant-Hans');
  private readonly simplifiedToTraditional: i18n.Transliterator =
    i18n.Transliterator.getInstance('Hans-Hant');

  toSimplified(text: string): string {
    return this.traditionalToSimplified.transform(text);
  }

  toTraditional(text: string): string {
    return this.simplifiedToTraditional.transform(text);
  }
}

export class SearchChineseScriptService {
  private static readonly converter: SearchChineseScriptConverter = new SearchChineseScriptConverter();

  static create(): SearchChineseScript {
    return new SearchChineseScript(SearchChineseScriptService.converter, new Map<string, string>());
  }

  static toSimplified(text: string): string {
    return SearchChineseScriptService.converter.toSimplified(text);
  }
}
