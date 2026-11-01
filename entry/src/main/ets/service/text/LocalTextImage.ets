export class LocalTextImageSize {
  width: number = 0;
  height: number = 0;
}

/** 图片占位保留在字符坐标中；朗读使用等长空白，避免听读位置漂移。 */
export class LocalTextImage {
  private static root: string = '';
  private static sizes: Map<string, LocalTextImageSize> = new Map();

  static size(path: string): LocalTextImageSize | undefined { return LocalTextImage.sizes.get(path); }

  static rememberSize(path: string, width: number, height: number): void {
    if (!LocalTextImage.resolve(path)) return;
    const size = new LocalTextImageSize();
    size.width = Number.isFinite(width) && width > 0 ? width : 0;
    size.height = Number.isFinite(height) && height > 0 ? height : 0;
    LocalTextImage.sizes.set(path, size);
    if (LocalTextImage.sizes.size > 8192) {
      for (const key of LocalTextImage.sizes.keys()) { LocalTextImage.sizes.delete(key); break; }
    }
  }

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
