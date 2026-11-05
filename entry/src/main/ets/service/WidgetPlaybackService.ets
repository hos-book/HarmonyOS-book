import { common } from '@kit.AbilityKit';
import { AudioService } from './AudioService';
import { PlaybackStore } from './PlaybackStore';
import { TextToSpeechService } from './text/TextToSpeechService';
import { PreferenceService } from './PreferenceService';
import { DataService } from './DataService';
import { BookSourceService } from './BookSourceService';

/** 卡片命令按当前播放类型分发，冷启动也保留电子书身份和字符进度。 */
export class WidgetPlaybackService {
  private static generation: number = 0;
  private static initialize: (() => Promise<void>) | null = null;

  static setInitializer(initialize: () => Promise<void>): void {
    WidgetPlaybackService.initialize = initialize;
  }

  static async execute(context: common.UIAbilityContext, command: string): Promise<void> {
    const ticket = ++WidgetPlaybackService.generation;
    const audio = AudioService.getInstance();
    const speech = TextToSpeechService.getInstance();
    // 卡片的 isPlaying 可能来自已被回收的进程，只信任当前进程的播放状态。
    if (command === 'toggle') {
      command = (speech.state.active && (speech.state.playing || speech.state.loading)) ||
        PlaybackStore.getInstance().isPlayingNow() ? 'pause' : 'play';
    }
    // 暂停优先直达运行中的播放器，同时取消尚未完成的冷启动播放。
    // 卡片快照可能陈旧，偏好缓存刷新也可能暂时不可读，均不能阻断暂停。
    if (command === 'pause') {
      if (speech.state.active && speech.currentBook() !== null) speech.pause();
      else await audio.pause('widget');
      return;
    }
    if (WidgetPlaybackService.initialize !== null) await WidgetPlaybackService.initialize();
    if (ticket !== WidgetPlaybackService.generation) return;
    await audio.whenReady();
    if (ticket !== WidgetPlaybackService.generation) return;
    if (speech.state.active && speech.currentBook() !== null) {
      if (command === 'play') await speech.resume();
      else if (command === 'next') await speech.moveChapter(1);
      else if (command === 'prev') await speech.moveChapter(-1);
      return;
    }
    if (PlaybackStore.getInstance().isPlayingNow()) {
      await WidgetPlaybackService.executeAudio(command);
      return;
    }
    const snapshot = await PreferenceService.getWidgetPlayerSnapshot();
    if (ticket !== WidgetPlaybackService.generation) return;
    if (snapshot?.playbackKind === 'tts') {
      let book = speech.currentBook();
      if (book?.id !== snapshot.bookId) book = await DataService.getBookById(context, snapshot.bookId) ?? null;
      if (!book || book.contentType !== 'text' || ticket !== WidgetPlaybackService.generation) return;
      if (book.chapters.length === 0) book.chapters = await DataService.getChaptersForBook(book.id);
      if (book.chapters.length === 0) book = await BookSourceService.loadTextBook(book);
      await PreferenceService.applyTocOrder(book);
      await speech.initialize(context);
      if (ticket !== WidgetPlaybackService.generation || book.chapters.length === 0) return;
      const index = Math.max(0, book.chapters.findIndex((chapter): boolean => chapter.id === snapshot.chapterId));
      const step = command === 'next' ? 1 : command === 'prev' ? -1 : 0;
      const target = index + step;
      if (target < 0 || target >= book.chapters.length) return;
      await speech.start(book, target, step === 0 ? snapshot.charOffset ?? 0 : 0, step === 0);
      return;
    }
    await WidgetPlaybackService.executeAudio(command);
  }

  private static async executeAudio(command: string): Promise<void> {
    const audio = AudioService.getInstance();
    if (command === 'play') await audio.play();
    else if (command === 'next') await audio.playNext();
    else if (command === 'prev') await audio.playPrevious();
  }
}
