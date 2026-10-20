import { GeneralSettings } from '../model/GeneralSettings';
import { MembershipState } from '../model/MembershipState';
import { MembershipService } from '../service/MembershipService';
import { ImmersiveActionButton } from '../components/ImmersiveActionButton';
import { ImmersiveOptionTabs } from '../components/ImmersiveOptionTabs';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { Binding, UIUtils } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRadius, AppSpace, AppFont, AppColor } from '../theme/Theme';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { DataService } from '../service/DataService';
import { DownloadService } from '../service/DownloadService';
import { StatsService } from '../service/StatsService';
import { TextToSpeechService } from '../service/text/TextToSpeechService';
import { SearchCache } from '../utils/SearchCache';
import { WidgetUpdater } from '../service/WidgetUpdater';
import { WindowUtils } from '../utils/WindowUtils';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ReaderPage } from './ReaderPage';
import { RankingSettingsComponent } from '../components/RankingSettingsComponent';
import { AppearanceSettingsComponent } from '../components/AppearanceSettingsComponent';
import { CoverSuperResolutionService } from '../service/CoverSuperResolutionService';

interface ThemeOption {
  mode: number;
  label: string;
}

interface TabOption {
  idx: number;
  label: string;
}

interface FocusModeOption {
  mode: number;
  label: string;
}

const THEME_OPTIONS: ThemeOption[] = [
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET, label: '跟随系统' },
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT, label: '浅色模式' },
  { mode: ConfigurationConstant.ColorMode.COLOR_MODE_DARK, label: '深色模式' }
];

const TAB_OPTIONS: TabOption[] = [
  { idx: 0, label: '首页' },
  { idx: 1, label: '书架' },
  { idx: 2, label: '记录' },
  { idx: 3, label: '我的' }
];

const FOCUS_MODE_OPTIONS: FocusModeOption[] = [
  { mode: 0, label: '共享焦点' },
  { mode: 1, label: '独立焦点' }
];

interface PreloadOption {
  count: number;
  label: string;
}

const PRELOAD_OPTIONS: PreloadOption[] = [
  { count: 0, label: '不预加载' },
  { count: 1, label: '1章' },
  { count: 5, label: '5章' },
  { count: 10, label: '10章' },
  { count: -1, label: '' }
];

const ROW_INDENT: number = AppSpace.Md;
const SEARCH_CONCURRENCY_OPTIONS: number[] = [3, 6, 9, 12];

@ComponentV2
export struct SettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local savingGeneral: boolean = false;
  @Local currentMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @Local selectedThemeIndex: number = 0;
  @Local defaultTab: number = 0;
  @Local autoPlayOnLaunch: boolean = false;
  @Local isSavingAutoPlayOnLaunch: boolean = false;
  @Local focusMode: number = 0;
  @Local isSavingFocusMode: boolean = false;
  @Local autoResume: boolean = true;
  @Local defaultPlaybackSpeed: number = 1;
  @Local defaultPlaybackSpeedDraft: number = 1;
  @Local isSavingDefaultPlaybackSpeed: boolean = false;
  @Local preloadCount: number = 1;
  @Local preloadDraft: string = '1';
  @Local preloadCustom: boolean = false;
  @Local membership: MembershipState = MembershipState.current;
  @Local membershipService: MembershipService = MembershipService.instance;
  @Local checkingSearchMembership: boolean = false;
  @Local searchConcurrency: number = 3;
  @Local searchConcurrencyDraft: string = '3';
  @Local searchConcurrencyCustom: boolean = false;
  @Local isSavingSearchConcurrency: boolean = false;
  @Local isSavingPreload: boolean = false;
  @Local isClearingListeningTime: boolean = false;
  @Local isLoaded: boolean = false;
  @Local preferencesLoadFailed: boolean = false;
  @Local searchConcurrencyLoading: boolean = true;
  @Local searchConcurrencyLoadFailed: boolean = false;
  private alive: boolean = false;
  private preferencesLoadSerial: number = 0;
  @Local coverSuperResolution: boolean = false;
  @Local isSavingCoverSuperResolution: boolean = false;
  @Local isClearingCache: boolean = false;
  @Local isClearingBookshelf: boolean = false;
  @Local isClearingDownloads: boolean = false;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  private viewportUpdateTimerId: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.loadPrefs();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.preferencesLoadSerial++;
    this.cancelViewportUpdateTimer();
  }

  private cancelViewportUpdateTimer(): void {
    if (this.viewportUpdateTimerId !== -1) {
      clearTimeout(this.viewportUpdateTimerId);
      this.viewportUpdateTimerId = -1;
    }
  }

  private handleViewportSizeChange(newValue: SizeOptions): void {
    if (typeof newValue.width !== 'number' || typeof newValue.height !== 'number') return;
    const width: number = newValue.width;
    const height: number = newValue.height;
    if (Math.abs(width - this.viewportWidth) < 1 && Math.abs(height - this.viewportHeight) < 1) return;
    this.cancelViewportUpdateTimer();
    this.viewportUpdateTimerId = setTimeout(() => {
      this.viewportUpdateTimerId = -1;
      this.viewportWidth = width;
      this.viewportHeight = height;
    }, 0);
  }

  private isCompactLayout(): boolean {
    return AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight);
  }

  private horizontalPadding(): number {
    return AdaptiveLayout.isCompact(this.viewportWidth, this.viewportHeight) ? AppSpace.Sm : AppSpace.Md;
  }

  private async loadPrefs(): Promise<void> {
    const serial = ++this.preferencesLoadSerial;
    this.isLoaded = false;
    this.preferencesLoadFailed = false;
    // 搜索并发需要联网核验会员，只更新自身控件，不阻塞本地设置首屏。
    this.loadSearchConcurrency(serial);
    try {
      const mode = await PreferenceService.getColorMode();
      const defaultTab = await PreferenceService.getDefaultTab();
      const autoPlay = await PreferenceService.getAutoPlayOnLaunch();
      const coverResolution = await PreferenceService.getCoverSuperResolution();
      const focusMode = await PreferenceService.getAudioInterruptMode();
      const autoResume = await PreferenceService.getAudioAutoResume();
      const defaultPlaybackSpeed = await PreferenceService.getDefaultPlaybackSpeed();
      const preloadCount = await PreferenceService.getPreloadChapters();
      if (!this.alive || serial !== this.preferencesLoadSerial) return;
      this.currentMode = mode;
      this.selectedThemeIndex = Math.max(0, THEME_OPTIONS.findIndex((opt: ThemeOption) => opt.mode === mode));
      this.defaultTab = defaultTab;
      this.autoPlayOnLaunch = autoPlay;
      this.coverSuperResolution = coverResolution;
      this.focusMode = focusMode;
      this.autoResume = autoResume;
      this.defaultPlaybackSpeed = defaultPlaybackSpeed;
      this.defaultPlaybackSpeedDraft = defaultPlaybackSpeed;
      this.preloadCount = preloadCount;
      this.preloadDraft = preloadCount.toString();
      this.preloadCustom = !PRELOAD_OPTIONS.some((opt: PreloadOption): boolean => opt.count === preloadCount);
      this.isLoaded = true;
    } catch (_error) {
      if (this.alive && serial === this.preferencesLoadSerial) this.preferencesLoadFailed = true;
    }
  }

  private async loadSearchConcurrency(serial: number): Promise<void> {
    this.searchConcurrencyLoading = true;
    this.searchConcurrencyLoadFailed = false;
    try {
      const count = await PreferenceService.getSearchConcurrency();
      if (!this.alive || serial !== this.preferencesLoadSerial) return;
      if (!this.membership.hasAccess && !this.membership.confirmedInactive) {
        this.searchConcurrencyLoadFailed = true;
        return;
      }
      this.searchConcurrency = this.membership.hasAccess ? count : 3;
      this.searchConcurrencyDraft = this.searchConcurrency.toString();
      this.searchConcurrencyCustom = !SEARCH_CONCURRENCY_OPTIONS.includes(this.searchConcurrency);
    } catch (_error) {
      if (this.alive && serial === this.preferencesLoadSerial) this.searchConcurrencyLoadFailed = true;
    } finally {
      if (this.alive && serial === this.preferencesLoadSerial) this.searchConcurrencyLoading = false;
    }
  }

  private async setDefaultTab(idx: number): Promise<void> {
    this.defaultTab = idx;
    await PreferenceService.setDefaultTab(idx);
  }

  private async setCoverSuperResolution(enabled: boolean): Promise<void> {
    if (this.isSavingCoverSuperResolution || !CoverSuperResolutionService.supported() ||
      this.coverSuperResolution === enabled) return;
    const previous = this.coverSuperResolution;
    this.isSavingCoverSuperResolution = true;
    this.coverSuperResolution = enabled;
    try {
      await PreferenceService.setCoverSuperResolution(enabled);
    } catch (_error) {
      this.coverSuperResolution = previous;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingCoverSuperResolution = false;
    }
  }

  private async setAutoPlayOnLaunch(enabled: boolean): Promise<void> {
    if (this.isSavingAutoPlayOnLaunch || this.autoPlayOnLaunch === enabled) return;
    const previous = this.autoPlayOnLaunch;
    this.isSavingAutoPlayOnLaunch = true;
    this.autoPlayOnLaunch = enabled;
    try {
      await PreferenceService.setAutoPlayOnLaunch(enabled);
    } catch (error) {
      this.autoPlayOnLaunch = previous;
      hilog.warn(0xFF00, 'SettingsPage', 'Save auto play on launch failed: %{public}s', String(error));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingAutoPlayOnLaunch = false;
    }
  }

  private async setFocusMode(mode: number): Promise<void> {
    if (!this.isLoaded || this.isSavingFocusMode || this.focusMode === mode) return;
    const previous = this.focusMode;
    this.isSavingFocusMode = true;
    this.focusMode = mode;
    try {
      await AudioService.getInstance().setInterruptMode(mode);
    } catch (error) {
      this.focusMode = previous;
      hilog.warn(0xFF00, 'SettingsPage', 'Save audio focus failed: %{public}s', String(error));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingFocusMode = false;
    }
  }

  private async setAutoResume(enabled: boolean): Promise<void> {
    this.autoResume = enabled;
    await AudioService.getInstance().setAutoResume(enabled);
  }

  private async setDefaultPlaybackSpeed(speed: number): Promise<void> {
    if (!this.isLoaded || this.isSavingDefaultPlaybackSpeed) return;
    const rate = PreferenceService.normalizeDefaultPlaybackSpeed(speed);
    if (rate === this.defaultPlaybackSpeed) return;
    this.isSavingDefaultPlaybackSpeed = true;
    try {
      await PreferenceService.setDefaultPlaybackSpeed(rate);
      this.defaultPlaybackSpeed = rate;
      this.defaultPlaybackSpeedDraft = rate;
    } catch (_error) {
      this.defaultPlaybackSpeedDraft = this.defaultPlaybackSpeed;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingDefaultPlaybackSpeed = false;
    }
  }

  private submitPreload(): void {
    const count = Number(this.preloadDraft);
    if (!/^[0-9]+$/.test(this.preloadDraft) || !Number.isInteger(count) || count < 0 || count > 50) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_preload_range') });
      return;
    }
    this.setPreloadCount(count, true);
  }

  private async setPreloadCount(count: number, custom: boolean = false): Promise<void> {
    if (this.isSavingPreload) return;
    this.isSavingPreload = true;
    try {
      await PreferenceService.setPreloadChapters(count);
      ChapterCacheService.getInstance().setPreloadCount(count);
      AudioService.getInstance().refreshPreload();
      this.preloadCount = count;
      this.preloadDraft = count.toString();
      this.preloadCustom = custom;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_preload_saved', count) });
    } catch (error) {
      this.preloadDraft = this.preloadCount.toString();
      hilog.warn(0xFF00, 'SettingsPage', 'Save preload failed: %{public}s', String(error));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingPreload = false;
    }
  }

  private async requireSearchMembership(): Promise<boolean> {
    if (this.checkingSearchMembership || this.searchConcurrencyLoading || this.searchConcurrencyLoadFailed) return false;
    if (!MembershipState.featureEnabled) return this.alive;
    this.checkingSearchMembership = true;
    try {
      const entitled = await this.membershipService.hasCurrentEntitlement();
      if (!this.alive) return false;
      if (entitled) return true;
      this.showSearchMembershipUnavailable();
      return false;
    } finally {
      this.checkingSearchMembership = false;
    }
  }

  private showSearchMembershipUnavailable(): void {
    if (this.membership.confirmedInactive && !this.membershipService.busy) {
      this.onSearchMembershipChanged();
      this.navStack.pushPathByName('membershipSubscription', '');
    } else {
      this.getUIContext().getPromptAction().showToast({ message: this.membershipService.message });
    }
  }

  @Monitor('membership.confirmedInactive')
  private onSearchMembershipChanged(): void {
    if (this.membership.confirmedInactive && !this.membership.hasAccess) {
      this.searchConcurrency = 3;
      this.searchConcurrencyDraft = '3';
      this.searchConcurrencyCustom = false;
    }
  }

  private async submitSearchConcurrency(): Promise<void> {
    if (!await this.requireSearchMembership()) return;
    const count = Number(this.searchConcurrencyDraft);
    if (!new RegExp('^[0-9]+$').test(this.searchConcurrencyDraft) ||
      !Number.isInteger(count) || count < 1 || count > 12) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_search_concurrency_range') });
      return;
    }
    this.setSearchConcurrency(count, true);
  }

  private async chooseSearchConcurrency(index: number): Promise<void> {
    if (index === 4) {
      if (await this.requireSearchMembership()) this.searchConcurrencyCustom = true;
    } else {
      await this.setSearchConcurrency(SEARCH_CONCURRENCY_OPTIONS[index], false);
    }
  }

  private async setSearchConcurrency(count: number, custom: boolean): Promise<void> {
    if (this.isSavingSearchConcurrency || !await this.requireSearchMembership()) return;
    const previous = this.searchConcurrency;
    const previousCustom = this.searchConcurrencyCustom;
    this.isSavingSearchConcurrency = true;
    try {
      await PreferenceService.setSearchConcurrency(count);
      if (!this.alive) return;
      this.searchConcurrency = count;
      this.searchConcurrencyDraft = count.toString();
      this.searchConcurrencyCustom = custom;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_search_concurrency_saved', count) });
    } catch (error) {
      if (!this.alive) return;
      if (!this.membership.hasAccess) {
        this.showSearchMembershipUnavailable();
        return;
      }
      this.searchConcurrencyDraft = previous.toString();
      this.searchConcurrencyCustom = previousCustom;
      hilog.warn(0xFF00, 'SettingsPage', 'Save search concurrency failed: %{public}s', String(error));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally {
      this.isSavingSearchConcurrency = false;
    }
  }

  private async clearCache(): Promise<void> {
    if (this.isClearingCache) return;
    this.isClearingCache = true;
    try {
      const result = await ChapterCacheService.getInstance().clearAllCache();
      const msg = result.failed > 0
        ? `已清除 ${result.deleted} 项，${result.failed} 项失败`
        : `已清除 ${result.deleted} 项`;
      try { this.getUIContext().getPromptAction().showToast({ message: msg }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingCache = false;
    }
  }

  private showAudioStorageCleanup(): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: $r('app.string.settings_audio_storage_cleanup'),
      message: $r('app.string.settings_audio_storage_cleanup_message'),
      buttons: [
        { text: $r('app.string.common_cancel'), color: '#8F8F8F' },
        { text: $r('app.string.settings_clear_preload_cache'), color: AppColor.Brand },
        { text: $r('app.string.settings_clear_downloads'), color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.clearCache();
      } else if (result.index === 2) {
        this.confirmClearDownloads();
      }
    }).catch(() => { /* ignore */ });
  }

  private confirmClearBookshelf(): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '清空在线收藏与播放记录',
      message: '将清除在线收藏、播放记录与进度。本地导入、下载内容和跳过头尾设置会保留。此操作不可恢复,确定吗?',
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '清空', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) this.doClearBookshelf();
    }).catch(() => { /* ignore */ });
  }

  private confirmResetListeningTime(): void {
    if (this.isClearingListeningTime) return;
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.settings_reset_listening_title'),
      message: $r('app.string.settings_reset_listening_confirm'),
      buttons: [
        { text: $r('app.string.settings_reset_listening_cancel'), color: '#8F8F8F' },
        { text: $r('app.string.settings_reset_listening_action'), color: '#FF4444' }
      ]
    }).then((result): void => {
      if (result.index === 1) this.resetListeningTime();
    }).catch((): void => {});
  }

  private async resetListeningTime(): Promise<void> {
    if (this.isClearingListeningTime) return;
    this.isClearingListeningTime = true;
    try {
      TextToSpeechService.getInstance().pause();
      await AudioService.getInstance().pause();
      await StatsService.resetListeningTime();
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_reset_listening_done') });
    } catch (error) {
      hilog.warn(0xFF00, 'SettingsPage', 'Reset listening time failed: %{public}s', String(error));
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_reset_listening_failed') });
    } finally { this.isClearingListeningTime = false; }
  }

  private async doClearBookshelf(): Promise<void> {
    if (this.isClearingBookshelf) return;
    this.isClearingBookshelf = true;
    try {
      const audioService = AudioService.getInstance();
      await audioService.stopForClear();
      await PreferenceService.clearOnlineFavoritesAndHistory();
      await DataService.clearCachedBooks();
      await ChapterCacheService.getInstance().wipeDiskCaches();
      await StatsService.clearBookStats();
      SearchCache.clear();
      audioService.unfreezePersist();
      try { this.getUIContext().getPromptAction().showToast({ message: '在线收藏与播放记录已清空' }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      AudioService.getInstance().unfreezePersist();
      try { this.getUIContext().getPromptAction().showToast({ message: '清空失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingBookshelf = false;
    }
  }

  private async setColorMode(mode: number): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const appCtx = ctx.getApplicationContext();
    try {
      appCtx.setColorMode(mode);
    } catch (_e) { /* system API may throw on invalid context */ }
    this.currentMode = mode;
    const newIndex = THEME_OPTIONS.findIndex((opt: ThemeOption) => opt.mode === mode);
    this.selectedThemeIndex = newIndex !== -1 ? newIndex : 0;
    await PreferenceService.setColorMode(mode);

    // 延迟更新状态栏，让主题切换完成后再应用
    setTimeout(() => {
      WindowUtils.updateColorMode(mode);
    }, 100);
  }

  private confirmClearDownloads(): void {
    const prompt = this.getUIContext().getPromptAction();
    prompt.showDialog({
      title: '清除下载内容',
      message: '将删除所有整本/单章离线下载音频，不会删除书架、收藏和播放记录。确定清除吗？',
      buttons: [
        { text: '取消', color: '#8F8F8F' },
        { text: '清除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) this.doClearDownloads();
    }).catch(() => { /* ignore */ });
  }

  private async doClearDownloads(): Promise<void> {
    if (this.isClearingDownloads) return;
    this.isClearingDownloads = true;
    try {
      await DownloadService.getInstance().clearAllDownloads();
      try { this.getUIContext().getPromptAction().showToast({ message: '下载内容已清除' }); } catch (_e) { /* ignore */ }
    } catch (_e) {
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败，请重试' }); } catch (_e2) { /* ignore */ }
    } finally {
      this.isClearingDownloads = false;
    }
  }

  private clearEpubCache(): void {
    try {
      ReaderPage.clearEpubCache();
      hilog.info(0xFF00, 'SettingsPage', 'epub handler cache cleared');
      try { this.getUIContext().getPromptAction().showToast({ message: '电子书缓存已清除' }); } catch (_e) { /* ignore */ }
    } catch (e) {
      hilog.warn(0xFF00, 'SettingsPage', 'clear epub cache failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败' }); } catch (_e) { /* ignore */ }
    }
  }

  private clearTextContentCache(): void {
    try {
      ReaderPage.clearTextContentCache();
      hilog.info(0xFF00, 'SettingsPage', 'text content cache cleared');
      try { this.getUIContext().getPromptAction().showToast({ message: '在线文本缓存已清除' }); } catch (_e) { /* ignore */ }
    } catch (e) {
      hilog.warn(0xFF00, 'SettingsPage', 'clear text content cache failed: %{public}s',
        e instanceof Error ? e.message : String(e));
      try { this.getUIContext().getPromptAction().showToast({ message: '清除失败' }); } catch (_e) { /* ignore */ }
    }
  }

  build() {
    Column() {
      this.buildHeader()

      if (!this.isLoaded) {
        Row({ space: AppSpace.Sm }) {
          if (!this.preferencesLoadFailed) {
            LoadingProgress().width(20).height(20).color(AppColor.Brand)
          }
          Text(this.preferencesLoadFailed ? $r('app.string.settings_load_failed') : $r('app.string.settings_loading'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          if (this.preferencesLoadFailed) {
            Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(AppColor.Brand).onClick((): void => { this.loadPrefs(); })
          }
        }.width('100%').padding({ left: AppSpace.Md, right: AppSpace.Md, bottom: AppSpace.Sm })
      }
      Scroll() {
        GridRow({ columns: this.viewportWidth >= AdaptiveLayout.LARGE_WIDTH ? 2 : 1,
          gutter: AdaptiveLayout.sectionSpacing(this.viewportWidth, this.viewportHeight) }) {
          GridCol() { this.buildAppearanceGroup() }.enabled(this.isLoaded)
          GridCol() { this.buildLaunchGroup() }.enabled(this.isLoaded)
          GridCol() { this.buildPlaybackGroup() }.enabled(this.isLoaded)
          GridCol() { this.buildSearchGroup() }
          GridCol() { this.buildGeneralGroup() }.enabled(this.isLoaded)
          GridCol() { RankingSettingsComponent() }
        }
        .width('100%')
        .padding({
          left: this.horizontalPadding(),
          right: this.horizontalPadding(),
          top: this.isCompactLayout() ? 0 : AppSpace.Sm,
          bottom: AppSpace.Xl
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.background_secondary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onSizeChange((_oldValue: SizeOptions, newValue: SizeOptions) => {
      this.handleViewportSizeChange(newValue);
    })
  }

  private async setAdaptiveHandedness(enabled: boolean): Promise<void> {
    if (this.savingGeneral) return;
    this.savingGeneral = true;
    try { await PreferenceService.setAdaptiveHandedness(enabled); }
    catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally { this.savingGeneral = false; }
  }

  private async setShowShelfSource(enabled: boolean): Promise<void> {
    if (this.savingGeneral) return;
    const previous: boolean = this.generalSettings.showShelfSource;
    if (previous === enabled) return;
    this.savingGeneral = true;
    this.generalSettings.showShelfSource = enabled;
    try {
      await PreferenceService.setShowShelfSource(enabled);
    } catch (_error) {
      this.generalSettings.showShelfSource = previous;
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.tts_save_error') });
    } finally { this.savingGeneral = false; }
  }

  @Builder
  buildGeneralGroup() {
    Column() {
      this.buildGroupTitle($r('app.string.shelf_title'))
      Column() {
        this.buildSwitchItem(
          $r('app.string.settings_shelf_source'),
          '',
          UIUtils.makeBinding<boolean>(() => this.generalSettings.showShelfSource),
          (enabled: boolean): void => { this.setShowShelfSource(enabled); },
          UIUtils.makeBinding<boolean>(() => this.isLoaded && !this.savingGeneral)
        )
      }.width('100%')
        .backgroundColor($r('sys.color.comp_background_primary')).borderRadius(AppRadius.Lg)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([$r('sys.color.font_primary')])
        .onClick(() => this.navStack.pop())
      Text('设置')
        .fontSize(AppFont.TitleL)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Bold)
        .margin({ left: AppSpace.Sm })
    }
    .width('100%')
    .padding({
      top: WindowUtils.getStatusBarHeightVp() + AppSpace.Sm,
      left: AppSpace.Md,
      right: AppSpace.Md,
      bottom: this.isCompactLayout() ? AppSpace.Sm : AppSpace.Md
    })
  }

  @Builder
  buildGroupTitle(title: ResourceStr) {
    Text(title)
      .fontSize(AppFont.Body)
      .fontColor($r('sys.color.font_tertiary'))
      .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.comp_divider'))
      .margin({ left: ROW_INDENT })
  }

  @Builder
  buildAppearanceGroup() {
    Column() {
      this.buildGroupTitle('外观')

      Column() {
        Row({ space: AppSpace.Sm }) {
          Column({ space: 2 }) {
            Text('主题模式')
              .fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          ImmersiveOptionTabs({
            labels: THEME_OPTIONS.map((opt: ThemeOption): ResourceStr => opt.label),
            selected: this.selectedThemeIndex,
            onSelect: (index: number): void => { this.setColorMode(THEME_OPTIONS[index].mode); }
          })

        }
        .width('100%')
        .padding({
          left: ROW_INDENT,
          right: AppSpace.Xs,
          top: AppSpace.Sm,
          bottom: AppSpace.Sm
        })
        .constraintSize({ minHeight: 56 })

        AppearanceSettingsComponent()
        this.buildDivider()
        this.buildSwitchItem(
          $r('app.string.settings_adaptive_handedness'),
          $r('app.string.settings_adaptive_handedness_desc'),
          UIUtils.makeBinding<boolean>(() => this.generalSettings.adaptiveHandedness),
          (enabled: boolean): void => { this.setAdaptiveHandedness(enabled); },
          UIUtils.makeBinding<boolean>(() => this.isLoaded && !this.savingGeneral)
        )
        this.buildDivider()
        this.buildSwitchItem(
          $r('app.string.settings_cover_super_resolution'),
          CoverSuperResolutionService.supported() ? $r('app.string.settings_cover_super_resolution_desc')
            : $r('app.string.settings_cover_super_resolution_unavailable'),
          UIUtils.makeBinding<boolean>(() => this.coverSuperResolution),
          (enabled: boolean): void => { this.setCoverSuperResolution(enabled); },
          UIUtils.makeBinding<boolean>(() =>
            this.isLoaded && !this.isSavingCoverSuperResolution && CoverSuperResolutionService.supported())
        )
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildLaunchGroup() {
    Column() {
      this.buildGroupTitle('启动')

      Column() {
        this.buildSelectItem(
          '默认打开',
          UIUtils.makeBinding<string>(() => ''),
          TAB_OPTIONS.map((opt: TabOption): SelectOption => { return { value: opt.label }; }),
          UIUtils.makeBinding<number>(() => this.defaultTab),
          (index: number) => this.setDefaultTab(index),
          UIUtils.makeBinding<boolean>(() => this.isLoaded)
        )

        this.buildDivider()

        this.buildSwitchItem(
          $r('app.string.settings_auto_play_on_launch'),
          $r('app.string.settings_auto_play_on_launch_desc'),
          UIUtils.makeBinding<boolean>(() => this.autoPlayOnLaunch),
          (isOn: boolean) => this.setAutoPlayOnLaunch(isOn),
          UIUtils.makeBinding<boolean>(() => !this.isSavingAutoPlayOnLaunch)
        )
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildPlaybackGroup() {
    Column() {
      this.buildGroupTitle('播放')

      Column() {
        Column({ space: AppSpace.Sm }) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.settings_default_playback_speed')).fontSize(AppFont.BodyL)
              .fontColor($r('sys.color.font_primary')).layoutWeight(1)
            Text(this.defaultPlaybackSpeedDraft.toFixed(2) + 'x')
              .fontSize(AppFont.BodyL).fontColor(AppColor.Brand)
          }.width('100%')
          Text($r('app.string.settings_default_playback_speed_desc'))
            .fontSize(AppFont.Caption).fontColor($r('sys.color.font_secondary')).width('100%')
          Slider({ value: this.defaultPlaybackSpeedDraft, min: 0.5, max: 3, step: 0.05 })
            .selectedColor(AppColor.Brand).width('100%')
            .accessibilityText($r('app.string.settings_default_playback_speed'))
            .onChange((value: number, mode: SliderChangeMode): void => {
              this.defaultPlaybackSpeedDraft = PreferenceService.normalizeDefaultPlaybackSpeed(value);
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                this.setDefaultPlaybackSpeed(this.defaultPlaybackSpeedDraft);
              }
            })
        }.width('100%').padding(ROW_INDENT)
          .enabled(this.isLoaded && !this.isSavingDefaultPlaybackSpeed)

        this.buildDivider()

        this.buildSelectItem(
          '音频焦点',
          UIUtils.makeBinding<string>(() => this.focusMode === 1 ? '与本应用其他音频独立计算焦点' : '与系统其他音频互斥（推荐）'),
          FOCUS_MODE_OPTIONS.map((opt: FocusModeOption): SelectOption => { return { value: opt.label }; }),
          UIUtils.makeBinding<number>(() => FOCUS_MODE_OPTIONS.findIndex((opt: FocusModeOption) => opt.mode === this.focusMode)),
          (index: number) => this.setFocusMode(FOCUS_MODE_OPTIONS[index].mode),
          UIUtils.makeBinding<boolean>(() => this.isLoaded && !this.isSavingFocusMode)
        )

        this.buildDivider()

        this.buildSwitchItem(
          '失焦后自动恢复',
          '被来电、导航、视频打断后自动续播',
          UIUtils.makeBinding<boolean>(() => this.autoResume),
          (isOn: boolean) => this.setAutoResume(isOn),
          UIUtils.makeBinding<boolean>(() => this.isLoaded)
        )

        this.buildDivider()

        Column({ space: AppSpace.Sm }) {
          Text($r('app.string.settings_preload_custom')).fontSize(AppFont.BodyL)
            .fontColor($r('sys.color.font_primary')).width('100%')
          Row({ space: AppSpace.Sm }) {
          ImmersiveOptionTabs({
            labels: PRELOAD_OPTIONS.map((opt: PreloadOption): ResourceStr => opt.count < 0 ? $r('app.string.settings_preload_custom_tab') : opt.label),
            fillWidth: true,
            selected: this.preloadCustom ? 4 : PRELOAD_OPTIONS.findIndex((opt: PreloadOption): boolean => opt.count === this.preloadCount),
            onSelect: (index: number): void => {
              if (index === 4) this.preloadCustom = true;
              else this.setPreloadCount(PRELOAD_OPTIONS[index].count);
            }
          }).layoutWeight(1.5)
            TextInput({ text: this.preloadDraft, placeholder: $r('app.string.settings_preload_input_hint') })
              .type(InputType.Number).maxLength(2).layoutWeight(1).height(40)
              .onChange((value: string): void => { this.preloadDraft = value; })
              .onSubmit((): void => this.submitPreload())
            ImmersiveActionButton({ onPress: (): void => this.submitPreload() }).layoutWeight(0.8)
          }.width('100%').alignItems(VerticalAlign.Center)
          .enabled(!this.isSavingPreload)
        }.width('100%').padding(ROW_INDENT)

        this.buildDivider()

        this.buildActionItem(
          '清除电子书缓存',
          '清除已解析的 EPUB 电子书缓存，下次打开时重新加载',
          () => this.clearEpubCache(),
          false
        )

        this.buildDivider()

        this.buildActionItem(
          '清除在线文本缓存',
          '清除已缓存的在线章节内容，下次阅读时重新请求',
          () => this.clearTextContentCache(),
          false
        )

        this.buildDivider()

        this.buildActionItem(
          $r('app.string.settings_audio_storage_cleanup'),
          $r('app.string.settings_audio_storage_cleanup_desc'),
          () => this.showAudioStorageCleanup(),
          this.isClearingCache || this.isClearingDownloads
        )

        this.buildDivider()

        this.buildActionItem('清空在线收藏与播放记录', '清除在线收藏 / 缓存书 / 播放记录，保留导入和下载', () => this.confirmClearBookshelf(), this.isClearingBookshelf)
        this.buildDivider()
        this.buildActionItem($r('app.string.settings_reset_listening_title'),
          $r('app.string.settings_reset_listening_subtitle'),
          (): void => this.confirmResetListeningTime(), this.isClearingListeningTime)
      }
      .width('100%')
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildSearchGroup() {
    Column() {
      this.buildGroupTitle($r('app.string.settings_search_group'))

      Column({ space: AppSpace.Sm }) {
        Text($r('app.string.settings_search_concurrency'))
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
        if (this.searchConcurrencyLoading || this.checkingSearchMembership || this.membershipService.busy) {
          Row({ space: AppSpace.Sm }) {
            LoadingProgress().width(18).height(18).color(AppColor.Brand)
            Text($r('app.string.settings_search_loading')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
          }.width('100%')
        } else if (this.searchConcurrencyLoadFailed) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.settings_search_load_failed')).fontSize(AppFont.Caption)
              .fontColor($r('sys.color.font_secondary')).layoutWeight(1)
            Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(AppColor.Brand)
              .onClick((): void => { this.loadSearchConcurrency(this.preferencesLoadSerial); })
          }.width('100%')
        }
        Row({ space: AppSpace.Sm }) {
          ImmersiveOptionTabs({
            labels: ['3', '6', '9', '12', $r('app.string.settings_search_custom')],
            fillWidth: true,
            selected: this.searchConcurrencyCustom ? 4 : SEARCH_CONCURRENCY_OPTIONS.indexOf(this.searchConcurrency),
            onSelect: (index: number): void => {
              this.chooseSearchConcurrency(index);
            }
          }).layoutWeight(1.5)
          TextInput({ text: this.searchConcurrencyDraft, placeholder: $r('app.string.settings_search_concurrency_hint') })
            .enabled(this.membership.hasAccess)
            .type(InputType.Number).maxLength(2).layoutWeight(1).height(40)
            .onChange((value: string): void => { this.searchConcurrencyDraft = value; })
            .onSubmit((): void => { this.submitSearchConcurrency(); })
          ImmersiveActionButton({ onPress: (): void => { this.submitSearchConcurrency(); } }).layoutWeight(0.8)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .enabled(!this.isSavingSearchConcurrency && !this.searchConcurrencyLoading && !this.searchConcurrencyLoadFailed &&
          !this.checkingSearchMembership && !this.membershipService.busy)
      }
      .width('100%')
      .padding(ROW_INDENT)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(AppRadius.Lg)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildSelectItem(
    title: string,
    subtitle: Binding<string>,
    options: SelectOption[],
    selected: Binding<number>,
    onSelect: (index: number) => void,
    enabled: Binding<boolean>
  ) {
    Row({ space: AppSpace.Sm }) {
      Column({ space: 2 }) {
      Text(title).fontSize(AppFont.BodyL).fontColor($r('sys.color.font_primary')).width('100%')
      if (subtitle.value.length > 0) {
        Text(subtitle.value).fontSize(AppFont.Caption).fontColor($r('sys.color.font_tertiary')).width('100%')
      }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      ImmersiveOptionTabs({
        labels: options.map((option: SelectOption): ResourceStr => option.value),
        selected: selected.value,
        onSelect: (index: number): void => onSelect(index)
      }).enabled(enabled.value)
    }
    .width('100%').padding(ROW_INDENT)
  }

  // 多参数 Builder 的普通布尔值只保留首帧；绑定保证加载、保存及失败回滚同步到开关。
  @Builder
  buildSwitchItem(
    title: ResourceStr,
    subtitle: ResourceStr,
    isOn: Binding<boolean>,
    onChange: (isOn: boolean) => void,
    enabled: Binding<boolean>
  ) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        if (typeof subtitle !== 'string' || subtitle.length > 0) {
          Text(subtitle)
            .fontSize(AppFont.Caption)
            .fontColor($r('sys.color.font_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn.value })
        .selectedColor(AppColor.Brand)
        .enabled(enabled.value)
        .onChange((on: boolean) => onChange(on))
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
  }

  @Builder
  buildActionItem(title: ResourceStr, subtitle: ResourceStr, onAction: () => void, isClearing: boolean = false) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppFont.BodyL)
          .fontColor($r('sys.color.font_primary'))
        Text(subtitle)
          .fontSize(AppFont.Caption)
          .fontColor($r('sys.color.font_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (isClearing) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(AppColor.Brand)
      } else {
        SymbolGlyph($r('sys.symbol.trash'))
          .fontSize(18)
          .fontColor([$r('sys.color.font_tertiary')])
      }
    }
    .width('100%')
    .padding({
      left: ROW_INDENT,
      right: ROW_INDENT,
      top: AppSpace.Sm,
      bottom: AppSpace.Sm
    })
    .constraintSize({ minHeight: 56 })
    .enabled(!this.isClearingCache && !this.isClearingBookshelf && !this.isClearingDownloads)
    .opacity((this.isClearingCache || this.isClearingBookshelf || this.isClearingDownloads) ? 0.5 : 1.0)
    .onClick(() => onAction())
  }
}
