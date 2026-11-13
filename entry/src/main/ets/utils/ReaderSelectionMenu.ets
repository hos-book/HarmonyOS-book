import { GeneralSettings } from '../model/GeneralSettings';
import { ReaderSelectionSettings } from '../model/ReaderSelectionSettings';

/** 阅读操作优先，系统翻译、字典保留原始身份与处理链路。 */
export class ReaderSelectionMenu {
  static readonly EXCERPT: string = 'reader-save-excerpt';
  static readonly LISTEN: string = 'reader-listen-from-paragraph';
  static readonly DICTIONARY: string = 'reader-ai-dictionary';
  static readonly SUMMARIZE: string = 'reader-ai-summarize';
  static readonly CONFIGURE: string = 'reader-selection-configure';

  static isReaderAction(id: TextMenuItemId): boolean {
    return [ReaderSelectionMenu.EXCERPT, ReaderSelectionMenu.LISTEN, ReaderSelectionMenu.DICTIONARY,
      ReaderSelectionMenu.SUMMARIZE, ReaderSelectionMenu.CONFIGURE].some((value: string): boolean => id.equals(TextMenuItemId.of(value)));
  }

  private static isTranslation(item: TextMenuItem): boolean {
    return item.id.equals(TextMenuItemId.TRANSLATE) ||
      (typeof item.content === 'string' && /翻译|translat/i.test(item.content));
  }

  private static isDictionary(item: TextMenuItem): boolean {
    return typeof item.content === 'string' && /字典|词典|dictionary/i.test(item.content);
  }

  private static key(item: TextMenuItem): string {
    if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.LISTEN))) return 'listen';
    if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.EXCERPT))) return 'excerpt';
    if (item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE))) return 'summarize';
    if (ReaderSelectionMenu.isTranslation(item)) return 'translate';
    if (ReaderSelectionMenu.isDictionary(item) || item.id.equals(TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY))) return 'dictionary';
    if (item.id.equals(TextMenuItemId.COPY)) return 'copy';
    if (item.id.equals(TextMenuItemId.SHARE)) return 'share';
    if (item.id.equals(TextMenuItemId.SEARCH)) return 'search';
    if (item.id.equals(TextMenuItemId.SELECT_ALL)) return 'selectAll';
    if (item.id.equals(TextMenuItemId.askAI)) return 'other';
    return '';
  }

  static items(listen: boolean = true, systemItems: TextMenuItem[] = []): TextMenuItem[] {
    const customIds: TextMenuItemId[] = [ReaderSelectionMenu.EXCERPT, ReaderSelectionMenu.LISTEN,
      ReaderSelectionMenu.DICTIONARY, ReaderSelectionMenu.SUMMARIZE, ReaderSelectionMenu.CONFIGURE].map(
      (id: string): TextMenuItemId => TextMenuItemId.of(id));
    const system: TextMenuItem[] = systemItems.filter((item: TextMenuItem): boolean =>
      !customIds.some((id: TextMenuItemId): boolean => id.equals(item.id)));
    const items: TextMenuItem[] = [];
    if (listen) items.push({ content: $r('app.string.reader_listen_from_paragraph'),
      icon: $r('app.media.reader_menu_listen'),
      id: TextMenuItemId.of(ReaderSelectionMenu.LISTEN) });
    items.push({ content: $r('app.string.reader_excerpt_save'),
      icon: $r('app.media.reader_menu_excerpt'),
      id: TextMenuItemId.of(ReaderSelectionMenu.EXCERPT) });
    items.push({ content: $r('app.string.reader_ai_summarize'), icon: $r('app.media.reader_menu_summary'),
      id: TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE) });
    items.push(...system.filter((item: TextMenuItem): boolean => ReaderSelectionMenu.isTranslation(item)));
    const dictionaries = system.filter((item: TextMenuItem): boolean => ReaderSelectionMenu.isDictionary(item));
    if (dictionaries.length > 0) items.push(...dictionaries);
    else items.push({ content: $r('app.string.reader_ai_dictionary'),
      icon: $r('app.media.reader_menu_dictionary'),
      id: TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY) });
    items.push(...system.filter((item: TextMenuItem): boolean =>
      !ReaderSelectionMenu.isTranslation(item) && !ReaderSelectionMenu.isDictionary(item)));
    const order = ReaderSelectionSettings.order(GeneralSettings.current.selectionMenuOrder);
    const hidden = ReaderSelectionSettings.hidden(GeneralSettings.current.selectionMenuHidden);
    const result: TextMenuItem[] = [];
    for (const key of order) {
      if (!hidden.includes(key)) result.push(...items.filter((item: TextMenuItem): boolean => ReaderSelectionMenu.key(item) === key));
    }
    result.push({ content: $r('app.string.selection_settings'), icon: $r('app.media.reader_menu_settings'),
      id: TextMenuItemId.of(ReaderSelectionMenu.CONFIGURE) });
    return result;
  }
}
