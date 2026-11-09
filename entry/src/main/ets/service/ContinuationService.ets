import { common } from '@kit.AbilityKit';
import { AudioSource, Book, Chapter } from '../model/Book';
import { PlayerState } from '../model/PlayerState';
import { DataService } from './DataService';
import { PreferenceService, PlayProgress } from './PreferenceService';
import { AudioService } from './AudioService';
import { AVSessionService } from './AVSessionService';
import { SearchCache } from '../utils/SearchCache';

export const CONTINUATION_PAYLOAD_KEY: string = 'listenbook_continuation_v1';
const CONTINUATION_VERSION: number = 1;

class PlaybackContinuationSnapshot {
  version: number = CONTINUATION_VERSION;
  bookId: string = '';
  bookTitle: string = '';
  author: string = '';
  narrator: string = '';
  cover: string = '';
  category: string = '';
  bookUrl: string = '';
  sourceUrl: string = '';
  chapterCount: number = 0;
  chapterId: string = '';
  chapterIndex: number = 0;
  chapterTitle: string = '';
  chapterPageUrl: string = '';
  progressMs: number = 0;
  durationMs: number = 0;
  speed: number = 1.0;
  wasPlaying: boolean = false;
  variablesJson: string = '';
  chapterVariablesJson: string = '';
  skipIntro: number = 0;
  skipOutro: number = 0;
}

export class ContinuationService {
  static createPayload(state: PlayerState): string {
    const book = state.currentBook;
    const chapter = state.currentChapter;
    if (!book || !chapter || !book.id || book.id.startsWith('import_')) return '';
    const chapterPageUrl = chapter.originSourceValue || chapter.source.value;
    if (!book.bookUrl || !book.sourceUrl || !chapterPageUrl) return '';
    const snapshot = new PlaybackContinuationSnapshot();
    snapshot.bookId = book.id;
    snapshot.bookTitle = book.title;
    snapshot.author = book.author;
    snapshot.narrator = book.narrator;
    snapshot.cover = book.cover;
    snapshot.category = book.category;
    snapshot.bookUrl = book.bookUrl;
    snapshot.sourceUrl = book.sourceUrl;
    snapshot.chapterCount = Math.max(book.chapterCount, book.chapters.length);
    snapshot.chapterId = chapter.id;
    snapshot.chapterIndex = chapter.index;
    snapshot.chapterTitle = chapter.title;
    snapshot.chapterPageUrl = chapterPageUrl;
    snapshot.progressMs = Math.max(0, state.progressMs);
    snapshot.durationMs = Math.max(0, state.durationMs || state.savedDurationMs);
    snapshot.speed = ContinuationService.normalizeSpeed(state.speed);
    snapshot.wasPlaying = state.isPlaying;
    snapshot.variablesJson = book.variables ? JSON.stringify(book.variables) : '';
    snapshot.chapterVariablesJson = chapter.variables ? JSON.stringify(chapter.variables) : '';
    snapshot.skipIntro = Math.max(0, book.skipIntro ?? 0);
    snapshot.skipOutro = Math.max(0, book.skipOutro ?? 0);
    return JSON.stringify(snapshot);
  }

  static async restorePayload(context: common.UIAbilityContext, state: PlayerState,
    payload: string): Promise<string> {
    if (!payload) return '';
    const snapshot = JSON.parse(payload) as PlaybackContinuationSnapshot;
    if (!ContinuationService.isValid(snapshot)) return '';
    let variables: Record<string, string> | undefined = undefined;
    let chapterVariables: Record<string, string> | undefined = undefined;
    if (snapshot.variablesJson) {
      try {
        variables = JSON.parse(snapshot.variablesJson) as Record<string, string>;
      } catch (_e) {
        variables = undefined;
      }
    }
    if (snapshot.chapterVariablesJson) {
      try {
        chapterVariables = JSON.parse(snapshot.chapterVariablesJson) as Record<string, string>;
      } catch (_e) {
        chapterVariables = undefined;
      }
    }
    const source: AudioSource = { type: 'url', value: snapshot.chapterPageUrl };
    const chapter: Chapter = {
      id: snapshot.chapterId,
      index: Math.max(1, snapshot.chapterIndex),
      title: snapshot.chapterTitle,
      duration: Math.floor(snapshot.durationMs / 1000),
      source: source,
      originSourceValue: snapshot.chapterPageUrl,
      variables: chapterVariables
    };
    const book: Book = {
      id: snapshot.bookId,
      contentType: 'audio',
      title: snapshot.bookTitle,
      author: snapshot.author,
      narrator: snapshot.narrator,
      cover: snapshot.cover,
      category: snapshot.category,
      intro: '',
      totalDuration: 0,
      chapterCount: Math.max(1, snapshot.chapterCount),
      rating: 0,
      tags: [],
      chapters: [chapter],
      bookUrl: snapshot.bookUrl,
      sourceUrl: snapshot.sourceUrl,
      variables: variables,
      skipIntro: Math.max(0, snapshot.skipIntro),
      skipOutro: Math.max(0, snapshot.skipOutro)
    };

    await DataService.restoreBackupBookShells([book]);
    SearchCache.put(book);
    await PreferenceService.saveSkipConfig(book.id, book.skipIntro ?? 0, book.skipOutro ?? 0);
    const speed = ContinuationService.normalizeSpeed(snapshot.speed);
    const progress: PlayProgress = {
      bookId: book.id,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      chapterIndex: chapter.index,
      positionMs: Math.max(0, snapshot.progressMs),
      durationMs: Math.max(0, snapshot.durationMs),
      updatedAt: Date.now(),
      speed: speed,
      sourceUrl: book.sourceUrl,
      bookUrl: book.bookUrl
    };
    await PreferenceService.saveProgress(progress);
    await PreferenceService.setLastPlayed(book.id, chapter.id, progress.positionMs,
      chapter.title, progress.durationMs, speed);

    state.currentBook = book;
    state.currentChapter = chapter;
    state.progressMs = progress.positionMs;
    state.durationMs = progress.durationMs;
    state.savedDurationMs = progress.durationMs;
    state.speed = speed;
    state.isPlaying = false;
    const audioService = AudioService.getInstance();
    audioService.bind(state, context);
    if (snapshot.wasPlaying) {
      await audioService.playChapterAndSeek(book, chapter, progress.positionMs);
      await audioService.setSpeed(speed);
    } else {
      await AVSessionService.getInstance().updateMetadata(book, chapter);
      await AVSessionService.getInstance().updatePlaybackState(false, progress.positionMs,
        speed, progress.durationMs);
    }
    return book.id;
  }

  private static isValid(snapshot: PlaybackContinuationSnapshot): boolean {
    return !!snapshot && snapshot.version === CONTINUATION_VERSION
      && !!snapshot.bookId && !snapshot.bookId.startsWith('import_')
      && !!snapshot.bookTitle && !!snapshot.bookUrl && !!snapshot.sourceUrl
      && !!snapshot.chapterId && !!snapshot.chapterTitle && !!snapshot.chapterPageUrl;
  }

  private static normalizeSpeed(speed: number): number {
    if (!Number.isFinite(speed) || speed <= 0) return 1.0;
    return Math.min(4.0, Math.max(0.125, speed));
  }
}
