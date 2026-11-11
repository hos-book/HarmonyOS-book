import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { Book } from '../model/Book';
import { PlayerState } from '../model/PlayerState';
import { AudioSubtitleState } from '../model/AudioSubtitleState';
import { SubtitleCue, SubtitleTimeline } from '../model/AudioSubtitle';
import { AudioSubtitleService } from '../service/subtitle/AudioSubtitleService';
import { AppColor } from '../theme/Theme';

class SubtitleDataSource implements IDataSource {
  private items: SubtitleCue[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): SubtitleCue { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  update(items: SubtitleCue[]): void {
    this.items = items;
    for (const listener of this.listeners) listener.onDataReloaded();
  }
}

@ComponentV2
export struct AudioSubtitlePanel {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param book: Book | null = null;
  @Param playerState: PlayerState = new PlayerState();
  @Local state: AudioSubtitleState = AudioSubtitleService.instance.state;
  @Local activeId: string = '';
  @Local following: boolean = true;
  @Local viewportHeight: number = 220;
  private source: SubtitleDataSource = new SubtitleDataSource();
  private scroller: Scroller = new Scroller();
  private context: common.Context | undefined = undefined;
  private mounted: boolean = false;
  private foreground: boolean = true;
  private visible: boolean = true;
  private chapterKey: string = '';
  private scrollTimer: number = -1;
  private displayedRevision: number = -1;
  private backgroundHandler = (): void => {
    this.foreground = false;
    AudioSubtitleService.instance.release();
    this.chapterKey = '';
  };
  private foregroundHandler = (): void => { this.foreground = true; this.syncChapter(); };
  private modelsHandler = (): void => { this.chapterKey = ''; this.syncChapter(); };

  aboutToAppear(): void {
    this.mounted = true;
    this.context = this.getUIContext().getHostContext();
    emitter.on('app.reader.background', this.backgroundHandler);
    emitter.on('app.reader.foreground', this.foregroundHandler);
    emitter.on('app.ai.models.changed', this.modelsHandler);
    this.syncChapter();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    emitter.off('app.reader.background', this.backgroundHandler);
    emitter.off('app.reader.foreground', this.foregroundHandler);
    emitter.off('app.ai.models.changed', this.modelsHandler);
    if (this.scrollTimer !== -1) clearTimeout(this.scrollTimer);
    AudioSubtitleService.instance.release();
  }

  @Monitor('playerState.currentChapter', 'playerState.currentBook', 'playerState.isLoading', 'playerState.durationMs')
  chapterChanged(): void { this.syncChapter(); }

  @Monitor('playerState.progressMs', 'state.revision')
  progressChanged(): void {
    if (!this.mounted || !this.foreground || !this.visible) return;
    if (this.displayedRevision !== this.state.revision) {
      this.source.update(this.state.cues);
      this.displayedRevision = this.state.revision;
    }
    const index = SubtitleTimeline.activeIndex(this.state.cues, this.playerState.progressMs);
    const next = index >= 0 ? this.state.cues[index].id : '';
    const changed = this.activeId !== next;
    this.activeId = next;
    if (this.following && changed && index >= 0) this.scrollToCue(index);
    AudioSubtitleService.instance.tick(this.playerState.progressMs);
  }

  private syncChapter(downloadModel: boolean = false): void {
    if (!this.mounted || !this.foreground || !this.visible || !this.context || !this.book) return;
    const chapter = this.playerState.currentChapter;
    if (!chapter || this.playerState.currentBook?.id !== this.book.id || this.playerState.isLive ||
      this.playerState.isLoading || this.playerState.durationMs <= 0) {
      AudioSubtitleService.instance.release();
      this.chapterKey = ''; this.activeId = ''; this.source.update([]);
      return;
    }
    const key = `${this.book.id}:${chapter.id}:${chapter.source.value}:${this.playerState.durationMs}`;
    if (key === this.chapterKey && !downloadModel) return;
    this.chapterKey = key; this.following = true; this.activeId = ''; this.source.update([]);
    AudioSubtitleService.instance.showPanel(this.context, this.book, chapter, this.playerState.durationMs,
      this.playerState.progressMs, downloadModel);
  }

  private scrollToCue(index: number): void {
    if (this.scrollTimer !== -1) clearTimeout(this.scrollTimer);
    this.scrollTimer = setTimeout((): void => {
      this.scrollTimer = -1;
      if (!this.mounted || !this.following) return;
      try { this.scroller.scrollToIndex(index, true, ScrollAlign.CENTER); } catch (_error) {}
    }, 32);
  }

  private follow(): void {
    this.following = true;
    const index = SubtitleTimeline.activeIndex(this.state.cues, this.playerState.progressMs);
    if (index >= 0) this.scrollToCue(index);
  }

  private statusText(): ResourceStr {
    if (this.playerState.isLive) return $r('app.string.subtitle_unsupported');
    if (this.playerState.isLoading) return $r('app.string.subtitle_wait_audio');
    if (this.state.phase === 'idle') return $r('app.string.subtitle_start_audio');
    if (this.state.phase === 'needsModel') return $r('app.string.subtitle_model_prompt');
    if (this.state.phase === 'model') return $r('app.string.subtitle_model_downloading', this.state.percent);
    if (this.state.phase === 'audio') return $r('app.string.subtitle_audio_preparing');
    if (this.state.phase === 'preparing') return $r('app.string.subtitle_preparing');
    if (this.state.phase === 'error') {
      if (this.state.error === 'subtitle_unsupported') return $r('app.string.subtitle_unsupported');
      if (this.state.error === 'subtitle_space') return $r('app.string.subtitle_space');
      if (this.state.error === 'subtitle_too_large') return $r('app.string.subtitle_too_large');
      return $r('app.string.subtitle_failed');
    }
    if (this.state.phase === 'recognizing') return $r('app.string.subtitle_recognizing');
    return $r('app.string.subtitle_silence');
  }

  build() {
    Column({ space: 8 }) {
      if (this.state.cues.length > 0) {
        Stack() {
        List({ scroller: this.scroller }) {
          LazyForEach(this.source, (cue: SubtitleCue) => {
            ListItem() {
              Text(cue.text).fontSize(16).lineHeight(26).width('100%').padding({ top: 8, bottom: 8 })
                .fontColor(cue.id === this.activeId ? '#FFFFFF' : '#99FFFFFF')
                .fontWeight(cue.id === this.activeId ? FontWeight.Medium : FontWeight.Normal)
            }
          }, (cue: SubtitleCue): string => cue.id)
        }.width('100%').height('100%').scrollBar(BarState.Off).cachedCount(2)
          .contentStartOffset(Math.max(0, this.viewportHeight / 2 - 21))
          .contentEndOffset(Math.max(0, this.viewportHeight / 2 - 21))
          .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) this.following = false; })
          .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
            if (typeof size.height === 'number') this.viewportHeight = size.height;
          })
        Column().width('100%').height('100%')
          .linearGradient({ direction: GradientDirection.Bottom,
            colors: [['#00FFFFFF', 0], ['#FFFFFFFF', 0.08], ['#FFFFFFFF', 0.92], ['#00FFFFFF', 1]] })
          .blendMode(BlendMode.DST_IN).hitTestBehavior(HitTestMode.None)
        }.width('100%').layoutWeight(1)
          .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
        Row({ space: 8 }) {
          Text(this.state.phase === 'error' || (!this.activeId && this.state.phase === 'recognizing') ?
            this.statusText() : $r('app.string.subtitle_ai_hint'))
            .fontSize(11).fontColor('#99FFFFFF').layoutWeight(1).maxLines(2)
          if (!this.following) {
            Button($r('app.string.subtitle_follow')).fontSize(12).fontColor('#FFFFFF')
              .backgroundColor('#22FFFFFF').height(32).onClick((): void => this.follow())
          }
          if (this.state.phase === 'error') {
            Button($r('app.string.subtitle_retry')).fontSize(12).fontColor('#FFFFFF')
              .backgroundColor('#22FFFFFF').height(32).onClick((): void => { this.chapterKey = ''; this.syncChapter(); })
          }
        }.width('100%')
      } else {
        Column({ space: 16 }) {
          if (this.state.phase === 'model' || this.state.phase === 'audio' ||
            this.state.phase === 'preparing' || this.state.phase === 'recognizing') {
            LoadingProgress().width(28).height(28).color(AppColor.Brand)
          }
          Text(this.statusText()).fontSize(14).lineHeight(22).fontColor('#CCFFFFFF').textAlign(TextAlign.Center)
          if (this.state.phase === 'needsModel') {
            Button($r('app.string.model_pack_import')).backgroundColor(AppColor.Brand)
              .onClick((): void => { this.navStack.pushPathByName('aiModelSettings', 'audio-subtitle-v1'); })
              .id('subtitle-import-model')
          } else if (this.state.phase === 'error') {
            Button($r('app.string.subtitle_retry')).backgroundColor(AppColor.Brand)
              .onClick((): void => { this.chapterKey = ''; this.syncChapter(); })
          }
        }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').id('audio-subtitle-panel')
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible === visible) return;
        this.visible = visible;
        if (visible) this.syncChapter();
        else { AudioSubtitleService.instance.release(); this.chapterKey = ''; }
      })
  }
}
