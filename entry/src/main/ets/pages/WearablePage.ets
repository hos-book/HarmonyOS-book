import { AppStorageV2 } from '@kit.ArkUI';
import { emitter } from '@kit.BasicServicesKit';
import { Book, Chapter } from '../model/Book';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { AudioService, EVT_AUDIO_PLAY_FAILED } from '../service/AudioService';
import { AuthService } from '../service/AuthService';
import lazy { CloudBackupService, CloudBackupInfo } from '../service/CloudBackupService';
import { DataService } from '../service/DataService';
import { DownloadService, EVT_DOWNLOAD_UPDATED } from '../service/DownloadService';
import { PreferenceService } from '../service/PreferenceService';
import { SourceDataService } from '../service/SourceDataService';
import { WearableRuntime } from '../service/wearable/WearableRuntime';
import { WearableLibraryService } from '../service/wearable/WearableLibraryService';
import { BookDataSource } from '../utils/BookDataSource';
import { ChapterDataSource } from '../utils/ChapterDataSource';
import { AppColor } from '../theme/Theme';
import { WebEngineGate } from '../service/WebEngineGate';
import { WebBookFetchRuntimeHost } from '../service/rulesource/light/WebBookFetchRuntimeHost';
import { BookSourceAudioWebRuntimeHost } from '../service/rulesource/light/BookSourceAudioWebRuntimeHost';
import { RuleSourceImportWebHost } from '../service/rulesource/light/RuleSourceImportWebHost';

@Entry
@ComponentV2
struct WearablePage {
  @Local private player: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local private runtime: WearableRuntime = WearableRuntime.instance;
  @Local private account: AuthService = AuthService.instance;
  @Local private screen: string = 'home';
  @Local private busy: boolean = false;
  @Local private keyword: string = '';
  @Local private sourceAddress: string = '';
  @Local private sourceCount: number = 0;
  @Local private bookCount: number = 0;
  @Local private selectedBook: Book | null = null;
  @Local private favorite: boolean = false;
  @Local private notice: ResourceStr = '';
  @Local private downloadRevision: number = 0;
  @Local private confirmDelete: boolean = false;
  @Local private cloudInfo: CloudBackupInfo | null = null;
  @Local private viewportHeight: number = 0;
  private cloudConfirmation: ((accepted: boolean) => void) | null = null;
  private cloudOperation: boolean = false;
  private gate: WebEngineGate = WebEngineGate.instance;
  private books: BookDataSource = new BookDataSource();
  private chapters: ChapterDataSource = new ChapterDataSource();
  private results: Book[] = [];
  private searchPage: number = 1;
  private searchKeyword: string = '';
  private generation: number = 0;
  private alive: boolean = false;
  private bookOrigin: string = 'shelf';
  private scroller: Scroller = new Scroller();
  private downloadUpdated = (): void => { this.downloadRevision++; };
  private playbackFailed = (): void => { this.notice = $r('app.string.watch_play_failed'); };

  aboutToAppear(): void {
    this.alive = true;
    emitter.on(EVT_DOWNLOAD_UPDATED, this.downloadUpdated);
    emitter.on(EVT_AUDIO_PLAY_FAILED, this.playbackFailed);
    this.initialize();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.cancelCloudRestore();
    emitter.off(EVT_DOWNLOAD_UPDATED, this.downloadUpdated);
    emitter.off(EVT_AUDIO_PLAY_FAILED, this.playbackFailed);
  }

  onBackPress(): boolean {
    if (this.screen === 'home') return false;
    this.back();
    return true;
  }

  private async initialize(): Promise<void> {
    const context = this.runtime.getContext();
    if (!context) return;
    await this.runtime.initialize(context);
    if (!this.alive || !this.runtime.ready) return;
    this.sourceCount = (await SourceDataService.getEnabledSources()).length;
  }

  private navigate(screen: string): void {
    this.cancelCloudRestore();
    this.generation++;
    this.busy = false;
    this.notice = '';
    this.confirmDelete = false;
    this.screen = screen;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private back(): void {
    if (this.screen === 'player' && this.selectedBook) this.navigate('detail');
    else if (this.screen === 'detail') {
      const origin = this.bookOrigin;
      this.navigate(origin);
      if (origin === 'search') {
        this.books.setBooks(this.results);
        this.bookCount = this.results.length;
      } else this.loadShelf();
    } else this.navigate('home');
  }

  private async loadShelf(): Promise<void> {
    this.navigate('shelf');
    const context = this.runtime.getContext();
    if (!context) return;
    const generation = this.generation;
    this.busy = true;
    this.books.clear();
    this.bookCount = 0;
    try {
      const books = await WearableLibraryService.shelf(context);
      if (!this.alive || generation !== this.generation) return;
      this.books.setBooks(books);
      this.bookCount = books.length;
    } catch (_error) {
      if (generation === this.generation) this.notice = $r('app.string.watch_operation_failed');
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }

  private async search(more: boolean = false): Promise<void> {
    if (this.busy || this.keyword.trim().length === 0) return;
    const generation = ++this.generation;
    this.busy = true;
    this.notice = '';
    const nextPage = more && this.keyword.trim() === this.searchKeyword ? this.searchPage + 1 : 1;
    this.searchKeyword = this.keyword.trim();
    if (nextPage === 1) {
      this.results = [];
      this.books.clear();
      this.bookCount = 0;
    }
    try {
      const result = await WearableLibraryService.search(this.searchKeyword, nextPage,
        (): boolean => !this.alive || generation !== this.generation);
      if (!this.alive || generation !== this.generation) return;
      const seen = new Set<string>(this.results.map((book: Book): string => book.id));
      for (const book of result.books) {
        if (!seen.has(book.id)) { seen.add(book.id); this.results.push(book); }
      }
      this.searchPage = nextPage;
      this.books.setBooks(this.results);
      this.bookCount = this.results.length;
      if (result.sourceCount === 0) this.notice = $r('app.string.watch_no_sources');
      else if (result.failedCount > 0) this.notice = $r('app.string.watch_search_partial', result.failedCount);
      else if (result.books.length === 0) this.notice = $r('app.string.watch_no_results');
    } catch (_error) {
      if (generation === this.generation) this.notice = $r('app.string.watch_operation_failed');
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }

  private async openBook(book: Book): Promise<void> {
    this.bookOrigin = this.screen;
    this.navigate('detail');
    this.selectedBook = book;
    this.chapters.setChapters([]);
    this.favorite = false;
    const generation = this.generation;
    this.busy = true;
    try {
      const loaded = await WearableLibraryService.openBook(book);
      const favorite = await PreferenceService.isFavorite(loaded.id);
      await PreferenceService.applyTocOrder(loaded);
      if (!this.alive || generation !== this.generation) return;
      this.selectedBook = loaded;
      this.favorite = favorite;
      this.chapters.setChapters(PreferenceService.orderedChapters(loaded));
      if (loaded.chapters.length === 0) this.notice = $r('app.string.watch_no_chapters');
    } catch (_error) {
      if (generation === this.generation) this.notice = $r('app.string.watch_book_failed');
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }

  private async play(chapter: Chapter): Promise<void> {
    const book = this.selectedBook;
    if (!book || !this.runtime.ready || this.busy || this.player.isLoading) return;
    this.navigate('player');
    await this.run(async (): Promise<void> => {
      await AudioService.getInstance().playChapterFromSavedProgress(book, chapter);
    });
  }

  private async run(action: () => Promise<void>): Promise<void> {
    if (this.busy) return;
    const generation = this.generation;
    this.busy = true;
    this.notice = '';
    try { await action(); } catch (_error) {
      if (generation === this.generation) this.notice = $r('app.string.watch_operation_failed');
    } finally {
      if (generation === this.generation) this.busy = false;
    }
  }

  private async toggleFavorite(): Promise<void> {
    const book = this.selectedBook;
    if (!book) return;
    await this.run(async (): Promise<void> => {
      await DataService.upsertCachedBook(book);
      this.favorite = await PreferenceService.toggleFavorite(book.id);
    });
  }

  private async download(): Promise<void> {
    const book = this.selectedBook;
    if (!book || book.chapters.length === 0) return;
    await this.run(async (): Promise<void> => {
      const current = this.player.currentBook?.id === book.id ? this.player.currentChapter : null;
      const index = current ? book.chapters.findIndex((chapter: Chapter): boolean => chapter.id === current.id) : 0;
      await DataService.upsertCachedBook(book);
      const count = await DownloadService.getInstance().downloadNextChapters(book, Math.max(0, index), 5);
      this.notice = $r('app.string.watch_download_queued', count);
      this.downloadRevision++;
    });
  }

  private downloadStatus(): ResourceStr {
    // 订阅共享下载事件，不在手表前台做高频轮询。
    if (this.downloadRevision < 0 || !this.selectedBook) return '';
    const record = DownloadService.getInstance().getBookStatus(this.selectedBook.id);
    if (!record) return $r('app.string.watch_not_downloaded');
    return $r('app.string.watch_download_status', record.downloadedCount, record.chapters.length, record.failedCount);
  }

  private chapterDownloaded(chapter: Chapter): boolean {
    if (this.downloadRevision < 0 || !this.selectedBook) return false;
    return DownloadService.getInstance().getChapterStatus(this.selectedBook.id, chapter)?.status === 'completed';
  }

  private async importSources(): Promise<void> {
    await this.run(async (): Promise<void> => {
      const count = await WearableLibraryService.importSource(this.sourceAddress);
      this.sourceCount = (await SourceDataService.getEnabledSources()).length;
      this.sourceAddress = '';
      this.notice = $r('app.string.watch_imported', count);
    });
  }

  private cancelCloudRestore(): void {
    this.cloudConfirmation?.(false);
    this.cloudConfirmation = null;
    this.cloudInfo = null;
    if (this.cloudOperation) CloudBackupService.instance.cancel();
  }

  private async restorePhoneLibrary(): Promise<void> {
    const context = this.runtime.getContext();
    if (!context || this.cloudOperation) return;
    const generation = this.generation;
    await this.run(async (): Promise<void> => {
      this.cloudOperation = true;
      try {
        const restored = await CloudBackupService.instance.restore(context, (info: CloudBackupInfo): Promise<boolean> => {
          if (!this.alive || generation !== this.generation) return Promise.resolve(false);
          this.cloudInfo = info;
          this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
          return new Promise<boolean>((resolve): void => { this.cloudConfirmation = resolve; });
        });
        if (restored && this.alive && generation === this.generation) {
          this.sourceCount = (await SourceDataService.getEnabledSources()).length;
          this.notice = $r('app.string.watch_cloud_restored');
        }
      } finally {
        this.cloudOperation = false;
        this.cloudInfo = null;
        this.cloudConfirmation = null;
      }
    });
  }

  private clock(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  @Builder
  private action(label: ResourceStr, clicked: () => void) {
    Button(label).width('100%').constraintSize({ minHeight: 40 }).fontSize(14)
      .fontColor('#FFFFFF').backgroundColor('#252525').onClick(clicked)
  }

  @Builder
  private bookRows() {
    LazyForEach(this.books, (book: Book) => {
      ListItem() {
        Column({ space: 4 }) {
          Text(book.title).fontSize(16).fontColor('#FFFFFF').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(book.author || book.narrator).fontSize(12).fontColor('#BBBBBB').maxLines(1)
        }.width('100%').padding(10).constraintSize({ minHeight: 48 }).borderRadius(18)
          .backgroundColor('#1C1C1E').onClick((): void => { this.openBook(book); })
      }
    }, (book: Book): string => book.id);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 列表使用完整屏高；首尾避让属于滚动内容，不能缩短视口形成横向裁切。
      List({ space: 8, scroller: this.scroller }) {
        ListItem() {
          if (this.screen === 'home') {
            Text($r('app.string.watch_title')).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').width('100%').textAlign(TextAlign.Center)
          } else {
            this.action($r('app.string.watch_back'), (): void => { this.back(); })
          }
        }
        if (!this.runtime.ready) {
          ListItem() {
            if (this.runtime.failed) {
              this.action($r('app.string.watch_retry_init'), (): void => { this.initialize(); })
            } else { LoadingProgress().width(32).height(32).color(AppColor.Brand) }
          }
        } else {
          if (this.cloudInfo) {
            ListItem() { Text($r('app.string.watch_cloud_confirm', this.cloudInfo.bookCount, this.cloudInfo.sourceCount)).fontSize(14).fontColor('#FFFFFF') }
            ListItem() {
              this.action($r('app.string.watch_cloud_apply'), (): void => {
                this.cloudConfirmation?.(true);
                this.cloudConfirmation = null;
                this.cloudInfo = null;
              })
            }
            ListItem() { this.action($r('app.string.watch_back'), (): void => { this.cancelCloudRestore(); }) }
          } else if (this.screen === 'home') {
            ListItem() { this.action($r('app.string.watch_shelf'), (): void => { this.loadShelf(); }) }
            ListItem() { this.action($r('app.string.watch_search'), (): void => { this.navigate('search'); this.books.setBooks(this.results); this.bookCount = this.results.length; }) }
            if (this.player.currentBook) {
              ListItem() { this.action($r('app.string.watch_now_playing'), (): void => { this.selectedBook = null; this.navigate('player'); }) }
            }
            ListItem() { this.action($r('app.string.watch_sources'), (): void => { this.navigate('sources'); }) }
            ListItem() { this.action($r('app.string.watch_account'), (): void => { this.navigate('account'); }) }
          } else if (this.screen === 'shelf') {
            if (!this.busy && this.bookCount === 0) {
              ListItem() { Text($r('app.string.watch_empty_shelf')).fontColor('#BBBBBB').fontSize(14) }
            }
            this.bookRows()
          } else if (this.screen === 'search') {
            ListItem() {
              TextInput({ text: this.keyword, placeholder: $r('app.string.watch_keyword') }).maxLength(100)
                .fontSize(14).fontColor('#FFFFFF').backgroundColor('#252525')
                .onChange((value: string): void => { this.keyword = value; })
                .onSubmit((): void => { this.search(); })
            }
            ListItem() { this.action($r('app.string.watch_search'), (): void => { this.search(); }) }
            this.bookRows()
            if (this.bookCount > 0) {
              ListItem() { this.action($r('app.string.watch_more'), (): void => { this.search(true); }) }
            }
          } else if (this.screen === 'detail') {
            ListItem() { Text(this.selectedBook?.title ?? '').fontSize(16).fontColor('#FFFFFF') }
            ListItem() { this.action(this.favorite ? $r('app.string.watch_unfavorite') : $r('app.string.watch_favorite'), (): void => { this.toggleFavorite(); }) }
            ListItem() { this.action($r('app.string.watch_download_five'), (): void => { this.download(); }) }
            ListItem() { Text(this.downloadStatus()).fontSize(12).fontColor('#BBBBBB') }
            ListItem() {
              this.action($r('app.string.watch_pause_download'), (): void => {
                const book = this.selectedBook;
                if (book) this.run((): Promise<void> => DownloadService.getInstance().pauseBook(book.id));
              })
            }
            ListItem() {
              this.action($r('app.string.watch_resume_download'), (): void => {
                const book = this.selectedBook;
                if (book) this.run((): Promise<void> => DownloadService.getInstance().resumeBook(book.id));
              })
            }
            ListItem() {
              this.action(this.confirmDelete ? $r('app.string.watch_confirm_delete') : $r('app.string.watch_delete_download'), (): void => {
                if (!this.confirmDelete) { this.confirmDelete = true; return; }
                const book = this.selectedBook;
                if (book) this.run(async (): Promise<void> => {
                  await DownloadService.getInstance().deleteBookDownload(book.id);
                  this.confirmDelete = false;
                  this.downloadRevision++;
                });
              })
            }
            LazyForEach(this.chapters, (chapter: Chapter) => {
              ListItem() {
                Column({ space: 3 }) {
                  Text(chapter.title).fontSize(15).fontColor('#FFFFFF').maxLines(3)
                  if (this.chapterDownloaded(chapter)) { Text($r('app.string.watch_offline')).fontSize(12).fontColor(AppColor.Brand) }
                }.width('100%').padding(10).constraintSize({ minHeight: 44 }).borderRadius(18)
                  .backgroundColor('#1C1C1E').onClick((): void => { this.play(chapter); })
              }
            }, (chapter: Chapter): string => chapter.id)
          } else if (this.screen === 'player') {
            ListItem() { Text(this.player.currentBook?.title ?? '').fontSize(16).fontColor('#FFFFFF').maxLines(2) }
            ListItem() { Text(this.player.currentChapter?.title ?? '').fontSize(14).fontColor('#BBBBBB').maxLines(2) }
            ListItem() {
              this.action(this.player.isPlaying ? $r('app.string.watch_pause') : $r('app.string.watch_play'), (): void => {
                this.run((): Promise<void> => AudioService.getInstance().toggle());
              })
            }
            ListItem() {
              Text(`${this.clock(this.player.progressMs)} / ${this.clock(this.player.durationMs || this.player.savedDurationMs)}`)
                .fontSize(13).fontColor('#BBBBBB').width('100%').textAlign(TextAlign.Center)
            }
            ListItem() { this.action($r('app.string.watch_rewind'), (): void => { this.run((): Promise<void> => AudioService.getInstance().seekBy(-15000)); }) }
            ListItem() { this.action($r('app.string.watch_forward'), (): void => { this.run((): Promise<void> => AudioService.getInstance().seekBy(15000)); }) }
            ListItem() { this.action($r('app.string.watch_previous'), (): void => { this.run((): Promise<void> => AudioService.getInstance().playPrevious()); }) }
            ListItem() { this.action($r('app.string.watch_next'), (): void => { this.run((): Promise<void> => AudioService.getInstance().playNext()); }) }
            ListItem() {
              this.action($r('app.string.watch_download_current'), (): void => {
                const book = this.player.currentBook;
                const chapter = this.player.currentChapter;
                if (book && chapter) this.run(async (): Promise<void> => {
                  const count = await DownloadService.getInstance().downloadChapter(book, chapter);
                  this.notice = $r('app.string.watch_download_queued', count);
                });
              })
            }
          } else if (this.screen === 'sources') {
            ListItem() { Text($r('app.string.watch_source_count', this.sourceCount)).fontSize(14).fontColor('#BBBBBB') }
            ListItem() { Text($r('app.string.watch_import_hint')).fontSize(14).fontColor('#BBBBBB') }
            ListItem() {
              TextInput({ text: this.sourceAddress, placeholder: 'https://' }).maxLength(4096).fontSize(14)
                .fontColor('#FFFFFF').backgroundColor('#252525')
                .onChange((value: string): void => { this.sourceAddress = value; })
            }
            ListItem() { this.action($r('app.string.watch_import'), (): void => { this.importSources(); }) }
          } else if (this.screen === 'account') {
            ListItem() {
              Text(this.account.isLoggedIn ? this.account.nickName || this.account.maskedId() : $r('app.string.watch_account_pending'))
                .fontSize(15).fontColor('#FFFFFF')
            }
            ListItem() { Text($r('app.string.watch_account_hint')).fontSize(13).fontColor('#BBBBBB') }
            if (this.account.isLoggedIn && canIUse('SystemCapability.FileManagement.DistributedFileService.CloudSync.Core')) {
              ListItem() { Text($r('app.string.watch_cloud_hint')).fontSize(13).fontColor('#BBBBBB') }
              ListItem() { this.action($r('app.string.watch_cloud_restore'), (): void => { this.restorePhoneLibrary(); }) }
            }
            ListItem() {
              this.action($r('app.string.watch_account_retry'), (): void => {
                const context = this.runtime.getContext();
                if (context) this.run(async (): Promise<void> => {
                  const restored = await this.account.restoreSharedAccount(context);
                  this.notice = restored ? $r('app.string.watch_account_ready') : $r('app.string.watch_account_pending');
                });
              })
            }
            if (!this.account.isLoggedIn) {
              ListItem() {
                this.action($r('app.string.watch_account_login'), (): void => {
                  const context = this.runtime.getContext();
                  if (context) this.run(async (): Promise<void> => { await this.account.login(context); });
                })
              }
            }
          }
          if (this.busy || this.player.isLoading && this.screen === 'player') {
            ListItem() { LoadingProgress().color(AppColor.Brand).width(28).height(28) }
          }
          if (this.notice !== '') {
            ListItem() { Text(this.notice).fontSize(13).fontColor('#FFCF99').width('100%') }
          }
        }
      }.width('76%').height('100%').scrollBar(BarState.Off)
        .contentStartOffset(this.viewportHeight * 0.18)
        .contentEndOffset(this.viewportHeight * 0.18)
      // 规则和音频提取仍由既有受限宿主执行；没有需要时不启动 Web 引擎。
      if (this.gate.needRuleBrowser) { WebBookFetchRuntimeHost()
        BookSourceAudioWebRuntimeHost()
        RuleSourceImportWebHost() }
    }.width('100%').height('100%').backgroundColor('#000000')
      .borderRadius('50%').clip(true)
      .onSizeChange((_oldSize: SizeOptions, size: SizeOptions): void => {
        this.viewportHeight = Number(size.height);
      })
  }
}
