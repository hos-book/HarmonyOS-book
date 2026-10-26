import { Want } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';

export class LocalImportRouteParams {
  uri: string;
  fileType: string;

  constructor(uri: string, fileType: string) {
    this.uri = uri;
    this.fileType = fileType;
  }
}

/** Route only supported local files. Preserve the original granted URI for all reads. */
export class FileOpenRouting {
  static readonly TEXT_EXTS: string[] = ['.txt', '.epub', '.mobi', '.html', '.htm', '.pdf'];

  static fileName(uri: string): string {
    try {
      const name = new fileUri.FileUri(uri).name;
      if (name.length > 0) return name;
    } catch (_error) { /* content providers may not expose a FileUri name. */ }
    const path = uri.split(/[?#]/)[0];
    const name = path.substring(path.lastIndexOf('/') + 1);
    try { return decodeURIComponent(name); } catch (_error) { return name; }
  }

  static extension(uri: string, fileType: string = ''): string {
    const name = FileOpenRouting.fileName(uri);
    const dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) return name.substring(dot).toLowerCase();
    switch (fileType.split(';')[0].trim().toLowerCase()) {
      case 'general.json':
      case 'application/json':
      case 'text/json': return '.json';
      case 'general.plain-text':
      case 'text/plain': return '.txt';
      case 'general.epub':
      case 'application/epub+zip': return '.epub';
      case 'com.adobe.pdf':
      case 'application/pdf': return '.pdf';
      case 'com.amazon.mobi':
      case 'application/x-mobipocket-ebook': return '.mobi';
      case 'general.html':
      case 'text/html': return '.html';
      case 'general.zip-archive':
      case 'application/zip':
      case 'application/x-zip-compressed': return '.zip';
      default: return '';
    }
  }

  static target(want: Want): string {
    if (want.action !== 'ohos.want.action.viewData' && want.action !== 'ohos.want.action.sendData') return '';
    const uri = want.uri ?? '';
    if (!uri.startsWith('file://') && !uri.startsWith('content://')) return '';
    const ext = FileOpenRouting.extension(uri, want.type ?? '');
    if (ext === '.json') return 'ruleSourceImport';
    return ext === '.zip' || FileOpenRouting.TEXT_EXTS.includes(ext) ? 'localBookImport' : '';
  }
}
