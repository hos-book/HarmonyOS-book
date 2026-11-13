/** 分类键稳定保存，系统菜单项的身份和处理函数不参与序列化。 */
export class ReaderSelectionSettings {
  static readonly defaults: string[] = ['listen', 'excerpt', 'summarize', 'translate', 'dictionary',
    'copy', 'share', 'search', 'selectAll', 'other'];

  static order(value: string): string[] {
    const result: string[] = [];
    for (const key of value.split(',')) {
      if (ReaderSelectionSettings.defaults.includes(key) && !result.includes(key)) result.push(key);
    }
    for (const key of ReaderSelectionSettings.defaults) if (!result.includes(key)) result.push(key);
    return result;
  }

  static hidden(value: string): string[] {
    return ReaderSelectionSettings.defaults.filter((key: string): boolean => value.split(',').includes(key));
  }

  static label(key: string): Resource {
    switch (key) {
      case 'listen': return $r('app.string.reader_listen_from_paragraph');
      case 'excerpt': return $r('app.string.reader_excerpt_save');
      case 'summarize': return $r('app.string.reader_ai_summarize');
      case 'translate': return $r('app.string.selection_translate');
      case 'dictionary': return $r('app.string.selection_dictionary');
      case 'copy': return $r('app.string.selection_copy');
      case 'share': return $r('app.string.selection_share');
      case 'search': return $r('app.string.selection_search');
      case 'selectAll': return $r('app.string.selection_select_all');
      default: return $r('app.string.selection_other');
    }
  }
}
