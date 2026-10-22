import { common } from '@kit.AbilityKit';
import { AudioService } from './AudioService';
import { TextToSpeechService } from './text/TextToSpeechService';
import { PreferenceService } from './PreferenceService';
import { DataService } from './DataService';
import { BookSourceService } from './BookSourceService';

/** 卡片命令按当前播放类型分发，冷启动也保留电子书身份和字符进度。 */
export class WidgetPlaybackService {
  private static generation: number = 0;

  static async execute(context: common.UIAbilityContext, command: string): Promise<void> {
    const ticket = ++WidgetPlaybackService.generation;
    const audio = AudioService.getInstance();
    await audio.whenReady();
    if (ticket !== WidgetPlaybackService.generation) return;
    const speech = TextToSpeechService.getInstance();
    if (speech.state.active && speech.currentBook() !== null) {
      if (command === 'play') await speech.resume();
      else if (command === 'pause') speech.pause();
      else if (command === 'next') await speech.moveChapter(1);
      else if (command === 'prev') await speech.moveChapter(-1);
      return;
    }
    const snapshot = await PreferenceService.getWidgetPlayerSnapshot();
    if (ticket !== WidgetPlaybackService.generation) return;
    if (snapshot?.playbackKind === 'tts') {
      if (command === 'pause') return;
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
    if (command === 'play') await audio.play();
    else if (command === 'pause') await audio.pause('widget');
    else if (command === 'next') await audio.playNext();
    else if (command === 'prev') await audio.playPrevious();
  }
}
