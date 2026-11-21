import { AppStorageV2 } from '@kit.ArkUI';
import { MiniPlayer } from './MiniPlayer';
import { Book } from '../model/Book';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { TextToSpeechState } from '../model/TextToSpeechState';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { PlayerDragState, PlayerDragTransition } from '../utils/PlayerDragTransition';

/** 转场面板复用迷你栏布局，并持续读取当前播放内容。 */
@ComponentV2
export struct PlayerTransitionMiniBar {
  @Local dragState: PlayerDragState = PlayerDragTransition.getInstance().state;
  @Local playerState: PlayerState =
    AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, (): PlayerState => new PlayerState()) ?? new PlayerState();
  @Local speechState: TextToSpeechState = TextToSpeechService.getInstance().state;

  private currentBook(): Book | null {
    return this.speechState.active ? TextToSpeechService.getInstance().currentBook() ?? null
      : this.playerState.currentBook;
  }

  private progressPercent(): number {
    const total: number = this.speechState.active ? this.speechState.contentLength :
      (this.playerState.durationMs > 0 ? this.playerState.durationMs : this.playerState.savedDurationMs);
    const position: number = this.speechState.active ? this.speechState.charOffset : this.playerState.progressMs;
    return total > 0 ? Math.max(0, Math.min(100, position * 100 / total)) : 0;
  }

  build() {
    MiniPlayer({
      book: this.currentBook(),
      chapterTitle: this.speechState.active ? this.speechState.error || this.speechState.chapterTitle
        : this.playerState.currentChapter?.title ?? '',
      playing: this.speechState.active ? this.speechState.playing : this.playerState.isPlaying,
      loading: this.speechState.active ? this.speechState.loading : this.playerState.isLoading,
      progressPercent: this.progressPercent(),
      collapsed: this.dragState.miniBarCollapsed,
      verticalStyle: this.dragState.miniBarVertical,
      compactControls: this.dragState.miniBarCompactControls,
      transitionCopy: true
    })
      .width('100%')
      .height(this.dragState.miniBarHeight)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no-hide-descendants')
  }
}
