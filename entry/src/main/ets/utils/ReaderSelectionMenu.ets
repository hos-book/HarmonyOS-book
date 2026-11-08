/** 普通正文与 EPUB 共用菜单，替换系统复制、全选等项目。 */
export class ReaderSelectionMenu {
  static readonly LISTEN: string = 'reader-listen-from-paragraph';
  static readonly DICTIONARY: string = 'reader-ai-dictionary';
  static readonly SUMMARIZE: string = 'reader-ai-summarize';

  static items(listen: boolean = true): TextMenuItem[] {
    const items: TextMenuItem[] = [];
    if (listen) items.push({ content: $r('app.string.reader_listen_from_paragraph'),
      id: TextMenuItemId.of(ReaderSelectionMenu.LISTEN) });
    items.push({ content: $r('app.string.reader_ai_dictionary'), id: TextMenuItemId.of(ReaderSelectionMenu.DICTIONARY) });
    items.push({ content: $r('app.string.reader_ai_summarize'), id: TextMenuItemId.of(ReaderSelectionMenu.SUMMARIZE) });
    return items;
  }
}
