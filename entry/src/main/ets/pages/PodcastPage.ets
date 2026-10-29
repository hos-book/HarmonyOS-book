import { AppStorageV2, LengthMetrics } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { PodcastDirectoryData, PodcastDirectoryEntry, PodcastEpisode, PodcastFeed, PodcastIdentity } from '../model/Podcast';
import { PlayerState, PLAYER_STATE_KEY } from '../model/PlayerState';
import { PodcastDirectoryService } from '../service/rulesource/podcast/PodcastDirectoryService';
import { PodcastFeedParser } from '../service/rulesource/podcast/PodcastFeedParser';
import { PodcastSourceAdapter } from '../service/rulesource/podcast/PodcastSourceAdapter';
import { PodcastRepository } from '../service/rulesource/podcast/PodcastRepository';
import { PodcastService } from '../service/rulesource/podcast/PodcastService';
import { AudioService } from '../service/AudioService';
import { AppColor, AppMaterial, AppTheme, HomeTheme } from '../theme/Theme';
import { WindowUtils } from '../utils/WindowUtils';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { HdsCompat } from '../utils/HdsCompat';
import { ListDataSource } from '../utils/ListDataSource';
import { ImmersiveCircleButton } from '../components/ImmersiveCircleButton';
import { ImmersiveActionButton } from '../components/ImmersiveActionButton';
import { HdsImmersiveTab } from '../components/HdsImmersiveTab';
import { PodcastGlassPanel, PodcastSearchSurface } from '../components/PodcastGlassSurface';

class PodcastCardRow {
  key: string = '';
  items: PodcastDirectoryEntry[] = [];
}

@ComponentV2
export struct PodcastPage {
  @Local visible: boolean = false;
  @Param navStack: NavPathStack = new NavPathStack();
  @Local playerState: PlayerState = AppStorageV2.connect(PlayerState, PLAYER_STATE_KEY, () => new PlayerState())!;
  @Local mode: number = 0;
  @Local directory: PodcastDirectoryData = new PodcastDirectoryData();
  @Local feeds: PodcastFeed[] = [];
  @Local selected: PodcastFeed = new PodcastFeed();
  @Local keyword: string = '';
  @Local platform: string = '';
  @Local picks: PodcastDirectoryEntry[] = [];
  @Local heroes: PodcastDirectoryEntry[] = [];
  @Local treasures: PodcastDirectoryEntry[] = [];
  @Local heroIndex: number = 0;
  private pickOffset: number = 0;
  private platformScroller: Scroller = new Scroller();
  @Local loading: boolean = false;
  @Local refreshing: boolean = false;
  @Local directoryError: boolean = false;
  @Local pageError: ResourceStr = '';
  @Local openingUrl: string = '';
  @Local playingId: string = '';
  @Local saving: boolean = false;
  @Local showAdd: boolean = false;
  @Local feedInput: string = '';
  @Local preview: PodcastFeed = new PodcastFeed();
  @Local previewBusy: boolean = false;
  @Local addError: ResourceStr = '';
  @Local resultCount: number = 0;
  @Local widthVp: number = 0;
  @Local topSafeVp: number = WindowUtils.getStatusBarHeightVp();
  @Local bottomSafeVp: number = WindowUtils.getBottomSafeVp();
  @Local statusBarContentColor: string = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  private statusBarColorListener: () => void = (): void => {
    this.statusBarContentColor = WindowUtils.isDarkMode() ? '#FFFFFFFF' : '#FF000000';
  };
  private ready: boolean = false;
  private alive: boolean = false;
  private requestId: number = 0;
  private previewRequest: number = 0;
  private scroller: Scroller = new Scroller();
  private popularRows: ListDataSource<PodcastCardRow> = new ListDataSource();
  private feedItems: ListDataSource<PodcastFeed> = new ListDataSource();
  private episodeItems: ListDataSource<PodcastEpisode> = new ListDataSource();
  private safeAreaChanged: (top: number, bottom: number) => void = (top: number, bottom: number): void => {
    this.topSafeVp = top;
    this.bottomSafeVp = bottom;
  };

  aboutToAppear(): void {
    this.alive = true;
    this.statusBarColorListener();
    WindowUtils.addReaderColorListener(this.statusBarColorListener);
    WindowUtils.addSafeAreaListener(this.safeAreaChanged);
    if (this.visible) this.load();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.requestId++;
    this.previewRequest++;
    WindowUtils.removeSafeAreaListener(this.safeAreaChanged);
    WindowUtils.removeReaderColorListener(this.statusBarColorListener);
  }

  @Monitor('visible')
  private visibilityChanged(): void {
    if (this.visible) this.load();
    else { this.showAdd = false; this.previewRequest++; this.previewBusy = false; }
  }

  private async load(): Promise<void> {
    if (this.loading) return;
    this.loading = true;
    this.pageError = '';
    try {
      const context = this.getUIContext().getHostContext();
      if (context === undefined) return;
      await PodcastRepository.init(context);
      this.ready = true;
      this.feeds = await PodcastService.subscriptions();
      this.updateLists();
      if (this.directory.featured.length === 0) await this.loadDirectory(false);
    } catch (_error) { this.pageError = $r('app.string.podcast_storage_failed'); }
    finally { this.loading = false; }
  }

  private async loadDirectory(refresh: boolean): Promise<void> {
    this.directoryError = false;
    try {
      const data = await PodcastDirectoryService.load(refresh);
      if (!this.alive) return;
      this.directory = data;
      this.updateLists();
    } catch (error) {
      console.warn(`[PodcastDirectory] ${String(error)}`);
      if (this.alive) this.directoryError = true;
    }
  }

  private updateLists(): void {
    const keyword = this.keyword.trim().toLocaleLowerCase();
    if (this.selected.feedUrl) {
      this.episodeItems.setItems(this.selected.episodes);
      this.resultCount = this.selected.episodes.length;
      return;
    }
    if (this.mode === 0) {
      const entries = this.directory.featured.filter((entry: PodcastDirectoryEntry): boolean =>
        (!this.platform || entry.platform === this.platform) &&
        (!keyword || (entry.title + ' ' + entry.author).toLocaleLowerCase().includes(keyword)));
      this.heroes = (this.directory.promoted.length > 0 ? this.directory.promoted : entries).slice(0, 4);
      this.treasures = entries.slice(0, 12);
      const candidates = this.directory.rightNow;
      const choices = candidates.length > 0 ? candidates : entries;
      this.picks = choices.slice(this.pickOffset % Math.max(1, choices.length), (this.pickOffset % Math.max(1, choices.length)) + 3);
      const columns = this.widthVp >= AdaptiveLayout.LARGE_WIDTH ? 4 : this.widthVp >= AdaptiveLayout.MEDIUM_WIDTH ? 3 : 2;
      const rows: PodcastCardRow[] = [];
      for (let index = 0; index < entries.length; index += columns) {
        const row = new PodcastCardRow();
        row.items = entries.slice(index, index + columns);
        row.key = row.items.map((entry: PodcastDirectoryEntry): string => entry.rssUrl).join('|');
        rows.push(row);
      }
      this.popularRows.setItems(rows);
      this.resultCount = entries.length;
    } else if (this.mode === 1) {
      const feeds = this.feeds.filter((feed: PodcastFeed): boolean => !keyword ||
        (feed.title + ' ' + feed.author).toLocaleLowerCase().includes(keyword));
      this.feedItems.setItems(feeds);
      this.resultCount = feeds.length;
    } else {
      const episodes: PodcastEpisode[] = [];
      for (const feed of this.feeds) {
        for (const episode of feed.episodes.slice(0, 50)) {
          if (!keyword || (episode.title + ' ' + episode.feedTitle).toLocaleLowerCase().includes(keyword)) episodes.push(episode);
        }
      }
      episodes.sort((left: PodcastEpisode, right: PodcastEpisode): number => right.publishedAt - left.publishedAt);
      this.episodeItems.setItems(episodes.slice(0, 300));
      this.resultCount = Math.min(episodes.length, 300);
    }
  }

  private back(): boolean {
    if (this.showAdd) { this.showAdd = false; this.previewRequest++; return true; }
    if (this.selected.feedUrl) {
      this.selected = new PodcastFeed();
      this.updateLists();
      this.scroller.scrollEdge(Edge.Top);
      return true;
    }
    return false;
  }

  private selectMode(mode: number): void {
    this.mode = mode;
    this.keyword = '';
    this.pageError = '';
    this.updateLists();
    this.scroller.scrollEdge(Edge.Top);
  }

  private subscribed(feedUrl: string): boolean { return this.feeds.some((feed: PodcastFeed): boolean => feed.feedUrl === feedUrl); }

  private async openEntry(entry: PodcastDirectoryEntry, play: boolean = false): Promise<void> {
    if (this.openingUrl) return;
    const request = ++this.requestId;
    this.openingUrl = entry.rssUrl;
    this.pageError = '';
    try {
      const cached = this.feeds.find((feed: PodcastFeed): boolean => feed.feedUrl === entry.rssUrl);
      const feed = cached ?? await PodcastSourceAdapter.load(entry.rssUrl);
      if (!this.alive || !this.visible || request !== this.requestId) return;
      this.openFeed(feed);
      if (play && feed.episodes.length > 0) {
        const episode = feed.episodes.find((item: PodcastEpisode): boolean => item.title === entry.latestEpisode.title) ?? feed.episodes[0];
        await this.playEpisode(episode);
      }
    } catch (error) { if (request === this.requestId) this.pageError = this.message(error instanceof Error ? error.message : ''); }
    finally { if (request === this.requestId) this.openingUrl = ''; }
  }

  private openFeed(feed: PodcastFeed): void {
    this.selected = feed;
    this.pageError = '';
    this.updateLists();
    this.scroller.scrollEdge(Edge.Top);
  }

  private async refresh(): Promise<void> {
    if (!this.ready || this.refreshing) return;
    this.refreshing = true;
    this.pageError = '';
    try {
      if (this.selected.feedUrl) {
        const feed = this.subscribed(this.selected.feedUrl) ? await PodcastService.refresh(this.selected.feedUrl)
          : await PodcastSourceAdapter.load(this.selected.feedUrl, true);
        this.selected = feed;
      } else if (this.mode === 0) {
        await this.loadDirectory(true);
      } else {
        let failures: number = 0;
        for (let start = 0; start < this.feeds.length && this.visible; start += 3) {
          await Promise.all(this.feeds.slice(start, start + 3).map(async (feed: PodcastFeed): Promise<void> => {
            try { await PodcastService.refresh(feed.feedUrl); } catch (_error) { failures++; }
          }));
        }
        if (failures > 0) this.pageError = $r('app.string.podcast_partial_refresh');
      }
      this.feeds = await PodcastService.subscriptions();
      this.updateLists();
    } catch (error) { this.pageError = this.message(error instanceof Error ? error.message : ''); }
    finally { this.refreshing = false; }
  }

  private openAdd(): void {
    this.feedInput = '';
    this.preview = new PodcastFeed();
    this.addError = '';
    this.previewBusy = false;
    this.previewRequest++;
    this.showAdd = true;
  }

  private async previewFeed(): Promise<void> {
    const address = PodcastFeedParser.httpUrl(this.feedInput);
    if (!address) { this.addError = $r('app.string.podcast_invalid_url'); return; }
    const request = ++this.previewRequest;
    this.previewBusy = true;
    this.addError = '';
    try {
      const feed = await PodcastSourceAdapter.load(address);
      if (request === this.previewRequest && this.showAdd) this.preview = feed;
    } catch (error) { if (request === this.previewRequest) this.addError = this.message(error instanceof Error ? error.message : ''); }
    finally { if (request === this.previewRequest) this.previewBusy = false; }
  }

  private async subscribe(feed: PodcastFeed, fromSheet: boolean = false): Promise<void> {
    if (this.saving || !this.ready) return;
    this.saving = true;
    try {
      await PodcastService.subscribe(feed);
      this.feeds = await PodcastService.subscriptions();
      if (fromSheet) { this.showAdd = false; this.openFeed(feed); }
      this.updateLists();
    } catch (error) {
      const message = this.message(error instanceof Error ? error.message : '');
      if (fromSheet) this.addError = message;
      else this.pageError = message;
    } finally { this.saving = false; }
  }

  private async unsubscribe(): Promise<void> {
    if (this.saving || this.refreshing) return;
    this.saving = true;
    try {
      await PodcastRepository.unsubscribe(this.selected.feedUrl);
      this.feeds = await PodcastService.subscriptions();
    } catch (_error) { this.pageError = $r('app.string.podcast_storage_failed'); }
    finally { this.saving = false; }
  }

  private async playEpisode(episode: PodcastEpisode): Promise<void> {
    if (this.playingId || this.saving) return;
    const feed = this.selected.feedUrl === episode.feedUrl ? this.selected :
      this.feeds.find((item: PodcastFeed): boolean => item.feedUrl === episode.feedUrl);
    if (feed === undefined) return;
    this.playingId = episode.id;
    this.pageError = '';
    try {
      if (!this.subscribed(feed.feedUrl)) {
        await PodcastService.subscribe(feed);
        this.feeds = await PodcastService.subscriptions();
      }
      const book = await PodcastService.playbackBook(feed);
      const chapterId = PodcastIdentity.chapterId(book.id, PodcastIdentity.episodeUrl(feed.feedUrl, episode.id));
      const chapter = book.chapters.find((item): boolean => item.id === chapterId);
      if (chapter === undefined) return;
      if (this.playerState.currentChapter?.id !== chapterId || !this.playerState.isPlaying) {
        await AudioService.getInstance().playChapterFromSavedProgress(book, chapter);
      }
      if (this.alive && this.visible) this.navStack.pushPathByName('player', book.id);
    } catch (error) { this.pageError = this.message(error instanceof Error ? error.message : ''); }
    finally { this.playingId = ''; }
  }

  private message(code: string): Resource {
    if (code.includes('podcast_feed_too_large')) return $r('app.string.podcast_feed_too_large');
    if (code.includes('podcast_timeout')) return $r('app.string.podcast_timeout');
    if (code.includes('podcast_invalid_url')) return $r('app.string.podcast_invalid_url');
    if (code.includes('podcast_invalid_feed')) return $r('app.string.podcast_invalid_feed');
    if (code.includes('podcast_no_audio')) return $r('app.string.podcast_no_audio');
    if (code.includes('podcast_source_conflict')) return $r('app.string.podcast_source_conflict');
    if (code.includes('podcast_source_missing')) return $r('app.string.podcast_source_missing');
    if (code.includes('podcast_subscription_failed')) return $r('app.string.podcast_subscription_failed');
    if (code.includes('podcast_storage_failed')) return $r('app.string.podcast_storage_failed');
    return $r('app.string.podcast_load_failed');
  }

  private date(timestamp: number): string {
    if (!timestamp || !Number.isFinite(timestamp)) return '';
    const value = new Date(timestamp);
    return `${value.getFullYear()}.${(value.getMonth() + 1).toString().padStart(2, '0')}.${value.getDate().toString().padStart(2, '0')}`;
  }

  private platformLabel(value: string): ResourceStr {
    if (value === 'XiaoYuZhou') return $r('app.string.podcast_platform_xyz');
    if (value === 'Ximalaya') return $r('app.string.podcast_platform_xm');
    if (value === 'Qingting') return $r('app.string.podcast_platform_qt');
    if (value === 'Lizhi') return $r('app.string.podcast_platform_lz');
    return value || $r('app.string.podcast_all');
  }

  private contentWidth(): number { return Math.min(960, Math.max(240, this.widthVp - 32)); }
  private listInset(): number { return Math.max(16, (this.widthVp - 960) / 2); }

  @Builder
  cover(address: string, size: number) {
    Stack() {
      SymbolGlyph($r('sys.symbol.waveform')).fontSize(size * 0.32).fontColor([AppColor.Brand])
      if (address) Image(address).width('100%').height('100%').objectFit(ImageFit.Cover)
    }.width(size).height(size).backgroundColor(AppColor.BrandSoft).borderRadius(size > 100 ? 18 : 10).clip(true)
  }

  @LocalBuilder
  titleBar() {
    Row({ space: 12 }) {
      ImmersiveCircleButton({ icon: $r('sys.symbol.chevron_left'), label: $r('app.string.podcast_back'),
        diameter: 36, iconSize: 19, onPress: (): void => { if (!this.back()) this.navStack.pop(); } })
      Text($r('app.string.podcast_title')).fontSize(27).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
      if (!this.selected.feedUrl) {
        ImmersiveActionButton({ label: this.mode === 0 ? $r('app.string.podcast_subscriptions') : $r('app.string.podcast_discover'),
          buttonHeight: 34, textSize: 12, onPress: (): void => this.selectMode(this.mode === 0 ? 1 : 0) }).width(84)
      } else {
        ImmersiveCircleButton({ icon: $r('sys.symbol.plus'), label: $r('app.string.podcast_add'),
          diameter: 36, iconSize: 20, onPress: (): void => this.openAdd() })
      }
    }.width('100%').height(58).padding({ left: this.listInset(), right: this.listInset() })
  }

  @Builder
  searchInput() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(17).fontColor([AppTheme.TextSecondary])
      TextInput({ text: this.keyword, placeholder: $r('app.string.podcast_search') })
        .layoutWeight(1).height(42).backgroundColor(Color.Transparent).padding(0).fontSize(14)
        .onChange((value: string): void => { this.keyword = value; this.updateLists(); })
    }.width('100%').padding({ left: 14, right: 14 })
  }

  @Builder
  searchRow() {
    Row({ space: 10 }) {
      PodcastSearchSurface({ surfaceWidth: this.contentWidth() - 52, content: (): void => this.searchInput() })
      ImmersiveCircleButton({ icon: $r('sys.symbol.plus'), label: $r('app.string.podcast_add'),
        diameter: 42, iconSize: 22, onPress: (): void => this.openAdd() })
    }.width('100%').padding({ bottom: 4 })
  }

  @Builder
  sectionTitle(title: Resource) {
    Text(title).fontSize(21).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).width('100%')
      .padding({ top: 10, bottom: 12 })
  }

  @Builder
  hero(entry: PodcastDirectoryEntry) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(entry.cover).width('100%').height('100%').objectFit(ImageFit.Cover)
      Column().width('100%').height('100%').linearGradient({ angle: 180,
        colors: [['#00000000', 0.15], ['#40000000', 0.5], ['#D9000000', 1]] })
      Column({ space: 8 }) {
        Text($r('app.string.podcast_hero_eyebrow')).fontSize(10).fontColor('#DFFFFFFF').letterSpacing(2)
        Text(entry.title).fontSize(25).fontWeight(FontWeight.Bold).fontColor(Color.White).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.author).fontSize(12).fontColor('#DFFFFFFF').maxLines(1)
      }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 20, right: 72, bottom: 32 })
      Row() {
        ImmersiveCircleButton({ icon: $r('sys.symbol.play_fill'), label: $r('app.string.podcast_play'),
          diameter: 36, iconSize: 17, onPress: (): void => { this.openEntry(entry, true); } })
      }.width('100%').justifyContent(FlexAlign.End).padding({ right: 16, bottom: 32 })
    }.width('100%').height('100%').borderRadius(24).clip(true)
      .onClick((): void => { this.openEntry(entry); })
  }

  @Builder
  recommendationRow(entry: PodcastDirectoryEntry, rank: number = 0) {
    Row({ space: 10 }) {
      if (rank > 0) Text(rank.toString()).fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor(rank < 4 ? AppColor.Brand : AppTheme.TextSecondary).width(16)
      this.cover(entry.latestEpisode.poster || entry.cover, rank > 0 ? 45 : 60)
      Column({ space: 6 }) {
        Text(entry.latestEpisode.title || entry.title).fontSize(rank > 0 ? 13 : 14).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TextPrimary).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(entry.title).fontSize(11).fontColor(AppTheme.TextSecondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.openingUrl === entry.rssUrl) LoadingProgress().width(32).height(32).color(AppColor.Brand)
      else ImmersiveCircleButton({ icon: $r('sys.symbol.play_fill'), label: $r('app.string.podcast_play'),
        diameter: 32, iconSize: 14, iconColor: AppColor.Brand, onPress: (): void => { this.openEntry(entry, true); } })
    }.width('100%').height(rank > 0 ? 78 : 90)
      .border({ width: { bottom: 0.5 }, color: AppTheme.Divider })
      .onClick((): void => { this.openEntry(entry); })
  }

  @Builder
  picksPanel() {
    Column() {
      Row() {
        Text($r('app.string.podcast_for_you')).fontSize(21).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).layoutWeight(1)
        ImmersiveCircleButton({ icon: $r('sys.symbol.arrow_clockwise'), label: $r('app.string.podcast_shuffle'),
          diameter: 32, iconSize: 18, onPress: (): void => { this.pickOffset += 3; this.updateLists(); } })
      }.width('100%').padding({ top: 2, bottom: 8 })
      ForEach(this.picks, (entry: PodcastDirectoryEntry) => { this.recommendationRow(entry) },
        (entry: PodcastDirectoryEntry): string => entry.rssUrl)
    }.padding(16).width('100%')
  }

  @Builder
  rankPanel(title: Resource, entries: PodcastDirectoryEntry[], episodes: boolean) {
    Column() {
      Text($r('app.string.podcast_top_list')).fontSize(10).fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).width('100%')
      Text(title).fontSize(23).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).width('100%').margin({ top: 3, bottom: 12 })
      ForEach(entries.slice(0, 5), (entry: PodcastDirectoryEntry, index: number) => {
        if (episodes) this.recommendationRow(entry, index + 1)
        else {
          Row({ space: 10 }) {
            Text((index + 1).toString()).fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColor.Brand).width(16)
            this.cover(entry.cover, 45)
            Column({ space: 6 }) {
              Text(entry.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary).maxLines(2)
              Text(entry.author).fontSize(11).fontColor(AppTheme.TextSecondary).maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([AppTheme.TextTertiary])
          }.height(78).width('100%').border({ width: { bottom: 0.5 }, color: AppTheme.Divider })
            .onClick((): void => { this.openEntry(entry); })
        }
      }, (entry: PodcastDirectoryEntry): string => entry.rssUrl)
    }.padding(18).width('100%')
  }

  @Builder
  treasure(entry: PodcastDirectoryEntry) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.cover(entry.cover, 138)
        ImmersiveCircleButton({ icon: $r('sys.symbol.plus'), label: $r('app.string.podcast_subscribe'),
          diameter: 28, iconSize: 17, onPress: (): void => { this.openEntry(entry); } }).margin(8)
      }
      Text(entry.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary).width('100%').maxLines(1)
      Text(entry.author).fontSize(11).fontColor(AppTheme.TextSecondary).width('100%').maxLines(1)
    }.width(138).alignItems(HorizontalAlign.Start).onClick((): void => { this.openEntry(entry); })
  }

  @Builder
  filterChip(value: string) {
    HdsImmersiveTab({ label: this.platformLabel(value), tabWidth: value === 'Ximalaya' ? 96 : 78,
      tabHeight: 36, selected: this.platform === value, scroller: this.platformScroller,
      onPress: (): void => {
        if (this.platform === value) return;
        this.platform = value;
        this.updateLists();
        this.scroller.scrollEdge(Edge.Top);
      } }).id('podcast-platform-' + (value || 'all'))
  }

  @Builder
  platformFilters() {
    List({ space: 8, scroller: this.platformScroller }) {
      ForEach(['', 'Apple', 'XiaoYuZhou', 'Ximalaya', 'Qingting', 'Lizhi'], (value: string) => {
        ListItem() { this.filterChip(value) }
      }, (value: string): string => value || 'all')
    }.listDirection(Axis.Horizontal).height(36).scrollBar(BarState.Off).width('100%')
      .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(24) }).renderGroup(false)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  feedRow(feed: PodcastFeed) {
    Row({ space: 14 }) {
      this.cover(feed.coverUrl, 64)
      Column({ space: 7 }) {
        Text(feed.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).maxLines(2)
        Text(feed.author).fontSize(12).fontColor(AppTheme.TextSecondary).maxLines(1)
        Text($r('app.string.podcast_episode_count', feed.episodes.length)).fontSize(11).fontColor(AppColor.Brand)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([AppTheme.TextTertiary])
    }.padding(16).width('100%').onClick((): void => this.openFeed(feed))
  }

  @Builder
  episodeRow(episode: PodcastEpisode) {
    Row({ space: 12 }) {
      if (!this.selected.feedUrl) this.cover(episode.coverUrl, 58)
      Column({ space: 8 }) {
        if (!this.selected.feedUrl) Text(episode.feedTitle).fontSize(11).fontColor(AppColor.Brand).maxLines(1)
        Text(episode.title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(AppTheme.TextPrimary).maxLines(3)
        Row({ space: 10 }) {
          Text(this.date(episode.publishedAt)).fontSize(11).fontColor(AppTheme.TextTertiary)
          if (episode.durationSeconds > 0) Text($r('app.string.podcast_minutes', Math.max(1, Math.round(episode.durationSeconds / 60))))
            .fontSize(11).fontColor(AppTheme.TextTertiary)
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      if (this.playingId === episode.id) LoadingProgress().width(36).height(36).color(AppColor.Brand)
      else ImmersiveCircleButton({ icon: $r('sys.symbol.play_fill'),
        label: this.subscribed(episode.feedUrl) ? $r('app.string.podcast_play') : $r('app.string.podcast_subscribe_play'),
        diameter: 36, iconSize: 15, iconColor: AppColor.Brand, onPress: (): void => { this.playEpisode(episode); } })
    }.width('100%').padding({ top: 16, bottom: 16 }).border({ width: { bottom: 0.5 }, color: AppTheme.Divider })
  }

  @Builder
  detailHeader() {
    Column({ space: 16 }) {
      this.cover(this.selected.coverUrl, 148)
      Text(this.selected.title).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).textAlign(TextAlign.Center)
      Text(this.selected.author).fontSize(13).fontColor(AppTheme.TextSecondary).textAlign(TextAlign.Center)
      ImmersiveActionButton({ label: this.subscribed(this.selected.feedUrl) ? $r('app.string.podcast_unsubscribe') : $r('app.string.podcast_subscribe'),
        buttonHeight: 42, textSize: 14,
        onPress: (): void => { if (this.subscribed(this.selected.feedUrl)) this.unsubscribe(); else this.subscribe(this.selected); } })
        .width(136).enabled(!this.saving && !this.refreshing)
      Text(this.selected.description).fontSize(13).fontColor(AppTheme.TextSecondary).lineHeight(22).maxLines(5).width('100%')
      Text($r('app.string.podcast_episode_count', this.selected.episodes.length)).fontSize(12).fontColor(AppColor.Brand)
    }.width('100%').padding(20)
  }

  @Builder
  emptySubscriptions() {
    Column({ space: 18 }) {
      SymbolGlyph($r('sys.symbol.waveform')).fontSize(54).fontColor([AppColor.Brand])
      Text($r('app.string.podcast_empty_title')).fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary)
      Text($r('app.string.podcast_empty_hint')).fontSize(13).fontColor(AppTheme.TextSecondary).textAlign(TextAlign.Center).lineHeight(22)
      ImmersiveActionButton({ label: $r('app.string.podcast_add'), buttonHeight: 44,
        onPress: (): void => this.openAdd() }).width(148)
    }.width('100%').padding({ top: 46, bottom: 38, left: 20, right: 20 })
  }

  @Builder
  addSheet() {
    Scroll() {
      Column({ space: 20 }) {
        Text($r('app.string.podcast_add')).fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).width('100%')
        Text($r('app.string.podcast_add_hint')).fontSize(14).fontColor(AppTheme.TextSecondary).lineHeight(22).width('100%')
        TextInput({ text: this.feedInput, placeholder: $r('app.string.podcast_url_placeholder') }).height(50)
          .type(InputType.URL).fontSize(14).backgroundColor(Color.Transparent)
          .attributeModifier(AppMaterial.modifier(AppMaterial.InteractiveClean)).borderRadius(25)
          .onChange((value: string): void => {
            this.feedInput = value; this.preview = new PodcastFeed(); this.previewRequest++; this.previewBusy = false;
          }).id('podcast-feed-input')
        if (this.addError !== '') Text(this.addError).fontSize(13).fontColor(AppColor.Brand).width('100%')
        if (this.preview.feedUrl) {
          Row({ space: 14 }) {
            this.cover(this.preview.coverUrl, 72)
            Column({ space: 8 }) {
              Text(this.preview.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(AppTheme.TextPrimary).maxLines(2)
              Text($r('app.string.podcast_episode_count', this.preview.episodes.length)).fontSize(12).fontColor(AppTheme.TextSecondary)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%')
          ImmersiveActionButton({ label: $r('app.string.podcast_subscribe'), buttonHeight: 48,
            onPress: (): void => { this.subscribe(this.preview, true); } }).enabled(!this.saving)
        } else {
          if (this.previewBusy) LoadingProgress().width(24).height(24).color(AppColor.Brand)
          ImmersiveActionButton({ label: this.previewBusy ? $r('app.string.podcast_loading') : $r('app.string.podcast_preview'),
            buttonHeight: 48, onPress: (): void => { this.previewFeed(); } }).enabled(!this.previewBusy).id('podcast-preview-button')
        }
      }.width('100%').padding(24)
    }.width('100%').scrollBar(BarState.Off).attributeModifier(AppMaterial.modifier(AppMaterial.Sheet))
  }

  build() {
    HdsNavDestination() {
      Refresh({ refreshing: $$this.refreshing }) {
        List({ space: 16, scroller: this.scroller }) {
          if (this.pageError !== '') ListItem() { Text(this.pageError).fontSize(13).fontColor(AppColor.Brand).padding(12) }
          if (this.selected.feedUrl) {
            ListItem() { PodcastGlassPanel({ content: (): void => this.detailHeader() }) }
            ListItem() { this.sectionTitle($r('app.string.podcast_updates')) }
            LazyForEach(this.episodeItems, (episode: PodcastEpisode) => {
              ListItem() { this.episodeRow(episode) }
            }, (episode: PodcastEpisode): string => episode.id)
          } else {
            ListItem() { this.searchRow() }
            if (this.mode === 0) {
              if (!this.keyword && !this.platform && this.heroes.length > 0) {
                ListItem() {
                  Swiper() {
                    ForEach(this.heroes, (entry: PodcastDirectoryEntry) => { this.hero(entry) },
                      (entry: PodcastDirectoryEntry): string => entry.rssUrl)
                  }.height(this.widthVp >= AdaptiveLayout.MEDIUM_WIDTH ? 300 : 226).width('100%')
                    .autoPlay(this.visible && !this.showAdd).interval(6000).loop(true)
                    .indicator(Indicator.dot().bottom(12).itemWidth(16).itemHeight(3).selectedItemWidth(28).selectedItemHeight(3)
                      .color('#70FFFFFF').selectedColor(Color.White)).borderRadius(24).clip(true)
                    .onChange((index: number): void => { this.heroIndex = index; })
                }
              }
              ListItem() { this.platformFilters() }
              if (this.loading && this.directory.featured.length === 0) {
                ListItem() { LoadingProgress().width(36).height(36).color(AppColor.Brand).margin({ top: 48, bottom: 48 }) }
              }
              if (this.directoryError) {
                ListItem() {
                  Column({ space: 16 }) {
                    Text($r('app.string.podcast_directory_failed')).fontSize(14).fontColor(AppTheme.TextSecondary).lineHeight(23)
                    ImmersiveActionButton({ label: $r('app.string.podcast_try_again'), onPress: (): void => { this.loadDirectory(true); } }).width(128)
                  }.width('100%').padding(24)
                }
              }
              if (!this.keyword && !this.platform) {
                if (this.picks.length > 0) ListItem() { PodcastGlassPanel({ content: (): void => this.picksPanel() }) }
                if (this.directory.rightNow.length > 0) {
                  ListItem() {
                    Scroll() {
                      Row({ space: 12 }) {
                        PodcastGlassPanel({ content: (): void => this.rankPanel($r('app.string.podcast_latest_chart'), this.directory.rightNow, true) })
                          .width(Math.min(330, this.contentWidth() - 24))
                        PodcastGlassPanel({ content: (): void => this.rankPanel($r('app.string.podcast_popular'), this.directory.featured, false) })
                          .width(Math.min(330, this.contentWidth() - 24))
                      }.alignItems(VerticalAlign.Top)
                    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
                  }
                }
                if (this.treasures.length > 0) {
                  ListItem() {
                    Column() {
                      this.sectionTitle($r('app.string.podcast_treasures'))
                      Scroll() {
                        Row({ space: 12 }) {
                          ForEach(this.treasures, (entry: PodcastDirectoryEntry) => { this.treasure(entry) },
                            (entry: PodcastDirectoryEntry): string => entry.rssUrl)
                        }
                      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
                    }
                  }
                }
              }
              ListItem() {
                Column() {
                  this.sectionTitle($r('app.string.podcast_more'))
                  Text($r('app.string.podcast_programme_count', this.resultCount)).fontSize(12)
                    .fontColor(AppTheme.TextSecondary).width('100%')
                }
              }
              LazyForEach(this.popularRows, (row: PodcastCardRow) => {
                ListItem() {
                  Column() {
                    ForEach(row.items, (entry: PodcastDirectoryEntry) => { this.recommendationRow(entry) },
                      (entry: PodcastDirectoryEntry): string => entry.rssUrl)
                  }.width('100%')
                }
              }, (row: PodcastCardRow): string => row.key)
              ListItem() { Text($r('app.string.podcast_directory_credit')).fontSize(10).fontColor(AppTheme.TextTertiary).width('100%').textAlign(TextAlign.Center).padding(18) }
            } else {
              ListItem() {
                Row({ space: 10 }) {
                  ImmersiveActionButton({ label: $r('app.string.podcast_subscriptions'), onPress: (): void => this.selectMode(1) }).layoutWeight(1)
                  ImmersiveActionButton({ label: $r('app.string.podcast_updates'), onPress: (): void => this.selectMode(2) }).layoutWeight(1)
                }.width('100%')
              }
              if (this.feeds.length === 0 && !this.loading) ListItem() { this.emptySubscriptions() }
              else if (this.mode === 1) {
                LazyForEach(this.feedItems, (feed: PodcastFeed) => {
                  ListItem() { PodcastGlassPanel({ content: (): void => this.feedRow(feed) }) }
                }, (feed: PodcastFeed): string => feed.feedUrl)
              } else {
                LazyForEach(this.episodeItems, (episode: PodcastEpisode) => {
                  ListItem() { this.episodeRow(episode) }
                }, (episode: PodcastEpisode): string => episode.id)
              }
            }
            if ((this.keyword || this.platform) && this.resultCount === 0 && !this.loading) {
              ListItem() { Text($r('app.string.podcast_no_results')).fontSize(14).fontColor(AppTheme.TextSecondary).padding(28) }
            }
          }
          ListItem() { Row().height(24 + this.bottomSafeVp) }
        }.width('100%').height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .contentStartOffset(this.topSafeVp + 66)
          .padding({ left: this.listInset(), right: this.listInset() })
      }.width('100%').height('100%').clip(false)
        .onRefreshing((): void => { this.refreshing = false; this.refresh(); })
    }.titleBar({
        avoidLayoutSafeArea: true,
        content: { stackBuilder: (): void => { this.titleBar(); } },
        style: {
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: HdsCompat.scrollEffect },
          originalStyle: { backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 16 } },
          scrollEffectStyle: { backgroundStyle: { backgroundColor: Color.Transparent, maskExtraHeight: 16 } },
          systemMaterialEffect: HdsCompat.material,
          thermoCtrl: true
        }
      }).titleMode(HdsNavDestinationTitleMode.MINI).hideBackButton(true)
      .bindToScrollable([this.scroller]).backgroundColor(HomeTheme.BgNeutral)
      .systemBarStyle({ statusBarContentColor: this.statusBarContentColor },
        { statusBarContentColor: this.statusBarContentColor })
      .onBackPressed((): boolean => this.back())
      .onShown((): void => { this.visible = true; })
      .onHidden((): void => { this.visible = false; })
      .renderGroup(false).systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
      .onSizeChange((_old: SizeOptions, value: SizeOptions): void => {
        if (typeof value.width === 'number' && value.width !== this.widthVp) { this.widthVp = value.width; this.updateLists(); }
      })
      .bindSheet($$this.showAdd, this.addSheet(), {
        height: SheetSize.FIT_CONTENT, detents: [SheetSize.FIT_CONTENT, '45%', SheetSize.LARGE],
        preferType: SheetType.BOTTOM, showClose: true, dragBar: true,
        backgroundColor: AppMaterial.SheetBackground, blurStyle: AppMaterial.SheetBlur, systemMaterial: AppMaterial.Sheet,
        onDisappear: (): void => { this.previewRequest++; this.previewBusy = false; }
      })
  }
}
