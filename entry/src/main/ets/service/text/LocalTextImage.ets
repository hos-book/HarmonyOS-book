/** 图片占位保留在字符坐标中；朗读使用等长空白，避免听读位置漂移。 */
export class LocalTextImage {
  private static root: string = '';

  static setRoot(filesDir: string): void { LocalTextImage.root = `${filesDir}/ebooks/`; }

  static pattern(): RegExp { return /\uFFF9([^\uFFF9\uFFFB\n]{1,1024})\uFFFB/g; }

  static token(path: string): string { return `\uFFF9${path}\uFFFB`; }

  static resolve(path: string): string {
    if (!LocalTextImage.root || !path.startsWith(LocalTextImage.root)) return '';
    const relative = path.substring(LocalTextImage.root.length);
    return /^import_[A-Za-z0-9_]+\/image_[0-9]+_[0-9]+\.img$/.test(relative) ? `file://${path}` : '';
  }

  static speechContent(content: string): string {
    return content.replace(LocalTextImage.pattern(), (value: string): string => ' '.repeat(value.length));
  }
}
