/** 保留系统菜单（包括设备提供的小艺），追加阅读操作。 */
export class ReaderSelectionMenu {
  static readonly EXCERPT: string = 'reader-save-excerpt';
  static readonly LISTEN: string = 'reader-listen-from-paragraph';
  static readonly DICTIONARY: string = 'reader-ai-dictionary';
  static readonly SUMMARIZE: string = 'reader-ai-summarize';

  static isReaderAction(id: TextMenuItemId): boolean {
    return [ReaderSelectionMenu.EXCERPT, ReaderSelectionMenu.LISTEN, ReaderSelectionMenu.DICTIONARY,
      ReaderSelectionMenu.SUMMARIZE].some((value: string): boolean => id.equals(TextMenuItemId.of(value)));
  }

  static items(listen: boolean = true, systemItems: TextMenuItem[] = []): TextMenuItem[] {
    const customIds: TextMenuItemId[] = [ReaderSelectionMenu.EXCERPT, ReaderSelectionMenu.LISTEN,
      ReaderSelectionMenu.DICTIONARY, ReaderSelectionMenu.SUMMARIZE].map(
      (id: string): TextMenuItemId => TextMenuItemId.of(id));
    const items: TextMenuItem[] = systemItems.filter((item: TextMenuItem): boolean =>
      !customIds.some((id: TextMenuItemId): boolean => id.equals(item.id)));
    items.push({ content: $r('app.string.reader_excerpt_save'),
      id: TextMenuItemId.of(ReaderSelectionMenu.EXCERPT) });
    if (listen) items.push({ content: $r('app.string.reader_listen_from_paragraph'),
      id: TextMenuItemId.of(ReaderSelectionMenu.LISTEN) });
    items.push({ content: $r('app.string.reader_ai_dictionary'), id: TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY) });
    items.push({ content: $r('app.string.reader_ai_summarize'), id: TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE) });
    return items;
  }
}
