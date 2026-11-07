import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { text } from '@kit.ArkGraphics2D';

export class ReaderImportedFont {
  path: string = '';
  name: string = '';
  family: string = '';
  enabled: boolean = true;
}

export class ReaderFontImportResult {
  fonts: ReaderImportedFont[] = [];
  failures: string[] = [];
}

export class ReaderFontDeleteResult {
  fonts: ReaderImportedFont[] = [];
  failedCount: number = 0;
}

/** 用户字体仅复制到私有目录；同步注册到正文和分页共用的全局字体集合。 */
export class ReaderFontService {
  private static loaded: Set<string> = new Set();

  static register(context: common.Context, path: string): string {
    if (!path.startsWith(`${context.filesDir}/reader_fonts/`) || path.includes('..') || !fileIo.accessSync(path)) {
      throw new Error('Font unavailable');
    }
    const name = `ReaderFont_${path.substring(path.lastIndexOf('/') + 1).replace(new RegExp('[^a-zA-Z0-9]', 'g'), '_')}`;
    if (!ReaderFontService.loaded.has(name)) {
      text.FontCollection.getGlobalInstance().loadFontSync(name, `file://${path}`);
      ReaderFontService.loaded.add(name);
    }
    return name;
  }

  static async list(context: common.Context, legacyPath: string = '', legacyName: string = ''): Promise<ReaderImportedFont[]> {
    const store = await preferences.getPreferences(context, { name: 'reader_fonts' });
    const saved = store.getSync('catalog', '[]');
    let catalog: ReaderImportedFont[] = [];
    try {
      if (typeof saved === 'string') catalog = JSON.parse(saved);
      if (!Array.isArray(catalog)) catalog = [];
    } catch (_e) { catalog = []; }
    const dir = `${context.filesDir}/reader_fonts`;
    const result: ReaderImportedFont[] = [];
    const paths: Set<string> = new Set();
    for (const item of catalog) {
      if (item === null || typeof item.path !== 'string' || typeof item.name !== 'string' ||
        !item.path.startsWith(dir + '/') || item.path.includes('..') || paths.has(item.path)) continue;
      if (!await fileIo.access(item.path)) continue;
      const font = new ReaderImportedFont();
      font.path = item.path; font.name = item.name;
      font.enabled = item.enabled !== false;
      result.push(font); paths.add(font.path);
    }
    // 迁移旧版已导入文件，包括之前被切换掉但仍保留在沙箱的字体。
    if (await fileIo.access(dir)) {
      const files = await fileIo.listFile(dir);
      files.sort();
      for (const filename of files) {
        if (!filename.endsWith('.ttf') && !filename.endsWith('.otf')) continue;
        const path = `${dir}/${filename}`;
        if (paths.has(path)) continue;
        const font = new ReaderImportedFont();
        font.path = path;
        font.name = path === legacyPath && legacyName.length > 0 ? legacyName : filename;
        result.push(font); paths.add(path);
      }
    }
    await ReaderFontService.saveCatalog(context, result);
    return result;
  }

  static async remove(context: common.Context, path: string): Promise<ReaderImportedFont[]> {
    const result = await ReaderFontService.removeBatch(context, [path]);
    if (result.failedCount > 0) throw new Error('Font deletion failed');
    return result.fonts;
  }

  static async listEnabled(context: common.Context, legacyPath: string = '',
    legacyName: string = ''): Promise<ReaderImportedFont[]> {
    return (await ReaderFontService.list(context, legacyPath, legacyName))
      .filter((font: ReaderImportedFont): boolean => font.enabled);
  }

  static async setEnabled(context: common.Context, paths: string[], enabled: boolean): Promise<ReaderImportedFont[]> {
    const catalog = await ReaderFontService.list(context);
    const selected = new Set(paths);
    for (const font of catalog) {
      if (selected.has(font.path)) font.enabled = enabled;
    }
    await ReaderFontService.saveCatalog(context, catalog);
    return catalog;
  }

  static async reorder(context: common.Context, paths: string[]): Promise<ReaderImportedFont[]> {
    const catalog = await ReaderFontService.list(context);
    const byPath: Map<string, ReaderImportedFont> = new Map();
    for (const font of catalog) byPath.set(font.path, font);
    const ordered: ReaderImportedFont[] = [];
    for (const path of paths) {
      const font = byPath.get(path);
      if (font) { ordered.push(font); byPath.delete(path); }
    }
    for (const font of catalog) {
      if (byPath.has(font.path)) ordered.push(font);
    }
    await ReaderFontService.saveCatalog(context, ordered);
    return ordered;
  }

  static async removeBatch(context: common.Context, paths: string[]): Promise<ReaderFontDeleteResult> {
    const catalog = await ReaderFontService.list(context);
    const selected = new Set(paths);
    const result = new ReaderFontDeleteResult();
    for (const font of catalog) {
      if (selected.has(font.path)) {
        try { await fileIo.unlink(font.path); }
        catch (_error) { result.fonts.push(font); result.failedCount++; }
      } else { result.fonts.push(font); }
    }
    await ReaderFontService.saveCatalog(context, result.fonts);
    return result;
  }

  private static async saveCatalog(context: common.Context, fonts: ReaderImportedFont[]): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'reader_fonts' });
    const previous = store.getSync('catalog', '[]');
    store.putSync('catalog', JSON.stringify(fonts));
    try { await store.flush(); }
    catch (error) {
      store.putSync('catalog', previous);
      throw new Error(error instanceof Error ? error.message : 'Font catalog save failed');
    }
  }

  static async pick(context: common.UIAbilityContext): Promise<ReaderFontImportResult> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 5;
    options.fileSuffixFilters = ['Font|.ttf,.otf'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    const result = new ReaderFontImportResult();
    if (uris.length === 0) return result;
    const catalog = await ReaderFontService.list(context);
    for (let index = 0; index < Math.min(5, uris.length); index++) {
      try {
        const font = await ReaderFontService.importOne(context, uris[index], index);
        catalog.push(font);
        try { await ReaderFontService.saveCatalog(context, catalog); }
        catch (error) {
          catalog.pop();
          await fileIo.unlink(font.path).catch((): void => {});
          throw new Error(error instanceof Error ? error.message : 'Font catalog save failed');
        }
        result.fonts.push(font);
      } catch (_e) { result.failures.push(uris[index]); }
    }
    return result;
  }

  private static async importOne(context: common.UIAbilityContext, uri: string, index: number): Promise<ReaderImportedFont> {
    const source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    let path = '';
    try {
      const size = (await fileIo.stat(source.fd)).size;
      if (size < 12 || size > 32 * 1024 * 1024) throw new Error('Invalid font size');
      const header = new ArrayBuffer(4);
      await fileIo.read(source.fd, header, { offset: 0, length: 4 });
      const magic = new Uint8Array(header);
      const ttf = magic[0] === 0 && magic[1] === 1 && magic[2] === 0 && magic[3] === 0;
      const otf = magic[0] === 79 && magic[1] === 84 && magic[2] === 84 && magic[3] === 79;
      if (!ttf && !otf) throw new Error('Invalid font format');
      const dir = `${context.filesDir}/reader_fonts`;
      if (!await fileIo.access(dir)) await fileIo.mkdir(dir, true);
      path = `${dir}/font_${Date.now()}_${index}.${otf ? 'otf' : 'ttf'}`;
      await fileIo.copyFile(source.fd, path);
      const result = new ReaderImportedFont();
      result.path = path;
      result.name = decodeURIComponent(uri.substring(uri.lastIndexOf('/') + 1));
      result.family = ReaderFontService.register(context, path);
      return result;
    } catch (error) {
      if (path.length > 0) await fileIo.unlink(path).catch((): void => {});
      throw new Error(error instanceof Error ? error.message : 'Font import failed');
    } finally {
      await fileIo.close(source);
    }
  }
}
