import { ReadingSession, ReadingSessionService, SessionLocation } from '../service/ReadingSessionService';
import { DataService } from '../service/DataService';
import { Chapter } from '../model/Book';
import { TextReaderRouteParams, TextReadingPosition } from '../model/TextReading';
import { TextReadingProgressService } from '../service/text/TextReadingProgressService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { AppColor } from '../theme/Theme';
import { AudioService } from '../service/AudioService';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { WindowUtils } from '../utils/WindowUtils';
import { BookPresentation } from '../model/BookPresentation';
import { PreferenceService, EVT_FAVORITES_CHANGED } from '../service/PreferenceService';
import { emitter } from '@kit.BasicServicesKit';

class SessionDataSource implements IDataSource {
  items: ReadingSession[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): ReadingSession { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((value: DataChangeListener): boolean => value !== listener);
  }
  update(items: ReadingSession[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener): void => listener.onDataReloaded());
  }
}

@ComponentV2
export struct SessionHistoryPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Param bookIds: string = '[]';
  @Local loading: boolean = true;
  @Local failed: boolean = false;
  @Local count: number = 0;
  @Local jumping: boolean = false;
  @Local transitionOffset: number = 0;
  private transitioning: boolean = false;
  private records: SessionDataSource = new SessionDataSource();
  private scroller: Scroller = new Scroller();
  private visible: boolean = false;
  private loaded: boolean = false;
  private loadGeneration: number = 0;
  private entryTimer: number = -1;
  private allEntries: ReadingSession[] = [];
  private requestedBookIds: string[] = [];
  private favoritesHandler: (event: emitter.EventData) => void = (_event: emitter.EventData): void => {
    this.applySessionVisibility();
  };

  aboutToAppear(): void { emitter.on(EVT_FAVORITES_CHANGED, this.favoritesHandler); }

  aboutToDisappear(): void {
    emitter.off(EVT_FAVORITES_CHANGED, this.favoritesHandler);
    this.stopLoading();
  }

  private onPageShown(): void {
    this.visible = true;
    if (this.loaded || this.entryTimer !== -1) return;
    // 等当前导航事务提交；有转场时由结束回调接续，不猜测动画耗时。
    this.entryTimer = setTimeout((): void => {
      this.entryTimer = -1;
      if (this.visible && !this.transitioning) this.load();
    }, 0);
  }

  private historyTransition(operation: NavigationOperation, isEnter: boolean): NavDestinationTransition[] | undefined {
    if (operation !== NavigationOperation.PUSH && operation !== NavigationOperation.POP) return undefined;
    this.transitioning = true;
    const entering = operation === NavigationOperation.PUSH && isEnter;
    const leaving = operation === NavigationOperation.POP && !isEnter;
    this.transitionOffset = entering ? WindowUtils.getWindowWidthVp() : 0;
    return [{
      duration: 280,
      curve: Curve.FastOutSlowIn,
      event: (): void => {
        this.transitionOffset = leaving ? WindowUtils.getWindowWidthVp() : 0;
      },
      onTransitionEnd: (): void => {
        this.transitioning = false;
        if (isEnter && this.visible) this.onPageShown();
      }
    }];
  }

  private stopLoading(): void {
    this.visible = false;
    this.loadGeneration++;
    if (this.entryTimer !== -1) clearTimeout(this.entryTimer);
    this.entryTimer = -1;
  }

  private async load(): Promise<void> {
    const generation = ++this.loadGeneration;
    this.loading = true;
    this.failed = false;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Missing context');
      await PreferenceService.ensureReady(context);
      const ids: string[] = JSON.parse(this.bookIds);
      this.requestedBookIds = ids;
      const entries = await ReadingSessionService.list(ids,
        (): boolean => this.visible && generation === this.loadGeneration);
      if (!this.visible || generation !== this.loadGeneration) return;
      this.allEntries = entries;
      this.applySessionVisibility();
      this.loaded = true;
    } catch (_error) {
      if (this.visible && generation === this.loadGeneration) this.failed = true;
    } finally {
      if (this.visible && generation === this.loadGeneration) this.loading = false;
    }
  }

  private isSessionHidden(entry: ReadingSession): boolean {
    // 此路由的多个 ID 属于同一本书的 canonical/alias；任一隐藏即隐藏整组会话。
    return this.requestedBookIds.some((id: string): boolean => BookPresentation.isHidden(id)) ||
      BookPresentation.isHidden(entry.start.bookId) || BookPresentation.isHidden(entry.end.bookId);
  }

  private applySessionVisibility(): void {
    const entries = this.allEntries.filter((entry: ReadingSession): boolean => !this.isSessionHidden(entry));
    this.records.update(entries);
    this.count = entries.length;
  }

  private time(ms: number): string {
    const seconds = Math.floor(Math.max(0, ms) / 1000);
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private dateLabel(ms: number): string {
    const date = new Date(ms);
    return `${date.getFullYear()}.${(date.getMonth() + 1).toString().padStart(2, '0')}.${date.getDate().toString().padStart(2, '0')}`;
  }

  private clockLabel(ms: number): string {
    const date = new Date(ms);
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}:${date.getSeconds().toString().padStart(2, '0')}`;
  }

  private async jump(entry: ReadingSession, location: SessionLocation): Promise<void> {
    if (this.jumping || this.isSessionHidden(entry) || BookPresentation.isHidden(location.bookId)) return;
    this.jumping = true;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Missing context');
      const book = await DataService.getBookById(context, location.bookId);
      if (this.isSessionHidden(entry) || BookPresentation.isHidden(location.bookId)) return;
      if (!book) throw new Error('Book unavailable');
      const index = book.chapters.findIndex((chapter: Chapter): boolean =>
        chapter.id === location.chapterId || (!!location.chapterUrl &&
          (chapter.originSourceValue || chapter.source.value) === location.chapterUrl));
      if (index < 0 && !location.domPos) throw new Error('Chapter unavailable');
      if (entry.kind === 'audio') {
        await AudioService.getInstance().playChapterAndSeek(book, book.chapters[index], location.position);
        const params: Record<string, Object> = { 'bookId': book.id,
          'chapterId': book.chapters[index].id, 'progressMs': location.position };
        this.navStack.pushPathByName('player', params);
      } else {
        TextToSpeechService.getInstance().stop();
        await TextReadingProgressService.save(context, TextReadingPosition.atChar(book.id,
          index >= 0 ? index : location.chapterIndex, location.domPos, location.position,
          location.pageOffset, location.chapterTitle));
        if (entry.kind === 'tts') {
          await TextToSpeechService.getInstance().start(book, index, location.position, false);
        }
        this.navStack.pushPathByName(book.contentType === 'comic' ? 'comicReader' : 'reader', TextReaderRouteParams.of(book.id));
      }
    } catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.session_jump_failed') });
    } finally { this.jumping = false; }
  }

  @Builder
  buildPosition(entry: ReadingSession, location: SessionLocation) {
    if (entry.kind === 'audio') {
      Text($r('app.string.session_audio_position', location.chapterTitle,
        this.time(location.position), this.time(location.total)))
        .fontSize(14).fontColor($r('sys.color.font_secondary'))
    } else if (location.domPos.startsWith('comic:')) {
      Text($r('app.string.comic_session_position', location.chapterTitle, location.pageOffset + 1))
        .fontSize(14).fontColor($r('sys.color.font_secondary'))
    } else {
      Text($r('app.string.session_text_position', location.chapterTitle, Math.floor(location.position)))
        .fontSize(14).fontColor($r('sys.color.font_secondary'))
      if (location.total > 0) {
        Text(`${Math.min(100, Math.floor(location.position / location.total * 100))}%`)
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
    }
  }

  build() {
    HdsNavDestination() {
        List({ scroller: this.scroller, space: 0 }) {
          ListItem() {
            Text($r('app.string.session_retention')).fontSize(12)
              .fontColor($r('sys.color.font_tertiary')).padding({ bottom: 24 })
          }
          if (this.loading) {
            ListItem() { LoadingProgress().color(AppColor.Brand).width(36).height(36) }
          } else if (this.failed) {
            ListItem() { Text($r('app.string.session_load_failed')).onClick((): void => { this.load(); }) }
          } else if (this.count === 0) {
            ListItem() { Text($r('app.string.session_empty')) }
          }
          LazyForEach(this.records, (entry: ReadingSession): void => {
            ListItem() {
              Column() {
                Row({ space: 12 }) {
                  Circle().width(10).height(10).fill(AppColor.Brand)
                  Text(this.dateLabel(entry.startedAt)).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor($r('sys.color.font_primary'))
                  Blank()
                  Text(this.clockLabel(entry.startedAt)).fontSize(13).fontColor($r('sys.color.font_secondary'))
                }.width('100%').padding({ bottom: 12 })
                Column() {
                  Column({ space: 10 }) {
                    Text($r('app.string.session_start', this.clockLabel(entry.startedAt)))
                      .fontSize(12).fontColor($r('sys.color.font_tertiary'))
                    this.buildPosition(entry, entry.start)
                    Divider().color(AppColor.Divider).margin({ top: 2, bottom: 2 })
                    Text($r('app.string.session_end', `${this.dateLabel(entry.endedAt)} ${this.clockLabel(entry.endedAt)}`))
                      .fontSize(12).fontColor($r('sys.color.font_tertiary'))
                    this.buildPosition(entry, entry.end)
                    Row({ space: 8 }) {
                      Button($r('app.string.session_jump_start')).onClick((): void => { this.jump(entry, entry.start); })
                        .layoutWeight(1).fontSize(13).height(36)
                        .backgroundColor($r('sys.color.comp_background_secondary')).fontColor(AppColor.Brand)
                      Button($r('app.string.session_jump_end')).onClick((): void => { this.jump(entry, entry.end); })
                        .layoutWeight(1).fontSize(13).height(36).backgroundColor(AppColor.Brand)
                    }.enabled(!this.jumping).width('100%').margin({ top: 4 })
                  }.width('100%').alignItems(HorizontalAlign.Start).padding(16)
                  .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(16)
                }.width('100%').padding({ left: 18, bottom: 24 })
                .border({ width: { left: 1 }, color: AppColor.Divider }).margin({ left: 5 })
              }.width('100%').alignItems(HorizontalAlign.Start)
            }
          }, (entry: ReadingSession): string => entry.id)
        }.width('100%').height('100%').padding({ left: 20, right: 24 })
        .scrollBar(BarState.Off)
        .contentStartOffset(WindowUtils.getStatusBarHeightVp() + 56 + 16)
        .contentEndOffset(WindowUtils.getBottomSafeVp() + 24)
    }
    .titleBar({
      avoidLayoutSafeArea: true,
      content: {
        title: { mainTitle: $r('app.string.session_history') },
        backIcon: { icon: $r('sys.symbol.chevron_left'), action: (): void => { this.navStack.pop(); } }
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: $r('sys.color.background_secondary') },
          contentStyle: {
            titleStyle: { mainTitleColor: $r('sys.color.font_primary') },
            backIconStyle: { iconColor: $r('sys.color.icon_primary') }
          }
        }
      }
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .width('100%').height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .translate({ x: this.transitionOffset })
    .customTransition((operation: NavigationOperation, isEnter: boolean): NavDestinationTransition[] | undefined =>
      this.historyTransition(operation, isEnter))
    .onShown((): void => this.onPageShown())
    .onWillHide((): void => this.stopLoading())
  }
}
