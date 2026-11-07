import { LocalBookImportService, LocalImportFile, LocalBookPreview } from '../service/LocalBookImportService';
import { LocalBookCover } from '../components/LocalBookCover';
import { BookGroupSheet } from '../components/BookGroupSheet';
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { zlib, emitter, BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { media } from '@kit.MediaKit';
import { AppColor, AppRadius, AppSpace, AppFont, AppTheme } from '../theme/Theme';
import { CoverDecoration } from '../components/CoverDecoration';
import { Book } from '../model/Book';
import { DataService } from '../service/DataService';
import { PreferenceService } from '../service/PreferenceService';
import { WindowUtils } from '../utils/WindowUtils';
import { FileOpenRouting } from '../utils/FileOpenRouting';
import { DiagnosticLogService } from '../service/DiagnosticLogService';
import { ImmersiveOptionTabs } from '../components/ImmersiveOptionTabs';
import { EpubImportMode } from '../service/text/EpubContentProfile';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';

export const EVT_SWITCH_TAB = 'app.nav.switchTab';
const TAB_INDEX_FAVORITE = 1;

@ObservedV2
class PickedFile extends LocalImportFile {
  @Trace preview: LocalBookPreview | null = null;
  @Trace previewFailed: boolean = false;
}

class ImportFileDataSource implements IDataSource {
  private files: PickedFile[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.files.length; }
  getData(index: number): PickedFile { return this.files[index]; }
  setFiles(files: PickedFile[]): void {
    this.files = files;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
}

@ComponentV2
export struct ImportPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param importFileUri: string = '';
  @Param importFileType: string = '';
  @Local epubMode: EpubImportMode = 'auto';
  private externalImportConsumed: boolean = false;
  @Local bookTitle: string = '';
  @Local shelfGroup: string = '';
  @Local shelfGroups: string[] = [];
  @Local showGroupSheet: boolean = false;
  @Local bookAuthor: string = '';
  @Local pickedFiles: PickedFile[] = [];
  @Local coverPath: string = '';
  @Local importing: boolean = false;
  @Local parsing: boolean = false;
  @Local showImportHelp: boolean = false;
  @Local contentWidth: number = 0;
  private disposed: boolean = false;
  private autoTitle: string = '';
  private autoAuthor: string = '';
  private autoCover: string = '';
  @Local importDone: boolean = false;
  @Local progressText: string = '';

  private context: common.UIAbilityContext | null = null;
  private importedCount: number = 0;
  private importFailures: string[] = [];
  private fileDataSource: ImportFileDataSource = new ImportFileDataSource();

  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.disposed = false;
    if (this.importFileUri.length > 0 && !this.externalImportConsumed) {
      this.externalImportConsumed = true;
      this.addPickedUris([this.importFileUri], this.importFileType).catch((error: BusinessError): void => {
        DiagnosticLogService.failure('import.external', error);
        if (!this.disposed && this.context !== null) {
          this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_external_failed').id);
        }
      });
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (!this.importing) this.releasePreviews();
  }

  private releasePreviews(): void {
    for (const file of this.pickedFiles) {
      if (file.preview !== null && file.preview.directory.length > 0) {
        LocalBookImportService.releasePreview(file.preview);
      }
    }
  }

  private async previewFiles(files: PickedFile[]): Promise<void> {
    if (this.context === null) return;
    this.parsing = true;
    this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_reading_metadata').id);
    let failures = 0;
    try {
      for (const file of files) {
        if (this.disposed) break;
        if (file.preview !== null) continue;
        try {
          file.preview = await LocalBookImportService.preview(this.context, file);
          file.previewFailed = false;
          if (this.disposed && file.preview.directory.length > 0) {
            await LocalBookImportService.releasePreview(file.preview);
          }
        } catch (error) {
          file.previewFailed = true;
          failures++;
          DiagnosticLogService.failure('import.preview', error, `format=${file.ext}`);
        }
      }
      if (this.disposed) return;
      if (files.length === 1 && files[0].preview !== null) {
        const info = files[0].preview;
        if (!this.bookTitle || this.bookTitle === this.autoTitle) this.bookTitle = info.title;
        if (!this.bookAuthor || this.bookAuthor === this.autoAuthor) this.bookAuthor = info.author;
        if (!this.coverPath || this.coverPath === this.autoCover) this.coverPath = info.cover;
        this.autoTitle = info.title; this.autoAuthor = info.author; this.autoCover = info.cover;
      } else if (!this.usesSharedBookInfo()) {
        this.bookTitle = ''; this.bookAuthor = ''; this.coverPath = '';
        this.autoTitle = ''; this.autoAuthor = ''; this.autoCover = '';
      } else {
        if (this.bookTitle === this.autoTitle) this.bookTitle = '';
        if (this.bookAuthor === this.autoAuthor) this.bookAuthor = '';
        if (this.coverPath === this.autoCover) this.coverPath = '';
        this.autoTitle = ''; this.autoAuthor = ''; this.autoCover = '';
      }
      this.progressText = failures > 0 ?
        this.context.resourceManager.getStringSync($r('app.string.import_metadata_failed').id) : '';
    } finally { this.parsing = false; }
  }

  private async pickFiles(): Promise<void> {
    if (this.importing || this.parsing) return;
    try {
      const opt = new picker.DocumentSelectOptions();
      opt.maxSelectNumber = 500;
      opt.fileSuffixFilters = [this.context!.resourceManager.getStringSync($r('app.string.import_file_filter').id)];
      const dp = new picker.DocumentViewPicker(this.context!);
      const uris = await dp.select(opt);
      DiagnosticLogService.info('import.pick', `selected=${uris?.length || 0}`);
      if (!uris || uris.length === 0) return;
      await this.addPickedUris(uris);
    } catch (e) {
      DiagnosticLogService.failure('import.pick', e);
      if (!this.disposed && this.context !== null) {
        this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_pick_failed').id);
      }
    }
  }

  private async addPickedUris(uris: string[], fileType: string = ''): Promise<void> {
    const files: PickedFile[] = this.pickedFiles.slice();
    for (const uri of uris) {
      const ext = FileOpenRouting.extension(uri, fileType);
      if (ext !== '.zip' && !LocalBookImportService.TEXT_EXTS.includes(ext) && !this.isAudioExt(ext)) continue;
      if (files.some((file: PickedFile): boolean => file.uri === uri)) continue;
      const fullName = FileOpenRouting.fileName(uri);
      const file = new PickedFile();
      file.uri = uri;
      file.ext = ext;
      file.name = fullName.toLowerCase().endsWith(ext) ? fullName.substring(0, fullName.length - ext.length) : fullName;
      files.push(file);
    }
    this.pickedFiles = files;
    this.fileDataSource.setFiles(files);
    await this.previewFiles(files);
    if (files.length === 0 && this.context !== null && !this.disposed) {
      this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_external_failed').id);
    }
  }

  private async pickCover(): Promise<void> {
    if (this.importing || this.parsing) return;
    try {
      const opt = new photoAccessHelper.PhotoSelectOptions();
      opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      opt.maxSelectNumber = 1;
      const pp = new photoAccessHelper.PhotoViewPicker();
      const result = await pp.select(opt);
      if (!result || !result.photoUris || result.photoUris.length === 0) return;
      const srcUri = result.photoUris[0];
      const ext = this.extractExt(srcUri) || '.jpg';
      const dir = this.context!.filesDir + '/covers';
      try { await fileIo.mkdir(dir, true); } catch (_e) { /* exists */ }
      const dest = `${dir}/cover_${Date.now()}${ext}`;
      const src = await fileIo.open(srcUri, fileIo.OpenMode.READ_ONLY);
      const dst = await fileIo.open(dest, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.copyFile(src.fd, dst.fd);
      await fileIo.close(src);
      await fileIo.close(dst);
      this.coverPath = dest;
    } catch (e) {
      // cancelled
    }
  }

  private extractExt(uri: string): string {
    try {
      const fullName = new fileUri.FileUri(uri).name;
      const dotIdx = fullName.lastIndexOf('.');
      return dotIdx > 0 ? fullName.substring(dotIdx).toLowerCase() : '';
    } catch (_e) {
      return '';
    }
  }

  private isAudioExt(ext: string): boolean {
    return LocalBookImportService.AUDIO_EXTS.includes(ext);
  }

  /**
   * 自然排序：把"第1集"、"第10集"、"track 02" 这类文件名按数字段大小比较。
   * 拆为 [文本, 数字, 文本, ...] 数组，逐段对比，数字段当数字比，文本段忽略大小写按 locale 比。
   */
  private naturalCompare(a: string, b: string): number {
    const tokenize = (s: string): string[] => {
      const arr: string[] = [];
      const re = /(\d+)|(\D+)/g;
      let m: RegExpExecArray | null = re.exec(s);
      while (m !== null) {
        arr.push(m[0]);
        m = re.exec(s);
      }
      return arr;
    };
    const sa = tokenize(a.toLowerCase());
    const sb = tokenize(b.toLowerCase());
    const len = Math.min(sa.length, sb.length);
    for (let i = 0; i < len; i++) {
      const xa = sa[i];
      const xb = sb[i];
      const na = parseInt(xa, 10);
      const nb = parseInt(xb, 10);
      const aIsNum = !isNaN(na) && /^\d+$/.test(xa);
      const bIsNum = !isNaN(nb) && /^\d+$/.test(xb);
      if (aIsNum && bIsNum) {
        if (na !== nb) return na - nb;
      } else {
        if (xa < xb) return -1;
        if (xa > xb) return 1;
      }
    }
    return sa.length - sb.length;
  }

  /**
   * 解压一个 zip 到沙箱临时目录，递归收集其中所有支持的音频/小说文件，转为 PickedFile。
   * zip 文件本身需要先复制到沙箱（zlib.decompressFile 不接受 file:// content uri）。
   */
  private async expandZip(pf: PickedFile, extractRoot: string): Promise<PickedFile[]> {
    const stamp = Date.now().toString() + '_' + Math.floor(Math.random() * 1000);
    const cachedZip = `${extractRoot}/_src_${stamp}.zip`;
    const outDir = `${extractRoot}/unpacked_${stamp}`;

    const compressedSize = await LocalBookImportService.fileSize(pf.uri);
    if (compressedSize > LocalBookImportService.MAX_ARCHIVE_BYTES) throw new Error('ZIP 超过 32 GiB');
    await LocalBookImportService.requireSpace(this.context!, compressedSize);
    // 把 content uri 的 zip 复制到沙箱；try/finally 确保异常时也关闭 fd，避免泄漏
    let sf: fileIo.File | null = null;
    let df: fileIo.File | null = null;
    try {
      await fileIo.mkdir(outDir, true);
      sf = await fileIo.open(pf.uri, fileIo.OpenMode.READ_ONLY);
      df = await fileIo.open(cachedZip, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      await fileIo.copyFile(sf.fd, df.fd);
    } catch (e) {
      throw new Error('准备解压失败: ' + (e as Error).message);
    } finally {
      if (sf) { try { await fileIo.close(sf); } catch (_e) { /* ignore */ } }
      if (df) { try { await fileIo.close(df); } catch (_e) { /* ignore */ } }
    }

    const originalSize = await zlib.getOriginalSize(cachedZip);
    if (originalSize > LocalBookImportService.MAX_EXPANDED_BYTES) throw new Error('ZIP 解压内容超过 64 GiB');
    await LocalBookImportService.requireSpace(this.context!, originalSize);
    this.progressText = `解压 ${pf.name}.zip`;
    await new Promise<void>((resolve, reject) => {
      zlib.decompressFile(cachedZip, outDir, {}, (err) => {
        if (err) reject(new Error(err.message || '解压失败'));
        else resolve();
      });
    });
    try { await fileIo.unlink(cachedZip); } catch (_e) { /* ignore */ }

    const collected: PickedFile[] = [];
    await this.walkDir(outDir, collected);
    return collected;
  }

  /**
   * 递归遍历目录，把音频/小说文件收集为 PickedFile（uri 用沙箱绝对路径，AVPlayer/fileIo 都能识别）。
   */
  private async walkDir(root: string, out: PickedFile[]): Promise<void> {
    const pending: string[] = [root];
    let entriesCount = 0;
    while (pending.length > 0) {
      const dir = pending.pop();
      if (!dir) continue;
      const entries = await fileIo.listFile(dir);
      for (const name of entries) {
        if (++entriesCount > 100000) throw new Error('ZIP 超过 100000 个文件或目录');
        const full = `${dir}/${name}`;
        const stat = await fileIo.lstat(full);
        if (stat.isSymbolicLink()) continue;
        if (stat.isDirectory()) { pending.push(full); continue; }
        const dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        const ext = name.substring(dot).toLowerCase();
        if (this.isAudioExt(ext) || LocalBookImportService.TEXT_EXTS.includes(ext)) {
          if (out.length >= LocalBookImportService.MAX_CHAPTERS) throw new Error('ZIP 超过 50000 个可导入文件');
          const file = new PickedFile();
          file.uri = full; file.name = name.substring(0, dot); file.ext = ext;
          out.push(file);
        }
      }
    }
  }

  private async saveImported(book: Book): Promise<void> {
    try {
      await DataService.addImportedBook(book);
      DiagnosticLogService.info('import.save', `chapters=${book.chapters.length}; type=${book.contentType || 'audio'}`);
    } catch (error) {
      DiagnosticLogService.failure('import.save', error);
      throw new Error(DiagnosticLogService.describe(error));
    }
    this.importedCount++;
    try {
      await PreferenceService.setBookGroup([book.id], this.shelfGroup, this.shelfGroups);
    } catch (error) {
      DiagnosticLogService.failure('import.shelfGroup', error);
      this.importFailures.push(this.context!.resourceManager.getStringSync($r('app.string.import_group_failed').id, book.title));
    }
    try {
      if (!await PreferenceService.isFavorite(book.id)) await PreferenceService.toggleFavorite(book.id);
    } catch (error) {
      DiagnosticLogService.failure('import.favorite', error);
      this.importFailures.push(`${book.title}: 已保存，加入书架失败`);
    }
  }

  private async importGroup(files: PickedFile[], title: string, batchId: string,
    extractRoot: string): Promise<number> {
    files.sort((a: PickedFile, b: PickedFile): number => this.naturalCompare(a.name, b.name));
    let imported = 0;
    const audio = files.filter((file: PickedFile): boolean => this.isAudioExt(file.ext));
    if (audio.length > LocalBookImportService.MAX_CHAPTERS) throw new Error('单本音频超过 50000 集');
    if (audio.length > 0) {
      const id = `${batchId}_audio`;
      const directory = `${this.context!.filesDir}/audio/${id}`;
      await fileIo.mkdir(directory, true);
      try {
        const book = await this.importAudioBook(id, directory, audio, extractRoot);
        book.title = title || audio[0].name;
        await this.saveImported(book);
        imported++;
      } catch (error) {
        try { await fileIo.rmdir(directory); } catch (_cleanup) { /* 保留错误 */ }
        DiagnosticLogService.failure('import.audio', error, `files=${audio.length}`);
        this.importFailures.push(error instanceof Error ? error.message : String(error));
      }
    }
    const ebooks = files.filter((file: PickedFile): boolean => LocalBookImportService.TEXT_EXTS.includes(file.ext));
    for (let index = 0; index < ebooks.length; index++) {
      const file = ebooks[index];
      try {
        const book = await LocalBookImportService.importBook(this.context!, file, `${batchId}_text_${index}`,
          files.length === 1 ? title : file.preview?.title || '',
          (this.usesSharedBookInfo() ? this.bookAuthor : '') || file.preview?.author || '',
          (this.usesSharedBookInfo() ? this.coverPath : '') || file.preview?.cover || '',
          (progress: string): void => { this.progressText = progress; }, this.epubMode);
        await this.saveImported(book);
        imported++;
      } catch (error) {
        DiagnosticLogService.failure('import.ebook', error, `format=${file.ext}`);
        this.importFailures.push(`${file.name}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }
    return imported;
  }

  private async doImport(): Promise<void> {
    if (this.importing || this.parsing || this.pickedFiles.length === 0 || this.context === null) return;
    this.importing = true;
    this.importedCount = 0;
    this.importFailures = [];
    const batchId = 'import_' + Date.now().toString();
    DiagnosticLogService.info('import.start', `batch=${batchId}; files=${this.pickedFiles.length}; ` +
      `formats=${this.pickedFiles.map((file: PickedFile): string => file.ext).filter((ext: string, index: number,
        all: string[]): boolean => all.indexOf(ext) === index).join(',')}`);
    const extractRoot = `${this.context.cacheDir}/import_extract_${batchId}`;
    let imported = 0;
    const failures = this.importFailures;
    try {
      const direct = this.pickedFiles.filter((file: PickedFile): boolean => file.ext !== '.zip');
      if (direct.length > 0) {
        try { imported += await this.importGroup(direct, this.bookTitle, batchId, extractRoot); }
        catch (error) {
          DiagnosticLogService.failure('import.group', error);
          failures.push(error instanceof Error ? error.message : String(error));
        }
      }
      const archives = this.pickedFiles.filter((file: PickedFile): boolean => file.ext === '.zip');
      for (let index = 0; index < archives.length; index++) {
        try {
          await fileIo.mkdir(extractRoot, true);
          const files = await this.expandZip(archives[index], extractRoot);
          if (files.length === 0) throw new Error('压缩包中没有支持的音频或电子书');
          imported += await this.importGroup(files,
            archives.length === 1 && direct.length === 0 ? this.bookTitle || archives[index].name : archives[index].name,
            `${batchId}_zip_${index}`, extractRoot);
        } catch (error) {
          DiagnosticLogService.failure('import.zip', error);
          failures.push(`${archives[index].name}: ${error instanceof Error ? error.message : String(error)}`);
        } finally {
          try { await fileIo.rmdir(extractRoot); } catch (_cleanup) { /* 无残留目录 */ }
        }
      }
      imported = this.importedCount;
      DiagnosticLogService.info('import.finish', `batch=${batchId}; saved=${imported}; failures=${failures.length}`);
      this.importDone = imported > 0;
      if (failures.length > 0) {
        this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_partial_result').id,
          imported, failures.join('\n'));
      } else if (imported > 0) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.import_success') });
        emitter.emit(EVT_SWITCH_TAB, { data: { index: TAB_INDEX_FAVORITE } });
        this.navStack.pop();
      } else {
        this.progressText = this.context.resourceManager.getStringSync($r('app.string.import_no_files').id);
      }
    } finally {
      this.importing = false;
      if (this.disposed) this.releasePreviews();
    }
  }

  private async probeAudioDuration(path: string): Promise<number> {
    let f: fileIo.File | null = null;
    let extractor: media.AVMetadataExtractor | null = null;
    try {
      f = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(f.fd);
      if (stat.size <= 0) return 0;
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: f.fd, offset: 0, length: stat.size };
      const meta = await extractor.fetchMetadata();
      // AVMetadata.duration 单位为毫秒(ms)，章节存秒
      const ms = meta && meta.duration ? Number(meta.duration) : 0;
      return ms > 0 ? Math.round(ms / 1_000) : 0;
    } catch (_e) {
      return 0;
    } finally {
      if (extractor) {
        try { await extractor.release(); } catch (_e) { /* ignore */ }
      }
      if (f) {
        try { await fileIo.close(f); } catch (_e) { /* ignore */ }
      }
    }
  }

  private async importAudioBook(bookId: string, sandboxDir: string, files: PickedFile[], extractRoot: string): Promise<Book> {
    const chapters = await LocalBookImportService.importAudioChapters(this.context!, bookId, sandboxDir,
      files, extractRoot, (path: string): Promise<number> => this.probeAudioDuration(path),
      (completed: number, total: number): void => { this.progressText = `导入音频 ${completed}/${total}`; });
    return {
      id: bookId, title: this.bookTitle, author: this.bookAuthor || '未知',
      narrator: '', cover: this.coverPath, category: 'import', intro: '本地导入',
      totalDuration: 0, chapterCount: chapters.length, rating: 0,
      tags: ['本地导入'], chapters: chapters, bookUrl: '', sourceUrl: ''
    };
  }

  // PLACEHOLDER_BUILD
  @Builder
  buildGroupSheet() {
    BookGroupSheet({ initialGroup: this.shelfGroup, initialGroups: this.shelfGroups,
      onConfirm: async (group: string, groups: string[]): Promise<void> => {
        this.shelfGroup = group;
        this.shelfGroups = groups;
        this.showGroupSheet = false;
      } })
  }

  private usesSharedBookInfo(): boolean {
    return this.pickedFiles.length === 1 || (this.pickedFiles.length > 0 &&
      this.pickedFiles.every((file: PickedFile): boolean => this.isAudioExt(file.ext)));
  }

  private async removeFile(file: PickedFile): Promise<void> {
    if (this.importing || this.parsing) return;
    this.pickedFiles = this.pickedFiles.filter((item: PickedFile): boolean => item.uri !== file.uri);
    this.fileDataSource.setFiles(this.pickedFiles);
    this.bookTitle = ''; this.bookAuthor = ''; this.coverPath = '';
    this.autoTitle = ''; this.autoAuthor = ''; this.autoCover = '';
    if (file.preview !== null) await LocalBookImportService.releasePreview(file.preview);
    if (!this.disposed) await this.previewFiles(this.pickedFiles);
  }

  build() {
    Column() {
      Row({ space: AppSpace.Sm }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24)
            .fontColor([$r('sys.color.font_primary')])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .enabled(!this.importing).onClick((): void => { this.navStack.pop(); })
        Text($r('app.string.profile_local_import'))
          .fontSize(AppFont.Title).fontColor($r('sys.color.font_primary')).fontWeight(FontWeight.Bold)
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(22)
            .fontColor([$r('sys.color.font_secondary')])
        }.width(40).height(40).backgroundColor(Color.Transparent)
          .accessibilityText(this.showImportHelp ? $r('app.string.import_help_collapse') :
            $r('app.string.import_help_expand'))
          .onClick((): void => { this.showImportHelp = !this.showImportHelp; })
      }.width('100%')
        .padding({ top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
          left: AppSpace.Sm, right: AppSpace.Md, bottom: AppSpace.Sm })

      Stack({ alignContent: Alignment.BottomEnd }) {
        List() {
          ListItemGroup({ header: this.buildFileSection(), footer: this.buildImportOptions(), space: AppSpace.Sm }) {
            if (this.pickedFiles.length > 1) {
              LazyForEach(this.fileDataSource, (file: PickedFile) => {
                ListItem() { this.buildBookPreview(file) }
              }, (file: PickedFile): string => file.uri)
            }
          }
        }.width('100%').height('100%')
          .lanes(this.pickedFiles.length > 1 && this.contentWidth >= AdaptiveLayout.MEDIUM_WIDTH ? 2 : 1, AppSpace.Sm)
          .padding({ left: AppSpace.Md, right: AppSpace.Md })
          .contentEndOffset(88).scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          Stack() {
            ImmersiveCircleButton({ icon: $r('sys.symbol.plus'), label: $r('app.string.import_add_files'),
              diameter: 56, iconSize: 28, iconColor: $r('sys.color.font_primary') })
            Row().width(56).height(56).backgroundColor($r('app.color.import_add_button_tint'))
          }.width(56).height(56).borderRadius(28).clip(true)
            .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        }.width(56).height(56).padding(0).backgroundColor(Color.Transparent)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
          .accessibilityText($r('app.string.import_add_files'))
          .enabled(!this.importing && !this.parsing).onClick((): void => { this.pickFiles(); })
          .opacity(this.importing || this.parsing ? 0.45 : 1)
          .margin({ right: AppSpace.Lg, bottom: AppSpace.Md })
      }.width('100%').layoutWeight(1)
        .onSizeChange((_previous: SizeOptions, current: SizeOptions): void => {
          this.contentWidth = Number(current.width);
        })
      this.buildActionBar()
    }.width('100%').height('100%').backgroundColor(AppTheme.Background)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildFileSection() {
    Column({ space: AppSpace.Sm }) {
      if (this.showImportHelp) {
        Column({ space: AppSpace.Sm }) {
          Text($r('app.string.import_supported_formats')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
          Text($r('app.string.import_limits_hint')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_secondary')).width('100%')
        }.width('100%').padding(AppSpace.Md)
          .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
      }
      if (this.pickedFiles.length === 0) {
        Column({ space: AppSpace.Sm }) {
          Text($r('app.string.import_empty_title')).fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary')).fontWeight(FontWeight.Medium)
          Text($r('app.string.import_empty_hint')).fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_tertiary'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: AppSpace.Lg })
      } else {
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.import_selected_files', this.pickedFiles.length))
            .fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1)
          if (this.parsing) { LoadingProgress().width(20).height(20).color(AppColor.Brand) }
          if (this.pickedFiles.length === 1) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([$r('sys.color.font_tertiary')])
            }.width(40).height(40).backgroundColor(Color.Transparent)
              .accessibilityText($r('app.string.import_remove_file')).enabled(!this.importing && !this.parsing)
              .onClick((): void => { this.removeFile(this.pickedFiles[0]); })
          }
        }.width('100%').constraintSize({ minHeight: 40 })
        if (this.pickedFiles.length > 1) {
          Text($r('app.string.import_batch_preview_hint')).fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary')).width('100%')
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: AppSpace.Md })
  }

  @Builder
  buildBookPreview(file: PickedFile) {
    Row({ space: AppSpace.Sm }) {
      Stack() {
        LocalBookCover({ title: file.preview?.title || file.name, author: file.preview?.author || '',
          imgWidth: 72, imgHeight: 100, useFixedHeight: true, radius: AppRadius.Sm, themedDecoration: false })
        if (file.preview?.cover) {
          Image('file://' + file.preview!.cover).width(72).height(100)
            .objectFit(ImageFit.Cover).borderRadius(AppRadius.Sm).draggable(false)
        }
        CoverDecoration({ radius: AppRadius.Sm })
      }.width(72).height(100)
      Column({ space: 6 }) {
        Text(file.preview?.title || file.name).fontSize(AppFont.BodyL).fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(file.preview?.author || $r('app.string.import_author_unknown')).fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(file.name + file.ext).fontSize(AppFont.Caption).fontColor($r('sys.color.font_tertiary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: AppSpace.Sm }) {
          Text(file.ext.substring(1).toUpperCase()).fontSize(10).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary')).padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor($r('sys.color.comp_background_tertiary')).borderRadius(4)
          if (file.previewFailed) {
            Text($r('app.string.import_preview_unavailable')).fontSize(10)
              .fontColor($r('sys.color.font_tertiary')).maxLines(1).layoutWeight(1)
          } else if (file.ext === '.zip') {
            Text($r('app.string.import_archive_preview_hint')).fontSize(10)
              .fontColor($r('sys.color.font_tertiary')).maxLines(1).layoutWeight(1)
          } else if (this.isAudioExt(file.ext)) {
            Text($r('app.string.import_audio_preview_hint')).fontSize(10)
              .fontColor($r('sys.color.font_tertiary')).maxLines(1).layoutWeight(1)
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([$r('sys.color.font_tertiary')])
      }.width(32).height(40).backgroundColor(Color.Transparent).alignSelf(ItemAlign.Start)
        .accessibilityText($r('app.string.import_remove_named_file', file.name))
        .enabled(!this.importing && !this.parsing).onClick((): void => { this.removeFile(file); })
    }.width('100%').padding(AppSpace.Sm)
      .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
  }

  @Builder
  buildImportOptions() {
    Column({ space: AppSpace.Lg }) {
      if (this.pickedFiles.length > 0) {
        if (this.usesSharedBookInfo()) { this.buildCoverSection() }
        if (this.pickedFiles.some((file: PickedFile): boolean =>
          file.ext === '.epub' || file.ext === '.mobi' || file.ext === '.cba' ||
          file.ext === '.pdf' || file.ext === '.zip')) {
          this.buildEpubModeSection()
        }
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.book_group_action')).fontSize(AppFont.Body)
            .fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Text(this.shelfGroup || $r('app.string.shelf_group_none')).fontColor($r('sys.color.font_primary'))
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('sys.color.font_primary')])
        }.width('100%').padding(AppSpace.Md).borderRadius(AppRadius.Lg)
          .backgroundColor($r('sys.color.comp_background_secondary'))
          .enabled(!this.importing && !this.parsing).onClick((): void => { this.showGroupSheet = true; })
          .bindSheet($$this.showGroupSheet, this.buildGroupSheet(), {
            height: '65%', detents: ['65%', '45%', SheetSize.LARGE],
            preferType: SheetType.BOTTOM, dragBar: true, showClose: true
          })
      }
    }.width('100%').padding({ top: this.pickedFiles.length > 1 ? AppSpace.Lg : 0 })
  }

  // PLACEHOLDER_BUILDERS
  @Builder
  buildEpubModeSection() {
    Column({ space: AppSpace.Sm }) {
      Text($r('app.string.import_epub_mode')).fontSize(AppFont.Body)
        .fontColor($r('sys.color.font_tertiary'))
      ImmersiveOptionTabs({
        labels: [$r('app.string.import_epub_auto'), $r('app.string.import_epub_text'), $r('app.string.import_epub_comic')],
        selected: this.epubMode === 'auto' ? 0 : this.epubMode === 'text' ? 1 : 2,
        onSelect: (index: number): void => { this.epubMode = index === 0 ? 'auto' : index === 1 ? 'text' : 'comic'; }
      }).enabled(!this.importing && !this.parsing)
      Text($r('app.string.import_epub_mode_hint'))
        .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary'))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildCoverSection() {
    Column({ space: AppSpace.Sm }) {
      if (this.pickedFiles.length > 1) {
        Text($r('app.string.import_audio_book_info')).fontSize(AppFont.Body)
          .fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: AppSpace.Md }) {
        Column({ space: AppSpace.Sm }) {
          Stack() {
            LocalBookCover({ title: this.bookTitle, author: this.bookAuthor,
              imgWidth: 80, imgHeight: 112, useFixedHeight: true, radius: AppRadius.Sm, themedDecoration: false })
            if (this.coverPath) {
              Image('file://' + this.coverPath).width(80).height(112)
                .borderRadius(AppRadius.Sm).objectFit(ImageFit.Cover).draggable(false)
            }
            CoverDecoration({ radius: AppRadius.Sm })
          }.width(80).height(112).onClick((): void => { this.pickCover(); })
          Text($r('app.string.import_edit_cover')).fontSize(AppFont.Caption).fontColor($r('sys.color.font_primary'))
            .onClick((): void => { this.pickCover(); })
        }
        Column({ space: AppSpace.Sm }) {
          TextInput({ placeholder: $r('app.string.import_title_optional'), text: this.bookTitle!! })
            .height(44).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
            .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(AppRadius.Md)
          TextInput({ placeholder: $r('app.string.import_author_optional'), text: this.bookAuthor!! })
            .height(44).fontSize(AppFont.Body).fontColor($r('sys.color.font_primary')).padding({ left: AppSpace.Sm, right: AppSpace.Sm })
            .backgroundColor($r('sys.color.comp_background_secondary')).borderRadius(AppRadius.Md)
          if (this.pickedFiles.length === 1) {
            Text(this.pickedFiles[0].name + this.pickedFiles[0].ext).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.coverPath) {
            Text($r('app.string.import_remove_cover')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_tertiary')).onClick((): void => { this.coverPath = ''; })
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(AppSpace.Md)
        .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
        .enabled(!this.importing && !this.parsing)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildActionBar() {
    Column() {
      if (this.progressText) {
        Scroll() {
          Text(this.progressText)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
            .width('100%')
        }
        .constraintSize({ maxHeight: this.importing ? 48 : 160 })
        .margin({ bottom: AppSpace.Sm })
      }
      Stack() {
        // 视觉内容独立绘制，透明按钮放在最上层，确保中央文字区同样可点。
        Row() {
          Text(this.importing ? $r('app.string.rule_source_importing') : $r('app.string.import_action_start'))
            .fontColor(this.canImport() && !this.importing ?
              $r('sys.color.comp_background_primary') : $r('sys.color.font_tertiary'))
            .fontSize(AppFont.BodyL)
            .fontWeight(FontWeight.Medium)
        }
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')

        Button()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .borderRadius(AppRadius.Md)
          .enabled(this.canImport() && !this.importing)
          .accessibilityText(this.importing ? $r('app.string.rule_source_importing') : $r('app.string.import_action_start'))
          .onClick(() => this.doImport())
      }
      .width('100%')
      .height(48)
      .backgroundColor(this.canImport() && !this.importing ?
        $r('sys.color.font_primary') : $r('sys.color.comp_background_tertiary'))
      .borderRadius(AppRadius.Md)
    }
    .width('100%')
    .padding({
      left: AppSpace.Md, right: AppSpace.Md,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm + WindowUtils.getBottomSafeVp()
    })
    .backgroundColor(AppTheme.Background)
    .border({ width: { top: 0.5 }, color: $r('sys.color.comp_divider') })
  }

  private canImport(): boolean {
    return this.pickedFiles.length > 0 && !this.parsing;
  }

}
