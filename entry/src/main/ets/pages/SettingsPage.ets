import { GeneralSettings } from '../model/GeneralSettings';
import { MembershipState } from '../model/MembershipState';
import { VipFeatureBadge } from '../components/VipFeatureBadge';
import { MembershipService } from '../service/MembershipService';
import { ImmersiveActionButton } from '../components/ImmersiveActionButton';
import { ImmersiveOptionTabs } from '../components/ImmersiveOptionTabs';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { Binding, UIUtils } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppTheme, AppRadius, AppSpace, AppFont, AppColor } from '../theme/Theme';
import { PreferenceService } from '../service/PreferenceService';
import { AudioService } from '../service/AudioService';
import { ChapterCacheService } from '../service/ChapterCacheService';
import { WidgetUpdater } from '../service/WidgetUpdater';
import { WindowUtils } from '../utils/WindowUtils';
import { AdaptiveLayout } from '../utils/AdaptiveLayout';
import { ReaderPage } from './ReaderPage';
import { RankingSettingsComponent } from '../components/RankingSettingsComponent';
import { AppearanceSettingsComponent } from '../components/AppearanceSettingsComponent';
import { CoverSuperResolutionService } from '../service/CoverSuperResolutionService';
import { ReaderCacheService, ReaderCacheKind, ReaderCacheUsage, ReaderCacheCleanup } from '../service/ReaderCacheService';
import { OnlineTextContentCache } from '../service/text/OnlineTextContentCache';

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

enum SettingsCacheKind { Text, Comic, Audio }

@ComponentV2
export struct SettingsPage {
  @Param navStack: NavPathStack = new NavPathStack();
  @Local generalSettings: GeneralSettings = GeneralSettings.current;
  @Local savingGeneral: boolean = false;
  @Local jianjianCompanionEnabled: boolean = false;
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
  @Local isLoaded: boolean = false;
  @Local preferencesLoadFailed: boolean = false;
  @Local searchConcurrencyLoading: boolean = true;
  @Local searchConcurrencyLoadFailed: boolean = false;
  private alive: boolean = false;
  private preferencesLoadSerial: number = 0;
  @Local coverSuperResolution: boolean = false;
  @Local isSavingCoverSuperResolution: boolean = false;
  @Local readerCacheUsage: ReaderCacheUsage = new ReaderCacheUsage();
  @Local readerCacheLoading: boolean = true;
  @Local readerCacheFailed: boolean = false;
  @Local audioCacheBytes: number = 0;
  @Local audioCacheLoading: boolean = true;
  @Local audioCacheFailed: boolean = false;
  @Local clearingCache: boolean = false;
  @Local viewportWidth: number = 0;
  @Local viewportHeight: number = 0;
  private viewportUpdateTimerId: number = -1;

  aboutToAppear(): void {
    this.alive = true;
    this.loadPrefs();
    this.loadReaderCacheUsage();
    this.loadAudioCacheUsage();
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
    // 首屏只读取本地偏好；权益由现有生命周期静默刷新，提交会员设置时才等待鉴权。
    this.loadSearchConcurrency(serial);
    try {
      const mode = await PreferenceService.getColorMode();
      const defaultTab = await PreferenceService.getDefaultTab();
      const autoPlay = await PreferenceService.getAutoPlayOnLaunch();
      const coverResolution = await PreferenceService.getStoredCoverSuperResolution();
      const focusMode = await PreferenceService.getAudioInterruptMode();
      const autoResume = await PreferenceService.getAudioAutoResume();
      const defaultPlaybackSpeed = await PreferenceService.getDefaultPlaybackSpeed();
      const preloadCount = await PreferenceService.getPreloadChapters();
      if (!this.alive || serial !== this.preferencesLoadSerial) return;
      this.currentMode = mode;
      this.jianjianCompanionEnabled = this.generalSettings.jianjianCompanionEnabled;
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
      const count = await PreferenceService.getStoredSearchConcurrency();
      if (!this.alive || serial !== this.preferencesLoadSerial) return;
      this.searchConcurrency = this.membership.confirmedInactive && !this.membership.hasAccess ? 3 : count;
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
      if (enabled && !await this.membershipService.hasCurrentEntitlement()) {
        this.coverSuperResolution = previous;
        if (this.alive) this.getUIContext().getPromptAction().showToast({ message: this.membershipService.message });
        return;
      }
      if (!this.alive) return;
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
    if (!this.isLoaded || this.isSavingPreload) return;
    const count = Number(this.preloadDraft);
    if (!/^[0-9]+$/.test(this.preloadDraft) || !Number.isInteger(count) || count < 0 || count > 50) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_preload_range') });
      return;
    }
    this.setPreloadCount(count, this.preloadCustom);
  }

  private choosePreload(index: number): void {
    if (!this.isLoaded || this.isSavingPreload || index < 0 || index >= PRELOAD_OPTIONS.length) return;
    this.preloadCustom = index === 4;
    if (!this.preloadCustom) this.preloadDraft = PRELOAD_OPTIONS[index].count.toString();
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
      this.coverSuperResolution = false;
    }
  }

  private async submitSearchConcurrency(): Promise<void> {
    if (this.isSavingSearchConcurrency || this.checkingSearchMembership) return;
    const count = Number(this.searchConcurrencyDraft);
    if (!new RegExp('^[0-9]+$').test(this.searchConcurrencyDraft) ||
      !Number.isInteger(count) || count < 1 || count > 12) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_search_concurrency_range') });
      return;
    }
    await this.setSearchConcurrency(count, this.searchConcurrencyCustom);
  }

  private async chooseSearchConcurrency(index: number): Promise<void> {
    if (this.isSavingSearchConcurrency || this.checkingSearchMembership || index < 0 || index > 4) return;
    this.searchConcurrencyCustom = index === 4;
    if (!this.searchConcurrencyCustom) this.searchConcurrencyDraft = SEARCH_CONCURRENCY_OPTIONS[index].toString();
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

  private async loadReaderCacheUsage(): Promise<void> {
    this.readerCacheLoading = true;
    this.readerCacheFailed = false;
    try {
      const context = this.getUIContext().getHostContext();
      if (!context) throw new Error('Context unavailable');
      await OnlineTextContentCache.migrateStorage(context);
      const usage = await ReaderCacheService.usage();
      if (this.alive) this.readerCacheUsage = usage;
    } catch (_error) {
      if (this.alive) this.readerCacheFailed = true;
    } finally { if (this.alive) this.readerCacheLoading = false; }
  }

  private async loadAudioCacheUsage(): Promise<void> {
    this.audioCacheLoading = true;
    this.audioCacheFailed = false;
    try {
      const bytes = await ChapterCacheService.getInstance().getCacheUsage();
      if (this.alive) this.audioCacheBytes = bytes;
    } catch (_error) {
      if (this.alive) this.audioCacheFailed = true;
    } finally { if (this.alive) this.audioCacheLoading = false; }
  }

  private cacheSize(bytes: number): string {
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KiB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GiB`;
  }

  private cacheTitle(kind: SettingsCacheKind): ResourceStr {
    if (kind === SettingsCacheKind.Audio) return $r('app.string.settings_audio_cache_title');
    return kind === SettingsCacheKind.Text ? $r('app.string.settings_text_cache_title') : $r('app.string.settings_comic_cache_title');
  }

  private cacheLoading(kind: SettingsCacheKind): boolean {
    return kind === SettingsCacheKind.Audio ? this.audioCacheLoading : this.readerCacheLoading;
  }

  private cacheFailed(kind: SettingsCacheKind): boolean {
    return kind === SettingsCacheKind.Audio ? this.audioCacheFailed : this.readerCacheFailed;
  }

  private cacheSummary(kind: SettingsCacheKind): ResourceStr {
    if (this.cacheLoading(kind)) return $r('app.string.settings_reader_cache_loading');
    if (this.cacheFailed(kind)) return $r('app.string.settings_reader_cache_unavailable');
    if (kind === SettingsCacheKind.Audio) return $r('app.string.settings_reader_cache_summary',
      this.cacheSize(this.audioCacheBytes), this.cacheSize(ChapterCacheService.CACHE_LIMIT));
    return $r('app.string.settings_reader_cache_summary',
      this.cacheSize(kind === SettingsCacheKind.Text ? this.readerCacheUsage.textBytes : this.readerCacheUsage.comicBytes),
      this.cacheSize(kind === SettingsCacheKind.Text ? ReaderCacheService.TEXT_LIMIT : ReaderCacheService.COMIC_LIMIT));
  }

  private async refreshCacheUsage(kind: SettingsCacheKind): Promise<void> {
    if (kind === SettingsCacheKind.Audio) await this.loadAudioCacheUsage();
    else await this.loadReaderCacheUsage();
  }

  private async clearCache(kind: SettingsCacheKind): Promise<void> {
    if (this.clearingCache || this.cacheLoading(kind)) return;
    if (this.cacheFailed(kind)) { await this.refreshCacheUsage(kind); return; }
    this.clearingCache = true;
    try {
      const prompt = this.getUIContext().getPromptAction();
      let choiceIndex: number = -1;
      try {
        const choice = await prompt.showDialog({
          title: this.cacheTitle(kind),
          message: kind === SettingsCacheKind.Audio ? $r('app.string.settings_audio_cache_confirm') : $r('app.string.settings_reader_cache_confirm'),
          buttons: [{ text: $r('app.string.common_cancel'), color: AppTheme.TextSecondary },
            { text: $r('app.string.settings_reader_cache_clear'), color: AppColor.Brand }]
        });
        choiceIndex = choice.index;
      } catch (_dialogError) { return; }
      if (choiceIndex !== 1 || !this.alive) return;
      let result: ReaderCacheCleanup = new ReaderCacheCleanup();
      if (kind === SettingsCacheKind.Audio) {
        const audioResult = await ChapterCacheService.getInstance().clearAllCache();
        result.releasedBytes = audioResult.releasedBytes;
        result.protectedCount = audioResult.protectedCount;
        result.failed = audioResult.failed;
      } else {
        const context = this.getUIContext().getHostContext();
        if (!context) throw new Error('Context unavailable');
        result = kind === SettingsCacheKind.Text ? await OnlineTextContentCache.clear(context) :
          await ReaderCacheService.clear(ReaderCacheKind.Comic);
        if (kind === SettingsCacheKind.Text) ReaderPage.clearTextContentCache();
      }
      if (!this.alive) return;
      await this.refreshCacheUsage(kind);
      if (this.alive) {
        try {
          prompt.showToast({ message: $r('app.string.settings_reader_cache_result',
            this.cacheSize(result.releasedBytes), result.protectedCount, result.failed) });
        } catch (_toastError) { /* 占用已刷新，提示失败不改变清理结果。 */ }
      }
    } catch (_error) {
      if (this.alive) {
        await this.refreshCacheUsage(kind);
        if (this.alive) this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_reader_cache_clear_failed') });
      }
    } finally { if (this.alive) this.clearingCache = false; }
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
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).layoutWeight(1)
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
    .backgroundColor(AppTheme.SettingsBackground)
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

  private async setSwipeSwitchTabs(enabled: boolean): Promise<void> {
    if (!this.isLoaded || this.savingGeneral || enabled === this.generalSettings.swipeSwitchTabs) return;
    this.savingGeneral = true;
    try { await PreferenceService.setSwipeSwitchTabs(enabled); }
    catch (_error) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
    } finally { this.savingGeneral = false; }
  }

  private async setJianjianCompanionEnabled(enabled: boolean): Promise<void> {
    if (!this.isLoaded || this.savingGeneral || enabled === this.jianjianCompanionEnabled) return;
    const previous: boolean = this.jianjianCompanionEnabled;
    this.savingGeneral = true;
    this.jianjianCompanionEnabled = enabled;
    try {
      await PreferenceService.setJianjianCompanionEnabled(enabled);
    } catch (_error) {
      this.jianjianCompanionEnabled = previous;
      if (this.alive) {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.settings_save_failed') });
      }
    } finally {
      this.savingGeneral = false;
    }
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
        .backgroundColor(AppTheme.Surface).borderRadius(AppRadius.Lg)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildHeader() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(24)
        .fontColor([AppTheme.TextPrimary])
        .onClick(() => this.navStack.pop())
      Text('设置')
        .fontSize(AppFont.TitleL)
        .fontColor(AppTheme.TextPrimary)
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
      .fontColor(AppTheme.TextTertiary)
      .padding({ left: AppSpace.Sm, bottom: AppSpace.Xs })
  }

  @Builder
  buildDivider() {
    Divider()
      .strokeWidth(0.5)
      .color(AppTheme.Divider)
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
              .fontColor(AppTheme.TextPrimary)
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
          $r('app.string.settings_jianjian_companion'),
          $r('app.string.settings_jianjian_companion_desc'),
          UIUtils.makeBinding<boolean>(() => this.jianjianCompanionEnabled),
          (enabled: boolean): void => { this.setJianjianCompanionEnabled(enabled); },
          UIUtils.makeBinding<boolean>(() => this.isLoaded && !this.savingGeneral),
          false,
          true
        )
        this.buildDivider()
        this.buildSwitchItem(
          $r('app.string.settings_swipe_switch_tabs'),
          $r('app.string.settings_swipe_switch_tabs_desc'),
          UIUtils.makeBinding<boolean>(() => this.generalSettings.swipeSwitchTabs),
          (enabled: boolean): void => { this.setSwipeSwitchTabs(enabled); },
          UIUtils.makeBinding<boolean>(() => this.isLoaded && !this.savingGeneral)
        )
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
            this.isLoaded && !this.isSavingCoverSuperResolution && CoverSuperResolutionService.supported()),
          true
        )
      }
      .width('100%')
      .backgroundColor(AppTheme.Surface)
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
      .backgroundColor(AppTheme.Surface)
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
              .fontColor(AppTheme.TextPrimary).layoutWeight(1)
            Text(this.defaultPlaybackSpeedDraft.toFixed(2) + 'x')
              .fontSize(AppFont.BodyL).fontColor(AppColor.Brand)
          }.width('100%')
          Text($r('app.string.settings_default_playback_speed_desc'))
            .fontSize(AppFont.Caption).fontColor(AppTheme.TextSecondary).width('100%')
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
            .fontColor(AppTheme.TextPrimary).width('100%')
          Row({ space: AppSpace.Sm }) {
          ImmersiveOptionTabs({
            labels: PRELOAD_OPTIONS.map((opt: PreloadOption): ResourceStr => opt.count < 0 ? $r('app.string.settings_preload_custom_tab') : opt.label),
            fillWidth: true,
            selected: this.preloadCustom ? 4 : PRELOAD_OPTIONS.findIndex((opt: PreloadOption): boolean => opt.count === Number(this.preloadDraft)),
            onSelect: (index: number): void => { this.choosePreload(index); }
          }).layoutWeight(1.5)
            TextInput({ text: this.preloadDraft, placeholder: $r('app.string.settings_preload_input_hint') })
              .type(InputType.Number).maxLength(2).layoutWeight(1).height(40)
              .onChange((value: string): void => { this.preloadDraft = value; this.preloadCustom = true; })
            ImmersiveActionButton({ onPress: (): void => this.submitPreload() }).layoutWeight(0.8)
          }.width('100%').alignItems(VerticalAlign.Center)
          .enabled(this.isLoaded && !this.isSavingPreload)
        }.width('100%').padding(ROW_INDENT)

        this.buildDivider()

        this.buildCacheItem(SettingsCacheKind.Text)

        this.buildDivider()

        this.buildCacheItem(SettingsCacheKind.Comic)

        this.buildDivider()

        this.buildCacheItem(SettingsCacheKind.Audio)

      }
      .width('100%')
      .backgroundColor(AppTheme.Surface)
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
        Row({ space: AppSpace.Sm }) {
          Text($r('app.string.settings_search_concurrency'))
            .fontSize(AppFont.BodyL)
            .fontColor(AppTheme.TextPrimary)
            .flexShrink(1)
          if (MembershipState.featureEnabled) {
            VipFeatureBadge()
          }
        }.width('100%')
        if (MembershipState.featureEnabled) {
          Text($r('app.string.settings_search_concurrency_membership_hint'))
            .fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextSecondary)
            .width('100%')
        }
        if (this.searchConcurrencyLoadFailed) {
          Row({ space: AppSpace.Sm }) {
            Text($r('app.string.settings_search_load_failed')).fontSize(AppFont.Caption)
              .fontColor(AppTheme.TextSecondary).layoutWeight(1)
            Button($r('app.string.common_retry'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .fontColor(AppColor.Brand)
              .onClick((): void => { this.loadSearchConcurrency(this.preferencesLoadSerial); })
          }.width('100%')
        }
        Row({ space: AppSpace.Sm }) {
          ImmersiveOptionTabs({
            labels: ['3', '6', '9', '12', $r('app.string.settings_search_custom')],
            fillWidth: true,
            selected: this.searchConcurrencyCustom ? 4 : SEARCH_CONCURRENCY_OPTIONS.indexOf(Number(this.searchConcurrencyDraft)),
            onSelect: (index: number): void => {
              this.chooseSearchConcurrency(index);
            }
          }).layoutWeight(1.5)
          TextInput({ text: this.searchConcurrencyDraft, placeholder: $r('app.string.settings_search_concurrency_hint') })
            .type(InputType.Number).maxLength(2).layoutWeight(1).height(40)
            .onChange((value: string): void => {
              this.searchConcurrencyDraft = value;
              this.searchConcurrencyCustom = true;
            })
          ImmersiveActionButton({ onPress: (): void => { this.submitSearchConcurrency(); } }).layoutWeight(0.8)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .enabled(!this.isSavingSearchConcurrency && !this.searchConcurrencyLoading && !this.searchConcurrencyLoadFailed &&
          !this.checkingSearchMembership)
      }
      .width('100%')
      .padding(ROW_INDENT)
      .backgroundColor(AppTheme.Surface)
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
      Text(title).fontSize(AppFont.BodyL).fontColor(AppTheme.TextPrimary).width('100%')
      if (subtitle.value.length > 0) {
        Text(subtitle.value).fontSize(AppFont.Caption).fontColor(AppTheme.TextTertiary).width('100%')
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
    enabled: Binding<boolean>,
    vipFeature: boolean = false,
    trialFeature: boolean = false
  ) {
    Row() {
      Column({ space: 2 }) {
        Row({ space: AppSpace.Sm }) {
          Text(title)
            .fontSize(AppFont.BodyL)
            .fontColor(AppTheme.TextPrimary)
            .flexShrink(1)
          if (vipFeature && MembershipState.featureEnabled) {
            VipFeatureBadge()
          }
          if (trialFeature) {
            Text($r('app.string.settings_limited_trial'))
              .fontSize(AppFont.Caption).fontColor(AppColor.Brand).flexShrink(0)
          }
        }.width('100%')
        if (typeof subtitle !== 'string' || subtitle.length > 0) {
          Text(subtitle)
            .fontSize(AppFont.Caption)
            .fontColor(AppTheme.TextTertiary)
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
  buildCacheItem(kind: SettingsCacheKind) {
    Row() {
      Column({ space: 2 }) {
        Text(this.cacheTitle(kind))
          .fontSize(AppFont.BodyL)
          .fontColor(AppTheme.TextPrimary)
        Text(this.cacheSummary(kind))
          .fontSize(AppFont.Caption)
          .fontColor(AppTheme.TextTertiary)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      if (this.clearingCache || this.cacheLoading(kind)) {
        LoadingProgress().width(18).height(18).color(AppColor.Brand)
      } else {
        SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor([AppTheme.TextTertiary])
      }
    }
    .width('100%')
    .padding({ left: ROW_INDENT, right: ROW_INDENT, top: AppSpace.Sm, bottom: AppSpace.Sm })
    .constraintSize({ minHeight: 56 })
    .enabled(!this.clearingCache && !this.cacheLoading(kind))
    .onClick(() => this.clearCache(kind))
  }
}
