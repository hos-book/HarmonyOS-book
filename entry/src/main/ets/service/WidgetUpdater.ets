import { PlatformCompat } from '../utils/PlatformCompat';
import { LocalBookCoverService } from './LocalBookCoverService';
import lazy { formBindingData, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { PreferenceService, WidgetPlayerSnapshot } from './PreferenceService';
import { Book, Chapter } from '../model/Book';
import { PlayerState } from '../model/PlayerState';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { PlaybackCoordinator } from './PlaybackCoordinator';
import { StorageMigrationService } from './StorageMigrationService';

const DOMAIN = 0xFF00;
const TAG = 'ListenBook_Widget';

/** 卡片名,与 form_config.json 里 forms[].name 严格一致 */
export const WIDGET_PLAYER = 'PlayerCard';

/** 单张图片大小上限：鸿蒙卡片 formImages 通道单图限制 ~2MB（再大会被框架拒绝） */
const MAX_IMG_BYTES = 1.5 * 1024 * 1024;
/** 卡片只展示 2x2 封面，预先缩图可避免原图解码后占用过大的共享内存。 */
const WIDGET_COVER_SIZE = 384;
const WIDGET_COVER_QUALITY = 88;
const WIDGET_COVER_CACHE_VERSION = 'v3';

interface BuildBindingResult {
  binding: formBindingData.FormBindingData;
  imgFile: fileIo.File | null;
}

/** 初次添加卡片时使用的空态数据；带封面的更新由 buildPlayerBinding 构造。 */
export class PlayerFormData {
  wearableLayout: boolean = PlatformCompat.wearable;
  hasBook: boolean = false;
  bookId: string = '';
  bookTitle: string = '没有正在播放的书';
  author: string = '';
  cover: string = '';
  imgName: string = '';
  chapterTitle: string = '点击挑一本';
  isPlaying: boolean = false;
  formImages: Record<string, number> = {};

  constructor(snap?: WidgetPlayerSnapshot) {
    if (snap === undefined) return;
    this.hasBook = snap.bookId.length > 0;
    this.bookId = snap.bookId;
    this.bookTitle = snap.bookTitle || '没有正在播放的书';
    this.author = snap.author;
    this.cover = snap.cover;
    this.chapterTitle = snap.chapterTitle || '点击挑一本';
    this.isPlaying = snap.isPlaying;
  }
}

/**
 * 鸿蒙官方推荐的卡片图片传递方式：
 *   1) 网络图直接传 https URL（最稳，无需 FD）
 *   2) 本地图通过 formImages 传 FD，卡片侧用 memory://<key> 加载
 *   3) imgName 每次更新必须变（否则卡片 ImageCache 不会刷新，闪一下又是旧图）
 *
 * 我们的策略：
 *   - 始终先把网络封面下到沙箱，主路径用 file FD（memory://），更稳定
 *   - 同时把 https URL 也回填一份做兜底（网络可达且体积合规时卡片能直接用）
 *   - 失败时卡片自动回退到默认占位
 */
export class WidgetUpdater {
  /** 阅读卡片复用现有缩图缓存和本地占位图，不改变听书卡片状态。 */
  static async resolveFormCover(context: common.Context, bookId: string, cover: string,
    title: string, author: string, allowNetwork: boolean): Promise<string | null> {
    WidgetUpdater.setContext(context);
    const resolved = await LocalBookCoverService.resolve(context, bookId, cover, title, author);
    if (resolved.startsWith('/') || resolved.startsWith('file://')) return resolved.replace(/^file:\/\//, '');
    if (resolved.startsWith('http')) return WidgetUpdater.downloadCover(resolved, allowNetwork);
    return null;
  }

  static async updateBookPresentation(book: Book): Promise<void> {
    const snapshot = await PreferenceService.getWidgetPlayerSnapshot();
    if (!snapshot || snapshot.bookId !== book.id) return;
    snapshot.bookTitle = book.title;
    snapshot.author = book.author;
    snapshot.cover = book.cover;
    snapshot.updatedAt = Date.now();
    await PreferenceService.setWidgetPlayerSnapshot(snapshot);
    await WidgetUpdater.pushSnapshotToCards();
  }
  /** 主进程的 Context,用于沙箱写入封面缓存 */
  private static appContext: common.Context | null = null;
  /**
   * 更新序号：播放状态回调可能并发触发，较早开始的异步下载/写图不能覆盖较新的快照。
   * 只让最后一次更新进入持久化和推送阶段，避免卡片偶尔回跳到旧状态。
   */
  private static updateGeneration: number = 0;
  /** url -> 沙箱文件路径 */
  private static coverPathCache: Map<string, string> = new Map();
  private static coverDownloads: Map<string, Promise<string | null>> = new Map();
  /** 每张卡片最后一次成功推送的可见状态，新登记的 formId 不会被全局去重误伤。 */
  private static pushedCardStateByForm: Map<string, WidgetPlayerSnapshot> = new Map();
  /** 已成功经 FD 推送的封面，区分文字快照已到达但封面仍在下载的状态。 */
  private static pushedCoverByForm: Map<string, string> = new Map();
  private static coverMigrationPromise: Promise<void> | null = null;

  static setContext(ctx: common.Context): void {
    WidgetUpdater.appContext = ctx;
    if (WidgetUpdater.coverMigrationPromise === null) {
      WidgetUpdater.coverMigrationPromise = StorageMigrationService.migrateFilesWithPrefix(
        ctx.filesDir, ctx.cacheDir, 'widget_cover_');
    }
  }

  /**
   * 把网络封面下到沙箱，返回 { localPath, sizeBytes }；失败返回 null。
   * - 已下载过：直接复用
   * - 失败：返回 null（外层用 https URL 兜底）
   */
  private static async downloadCover(url: string, allowNetwork: boolean = true): Promise<string | null> {
    if (!allowNetwork) return WidgetUpdater.loadCover(url, false);
    const pending = WidgetUpdater.coverDownloads.get(url);
    if (pending) return pending;
    const download = WidgetUpdater.loadCover(url, true);
    WidgetUpdater.coverDownloads.set(url, download);
    try {
      return await download;
    } finally {
      WidgetUpdater.coverDownloads.delete(url);
    }
  }

  private static async loadCover(url: string, allowNetwork: boolean): Promise<string | null> {
    if (url.startsWith('file://') || url.startsWith('/data/')) {
      const path = url.replace(/^file:\/\//, '');
      try { return (await fileIo.stat(path)).size <= MAX_IMG_BYTES ? path : null; } catch (_error) { return null; }
    }
    if (!url || !url.startsWith('http')) return null;
    const cached = WidgetUpdater.coverPathCache.get(url);
    if (cached) {
      try {
        const stat = await fileIo.stat(cached);
        if (stat.size > 0) return cached;
      } catch (_e) {}
      WidgetUpdater.coverPathCache.delete(url);
    }
    if (!WidgetUpdater.appContext) return null;
    if (WidgetUpdater.coverMigrationPromise) await WidgetUpdater.coverMigrationPromise;
    try {
      const cacheDir = WidgetUpdater.appContext.cacheDir;
      const fileName = `widget_cover_${WidgetUpdater.hash(url)}_${WIDGET_COVER_CACHE_VERSION}.jpg`;
      const filePath = `${cacheDir}/${fileName}`;
      try {
        const stat = await fileIo.stat(filePath);
        if (stat.size > 0) {
          WidgetUpdater.coverPathCache.set(url, filePath);
          return filePath;
        }
      } catch (_e) { /* not exist, continue */ }
      const legacyPath = `${WidgetUpdater.appContext.filesDir}/${fileName}`;
      if (await StorageMigrationService.migrateFile(legacyPath, filePath)) {
        try {
          const stat = await fileIo.stat(filePath);
          if (stat.size > 0) {
            WidgetUpdater.coverPathCache.set(url, filePath);
            return filePath;
          }
        } catch (_e) {}
      }
      try {
        const legacyStat = await fileIo.stat(legacyPath);
        if (legacyStat.size > 0) return legacyPath;
      } catch (_e) {}

      // FormExtensionAbility 生命周期很短，只允许复用已落盘封面。
      if (!allowNetwork) return null;

      const httpClient = http.createHttp();
      try {
        const resp = await httpClient.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 8000,
          readTimeout: 8000,
        });
        if (resp.responseCode === 200 && resp.result) {
          const buf = resp.result as ArrayBuffer;
          const widgetCover = await WidgetUpdater.createWidgetCover(buf);
          if (widgetCover.byteLength > MAX_IMG_BYTES) {
            hilog.warn(DOMAIN, TAG, 'cover too big (%{public}d bytes), drop FD path: %{public}s',
              widgetCover.byteLength, url);
            return null;
          }
          const f = await fileIo.open(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
          await fileIo.write(f.fd, widgetCover);
          await fileIo.close(f);
          WidgetUpdater.coverPathCache.set(url, filePath);
          hilog.info(DOMAIN, TAG, 'widget cover cached source=%{public}d bytes output=%{public}d bytes',
            buf.byteLength, widgetCover.byteLength);
          return filePath;
        }
        hilog.warn(DOMAIN, TAG, 'download cover bad status %{public}d for %{public}s',
          resp.responseCode, url);
      } finally {
        httpClient.destroy();
      }
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'download cover failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
    return null;
  }

  /** 把大尺寸原图转成卡片专用 JPEG，控制解码内存和跨进程传输体积。 */
  private static async createWidgetCover(buf: ArrayBuffer): Promise<ArrayBuffer> {
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      source = image.createImageSource(buf);
      const info = await source.getImageInfo();
      const scale = Math.min(1, WIDGET_COVER_SIZE / Math.max(info.size.width, info.size.height));
      const decodingOptions: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        }
      };
      pixelMap = await source.createPixelMap(decodingOptions);
      packer = image.createImagePacker();
      const packingOptions: image.PackingOption = {
        format: 'image/jpeg',
        quality: WIDGET_COVER_QUALITY
      };
      return await packer.packToData(pixelMap, packingOptions);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'resize widget cover failed, use original: %{public}s',
        e?.message ?? JSON.stringify(err));
      return buf;
    } finally {
      if (packer) {
        try { await packer.release(); } catch (_e) {}
      }
      if (pixelMap) {
        try { pixelMap.release(); } catch (_e) {}
      }
      if (source) {
        try { source.release(); } catch (_e) {}
      }
    }
  }

  private static hash(s: string): string {
    let h = 0;
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) - h + s.charCodeAt(i)) | 0;
    }
    return Math.abs(h).toString(16);
  }

  /**
   * 给 formProvider 准备一份 binding（鸿蒙官方推荐结构）：
   *   平铺字段 + imgName + formImages 全部塞在同一个对象里（不要再包一层 data 字符串）
   *   卡片侧用 Image('memory://' + this.imgName) 加载
   *   imgName 每次更新都变,否则卡片 ImageCache 不会刷新
   *
   * 返回 { binding, imgFile }，调用方在 updateForm 完成后必须 close imgFile 释放 fd
   */
  private static async buildPlayerBinding(snap: WidgetPlayerSnapshot, allowNetwork: boolean = true)
    : Promise<BuildBindingResult> {
    const cover = WidgetUpdater.appContext ? await LocalBookCoverService.resolve(WidgetUpdater.appContext,
      snap.bookId, snap.cover, snap.bookTitle, snap.author) : snap.cover;
    const data: Record<string, Object> = {
      'wearableLayout': PlatformCompat.wearable,
      'hasBook': snap.bookId.length > 0,
      'bookId': snap.bookId,
      'bookTitle': snap.bookTitle || '没有正在播放的书',
      'author': snap.author,
      'cover': cover,
      'imgName': '',
      'chapterTitle': snap.chapterTitle || '点击挑一本',
      'isPlaying': snap.isPlaying
    };
    let imgFile: fileIo.File | null = null;
    let imgName = '';
    if (cover && (cover.startsWith('http') || cover.startsWith('/') || cover.startsWith('file://'))) {
      try {
        let localPath: string | null = null;
        if (cover.startsWith('http')) {
          localPath = await WidgetUpdater.downloadCover(cover, allowNetwork);
        } else if (cover.startsWith('file://')) {
          localPath = cover.substring('file://'.length);
        } else if (cover.startsWith('/')) {
          localPath = cover;
        }
        if (localPath) {
          imgFile = await fileIo.open(localPath, fileIo.OpenMode.READ_ONLY);
          imgName = `cover_${WidgetUpdater.hash(snap.bookId)}_${snap.updatedAt}`;
          data['imgName'] = imgName;
          const formImages: Record<string, number> = {};
          formImages[imgName] = imgFile.fd;
          data['formImages'] = formImages;
          const stat = await fileIo.stat(localPath);
          hilog.info(DOMAIN, TAG, 'cover binding ready key=%{public}s bytes=%{public}d fd=%{public}d',
            imgName, stat.size, imgFile.fd);
        } else if (cover.length > 0) {
          hilog.warn(DOMAIN, TAG, 'cover binding fallback to url, network=%{public}s',
            allowNetwork ? 'true' : 'false');
        }
      } catch (err) {
        const e = err as Error;
        hilog.warn(DOMAIN, TAG, 'open cover fd failed: %{public}s',
          e?.message ?? JSON.stringify(err));
      }
    }
    return { binding: formBindingData.createFormBindingData(data), imgFile };
  }

  private static closeFd(f: fileIo.File | null): void {
    if (!f) return;
    try { fileIo.closeSync(f); } catch (_e) { /* ignore */ }
  }

  private static isLatest(generation: number): boolean {
    return generation === WidgetUpdater.updateGeneration;
  }

  /** 重新打开 preferences，读取 FormExtensionAbility 刚写入的 formId。 */
  private static async refreshPreferenceCache(): Promise<void> {
    if (!WidgetUpdater.appContext) return;
    try {
      await PreferenceService.invalidateCache(WidgetUpdater.appContext);
      await PreferenceService.init(WidgetUpdater.appContext);
    } catch (err) {
      const e = err as Error;
      hilog.warn(DOMAIN, TAG, 'refresh preferences failed: %{public}s',
        e?.message ?? JSON.stringify(err));
    }
  }

  /** 卡片当前不展示播放进度，比较可见字段即可，避免每个 tick 都重建图片绑定。 */
  private static sameCardState(a: WidgetPlayerSnapshot, b: WidgetPlayerSnapshot): boolean {
    return a.bookId === b.bookId
      && a.bookTitle === b.bookTitle
      && a.author === b.author
      && a.cover === b.cover
      && a.chapterId === b.chapterId
      && a.chapterTitle === b.chapterTitle
      && a.playbackKind === b.playbackKind
      && a.isPlaying === b.isPlaying;
  }

  /** 把当前 PlayerState 写入快照,并广播给所有听书卡片 */
  static async updatePlayerCard(state: PlayerState | null, force: boolean = false): Promise<void> {
    if (PlatformCompat.wearable || PlaybackCoordinator.speechActive) return;
    const existing = await PreferenceService.getWidgetPlayerSnapshot();
    // 朗读停止后，旧有声书的暂停/释放回调不能抢回桌面卡片。
    if (PlaybackCoordinator.speechActive) return;
    if (existing?.playbackKind === 'tts' && !state?.isPlaying && !state?.isLoading) return;
    await WidgetUpdater.updateSnapshot(WidgetUpdater.buildSnapshot(state), force);
  }

  static async updateSpeechCard(book: Book, state: TextToSpeechState): Promise<void> {
    if (PlatformCompat.wearable || !PlaybackCoordinator.speechActive) return;
    const chapter = book.chapters[state.chapterIndex];
    const snap: WidgetPlayerSnapshot = {
      playbackKind: 'tts', charOffset: state.charOffset,
      bookId: book.id, bookTitle: book.title, author: book.author, cover: book.cover,
      chapterId: chapter?.id ?? '', chapterTitle: chapter?.title ?? '',
      progressMs: 0, durationMs: 0, isPlaying: state.playing && !state.loading, updatedAt: Date.now()
    };
    await WidgetUpdater.updateSnapshot(snap);
  }

  private static async updateSnapshot(snap: WidgetPlayerSnapshot, force: boolean = false): Promise<void> {
    const generation = ++WidgetUpdater.updateGeneration;
    const existing = await PreferenceService.getWidgetPlayerSnapshot();
    if (!WidgetUpdater.isLatest(generation)) return;
    if (force || !existing || !WidgetUpdater.sameCardState(snap, existing) || snap.charOffset !== existing.charOffset) {
      await PreferenceService.setWidgetPlayerSnapshot(snap);
    }
    if (!WidgetUpdater.isLatest(generation)) return;
    // form-id 列表由 FormExtensionAbility 进程写入，主进程必须刷新 preferences 缓存。
    await WidgetUpdater.refreshPreferenceCache();
    const ids = await PreferenceService.getWidgetFormIds(WIDGET_PLAYER);
    hilog.info(DOMAIN, TAG, 'update card generation=%{public}d forms=%{public}d playing=%{public}s',
      generation, ids.length, snap.isPlaying ? 'true' : 'false');
    if (ids.length === 0) return;
    if (!WidgetUpdater.isLatest(generation)) return;
    const pendingIds: string[] = ids.filter((id: string) => {
      const pushed = WidgetUpdater.pushedCardStateByForm.get(id);
      return force || !pushed || !WidgetUpdater.sameCardState(snap, pushed) ||
        (snap.cover.startsWith('http') && WidgetUpdater.coverPathCache.has(snap.cover) &&
          WidgetUpdater.pushedCoverByForm.get(id) !== snap.cover);
    });
    if (pendingIds.length === 0) {
      // 相同状态的后续同步也会推进代次，接手尚未完成的封面下载。
      if (snap.cover.startsWith('http') && !WidgetUpdater.coverPathCache.has(snap.cover)) {
        WidgetUpdater.refreshCardCover(snap, ids, generation).catch((): void => {});
      }
      return;
    }
    // 文本和播放状态先推送，只读本地封面缓存，不能被网络封面阻塞。
    const built = await WidgetUpdater.buildPlayerBinding(snap, false);
    try {
      for (const id of pendingIds) {
        if (!WidgetUpdater.isLatest(generation)) break;
        try {
          await formProvider.updateForm(id, built.binding);
          WidgetUpdater.pushedCardStateByForm.set(id, snap);
          WidgetUpdater.pushedCoverByForm.set(id, built.imgFile ? snap.cover : '');
          hilog.info(DOMAIN, TAG, 'update card success id=%{public}s', id);
        } catch (err) {
          const e = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'updatePlayerCard fail id=%{public}s code=%{public}d msg=%{public}s',
            id, e.code, e.message);
          // 16500001 invalid id / 16500100 not removed / 16501001 form not exist
          // 这三种都是死 ID，从持久化里清掉，下次重新添加卡片时由 onAddForm 重新登记
          if (e.code === 16500001 || e.code === 16500100 || e.code === 16501001) {
            WidgetUpdater.pushedCardStateByForm.delete(id);
            WidgetUpdater.pushedCoverByForm.delete(id);
            await PreferenceService.removeWidgetFormId(WIDGET_PLAYER, id);
          }
        }
      }
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
    if (!built.imgFile && snap.cover.startsWith('http') && WidgetUpdater.isLatest(generation)) {
      WidgetUpdater.refreshCardCover(snap, pendingIds, generation).catch((): void => {});
    }
  }

  private static async refreshCardCover(snap: WidgetPlayerSnapshot, ids: string[],
    generation: number): Promise<void> {
    const built = await WidgetUpdater.buildPlayerBinding(snap);
    try {
      if (!built.imgFile) return;
      for (const id of ids) {
        // 下载期间切书或暂停后，不得回写旧的书名、封面和播放状态。
        if (!WidgetUpdater.isLatest(generation)) return;
        try {
          await formProvider.updateForm(id, built.binding);
          WidgetUpdater.pushedCoverByForm.set(id, snap.cover);
        } catch (_error) {
          hilog.warn(DOMAIN, TAG, 'refresh card cover failed id=%{public}s', id);
        }
      }
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  /** 单卡片推送(onAddForm/onUpdateForm 用),内部走 fd 通道并自动关闭 fd */
  static async pushPlayerSnapshotToForm(formId: string, snap: WidgetPlayerSnapshot,
    allowNetwork: boolean = true): Promise<void> {
    const built = await WidgetUpdater.buildPlayerBinding(snap, allowNetwork);
    try {
      await formProvider.updateForm(formId, built.binding);
      WidgetUpdater.pushedCardStateByForm.set(formId, snap);
      hilog.info(DOMAIN, TAG, 'single card push success id=%{public}s', formId);
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  /** 没有快照时,从 lastPlayed + cachedBooks 拼一份兜底快照(冷启动卡片首次添加用)。
   *  注意:这里 isPlaying 必须保持 false —— 兜底是给"主进程从未推过快照"的场景用的,
   *  此时主进程那边肯定不在播。
   *  ★ 不再写回 preferences:FormExt 与主进程的 preferences 缓存不互通,
   *  如果 FormExt 因缓存陈旧错读出 null 走到这里,写回会用 false 覆盖
   *  主进程刚 put 的真值(磁盘也被污染),卡片就会卡在"暂停"。 */
  static async seedSnapshotFromLastPlayed(): Promise<WidgetPlayerSnapshot | null> {
    const last = await PreferenceService.getLastPlayed();
    if (!last) return null;
    const cachedJson = await PreferenceService.getCachedBooks();
    const importedJson = await PreferenceService.getImportedBooks();
    let book: Book | undefined;
    try {
      const cached = JSON.parse(cachedJson) as Book[];
      const imported = JSON.parse(importedJson) as Book[];
      book = imported.find((b) => b.id === last.bookId) ?? cached.find((b) => b.id === last.bookId);
    } catch (_e) { /* ignore */ }
    if (!book) return null;
    const snap: WidgetPlayerSnapshot = {
      bookId: book.id,
      bookTitle: book.title,
      author: book.author,
      cover: book.cover,
      chapterId: last.chapterId,
      chapterTitle: last.chapterTitle ?? '',
      progressMs: last.progressMs,
      durationMs: last.durationMs ?? 0,
      isPlaying: false,
      updatedAt: Date.now(),
    };
    return snap;
  }

  /** EntryAbility 启动时调:把兜底快照写回 preferences 给桌面卡片使用。
   *  和 seedSnapshotFromLastPlayed 分开,确保只有主进程会写盘。 */
  static async seedAndPersistFromLastPlayed(): Promise<WidgetPlayerSnapshot | null> {
    const existing = await PreferenceService.getWidgetPlayerSnapshot();
    if (existing?.playbackKind === 'tts') {
      if (PlaybackCoordinator.speechActive) return existing;
      existing.isPlaying = false;
      existing.updatedAt = Date.now();
      await PreferenceService.setWidgetPlayerSnapshot(existing);
      return existing;
    }
    const snap = await WidgetUpdater.seedSnapshotFromLastPlayed();
    if (snap) {
      await PreferenceService.setWidgetPlayerSnapshot(snap);
    }
    return snap;
  }

  /** 把当前 preference 里的快照推送到所有听书卡片(seed 后调用) */
  static async pushSnapshotToCards(): Promise<void> {
    const generation = WidgetUpdater.updateGeneration;
    await WidgetUpdater.refreshPreferenceCache();
    const ids = await PreferenceService.getWidgetFormIds(WIDGET_PLAYER);
    if (ids.length === 0) return;
    const snap = await PreferenceService.getWidgetPlayerSnapshot();
    if (!snap) return;
    if (!WidgetUpdater.isLatest(generation)) return;
    const built = await WidgetUpdater.buildPlayerBinding(snap);
    try {
      for (const id of ids) {
        if (!WidgetUpdater.isLatest(generation)) break;
        try {
          await formProvider.updateForm(id, built.binding);
          WidgetUpdater.pushedCardStateByForm.set(id, snap);
        } catch (err) {
          const e = err as BusinessError;
          hilog.warn(DOMAIN, TAG, 'pushSnapshotToCards fail id=%{public}s code=%{public}d',
            id, e.code);
          if (e.code === 16500001 || e.code === 16500100 || e.code === 16501001) {
            WidgetUpdater.pushedCardStateByForm.delete(id);
            await PreferenceService.removeWidgetFormId(WIDGET_PLAYER, id);
          }
        }
      }
    } finally {
      WidgetUpdater.closeFd(built.imgFile);
    }
  }

  /**
   * 乐观更新卡片播放/暂停状态:卡片按钮点击瞬间立即调,不等 AVPlayer 真正 play/pause。
   * 卡片按钮原本要走完整往返(卡片→IPC→主进程→AVPlayer 异步→stateChange 回调→
   * syncPlaybackState→updatePlayerCard→卡片)图标才翻,体感"慢一拍"。
   * 这里只翻转快照里的 isPlaying 字段并立即推送,真实状态稍后由 syncPlaybackState 兜底校正
   * (即使 AVPlayer 实际失败,下一次 stateChange 也会把卡片纠回正确状态)。
   */
  static async optimisticSetPlaying(isPlaying: boolean): Promise<void> {
    if (!WidgetUpdater.appContext) return;

    try {
      const generation = ++WidgetUpdater.updateGeneration;
      await WidgetUpdater.refreshPreferenceCache();
      const snap = await PreferenceService.getWidgetPlayerSnapshot();
      if (!snap || snap.bookId.length === 0 || snap.isPlaying === isPlaying) {
        return;
      }

      snap.isPlaying = isPlaying;
      snap.updatedAt = Date.now();
      if (!WidgetUpdater.isLatest(generation)) return;
      await PreferenceService.setWidgetPlayerSnapshot(snap);

      await WidgetUpdater.refreshPreferenceCache();
      const ids = await PreferenceService.getWidgetFormIds(WIDGET_PLAYER);
      if (ids.length === 0) return;

      // 乐观更新也必须走完整绑定，否则会把已有 imgName/formImages 覆盖掉，
      // 播放按钮点击后封面和背景就会短暂消失。
      const built = await WidgetUpdater.buildPlayerBinding(snap);
      try {
        for (const id of ids) {
          if (!WidgetUpdater.isLatest(generation)) break;
          try {
            await formProvider.updateForm(id, built.binding);
            WidgetUpdater.pushedCardStateByForm.set(id, snap);
          } catch (err) {
            const e = err as BusinessError;
            if (e.code === 16500001 || e.code === 16500100 || e.code === 16501001) {
              WidgetUpdater.pushedCardStateByForm.delete(id);
              await PreferenceService.removeWidgetFormId(WIDGET_PLAYER, id);
            }
          }
        }
      } finally {
        WidgetUpdater.closeFd(built.imgFile);
      }

      setTimeout(() => {
        WidgetUpdater.pushSnapshotToCards().catch(() => {});
      }, 600);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'optimisticSetPlaying failed: %{public}s',
        (err as Error)?.message ?? '');
    }
  }

  static buildSnapshot(state: PlayerState | null): WidgetPlayerSnapshot {
    const book: Book | null = state ? state.currentBook : null;
    const chapter: Chapter | null = state ? state.currentChapter : null;
    return {
      playbackKind: 'audio',
      bookId: book ? book.id : '',
      bookTitle: book ? book.title : '',
      author: book ? book.author : '',
      cover: book ? book.cover : '',
      chapterId: chapter ? chapter.id : '',
      chapterTitle: chapter ? chapter.title : '',
      progressMs: state ? state.progressMs : 0,
      durationMs: state ? state.durationMs : 0,
      isPlaying: state ? state.isPlaying : false,
      updatedAt: Date.now()
    };
  }
}
