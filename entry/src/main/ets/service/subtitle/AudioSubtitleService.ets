import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { worker, MessageEvents, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Book, Chapter } from '../../model/Book';
import { AudioSubtitleState, SubtitleChunk, SubtitleCue, SubtitleUnit, SubtitleSegmenter, SubtitleWorkerRequest, SubtitleWorkerResponse,
  SUBTITLE_CHUNK_MS, SUBTITLE_MODEL_VERSION } from '../../model/AudioSubtitle';
import { AudioService } from '../AudioService';
import { ChapterCacheService } from '../ChapterCacheService';
import { DownloadService } from '../DownloadService';
import { DownloadPolicy } from '../DownloadPolicy';
import { SubtitleFiles } from './SubtitleFiles';
import { PlayerState } from '../../model/PlayerState';
import { DesktopLyricText } from '../../model/DesktopLyric';
import { AVSessionService } from '../AVSessionService';
import { PlaybackCoordinator } from '../PlaybackCoordinator';
import { SubtitleModelService } from './SubtitleModelService';

class SubtitleCache {
  version: string = SUBTITLE_MODEL_VERSION;
  chunks: SubtitleChunk[] = [];
}

class SubtitlePreload {
  audioPath: string = '';
  cachePath: string = '';
  durationMs: number = 0;
  firstChunk: number = 0;
  chunks: Map<number, SubtitleChunk> = new Map();
}

/** Foreground subtitle work is independent of playback, and owns only its temporary audio. */
export class AudioSubtitleService {
  static readonly instance: AudioSubtitleService = new AudioSubtitleService();
  readonly state: AudioSubtitleState = new AudioSubtitleState();
  private generation: number = 0;
  private sequence: number = 0;
  private setup: Promise<void> = Promise.resolve();
  private host: worker.ThreadWorker | null = null;
  private watchdog: number = -1;
  private pending: number = -1;
  private positionMs: number = 0;
  private durationMs: number = 0;
  private audioPath: string = '';
  private modelDir: string = '';
  private cachePath: string = '';
  private chunks: Map<number, SubtitleChunk> = new Map();
  private preview: SubtitleChunk | null = null;
  private previewedChunk: number = -1;
  private next: SubtitlePreload | null = null;
  private pendingNext: boolean = false;
  private preparingNext: boolean = false;
  private nextFailed: boolean = false;
  private nextCheckAt: number = 0;
  private context: common.Context | null = null;
  private book: Book | null = null;
  private chapterId: string = '';
  private lexiconReady: boolean = false;
  private panelActive: boolean = false;
  private desktopActive: boolean = false;
  private desktopKey: string = '';
  private activeKey: string = '';

  showPanel(context: common.Context, book: Book, chapter: Chapter, durationMs: number,
    positionMs: number, downloadModel: boolean = false): void {
    this.panelActive = true;
    this.ensure(context, book, chapter, durationMs, positionMs, downloadModel);
  }

  /** 桌面歌词与页面共用同一个识别任务；页面卸载只释放自己的使用权。 */
  syncDesktop(context: common.Context, state: PlayerState): void {
    const session = AVSessionService.getInstance();
    const wanted = session.desktopLyric.visible && !PlaybackCoordinator.speechActive && !state.isLive;
    if (!wanted || !state.currentBook || !state.currentChapter) {
      if (!this.desktopActive) return;
      this.desktopActive = false;
      this.desktopKey = '';
      if (!this.panelActive) this.release();
      return;
    }
    this.desktopActive = true;
    const book = state.currentBook;
    const chapter = state.currentChapter;
    if (state.isLoading || state.durationMs <= 0) {
      this.desktopKey = '';
      session.updateDesktopLyric(book.id, chapter.id,
        '[00:00.00]' + context.resourceManager.getStringSync($r('app.string.subtitle_wait_audio').id));
      return;
    }
    const key = `${book.id}:${chapter.id}:${chapter.source.value}:${state.durationMs}`;
    if (key !== this.desktopKey) {
      this.desktopKey = key;
      this.ensure(context, book, chapter, state.durationMs, state.progressMs);
    }
    this.tick(state.progressMs);
    this.publishDesktop();
  }

  private publishDesktop(): void {
    if (!this.desktopActive || !this.context || !this.book || PlaybackCoordinator.speechActive) return;
    let lyric = DesktopLyricText.audio(this.state.cues, this.positionMs);
    if (!lyric) {
      let message = $r('app.string.subtitle_recognizing');
      if (this.state.phase === 'needsModel') message = $r('app.string.desktop_lyric_needs_model');
      else if (this.state.phase === 'error') message = $r('app.string.subtitle_failed');
      lyric = '[00:00.00]' + this.context.resourceManager.getStringSync(message.id);
    }
    AVSessionService.getInstance().updateDesktopLyric(this.book.id, this.chapterId, lyric);
  }

  stop(): void {
    this.generation++;
    if (this.watchdog !== -1) clearTimeout(this.watchdog);
    this.watchdog = -1;
    this.pending = -1;
    this.preview = null; this.previewedChunk = -1;
    this.next = null; this.pendingNext = false; this.preparingNext = false;
    this.nextFailed = false; this.nextCheckAt = 0;
    this.context = null; this.book = null;
    try { this.host?.terminate(); } catch (_error) {}
    this.host = null;
    this.audioPath = '';
    if (this.ownedTemporary) SubtitleFiles.remove(this.ownedTemporary);
    this.ownedTemporary = '';
  }

  private ensure(context: common.Context, book: Book, chapter: Chapter, durationMs: number,
    positionMs: number, downloadModel: boolean = false): void {
    const key = `${book.id}:${chapter.id}:${chapter.source.value}:${durationMs}`;
    if (key === this.activeKey && !downloadModel && this.state.phase !== 'idle' && this.state.phase !== 'error') {
      this.tick(positionMs);
      return;
    }
    this.begin(context, book, chapter, durationMs, positionMs, downloadModel);
  }

  begin(context: common.Context, book: Book, chapter: Chapter, durationMs: number,
    positionMs: number, downloadModel: boolean = false): void {
    this.stop();
    this.activeKey = `${book.id}:${chapter.id}:${chapter.source.value}:${durationMs}`;
    const generation = this.generation;
    this.context = context; this.book = book; this.chapterId = chapter.id;
    this.state.phase = 'preparing'; this.state.percent = 0; this.state.error = '';
    this.state.cues = []; this.chunks.clear(); this.cachePath = '';
    this.durationMs = Math.min(86400000, Math.max(0, durationMs));
    this.positionMs = positionMs;
    // Serialize setup/cleanup so rapid toggles cannot write/remove the same model .part file concurrently.
    this.setup = this.setup.catch((): void => {}).then(async (): Promise<void> => {
      const active = (): boolean => generation === this.generation;
      if (!active()) return;
      let temporary = '';
      try {
        if (this.durationMs <= 0 || DownloadPolicy.isHls(chapter.source.value, '')) throw new Error('subtitle_unsupported');
        if (!await SubtitleModelService.ready(context, active)) {
          if (!active()) return;
          if (!downloadModel) { this.state.phase = 'needsModel'; this.publishDesktop(); return; }
          this.state.phase = 'model';
          await SubtitleModelService.ensure(context, active, (percent: number): void => {
            if (active()) this.state.percent = percent;
          });
        }
        if (!active()) return;
        this.modelDir = SubtitleModelService.directory(context);
        await SubtitleModelService.preparePunctuation(context, active);
        if (!this.lexiconReady) {
          const bytes = await context.resourceManager.getRawFileContent('audio_subtitles/idioms.txt');
          SubtitleSegmenter.setProtectedWords(util.TextDecoder.create('utf-8').decodeToString(bytes).split('\n'));
          this.lexiconReady = true;
        }
        if (!active()) return;
        const origin = chapter.originSourceValue || chapter.source.value;
        let path = DownloadService.getInstance().getDownloadedFilePath(book.id, chapter) ??
          ChapterCacheService.getInstance().getAudioFilePath(book.id, chapter.id, origin) ?? '';
        if (!path && chapter.source.type === 'file') path = chapter.source.value;
        if (!path) {
          const url = chapter.source.value;
          if (chapter.source.type !== 'url' || !/^https?:\/\//.test(url) || DownloadPolicy.isHls(url, '')) {
            throw new Error('subtitle_unsupported');
          }
          this.state.phase = 'audio'; this.state.percent = 0;
          temporary = `${context.cacheDir}/subtitle_audio_${generation}.tmp`;
          const headers = AudioService.getInstance().subtitleHeaders(book.id, chapter.id);
          await SubtitleFiles.download(url, headers, temporary, 256 * 1024 * 1024, active,
            (_bytes: number): void => {});
          path = temporary;
        }
        if (!active()) return;
        this.state.phase = 'preparing';
        const fingerprint = await SubtitleFiles.digest(path, active);
        const key = await SubtitleFiles.key(`${SUBTITLE_MODEL_VERSION}\n${book.sourceUrl}\n${book.id}\n${chapter.id}\n${origin}\n${fingerprint}`);
        if (!active()) return;
        const directory = `${context.cacheDir}/audio_subtitles`;
        if (!fileIo.accessSync(directory)) fileIo.mkdirSync(directory, true);
        this.prune(directory, `${key}.json`);
        this.cachePath = `${directory}/${key}.json`;
        this.restore();
        this.audioPath = path;
        this.state.phase = 'ready';
        this.host = new worker.ThreadWorker('entry/ets/workers/AudioSubtitleWorker.ets', { name: 'AudioSubtitle' });
        this.host.onmessage = (event: MessageEvents): void => {
          if (!active()) return;
          const response: SubtitleWorkerResponse = event.data;
          if (response.requestId !== this.pending) return;
          if (this.watchdog !== -1) clearTimeout(this.watchdog);
          this.watchdog = -1; this.pending = -1;
          const background = this.pendingNext;
          this.pendingNext = false;
          if (response.preview) {
            if (!response.error) { this.preview = response.chunk; this.publish(); }
            this.state.phase = 'ready'; this.pump(); return;
          }
          if (response.error && !background) { this.fail(response.error); return; }
          if (background) {
            if (response.error) { this.nextFailed = true; this.next = null; }
            else if (this.next) {
              if (response.previous) this.next.chunks.set(response.previous.index, response.previous);
              this.next.chunks.set(response.chunk.index, response.chunk);
              this.save(this.next.cachePath, this.next.chunks);
            }
          } else {
            if (response.previous) this.chunks.set(response.previous.index, response.previous);
            this.chunks.set(response.chunk.index, response.chunk);
            if (this.preview?.index === response.chunk.index) this.preview = null;
            this.publish(); this.save();
          }
          this.state.phase = 'ready';
          this.pump();
        };
        this.host.onerror = (): void => {
          if (!active()) return;
          if (this.pendingNext) this.resetBackgroundWorker();
          else this.fail('subtitle_recognition_failed');
        };
        // Keep the temporary file until the owning generation is cancelled, without occupying the setup chain.
        if (temporary) {
          const owned = temporary;
          temporary = '';
          this.ownedTemporary = owned;
        }
        this.pump();
      } catch (error) {
        if (active()) this.fail(error instanceof Error ? error.message : 'subtitle_recognition_failed');
      } finally { if (temporary) SubtitleFiles.remove(temporary); }
    });
  }

  private ownedTemporary: string = '';

  release(): void {
    this.panelActive = false;
    if (this.desktopActive) return;
    this.stop();
    this.activeKey = '';
    this.state.phase = 'idle';
    this.state.cues = [];
    this.state.revision++;
  }

  tick(positionMs: number): void {
    this.positionMs = Math.max(0, positionMs);
    if (this.state.phase === 'ready' || this.state.phase === 'recognizing') {
      const current = Math.floor(this.positionMs / SUBTITLE_CHUNK_MS);
      this.state.phase = this.chunks.has(current) || this.preview?.index === current ? 'ready' : 'recognizing';
    }
    this.pump();
  }

  private pump(): void {
    if (!this.host || this.pending !== -1 || !this.audioPath || this.state.phase === 'error') return;
    const current = Math.floor(this.positionMs / SUBTITLE_CHUNK_MS);
    const total = Math.ceil(this.durationMs / SUBTITLE_CHUNK_MS);
    const preload = ChapterCacheService.getInstance().isPreloadEnabled();
    // Prepare the cache key while current audio is being recognized, not after two minutes of work.
    if (preload && !this.next && !this.preparingNext && !this.nextFailed && Date.now() >= this.nextCheckAt) {
      this.nextCheckAt = Date.now() + 3000;
      this.prepareNext();
    }
    let urgentReady = true;
    for (let index = current; index < Math.min(total, current + 2); index++) {
      if (!this.chunks.has(index)) urgentReady = false;
    }
    // Protect the current 24 seconds, then give the next chapter an early opening buffer.
    if (preload && urgentReady && this.pumpNext(2)) return;
    for (let index = current; index < Math.min(total, current + 10); index++) {
      if (this.chunks.has(index)) continue;
      const request = new SubtitleWorkerRequest();
      request.requestId = ++this.sequence; request.chunk = index;
      request.modelDir = this.modelDir; request.audioPath = this.audioPath;
      request.previous = this.chunks.get(index - 1) ?? null;
      request.prefix = this.chunks.get(index - 2)?.units ?? [];
      request.finalChunk = index === total - 1;
      // First show a short provisional span, then replace it with full-context recognition.
      // Provisional units never enter persistent cache or next-chapter pre-recognition.
      request.preview = index === current && this.state.cues.length === 0 && this.previewedChunk !== current;
      request.positionMs = this.positionMs;
      if (request.preview) this.previewedChunk = current;
      this.pending = request.requestId;
      this.state.phase = this.chunks.has(current) || this.preview?.index === current ? 'ready' : 'recognizing';
      const generation = this.generation;
      this.watchdog = setTimeout((): void => {
        if (generation === this.generation) this.fail('subtitle_recognition_timeout');
      }, 90000);
      try { this.host.postMessage(request); }
      catch (_error) { this.fail('subtitle_recognition_failed'); }
      return;
    }
    this.state.phase = 'ready';
    if (preload) this.pumpNext(10);
  }

  private pumpNext(count: number): boolean {
    if (!this.next || !this.host) return false;
    const first = this.next.firstChunk;
    for (let index = first; index < Math.min(first + count, Math.ceil(this.next.durationMs / SUBTITLE_CHUNK_MS)); index++) {
      if (this.next.chunks.has(index)) continue;
      const request = new SubtitleWorkerRequest();
      request.requestId = ++this.sequence; request.chunk = index;
      request.modelDir = this.modelDir; request.audioPath = this.next.audioPath;
      request.previous = this.next.chunks.get(index - 1) ?? null;
      request.prefix = this.next.chunks.get(index - 2)?.units ?? [];
      this.pending = request.requestId; this.pendingNext = true;
      const generation = this.generation;
      this.watchdog = setTimeout((): void => {
        if (generation !== this.generation) return;
        this.resetBackgroundWorker();
      }, 90000);
      try { this.host.postMessage(request); }
      catch (_error) { this.resetBackgroundWorker(); }
      return true;
    }
    return false;
  }

  private resetBackgroundWorker(): void {
    if (this.watchdog !== -1) clearTimeout(this.watchdog);
    this.watchdog = -1; this.pending = -1; this.pendingNext = false;
    this.nextFailed = true; this.next = null;
    // A stuck native job must be terminated, but current cached subtitles remain usable.
    const messageHandler = this.host?.onmessage;
    const errorHandler = this.host?.onerror;
    try {
      this.host?.terminate();
      this.host = new worker.ThreadWorker('entry/ets/workers/AudioSubtitleWorker.ets', { name: 'AudioSubtitle' });
      if (messageHandler) this.host.onmessage = messageHandler;
      if (errorHandler) this.host.onerror = errorHandler;
      this.pump();
    } catch (_error) { this.fail('subtitle_recognition_failed'); }
  }

  private async prepareNext(): Promise<void> {
    const context = this.context;
    const book = this.book;
    if (!context || !book) return;
    const cache = ChapterCacheService.getInstance();
    const index = book.chapters.findIndex((chapter: Chapter): boolean => chapter.id === this.chapterId);
    if (index < 0 || index + 1 >= book.chapters.length) return;
    const chapter = book.chapters[index + 1];
    const origin = chapter.originSourceValue || chapter.source.value;
    const path = DownloadService.getInstance().getDownloadedFilePath(book.id, chapter) ??
      cache.getAudioFilePath(book.id, chapter.id, origin) ??
      (chapter.source.type === 'file' ? chapter.source.value : '');
    const duration = cache.getChapterDuration(chapter.id) || chapter.duration;
    if (!path) return;
    const generation = this.generation;
    const active = (): boolean => generation === this.generation;
    this.preparingNext = true;
    try {
      const fingerprint = await SubtitleFiles.digest(path, active);
      const key = await SubtitleFiles.key(`${SUBTITLE_MODEL_VERSION}\n${book.sourceUrl}\n${book.id}\n${chapter.id}\n${origin}\n${fingerprint}`);
      if (!active()) return;
      const next = new SubtitlePreload();
      next.audioPath = path;
      const skip = book.skipIntro ?? 0;
      next.firstChunk = Math.floor(Math.max(0, Number.isFinite(skip) ? skip : 0) * 1000 / SUBTITLE_CHUNK_MS);
      // Metadata extraction can lag behind file download. Decode a bounded opening without waiting for it.
      next.durationMs = Number.isFinite(duration) && duration > 0 ? Math.min(86400000, duration * 1000) :
        (next.firstChunk + 10) * SUBTITLE_CHUNK_MS;
      if (next.firstChunk * SUBTITLE_CHUNK_MS >= next.durationMs) next.firstChunk = 0;
      next.cachePath = `${context.cacheDir}/audio_subtitles/${key}.json`;
      this.prune(`${context.cacheDir}/audio_subtitles`, `${key}.json`);
      this.restore(next.cachePath, next.chunks);
      this.next = next;
    } catch (_error) {
      // Preloaded audio may be evicted. Failure must never stop current-chapter subtitles.
      if (active()) this.nextFailed = true;
    } finally {
      if (active()) { this.preparingNext = false; this.pump(); }
    }
  }

  private fail(error: string): void {
    const context = this.context;
    const book = this.book;
    this.stop();
    hilog.warn(0xFF00, 'AudioSubtitle', 'subtitle task failed: %{public}s',
      /^subtitle_[a-z_]+$/.test(error) ? error : 'subtitle_recognition_failed');
    this.state.error = error;
    this.state.phase = 'error';
    if (this.desktopActive && context && book && !PlaybackCoordinator.speechActive) {
      AVSessionService.getInstance().updateDesktopLyric(book.id, this.chapterId,
        '[00:00.00]' + context.resourceManager.getStringSync($r('app.string.subtitle_failed').id));
    }
  }

  private publish(): void {
    const chunks: SubtitleChunk[] = [];
    this.chunks.forEach((chunk: SubtitleChunk): void => { chunks.push(chunk); });
    if (this.preview && !this.chunks.has(this.preview.index)) chunks.push(this.preview);
    this.state.cues = SubtitleSegmenter.timeline(chunks);
    this.state.revision++;
    this.publishDesktop();
  }

  private restore(cachePath: string = this.cachePath, chunks: Map<number, SubtitleChunk> = this.chunks): void {
    try {
      if (fileIo.statSync(cachePath).size > 2 * 1024 * 1024) return;
      const data: SubtitleCache = JSON.parse(fileIo.readTextSync(cachePath));
      if (data.version !== SUBTITLE_MODEL_VERSION || !Array.isArray(data.chunks) || data.chunks.length > 7200) return;
      for (const saved of data.chunks) {
        if (!Number.isInteger(saved.index) || saved.index < 0 || saved.index >= 7200 ||
          !Array.isArray(saved.cues) || saved.cues.length > 128) continue;
        const chunk = new SubtitleChunk(); chunk.index = saved.index; chunk.endMs = saved.endMs;
        for (const cue of saved.cues) {
          if (typeof cue.text !== 'string' || cue.text.length > 2048 || !Number.isFinite(cue.startMs) ||
            !Number.isFinite(cue.endMs) || cue.startMs < saved.index * SUBTITLE_CHUNK_MS ||
            cue.endMs > (saved.index + 1) * SUBTITLE_CHUNK_MS || cue.endMs <= cue.startMs) continue;
          const restored = new SubtitleCue(`chunk-${saved.index}-${chunk.cues.length}`, cue.startMs, cue.endMs, cue.text);
          restored.continues = cue.continues === true;
          chunk.cues.push(restored);
        }
        if (Array.isArray(saved.units) && saved.units.length <= 2048) {
          for (const unit of saved.units) {
            if (typeof unit.text !== 'string' || unit.text.length > 8 || !Number.isFinite(unit.startMs) ||
              !Number.isFinite(unit.endMs) || unit.startMs < saved.index * SUBTITLE_CHUNK_MS ||
              unit.endMs > (saved.index + 1) * SUBTITLE_CHUNK_MS || unit.endMs <= unit.startMs) continue;
            chunk.units.push(new SubtitleUnit(unit.text, unit.startMs, unit.endMs));
          }
        }
        if (Array.isArray(saved.annotated) && saved.annotated.length <= 2048) {
          for (const unit of saved.annotated) {
            if (typeof unit.text !== 'string' || unit.text.length > 24 || !Number.isFinite(unit.startMs) ||
              !Number.isFinite(unit.endMs) || unit.startMs < saved.index * SUBTITLE_CHUNK_MS ||
              unit.endMs > (saved.index + 1) * SUBTITLE_CHUNK_MS || unit.endMs <= unit.startMs) continue;
            const restored = new SubtitleUnit(unit.text, unit.startMs, unit.endMs);
            restored.sentenceEnd = unit.sentenceEnd === true; chunk.annotated.push(restored);
          }
        }
        chunks.set(chunk.index, chunk);
      }
      if (chunks === this.chunks) this.publish();
    } catch (_error) { /* A missing/evicted cache is regenerated, never a playback failure. */ }
  }

  private save(cachePath: string = this.cachePath, chunks: Map<number, SubtitleChunk> = this.chunks): void {
    if (!cachePath) return;
    const data = new SubtitleCache();
    chunks.forEach((chunk: SubtitleChunk): void => { data.chunks.push(chunk); });
    const text = JSON.stringify(data);
    if (text.length > 1000000) return;
    const part = `${cachePath}.part`;
    try {
      const file = fileIo.openSync(part, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
      try { fileIo.writeSync(file.fd, text); } finally { fileIo.closeSync(file); }
      fileIo.renameSync(part, cachePath);
    } catch (_error) { SubtitleFiles.remove(part); }
  }

  private prune(directory: string, keep: string): void {
    try {
      const names = fileIo.listFileSync(directory).filter((name: string): boolean => /^[a-f0-9]{64}\.json$/.test(name) && name !== keep);
      names.sort((a: string, b: string): number => fileIo.statSync(`${directory}/${a}`).mtime - fileIo.statSync(`${directory}/${b}`).mtime);
      for (let i = 0; i < names.length - 31; i++) SubtitleFiles.remove(`${directory}/${names[i]}`);
    } catch (_error) {}
  }
}
